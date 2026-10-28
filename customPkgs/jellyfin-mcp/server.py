"""jellyfin-mcp: an MCP server (stdio, stdlib only) for the user's Jellyfin
library and the players playing from it.

  jellyfin-mcp                       the MCP server, JSON-RPC lines on stdin/stdout
  jellyfin-mcp configured            {"configured", "player"}; exit 1 when not configured
  jellyfin-mcp play-query TEXT [--season N] [--episode M] [--lang en|fr|de|vi]
                          [--session NAME] [--strict]
                                     find a film, series or episode by its
                                     title and play it, no model: one JSON line
                                     {ok, matched, said, title, ...}
  jellyfin-mcp credentials status|forget
  jellyfin-mcp credentials save|test URL [USER]
                                     the API key (on stdin; empty: the current
                                     one) checked on the server; save keeps it
                                     in the keyring
  jellyfin-mcp shim-login URL USERNAME
                                     the password on stdin: signs the player
                                     (jellyfin-mpv-shim) in, then restarts it
  jellyfin-mcp shim-status | shim-logout

The server is JELLYFIN_URL; the API key is JELLYFIN_API_KEY, else the file
JELLYFIN_API_KEY_FILE names (`~/` allowed), else the keyring's
service=jellyfin-mcp secret (secret-tool; nixbook-shell's Settings saves it
there). JELLYFIN_USER picks the user whose library, progress and favourites
are used (by name), else the first administrator. An API key or a password
is never printed, logged, put in a tool result or on a command line.

Playback goes to a player through the server (a Play command it sends over
the player's websocket): by default this computer's jellyfin-mpv-shim (the
user service nixbook runs, mpv with the user's own mpv config), which
reports progress, marks watched and plays the next episode itself; Moonfin,
a TV or a browser when named (`session`). The players play exactly the
items they are sent, so a series, season, album, artist or playlist is
turned into its playable items here.
"""

import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid

VERSION = "0.1.0"
SERVER_NAME = "jellyfin-mcp"
PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]
# Looked up on PATH (the package adds libsecret after it; tests put stubs first).
SECRET_TOOL = "secret-tool"
SYSTEMCTL = "systemctl"
SECRET_ATTRS = ["service", "jellyfin-mcp"]
CLIENT_NAME = "nixbook-jellyfin-mcp"
SHIM_CLIENT = "Jellyfin MPV Shim"
SHIM_UNIT = os.environ.get("JELLYFIN_SHIM_UNIT") or "jellyfin-mpv-shim.service"
TICKS = 10_000_000
MAX_LIST = 50
MAX_QUEUE = 100
OVERVIEW_SHORT = 200
OVERVIEW_LONG = 1200
NOT_SET_UP = ("Jellyfin isn't set up: set its server and API key in Settings > Desktop agents > "
              "Apps it can use (or JELLYFIN_URL and JELLYFIN_API_KEY).")
NO_PLAYER = ("the player isn't connected: connect it in Settings > Desktop agents > Jellyfin "
             "(\"Connect the player\"), or open Moonfin")

TYPE_OUT = {
    "Movie": "movie", "Series": "series", "Season": "season", "Episode": "episode",
    "Audio": "song", "MusicAlbum": "album", "MusicArtist": "artist", "Playlist": "playlist",
    "BoxSet": "collection", "MusicVideo": "music video", "Video": "video", "Folder": "folder",
    "AudioBook": "audiobook", "Book": "book", "TvChannel": "channel",
}
TYPE_IN = {
    "movie": "Movie", "movies": "Movie", "film": "Movie", "films": "Movie",
    "series": "Series", "show": "Series", "shows": "Series", "tv": "Series",
    "episode": "Episode", "episodes": "Episode",
    "song": "Audio", "songs": "Audio", "audio": "Audio", "track": "Audio", "tracks": "Audio", "music": "Audio",
    "album": "MusicAlbum", "albums": "MusicAlbum",
    "artist": "MusicArtist", "artists": "MusicArtist",
    "playlist": "Playlist", "playlists": "Playlist",
    "collection": "BoxSet", "collections": "BoxSet",
    "music video": "MusicVideo", "video": "Video",
}
SEARCH_TYPES = ["Movie", "Series", "Episode", "Audio", "MusicAlbum", "MusicArtist"]
PLAYABLE = {"Movie", "Episode", "Audio", "MusicVideo", "Video", "AudioBook", "TvChannel"}
FIELDS = "Overview,Genres,ChildCount,RecursiveItemCount"


class JfError(Exception):
    """A failure reported to the agent as a tool error."""


class NotFound(JfError):
    pass


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
    path = os.path.join(base, "jellyfin-mcp")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def write_private(path, payload):
    """JSON written atomically, readable by this user only."""
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=4)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


# --------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------


def load_key():
    """(key, source): env, file, keyring, or ("", None)."""
    key = os.environ.get("JELLYFIN_API_KEY", "").strip()
    if key:
        return key, "env"
    path = os.environ.get("JELLYFIN_API_KEY_FILE", "").strip()
    if path:
        try:
            with open(os.path.expanduser(path), encoding="utf-8") as f:
                key = f.read().strip()
        except OSError:
            key = ""
        if key:
            return key, "file"
    try:
        found = subprocess.run([SECRET_TOOL, "lookup", *SECRET_ATTRS],
                               capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return "", None
    key = found.stdout.strip() if found.returncode == 0 else ""
    return (key, "keyring") if key else ("", None)


def clean_url(url):
    url = (url or "").strip().rstrip("/")
    if not url:
        return ""
    if not url.startswith(("http://", "https://")):
        raise JfError("the Jellyfin URL must start with http:// or https://")
    return url


# --------------------------------------------------------------------------
# The player: jellyfin-mpv-shim's own files ($XDG_CONFIG_HOME/jellyfin-mpv-shim)
# --------------------------------------------------------------------------
#
# conf.json: its settings (client_uuid: the device id of its default profile,
# player_name: the device name it reports). users.json (since 3.0; cred.json
# before, migrated into it on first run): {"active": profile id, "users":
# [{id, name, device_id, default, ..., credentials: [{address, Name, Id,
# Version, DateLastAccessed, UserId, AccessToken, Users, uuid, username}]}]}.
# A token belongs to the device that signed in, so the login below signs in
# with the shim's own client name, device name and device id.


def shim_dir():
    if os.environ.get("JELLYFIN_SHIM_CONFIG"):
        return os.environ["JELLYFIN_SHIM_CONFIG"]
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "jellyfin-mpv-shim")


def read_json(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def shim_identity():
    """{device_id, device_name, profile} of the shim's active profile, or
    None when it has never been configured."""
    conf = read_json(os.path.join(shim_dir(), "conf.json")) or {}
    users = read_json(os.path.join(shim_dir(), "users.json")) or {}
    player = conf.get("player_name") or socket.gethostname()
    profiles = users.get("users") if isinstance(users, dict) else None
    if profiles:
        active = next((u for u in profiles if u.get("id") == users.get("active")), profiles[0])
        name = player if active.get("default") else f"{player} ({active.get('name')})"
        return {"device_id": active.get("device_id") or conf.get("client_uuid"), "device_name": name,
                "profile": active}
    if conf.get("client_uuid"):
        return {"device_id": conf["client_uuid"], "device_name": player, "profile": None}
    return None


def shim_credential(url):
    """The shim's saved login for this server (its address), or None."""
    ident = shim_identity()
    creds = ((ident or {}).get("profile") or {}).get("credentials") or []
    want = (url or "").rstrip("/")
    for cred in creds:
        if cred.get("AccessToken") and str(cred.get("address", "")).rstrip("/") == want:
            return cred
    return None


def systemctl(*args, timeout=10):
    try:
        res = subprocess.run([SYSTEMCTL, "--user", *args], capture_output=True,
                             text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return res.returncode, res.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 127, ""


# --------------------------------------------------------------------------
# The Jellyfin API
# --------------------------------------------------------------------------


class Jellyfin:
    def __init__(self, url, key, user_name="", timeout=None):
        self.url = clean_url(url)
        self.key = key
        self.user_name = (user_name or "").strip()
        self.timeout = timeout or float(os.environ.get("JELLYFIN_TIMEOUT") or 10)
        self._user = None
        self._server_id = None
        device = f"{socket.gethostname()}:{os.getuid()}"
        self.device_id = hashlib.sha256(device.encode()).hexdigest()[:24]

    def hide(self, text):
        text = str(text)
        return text.replace(self.key, "***") if self.key else text

    def headers(self, auth=True, client=None):
        h = {"Accept": "application/json"}
        c = client or {"Client": CLIENT_NAME, "Device": socket.gethostname(), "DeviceId": self.device_id,
                       "Version": VERSION}
        fields = ", ".join(f'{k}="{str(v).replace(chr(34), "")}"' for k, v in c.items())
        if auth and self.key:
            # Jellyfin 10.11 reads only this one by default (X-Emby-Token is
            # legacy authorization, off unless turned on); Emby reads the other.
            h["Authorization"] = f'MediaBrowser {fields}, Token="{self.key}"'
            h["X-Emby-Token"] = self.key
        else:
            h["Authorization"] = f"MediaBrowser {fields}"
        return h

    def request(self, method, path, params=None, body=None, auth=True, client=None):
        if not self.url:
            raise JfError(NOT_SET_UP)
        if auth and not self.key:
            raise JfError(NOT_SET_UP)
        query = {k: v for k, v in (params or {}).items() if v is not None and v != ""}
        for k, v in list(query.items()):
            if isinstance(v, bool):
                query[k] = "true" if v else "false"
        full = self.url + path + ("?" + urllib.parse.urlencode(query) if query else "")
        data = None
        headers = self.headers(auth, client)
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        elif method == "POST":
            data = b""
        req = urllib.request.Request(full, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                raise JfError(f"Jellyfin refused the API key (HTTP {exc.code})") from None
            if exc.code in (404, 405):
                raise NotFound(f"Jellyfin has no {path.split('?')[0]} (HTTP {exc.code})") from None
            raise JfError(f"Jellyfin answered HTTP {exc.code} to {method} {path}") from None
        except (socket.timeout, TimeoutError):
            raise JfError(f"Jellyfin at {self.url} didn't answer within {self.timeout:g} s") from None
        except urllib.error.URLError as exc:
            raise JfError(self.hide(f"couldn't reach Jellyfin at {self.url}: {exc.reason}")) from None
        except OSError as exc:
            raise JfError(self.hide(f"couldn't reach Jellyfin at {self.url}: {exc}")) from None
        if not raw.strip():
            return None
        try:
            return json.loads(raw)
        except ValueError:
            raise JfError(f"{self.url} didn't answer in JSON: is it a Jellyfin server?") from None

    def compat(self, method, candidates, body=None):
        """The first of [(path, params)] the server has: Jellyfin 10.9+ moved
        the user's routes out of /Users/{id}; older servers and Emby only have
        those."""
        last = None
        for path, params in candidates:
            try:
                return self.request(method, path, params, body)
            except NotFound as exc:
                last = exc
        raise last

    # -- identity -----------------------------------------------------------

    def public_info(self):
        info = self.request("GET", "/System/Info/Public", auth=False) or {}
        if not isinstance(info, dict) or not (info.get("Id") or info.get("ServerName")):
            raise JfError(f"{self.url} doesn't look like a Jellyfin server")
        self._server_id = info.get("Id")
        return info

    def server_id(self):
        if self._server_id is None:
            try:
                self.public_info()
            except JfError:
                self._server_id = ""
        return self._server_id

    def _user_cache(self):
        tag = hashlib.sha256(f"{self.url}\0{self.user_name}\0{self.key}".encode()).hexdigest()[:20]
        return os.path.join(runtime_dir(), f"user-{tag}.json")

    def user(self):
        """{Id, Name} of the user it acts for; remembered a day in the
        runtime directory (the fast path makes one call fewer)."""
        if self._user:
            return self._user
        try:
            cached = read_json(self._user_cache())
        except OSError:
            cached = None
        if isinstance(cached, dict) and cached.get("Id") and time.time() - cached.get("time", 0) < 86400:
            self._user = {"Id": cached["Id"], "Name": cached.get("Name", "")}
            return self._user
        try:
            users = self.request("GET", "/Users") or []
        except JfError as exc:
            if "refused" not in str(exc):
                raise
            # A user's own token (not an API key) may not list the users.
            me = self.request("GET", "/Users/Me")
            users = [me] if me else []
        if not users:
            raise JfError("Jellyfin has no users")
        if self.user_name:
            wanted = self.user_name.casefold()
            match = [u for u in users if str(u.get("Name", "")).casefold() == wanted]
            if not match:
                raise JfError(f"Jellyfin has no user named {self.user_name!r}")
            chosen = match[0]
        else:
            admins = [u for u in users if (u.get("Policy") or {}).get("IsAdministrator")]
            chosen = (admins or users)[0]
        self._user = {"Id": chosen["Id"], "Name": chosen.get("Name", "")}
        try:
            write_private(self._user_cache(), {**self._user, "time": time.time()})
        except OSError:
            pass
        return self._user

    def uid(self):
        return self.user()["Id"]

    # -- library ------------------------------------------------------------

    def items(self, params):
        uid = self.uid()
        base = {"Fields": FIELDS, "EnableUserData": True, "EnableImages": False, **params}
        return self.compat("GET", [("/Items", {"userId": uid, **base}),
                                   (f"/Users/{uid}/Items", base)]) or {}

    def item(self, item_id):
        uid = self.uid()
        try:
            return self.compat("GET", [(f"/Items/{q(item_id)}", {"userId": uid}),
                                       (f"/Users/{uid}/Items/{q(item_id)}", {})])
        except NotFound:
            raise JfError(f"no Jellyfin item with id {item_id!r} (search first)") from None

    def episodes(self, series_id, season_id=None):
        res = self.request("GET", f"/Shows/{q(series_id)}/Episodes", {
            "userId": self.uid(), "seasonId": season_id, "Fields": FIELDS,
            "EnableUserData": True, "EnableImages": False}) or {}
        return res.get("Items") or []

    def next_up(self, limit, series_id=None):
        res = self.request("GET", "/Shows/NextUp", {
            "userId": self.uid(), "Limit": limit, "seriesId": series_id, "Fields": FIELDS,
            "EnableUserData": True, "EnableImages": False}) or {}
        return res.get("Items") or []

    def web_url(self, item_id):
        sid = self.server_id()
        return f"{self.url}/web/#/details?id={item_id}" + (f"&serverId={sid}" if sid else "")

    # -- sessions -----------------------------------------------------------

    def sessions(self):
        res = self.request("GET", "/Sessions", {"activeWithinSeconds": 960}) or []
        return [s for s in res if s.get("Client") != CLIENT_NAME and s.get("DeviceId") != self.device_id]


def q(value):
    return urllib.parse.quote(str(value), safe="")


# --------------------------------------------------------------------------
# Formatting
# --------------------------------------------------------------------------


def clock(ticks):
    secs = int((ticks or 0) // TICKS)
    h, rest = divmod(secs, 3600)
    m, s = divmod(rest, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def duration(ticks):
    mins = round((ticks or 0) / TICKS / 60)
    if mins < 60:
        return f"{mins} min"
    return f"{mins // 60}h {mins % 60:02d}m"


def short(text, limit):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def brief(it, overview=OVERVIEW_SHORT):
    kind = it.get("Type", "")
    out = {"id": it.get("Id"), "type": TYPE_OUT.get(kind, kind.lower()), "name": it.get("Name")}
    if it.get("ProductionYear"):
        out["year"] = it["ProductionYear"]
    if kind == "Episode":
        if it.get("SeriesName"):
            out["series"] = it["SeriesName"]
        if it.get("ParentIndexNumber") is not None:
            out["season"] = it["ParentIndexNumber"]
        if it.get("IndexNumber") is not None:
            out["episode"] = it["IndexNumber"]
    if kind == "Audio":
        artists = it.get("Artists") or ([it["AlbumArtist"]] if it.get("AlbumArtist") else [])
        if artists:
            out["artists"] = artists[:5]
        if it.get("Album"):
            out["album"] = it["Album"]
    if kind == "MusicAlbum" and it.get("AlbumArtist"):
        out["artist"] = it["AlbumArtist"]
    if it.get("RunTimeTicks") and kind not in ("Series", "MusicArtist", "Playlist", "BoxSet"):
        out["runtime"] = duration(it["RunTimeTicks"])
    ud = it.get("UserData") or {}
    if kind in PLAYABLE or kind in ("Series", "Season"):
        out["played"] = bool(ud.get("Played"))
    if ud.get("PlaybackPositionTicks"):
        out["resume_at"] = clock(ud["PlaybackPositionTicks"])
        if ud.get("PlayedPercentage") is not None:
            out["progress"] = f"{round(ud['PlayedPercentage'])}%"
    if kind in ("Series", "Season") and ud.get("UnplayedItemCount") is not None:
        out["unplayed"] = ud["UnplayedItemCount"]
    if ud.get("IsFavorite"):
        out["favorite"] = True
    if overview and it.get("Overview"):
        out["overview"] = short(it["Overview"], overview)
    return out


def title_of(it):
    """"Cyberpunk: Edgerunners, S01E01", "Dune (2021)", a song's name."""
    if it.get("Type") == "Episode":
        s, e = it.get("ParentIndexNumber"), it.get("IndexNumber")
        code = f"S{s:02d}E{e:02d}" if isinstance(s, int) and isinstance(e, int) else it.get("Name", "")
        return f"{it.get('SeriesName') or it.get('Name')}, {code}"
    if it.get("Type") == "Movie" and it.get("ProductionYear"):
        return f"{it.get('Name')} ({it['ProductionYear']})"
    return it.get("Name") or "?"


def is_moonfin(s):
    return "moonfin" in f"{s.get('Client', '')} {s.get('DeviceName', '')}".casefold()


def is_shim(s):
    return s.get("Client") == SHIM_CLIENT


def is_local_shim(s, ident=None):
    ident = ident if ident is not None else shim_identity()
    return is_shim(s) and bool(ident) and s.get("DeviceId") == ident.get("device_id")


def session_out(s, uid=None, ident=None):
    out = {
        "id": s.get("Id"),
        "client": s.get("Client"),
        "device": s.get("DeviceName"),
        "user": s.get("UserName"),
        "remote_control": bool(s.get("SupportsRemoteControl")),
    }
    if uid and s.get("UserId") and s.get("UserId") != uid:
        out["other_user"] = True
    if is_local_shim(s, ident):
        out["this_computer"] = True
    if is_moonfin(s):
        out["moonfin"] = True
    playing = s.get("NowPlayingItem")
    if playing:
        state = s.get("PlayState") or {}
        now = brief(playing, overview=0)
        now.pop("played", None)
        pos = state.get("PositionTicks")
        if pos is not None:
            now["position"] = clock(pos) + (f" / {clock(playing['RunTimeTicks'])}" if playing.get("RunTimeTicks") else "")
        now["paused"] = bool(state.get("IsPaused"))
        out["now_playing"] = now
    if s.get("LastActivityDate"):
        out["last_active"] = s["LastActivityDate"]
    return out


def supported_commands(s):
    caps = s.get("Capabilities") or {}
    return set(s.get("SupportedCommands") or caps.get("SupportedCommands") or [])


# --------------------------------------------------------------------------
# Choosing a player, playing
# --------------------------------------------------------------------------


def ensure_shim(jf):
    """This computer's shim session, after starting (or restarting) its
    service when it is signed in to this server but not connected; (session,
    why)."""
    if not shim_credential(jf.url):
        return None, NO_PLAYER
    code, state = systemctl("is-active", SHIM_UNIT)
    systemctl("restart" if state == "active" else "start", SHIM_UNIT, timeout=15)
    deadline = time.monotonic() + float(os.environ.get("JELLYFIN_SHIM_WAIT") or 5)
    ident = shim_identity()
    while time.monotonic() < deadline:
        time.sleep(0.25)
        for s in jf.sessions():
            if is_local_shim(s, ident) and s.get("SupportsRemoteControl"):
                return s, None
    code, state = systemctl("is-active", SHIM_UNIT)
    return None, (f"the player (jellyfin-mpv-shim) didn't connect to Jellyfin (its service is {state or 'unknown'}): "
                  "see `journalctl --user -u jellyfin-mpv-shim`, or connect it again in Settings > Desktop agents > Jellyfin")


def pick_session(jf, wanted, playing=False):
    """(session, None) or (None, why). Named: that one. Else for playing
    something new, this computer's player (jellyfin-mpv-shim; started if it
    is signed in but not connected), else the user's own controllable
    clients, Moonfin first; for controlling (playing=True), first the one
    that plays something."""
    uid = jf.uid()
    sessions = jf.sessions()
    ident = shim_identity()
    if wanted:
        w = str(wanted).strip().casefold()
        match = [s for s in sessions if str(s.get("Id", "")).casefold() == w]
        if not match and w in ("mpv", "shim", "player", "this computer", "here"):
            match = [s for s in sessions if is_local_shim(s, ident)]
            if not match:
                return ensure_shim(jf)
        if not match:
            match = [s for s in sessions
                     if w in f"{s.get('Client', '')} {s.get('DeviceName', '')}".casefold()]
        if not match:
            names = sorted({f"{s.get('Client')} on {s.get('DeviceName')}" for s in sessions})
            return None, f"no connected player matches {wanted!r}" + (f" (connected: {', '.join(names[:10])})" if names else "")
        ok = [s for s in match if s.get("SupportsRemoteControl")]
        if not ok:
            s = match[0]
            return None, f"{s.get('Client')} on {s.get('DeviceName')} doesn't accept remote control"
        return best(ok, playing, ident), None
    ok = [s for s in sessions if s.get("SupportsRemoteControl")]
    # Other people's screens only when named.
    mine = [s for s in ok if not s.get("UserId") or s.get("UserId") == uid or is_local_shim(s, ident)]
    if playing:
        busy = [s for s in mine if s.get("NowPlayingItem")]
        if busy:
            return best(busy, True, ident), None
    local = [s for s in mine if is_local_shim(s, ident)]
    if local:
        return local[0], None
    if not playing and shim_credential(jf.url):
        found, why = ensure_shim(jf)
        if found:
            return found, None
        if not mine:
            return None, why
    if mine:
        return best(mine, playing, ident), None
    if ok:
        return None, "no player of yours accepts remote control (others' must be named with session)"
    return None, NO_PLAYER


def best(sessions, playing, ident):
    def rank(s):
        return (bool(s.get("NowPlayingItem")) if playing else False, is_local_shim(s, ident),
                is_moonfin(s), s.get("LastActivityDate") or "")
    return max(sessions, key=rank)


def playable(jf, it):
    """(item ids to send, start ticks of the first)."""
    kind = it.get("Type")

    def resume(x):
        return (x.get("UserData") or {}).get("PlaybackPositionTicks") or 0

    if kind in PLAYABLE:
        return [it["Id"]], resume(it)
    if kind in ("Series", "Season"):
        series = it["Id"] if kind == "Series" else (it.get("SeriesId") or it.get("ParentId"))
        eps = jf.episodes(series, None if kind == "Series" else it["Id"])
        if not eps:
            raise JfError(f"{it.get('Name')} has no episodes")
        start = 0
        if kind == "Series":
            nxt = jf.next_up(1, series)
            if nxt:
                ids = [e["Id"] for e in eps]
                start = ids.index(nxt[0]["Id"]) if nxt[0]["Id"] in ids else 0
        else:
            unplayed = [i for i, e in enumerate(eps) if not (e.get("UserData") or {}).get("Played")]
            start = unplayed[0] if unplayed else 0
        chosen = eps[start:start + MAX_QUEUE]
        return [e["Id"] for e in chosen], resume(chosen[0])
    if kind == "MusicArtist":
        res = jf.items({"ArtistIds": it["Id"], "IncludeItemTypes": "Audio", "Recursive": True,
                        "SortBy": "ProductionYear,Album,ParentIndexNumber,IndexNumber", "Limit": MAX_QUEUE})
    elif kind in ("MusicAlbum", "Playlist", "BoxSet", "Folder"):
        params = {"ParentId": it["Id"], "Recursive": True, "Limit": MAX_QUEUE,
                  "IncludeItemTypes": "Audio,Movie,Episode,MusicVideo,Video"}
        if kind == "MusicAlbum":
            params["SortBy"] = "ParentIndexNumber,IndexNumber,SortName"
        res = jf.items(params)
    else:
        raise JfError(f"a {TYPE_OUT.get(kind, kind)} can't be played")
    ids = [c["Id"] for c in res.get("Items") or []]
    if not ids:
        raise JfError(f"{it.get('Name')} holds nothing playable")
    return ids, 0


def send_play(jf, session, ids, start_ticks, mode="PlayNow", resume=True):
    params = {"playCommand": mode, "itemIds": ",".join(ids)}
    if mode == "PlayNow":
        params["startIndex"] = 0
        if start_ticks and resume:
            params["startPositionTicks"] = int(start_ticks)
    jf.request("POST", f"/Sessions/{q(session['Id'])}/Playing", params)
    return params.get("startPositionTicks")


# --------------------------------------------------------------------------
# Tools
# --------------------------------------------------------------------------

TOOLS = {}


def tool(name, description, props=None, required=(), read_only=False, idempotent=None, title=None):
    def register(fn):
        TOOLS[name] = {
            "fn": fn,
            "spec": {
                "name": name,
                "title": title or name.replace("_", " ").capitalize(),
                "description": description,
                "inputSchema": {"type": "object", "properties": props or {},
                                "required": list(required), "additionalProperties": False},
                "annotations": {
                    "readOnlyHint": read_only,
                    "destructiveHint": False,
                    "idempotentHint": read_only if idempotent is None else idempotent,
                    "openWorldHint": False,
                },
            },
        }
        return fn
    return register


def limit_of(args, default):
    try:
        n = int(args.get("limit") or default)
    except (TypeError, ValueError):
        raise JfError("limit must be a number") from None
    return max(1, min(n, MAX_LIST))


def need(args, key):
    value = args.get(key)
    if value is None or (isinstance(value, str) and not value.strip()):
        raise JfError(f"{key} is required")
    return value.strip() if isinstance(value, str) else value


def types_of(values):
    if values is None:
        return SEARCH_TYPES
    if isinstance(values, str):
        values = [v for v in values.replace(",", " ").split() if v]
    out = []
    for v in values:
        t = TYPE_IN.get(str(v).strip().casefold())
        if not t:
            raise JfError(f"unknown type {v!r}: movie, series, episode, song, album, artist")
        if t not in out:
            out.append(t)
    return out or SEARCH_TYPES


TYPE_ENUM = ["movie", "series", "episode", "song", "album", "artist", "playlist", "collection"]
LIMIT = {"type": "integer", "minimum": 1, "maximum": MAX_LIST}
SESSION = {"type": "string", "description": "A player: \"mpv\" (this computer's, the default), a client or device name (\"Moonfin\", \"Living room TV\") or a session id."}


@tool("search", "Search the Jellyfin library: films, series, episodes, songs, albums, artists. Returns ids for item/play.",
      {"query": {"type": "string"},
       "types": {"type": "array", "items": {"type": "string", "enum": TYPE_ENUM}, "description": "Default: all six main kinds."},
       "limit": LIMIT},
      required=["query"], read_only=True)
def t_search(jf, args):
    query = need(args, "query")
    res = jf.items({"searchTerm": query, "IncludeItemTypes": ",".join(types_of(args.get("types"))),
                    "Recursive": True, "Limit": limit_of(args, 20)})
    items = [brief(i) for i in res.get("Items") or []]
    return {"total": res.get("TotalRecordCount", len(items)), "items": items}


@tool("item", "One item's details. A series also lists its seasons and next episode; a season, album, artist, playlist or collection lists what it holds.",
      {"id": {"type": "string"}}, required=["id"], read_only=True)
def t_item(jf, args):
    it = jf.item(need(args, "id"))
    out = brief(it, overview=OVERVIEW_LONG)
    kind = it.get("Type")
    for key, name in (("Genres", "genres"), ("CommunityRating", "rating"), ("OfficialRating", "age_rating"),
                      ("PremiereDate", "premiere")):
        if it.get(key):
            out[name] = it[key][:5] if isinstance(it[key], list) else it[key]
    people = it.get("People") or []
    if people:
        out["directors"] = [p["Name"] for p in people if p.get("Type") == "Director"][:3]
        out["cast"] = [p["Name"] for p in people if p.get("Type") == "Actor"][:6]
    if kind == "Series":
        seasons = jf.request("GET", f"/Shows/{q(it['Id'])}/Seasons",
                             {"userId": jf.uid(), "EnableUserData": True, "Fields": FIELDS}) or {}
        out["seasons"] = [{k: v for k, v in brief(s, overview=0).items() if k != "type"}
                          for s in (seasons.get("Items") or [])[:MAX_LIST]]
        nxt = jf.next_up(1, it["Id"])
        if nxt:
            out["next_up"] = brief(nxt[0], overview=0)
    elif kind == "Season":
        eps = jf.episodes(it.get("SeriesId") or it.get("ParentId"), it["Id"])
        out["episodes"] = [brief(e, overview=100) for e in eps[:MAX_LIST]]
    elif kind == "MusicArtist":
        res = jf.items({"ArtistIds": it["Id"], "IncludeItemTypes": "MusicAlbum", "Recursive": True,
                        "SortBy": "ProductionYear,SortName", "Limit": MAX_LIST})
        out["albums"] = [brief(a, overview=0) for a in res.get("Items") or []]
    elif kind in ("MusicAlbum", "Playlist", "BoxSet", "Folder"):
        params = {"ParentId": it["Id"], "Limit": MAX_LIST}
        if kind == "MusicAlbum":
            params["SortBy"] = "ParentIndexNumber,IndexNumber,SortName"
        res = jf.items(params)
        out["items"] = [brief(c, overview=0) for c in res.get("Items") or []]
        out["count"] = res.get("TotalRecordCount", len(out["items"]))
    out["web_url"] = jf.web_url(it["Id"])
    return out


@tool("continue_watching", "What you started watching and didn't finish, newest first, with where you stopped.",
      {"limit": LIMIT}, read_only=True)
def t_continue(jf, args):
    uid = jf.uid()
    params = {"Limit": limit_of(args, 12), "MediaTypes": "Video", "Fields": FIELDS,
              "EnableUserData": True, "EnableImages": False}
    res = jf.compat("GET", [("/UserItems/Resume", {"userId": uid, **params}),
                            (f"/Users/{uid}/Items/Resume", params)]) or {}
    return {"items": [brief(i) for i in res.get("Items") or []]}


@tool("next_up", "The next episode to watch of each series you're following (or of one series).",
      {"limit": LIMIT, "series_id": {"type": "string"}}, read_only=True)
def t_next_up(jf, args):
    return {"items": [brief(i) for i in jf.next_up(limit_of(args, 12), args.get("series_id") or None)]}


@tool("recently_added", "The newest additions to the library, optionally of one kind.",
      {"type": {"type": "string", "enum": TYPE_ENUM}, "limit": LIMIT}, read_only=True)
def t_recent(jf, args):
    uid = jf.uid()
    params = {"Limit": limit_of(args, 15), "Fields": FIELDS, "EnableUserData": True, "EnableImages": False}
    if args.get("type"):
        params["IncludeItemTypes"] = ",".join(types_of([args["type"]]))
    res = jf.compat("GET", [("/Items/Latest", {"userId": uid, **params}),
                            (f"/Users/{uid}/Items/Latest", params)]) or []
    if isinstance(res, dict):
        res = res.get("Items") or []
    return {"items": [brief(i) for i in res[:MAX_LIST]]}


@tool("sessions", "The players connected to Jellyfin (this computer's mpv player, Moonfin, TVs, browsers): what each plays, and whether it accepts remote control (play/control).",
      read_only=True)
def t_sessions(jf, args):
    uid = jf.uid()
    ident = shim_identity()
    sessions = sorted(jf.sessions(), key=lambda s: s.get("LastActivityDate") or "", reverse=True)
    out = {"sessions": [session_out(s, uid, ident) for s in sessions[:MAX_LIST]]}
    if not any(is_local_shim(s, ident) for s in sessions):
        out["this_computer"] = ("the player is signed in but not connected (play starts it)"
                                if shim_credential(jf.url) else NO_PLAYER)
    return out


@tool("play", "Play an item (film, episode, song, or a whole series, season, album, artist, playlist): by default in mpv on this computer (fullscreen; it saves progress and plays the next episode itself); on Moonfin or a TV when named in session. A series starts at its next episode; a film or episode where you stopped.",
      {"item_id": {"type": "string"}, "session": SESSION,
       "mode": {"type": "string", "enum": ["now", "next", "last"], "description": "now (default), or add to the queue: next / last"},
       "resume": {"type": "boolean", "description": "Start where you stopped (default true)"}},
      required=["item_id"], title="Play on a player")
def t_play(jf, args):
    it = jf.item(need(args, "item_id"))
    ids, start_ticks = playable(jf, it)
    session, why = pick_session(jf, args.get("session"))
    if not session:
        return {"played": False, "reason": why, "item": brief(it, overview=0), "web_url": jf.web_url(it["Id"]),
                "hint": "No player could take it: tell the user why (reason), or open web_url in the browser."}
    mode = {"now": "PlayNow", "next": "PlayNext", "last": "PlayLast"}.get(str(args.get("mode") or "now"))
    if not mode:
        raise JfError("mode must be now, next or last")
    started = send_play(jf, session, ids, start_ticks, mode, args.get("resume", True) is not False)
    on = session_out(session, jf.uid())
    on.pop("now_playing", None)
    out = {"played": mode == "PlayNow", "queued": mode != "PlayNow", "on": on,
           "item": brief(it, overview=0), "items_sent": len(ids)}
    if started:
        out["from"] = clock(started)
    return out


PLAYSTATE = {"pause": "Pause", "unpause": "Unpause", "resume": "Unpause", "toggle": "PlayPause",
             "stop": "Stop", "next": "NextTrack", "previous": "PreviousTrack"}
GENERAL = {"volume_up": "VolumeUp", "volume_down": "VolumeDown", "mute": "Mute", "unmute": "Unmute",
           "fullscreen": "ToggleFullscreen"}
ACTIONS = ["pause", "unpause", "toggle", "stop", "next", "previous", "seek", "forward", "back",
           "volume", "volume_up", "volume_down", "mute", "unmute", "fullscreen"]


@tool("control", "Control what a player plays (the one playing, else this computer's mpv): pause, unpause, toggle, stop, next (episode), previous, seek to seconds, forward/back by seconds, volume (level 0-100), volume_up/down, mute, unmute, fullscreen.",
      {"action": {"type": "string", "enum": ACTIONS}, "session": SESSION,
       "seconds": {"type": "number", "minimum": 0, "description": "seek: the position; forward/back: how far (default 30/10)"},
       "level": {"type": "integer", "minimum": 0, "maximum": 100, "description": "volume: 0-100"}},
      required=["action"], title="Control playback")
def t_control(jf, args):
    action = str(need(args, "action")).casefold()
    if action not in ACTIONS and action not in PLAYSTATE:
        raise JfError(f"unknown action {action!r}: {', '.join(ACTIONS)}")
    session, why = pick_session(jf, args.get("session"), playing=True)
    if not session:
        raise JfError(why)
    sid = q(session["Id"])
    state = session.get("PlayState") or {}
    done = {"done": action, "on": {k: v for k, v in session_out(session, jf.uid()).items()
                                   if k in ("id", "client", "device", "user")}}

    def needs_playing():
        if not session.get("NowPlayingItem"):
            raise JfError(f"{session.get('Client')} on {session.get('DeviceName')} isn't playing anything")

    if action in PLAYSTATE:
        if action != "stop":
            needs_playing()
        jf.request("POST", f"/Sessions/{sid}/Playing/{PLAYSTATE[action]}")
        return done
    if action in ("seek", "forward", "back"):
        needs_playing()
        seconds = args.get("seconds")
        if action == "seek":
            if seconds is None:
                raise JfError("seek needs seconds (the position to go to)")
            target = float(seconds) * TICKS
        else:
            step = float(seconds if seconds is not None else (30 if action == "forward" else 10)) * TICKS
            pos = state.get("PositionTicks") or 0
            target = pos + step if action == "forward" else max(0, pos - step)
        runtime = (session.get("NowPlayingItem") or {}).get("RunTimeTicks")
        if runtime:
            target = min(target, max(0, runtime - TICKS))
        jf.request("POST", f"/Sessions/{sid}/Playing/Seek", {"seekPositionTicks": int(target)})
        done["position"] = clock(target)
        return done
    supported = supported_commands(session)
    name = "SetVolume" if action == "volume" else GENERAL[action]
    if supported and name not in supported:
        raise JfError(f"{session.get('Client')} doesn't support {action}")
    if action == "volume":
        level = args.get("level")
        if level is None:
            raise JfError("volume needs level (0-100)")
        level = max(0, min(100, int(level)))
        jf.request("POST", f"/Sessions/{sid}/Command", body={"Name": "SetVolume", "Arguments": {"Volume": str(level)}})
        done["level"] = level
        return done
    jf.request("POST", f"/Sessions/{sid}/Command/{name}")
    return done


@tool("mark_played", "Mark an item (film, episode, a whole season or series) watched, or not watched.",
      {"id": {"type": "string"}, "played": {"type": "boolean"}}, required=["id", "played"], idempotent=True)
def t_mark_played(jf, args):
    item_id = need(args, "id")
    played = args.get("played") is not False
    uid = jf.uid()
    method = "POST" if played else "DELETE"
    try:
        jf.compat(method, [(f"/UserPlayedItems/{q(item_id)}", {"userId": uid}),
                           (f"/Users/{uid}/PlayedItems/{q(item_id)}", {})])
    except NotFound:
        raise JfError(f"no Jellyfin item with id {item_id!r}") from None
    return {"id": item_id, "played": played}


@tool("favorite", "Add an item to your Jellyfin favourites, or remove it.",
      {"id": {"type": "string"}, "on": {"type": "boolean"}}, required=["id", "on"], idempotent=True)
def t_favorite(jf, args):
    item_id = need(args, "id")
    on = args.get("on") is not False
    uid = jf.uid()
    method = "POST" if on else "DELETE"
    try:
        jf.compat(method, [(f"/UserFavoriteItems/{q(item_id)}", {"userId": uid}),
                           (f"/Users/{uid}/FavoriteItems/{q(item_id)}", {})])
    except NotFound:
        raise JfError(f"no Jellyfin item with id {item_id!r}") from None
    return {"id": item_id, "favorite": on}


def list_playlists(jf):
    res = jf.items({"IncludeItemTypes": "Playlist", "Recursive": True, "SortBy": "SortName", "Limit": MAX_LIST})
    return res.get("Items") or []


@tool("playlists", "Your Jellyfin playlists.", read_only=True)
def t_playlists(jf, args):
    return {"playlists": [{"id": p.get("Id"), "name": p.get("Name"),
                           "items": p.get("ChildCount", p.get("RecursiveItemCount")),
                           "media": p.get("MediaType")} for p in list_playlists(jf)]}


@tool("playlist_add", "Add an item to one of your playlists (by playlist name or id).",
      {"playlist": {"type": "string"}, "item_id": {"type": "string"}}, required=["playlist", "item_id"])
def t_playlist_add(jf, args):
    wanted = need(args, "playlist")
    item_id = need(args, "item_id")
    lists = list_playlists(jf)
    match = [p for p in lists if p.get("Id") == wanted] or \
        [p for p in lists if str(p.get("Name", "")).casefold() == wanted.casefold()] or \
        [p for p in lists if wanted.casefold() in str(p.get("Name", "")).casefold()]
    if not match:
        names = [p.get("Name") for p in lists][:20]
        raise JfError(f"no playlist named {wanted!r}" + (f" (yours: {', '.join(names)})" if names else " (you have none)"))
    if len(match) > 1:
        raise JfError(f"several playlists match {wanted!r}: {', '.join(p.get('Name') for p in match[:10])}")
    playlist = match[0]
    it = jf.item(item_id)
    jf.request("POST", f"/Playlists/{q(playlist['Id'])}/Items", {"ids": it["Id"], "userId": jf.uid()})
    return {"added": brief(it, overview=0), "playlist": {"id": playlist["Id"], "name": playlist.get("Name")}}


# --------------------------------------------------------------------------
# The fast path: "play edgerunners season 2 episode 1", no model
# --------------------------------------------------------------------------

LEAD = re.compile(
    r"^(?:(?:please|can you|could you|peux-tu|tu peux|bitte|kannst du|h[aã]y|l[aà]m [oơ]n)\s+)*"
    r"(?:play|watch|put on|start|stream|lance|mets|regarde|joue|spiel(?:e)?|schau(?:e)?(?: mir)?|"
    r"zeig(?:e)?(?: mir)?|xem|m[oở]|ph[aá]t|b[aậ]t|cho (?:t[oô]i|m[iì]nh|em) xem)\s+", re.I)
TRAIL = re.compile(r"\s+(?:ab|an|please|bitte|merci|stp|svp|nh[eé]|nha|[dđ]i|for me|pour moi)$", re.I)
SXE = [
    re.compile(r"\bs(?:eason)?\s?(\d{1,2})\s?e(?:p(?:isode)?)?\s?(\d{1,3})\b", re.I),
    re.compile(r"\b(\d{1,2})x(\d{1,3})\b", re.I),
]
SEASON = re.compile(r"\b(?:season|saison|staffel|m[uù]a)\s+(\d{1,2})\b", re.I)
EPISODE = re.compile(r"\b(?:episode|[eé]pisode|ep|folge|t[aậ]p)\s+(\d{1,3})\b", re.I)
FILLER = {"the", "a", "an", "le", "la", "les", "l", "de", "du", "des", "un", "une", "der", "die", "das", "den",
          "dem", "ein", "eine", "phim", "bo", "film", "movie", "series", "show", "serie", "of", "von", "on", "in",
          "mpv", "jellyfin"}

MSG = {
    "en": {"playing": "Playing {title}.", "queued": "Playing {title} on {player}.",
           "seasons": "{series} has only {n} season{s}.", "episodes": "{series} season {season} has only {n} episode{s}.",
           "notfound": "I couldn't find {query} in Jellyfin.", "which": "Which one: {list}?",
           "noplayer": "The player isn't connected: connect it in Settings > Desktop agents > Jellyfin.",
           "error": "Jellyfin: {error}.", "setup": "Jellyfin isn't set up: see Settings > Desktop agents."},
    "fr": {"playing": "Je lance {title}.", "queued": "Je lance {title} sur {player}.",
           "seasons": "{series} n'a que {n} saison{s}.", "episodes": "La saison {season} de {series} n'a que {n} épisode{s}.",
           "notfound": "Je n'ai pas trouvé {query} dans Jellyfin.", "which": "Lequel : {list} ?",
           "noplayer": "Le lecteur n'est pas connecté : connecte-le dans Paramètres > Agents du bureau > Jellyfin.",
           "error": "Jellyfin : {error}.", "setup": "Jellyfin n'est pas configuré : voir Paramètres > Agents du bureau."},
    "de": {"playing": "Ich spiele {title} ab.", "queued": "Ich spiele {title} auf {player} ab.",
           "seasons": "{series} hat nur {n} Staffel{s}.", "episodes": "Staffel {season} von {series} hat nur {n} Folge{s}.",
           "notfound": "Ich habe {query} in Jellyfin nicht gefunden.", "which": "Welches: {list}?",
           "noplayer": "Der Player ist nicht verbunden: verbinde ihn unter Einstellungen > Desktop-Agenten > Jellyfin.",
           "error": "Jellyfin: {error}.", "setup": "Jellyfin ist nicht eingerichtet: siehe Einstellungen > Desktop-Agenten."},
    "vi": {"playing": "Đang phát {title}.", "queued": "Đang phát {title} trên {player}.",
           "seasons": "{series} chỉ có {n} mùa.", "episodes": "Mùa {season} của {series} chỉ có {n} tập.",
           "notfound": "Không tìm thấy {query} trong Jellyfin.", "which": "Phim nào: {list}?",
           "noplayer": "Trình phát chưa kết nối: kết nối trong Cài đặt > Tác nhân máy tính > Jellyfin.",
           "error": "Jellyfin: {error}.", "setup": "Jellyfin chưa được thiết lập: xem Cài đặt > Tác nhân máy tính."},
}
PLURAL = {"en": "s", "fr": "s", "de": "n", "vi": ""}
OR = {"en": " or ", "fr": " ou ", "de": " oder ", "vi": " hay "}


def fold(text):
    s = unicodedata.normalize("NFKD", str(text or "")).replace("đ", "d").replace("Đ", "D").replace("ß", "ss")
    s = "".join(c for c in s if not unicodedata.combining(c)).casefold()
    return " ".join(re.sub(r"[^\w]+", " ", s).split())


def words(text):
    return [w for w in fold(text).split() if w not in FILLER]


VI_LETTERS = re.compile("[ăđơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]")


def guess_lang(text):
    raw = str(text or "").casefold()
    t = f" {fold(text)} "
    if VI_LETTERS.search(raw) or re.search(r" (xem|phat|mua|tap|cho toi) ", t):
        return "vi"
    if re.search(r" (lance|mets|regarde|joue|saison) ", t) or "épisode" in raw:
        return "fr"
    if re.search(r" (spiel|spiele|schau|schaue|zeig|staffel|folge) ", t):
        return "de"
    return "en"


def parse_query(text, season=None, episode=None):
    """(title words, season, episode) from what was said."""
    t = " ".join(str(text or "").split()).strip().rstrip(".!?")
    t = LEAD.sub("", t)
    t = TRAIL.sub("", t)
    for rx in SXE:
        m = rx.search(t)
        if m:
            season = season or int(m.group(1))
            episode = episode or int(m.group(2))
            t = rx.sub(" ", t)
            break
    m = SEASON.search(t)
    if m:
        season = season or int(m.group(1))
        t = SEASON.sub(" ", t)
    m = EPISODE.search(t)
    if m:
        episode = episode or int(m.group(1))
        t = EPISODE.sub(" ", t)
    t = re.sub(r"\s+(?:,|and|et|und|v[aà])\s*$", "", t.strip(" ,"))
    return t.strip(" ,-"), season, episode


def match_score(query_words, name):
    """How well the words said name it: 1 exact; the words said found in it
    (a word's start counts: "edgerunner" in "Edgerunners"), weighted 3:1
    against how much of the name was said."""
    n = words(name)
    qw = query_words
    if not qw or not n:
        return 0.0
    if qw == n:
        return 1.0

    def tok(a, b):
        if a == b:
            return 1.0
        if min(len(a), len(b)) >= 3 and (a.startswith(b) or b.startswith(a)):
            return 0.9
        return 0.0
    q_cov = sum(max(tok(a, b) for b in n) for a in qw) / len(qw)
    n_cov = sum(max(tok(b, a) for a in qw) for b in n) / len(n)
    return round(0.75 * q_cov + 0.25 * n_cov, 3)


def find_title(jf, title, want_series, strict):
    """(best item, [close candidates]) by its title: one search call (and a
    second, with the longest word only, when the whole title finds
    nothing)."""
    qw = words(title)
    if not qw:
        return None, []
    types = "Series" if want_series else "Movie,Series,Episode"
    tried = []
    for term in (" ".join(qw), max(qw, key=len)):
        if term in tried:
            continue
        tried.append(term)
        res = jf.items({"searchTerm": term, "IncludeItemTypes": types, "Recursive": True, "Limit": 12,
                        "Fields": "ProductionYear", "EnableUserData": True})
        found = res.get("Items") or []
        if found:
            break
    kind_bonus = {"Series": 0.02, "Movie": 0.02, "Episode": 0.0}
    scored = sorted(((match_score(qw, i.get("Name", "")) + kind_bonus.get(i.get("Type"), 0), i) for i in found),
                    key=lambda x: -x[0])
    threshold = 0.82 if strict else 0.6
    good = [(s, i) for s, i in scored if s >= threshold]
    if not good:
        return None, []
    top = good[0][0]
    close = [i for s, i in good if top - s <= 0.03]
    distinct = {(fold(i.get("Name")), i.get("ProductionYear"), i.get("Type")) for i in close}
    if len(distinct) > 1:
        return None, close[:3]
    return good[0][1], []


def play_query(text, season=None, episode=None, lang=None, session=None, strict=False):
    lang = lang if lang in MSG else guess_lang(text)
    msg = MSG[lang]
    title, season, episode = parse_query(text, season, episode)
    out = {"ok": False, "matched": False, "lang": lang, "query": title}
    key, _ = load_key()
    jf = Jellyfin(os.environ.get("JELLYFIN_URL", ""), key, os.environ.get("JELLYFIN_USER", ""))
    if not jf.url or not key:
        return {**out, "said": msg["setup"], "reason": "not configured"}
    try:
        episodic = season is not None or episode is not None
        it, close = find_title(jf, title, episodic, strict and not episodic)
        if close:
            names = [title_of(c) for c in close]
            listed = ", ".join(names[:-1]) + OR[lang] + names[-1]
            return {**out, "matched": True, "said": msg["which"].format(list=listed),
                    "candidates": [brief(c, overview=0) for c in close]}
        if not it:
            return {**out, "said": msg["notfound"].format(query=title or text), "reason": "not found"}
        out["matched"] = True
        if episodic and it.get("Type") == "Series":
            eps = [e for e in jf.episodes(it["Id"]) if (e.get("ParentIndexNumber") or 0) > 0]
            seasons = sorted({e.get("ParentIndexNumber") for e in eps})
            season = season or 1
            if season not in seasons:
                n = len(seasons)
                return {**out, "said": msg["seasons"].format(series=it.get("Name"), n=n, s=PLURAL[lang] if n != 1 else ""),
                        "reason": "no such season"}
            in_season = [e for e in eps if e.get("ParentIndexNumber") == season]
            if episode is None:
                unplayed = [e for e in in_season if not (e.get("UserData") or {}).get("Played")]
                chosen = (unplayed or in_season)[0]
            else:
                chosen = next((e for e in in_season if e.get("IndexNumber") == episode), None)
                if chosen is None:
                    n = len(in_season)
                    return {**out, "said": msg["episodes"].format(series=it.get("Name"), season=season, n=n,
                                                                  s=PLURAL[lang] if n != 1 else ""),
                            "reason": "no such episode"}
            # From that episode on, so the player goes on to the next one.
            start = eps.index(chosen)
            target = chosen
            ids = [e["Id"] for e in eps[start:start + MAX_QUEUE]]
            ticks = (chosen.get("UserData") or {}).get("PlaybackPositionTicks") or 0
        else:
            target = it
            if it.get("Type") == "Series":
                ids, ticks = playable(jf, it)
                target = next((e for e in jf.episodes(it["Id"]) if e["Id"] == ids[0]), it)
            else:
                ids, ticks = playable(jf, it)
        player, why = pick_session(jf, session)
        if not player:
            return {**out, "said": msg["noplayer"], "reason": why, "title": title_of(target),
                    "web_url": jf.web_url(target["Id"])}
        send_play(jf, player, ids, ticks)
        said = (msg["playing"] if is_local_shim(player) or not session
                else msg["queued"]).format(title=title_of(target), player=player.get("DeviceName") or player.get("Client"))
        return {**out, "ok": True, "said": said, "title": title_of(target), "kind": TYPE_OUT.get(target.get("Type")),
                "item_id": target["Id"], "player": player.get("DeviceName") or player.get("Client"),
                **({"from": clock(ticks)} if ticks else {})}
    except JfError as exc:
        return {**out, "said": msg["error"].format(error=jf.hide(exc).rstrip(".")), "reason": jf.hide(exc)}


# --------------------------------------------------------------------------
# MCP over stdio
# --------------------------------------------------------------------------

INSTRUCTIONS = (
    "The user's Jellyfin library (films, series, music) and its players. Find with search, then "
    "play {item_id}: by default it plays fullscreen in mpv on this computer (the player keeps the "
    "progress and goes on to the next episode itself); name session for Moonfin, a TV or a browser. "
    "control pauses, seeks, skips and sets the volume of what plays; sessions shows what plays "
    "where. Other people's players are used only when named.")


class Server:
    def __init__(self):
        self.jf = None

    def client(self):
        if self.jf is None:
            key, _ = load_key()
            self.jf = Jellyfin(os.environ.get("JELLYFIN_URL", ""), key, os.environ.get("JELLYFIN_USER", ""))
        return self.jf

    def call(self, name, args):
        entry = TOOLS.get(name)
        if not entry:
            raise RpcError(-32602, f"unknown tool: {name}")
        if not isinstance(args, dict):
            return [text("arguments must be an object")], True
        try:
            jf = self.client()
            result = entry["fn"](jf, args)
        except JfError as exc:
            msg = self.jf.hide(exc) if self.jf else str(exc)
            return [text(msg)], True
        except (TypeError, ValueError, KeyError) as exc:
            msg = f"{name} failed: {type(exc).__name__}: {exc}"
            return [text(self.jf.hide(msg) if self.jf else msg)], True
        return [text(json.dumps(result, ensure_ascii=False, separators=(",", ":")))], False

    def handle(self, msg):
        if not isinstance(msg, dict):
            return error(None, -32600, "invalid request")
        mid = msg.get("id")
        if mid is None:
            return None
        try:
            result = self.dispatch(msg.get("method"), msg.get("params") or {})
        except RpcError as exc:
            return error(mid, exc.code, exc.message)
        return {"jsonrpc": "2.0", "id": mid, "result": result}

    def dispatch(self, method, params):
        if method == "initialize":
            asked = params.get("protocolVersion")
            return {
                "protocolVersion": asked if asked in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "title": "Jellyfin", "version": VERSION},
                "instructions": INSTRUCTIONS,
            }
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": [t["spec"] for t in TOOLS.values()]}
        if method == "tools/call":
            content, is_error = self.call(params.get("name"), params.get("arguments") or {})
            return {"content": content, "isError": is_error}
        raise RpcError(-32601, f"method not found: {method}")


class RpcError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def text(s):
    return {"type": "text", "text": s}


def error(mid, code, message):
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}}


def serve():
    server = Server()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            reply = error(None, -32700, "parse error")
        else:
            reply = server.handle(msg)
        if reply is not None:
            sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
            sys.stdout.flush()


# --------------------------------------------------------------------------
# The CLI, for nixbook-shell (Settings, the bubble's fast path)
# --------------------------------------------------------------------------


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)


def status():
    key, source = load_key()
    return {"has_key": bool(key), "key_source": source, "url": os.environ.get("JELLYFIN_URL") or None}


def stdin_line():
    return "" if sys.stdin is None or sys.stdin.isatty() else sys.stdin.readline().strip()


def check(url, key, user):
    jf = Jellyfin(url, key, user)
    try:
        info = jf.public_info()
        chosen = pick_user(jf.request("GET", "/Users") or [], user)
        counts = jf.request("GET", "/Items/Counts", {"userId": chosen["Id"]}) or {}
    except JfError as exc:
        out({"error": jf.hide(exc)}, 1)
    return {"server": info.get("ServerName"), "version": info.get("Version"), "user": chosen.get("Name"),
            "movies": counts.get("MovieCount"), "series": counts.get("SeriesCount"),
            "songs": counts.get("SongCount"), "albums": counts.get("AlbumCount")}


def pick_user(users, name):
    if not users:
        raise JfError("Jellyfin has no users")
    if name:
        match = [u for u in users if str(u.get("Name", "")).casefold() == name.strip().casefold()]
        if not match:
            raise JfError(f"Jellyfin has no user named {name!r}")
        return match[0]
    admins = [u for u in users if (u.get("Policy") or {}).get("IsAdministrator")]
    return (admins or users)[0]


def credentials(args):
    if args == ["status"]:
        out(status())
    if args == ["forget"]:
        try:
            subprocess.run([SECRET_TOOL, "clear", *SECRET_ATTRS], check=False,
                           timeout=10, capture_output=True, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired) as exc:
            out({"error": f"couldn't reach the keyring: {exc}"}, 1)
        os.environ.pop("JELLYFIN_API_KEY", None)
        out(status())
    if len(args) in (2, 3) and args[0] in ("save", "test"):
        try:
            url = clean_url(args[1])
        except JfError as exc:
            out({"error": str(exc)}, 1)
        if not url:
            out({"error": "the Jellyfin server URL is needed"}, 1)
        user = args[2] if len(args) == 3 else os.environ.get("JELLYFIN_USER", "")
        new_key = stdin_line()
        key = new_key or load_key()[0]
        if not key:
            out({"error": "an API key is needed (Jellyfin: Dashboard > API Keys)"}, 1)
        result = check(url, key, user)
        if args[0] == "save" and new_key:
            try:
                stored = subprocess.run([SECRET_TOOL, "store",
                                         "--label=Jellyfin API key (jellyfin-mcp)", *SECRET_ATTRS],
                                        input=new_key, text=True, capture_output=True, timeout=30)
            except (OSError, subprocess.TimeoutExpired) as exc:
                out({"error": f"couldn't save the key in the keyring: {exc}"}, 1)
            if stored.returncode != 0:
                out({"error": f"couldn't save the key in the keyring: {stored.stderr.strip()}"[:300].replace(new_key, "***")}, 1)
        st = status()
        if new_key:
            st = {**st, "has_key": True, "key_source": "keyring" if args[0] == "save" else st["key_source"]}
        out({**st, "url": url, **result})
    out({"error": "usage: jellyfin-mcp credentials status | save URL [USER] | test URL [USER] (key on stdin) | forget"}, 1)


def ensure_shim_conf():
    """conf.json with a device id (client_uuid), so the login and the shim
    agree on it even before the shim first ran. Home Manager writes the rest."""
    path = os.path.join(shim_dir(), "conf.json")
    os.makedirs(shim_dir(), mode=0o700, exist_ok=True)
    conf = read_json(path)
    if not isinstance(conf, dict):
        if os.path.exists(path):
            raise JfError(f"{path} isn't valid JSON: fix or remove it first")
        conf = {}
    if not conf.get("client_uuid"):
        conf["client_uuid"] = str(uuid.uuid4())
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(conf, f, indent=4, sort_keys=True)
        os.replace(tmp, path)
    return conf


def shim_login(args):
    """Signs jellyfin-mpv-shim in as it would itself (its client name, device
    name and device id), with the password from stdin, and files the token
    in its users.json (0600). The password is never stored."""
    if len(args) != 2:
        out({"error": "usage: jellyfin-mcp shim-login URL USERNAME (password on stdin)"}, 1)
    try:
        url = clean_url(args[0])
    except JfError as exc:
        out({"error": str(exc)}, 1)
    username = args[1].strip()
    password = stdin_line()
    if not url or not username:
        out({"error": "the server URL and the username are needed"}, 1)
    jf = Jellyfin(url, "")
    try:
        conf = ensure_shim_conf()
        ident = shim_identity() or {"device_id": conf["client_uuid"],
                                    "device_name": conf.get("player_name") or socket.gethostname(), "profile": None}
        info = jf.public_info()
        client = {"Client": SHIM_CLIENT, "Device": ident["device_name"], "DeviceId": ident["device_id"],
                  "Version": os.environ.get("JELLYFIN_SHIM_VERSION") or "3.1.0"}
        try:
            auth = jf.request("POST", "/Users/AuthenticateByName", body={"Username": username, "Pw": password},
                              auth=False, client=client) or {}
        except JfError as exc:
            if "refused" in str(exc):
                raise JfError("Jellyfin refused this username or password") from None
            raise
    except JfError as exc:
        out({"error": str(exc).replace(password, "***") if password else str(exc)}, 1)
    password = ""
    token = auth.get("AccessToken")
    user = auth.get("User") or {}
    if not token or not user.get("Id"):
        out({"error": "Jellyfin didn't return a token"}, 1)
    cred = {
        "address": url,
        "Name": info.get("ServerName"),
        "Id": info.get("Id") or auth.get("ServerId"),
        "Version": info.get("Version"),
        "DateLastAccessed": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "UserId": user["Id"],
        "AccessToken": token,
        "Users": [{"Id": user["Id"], "IsSignedInOffline": True}],
        "uuid": str(uuid.uuid4()),
        "username": username,
    }
    path = os.path.join(shim_dir(), "users.json")
    data = read_json(path)
    if not (isinstance(data, dict) and data.get("users")):
        profile = {"id": uuid.uuid4().hex, "name": "(default)", "device_id": ident["device_id"],
                   "default": True, "pin_hash": None, "pin_salt": None, "require_pin_startup": False,
                   "last_server": None, "auto_download": None, "credentials": []}
        data = {"active": profile["id"], "users": [profile]}
    profile = next((u for u in data["users"] if u.get("id") == data.get("active")), data["users"][0])
    kept = []
    for c in profile.get("credentials") or []:
        if c.get("Id") == cred["Id"] or str(c.get("address", "")).rstrip("/") == url:
            # The same login signed in again: it keeps its uuid (the shim's
            # name for it).
            if c.get("uuid") and c.get("UserId") == cred["UserId"]:
                cred["uuid"] = c["uuid"]
            continue
        kept.append(c)
    profile["credentials"] = kept + [cred]
    # The shim writes this file back from memory: stopped while it changes.
    systemctl("stop", SHIM_UNIT, timeout=15)
    try:
        write_private(path, data)
        write_private(path + ".bak", data)
    except OSError as exc:
        out({"error": f"couldn't write {path}: {exc}"}, 1)
    code, _ = systemctl("start", SHIM_UNIT, timeout=15)
    out({"ok": True, "server": info.get("ServerName"), "user": user.get("Name") or username,
         "device": ident["device_name"], "started": code == 0})


def shim_status():
    url = os.environ.get("JELLYFIN_URL", "").rstrip("/")
    cred = shim_credential(url) if url else None
    ident = shim_identity()
    _, state = systemctl("is-active", SHIM_UNIT)
    return {"signed_in": bool(cred), "user": (cred or {}).get("username") or None,
            "device": (ident or {}).get("device_name"), "service": state or "unknown"}


def shim_logout():
    url = os.environ.get("JELLYFIN_URL", "").rstrip("/")
    path = os.path.join(shim_dir(), "users.json")
    data = read_json(path)
    removed = 0
    if isinstance(data, dict) and data.get("users"):
        systemctl("stop", SHIM_UNIT, timeout=15)
        for profile in data["users"]:
            creds = profile.get("credentials") or []
            keep = [c for c in creds if url and str(c.get("address", "")).rstrip("/") != url]
            removed += len(creds) - len(keep)
            profile["credentials"] = keep
        write_private(path, data)
        write_private(path + ".bak", data)
    out({"ok": True, "removed": removed, **shim_status()})


def cli_play_query(args):
    season = episode = lang = session = None
    strict = False
    rest = []
    it = iter(args)
    try:
        for a in it:
            if a == "--season":
                season = int(next(it))
            elif a == "--episode":
                episode = int(next(it))
            elif a == "--lang":
                lang = next(it)
            elif a == "--session":
                session = next(it)
            elif a == "--strict":
                strict = True
            else:
                rest.append(a)
    except (StopIteration, ValueError):
        out({"ok": False, "matched": False, "said": "usage: jellyfin-mcp play-query TEXT [--season N] [--episode M]"}, 2)
    result = play_query(" ".join(rest), season, episode, lang, session, strict)
    out(result, 0 if result.get("ok") else 1)


def main():
    args = sys.argv[1:]
    if args[:1] == ["credentials"]:
        credentials(args[1:])
    if args[:1] == ["play-query"]:
        cli_play_query(args[1:])
    if args[:1] == ["shim-login"]:
        shim_login(args[1:])
    if args == ["shim-status"]:
        out(shim_status())
    if args == ["shim-logout"]:
        shim_logout()
    if args == ["configured"]:
        st = status()
        ok = bool(st["has_key"] and st["url"])
        cred = shim_credential(st["url"]) if st["url"] else None
        out({"configured": ok, "player": bool(cred)}, 0 if ok else 1)
    if args in ([], ["serve"]):
        serve()
        return
    if args in (["--version"], ["version"]):
        print(VERSION)
        return
    sys.stderr.write("usage: jellyfin-mcp [serve] | configured | play-query TEXT | credentials … | shim-login|shim-status|shim-logout\n")
    sys.exit(2)


if __name__ == "__main__":
    main()
