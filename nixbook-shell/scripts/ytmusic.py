#!/usr/bin/env python3
"""nixbook-ytmusic: YouTube Music in the background, without a window.

Your library from your browser's YouTube Music session, played by mpv
(audio only, through yt-dlp), shown to the desktop as an MPRIS player
("YouTube Music (background)") and scrobbled to Last.fm. nixbook-shell's
side panel lists your playlists with it; listening along (Mesh) follows a
friend's song with it.

  nixbook-ytmusic browsers             the browsers with a YouTube login
  nixbook-ytmusic login-from-browser [BROWSER]
                                       a browser's YouTube session (its
                                       cookies) into the keyring, checked:
                                       the most recent login, or BROWSER's
                                       (Zen, Firefox, LibreWolf, Floorp,
                                       Waterfox, Mullvad Browser, Chrome,
                                       Chromium, Brave, Vivaldi, Edge, Opera,
                                       Thorium; Flatpak and Snap ones too),
                                       or the YouTube Music app's own
  nixbook-ytmusic status               signed in as whom, the player, Last.fm
  nixbook-ytmusic forget               the session out of the keyring
  nixbook-ytmusic playlists            your playlists (Liked Music first), JSON
  nixbook-ytmusic playlist ID          its songs, JSON
  nixbook-ytmusic play ID [--index N] [--shuffle]
                                       a playlist, from its song N
  nixbook-ytmusic play-tracks          {tracks, index, shuffle} on stdin
  nixbook-ytmusic play-id VIDEO [--start SECONDS]
  nixbook-ytmusic control play|pause|toggle|next|previous|stop|seek S
                       shuffle [on|off|toggle]  repeat [none|playlist|track|cycle]
  nixbook-ytmusic lastfm start|finish  Last.fm's desktop sign-in: start gives
                                       the page where you allow it (your own
                                       API key and secret as {apiKey, secret}
                                       on stdin, else the YouTube Music app's);
                                       finish, once allowed, keeps the session
  nixbook-ytmusic lastfm import|status|forget
                                       import: the YouTube Music app's
                                       (pear-desktop) own Last.fm sign-in
  nixbook-ytmusic serve                the player (the nixbook-ytmusic user
                                       service)

Secrets live in the keyring (secret-tool, service=nixbook-ytmusic, kind
session|lastfm), never in a file but the cookie file yt-dlp reads while the
player runs ($XDG_RUNTIME_DIR, 0600, removed when it stops). The player's
socket ($XDG_RUNTIME_DIR/nixbook-ytmusic/player.sock) is this user's only
(0700 directory, 0600 socket, the peer's uid checked).
"""

import concurrent.futures
import glob
import hashlib
import json
import os
import random
import re
import shutil
import socket
import sqlite3
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

APP = "nixbook-ytmusic"
SECRET_TOOL = os.environ.get("NIXBOOK_YTMUSIC_SECRET_TOOL", "secret-tool")
MPV = os.environ.get("NIXBOOK_YTMUSIC_MPV", "mpv")
YT_DLP = os.environ.get("NIXBOOK_YTMUSIC_YT_DLP", "yt-dlp")
BUS_NAME = "org.mpris.MediaPlayer2.nixbook_ytmusic"
IDENTITY = "YouTube Music (background)"
DESKTOP_ENTRY = "com.github.th-ch.youtube-music"
TRACK_PREFIX = "/nixbook/ytmusic/track/"
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
PLAYLIST_ID = re.compile(r"^[A-Za-z0-9_-]{2,64}$")
WATCH_URL = "https://music.youtube.com/watch?v={}"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/140.0.0.0 Safari/537.36")
# The player lets mpv go after this long with nothing playing.
IDLE_QUIT = float(os.environ.get("NIXBOOK_YTMUSIC_IDLE_QUIT", 30 * 60))
MAX_TRACKS = 1000
LASTFM_ROOT = "https://ws.audioscrobbler.com/2.0/"


class Error(Exception):
    pass


# -- paths ------------------------------------------------------------------
def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    d = os.path.join(base, APP)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def player_socket():
    return os.path.join(runtime_dir(), "player.sock")


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    d = os.path.join(base, APP)
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def cache_dir(*sub):
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    d = os.path.join(base, APP, *sub)
    os.makedirs(d, exist_ok=True)
    return d


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_private(path, payload):
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    os.replace(tmp, path)


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)


# -- keyring ----------------------------------------------------------------
def keyring_get(kind):
    try:
        got = subprocess.run([SECRET_TOOL, "lookup", "service", APP, "kind", kind], capture_output=True,
                             text=True, timeout=15, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if got.returncode != 0 or not got.stdout.strip():
        return None
    try:
        return json.loads(got.stdout)
    except ValueError:
        return None


def keyring_set(kind, label, value):
    secret = json.dumps(value)
    try:
        stored = subprocess.run([SECRET_TOOL, "store", f"--label={label}", "service", APP, "kind", kind],
                                input=secret, text=True, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Error(f"couldn't save it in the keyring: {exc}") from None
    if stored.returncode != 0:
        raise Error("couldn't save it in the keyring: " + stored.stderr.strip()[:200])


def keyring_clear(kind):
    try:
        subprocess.run([SECRET_TOOL, "clear", "service", APP, "kind", kind], capture_output=True, timeout=15,
                       stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        pass


# -- the browser's YouTube session ------------------------------------------
# Where the browsers keep their cookies (under the home), Zen first. The
# Firefox family stores them in clear; the Chromium family encrypts them with
# a key from the keyring. (As seerr-mcp's login-from-browser, which reads one
# site's session cookie; here every cookie of YouTube's, one login's set.)
FIREFOX_DBS = [("Zen", ".zen/*/cookies.sqlite"), ("Zen", ".config/zen/*/cookies.sqlite"),
               ("Zen", ".var/app/app.zen_browser.zen/.zen/*/cookies.sqlite"),
               ("Firefox", ".mozilla/firefox/*/cookies.sqlite"),
               ("Firefox", ".config/mozilla/firefox/*/cookies.sqlite"),
               ("Firefox", ".var/app/org.mozilla.firefox/.mozilla/firefox/*/cookies.sqlite"),
               ("Firefox", "snap/firefox/common/.mozilla/firefox/*/cookies.sqlite"),
               ("LibreWolf", ".librewolf/*/cookies.sqlite"),
               ("LibreWolf", ".var/app/io.gitlab.librewolf-community/.librewolf/*/cookies.sqlite"),
               ("Floorp", ".floorp/*/cookies.sqlite"), ("Waterfox", ".waterfox/*/cookies.sqlite"),
               ("Mullvad Browser", ".mullvad-browser/*/cookies.sqlite")]
CHROMIUM_DIRS = [("Chrome", ".config/google-chrome", ["chrome"]),
                 ("Chrome Beta", ".config/google-chrome-beta", ["chrome"]),
                 ("Chrome Dev", ".config/google-chrome-unstable", ["chrome"]),
                 ("Chrome", ".var/app/com.google.Chrome/config/google-chrome", ["chrome"]),
                 ("Chromium", ".config/chromium", ["chromium"]),
                 ("Chromium", ".var/app/org.chromium.Chromium/config/chromium", ["chromium"]),
                 ("Chromium", "snap/chromium/common/chromium", ["chromium"]),
                 ("Brave", ".config/BraveSoftware/Brave-Browser", ["brave"]),
                 ("Brave", ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser", ["brave"]),
                 ("Vivaldi", ".config/vivaldi", ["chrome", "vivaldi"]),
                 ("Edge", ".config/microsoft-edge", ["chromium", "microsoft-edge"]),
                 ("Opera", ".config/opera", ["chromium", "opera"]),
                 ("Thorium", ".config/thorium", ["chromium", "thorium"])]
# Electron apps keep one profile at the top of their folder: the YouTube Music
# app (pear-desktop) is signed in to YouTube already (and on a desktop whose
# browser sends music.youtube.com links to the app, it's where a login made
# from a link lands).
ELECTRON_DIRS = [("YouTube Music app", ".config/YouTube Music", ["chromium", "YouTube Music", "pear-desktop"])]
CHROME_EPOCH_US = 11644473600 * 1_000_000
YOUTUBE_HOSTS = (".youtube.com", "youtube.com", "music.youtube.com", ".music.youtube.com")
# The cookie that says a Google login is there, and the one ytmusicapi signs
# its requests with.
LOGIN_COOKIES = ("__Secure-3PAPISID", "SAPISID")


def cookie_dbs():
    """[(path, browser, keyring apps)]; NIXBOOK_YTMUSIC_COOKIE_DBS (":"-separated)
    instead in tests."""
    if os.environ.get("NIXBOOK_YTMUSIC_COOKIE_DBS"):
        return [(p, "", []) for p in os.environ["NIXBOOK_YTMUSIC_COOKIE_DBS"].split(":") if p]
    home = os.path.expanduser("~")
    found = []
    for name, pattern in FIREFOX_DBS:
        found += [(p, name, []) for p in sorted(glob.glob(os.path.join(home, pattern)),
                                                key=lambda p: -os.path.getmtime(p))]
    for name, base, apps in CHROMIUM_DIRS:
        paths = glob.glob(os.path.join(home, base, "*", "Network", "Cookies")) + \
            glob.glob(os.path.join(home, base, "*", "Cookies"))
        found += [(p, name, apps) for p in sorted(paths, key=lambda p: -os.path.getmtime(p))]
    for name, base, apps in ELECTRON_DIRS:
        for rel in ("Network/Cookies", "Cookies"):
            path = os.path.join(home, base, rel)
            if os.path.exists(path):
                found.append((path, name, apps))
                break
    return found


def _chromium_key(password):
    return hashlib.pbkdf2_hmac("sha1", password.encode(), b"saltysalt", 1, 16)


def chromium_decrypt(blob, host_key, apps):
    """A Chromium cookie's value (v10: the "peanuts" key; v11: the keyring's
    password). AES-128-CBC through openssl (no Python crypto in the stdlib)."""
    blob = bytes(blob or b"")
    if blob[:3] not in (b"v10", b"v11"):
        return None
    keys = [_chromium_key("peanuts")] if blob[:3] == b"v10" else []
    for app in apps:
        try:
            got = subprocess.run([SECRET_TOOL, "lookup", "application", app], capture_output=True,
                                 text=True, timeout=15, stdin=subprocess.DEVNULL)
            if got.returncode == 0 and got.stdout.strip():
                keys.append(_chromium_key(got.stdout.strip()))
        except (OSError, subprocess.TimeoutExpired):
            pass
    keys.append(_chromium_key(""))
    for key in keys:
        try:
            got = subprocess.run(["openssl", "enc", "-d", "-aes-128-cbc", "-K", key.hex(), "-iv", "20" * 16],
                                 input=blob[3:], capture_output=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if got.returncode != 0:
            continue
        plain = got.stdout
        if len(plain) > 32 and plain[:32] == hashlib.sha256(host_key.encode()).digest():
            plain = plain[32:]
        try:
            text = plain.decode("ascii")
        except UnicodeDecodeError:
            continue
        if text.isprintable():
            return text
    return None


def browser_logins():
    """YouTube's cookies of each browser login (a profile, and in Zen/Firefox
    a container), the most recently used Google login first:
    [(cookie dict, browser)]. Each file is read from a private copy."""
    groups = []
    with tempfile.TemporaryDirectory(prefix="nixbook-ytmusic-") as tmp:
        os.chmod(tmp, 0o700)
        for i, (db, browser, apps) in enumerate(cookie_dbs()):
            copy = os.path.join(tmp, f"{i}.sqlite")
            try:
                shutil.copyfile(db, copy)
                for extra in ("-wal", "-journal"):
                    if os.path.exists(db + extra):
                        shutil.copyfile(db + extra, copy + extra)
                con = sqlite3.connect(copy)
                tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
                marks = ",".join("?" * len(YOUTUBE_HOSTS))
                by = {}
                if "moz_cookies" in tables:
                    rows = con.execute(f"SELECT name, value, lastAccessed, originAttributes, expiry FROM moz_cookies "
                                       f"WHERE host IN ({marks})", YOUTUBE_HOSTS).fetchall()
                    for name, value, used, origin, expiry in rows:
                        g = by.setdefault(origin or "", {"cookies": {}, "used": 0})
                        if value and (not expiry or expiry > time.time()):
                            g["cookies"][name] = value
                            if name in LOGIN_COOKIES:
                                g["used"] = max(g["used"], used or 0)
                elif "cookies" in tables:
                    rows = con.execute(f"SELECT name, value, encrypted_value, host_key, last_access_utc FROM cookies "
                                       f"WHERE host_key IN ({marks})", YOUTUBE_HOSTS).fetchall()
                    g = by.setdefault("", {"cookies": {}, "used": 0})
                    for name, value, blob, host_key, used in rows:
                        value = value or chromium_decrypt(blob, host_key, apps)
                        if value:
                            g["cookies"][name] = value
                            if name in LOGIN_COOKIES:
                                g["used"] = max(g["used"], (used or 0) - CHROME_EPOCH_US)
                con.close()
            except (OSError, sqlite3.Error):
                continue
            for g in by.values():
                if any(n in g["cookies"] for n in LOGIN_COOKIES):
                    groups.append((g["used"], g["cookies"], browser or "Firefox"))
    return [(c, b) for _, c, b in sorted(groups, key=lambda g: g[0], reverse=True)]


def cookie_header(cookies):
    return "; ".join(f"{k}={v}" for k, v in cookies.items())


def auth_headers(cookie):
    """ytmusicapi's browser authentication: the cookie, and an authorization
    it recomputes on every request (SAPISIDHASH from __Secure-3PAPISID)."""
    return {"user-agent": UA, "accept": "*/*", "accept-language": "en-US,en;q=0.9",
            "content-type": "application/json", "x-goog-authuser": "0",
            "x-origin": "https://music.youtube.com", "origin": "https://music.youtube.com",
            "authorization": "SAPISIDHASH 0_0", "cookie": cookie}


def session():
    got = keyring_get("session")
    return got.get("cookie") if isinstance(got, dict) and got.get("cookie") else None


def ytmusic(cookie=None, signed_in=True):
    try:
        from ytmusicapi import YTMusic
    except ImportError as exc:
        raise Error(f"ytmusicapi is missing: {exc}") from None
    if not signed_in:
        return YTMusic()
    cookie = cookie or session()
    if not cookie:
        raise Error("not signed in: Settings > Apps & accounts > YouTube Music > Use my browser's session")
    return YTMusic(auth=auth_headers(cookie))


def account_of(yt):
    try:
        info = yt.get_account_info() or {}
    except Exception as exc:  # noqa: BLE001 — ytmusicapi raises many kinds
        raise Error(f"YouTube Music refused the session: {exc}") from None
    name = info.get("accountName") or info.get("channelHandle") or ""
    if not name:
        raise Error("YouTube Music didn't say who is signed in: the session has probably ended")
    return name


def login_path():
    return os.path.join(state_dir(), "login.json")


def cmd_browsers(_args):
    """The browsers with a YouTube login (names only), the most recent first."""
    seen = []
    for _, browser in browser_logins():
        if browser not in seen:
            seen.append(browser)
    out({"browsers": seen})


def cmd_login(args):
    logins = browser_logins()
    want = " ".join(args).strip().lower()
    if want:
        logins = [lg for lg in logins if lg[1].lower() == want]
        if not logins:
            out({"error": f"no YouTube login in {' '.join(args)}: open music.youtube.com there, sign in, "
                          "then try again"}, 1)
    if not logins:
        out({"error": "no YouTube login in your browser: open music.youtube.com in Zen (or Chrome), sign in, "
                      "then try again"}, 1)
    last = ""
    for cookies, browser in logins:
        cookie = cookie_header(cookies)
        try:
            name = account_of(ytmusic(cookie))
        except Error as exc:
            last = str(exc)
            continue
        try:
            keyring_set("session", f"YouTube Music session of {name} ({APP})", {"cookie": cookie})
        except Error as exc:
            out({"error": str(exc)}, 1)
        write_private(login_path(), {"account": name, "browser": browser, "at": int(time.time())})
        out({"signedIn": True, "account": name, "browser": browser})
    out({"error": "your browser's YouTube login didn't work here (" + last + "): sign in again on "
                  "music.youtube.com, then try again"}, 1)


def cmd_forget(_args):
    keyring_clear("session")
    try:
        os.remove(login_path())
    except OSError:
        pass
    out({"signedIn": False})


def lastfm_creds():
    got = keyring_get("lastfm")
    if isinstance(got, dict) and all(got.get(k) for k in ("apiKey", "secret", "sessionKey")):
        return got
    return None


def cmd_status(_args):
    login = read_json(login_path(), {}) or {}
    signed = bool(session())
    player = ask_player({"cmd": "status"}, start=False)
    lf = lastfm_creds()
    out({"signedIn": signed, "account": login.get("account") if signed else None,
         "browser": login.get("browser") if signed else None,
         "player": player.get("result") if player.get("ok") else None,
         "lastfm": {"on": bool(lf), "user": (lf or {}).get("user")}})


# -- the library ------------------------------------------------------------
def thumb(url, size=226):
    """A picture cached by its URL ($XDG_CACHE_HOME/nixbook-ytmusic/thumbs),
    its path, or "" (none, or it couldn't be fetched)."""
    if not url or not url.startswith("https://"):
        return ""
    url = re.sub(r"=w\d+-h\d+", f"=w{size}-h{size}", url)
    path = os.path.join(cache_dir("thumbs"), hashlib.sha1(url.encode()).hexdigest()[:24] + ".jpg")
    if os.path.exists(path):
        return path
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read(4 * 1024 * 1024)
        tmp = f"{path}.{os.getpid()}.tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        return path
    except (OSError, ValueError):
        return ""


def best(thumbs):
    thumbs = [t for t in (thumbs or []) if isinstance(t, dict) and t.get("url")]
    return max(thumbs, key=lambda t: t.get("width") or 0)["url"] if thumbs else ""


def with_thumbs(items, key="thumb", size=226):
    with concurrent.futures.ThreadPoolExecutor(6) as pool:
        paths = list(pool.map(lambda it: thumb(it.pop("_art", ""), size), items))
    for it, p in zip(items, paths):
        it[key] = p
    return items


def track_of(t):
    """A song as the shell and the player know it, or None (unavailable)."""
    vid = t.get("videoId") or ""
    if not VIDEO_ID.match(vid) or t.get("isAvailable") is False:
        return None
    artists = ", ".join(a.get("name", "") for a in (t.get("artists") or []) if a.get("name"))
    album = (t.get("album") or {}).get("name", "") if isinstance(t.get("album"), dict) else ""
    return {"videoId": vid, "title": t.get("title") or "", "artist": artists, "album": album,
            "duration": int(t.get("duration_seconds") or 0), "art": best(t.get("thumbnails"))}


def cmd_playlists(_args):
    yt = ytmusic()
    try:
        raw = yt.get_library_playlists(limit=None) or []
    except Exception as exc:  # noqa: BLE001
        out({"error": f"YouTube Music didn't list your playlists: {exc}"}, 1)
    items = []
    for p in raw:
        pid = p.get("playlistId") or ""
        if not PLAYLIST_ID.match(pid):
            continue
        items.append({"id": pid, "title": p.get("title") or "", "count": p.get("count") or "",
                      "author": ", ".join(a.get("name", "") for a in (p.get("author") or []) if isinstance(a, dict)),
                      "_art": best(p.get("thumbnails"))})
    items.sort(key=lambda p: p["id"] != "LM")  # Liked Music first
    out({"playlists": with_thumbs(items)})


def playlist_tracks(pid, yt=None):
    if not PLAYLIST_ID.match(pid or ""):
        raise Error(f"not a playlist id: {pid!r}")
    yt = yt or ytmusic()
    try:
        raw = yt.get_playlist(pid, limit=MAX_TRACKS) or {}
    except Exception as exc:  # noqa: BLE001
        raise Error(f"YouTube Music didn't give that playlist: {exc}") from None
    tracks = [t for t in (track_of(t) for t in raw.get("tracks") or []) if t]
    return raw.get("title") or "", tracks


def cmd_playlist(args):
    if len(args) != 1:
        out({"error": "usage: nixbook-ytmusic playlist ID"}, 1)
    try:
        title, tracks = playlist_tracks(args[0])
    except Error as exc:
        out({"error": str(exc)}, 1)
    for t in tracks:
        t["_art"] = t["art"]
    out({"id": args[0], "title": title, "tracks": with_thumbs(tracks, size=120)})


def song(vid):
    """A song's details from its id (no sign-in needed)."""
    if not VIDEO_ID.match(vid or ""):
        raise Error(f"not a song id: {vid!r}")
    try:
        d = (ytmusic(signed_in=False).get_song(vid) or {}).get("videoDetails") or {}
    except Error:
        raise
    except Exception:  # noqa: BLE001
        d = {}
    return {"videoId": vid, "title": d.get("title") or "", "artist": d.get("author") or "", "album": "",
            "duration": int(d.get("lengthSeconds") or 0), "art": best((d.get("thumbnail") or {}).get("thumbnails"))}


# -- the player's socket, from the command line ----------------------------
def ask_player(req, start=True, timeout=30):
    path = player_socket()
    if start and not os.path.exists(path):
        subprocess.run(["systemctl", "--user", "start", APP], capture_output=True, timeout=20)
        for _ in range(50):
            if os.path.exists(path):
                break
            time.sleep(0.1)
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(timeout)
        s.connect(path)
        s.sendall(json.dumps(req).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        s.close()
        return json.loads(data or b"{}")
    except (OSError, ValueError) as exc:
        return {"ok": False, "error": f"the player isn't running ({exc})"}


def reply(r):
    out(r, 0 if r.get("ok") else 1)


def cmd_play(args):
    if not args:
        out({"error": "usage: nixbook-ytmusic play ID [--index N] [--shuffle]"}, 1)
    index = int(args[args.index("--index") + 1]) if "--index" in args else 0
    try:
        _, tracks = playlist_tracks(args[0])
    except Error as exc:
        out({"error": str(exc)}, 1)
    reply(ask_player({"cmd": "play", "tracks": tracks, "index": index, "shuffle": "--shuffle" in args,
                      "playlist": args[0]}))


def cmd_play_tracks(_args):
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        out({"error": "a JSON object on stdin: {tracks, index, shuffle}"}, 1)
    tracks = [t for t in (req.get("tracks") or []) if isinstance(t, dict) and VIDEO_ID.match(t.get("videoId") or "")]
    reply(ask_player({"cmd": "play", "tracks": tracks[:MAX_TRACKS], "index": int(req.get("index") or 0),
                      "shuffle": bool(req.get("shuffle")), "playlist": str(req.get("playlist") or "")}))


def cmd_play_id(args):
    if not args:
        out({"error": "usage: nixbook-ytmusic play-id VIDEO [--start SECONDS]"}, 1)
    start = float(args[args.index("--start") + 1]) if "--start" in args else 0.0
    reply(ask_player({"cmd": "playId", "videoId": args[0], "start": start}))


def cmd_control(args):
    if not args:
        out({"error": "usage: nixbook-ytmusic control play|pause|toggle|next|previous|stop|seek S|"
                      "shuffle [on|off|toggle]|repeat [none|playlist|track|cycle]"}, 1)
    req = {"cmd": "control", "action": args[0]}
    if args[0] == "seek" and len(args) > 1:
        req["value"] = float(args[1])
    elif args[0] in ("shuffle", "repeat") and len(args) > 1:
        req["value"] = args[1]
    reply(ask_player(req, start=args[0] in ("play", "toggle")))


# -- Last.fm ----------------------------------------------------------------
def lastfm_sign(params, secret):
    text = "".join(f"{k}{params[k]}" for k in sorted(params) if k not in ("format", "callback")) + secret
    return hashlib.md5(text.encode()).hexdigest()


def lastfm_call(creds, method, **params):
    params = {k: str(v) for k, v in params.items() if v not in (None, "")}
    params.update(method=method, api_key=creds["apiKey"])
    if creds.get("sessionKey"):
        params["sk"] = creds["sessionKey"]
    params["api_sig"] = lastfm_sign(params, creds["secret"])
    params["format"] = "json"
    root = creds.get("apiRoot") or LASTFM_ROOT
    req = urllib.request.Request(root, data=urllib.parse.urlencode(params).encode(),
                                 headers={"User-Agent": f"{APP}/1"})
    with urllib.request.urlopen(req, timeout=20) as r:
        answer = json.loads(r.read() or b"{}")
    if answer.get("error"):
        raise Error(f"Last.fm: {answer.get('message') or answer['error']}")
    return answer


def pear_config():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return read_json(os.path.join(base, "YouTube Music", "config.json"), {}) or {}


LASTFM_AUTH = "https://www.last.fm/api/auth/?api_key={}&token={}"
LASTFM_NEW_KEY = "https://www.last.fm/api/account/create"


def pear_lastfm():
    return (((pear_config().get("plugins") or {}).get("scrobbler") or {}).get("scrobblers") or {}).get("lastfm") or {}


def api_pair(req):
    """The API key and secret a sign-in uses: the ones given (the user's own
    Last.fm API account), else the YouTube Music app's."""
    key, secret = str(req.get("apiKey") or "").strip(), str(req.get("secret") or "").strip()
    if not (key and secret):
        lf = pear_lastfm()
        key, secret = str(lf.get("apiKey") or ""), str(lf.get("secret") or "")
    if not re.fullmatch(r"[0-9a-f]{32}", key) or not re.fullmatch(r"[0-9a-f]{32}", secret):
        raise Error("a Last.fm API key and secret are needed (32 hex characters each): create them at "
                    f"{LASTFM_NEW_KEY} (free), or sign the YouTube Music app in to Last.fm")
    return {"apiKey": key, "secret": secret, "apiRoot": LASTFM_ROOT}


def stdin_json():
    if sys.stdin.isatty():
        return {}
    try:
        got = json.loads(sys.stdin.read() or "{}")
        return got if isinstance(got, dict) else {}
    except ValueError:
        return {}


def cmd_lastfm(args):
    what = args[0] if args else "status"
    if what == "start":
        # Step 1 of the desktop sign-in: a token, and the page where the user
        # allows it ({apiKey, secret} on stdin, else the app's).
        try:
            pair = api_pair(stdin_json())
            token = lastfm_call(pair, "auth.getToken").get("token") or ""
        except (Error, OSError, ValueError) as exc:
            out({"error": str(exc)}, 1)
        if not re.fullmatch(r"[A-Za-z0-9]{16,64}", token):
            out({"error": "Last.fm gave no sign-in token"}, 1)
        pending = os.path.join(runtime_dir(), "lastfm-pending.json")
        write_private(pending, {**pair, "token": token, "at": time.time()})
        out({"url": LASTFM_AUTH.format(pair["apiKey"], token)})
    if what == "finish":
        # Step 2, once the user allowed it on that page: the session.
        pending = os.path.join(runtime_dir(), "lastfm-pending.json")
        p = read_json(pending, {}) or {}
        if not p.get("token") or time.time() - p.get("at", 0) > 3600:
            out({"error": "no sign-in under way: start it again"}, 1)
        try:
            got = lastfm_call({k: p[k] for k in ("apiKey", "secret", "apiRoot")}, "auth.getSession",
                              token=p["token"]).get("session") or {}
        except (Error, OSError, ValueError) as exc:
            out({"error": f"{exc} (allow nixbook on the Last.fm page first, then try again)"}, 1)
        if not got.get("key"):
            out({"error": "Last.fm gave no session: allow it on its page, then try again"}, 1)
        creds = {"apiKey": p["apiKey"], "secret": p["secret"], "apiRoot": LASTFM_ROOT,
                 "sessionKey": got["key"], "user": got.get("name") or ""}
        try:
            keyring_set("lastfm", f"Last.fm session of {creds['user']} ({APP})", creds)
        except Error as exc:
            out({"error": str(exc)}, 1)
        os.remove(pending)
        ask_player({"cmd": "reload"}, start=False)
        out({"on": True, "user": creds["user"]})
    if what == "import":
        lf = pear_lastfm()
        creds = {k: lf.get(k) for k in ("apiKey", "secret", "sessionKey")}
        if not all(creds.values()):
            out({"error": "the YouTube Music app isn't signed in to Last.fm: its Plugins > Scrobbler > Last.fm, "
                          "then try again"}, 1)
        root = lf.get("apiRoot") or LASTFM_ROOT
        creds["apiRoot"] = root if root.startswith("https://") else LASTFM_ROOT
        try:
            user = lastfm_call(creds, "user.getInfo").get("user", {}).get("name")
        except (Error, OSError, ValueError) as exc:
            out({"error": f"Last.fm refused that sign-in: {exc}"}, 1)
        creds["user"] = user or ""
        try:
            keyring_set("lastfm", f"Last.fm session of {user} ({APP})", creds)
        except Error as exc:
            out({"error": str(exc)}, 1)
        ask_player({"cmd": "reload"}, start=False)
        out({"on": True, "user": user})
    if what == "forget":
        keyring_clear("lastfm")
        ask_player({"cmd": "reload"}, start=False)
        out({"on": False})
    lf = lastfm_creds()
    app = pear_lastfm()
    out({"on": bool(lf), "user": (lf or {}).get("user"),
         "fromApp": bool(app.get("sessionKey") and app.get("apiKey")), "appKey": bool(app.get("apiKey")),
         "newKey": LASTFM_NEW_KEY})


# -- the player ---------------------------------------------------------------
class Mpv:
    """mpv driven over its JSON IPC: started when something plays, audio
    only. Events go to on_event (from the reader thread). yt-dlp gets the
    YouTube session only to retry a song that failed without it (with it,
    yt-dlp picks a client whose streams answered 403: measured on a signed-in
    Zen session, 2026-11-11), so the session stays in the keyring for most
    songs."""

    def __init__(self, on_event, cookies_file=None):
        self.on_event, self.cookies_file = on_event, cookies_file
        self.proc, self.sock, self.lock = None, None, threading.Lock()
        self.waiting, self.next_id = {}, 1
        self.path = os.path.join(runtime_dir(), "mpv.sock")

    def running(self):
        return self.proc is not None and self.proc.poll() is None and self.sock is not None

    def start(self):
        if self.running():
            return
        self.stop()
        try:
            os.remove(self.path)
        except OSError:
            pass
        argv = [MPV, "--idle=yes", "--no-video", "--force-window=no", "--no-terminal", "--no-config",
                "--input-ipc-server=" + self.path, "--ytdl-format=bestaudio/best", "--cache=yes",
                f"--script-opts=ytdl_hook-ytdl_path={YT_DLP}", "--audio-display=no", "--keep-open=no"]
        self.proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(100):
            if os.path.exists(self.path):
                try:
                    s = socket.socket(socket.AF_UNIX)
                    s.connect(self.path)
                    self.sock = s
                    break
                except OSError:
                    pass
            if self.proc.poll() is not None:
                break
            time.sleep(0.05)
        if not self.sock:
            self.stop()
            raise Error("mpv didn't start")
        threading.Thread(target=self._read, args=(self.sock,), daemon=True).start()
        for prop in ("pause", "idle-active"):
            self.command("observe_property", 1, prop)

    def _read(self, s):
        buf = b""
        while True:
            try:
                chunk = s.recv(65536)
            except OSError:
                chunk = b""
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if "request_id" in msg and msg["request_id"] in self.waiting:
                    slot = self.waiting.pop(msg["request_id"])
                    slot["reply"] = msg
                    slot["event"].set()
                elif "event" in msg:
                    self.on_event(msg)
        self.on_event({"event": "mpv-gone"})

    def command(self, *args, timeout=10):
        if not self.sock:
            return None
        with self.lock:
            rid = self.next_id
            self.next_id += 1
            slot = {"event": threading.Event(), "reply": None}
            self.waiting[rid] = slot
            try:
                self.sock.sendall(json.dumps({"command": list(args), "request_id": rid}).encode() + b"\n")
            except OSError:
                self.waiting.pop(rid, None)
                return None
        slot["event"].wait(timeout)
        r = slot["reply"] or {}
        return r.get("data") if r.get("error") == "success" else None

    def stop(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None


class Scrobbler:
    """Last.fm's rules: now playing when a song starts; a scrobble once it
    has played half its length or 4 minutes, for songs over 30 seconds."""

    def __init__(self):
        self.creds = lastfm_creds()
        self.track, self.started, self.played, self.done = None, 0, 0.0, False

    def begin(self, track):
        self.track, self.started, self.played, self.done = track, int(time.time()), 0.0, False
        if self.creds and track.get("title"):
            self._send("track.updateNowPlaying", track, duration=track.get("duration") or None)

    def tick(self, seconds):
        t = self.track
        if not t or self.done or not self.creds:
            return
        self.played += seconds
        dur = t.get("duration") or 0
        if dur > 30 and self.played >= min(dur / 2, 240):
            self.done = True
            self._send("track.scrobble", t, timestamp=self.started, duration=dur)

    def _send(self, method, t, **extra):
        creds = self.creds

        def go():
            try:
                lastfm_call(creds, method, artist=(t.get("artist") or "").split(", ")[0], track=t.get("title"),
                            album=t.get("album"), **extra)
            except (Error, OSError, ValueError) as exc:
                print(f"{APP}: {method}: {exc}", file=sys.stderr, flush=True)
        threading.Thread(target=go, daemon=True).start()


def write_cookies_file(cookie):
    """The session as a Netscape cookie file for yt-dlp (0600, runtime dir)."""
    path = os.path.join(runtime_dir(), "cookies.txt")
    lines = ["# Netscape HTTP Cookie File"]
    for part in cookie.split("; "):
        if "=" in part:
            k, v = part.split("=", 1)
            lines.append("\t".join([".youtube.com", "TRUE", "/", "TRUE", "0", k, v]))
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path


def peer_uid(conn):
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", creds)[1]


def serve(_args):
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    ROOT, PLAYER, PROPS = "org.mpris.MediaPlayer2", "org.mpris.MediaPlayer2.Player", "org.freedesktop.DBus.Properties"

    def on_main(fn, *args):
        """Runs fn on the main loop and returns its result (from a thread)."""
        done, box = threading.Event(), {}

        def run():
            try:
                box["r"] = fn(*args)
            except Exception as exc:  # noqa: BLE001 — answered to the client
                box["e"] = exc
            done.set()
            return False
        GLib.idle_add(run)
        done.wait(60)
        if "e" in box:
            raise box["e"]
        return box.get("r")

    class Player(dbus.service.Object):
        def __init__(self):
            super().__init__(bus, "/org/mpris/MediaPlayer2")
            self.queue, self.index, self.playlist = [], -1, ""
            self.paused, self.loading, self.owned, self.attempt = True, False, False, "ytdl"
            self.streams = {}  # videoId → (its resolved stream, until)
            # Shuffle (the songs still to come in a random order; the
            # playlist's own order kept to go back to) and repeat:
            # None | Playlist | Track (MPRIS's LoopStatus).
            self.shuffle, self.loop, self.order = False, "None", []
            self.base, self.at = 0.0, time.monotonic()  # position = base (+ since `at` while playing)
            self.volume, self.errors, self.idle_since = 1.0, 0, time.monotonic()
            cookie = session()
            self.mpv = Mpv(lambda ev: GLib.idle_add(self.mpv_event, ev),
                           write_cookies_file(cookie) if cookie else None)
            self.scrobbler = Scrobbler()
            GLib.timeout_add_seconds(2, self.tick)

        # -- state
        def track(self):
            return self.queue[self.index] if 0 <= self.index < len(self.queue) else None

        def position(self):
            pos = self.mpv.command("get_property", "time-pos", timeout=2) if self.mpv.running() else None
            if isinstance(pos, (int, float)):
                return float(pos)
            # Still loading (or mpv gone): where it starts, or stopped.
            return self.base + (0 if self.paused or self.loading else time.monotonic() - self.at)

        def status(self):
            t = self.track()
            if not t:
                return "Stopped"
            return "Paused" if self.paused else "Playing"

        def own(self, want):
            if want and not self.owned:
                bus.request_name(BUS_NAME)
                self.owned = True
            elif not want and self.owned:
                bus.release_name(BUS_NAME)
                self.owned = False

        def metadata(self):
            t = self.track()
            if not t:
                return dbus.Dictionary({}, signature="sv")
            path = TRACK_PREFIX + "".join(c if c.isalnum() else f"_{ord(c):02X}" for c in t["videoId"])
            md = {"mpris:trackid": dbus.ObjectPath(path), "xesam:title": t.get("title") or t["videoId"],
                  "xesam:url": WATCH_URL.format(t["videoId"])}
            if t.get("artist"):
                md["xesam:artist"] = dbus.Array([a for a in t["artist"].split(", ") if a], signature="s")
            if t.get("album"):
                md["xesam:album"] = t["album"]
            if t.get("duration"):
                md["mpris:length"] = dbus.Int64(int(t["duration"] * 1e6))
            if t.get("art"):
                md["mpris:artUrl"] = t["art"]
            return dbus.Dictionary(md, signature="sv")

        def changed(self, *keys):
            if not self.owned:
                return
            props = self.props(PLAYER)
            self.PropertiesChanged(PLAYER, dbus.Dictionary({k: props[k] for k in keys}, signature="sv"),
                                   dbus.Array([], signature="s"))

        def summary(self):
            t = self.track()
            return {"status": self.status(), "track": t, "index": self.index, "count": len(self.queue),
                    "playlist": self.playlist, "position": round(self.position(), 1) if t else 0,
                    "loading": self.loading, "shuffle": self.shuffle, "loop": self.loop,
                    "lastfm": bool(self.scrobbler.creds)}

        # -- playing
        # How a song is opened, tried in this order when one fails: its
        # stream already resolved while the previous song played ("direct":
        # no pause between songs; yt-dlp takes 5-8 s), yt-dlp through mpv,
        # yt-dlp with the account's session.
        ATTEMPTS = ("direct", "ytdl", "signed")

        def prefetch(self, index):
            if not 0 <= index < len(self.queue):
                return
            vid = self.queue[index]["videoId"]
            got = self.streams.get(vid)
            if got and got[1] > time.monotonic():
                return

            def run():
                try:
                    r = subprocess.run([YT_DLP, "-f", "bestaudio/best", "-g", "--no-playlist", "--no-warnings",
                                        WATCH_URL.format(vid)], capture_output=True, text=True, timeout=45,
                                       stdin=subprocess.DEVNULL)
                except (OSError, subprocess.TimeoutExpired):
                    return
                url = (r.stdout.strip().splitlines() or [""])[0]
                if r.returncode == 0 and url.startswith("https://"):
                    # Its links last 6 hours: kept 2.
                    GLib.idle_add(lambda: self.streams.__setitem__(vid, (url, time.monotonic() + 7200)) and False)
            threading.Thread(target=run, daemon=True).start()

        def load(self, index, start=0.0, attempt=None):
            if not 0 <= index < len(self.queue):
                return self.stop_all()
            self.mpv.start()
            t = self.queue[index]
            cached = self.streams.get(t["videoId"])
            if attempt is None:
                attempt = "direct" if cached and cached[1] > time.monotonic() else "ytdl"
            self.index, self.loading, self.attempt = index, True, attempt
            self.mpv.command("set_property", "volume", round(self.volume * 100))
            opts = f"start={max(0.0, float(start)):.1f}"
            url = WATCH_URL.format(t["videoId"])
            if attempt == "direct":
                url = cached[0]
            elif attempt == "signed":
                opts += f",ytdl-raw-options-append=cookies={self.mpv.cookies_file}"
            self.mpv.command("loadfile", url, "replace", -1, opts)
            self.mpv.command("set_property", "pause", False)
            self.paused, self.base, self.at = False, float(start), time.monotonic()
            self.own(True)
            self.scrobbler.begin(t)
            self.changed("Metadata", "PlaybackStatus", "CanGoNext", "CanGoPrevious")
            self.Seeked(dbus.Int64(int(float(start) * 1e6)))
            return self.summary()

        def play_queue(self, tracks, index=0, shuffle=False, playlist=""):
            tracks = [dict(t) for t in tracks if VIDEO_ID.match((t or {}).get("videoId") or "")][:MAX_TRACKS]
            if not tracks:
                raise Error("nothing to play")
            index = max(0, min(int(index), len(tracks) - 1))
            self.queue, self.order, self.playlist, self.errors = tracks, list(tracks), playlist, 0
            self.index = index
            self.shuffle = False
            if shuffle:
                self.set_shuffle(True, quiet=True)
            return self.load(self.index)

        def set_shuffle(self, on, quiet=False):
            on = bool(on)
            if on and not self.shuffle and self.queue:
                cur = self.queue[self.index] if 0 <= self.index < len(self.queue) else None
                rest = [t for i, t in enumerate(self.queue) if i != self.index]
                random.shuffle(rest)
                self.queue = ([cur] if cur else []) + rest
                self.index = 0 if cur else -1
            elif not on and self.shuffle and self.order:
                cur = self.track()
                self.queue = list(self.order)
                self.index = next((i for i, t in enumerate(self.queue) if cur and t["videoId"] == cur["videoId"]), 0)
            self.shuffle = on
            if not quiet:
                self.changed("Shuffle", "CanGoNext", "CanGoPrevious")
            return self.summary()

        def set_loop(self, status):
            if status == "cycle":
                status = {"None": "Playlist", "Playlist": "Track", "Track": "None"}[self.loop]
            if status not in ("None", "Playlist", "Track"):
                raise Error(f"repeat: None, Playlist or Track, not {status!r}")
            self.loop = status
            self.changed("LoopStatus", "CanGoNext", "CanGoPrevious")
            return self.summary()

        def after(self, index):
            """The song after `index`, as repeat has it (None: the end)."""
            if index + 1 < len(self.queue):
                return index + 1
            return 0 if self.loop == "Playlist" and self.queue else None

        def resync(self):
            pos = self.mpv.command("get_property", "time-pos", timeout=2) if self.mpv.running() else None
            if isinstance(pos, (int, float)):
                self.base, self.at = float(pos), time.monotonic()
                self.Seeked(dbus.Int64(int(float(pos) * 1e6)))
            return False

        def set_paused(self, paused):
            if not self.track():
                return self.summary()
            if not self.mpv.running():
                return self.load(self.index, self.base)
            pos = self.position()
            self.mpv.command("set_property", "pause", bool(paused))
            self.paused, self.base, self.at = bool(paused), pos, time.monotonic()
            self.changed("PlaybackStatus")
            if not paused:
                self.resync()
            return self.summary()

        def seek_to(self, seconds):
            if not self.track():
                return self.summary()
            seconds = max(0.0, float(seconds))
            if self.mpv.running():
                self.mpv.command("seek", seconds, "absolute")
            self.base, self.at = seconds, time.monotonic()
            self.Seeked(dbus.Int64(int(seconds * 1e6)))
            return self.summary()

        def step(self, by):
            if not self.queue:
                return self.summary()
            if by < 0 and self.position() > 5:
                return self.seek_to(0)
            if by > 0:
                nxt = self.after(self.index)
                return self.load(nxt) if nxt is not None else self.summary()
            prev = self.index - 1 if self.index > 0 else (len(self.queue) - 1 if self.loop == "Playlist" else None)
            return self.load(prev) if prev is not None else self.seek_to(0)

        def stop_all(self):
            self.mpv.stop()
            self.queue, self.order, self.index, self.paused, self.playlist = [], [], -1, True, ""
            self.changed("Metadata", "PlaybackStatus")
            self.own(False)
            self.idle_since = time.monotonic()
            return self.summary()

        def mpv_event(self, ev):
            name = ev.get("event")
            if name == "property-change" and ev.get("name") == "pause" and isinstance(ev.get("data"), bool):
                if ev["data"] != self.paused and not self.loading:
                    self.base, self.at, self.paused = self.position(), time.monotonic(), ev["data"]
                    self.changed("PlaybackStatus")
            elif name == "playback-restart":
                # Sound actually starts (a song loaded — yt-dlp takes
                # seconds —, a seek done): where it is, said to MPRIS, whose
                # clients (lyrics, progress bars) count from the last Seeked.
                self.resync()
            elif name == "file-loaded":
                self.loading, self.errors = False, 0
                nxt = self.after(self.index)
                if nxt is not None:
                    self.prefetch(nxt)
            elif name == "end-file":
                reason = ev.get("reason")
                if reason == "eof":
                    nxt = self.index if self.loop == "Track" else self.after(self.index)
                    self.load(nxt) if nxt is not None else self.stop_all()
                elif reason == "error":
                    t = self.track()
                    print(f"{APP}: couldn't play {t and t['videoId']} ({self.attempt}): {ev.get('file_error')}",
                          file=sys.stderr, flush=True)
                    if t:
                        self.streams.pop(t["videoId"], None)
                    # The next way to open it (some songs need the account:
                    # age-restricted…), else the next song.
                    later = [a for a in self.ATTEMPTS[self.ATTEMPTS.index(self.attempt) + 1:]
                             if a != "signed" or self.mpv.cookies_file]
                    if t and later:
                        self.load(self.index, self.base, attempt=later[0])
                        return False
                    self.errors += 1
                    nxt = self.after(self.index)
                    if self.errors < 3 and nxt is not None and nxt != self.index:
                        self.load(nxt)
                    else:
                        self.stop_all()
            elif name == "mpv-gone" and self.track():
                # mpv ended on its own: kept where it was, paused.
                self.base, self.paused = self.position(), True
                self.mpv.stop()
                self.changed("PlaybackStatus")
            return False

        def tick(self):
            if self.track() and not self.paused:
                self.scrobbler.tick(2)
                self.idle_since = time.monotonic()
            elif self.mpv.running() and time.monotonic() - self.idle_since > IDLE_QUIT:
                self.base = self.position()
                self.mpv.stop()
            return True

        # -- org.freedesktop.DBus.Properties
        def props(self, iface):
            if iface == ROOT:
                return {"Identity": IDENTITY, "DesktopEntry": DESKTOP_ENTRY, "CanQuit": True, "CanRaise": False,
                        "HasTrackList": False, "SupportedUriSchemes": dbus.Array(["https"], signature="s"),
                        "SupportedMimeTypes": dbus.Array([], signature="s")}
            return {"PlaybackStatus": self.status(), "Metadata": self.metadata(), "LoopStatus": self.loop,
                    "Shuffle": self.shuffle, "Rate": 1.0, "MinimumRate": 1.0, "MaximumRate": 1.0,
                    "Volume": self.volume, "Position": dbus.Int64(int(self.position() * 1e6)),
                    "CanGoNext": self.after(self.index) is not None, "CanGoPrevious": bool(self.queue),
                    "CanPlay": bool(self.queue), "CanPause": bool(self.queue), "CanSeek": bool(self.queue),
                    "CanControl": True}

        @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self.props(iface)[prop]

        @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return self.props(iface)

        @dbus.service.method(PROPS, in_signature="ssv")
        def Set(self, iface, prop, value):
            if iface == PLAYER and prop == "Shuffle":
                self.set_shuffle(bool(value))
            elif iface == PLAYER and prop == "LoopStatus":
                self.set_loop(str(value))
            elif iface == PLAYER and prop == "Volume":
                self.volume = max(0.0, min(1.0, float(value)))
                if self.mpv.running():
                    self.mpv.command("set_property", "volume", round(self.volume * 100))
                self.changed("Volume")

        @dbus.service.signal(PROPS, signature="sa{sv}as")
        def PropertiesChanged(self, iface, changed, invalidated):
            pass

        @dbus.service.method(ROOT)
        def Raise(self):
            pass

        @dbus.service.method(ROOT)
        def Quit(self):
            self.stop_all()

        @dbus.service.signal(PLAYER, signature="x")
        def Seeked(self, position):
            pass

        @dbus.service.method(PLAYER)
        def Play(self):
            self.set_paused(False)

        @dbus.service.method(PLAYER)
        def Pause(self):
            self.set_paused(True)

        @dbus.service.method(PLAYER)
        def PlayPause(self):
            self.set_paused(not self.paused)

        @dbus.service.method(PLAYER)
        def Stop(self):
            self.stop_all()

        @dbus.service.method(PLAYER)
        def Next(self):
            self.step(1)

        @dbus.service.method(PLAYER)
        def Previous(self):
            self.step(-1)

        @dbus.service.method(PLAYER, in_signature="x")
        def Seek(self, offset):
            self.seek_to(self.position() + offset / 1e6)

        @dbus.service.method(PLAYER, in_signature="ox")
        def SetPosition(self, track_id, position):
            self.seek_to(position / 1e6)

        @dbus.service.method(PLAYER, in_signature="s")
        def OpenUri(self, uri):
            vid = (re.search(r"[?&]v=([\w-]{11})", uri) or [None, ""])[1]
            t = float((re.search(r"[?&]t=(\d+)", uri) or [None, "0"])[1])
            if vid:
                threading.Thread(target=lambda: self.handle({"cmd": "playId", "videoId": vid, "start": t}),
                                 daemon=True).start()

        # -- the socket's commands (from a client thread)
        def handle(self, req):
            cmd = req.get("cmd")
            if cmd == "status":
                return on_main(self.summary)
            if cmd == "play":
                return on_main(self.play_queue, req.get("tracks") or [], req.get("index") or 0,
                               bool(req.get("shuffle")), str(req.get("playlist") or ""))
            if cmd == "playId":
                t = song(str(req.get("videoId") or ""))  # the network, off the main loop
                start = float(req.get("start") or 0)
                return on_main(lambda: self.play_queue([t], 0) if start <= 0 else (
                    self.play_queue([t], 0), self.load(0, start))[1])
            if cmd == "control":
                action = req.get("action")
                acts = {"play": lambda: self.set_paused(False), "pause": lambda: self.set_paused(True),
                        "toggle": lambda: self.set_paused(not self.paused), "next": lambda: self.step(1),
                        "previous": lambda: self.step(-1), "stop": self.stop_all,
                        "seek": lambda: self.seek_to(float(req.get("value") or 0)),
                        "shuffle": lambda: self.set_shuffle(not self.shuffle if req.get("value") in (None, "toggle")
                                                            else req.get("value") in (True, "on", "true", 1)),
                        "repeat": lambda: self.set_loop({"none": "None", "playlist": "Playlist", "track": "Track",
                                                         "one": "Track", "all": "Playlist"}.get(
                                                             str(req.get("value") or "cycle").lower(), "cycle"))}
                if action not in acts:
                    raise Error(f"unknown action {action!r}")
                return on_main(acts[action])
            if cmd == "reload":
                def reload():
                    self.scrobbler.creds = lastfm_creds()
                    cookie = session()
                    self.mpv.cookies_file = write_cookies_file(cookie) if cookie else None
                    return self.summary()
                return on_main(reload)
            raise Error(f"unknown command {cmd!r}")

    player = Player()

    path = player_socket()
    try:
        os.remove(path)
    except OSError:
        pass
    srv = socket.socket(socket.AF_UNIX)
    old = os.umask(0o177)
    srv.bind(path)
    os.umask(old)
    srv.listen(8)

    def client(conn):
        with conn:
            try:
                if peer_uid(conn) != os.getuid():
                    return
                f = conn.makefile("rb")
                for line in f:
                    try:
                        r = {"ok": True, "result": player.handle(json.loads(line))}
                    except (Error, ValueError, TypeError) as exc:
                        r = {"ok": False, "error": str(exc)}
                    conn.sendall(json.dumps(r, ensure_ascii=False).encode() + b"\n")
            except OSError:
                pass

    def accept():
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=client, args=(conn,), daemon=True).start()
    threading.Thread(target=accept, daemon=True).start()

    loop = GLib.MainLoop()
    import signal
    try:
        from gi.repository import GLibUnix
        add_signal = GLibUnix.signal_add
    except ImportError:
        add_signal = GLib.unix_signal_add
    for sig in (signal.SIGTERM, signal.SIGINT):
        add_signal(GLib.PRIORITY_HIGH, sig, lambda: (loop.quit(), False)[1])
    print(f"{APP}: ready", file=sys.stderr, flush=True)
    try:
        loop.run()
    finally:
        player.mpv.stop()
        for p in (path, os.path.join(runtime_dir(), "cookies.txt")):
            try:
                os.remove(p)
            except OSError:
                pass


COMMANDS = {"browsers": cmd_browsers, "login-from-browser": cmd_login, "forget": cmd_forget, "status": cmd_status,
            "playlists": cmd_playlists, "playlist": cmd_playlist, "play": cmd_play,
            "play-tracks": cmd_play_tracks, "play-id": cmd_play_id, "control": cmd_control,
            "lastfm": cmd_lastfm, "serve": serve}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        COMMANDS[argv[0]](argv[1:])
    except Error as exc:
        out({"error": str(exc)}, 1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
