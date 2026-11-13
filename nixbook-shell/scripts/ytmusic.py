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
  nixbook-ytmusic search WORDS...      songs and videos found on YouTube
                                       Music, JSON
  nixbook-ytmusic add PLAYLIST VIDEO   a song into one of your playlists
                                       (LM, Liked Music: the song liked)
  nixbook-ytmusic remove PLAYLIST VIDEO [SET_VIDEO]
                                       a song out of one of your playlists
                                       (LM: the like taken back)
  nixbook-ytmusic create TITLE... [VIDEO]
                                       a new private playlist (with a song)
  nixbook-ytmusic play ID [--index N] [--shuffle]
                                       a playlist, from its song N
  nixbook-ytmusic play-tracks          {tracks, index, shuffle} on stdin
  nixbook-ytmusic play-id VIDEO [--start SECONDS]
  nixbook-ytmusic control play|pause|toggle|next|previous|stop|seek S|volume 0-100
                       shuffle [on|off|toggle]  repeat [none|playlist|track|cycle]
  nixbook-ytmusic offline status|keep ID [TITLE]|unkeep ID|set limit MB|
                       set auto on|off|clear [--all]|gc|sync
                                       songs kept on this computer for
                                       offline listening: a playlist kept
                                       whole, the songs heard 30 s (auto);
                                       over the limit (4 GB) the least
                                       recently played go, never a kept
                                       playlist's
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
  nixbook-ytmusic videos home|subscriptions [--count N] [--cached]
  nixbook-ytmusic videos search WORDS... [--count N]
  nixbook-ytmusic videos channel URL|VIDEO [--tab latest|popular|shorts|live|playlists]
                       [--query WORDS...] [--count N]
                                       a channel's tab (latest: its Videos,
                                       popular: its most viewed, shorts,
                                       live: its streams, playlists: its
                                       playlists {id, title, thumb}), or a
                                       search in the channel (--query)
  nixbook-ytmusic videos playlist ID [--count N]
                                       a playlist's videos
  nixbook-ytmusic videos channels [--cached]
  nixbook-ytmusic videos video ID      one video (a pasted link): its title
                                       and channel, through YouTube's oEmbed
  nixbook-ytmusic videos subscribe|unsubscribe CHANNEL_ID
                                       subscribe to a channel (UC…), or no
                                       longer (the same subscriptions as
                                       YouTube's own)
                                       YouTube's videos (www.youtube.com, the
                                       same session): your home page, your
                                       subscriptions' latest, a search; JSON
                                       ({feed, items: [{id, title, channel,
                                       channelUrl, duration, views, live,
                                       thumb}]}), a channel's latest videos
                                       (newest first; {channel: {name, url,
                                       followers}}), the channels you're
                                       subscribed to ({channels: [{id, name,
                                       url, followers, avatar}]}); --cached:
                                       the last copy, at once
  nixbook-ytmusic watch VIDEO [--start SECONDS] [--volume 0-100]
                                       a YouTube video in mpv (yours: your
                                       config), the background player paused

Secrets live in the keyring (secret-tool, service=nixbook-ytmusic, kind
session|lastfm), never in a file but the cookie file yt-dlp reads while the
player runs ($XDG_RUNTIME_DIR, 0600, removed when it stops). The player's
socket ($XDG_RUNTIME_DIR/nixbook-ytmusic/player.sock) is this user's only
(0700 directory, 0600 socket, the peer's uid checked).
"""

import concurrent.futures
import contextlib
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


def saved_volume():
    """The player's volume as last set (MPRIS Volume, 0-1), 1 the first time."""
    try:
        return max(0.0, min(1.0, float((read_json(os.path.join(state_dir(), "volume.json"), {}) or {}).get("volume", 1))))
    except (TypeError, ValueError):
        return 1.0


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


# Google rotates a signed-in browser's cookies; the copy kept here then stops
# working: YouTube Music answers 401 "not authorized to edit this playlist",
# or an empty library (2026-11-11: every add refused, the playlists stale).
REFUSED = re.compile(r"\b40[13]\b|unauthori[sz]ed|not authorized|login required|sign(ed)? ?in", re.I)


def renew_session():
    """The session copied again from the browser it came from (login.json),
    when that browser still has a working login of the same account: the
    new cookie kept and returned, else None."""
    login = read_json(login_path(), {}) or {}
    browser, account = login.get("browser"), login.get("account")
    if not browser:
        return None
    old = session()
    for cookies, b in browser_logins():
        cookie = cookie_header(cookies)
        if b != browser or cookie == old:
            continue
        try:
            name = account_of(ytmusic(cookie))
        except Error:
            continue
        if account and name != account:
            continue
        keyring_set("session", f"YouTube Music session of {name} ({APP})", {"cookie": cookie})
        write_private(login_path(), {**login, "account": name, "at": int(time.time())})
        return cookie
    return None


def signed_in(fn, refused=None):
    """fn(yt) on the kept session; when YouTube Music refuses it (an error
    saying so, or refused(answer): an empty library), once more on the
    session renewed from the browser (renew_session)."""
    try:
        answer = fn(ytmusic())
    except Error:
        raise
    except Exception as exc:  # noqa: BLE001 — ytmusicapi raises many kinds
        if not REFUSED.search(str(exc)) or not renew_session():
            raise
        return fn(ytmusic())
    if refused and refused(answer) and renew_session():
        return fn(ytmusic())
    return answer


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
    track = {"videoId": vid, "title": t.get("title") or "", "artist": artists, "album": album,
             "duration": int(t.get("duration_seconds") or 0), "art": best(t.get("thumbnails"))}
    # A playlist item's own id (in your playlists): what removing it takes.
    if PLAYLIST_ID.match(t.get("setVideoId") or ""):
        track["setVideoId"] = t["setVideoId"]
    return track


def offline_card(index=None):
    index = index or read_index()
    n = len(index["songs"])
    return [{"id": OFFLINE_PLAYLIST, "title": "", "count": str(n), "author": "", "thumb": ""}] if n else []


def with_kept(playlists):
    kept = offline_settings()["kept"]
    for p in playlists:
        p["kept"] = p.get("id") in kept
    return playlists


def cmd_playlists(_args):
    copy = os.path.join(offline_dir(), "playlists.json")
    def library(yt):
        raw = yt.get_library_playlists(limit=None) or []
        # YouTube Music sometimes answers an empty library, no error (a
        # signed-in library always holds Liked Music): asked once more.
        if not raw:
            time.sleep(1.5)
            raw = yt.get_library_playlists(limit=None) or []
        return raw

    try:
        # Still empty: the session may have gone stale, renewed from the
        # browser.
        raw = signed_in(library, refused=lambda raw: not raw)
    except Error:
        raise
    except Exception as exc:  # noqa: BLE001
        # No network (or YouTube Music not answering): the last copy.
        last = read_json(copy, {}) or {}
        if last.get("playlists"):
            out({"playlists": with_kept(offline_card() + last["playlists"]), "offline": True,
                 "why": f"{exc}"[:200]})
        out({"error": f"YouTube Music didn't list your playlists: {exc}"}, 1)
    items = []
    for p in raw:
        pid = p.get("playlistId") or ""
        if not PLAYLIST_ID.match(pid) or pid == OFFLINE_PLAYLIST:
            continue
        # own: songs can be added to it (Liked Music: by liking them).
        items.append({"id": pid, "title": p.get("title") or "", "count": p.get("count") or "",
                      "own": pid == "LM" or bool(p.get("owned")),
                      "author": ", ".join(a.get("name", "") for a in (p.get("author") or []) if isinstance(a, dict)),
                      "_art": best(p.get("thumbnails"))})
    items.sort(key=lambda p: p["id"] != "LM")  # Liked Music first
    if not items:
        # Still empty: the last copy, kept (it used to be overwritten with
        # nothing, and the tab showed no playlist but "On this computer").
        last = read_json(copy, {}) or {}
        if last.get("playlists"):
            out({"playlists": with_kept(with_offline_card(last["playlists"])), "stale": True,
                 "why": "YouTube Music answered an empty library"})
    items = with_thumbs(items)
    if items:
        write_private(copy, {"playlists": items, "at": int(time.time())})
    out({"playlists": with_kept(with_offline_card(items))})


def with_offline_card(items):
    """The songs on this computer right after Liked Music."""
    n = 1 if items and items[0]["id"] == "LM" else 0
    return items[:n] + offline_card() + items[n:]


def playlist_tracks(pid, yt=None):
    if not PLAYLIST_ID.match(pid or ""):
        raise Error(f"not a playlist id: {pid!r}")
    try:
        if yt:
            raw = yt.get_playlist(pid, limit=MAX_TRACKS) or {}
        else:
            raw = signed_in(lambda yt: yt.get_playlist(pid, limit=MAX_TRACKS)) or {}
    except Error:
        raise
    except Exception as exc:  # noqa: BLE001
        raise Error(f"YouTube Music didn't give that playlist: {exc}") from None
    tracks = [t for t in (track_of(t) for t in raw.get("tracks") or []) if t]
    return raw.get("title") or "", tracks


def save_playlist_copy(pid, title, tracks):
    write_private(playlist_copy_path(pid), {"id": pid, "title": title, "tracks": tracks, "at": int(time.time())})


def cmd_playlist(args):
    if len(args) != 1:
        out({"error": "usage: nixbook-ytmusic playlist ID"}, 1)
    pid = args[0]
    if pid == OFFLINE_PLAYLIST:
        out({"id": pid, "title": "", "tracks": offline_tracks(), "offline": True, "kept": False})
    kept = pid in offline_settings()["kept"]
    try:
        title, tracks = playlist_tracks(pid)
    except Error as exc:
        last = read_json(playlist_copy_path(pid), {}) or {}
        if last.get("tracks"):
            out({"id": pid, "title": last.get("title") or "", "tracks": with_cached(last["tracks"]),
                 "offline": True, "kept": kept})
        out({"error": str(exc)}, 1)
    for t in tracks:
        t["_art"] = t["art"]
    tracks = with_thumbs(tracks, size=120)
    save_playlist_copy(pid, title, tracks)
    out({"id": pid, "title": title, "tracks": with_cached(tracks), "kept": kept})


def edit_status(answer):
    """ytmusicapi's answer to a playlist edit: "added", "already" (the song
    is in it: duplicates refused) or None (refused)."""
    if isinstance(answer, dict) and "SUCCEEDED" in str(answer.get("status") or ""):
        return "added"
    text = json.dumps(answer, default=str).lower() if answer else ""
    if "duplicate" in text or "already" in text:
        return "already"
    return None


def cmd_add(args):
    """A song into one of your playlists (Liked Music: the song liked)."""
    if len(args) != 2 or not PLAYLIST_ID.match(args[0]) or not VIDEO_ID.match(args[1]):
        out({"error": "usage: nixbook-ytmusic add PLAYLIST VIDEO"}, 1)
    pid, vid = args

    def add(yt):
        if pid == "LM":
            yt.rate_song(vid, "LIKE")
            return "added"
        return edit_status(yt.add_playlist_items(pid, [vid], duplicates=False))

    try:
        status = signed_in(add)
    except Error:
        raise
    except Exception as exc:  # noqa: BLE001
        out({"error": f"YouTube Music didn't add it: {exc}"[:300]}, 1)
    if not status:
        out({"error": "YouTube Music didn't add it (is the playlist yours?)"}, 1)
    out({"ok": True, "playlist": pid, "videoId": vid, "status": status})


def cmd_remove(args):
    """A song out of one of your playlists (Liked Music: the like taken
    back). SET_VIDEO is the playlist item's own id (a song can be in a
    playlist twice); without it, the song's first item is looked up."""
    if len(args) not in (2, 3) or not PLAYLIST_ID.match(args[0]) or not VIDEO_ID.match(args[1]) \
            or (len(args) == 3 and not PLAYLIST_ID.match(args[2])):
        out({"error": "usage: nixbook-ytmusic remove PLAYLIST VIDEO [SET_VIDEO]"}, 1)
    pid, vid = args[0], args[1]
    set_vid = args[2] if len(args) == 3 else ""

    def remove(yt):
        if pid == "LM":
            yt.rate_song(vid, "INDIFFERENT")
            return "removed"
        item = set_vid
        if not item:
            raw = yt.get_playlist(pid, limit=MAX_TRACKS) or {}
            item = next((t.get("setVideoId") for t in raw.get("tracks") or []
                         if t.get("videoId") == vid and t.get("setVideoId")), "")
            if not item:
                return "absent"
        answer = yt.remove_playlist_items(pid, [{"videoId": vid, "setVideoId": item}])
        return "removed" if "SUCCEEDED" in str(answer.get("status") if isinstance(answer, dict) else answer) else None

    try:
        status = signed_in(remove)
    except Error:
        raise
    except Exception as exc:  # noqa: BLE001
        out({"error": f"YouTube Music didn't remove it: {exc}"[:300]}, 1)
    if not status:
        out({"error": "YouTube Music didn't remove it (is the playlist yours?)"}, 1)
    # The playlist's last copy (offline) without it.
    copy = read_json(playlist_copy_path(pid), {}) or {}
    if status == "removed" and copy.get("tracks"):
        tracks = copy["tracks"]
        at = next((i for i, t in enumerate(tracks) if t.get("videoId") == vid
                   and (not set_vid or t.get("setVideoId") in (None, set_vid))), None)
        if at is not None:
            save_playlist_copy(pid, copy.get("title") or "", tracks[:at] + tracks[at + 1:])
    out({"ok": True, "playlist": pid, "videoId": vid, "status": status})


def cmd_create(args):
    """A new (private) playlist, with a song in it."""
    vid = args[-1] if args and VIDEO_ID.match(args[-1]) else ""
    title = " ".join(args[:-1] if vid else args).strip()[:150]
    if not title:
        out({"error": "usage: nixbook-ytmusic create TITLE... [VIDEO]"}, 1)
    try:
        answer = signed_in(lambda yt: yt.create_playlist(title, "", video_ids=[vid] if vid else None))
    except Error:
        raise
    except Exception as exc:  # noqa: BLE001
        out({"error": f"YouTube Music didn't make the playlist: {exc}"[:300]}, 1)
    if not isinstance(answer, str) or not PLAYLIST_ID.match(answer):
        out({"error": "YouTube Music didn't make the playlist"}, 1)
    out({"ok": True, "playlist": answer, "title": title, "videoId": vid or None})


SEARCH_LIMIT = 20


def search_results(raw, kinds=("song", "video"), limit=SEARCH_LIMIT):
    """The songs (and videos) of a search's answer, each once, as the player
    knows them; `kind` says which."""
    seen, found = set(), []
    for r in raw or []:
        if not isinstance(r, dict) or r.get("resultType") not in kinds:
            continue
        t = track_of(r)
        if t and t["videoId"] not in seen:
            seen.add(t["videoId"])
            t["kind"] = r["resultType"]
            found.append(t)
        if len(found) >= limit:
            break
    return found


def cmd_search(args):
    query = " ".join(args).strip()[:200]
    if not query:
        out({"error": "usage: nixbook-ytmusic search WORDS..."}, 1)
    try:
        yt = ytmusic()
    except Error:
        yt = ytmusic(signed_in=False)  # the catalogue answers signed out too

    def find(kind):
        return yt.search(query, filter=kind + "s", limit=SEARCH_LIMIT) or []

    # Songs and videos (covers, live versions, what isn't released as a song),
    # asked together.
    try:
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            songs, videos = pool.map(find, ("song", "video"))
    except Exception as exc:  # noqa: BLE001
        out({"error": f"YouTube Music didn't answer the search: {exc}"}, 1)
    # The pictures stay links: the panel loads them as they come, so the
    # answer doesn't wait for 40 downloads.
    out({"query": query, "songs": search_results(songs, ("song",)),
         "videos": search_results(videos, ("video",))})


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


# -- offline: songs kept on this computer ---------------------------------
# Each song is yt-dlp's best audio as it comes (Opus or AAC, ~3-5 MB),
# $XDG_CACHE_HOME/nixbook-ytmusic/offline/<videoId>.<ext>, listed in
# index.json ({songs: {videoId: {file, size, track, added, played}}}, written
# under offline/.lock, replaced by rename so a reader never sees half of it).
# Songs come there two ways: one heard AUTO_AFTER seconds (the `auto`
# setting), and every song of a playlist kept offline (`kept`). The settings
# ({limitMB, auto, kept: {id: {title, at}}}) are the user's, in the state
# dir; the songs are a cache. Over `limitMB`, the least recently played go
# first; a kept playlist's songs never do (when they alone fill the space,
# what is left of them waits: `full`). The last copy of each playlist opened
# (playlists.json, playlist-<id>.json) answers when YouTube Music doesn't:
# no network, the panel lists them from there and plays what is kept.
OFFLINE_LIMIT_MB = 4096
OFFLINE_PLAYLIST = "_offline"  # the virtual playlist of every song kept
AUTO_AFTER = 30
OFFLINE_REFRESH = 3 * 3600  # the kept playlists looked at again (new songs)


def offline_dir():
    return cache_dir("offline")


def offline_settings_path():
    return os.path.join(state_dir(), "offline.json")


def offline_settings():
    s = read_json(offline_settings_path(), {}) or {}
    kept = s.get("kept") if isinstance(s.get("kept"), dict) else {}
    try:
        limit = int(s.get("limitMB") or OFFLINE_LIMIT_MB)
    except (TypeError, ValueError):
        limit = OFFLINE_LIMIT_MB
    return {"limitMB": max(256, min(limit, 1024 * 1024)), "auto": s.get("auto", True) is not False,
            "kept": {k: v for k, v in kept.items() if PLAYLIST_ID.match(k) and k != OFFLINE_PLAYLIST
                     and isinstance(v, dict)}}


def save_offline_settings(s):
    write_private(offline_settings_path(), s)


def read_index():
    idx = read_json(os.path.join(offline_dir(), "index.json"), {}) or {}
    songs = idx.get("songs") if isinstance(idx.get("songs"), dict) else {}
    return {"songs": {k: v for k, v in songs.items() if VIDEO_ID.match(k) and isinstance(v, dict)}}


class IndexLock:
    """The index, read under the lock and written back when left."""

    def __enter__(self):
        import fcntl
        self.f = open(os.path.join(offline_dir(), ".lock"), "a")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        self.index = read_index()
        return self.index

    def __exit__(self, kind, *_):
        try:
            if kind is None:
                write_private(os.path.join(offline_dir(), "index.json"), self.index)
        finally:
            self.f.close()


def offline_file(vid, index=None):
    """The song's file when it is kept here, else ""."""
    s = (index or read_index())["songs"].get(vid)
    if not s or "/" in str(s.get("file") or "/"):
        return ""
    path = os.path.join(offline_dir(), s["file"])
    return path if os.path.isfile(path) else ""


def playlist_copy_path(pid):
    return os.path.join(offline_dir(), f"playlist-{pid}.json")


def kept_ids(settings, index=None):
    """The songs of the playlists kept offline (their last copy)."""
    ids = set()
    for pid in settings["kept"]:
        for t in (read_json(playlist_copy_path(pid), {}) or {}).get("tracks") or []:
            if isinstance(t, dict) and VIDEO_ID.match(t.get("videoId") or ""):
                ids.add(t["videoId"])
    return ids


def gc_plan(songs, keep, limit):
    """The songs to let go so the rest fits in `limit` bytes, the least
    recently played first, never one in `keep`; and the total left."""
    total = sum(int(s.get("size") or 0) for s in songs.values())
    gone = []
    for vid, s in sorted(songs.items(), key=lambda kv: (kv[1].get("played") or kv[1].get("added") or 0, kv[0])):
        if total <= limit:
            break
        if vid in keep:
            continue
        gone.append(vid)
        total -= int(s.get("size") or 0)
    return gone, total


def remove_songs(index, vids):
    freed = 0
    for vid in vids:
        s = index["songs"].pop(vid, None)
        if not s:
            continue
        freed += int(s.get("size") or 0)
        try:
            os.remove(os.path.join(offline_dir(), os.path.basename(s.get("file") or "")))
        except OSError:
            pass
    return freed


def collect_garbage(settings=None):
    """Over the limit, the least recently played go (never a kept
    playlist's); songs whose file is gone leave the index, and files no song
    names (a download cut off, an older copy) the folder, once an hour old."""
    settings = settings or offline_settings()
    keep = kept_ids(settings)
    d, now = offline_dir(), time.time()
    with IndexLock() as index:
        for vid in [v for v in index["songs"] if not offline_file(v, index)]:
            index["songs"].pop(vid)
        gone, total = gc_plan(index["songs"], keep, settings["limitMB"] * 1024 * 1024)
        freed = remove_songs(index, gone)
        named = {s["file"] for s in index["songs"].values()}
        copies = {os.path.basename(playlist_copy_path(p)) for p in settings["kept"]}
        for name in os.listdir(d):
            path = os.path.join(d, name)
            if name in named or name in ("index.json", ".lock", "playlists.json", "status.json") or name in copies:
                continue
            try:
                age = now - os.path.getmtime(path)
                # Another playlist's copy stays a month (offline browsing).
                if age > (30 * 86400 if name.startswith("playlist-") else 3600):
                    os.remove(path)
            except OSError:
                pass
    return {"removed": len(gone), "freed": freed, "used": total}


def mark_played(vid):
    with IndexLock() as index:
        if vid in index["songs"]:
            index["songs"][vid]["played"] = int(time.time())


def with_cached(tracks, index=None):
    index = index or read_index()
    for t in tracks:
        t["cached"] = t.get("videoId") in index["songs"]
    return tracks


def offline_tracks(index=None):
    """Every song kept, the last played first."""
    index = index or read_index()
    # Times are whole seconds: a song played in the second the others came
    # goes before them.
    songs = sorted(index["songs"].values(),
                   key=lambda s: (-(s.get("played") or s.get("added") or 0), 0 if s.get("played") else 1))
    return [dict(s.get("track") or {}, cached=True) for s in songs
            if VIDEO_ID.match((s.get("track") or {}).get("videoId") or "")]


def download_song(vid, cookies_file=None):
    """The song's audio into the offline folder (its path), at low priority."""
    d = offline_dir()
    cmd = [YT_DLP, "-f", "bestaudio/best", "--no-playlist", "--no-warnings", "--quiet", "--no-progress",
           "--no-mtime", "-o", os.path.join(d, "%(id)s.%(ext)s"), "--print", "after_move:filepath",
           WATCH_URL.format(vid)]
    if cookies_file:
        cmd[1:1] = ["--cookies", cookies_file]
    if shutil.which("nice"):  # not preexec_fn: the player has threads
        cmd[:0] = ["nice", "-n", "10"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Error(f"yt-dlp didn't finish: {exc}") from None
    path = (r.stdout.strip().splitlines() or [""])[-1]
    real = os.path.realpath(path) if path else ""
    if r.returncode != 0 or not real or os.path.dirname(real) != os.path.realpath(d) or not os.path.isfile(real):
        raise Error((r.stderr.strip().splitlines() or ["yt-dlp gave no file"])[-1][:300])
    return real


def offline_status_path():
    return os.path.join(offline_dir(), "status.json")


def offline_summary():
    s, index = offline_settings(), read_index()
    used = sum(int(x.get("size") or 0) for x in index["songs"].values())
    st = read_json(offline_status_path(), {}) or {}
    alive = False
    try:
        os.kill(int(st.get("pid") or 0), 0)
        alive = int(st.get("pid") or 0) > 0
    except (OSError, ValueError):
        pass
    kept = []
    for pid, meta in s["kept"].items():
        tracks = (read_json(playlist_copy_path(pid), {}) or {}).get("tracks") or []
        ids = [t.get("videoId") for t in tracks if isinstance(t, dict)]
        kept.append({"id": pid, "title": meta.get("title") or (read_json(playlist_copy_path(pid), {}) or {}).get("title") or pid,
                     "total": len(ids), "cached": sum(1 for v in ids if v in index["songs"])})
    return {"limitMB": s["limitMB"], "auto": s["auto"], "used": used, "count": len(index["songs"]), "kept": kept,
            "downloading": st.get("downloading") if alive else None, "left": int(st.get("left") or 0) if alive else 0,
            "full": bool(st.get("full")), "error": st.get("error") or ""}


def cmd_offline(args):
    what = args[0] if args else "status"
    s = offline_settings()
    if what == "status":
        out(offline_summary())
    if what == "keep" and len(args) >= 2 and PLAYLIST_ID.match(args[1]) and args[1] != OFFLINE_PLAYLIST:
        s["kept"][args[1]] = {"title": " ".join(args[2:])[:200], "at": int(time.time())}
        save_offline_settings(s)
        ask_player({"cmd": "offlineSync"})  # started if it isn't: it downloads
        out(offline_summary())
    if what == "unkeep" and len(args) == 2:
        before = kept_ids(s)
        s["kept"].pop(args[1], None)
        save_offline_settings(s)
        # Its songs go, but those another kept playlist has.
        with IndexLock() as index:
            remove_songs(index, before - kept_ids(s))
        out(offline_summary())
    if what == "set" and len(args) == 3 and args[1] == "limit":
        try:
            s["limitMB"] = int(args[2])
        except ValueError:
            out({"error": "usage: nixbook-ytmusic offline set limit MB"}, 1)
        save_offline_settings(s)
        collect_garbage()
        ask_player({"cmd": "offlineSync"}, start=False)  # room for what waited
        out(offline_summary())
    if what == "set" and len(args) == 3 and args[1] == "auto" and args[2] in ("on", "off"):
        s["auto"] = args[2] == "on"
        save_offline_settings(s)
        out(offline_summary())
    if what == "clear":
        # The songs no kept playlist has; --all: every song, and nothing kept.
        if "--all" in args:
            s["kept"] = {}
            save_offline_settings(s)
        keep = kept_ids(s)
        with IndexLock() as index:
            remove_songs(index, [v for v in index["songs"] if v not in keep])
        collect_garbage()
        out(offline_summary())
    if what == "gc":
        out(collect_garbage())
    if what == "sync":
        reply(ask_player({"cmd": "offlineSync"}))
    out({"error": "usage: nixbook-ytmusic offline status|keep ID [TITLE]|unkeep ID|set limit MB|"
                  "set auto on|off|clear [--all]|gc|sync"}, 1)


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
        out({"error": "usage: nixbook-ytmusic control play|pause|toggle|next|previous|stop|seek S|volume N|"
                      "shuffle [on|off|toggle]|repeat [none|playlist|track|cycle]"}, 1)
    req = {"cmd": "control", "action": args[0]}
    if args[0] in ("seek", "volume") and len(args) > 1:
        try:
            req["value"] = float(args[1])
        except ValueError:
            out({"error": f"{args[0]}: a number"}, 1)
        if args[0] == "volume" and not 0 <= req["value"] <= 100:
            out({"error": "volume: 0 to 100"}, 1)
    elif args[0] in ("shuffle", "repeat") and len(args) > 1:
        req["value"] = args[1]
    reply(ask_player(req, start=args[0] in ("play", "toggle")))



# -- YouTube's videos: the side panel's YouTube tab -------------------------
# The same YouTube session as the music (Google's cookies are youtube.com's,
# music. and www. alike), read through yt-dlp: it follows YouTube's pages as
# they change, so nothing here names YouTube's own structures. Home is
# yt-dlp's :ytrec (the recommendations of your home page), Subscriptions its
# :ytsubs (your subscriptions' latest videos), a search ytsearchN:. Each
# answer is kept (videos-<feed>.json in the cache) so the tab shows the last
# one at once while the next comes (2-3 s for 30 videos).
VIDEO_FEEDS = {"home": ":ytrec", "subscriptions": ":ytsubs"}
VIDEO_PAGE = 30
VIDEO_MAX = 150
YOUTUBE_WATCH = "https://www.youtube.com/watch?v={}"
# A channel's page: its id, its @handle, or the older /c/ and /user/ names.
CHANNEL_URL = re.compile(r"^https://(?:www\.|m\.)?youtube\.com/(?:channel/UC[A-Za-z0-9_-]{22}|@[^/?#\s]{1,100}"
                         r"|c/[^/?#\s]{1,100}|user/[^/?#\s]{1,100})")


def channel_url(e):
    """The channel page of an entry (or of a list), "" when unknown."""
    for url in (e.get("channel_url"), e.get("uploader_url")):
        m = CHANNEL_URL.match(str(url or ""))
        if m:
            return m.group(0).replace("://m.", "://www.")
    cid = str(e.get("channel_id") or "")
    return f"https://www.youtube.com/channel/{cid}" if re.fullmatch(r"UC[A-Za-z0-9_-]{22}", cid) else ""


def video_of(e):
    """A video as the tab shows it, or None (a channel, a playlist, a short
    without an id)."""
    vid = str(e.get("id") or "")
    if not VIDEO_ID.match(vid) or e.get("_type") not in (None, "url", "video"):
        return None
    if e.get("ie_key") not in (None, "Youtube"):
        return None
    live = e.get("live_status") in ("is_live", "is_upcoming")
    return {"id": vid, "title": str(e.get("title") or ""),
            "channel": str(e.get("channel") or e.get("uploader") or ""), "channelUrl": channel_url(e),
            "duration": int(e.get("duration") or 0), "views": int(e.get("view_count") or 0),
            "live": live, "upcoming": e.get("live_status") == "is_upcoming",
            # A small picture every video has (320x180), loaded by the panel.
            "thumb": f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg"}


def subscribed_channel(e):
    """A channel of your subscriptions list, or None."""
    cid = str(e.get("channel_id") or e.get("id") or "")
    if not re.fullmatch(r"UC[A-Za-z0-9_-]{22}", cid):
        return None
    pics = [t for t in (e.get("thumbnails") or []) if isinstance(t, dict) and t.get("url")]
    avatar = str(max(pics, key=lambda t: t.get("width") or 0)["url"]) if pics else ""
    if avatar.startswith("//"):
        avatar = "https:" + avatar
    return {"id": cid, "name": str(e.get("title") or e.get("channel") or ""),
            "url": channel_url(e) or f"https://www.youtube.com/channel/{cid}",
            "followers": int(e.get("channel_follower_count") or 0),
            "avatar": avatar if avatar.startswith("https://") else ""}


def channel_playlist(e):
    """A playlist of a channel's Playlists tab, or None."""
    pid = str(e.get("id") or "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{10,64}", pid) or e.get("ie_key") not in (None, "YoutubeTab"):
        return None
    pics = [t for t in (e.get("thumbnails") or []) if isinstance(t, dict) and str(t.get("url") or "").startswith("https://")]
    return {"id": pid, "title": str(e.get("title") or ""), "count": int(e.get("playlist_count") or 0),
            "thumb": str(max(pics, key=lambda t: t.get("width") or 0)["url"]) if pics else ""}


CHANNEL_TABS = {"latest": "/videos", "shorts": "/shorts", "live": "/streams", "playlists": "/playlists"}


def videos_copy_path(feed):
    return os.path.join(cache_dir(), f"videos-{feed}.json")


def oembed(vid):
    """YouTube's oEmbed answer about a video (~0.1 s, no sign-in), {} when
    it can't say (private, removed, no network)."""
    url = "https://www.youtube.com/oembed?format=json&url=" + urllib.parse.quote(YOUTUBE_WATCH.format(vid), safe="")
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=10) as r:
            answer = json.loads(r.read(65536))
    except (OSError, ValueError):
        return {}
    return answer if isinstance(answer, dict) else {}


def channel_of_video(vid):
    """A video's channel page through YouTube's oEmbed (~0.1 s; yt-dlp's
    flat lists leave it out for some videos), "" when it can't say."""
    m = CHANNEL_URL.match(str(oembed(vid).get("author_url") or ""))
    return m.group(0).replace("://m.", "://www.") if m else ""


def run_video_feed(target, count, cookie, top=None, parse=None):
    """yt-dlp's flat list of `target` (count at most): (videos, error), each
    entry read by `parse` (video_of); the list's own fields (a channel's
    name…) into `top` when given."""
    parse = parse or video_of
    argv = [YT_DLP, "--flat-playlist", "-J", "--no-warnings", "--playlist-end", str(count), target]
    # The session as a cookie file only while yt-dlp reads it (one per run:
    # two feeds may be asked at once).
    cookies = write_cookies_file(cookie, f"videos-cookies-{os.getpid()}.txt") if cookie else None
    if cookies:
        argv[1:1] = ["--cookies", cookies]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=90)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, f"yt-dlp didn't answer ({exc})"
    finally:
        if cookies:
            with contextlib.suppress(OSError):
                os.unlink(cookies)
    if r.returncode != 0:
        lines = [ln for ln in r.stderr.strip().splitlines() if ln.startswith("ERROR")] or r.stderr.strip().splitlines()
        return None, (lines[-1] if lines else f"yt-dlp failed ({r.returncode})").removeprefix("ERROR: ")
    try:
        answer = json.loads(r.stdout or "{}")
        entries = answer.get("entries") or []
    except (ValueError, AttributeError):
        return None, "yt-dlp's answer wasn't readable"
    if top is not None:
        top.update({k: v for k, v in answer.items() if k != "entries"})
    seen, items = set(), []
    for e in entries:
        v = parse(e) if isinstance(e, dict) else None
        if v and v["id"] not in seen:
            seen.add(v["id"])
            items.append(v)
    return items, None


def cmd_videos(args):
    usage = ("usage: nixbook-ytmusic videos home|subscriptions [--count N] [--cached] | videos search WORDS... [--count N]"
             " | videos channel URL|VIDEO [--count N] | videos channels [--cached]")
    if not args:
        out({"error": usage}, 1)
    count = VIDEO_PAGE
    if "--count" in args:
        i = args.index("--count")
        try:
            count = max(1, min(VIDEO_MAX, int(args[i + 1])))
        except (IndexError, ValueError):
            out({"error": usage}, 1)
        args = args[:i] + args[i + 2:]
    feed = args[0]
    if feed in ("subscribe", "unsubscribe"):
        # The account's subscriptions (YouTube Music's artists are YouTube's
        # channels: one list), with the session; the kept list follows.
        cid = args[1] if len(args) > 1 else ""
        if not re.fullmatch(r"UC[A-Za-z0-9_-]{22}", cid):
            out({"error": f"videos {feed}: a channel id (UC…)"}, 1)
        if not session():
            out({"error": "not signed in: Settings > Apps & accounts > YouTube Music > Use my browser's session",
                 "signedOut": True}, 1)
        try:
            if feed == "subscribe":
                signed_in(lambda yt: yt.subscribe_artist(cid))
            else:
                signed_in(lambda yt: yt.unsubscribe_artists([cid]))
        except Error:
            raise
        except Exception as exc:  # noqa: BLE001 — ytmusicapi raises many kinds
            out({"error": f"YouTube didn't {feed}: {exc}"}, 1)
        copy = read_json(videos_copy_path("channels"), None)
        if isinstance(copy, dict) and isinstance(copy.get("channels"), list):
            chans = [c for c in copy["channels"] if c.get("id") != cid]
            if feed == "subscribe":
                # Its name and picture come with the next refresh.
                chans.insert(0, {"id": cid, "name": "", "url": f"https://www.youtube.com/channel/{cid}",
                                 "followers": 0, "avatar": ""})
            write_private(videos_copy_path("channels"), dict(copy, channels=chans))
        out({"ok": True, "channel": cid, "subscribed": feed == "subscribe"})
    if feed == "video":
        # One video by its id (a link pasted in the tab's search field).
        vid = args[1] if len(args) > 1 else ""
        if not VIDEO_ID.match(vid):
            out({"error": "videos video: a YouTube video id"}, 1)
        info = oembed(vid)
        m = CHANNEL_URL.match(str(info.get("author_url") or ""))
        out({"feed": "video", "items": [{
            "id": vid, "title": str(info.get("title") or ""), "channel": str(info.get("author_name") or ""),
            "channelUrl": m.group(0).replace("://m.", "://www.") if m else "", "duration": 0, "views": 0,
            "live": False, "upcoming": False, "thumb": f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg"}],
             "found": bool(info), "at": int(time.time())})
    if feed == "channels":
        # The channels you're subscribed to (YouTube's feed/channels page).
        if "--cached" in args:
            copy = read_json(videos_copy_path("channels"), None)
            out(copy if isinstance(copy, dict) else {"feed": "channels", "channels": [], "at": 0, "none": True})
        cookie = session()
        if not cookie:
            out({"error": "not signed in: Settings > Apps & accounts > YouTube Music > Use my browser's session",
                 "signedOut": True}, 1)
        target, most = "https://www.youtube.com/feed/channels", 2000
        channels, error = run_video_feed(target, most, cookie, parse=subscribed_channel)
        if (error and REFUSED.search(error)) or (not error and not channels):
            renewed = renew_session()
            if renewed:
                channels, error = run_video_feed(target, most, renewed, parse=subscribed_channel)
        if error:
            out({"error": f"YouTube didn't give your subscriptions: {error}"}, 1)
        answer = {"feed": "channels", "channels": channels, "at": int(time.time())}
        write_private(videos_copy_path("channels"), answer)
        out(answer)
    if feed == "playlist":
        # A playlist's videos (a channel's Playlists tab), signed in or not.
        pid = args[1] if len(args) > 1 else ""
        if not re.fullmatch(r"[A-Za-z0-9_-]{10,64}", pid):
            out({"error": "videos playlist: a playlist id"}, 1)
        top = {}
        items, error = run_video_feed(f"https://www.youtube.com/playlist?list={pid}", count, session(), top)
        if error:
            out({"error": f"YouTube didn't give this playlist: {error}"}, 1)
        out({"feed": "playlist", "playlist": {"id": pid, "title": str(top.get("title") or ""),
                                              "count": int(top.get("playlist_count") or 0)},
             "items": items, "at": int(time.time())})
    if feed == "channel":
        # A channel's tab (its latest videos by default, newest first), or a
        # search in it; signed in or not.
        tab = "latest"
        if "--tab" in args:
            i = args.index("--tab")
            tab = args[i + 1] if i + 1 < len(args) else ""
            args = args[:i] + args[i + 2:]
        query = ""
        if "--query" in args:
            i = args.index("--query")
            query = " ".join(args[i + 1:]).strip()[:200]
            args = args[:i]
            if not query:
                out({"error": "videos channel --query: the words to search for"}, 1)
        if tab not in CHANNEL_TABS and tab != "popular":
            out({"error": "videos channel --tab: latest, popular, shorts, live or playlists"}, 1)
        url = (args[1] if len(args) > 1 else "").strip()
        # A video's id: its channel (a feed entry without the channel's link).
        if VIDEO_ID.match(url):
            url = channel_of_video(url)
            if not url:
                out({"error": "YouTube didn't say whose video it is"}, 1)
        m = CHANNEL_URL.match(url)
        if not m:
            out({"error": "videos channel: a YouTube channel's link (youtube.com/channel/UC…, /@name…) or a video id"}, 1)
        page = m.group(0).replace("://m.", "://www.")
        top = {}
        if query:
            target = page + "/search?query=" + urllib.parse.quote(query)
        elif tab == "popular":
            # YouTube's own "Popular videos" list of the channel (UULP + the
            # id: its videos by views); the id from its page when the link is
            # an @name.
            cid = (re.search(r"/channel/UC([A-Za-z0-9_-]{22})", page) or [None, ""])[1]
            if not cid:
                run_video_feed(page + "/videos", 1, session(), top)
                cid = (re.search(r"/channel/UC([A-Za-z0-9_-]{22})", channel_url(top)) or [None, ""])[1]
                if not cid:
                    out({"error": "YouTube didn't say which channel that is"}, 1)
            target = f"https://www.youtube.com/playlist?list=UULP{cid}"
        else:
            target = page + CHANNEL_TABS[tab]
        parse = channel_playlist if tab == "playlists" and not query else None
        list_top = {}
        items, error = run_video_feed(target, count, session(), list_top, parse=parse)
        if error:
            out({"error": f"YouTube didn't give this channel's videos: {error}"}, 1)
        # The channel's own name and link (the popular list is a playlist:
        # its owner's).
        top = top or list_top
        page = channel_url(top) or channel_url(list_top) or page
        name = str(top.get("channel") or top.get("uploader") or list_top.get("channel") or "")
        if parse is None:
            for v in items:
                v["channel"] = v["channel"] or name
                v["channelUrl"] = v["channelUrl"] or page
        out({"feed": "channel", "tab": tab, "query": query,
             "channel": {"name": name, "url": page, "followers": int(top.get("channel_follower_count") or 0)},
             "items": items, "at": int(time.time())})
    if feed == "search":
        query = " ".join(a for a in args[1:] if a != "--cached").strip()[:200]
        if not query:
            out({"error": usage}, 1)
        # Signed in or not: a search answers either way (signed in, as on
        # youtube.com: what you watch counts).
        items, error = run_video_feed(f"ytsearch{count}:{query}", count, session())
        if error:
            out({"error": f"YouTube didn't answer the search: {error}"}, 1)
        out({"feed": "search", "query": query, "items": items, "at": int(time.time())})
    if feed not in VIDEO_FEEDS:
        out({"error": usage}, 1)
    if "--cached" in args:
        copy = read_json(videos_copy_path(feed), None)
        out(copy if isinstance(copy, dict) else {"feed": feed, "items": [], "at": 0, "none": True})
    cookie = session()
    if not cookie:
        out({"error": "not signed in: Settings > Apps & accounts > YouTube Music > Use my browser's session",
             "signedOut": True}, 1)
    items, error = run_video_feed(VIDEO_FEEDS[feed], count, cookie)
    # Google rotates a browser's cookies: the copy kept here can stop
    # working (refused, or an empty feed); renewed once from the browser.
    if (error and REFUSED.search(error)) or (not error and not items):
        renewed = renew_session()
        if renewed:
            items, error = run_video_feed(VIDEO_FEEDS[feed], count, renewed)
    if error:
        out({"error": f"YouTube didn't give your {feed} page: {error}"}, 1)
    answer = {"feed": feed, "items": items, "at": int(time.time())}
    write_private(videos_copy_path(feed), answer)
    out(answer)


def cmd_watch(args):
    """A video in mpv, on its own (the shell starts this through niri, so it
    outlives the shell): the user's mpv first, for their configuration, its
    yt-dlp hook given this package's yt-dlp in case theirs has none."""
    if not args or not VIDEO_ID.match(args[0]):
        out({"error": "usage: nixbook-ytmusic watch VIDEO [--start SECONDS] [--volume 0-100]"}, 1)
    vid, start, volume = args[0], 0, None
    if "--start" in args:
        try:
            start = max(0, int(float(args[args.index("--start") + 1])))
        except (IndexError, ValueError):
            out({"error": "--start: seconds"}, 1)
    if "--volume" in args:
        # The volume the tab's slider was last left at.
        try:
            volume = max(0, min(100, int(float(args[args.index("--volume") + 1]))))
        except (IndexError, ValueError):
            out({"error": "--volume: 0 to 100"}, 1)
    # The music in the background stops for the video (not started if it
    # isn't running).
    ask_player({"cmd": "control", "action": "pause"}, start=False, timeout=3)
    mpv = shutil.which("mpv") or MPV
    argv = [mpv, f"--script-opts-append=ytdl_hook-ytdl_path={YT_DLP}", "--force-window=immediate"]
    if start:
        argv.append(f"--start={start}")
    if volume is not None:
        argv.append(f"--volume={volume}")
    argv.append(YOUTUBE_WATCH.format(vid))
    sys.stdout.flush()
    os.execv(mpv, argv)

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
                f"--script-opts=ytdl_hook-ytdl_path={YT_DLP}", "--audio-display=no", "--keep-open=no",
                # No window, so no on-screen controller: its script ran on every
                # pass of the player all the same (a quarter of mpv's CPU here).
                "--osc=no"]
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


class Downloader:
    """Brings songs to the offline folder, one at a time, at low priority,
    in the player's service: the kept playlists' songs (looked at again
    every OFFLINE_REFRESH, and when told: `offline keep`, `offline sync`),
    then the songs heard (`want`). What it does goes to offline/status.json,
    which `offline status` reads."""

    def __init__(self, cookies_file):
        self.cookies_file = cookies_file  # () → the session's cookie file, or None
        self.wake, self.lock, self.heard = threading.Event(), threading.Lock(), []
        self.state = {"pid": os.getpid(), "downloading": None, "left": 0, "full": False, "error": ""}
        offline_dir()  # made now: not under the socket's umask, a thread later

    def start(self):
        # Once the socket is bound: its umask (0177) is the process's, and a
        # folder this thread made meanwhile had no x bit.
        threading.Thread(target=self.run, daemon=True).start()

    def want(self, track):
        with self.lock:
            if track["videoId"] not in [t["videoId"] for t in self.heard]:
                self.heard.append(dict(track))
        self.wake.set()

    def run(self):
        self.wake.set()  # once at start: what a stopped run left
        while True:
            self.wake.wait(OFFLINE_REFRESH)
            self.wake.clear()
            try:
                self.sync()
            except Exception as exc:  # noqa: BLE001 — logged, the next run tries again
                print(f"{APP}: offline: {exc}", file=sys.stderr, flush=True)
                self.say(downloading=None, left=0, error=str(exc)[:300])

    def say(self, **kw):
        self.state.update(kw)
        try:
            write_private(offline_status_path(), self.state)
        except OSError:
            pass

    def sync(self):
        s = offline_settings()
        todo = []
        for pid, meta in s["kept"].items():
            try:
                title, tracks = playlist_tracks(pid)
                for t in tracks:
                    t["_art"] = t["art"]
                tracks = with_thumbs(tracks, size=120)
                save_playlist_copy(pid, title, tracks)
            except Error:
                tracks = (read_json(playlist_copy_path(pid), {}) or {}).get("tracks") or []
            todo += [(t, True) for t in tracks if isinstance(t, dict)]
        with self.lock:
            heard, self.heard = self.heard, []
        todo += [(t, False) for t in heard if s["auto"]]
        index = read_index()
        todo = [(t, k) for t, k in todo if VIDEO_ID.match(t.get("videoId") or "")
                and not offline_file(t["videoId"], index)]
        seen, queue = set(), []
        for t, k in todo:
            if t["videoId"] not in seen:
                seen.add(t["videoId"])
                queue.append((t, k))
        limit, keep, full, failed = s["limitMB"] * 1024 * 1024, kept_ids(s), False, 0
        for n, (t, kept) in enumerate(queue):
            index = read_index()
            kept_size = sum(int(x.get("size") or 0) for v, x in index["songs"].items() if v in keep)
            if kept_size >= limit:
                # The kept playlists fill the space: nothing more fits.
                full = True
                break
            self.say(downloading={k: t.get(k, "") for k in ("videoId", "title", "artist")},
                     left=len(queue) - n, full=False, error="")
            try:
                path = download_song(t["videoId"])
            except Error as exc:
                try:
                    if not self.cookies_file():
                        raise
                    path = download_song(t["videoId"], self.cookies_file())  # some songs need the account
                except Error:
                    failed += 1
                    print(f"{APP}: offline: {t['videoId']}: {exc}", file=sys.stderr, flush=True)
                    if failed >= 5 and failed > n // 2:
                        self.say(error=str(exc)[:300])
                        break
                    continue
            track = {k: t.get(k) for k in ("videoId", "title", "artist", "album", "duration", "art")}
            track["thumb"] = t.get("thumb") or thumb(t.get("art") or "", 120)
            with IndexLock() as idx:
                idx["songs"][t["videoId"]] = {"file": os.path.basename(path), "size": os.path.getsize(path),
                                              "track": track, "added": int(time.time()), "played": 0,
                                              "why": "kept" if kept else "heard"}
            collect_garbage(s)
        self.say(downloading=None, left=0, full=full)


def write_cookies_file(cookie, name="cookies.txt"):
    """The session as a Netscape cookie file for yt-dlp (0600, runtime dir)."""
    path = os.path.join(runtime_dir(), name)
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
            self.volume, self.errors, self.idle_since = saved_volume(), 0, time.monotonic()
            self.volume_save = None  # the pending write of a changed volume
            cookie = session()
            self.mpv = Mpv(lambda ev: GLib.idle_add(self.mpv_event, ev),
                           write_cookies_file(cookie) if cookie else None)
            self.scrobbler = Scrobbler()
            self.offline = Downloader(lambda: self.mpv.cookies_file)
            self.heard = False  # the song playing given to the downloader
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
                    "volume": round(self.volume * 100),
                    "loading": self.loading, "shuffle": self.shuffle, "loop": self.loop,
                    "lastfm": bool(self.scrobbler.creds)}

        # -- playing
        # How a song is opened, tried in this order when one fails: its copy
        # on this computer ("offline": no network), its stream already
        # resolved while the previous song played ("direct": no pause
        # between songs; yt-dlp takes 5-8 s), yt-dlp through mpv, yt-dlp
        # with the account's session.
        ATTEMPTS = ("offline", "direct", "ytdl", "signed")

        def can(self, attempt, vid):
            if attempt == "offline":
                return bool(offline_file(vid))
            if attempt == "direct":
                got = self.streams.get(vid)
                return bool(got and got[1] > time.monotonic())
            if attempt == "signed":
                return bool(self.mpv.cookies_file)
            return True

        def prefetch(self, index):
            if not 0 <= index < len(self.queue):
                return
            vid = self.queue[index]["videoId"]
            got = self.streams.get(vid)
            if (got and got[1] > time.monotonic()) or offline_file(vid):
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
                attempt = next(a for a in self.ATTEMPTS if self.can(a, t["videoId"]))
            self.index, self.loading, self.attempt, self.heard = index, True, attempt, attempt == "offline"
            local = offline_file(t["videoId"]) if attempt == "offline" else ""
            self.mpv.command("set_property", "volume", round(self.volume * 100))
            opts = f"start={max(0.0, float(start)):.1f}"
            url = WATCH_URL.format(t["videoId"])
            if attempt == "offline":
                url = local
            elif attempt == "direct":
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
                t = self.track()
                if t and self.attempt == "offline":
                    threading.Thread(target=mark_played, args=(t["videoId"],), daemon=True).start()
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
                    if t and self.attempt == "offline":
                        # A copy that doesn't play: gone, the network next.
                        def drop(vid=t["videoId"]):
                            with IndexLock() as index:
                                remove_songs(index, [vid])
                        threading.Thread(target=drop, daemon=True).start()
                    # The next way to open it (some songs need the account:
                    # age-restricted…), else the next song.
                    later = [a for a in self.ATTEMPTS[self.ATTEMPTS.index(self.attempt) + 1:]
                             if a != "offline" and (a != "direct" or self.can(a, t["videoId"] if t else ""))
                             and (a != "signed" or self.mpv.cookies_file)]
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
                # Heard long enough: kept for offline listening (`auto`).
                if not self.heard and not self.loading and self.position() >= AUTO_AFTER:
                    self.heard = True
                    if offline_settings()["auto"]:
                        self.offline.want(self.track())
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
                self.set_volume(value)

        def set_volume(self, value):
            """0-1, into mpv and MPRIS; kept for the next start (a slider
            moves it many times a second: written once it rests)."""
            self.volume = max(0.0, min(1.0, float(value)))
            if self.mpv.running():
                self.mpv.command("set_property", "volume", round(self.volume * 100))
            self.changed("Volume")
            if self.volume_save:
                GLib.source_remove(self.volume_save)
            self.volume_save = GLib.timeout_add(1000, self.save_volume)
            return self.summary()

        def save_volume(self):
            self.volume_save = None
            try:
                write_private(os.path.join(state_dir(), "volume.json"), {"volume": round(self.volume, 3)})
            except OSError:
                pass
            return False

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
                        "volume": lambda: self.set_volume(float(req.get("value") or 0) / 100),
                        "shuffle": lambda: self.set_shuffle(not self.shuffle if req.get("value") in (None, "toggle")
                                                            else req.get("value") in (True, "on", "true", 1)),
                        "repeat": lambda: self.set_loop({"none": "None", "playlist": "Playlist", "track": "Track",
                                                         "one": "Track", "all": "Playlist"}.get(
                                                             str(req.get("value") or "cycle").lower(), "cycle"))}
                if action not in acts:
                    raise Error(f"unknown action {action!r}")
                return on_main(acts[action])
            if cmd == "offlineSync":
                self.offline.wake.set()
                return on_main(self.summary)
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
    player.offline.start()

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
            "playlists": cmd_playlists, "playlist": cmd_playlist, "search": cmd_search, "add": cmd_add, "remove": cmd_remove, "create": cmd_create, "play": cmd_play,
            "play-tracks": cmd_play_tracks, "play-id": cmd_play_id, "control": cmd_control,
            "lastfm": cmd_lastfm, "offline": cmd_offline, "serve": serve, "videos": cmd_videos,
            "watch": cmd_watch}


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
