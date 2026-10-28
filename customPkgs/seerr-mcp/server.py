"""seerr-mcp: an MCP server (stdio, stdlib only) for the user's Seerr
(Overseerr / Jellyseerr): find films and series, see what is available or
on its way, request them, follow and manage requests.

  seerr-mcp                          the MCP server, JSON-RPC lines on stdin/stdout
  seerr-mcp configured               {"configured"}; exit 1 when not configured
  seerr-mcp credentials status|forget
  seerr-mcp login-from-browser URL   your own login: Seerr's session from your
                                     browser's cookies (Zen, Firefox, Chrome,
                                     Chromium, Brave…), after you signed in
                                     there; kept in the keyring
  seerr-mcp credentials save|test URL [USER]
                                     the API key (on stdin; empty: the current
                                     one) checked on the server; save keeps it
                                     in the keyring
  seerr-mcp users URL                the server's users (to pick who requests
                                     go out as; the API key on stdin, else the
                                     saved one)

Two ways in. Your own login (no admin key): Seerr has no per-user API key,
and a server with OpenID Connect only logs in through the browser, so you sign
in there once (Zen, Firefox, LibreWolf; Chrome, Chromium, Brave, Vivaldi,
Edge: their cookies decrypted with the browser's key from the keyring) and
`login-from-browser` takes only Seerr's session cookie (connect.sid, for that
host) from its cookie file:
seerr-mcp then acts as you, with your permissions and quota, until the
session ends (sign in again then). Or an admin's API key (Settings >
General > API Key; any login method), sent with X-API-User so requests go out
as SEERR_USER (a user id, name or email; else the key's own admin).

The server is SEERR_URL; the credential is SEERR_SESSION or SEERR_API_KEY,
else the file SEERR_API_KEY_FILE names (`~/` allowed), else the keyring's
service=seerr-mcp secret (secret-tool; nixbook-shell's Settings saves it
there, `kind` session or apikey). It is never printed, logged, put in a tool
result or on a command line.
"""

import glob
import shutil
import sqlite3
import tempfile

import hashlib
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

VERSION = "0.1.0"
SERVER_NAME = "seerr-mcp"
PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]
SECRET_TOOL = "secret-tool"
SECRET_ATTRS = ["service", "seerr-mcp"]
MAX_LIST = 40
NOT_SET_UP = ("Seerr isn't set up: set its server and API key in Settings > Desktop agents > "
              "Apps it can use (or SEERR_URL and SEERR_API_KEY).")
REFUSED = "Seerr refused the API key (HTTP {code}): check it in Settings > Desktop agents > Seerr"
SIGNED_OUT = ("Seerr doesn't take your login any more (HTTP {code}): sign in to Seerr in your browser again, then "
              "Settings > Desktop agents > Seerr > Use my browser's login")
SESSION_COOKIE = "connect.sid"

# Seerr's media and request states.
MEDIA_STATUS = {1: "not requested", 2: "requested, waiting for approval", 3: "requested, on its way",
                4: "partly available", 5: "available", 6: "blocklisted", 7: "deleted"}
REQUEST_STATUS = {1: "waiting for approval", 2: "approved", 3: "declined", 4: "failed", 5: "completed"}
FILTERS = ["all", "pending", "approved", "processing", "available", "unavailable", "failed"]


class SeerrError(Exception):
    """A failure reported to the agent as a tool error."""


class HttpError(SeerrError):
    def __init__(self, message, code):
        super().__init__(message)
        self.code = code


# --------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------


def keyring_lookup(*attrs):
    try:
        found = subprocess.run([SECRET_TOOL, "lookup", *SECRET_ATTRS, *attrs],
                               capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return found.stdout.strip() if found.returncode == 0 else ""


def load_cred():
    """(secret, source, kind): your session (kind session: SEERR_SESSION, or
    the keyring's kind=session secret) or an API key (load_key)."""
    session = os.environ.get("SEERR_SESSION", "").strip()
    if session:
        return session, "env", "session"
    if not os.environ.get("SEERR_API_KEY", "").strip() and not os.environ.get("SEERR_API_KEY_FILE", "").strip():
        session = keyring_lookup("kind", "session")
        if session:
            return session, "keyring", "session"
    key, source = load_key()
    return key, source, "apikey" if key else None


def load_key():
    """(key, source): env, file, keyring, or ("", None)."""
    key = os.environ.get("SEERR_API_KEY", "").strip()
    if key:
        return key, "env"
    path = os.environ.get("SEERR_API_KEY_FILE", "").strip()
    if path:
        try:
            with open(os.path.expanduser(path), encoding="utf-8") as f:
                key = f.read().strip()
        except OSError:
            key = ""
        if key:
            return key, "file"
    key = keyring_lookup()
    if key and keyring_lookup("kind", "session") == key:
        return "", None  # the keyring holds a session, not a key
    return (key, "keyring") if key else ("", None)


def clean_url(url):
    url = (url or "").strip().rstrip("/")
    if not url:
        return ""
    if not url.startswith(("http://", "https://")):
        raise SeerrError("the Seerr URL must start with http:// or https://")
    return url


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
    path = os.path.join(base, "seerr-mcp")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_private(path, payload):
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    os.replace(tmp, path)


# --------------------------------------------------------------------------
# The Seerr API
# --------------------------------------------------------------------------


class Seerr:
    def __init__(self, url, key, user="", timeout=None, session=""):
        self.url = clean_url(url)
        self.key = key
        # Your own login (the session cookie): you, no X-API-User.
        self.session = session
        self.user_hint = "" if session else (user or "").strip()
        self.timeout = timeout or float(os.environ.get("SEERR_TIMEOUT") or 10)
        self._as = None  # the user the requests go out as: {id, name}

    def hide(self, text):
        text = str(text)
        for secret in (self.key, self.session):
            if secret:
                text = text.replace(secret, "***")
        return text

    def request(self, method, path, params=None, body=None, as_user=True):
        if not self.url or not (self.key or self.session):
            raise SeerrError(NOT_SET_UP)
        query = {k: v for k, v in (params or {}).items() if v is not None and v != ""}
        # Seerr wants spaces as %20 in a search, not "+".
        full = self.url + "/api/v1" + path + ("?" + urllib.parse.urlencode(query, quote_via=urllib.parse.quote)
                                              if query else "")
        headers = {"Accept": "application/json"}
        if self.session:
            headers["Cookie"] = f"{SESSION_COOKIE}={self.session}"
        else:
            headers["X-Api-Key"] = self.key
        if as_user and not self.session:
            who = self.acting_as()
            if who and who.get("id"):
                headers["X-API-User"] = str(who["id"])
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        elif method in ("POST", "PUT"):
            data = b""
        req = urllib.request.Request(full, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                detail = ""
                try:
                    detail = json.loads(exc.read() or b"{}").get("message") or ""
                except (ValueError, OSError):
                    pass
                # A session that ended answers like a missing permission:
                # /auth/me tells them apart (only the former fails there).
                if self.session and (path == "/auth/me" or not self._signed_in()):
                    raise HttpError(SIGNED_OUT.format(code=exc.code), exc.code) from None
                if exc.code == 403 and detail:
                    raise HttpError(f"Seerr said no: {detail}", exc.code) from None
                raise HttpError(REFUSED.format(code=exc.code), exc.code) from None
            if exc.code == 404:
                raise HttpError(f"Seerr has no {path.split('?')[0]} (HTTP 404)", exc.code) from None
            message = ""
            try:
                message = json.loads(exc.read() or b"{}").get("message") or ""
            except (ValueError, OSError):
                pass
            raise HttpError(f"Seerr answered HTTP {exc.code}" + (f": {message}" if message else ""), exc.code) from None
        except (socket.timeout, TimeoutError):
            raise SeerrError(f"Seerr at {self.url} didn't answer within {self.timeout:g} s") from None
        except urllib.error.URLError as exc:
            raise SeerrError(self.hide(f"couldn't reach Seerr at {self.url}: {exc.reason}")) from None
        except OSError as exc:
            raise SeerrError(self.hide(f"couldn't reach Seerr at {self.url}: {exc}")) from None
        if not raw.strip():
            return None
        try:
            return json.loads(raw)
        except ValueError:
            raise SeerrError(f"{self.url} didn't answer in JSON: is it a Seerr server?") from None

    def _signed_in(self):
        try:
            self.request("GET", "/auth/me")
            return True
        except SeerrError:
            return False

    def users(self):
        res = self.request("GET", "/user", {"take": 200, "skip": 0, "sort": "displayname"}, as_user=False) or {}
        return res.get("results") or []

    def _cache(self):
        tag = hashlib.sha256(f"{self.url}\0{self.user_hint}\0{self.key}".encode()).hexdigest()[:20]
        return os.path.join(runtime_dir(), f"user-{tag}.json")

    def acting_as(self):
        """{id, name}: SEERR_USER (an id, a name or an email), resolved once a
        day; without it, the key's own user (None: no X-API-User)."""
        if self._as is not None:
            return self._as or None
        if not self.user_hint:
            self._as = {}
            return None
        cached = read_json(self._cache())
        if isinstance(cached, dict) and cached.get("id") and time.time() - cached.get("time", 0) < 86400:
            self._as = {"id": cached["id"], "name": cached.get("name", "")}
            return self._as
        want = self.user_hint.casefold()
        found = None
        for u in self.users():
            names = {str(u.get(k) or "").casefold() for k in
                     ("displayName", "username", "email", "jellyfinUsername", "plexUsername")}
            if want == str(u.get("id")) or want in names:
                found = u
                break
        if not found:
            raise SeerrError(f"Seerr has no user {self.user_hint!r} (Settings > Desktop agents > Seerr: Request as)")
        self._as = {"id": found["id"], "name": user_name(found)}
        try:
            write_private(self._cache(), {**self._as, "time": time.time()})
        except OSError:
            pass
        return self._as


def user_name(u):
    return u.get("displayName") or u.get("username") or u.get("jellyfinUsername") or u.get("plexUsername") \
        or u.get("email") or f"user {u.get('id')}"


# --------------------------------------------------------------------------
# Formatting
# --------------------------------------------------------------------------


def short(text, n):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def year_of(item):
    d = item.get("releaseDate") or item.get("firstAirDate") or ""
    return int(d[:4]) if len(d) >= 4 and d[:4].isdigit() else None


def status_of(info, is4k=False):
    if not info:
        return MEDIA_STATUS[1]
    return MEDIA_STATUS.get(info.get("status4k" if is4k else "status"), MEDIA_STATUS[1])


def brief(item, overview=160):
    kind = item.get("mediaType") or ("tv" if item.get("firstAirDate") or item.get("name") and not item.get("title") else "movie")
    out = {"id": item.get("id"), "type": "series" if kind == "tv" else kind,
           "title": item.get("title") or item.get("name")}
    y = year_of(item)
    if y:
        out["year"] = y
    if kind in ("movie", "tv"):
        out["status"] = status_of(item.get("mediaInfo"))
    if overview and item.get("overview"):
        out["overview"] = short(item["overview"], overview)
    return out


def kind_of(value):
    v = str(value or "").strip().casefold()
    if v in ("movie", "film", "movies", "films"):
        return "movie"
    if v in ("tv", "series", "show", "shows", "serie", "série"):
        return "tv"
    raise SeerrError(f"type: movie or series, not {value!r}")


# --------------------------------------------------------------------------
# Tools
# --------------------------------------------------------------------------

TOOLS = {}


def tool(name, description, props=None, required=(), read_only=False, destructive=False, title=None):
    def register(fn):
        TOOLS[name] = {
            "fn": fn,
            "spec": {
                "name": name,
                "title": title or name.replace("_", " ").capitalize(),
                "description": description,
                "inputSchema": {"type": "object", "properties": props or {},
                                "required": list(required), "additionalProperties": False},
                "annotations": {"readOnlyHint": read_only, "destructiveHint": destructive,
                                "idempotentHint": read_only, "openWorldHint": True},
            },
        }
        return fn
    return register


def need(args, key):
    value = args.get(key)
    if value is None or (isinstance(value, str) and not value.strip()):
        raise SeerrError(f"{key} is required")
    return value.strip() if isinstance(value, str) else value


def limit_of(args, default):
    try:
        n = int(args.get("limit") or default)
    except (TypeError, ValueError):
        raise SeerrError("limit must be a number") from None
    return max(1, min(n, MAX_LIST))


TYPE = {"type": "string", "enum": ["movie", "series"]}
LIMIT = {"type": "integer", "minimum": 1, "maximum": MAX_LIST}
TMDB = {"type": "integer", "description": "The TMDB id search gives."}


@tool("search", "Search Seerr (films and series, from TMDB) and see each one's status: available, on its way, requested, or not requested. Returns the ids request and details take.",
      {"query": {"type": "string"}, "type": TYPE, "limit": LIMIT}, required=["query"], read_only=True)
def t_search(sr, args):
    query = need(args, "query")
    want = kind_of(args["type"]) if args.get("type") else None
    res = sr.request("GET", "/search", {"query": query, "page": 1}) or {}
    items = [i for i in res.get("results") or [] if i.get("mediaType") in ("movie", "tv")
             and (want is None or i.get("mediaType") == want)]
    return {"total": len(items), "results": [brief(i) for i in items[:limit_of(args, 10)]]}


@tool("details", "A film's or series' details: what it is, whether it is available (each season of a series), its requests.",
      {"type": TYPE, "id": TMDB}, required=["type", "id"], read_only=True)
def t_details(sr, args):
    kind = kind_of(need(args, "type"))
    item = sr.request("GET", f"/{kind}/{int(need(args, 'id'))}") or {}
    out = brief({**item, "mediaType": kind}, overview=600)
    if item.get("genres"):
        out["genres"] = [g.get("name") for g in item["genres"]][:5]
    if kind == "movie" and item.get("runtime"):
        out["runtime"] = f"{item['runtime']} min"
    info = item.get("mediaInfo") or {}
    if kind == "tv":
        by_season = {s.get("seasonNumber"): s.get("status") for s in info.get("seasons") or []}
        out["seasons"] = [{"season": s.get("seasonNumber"), "episodes": s.get("episodeCount"),
                           "status": MEDIA_STATUS.get(by_season.get(s.get("seasonNumber")), MEDIA_STATUS[1])}
                          for s in item.get("seasons") or [] if (s.get("seasonNumber") or 0) > 0]
    requests = info.get("requests") or []
    if requests:
        out["requests"] = [request_brief(r) for r in requests[:10]]
    return out


def request_brief(r, title=None):
    out = {"id": r.get("id"), "status": REQUEST_STATUS.get(r.get("status"), str(r.get("status"))),
           "requested_by": user_name(r.get("requestedBy") or {}) if r.get("requestedBy") else None,
           "date": str(r.get("createdAt") or "")[:10]}
    media = r.get("media") or {}
    if media:
        out["type"] = "series" if media.get("mediaType") == "tv" else media.get("mediaType")
        out["tmdb_id"] = media.get("tmdbId")
        out["availability"] = status_of(media, bool(r.get("is4k")))
    if title:
        out["title"] = title
    seasons = [s.get("seasonNumber") for s in r.get("seasons") or []]
    if seasons:
        out["seasons"] = seasons
    if r.get("is4k"):
        out["4k"] = True
    return {k: v for k, v in out.items() if v not in (None, "", [])}


@tool("request", "Request a film, or a series' seasons, on Seerr (as the user set in Settings: their quota, shown as theirs). A series: give seasons, or all of them not yet available or requested. Says what was requested and its status.",
      {"type": TYPE, "id": TMDB,
       "seasons": {"type": "array", "items": {"type": "integer", "minimum": 1}, "description": "A series' seasons (default: every one missing)."},
       "is4k": {"type": "boolean", "description": "The 4K version (when the server has one)."}},
      required=["type", "id"], title="Request on Seerr")
def t_request(sr, args):
    kind = kind_of(need(args, "type"))
    tmdb = int(need(args, "id"))
    item = sr.request("GET", f"/{kind}/{tmdb}") or {}
    title = item.get("title") or item.get("name") or str(tmdb)
    body = {"mediaType": kind, "mediaId": tmdb}
    if args.get("is4k"):
        body["is4k"] = True
    if kind == "movie":
        if (item.get("mediaInfo") or {}).get("status4k" if args.get("is4k") else "status") in (2, 3, 4, 5):
            return {"requested": False, "title": title,
                    "why": f"{title} is already {status_of(item.get('mediaInfo'), bool(args.get('is4k')))}"}
    else:
        info = item.get("mediaInfo") or {}
        taken = {s.get("seasonNumber") for s in info.get("seasons") or [] if s.get("status") in (2, 3, 4, 5)}
        for r in info.get("requests") or []:
            if r.get("status") in (1, 2):
                taken |= {s.get("seasonNumber") for s in r.get("seasons") or []}
        all_seasons = [s.get("seasonNumber") for s in item.get("seasons") or [] if (s.get("seasonNumber") or 0) > 0]
        asked = [int(s) for s in args.get("seasons") or []] or all_seasons
        unknown = [s for s in asked if s not in all_seasons]
        if unknown:
            raise SeerrError(f"{title} has no season {', '.join(map(str, unknown))} (it has {len(all_seasons)})")
        missing = [s for s in asked if s not in taken]
        if not missing:
            return {"requested": False, "title": title, "why": "those seasons are already available or requested"}
        body["seasons"] = missing
    r = sr.request("POST", "/request", body=body) or {}
    out = {"requested": True, "title": title, **request_brief(r)}
    out.pop("title", None)
    out["title"] = title
    return out


@tool("requests", "The requests on Seerr: the user's own by default (mine: false for everyone's), filtered by status, newest first, with each title and how far it is.",
      {"filter": {"type": "string", "enum": FILTERS}, "mine": {"type": "boolean"}, "limit": LIMIT}, read_only=True)
def t_requests(sr, args):
    flt = str(args.get("filter") or "all")
    if flt not in FILTERS:
        raise SeerrError(f"filter: one of {', '.join(FILTERS)}")
    params = {"take": limit_of(args, 15), "skip": 0, "filter": flt, "sort": "added"}
    if args.get("mine", True) is not False:
        who = sr.acting_as() or (sr.request("GET", "/auth/me") or {})
        if who.get("id"):
            params["requestedBy"] = who["id"]
    res = sr.request("GET", "/request", params) or {}
    out = []
    titles = {}
    for r in res.get("results") or []:
        media = r.get("media") or {}
        key = (media.get("mediaType"), media.get("tmdbId"))
        if key not in titles and media.get("tmdbId"):
            try:
                it = sr.request("GET", f"/{media['mediaType']}/{media['tmdbId']}") or {}
                titles[key] = it.get("title") or it.get("name")
            except SeerrError:
                titles[key] = None
        out.append(request_brief(r, titles.get(key)))
    return {"total": (res.get("pageInfo") or {}).get("results", len(out)), "requests": out}


@tool("cancel_request", "Cancel a request still waiting for approval (the user's own; an admin's key any).",
      {"id": {"type": "integer", "description": "The request id requests gives."}}, required=["id"], destructive=True)
def t_cancel(sr, args):
    rid = int(need(args, "id"))
    sr.request("DELETE", f"/request/{rid}")
    return {"cancelled": rid}


@tool("approve_request", "Approve a request waiting for approval (needs a user allowed to manage requests).",
      {"id": {"type": "integer"}}, required=["id"])
def t_approve(sr, args):
    rid = int(need(args, "id"))
    r = sr.request("POST", f"/request/{rid}/approve") or {}
    return {"approved": rid, **request_brief(r)}


@tool("decline_request", "Decline a request waiting for approval (needs a user allowed to manage requests).",
      {"id": {"type": "integer"}}, required=["id"], destructive=True)
def t_decline(sr, args):
    rid = int(need(args, "id"))
    r = sr.request("POST", f"/request/{rid}/decline") or {}
    return {"declined": rid, **request_brief(r)}


def discover(sr, path, args):
    res = sr.request("GET", path, {"page": 1}) or {}
    items = [i for i in res.get("results") or [] if i.get("mediaType", "movie") in ("movie", "tv")]
    return {"results": [brief(i, overview=120) for i in items[:limit_of(args, 10)]]}


@tool("trending", "What is trending now (films and series), with each one's status on Seerr.",
      {"type": TYPE, "limit": LIMIT}, read_only=True)
def t_trending(sr, args):
    if args.get("type"):
        kind = kind_of(args["type"])
        return discover(sr, "/discover/movies" if kind == "movie" else "/discover/tv", args)
    return discover(sr, "/discover/trending", args)


@tool("upcoming", "Films or series coming out soon, with each one's status on Seerr.",
      {"type": TYPE, "limit": LIMIT}, read_only=True)
def t_upcoming(sr, args):
    kind = kind_of(args.get("type") or "movie")
    res = discover(sr, "/discover/movies/upcoming" if kind == "movie" else "/discover/tv/upcoming", args)
    for r in res["results"]:
        r["type"] = "movie" if kind == "movie" else "series"
    return res


@tool("whoami", "Seerr's server, who the requests go out as, and how much of their request quota is left.", read_only=True)
def t_whoami(sr, args):
    status = sr.request("GET", "/status", as_user=False) or {}
    me = sr.request("GET", "/auth/me") or {}
    out = {"server": sr.url, "version": status.get("version"), "as": user_name(me), "user_id": me.get("id")}
    if me.get("id"):
        try:
            q = sr.request("GET", f"/user/{me['id']}/quota") or {}
            out["quota"] = {k: {"limit": v.get("limit"), "used": v.get("used"), "remaining": v.get("remaining"),
                                "days": v.get("days")}
                            for k, v in q.items() if isinstance(v, dict) and v.get("limit")}
        except SeerrError:
            pass
    return out


# --------------------------------------------------------------------------
# MCP over stdio
# --------------------------------------------------------------------------

INSTRUCTIONS = (
    "The user's Seerr (Overseerr / Jellyseerr): find films and series (search, trending, upcoming), see whether "
    "they are available, on their way or not requested (details), request them (request: a film, or a series' "
    "seasons), and follow or manage requests (requests, cancel_request, approve_request, decline_request). "
    "Requests go out as the user. Something already available is in their media server: play it from there "
    "(the jellyfin tools, when present), don't request it again.")


class RpcError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def text(s):
    return {"type": "text", "text": s}


def error(mid, code, message):
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}}


def client_from_env():
    secret, _, kind = load_cred()
    url = os.environ.get("SEERR_URL", "")
    if kind == "session":
        return Seerr(url, "", session=secret)
    return Seerr(url, secret, os.environ.get("SEERR_USER", ""))


class Server:
    def __init__(self):
        self.sr = None

    def client(self):
        if self.sr is None:
            self.sr = client_from_env()
        return self.sr


    def call(self, name, args):
        entry = TOOLS.get(name)
        if not entry:
            raise RpcError(-32602, f"unknown tool: {name}")
        if not isinstance(args, dict):
            return [text("arguments must be an object")], True
        try:
            sr = self.client()
            result = entry["fn"](sr, args)
        except SeerrError as exc:
            return [text(self.sr.hide(exc) if self.sr else str(exc))], True
        except (TypeError, ValueError, KeyError) as exc:
            msg = f"{name} failed: {type(exc).__name__}: {exc}"
            return [text(self.sr.hide(msg) if self.sr else msg)], True
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
            return {"protocolVersion": asked if asked in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": SERVER_NAME, "title": "Seerr", "version": VERSION},
                    "instructions": INSTRUCTIONS}
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": [t["spec"] for t in TOOLS.values()]}
        if method == "tools/call":
            content, is_error = self.call(params.get("name"), params.get("arguments") or {})
            return {"content": content, "isError": is_error}
        raise RpcError(-32601, f"method not found: {method}")


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
# The CLI, for nixbook-shell's Settings
# --------------------------------------------------------------------------


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)


def stdin_line():
    return "" if sys.stdin is None or sys.stdin.isatty() else sys.stdin.readline().strip()


def login_path():
    """Who signed in with their browser's login ({url, user}: no secret)."""
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "seerr-mcp", "login.json")


def status():
    secret, source, kind = load_cred()
    login = read_json(login_path()) if kind == "session" and source == "keyring" else None
    return {"has_key": bool(secret), "key_source": source, "kind": kind,
            "signed_in_as": login.get("user") if isinstance(login, dict) else None,
            "url": os.environ.get("SEERR_URL") or None}


def keyring_store(secret, label, kind):
    """The one seerr-mcp secret replaced: an API key or a session."""
    try:
        subprocess.run([SECRET_TOOL, "clear", *SECRET_ATTRS], check=False, timeout=10,
                       capture_output=True, stdin=subprocess.DEVNULL)
        stored = subprocess.run([SECRET_TOOL, "store", f"--label={label}", *SECRET_ATTRS, "kind", kind],
                                input=secret, text=True, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SeerrError(f"couldn't save it in the keyring: {exc}") from None
    if stored.returncode != 0:
        raise SeerrError(f"couldn't save it in the keyring: {stored.stderr.strip()}"[:300].replace(secret, "***"))


# Where the browsers keep their cookies (under the home), Zen first. The
# Firefox family stores them in clear; the Chromium family encrypts them
# with a key from the keyring (its `application` attribute, tried in order).
FIREFOX_DBS = [("Zen", ".zen/*/cookies.sqlite"), ("Zen", ".config/zen/*/cookies.sqlite"),
               ("Zen", ".var/app/app.zen_browser.zen/.zen/*/cookies.sqlite"),
               ("Firefox", ".mozilla/firefox/*/cookies.sqlite"),
               ("Firefox", ".var/app/org.mozilla.firefox/.mozilla/firefox/*/cookies.sqlite"),
               ("LibreWolf", ".librewolf/*/cookies.sqlite"), ("Floorp", ".floorp/*/cookies.sqlite")]
CHROMIUM_DIRS = [("Chrome", ".config/google-chrome", ["chrome"]),
                 ("Chrome Beta", ".config/google-chrome-beta", ["chrome"]),
                 ("Chrome Dev", ".config/google-chrome-unstable", ["chrome"]),
                 ("Chrome", ".var/app/com.google.Chrome/config/google-chrome", ["chrome"]),
                 ("Chromium", ".config/chromium", ["chromium"]),
                 ("Chromium", ".var/app/org.chromium.Chromium/config/chromium", ["chromium"]),
                 ("Chromium", "snap/chromium/common/chromium", ["chromium"]),
                 ("Brave", ".config/BraveSoftware/Brave-Browser", ["brave"]),
                 ("Vivaldi", ".config/vivaldi", ["chrome", "vivaldi"]),
                 ("Edge", ".config/microsoft-edge", ["chromium", "microsoft-edge"])]
CHROMIUM_APPS = ["chrome", "chromium", "brave", "vivaldi", "microsoft-edge"]
# Chrome's time stamps count from 1601, Firefox's from 1970 (both in µs).
CHROME_EPOCH_US = 11644473600 * 1_000_000


def cookie_dbs():
    """The cookie files of the user's browsers, [(path, browser, keyring
    apps)], each browser's most recently written first; SEERR_COOKIE_DBS
    (":"-separated files, either kind) instead in tests."""
    if os.environ.get("SEERR_COOKIE_DBS"):
        return [(p, "", CHROMIUM_APPS) for p in os.environ["SEERR_COOKIE_DBS"].split(":") if p]
    home = os.path.expanduser("~")

    def newest(paths):
        return sorted(set(paths), key=lambda p: -os.path.getmtime(p))

    found = []
    for name, pattern in FIREFOX_DBS:
        found += [(p, name, []) for p in newest(glob.glob(os.path.join(home, pattern)))]
    for name, base, apps in CHROMIUM_DIRS:
        paths = glob.glob(os.path.join(home, base, "*", "Network", "Cookies")) + \
            glob.glob(os.path.join(home, base, "*", "Cookies"))
        found += [(p, name, apps) for p in newest(paths)]
    return found


# -- AES-128-CBC decryption (Chromium's cookies), stdlib only ---------------
def _aes_tables():
    sbox, p, q = [0] * 256, 1, 1
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        rot = lambda v, n: ((v << n) | (v >> (8 - n))) & 0xFF  # noqa: E731
        sbox[p] = q ^ rot(q, 1) ^ rot(q, 2) ^ rot(q, 3) ^ rot(q, 4) ^ 0x63
        if p == 1:
            break
    sbox[0] = 0x63
    inv = [0] * 256
    for i, v in enumerate(sbox):
        inv[v] = i
    return sbox, inv


def _gmul(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        a = ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1
        b >>= 1
    return r


_SBOX, _INV_SBOX = _aes_tables()
_MUL = {n: [_gmul(i, n) for i in range(256)] for n in (9, 11, 13, 14)}


def _round_keys(key):
    w, rcon = [list(key[i:i + 4]) for i in range(0, 16, 4)], 1
    for i in range(4, 44):
        t = list(w[i - 1])
        if i % 4 == 0:
            t = [_SBOX[b] for b in t[1:] + t[:1]]
            t[0] ^= rcon
            rcon = _gmul(rcon, 2)
        w.append([a ^ b for a, b in zip(w[i - 4], t)])
    return [sum(w[4 * r:4 * r + 4], []) for r in range(11)]


def _decrypt_block(block, rks):
    m9, m11, m13, m14 = _MUL[9], _MUL[11], _MUL[13], _MUL[14]
    s = [b ^ k for b, k in zip(block, rks[10])]
    for rnd in range(9, -1, -1):
        s = [_INV_SBOX[s[r + 4 * ((c - r) % 4)]] for c in range(4) for r in range(4)]
        s = [b ^ k for b, k in zip(s, rks[rnd])]
        if rnd:
            out_ = []
            for c in range(4):
                a0, a1, a2, a3 = s[4 * c:4 * c + 4]
                out_ += [m14[a0] ^ m11[a1] ^ m13[a2] ^ m9[a3], m9[a0] ^ m14[a1] ^ m11[a2] ^ m13[a3],
                         m13[a0] ^ m9[a1] ^ m14[a2] ^ m11[a3], m11[a0] ^ m13[a1] ^ m9[a2] ^ m14[a3]]
            s = out_
    return s


def aes128_cbc_decrypt(key, iv, data):
    """The plaintext, or None when the padding is wrong (the wrong key)."""
    if not data or len(data) % 16:
        return None
    rks, prev, plain = _round_keys(key), list(iv), []
    for i in range(0, len(data), 16):
        block = list(data[i:i + 16])
        plain += [a ^ b for a, b in zip(_decrypt_block(block, rks), prev)]
        prev = block
    pad = plain[-1]
    if not 1 <= pad <= 16 or plain[-pad:] != [pad] * pad:
        return None
    return bytes(plain[:-pad])


def chromium_password(app):
    """The Chromium-family browser's cookie password from the keyring."""
    try:
        got = subprocess.run([SECRET_TOOL, "lookup", "application", app], capture_output=True,
                             text=True, timeout=15, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return got.stdout.strip() if got.returncode == 0 and got.stdout.strip() else None


def chromium_decrypt(blob, host_key, keys):
    """A Chromium cookie's value: v10 (key from "peanuts", no keyring), v11
    (the keyring's password, else an empty one). Newer Chromes put the
    SHA-256 of the host before the value."""
    blob = bytes(blob or b"")
    if blob[:3] not in (b"v10", b"v11"):
        return None
    for key in keys(blob[:3]):
        plain = aes128_cbc_decrypt(key, b" " * 16, blob[3:])
        if plain is None:
            continue
        if len(plain) > 32 and plain[:32] == hashlib.sha256(host_key.encode()).digest():
            plain = plain[32:]
        try:
            text = plain.decode("ascii")
        except UnicodeDecodeError:
            continue
        if text.isprintable():
            return text
    return None


def _chromium_key(password):
    return hashlib.pbkdf2_hmac("sha1", password.encode(), b"saltysalt", 1, 16)


def browser_sessions(host):
    """Seerr's session cookies for HOST in those files (only that cookie,
    only that host), the most recently used first: [(value, browser)]. Each
    file is copied (with its journal: a login just made may be there only)
    and read from the copy; a Chromium file's keyring password is asked for
    only when it has such a cookie."""
    out = []
    passwords = {}

    def keys_for(apps):
        def keys(version):
            if version == b"v10":
                yield _chromium_key("peanuts")
                return
            for app in apps:
                if app not in passwords:
                    passwords[app] = chromium_password(app)
                if passwords[app]:
                    yield _chromium_key(passwords[app])
            yield _chromium_key("")
        return keys

    with tempfile.TemporaryDirectory(prefix="seerr-mcp-") as tmp:
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
                if "moz_cookies" in tables:
                    rows = con.execute("SELECT value, lastAccessed FROM moz_cookies WHERE name = ? AND host IN (?, ?)",
                                       (SESSION_COOKIE, host, "." + host)).fetchall()
                    out += [(r[1] or 0, r[0], browser or "Firefox") for r in rows if r[0]]
                elif "cookies" in tables:
                    rows = con.execute("SELECT value, encrypted_value, host_key, last_access_utc FROM cookies "
                                       "WHERE name = ? AND host_key IN (?, ?)",
                                       (SESSION_COOKIE, host, "." + host)).fetchall()
                    for value, blob, host_key, used in rows:
                        value = value or chromium_decrypt(blob, host_key, keys_for(apps))
                        if value:
                            out.append(((used or 0) - CHROME_EPOCH_US, value, browser or "Chrome"))
                con.close()
            except (OSError, sqlite3.Error):
                continue
    return [(value, browser) for _, value, browser in sorted(out, key=lambda r: r[0], reverse=True)]


def browser_login(args):
    """login-from-browser URL: your own login, from your browser's cookies."""
    if len(args) != 1:
        out({"error": "usage: seerr-mcp login-from-browser URL"}, 1)
    try:
        url = clean_url(args[0])
    except SeerrError as exc:
        out({"error": str(exc)}, 1)
    if not url:
        out({"error": "the Seerr server URL is needed"}, 1)
    host = urllib.parse.urlsplit(url).hostname or ""
    found = browser_sessions(host)
    if not found:
        out({"error": f"no Seerr login for {host} in your browser: open {url} in Zen or Chrome, sign in, "
                       "then try again (Chrome writes a new login to disk within about 30 s)"}, 1)
    for value, browser in found:
        sr = Seerr(url, "", session=value)
        try:
            me = sr.request("GET", "/auth/me") or {}
            st = sr.request("GET", "/status", as_user=False) or {}
        except SeerrError:
            continue
        try:
            keyring_store(value, f"Seerr login of {user_name(me)} (seerr-mcp)", "session")
            os.makedirs(os.path.dirname(login_path()), mode=0o700, exist_ok=True)
            write_private(login_path(), {"url": url, "user": user_name(me), "user_id": me.get("id")})
        except (SeerrError, OSError) as exc:
            out({"error": str(exc)}, 1)
        out({**status(), "url": url, "server": url, "version": st.get("version"), "user": user_name(me),
             "user_id": me.get("id"), "browser": browser})
    out({"error": f"your browser's Seerr login for {host} has ended: sign in again there, then try again"}, 1)


def check(url, key, user, session=""):
    sr = Seerr(url, key, user, session=session)
    try:
        st = sr.request("GET", "/status", as_user=False) or {}
        me = sr.request("GET", "/auth/me") or {}
        counts = sr.request("GET", "/request/count", as_user=False) or {}
    except SeerrError as exc:
        out({"error": sr.hide(exc)}, 1)
    return {"server": url, "version": st.get("version"), "user": user_name(me), "user_id": me.get("id"),
            "requests": counts.get("total"), "pending": counts.get("pending")}


def credentials(args):
    if args == ["status"]:
        out(status())
    if args == ["forget"]:
        # Only forgotten here: logging the session out would sign the
        # browser out too (the same session).
        try:
            subprocess.run([SECRET_TOOL, "clear", *SECRET_ATTRS], check=False, timeout=10,
                           capture_output=True, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired) as exc:
            out({"error": f"couldn't reach the keyring: {exc}"}, 1)
        try:
            os.remove(login_path())
        except OSError:
            pass
        os.environ.pop("SEERR_API_KEY", None)
        out(status())
    if len(args) in (2, 3) and args[0] in ("save", "test"):
        try:
            url = clean_url(args[1])
        except SeerrError as exc:
            out({"error": str(exc)}, 1)
        if not url:
            out({"error": "the Seerr server URL is needed"}, 1)
        user = args[2] if len(args) == 3 else os.environ.get("SEERR_USER", "")
        new_key = stdin_line()
        if not new_key and args[0] == "test":
            secret, _, kind = load_cred()
            if kind == "session":
                out({**status(), "url": url, **check(url, "", "", secret)})
        key = new_key or load_key()[0]
        if not key:
            out({"error": "an API key is needed (Seerr: Settings > General > API Key)"}, 1)
        result = check(url, key, user)
        if args[0] == "save" and new_key:
            try:
                keyring_store(new_key, "Seerr API key (seerr-mcp)", "apikey")
            except SeerrError as exc:
                out({"error": str(exc)}, 1)
            try:
                os.remove(login_path())
            except OSError:
                pass
        st = status()
        if new_key:
            st = {**st, "has_key": True, "key_source": "keyring" if args[0] == "save" else st["key_source"]}
        out({**st, "url": url, **result})
    out({"error": "usage: seerr-mcp credentials status | save URL [USER] | test URL [USER] (key on stdin) | forget"}, 1)


def cli_users(args):
    if len(args) != 1:
        out({"error": "usage: seerr-mcp users URL (key on stdin, else the saved one)"}, 1)
    try:
        url = clean_url(args[0])
    except SeerrError as exc:
        out({"error": str(exc)}, 1)
    key = stdin_line()
    secret, _, kind = load_cred()
    sr = Seerr(url, key) if key else Seerr(url, "", session=secret) if kind == "session" else Seerr(url, secret)
    try:
        users = sr.users()
    except SeerrError as exc:
        out({"error": sr.hide(exc)}, 1)
    out({"users": [{"id": u.get("id"), "name": user_name(u), "email": u.get("email") or None} for u in users]})


def main():
    args = sys.argv[1:]
    if args[:1] == ["credentials"]:
        credentials(args[1:])
    if args[:1] == ["users"]:
        cli_users(args[1:])
    if args[:1] == ["login-from-browser"]:
        browser_login(args[1:])
    if args == ["configured"]:
        st = status()
        ok = bool(st["has_key"] and st["url"])
        out({"configured": ok}, 0 if ok else 1)
    if args in ([], ["serve"]):
        serve()
        return
    if args in (["--version"], ["version"]):
        print(VERSION)
        return
    sys.stderr.write("usage: seerr-mcp [serve] | configured | credentials … | login-from-browser URL | users URL\n")
    sys.exit(2)


if __name__ == "__main__":
    main()
