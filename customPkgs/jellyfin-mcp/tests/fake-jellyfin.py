"""A fake Jellyfin server for jellyfin-mcp's tests (stdlib only).

  fake-jellyfin.py PORTFILE LOGFILE SESSIONSFILE

Listens on 127.0.0.1 (a free port, written to PORTFILE), logs every request
as a JSON line {method, path, query, body, client} to LOGFILE (never the
token), and reads the sessions from SESSIONSFILE on each request (the tests
change it). Jellyfin 10.11's routes; while SESSIONSFILE.old exists, only
the older /Users/{id}/... ones. FAKE_SLOW=1: /System/Info/Public takes 3 s. Only the
Authorization header's Token is accepted (Jellyfin 10.11 ignores
X-Emby-Token unless legacy authorization is on): the API key, or a token
AuthenticateByName gave (a user's: /Users/Me answers it, a non-admin's can't
list the users and only sees its own sessions; /Sessions/Logout ends it).
"Mai" stands for a server with a two-factor plugin: her password gives a
token every call refuses, her app password a working one.
"""

import json
import re
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = "test-key-123"
PASSWORD = "hunter2-secret"
TICKS = 10_000_000
port_file, log_file, sessions_file = sys.argv[1:4]

USERS = [
    {"Id": "u-guest", "Name": "guest", "Policy": {"IsAdministrator": False}},
    {"Id": "u-admin", "Name": "Khoa", "Policy": {"IsAdministrator": True}},
    {"Id": "u-mai", "Name": "Mai", "Policy": {"IsAdministrator": False}},
]
# name -> {password: blocked?}
ACCOUNTS = {"Khoa": {PASSWORD: False}, "guest": {"guest-pass": False},
            "Mai": {"mai-password": True, "mai-app-password": False}}
# token -> {user, blocked}; revoked ones are dropped.
TOKENS = {}


def ud(played=False, pos=0, fav=False, pct=None):
    d = {"Played": played, "PlaybackPositionTicks": pos, "IsFavorite": fav}
    if pct is not None:
        d["PlayedPercentage"] = pct
    return d


ITEMS = [
    {"Id": "ser-edge", "Type": "Series", "Name": "Cyberpunk: Edgerunners", "ProductionYear": 2022,
     "Overview": "In a dystopia riddled with corruption and cybernetic implants, a talented but reckless street kid "
                 "strives to become a mercenary outlaw — an edgerunner. " * 3,
     "Genres": ["Animation", "Sci-Fi"], "UserData": {"UnplayedItemCount": 9}},
    {"Id": "sea-edge-1", "Type": "Season", "Name": "Season 1", "SeriesId": "ser-edge", "IndexNumber": 1,
     "ParentId": "ser-edge", "UserData": {"UnplayedItemCount": 9}},
    {"Id": "mov-spirited", "Type": "Movie", "Name": "Spirited Away", "ProductionYear": 2001,
     "RunTimeTicks": 125 * 60 * TICKS, "Overview": "A girl in a world of spirits.", "UserData": ud()},
    {"Id": "mov-dune84", "Type": "Movie", "Name": "Dune", "ProductionYear": 1984, "RunTimeTicks": 137 * 60 * TICKS,
     "UserData": ud()},
    {"Id": "mov-dune21", "Type": "Movie", "Name": "Dune", "ProductionYear": 2021, "RunTimeTicks": 155 * 60 * TICKS,
     "UserData": ud(fav=True)},
    {"Id": "mov-jazz", "Type": "Movie", "Name": "Jazz on a Summer's Day", "ProductionYear": 1959,
     "RunTimeTicks": 85 * 60 * TICKS, "UserData": ud()},
    {"Id": "art-miles", "Type": "MusicArtist", "Name": "Miles Davis", "UserData": ud()},
    {"Id": "alb-kob", "Type": "MusicAlbum", "Name": "Kind of Blue", "AlbumArtist": "Miles Davis",
     "ProductionYear": 1959, "ArtistIds": ["art-miles"], "UserData": ud()},
    {"Id": "pl-road", "Type": "Playlist", "Name": "Road trip", "MediaType": "Audio", "ChildCount": 1,
     "UserData": ud()},
]
for n, title in enumerate(["So What", "Freddie Freeloader", "Blue in Green"], 1):
    ITEMS.append({"Id": f"aud-{n}", "Type": "Audio", "Name": title, "Album": "Kind of Blue",
                  "AlbumArtist": "Miles Davis", "Artists": ["Miles Davis"], "ParentId": "alb-kob",
                  "ArtistIds": ["art-miles"], "IndexNumber": n, "ParentIndexNumber": 1,
                  "RunTimeTicks": 9 * 60 * TICKS, "UserData": ud()})
for n in range(1, 11):
    ITEMS.append({"Id": f"ep-e{n}", "Type": "Episode", "Name": f"Episode title {n}", "SeriesId": "ser-edge",
                  "SeriesName": "Cyberpunk: Edgerunners", "SeasonId": "sea-edge-1", "ParentId": "sea-edge-1",
                  "ParentIndexNumber": 1, "IndexNumber": n, "RunTimeTicks": 25 * 60 * TICKS,
                  "UserData": ud(played=n == 1, pos=600 * TICKS if n == 2 else 0, pct=40 if n == 2 else None)})
PLAYLIST = {"pl-road": ["aud-1"]}
BY_ID = {i["Id"]: i for i in ITEMS}


def stream(index, kind, lang, title, **kw):
    return {"Index": index, "Type": kind, "Language": lang, "DisplayTitle": title, "Codec": kw.pop("codec", "aac"), **kw}


# The tracks a full item carries (GET /Items/{id}), as Jellyfin lists them;
# lists don't (no Fields=MediaSources).
EPISODE_STREAMS = [
    stream(0, "Video", None, "1080p HEVC", codec="hevc"),
    stream(1, "Audio", "jpn", "Japanese - AAC - Stereo", IsDefault=True, Channels=2),
    stream(2, "Audio", "eng", "English - AAC - 5.1", Channels=6),
    stream(3, "Subtitle", "eng", "English (Signs & Songs)", codec="ass", IsForced=True),
    stream(4, "Subtitle", "eng", "English - ASS", codec="ass"),
    stream(5, "Subtitle", "fre", "French - SRT", codec="srt", IsExternal=True),
]
MOVIE_STREAMS = [stream(0, "Video", None, "1080p H264", codec="h264"),
                 stream(1, "Audio", "eng", "English - AC3 - 5.1", IsDefault=True, Channels=6, codec="ac3")]
# The users' playback settings (UserConfiguration).
CONFIG = {u["Id"]: {"AudioLanguagePreference": None, "SubtitleLanguagePreference": None, "SubtitleMode": "Default",
                    "PlayDefaultAudioTrack": True, "HidePlayedInLatest": True} for u in USERS}
# While SESSIONSFILE.live exists, a player told to play reports it (its
# session's NowPlayingItem and track indexes), as a real one does.
LIVE = {}


def full(item):
    if item["Type"] == "Episode":
        return {**item, "MediaSources": [{"Id": item["Id"] + "-src", "MediaStreams": EPISODE_STREAMS}]}
    if item["Type"] == "Movie":
        return {**item, "MediaSources": [{"Id": item["Id"] + "-src", "MediaStreams": MOVIE_STREAMS}]}
    return item


def fold(s):
    return " ".join(re.sub(r"[^\w]+", " ", str(s).casefold()).split())


def page(items, query):
    limit = int(query.get("Limit", ["100"])[0] or 100)
    return {"Items": items[:limit], "TotalRecordCount": len(items), "StartIndex": 0}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def auth(self):
        header = self.headers.get("Authorization", "")
        fields = dict(re.findall(r'(\w+)="([^"]*)"', header))
        return fields

    def reply(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_DELETE(self):
        self.route("DELETE")

    def route(self, method):
        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query)
        path = url.path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else None
        fields = self.auth()
        client = {k: v for k, v in fields.items() if k != "Token"}
        logged_body = body
        if path == "/Users/AuthenticateByName" and isinstance(body, dict):
            logged_body = {**body, "Pw": "<given>" if body.get("Pw") else ""}
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps({"method": method, "path": path, "query": {k: v[0] for k, v in query.items()},
                                "body": logged_body, "client": client}) + "\n")
        if path == "/System/Info/Public":
            if __import__("os").environ.get("FAKE_SLOW"):
                time.sleep(3)
            return self.reply(200, {"ServerName": "Fake Jellyfin", "Version": "10.11.0", "Id": "srv-1",
                                    "ProductName": "Jellyfin Server"})
        if path == "/Users/AuthenticateByName" and method == "POST":
            name, pw = (body or {}).get("Username"), (body or {}).get("Pw")
            if pw not in ACCOUNTS.get(name, {}):
                return self.reply(401)
            user = next(u for u in USERS if u["Name"] == name)
            if name == "Khoa":
                token = "user-token-abc"
            else:
                slug = re.sub(r"[^a-z]", "", client.get("Client", "").lower())
                token = f"{name.lower()}-{slug}-{len(TOKENS)}"
            TOKENS[token] = {"user": user, "blocked": ACCOUNTS[name][pw]}
            return self.reply(200, {"User": {"Id": user["Id"], "Name": name}, "AccessToken": token,
                                    "ServerId": "srv-1", "SessionInfo": {}})
        token = fields.get("Token")
        me = None
        if token == KEY:
            pass
        elif token == "user-token-abc" or (token in TOKENS and not TOKENS[token]["blocked"]):
            me = TOKENS.get(token, {"user": USERS[1]})["user"]
        else:
            return self.reply(401)
        if path == "/Users/Me":
            return self.reply(200, {**me, "Configuration": CONFIG[me["Id"]]}) if me else self.reply(400)
        m = re.match(r"^/Users/([^/]+)$", path)
        if m and method == "GET" and m.group(1) not in ("Me",):
            user = next((u for u in USERS if u["Id"] == m.group(1)), None)
            if not user:
                return self.reply(404)
            if me and me["Id"] != user["Id"] and not me["Policy"]["IsAdministrator"]:
                return self.reply(403)
            return self.reply(200, {**user, "Configuration": CONFIG[user["Id"]]})
        if path == "/Users/Configuration" and method == "POST":
            uid = query.get("userId", [""])[0]
            if uid not in CONFIG or (me and me["Id"] != uid and not me["Policy"]["IsAdministrator"]):
                return self.reply(403)
            CONFIG[uid] = body
            return self.reply(204)
        if path == "/Sessions/Logout" and method == "POST":
            TOKENS.pop(token, None)
            return self.reply(204)
        admin = me is None or me["Policy"]["IsAdministrator"]
        old = __import__("os").path.exists(sessions_file + ".old")
        m = re.match(r"^/Users/([^/]+)(/.*)$", path)
        if m and m.group(1) not in ("AuthenticateByName", "Me") and m.group(2) != "":
            # The routes of older servers (and Emby): /Users/{id}/...
            sub = m.group(2)
            if sub == "/Items":
                path = "/Items"
            elif sub.startswith("/Items/") and sub not in ("/Items/Resume", "/Items/Latest"):
                path = "/Items/" + sub[len("/Items/"):]
            elif sub == "/Items/Resume":
                path = "/UserItems/Resume"
            elif sub == "/Items/Latest":
                path = "/Items/Latest"
            elif sub.startswith("/PlayedItems/"):
                path = "/UserPlayedItems/" + sub[len("/PlayedItems/"):]
            elif sub.startswith("/FavoriteItems/"):
                path = "/UserFavoriteItems/" + sub[len("/FavoriteItems/"):]
            legacy = True
        else:
            legacy = False
        if old and not legacy and (path.startswith(("/UserItems", "/UserPlayedItems", "/UserFavoriteItems"))
                                   or path in ("/Items", "/Items/Latest") or re.match(r"^/Items/[^/]+$", path)):
            if path != "/Items/Counts":
                return self.reply(404)
        if path == "/Users":
            return self.reply(200, USERS) if admin else self.reply(403)
        if path == "/Items/Counts":
            return self.reply(200, {"MovieCount": 4, "SeriesCount": 1, "EpisodeCount": 10, "SongCount": 3,
                                    "AlbumCount": 1})
        if path == "/Sessions":
            with open(sessions_file, encoding="utf-8") as f:
                sessions = json.load(f)
            if __import__("os").path.exists(sessions_file + ".live"):
                sessions = [{**x, **LIVE.get(x.get("Id"), {})} for x in sessions]
            if not admin:
                sessions = [x for x in sessions if x.get("UserId") == me["Id"]]
            return self.reply(200, sessions)
        if path == "/Items":
            items = [i for i in ITEMS if i["Type"] not in ("Season",)]
            if query.get("IncludeItemTypes"):
                kinds = set(query["IncludeItemTypes"][0].split(","))
                items = [i for i in items if i["Type"] in kinds]
            if query.get("searchTerm"):
                term = fold(query["searchTerm"][0])
                items = [i for i in items if term in fold(i["Name"])]
            if query.get("ParentId"):
                pid = query["ParentId"][0]
                if pid in PLAYLIST:
                    items = [BY_ID[x] for x in PLAYLIST[pid]]
                else:
                    items = [i for i in items if i.get("ParentId") == pid]
            if query.get("ArtistIds"):
                items = [i for i in items if query["ArtistIds"][0] in i.get("ArtistIds", [])]
            return self.reply(200, page(items, query))
        if path == "/Items/Latest":
            items = [i for i in ITEMS if i["Type"] in ("Movie", "Series", "MusicAlbum")]
            if query.get("IncludeItemTypes"):
                kinds = set(query["IncludeItemTypes"][0].split(","))
                items = [i for i in items if i["Type"] in kinds]
            return self.reply(200, items[: int(query.get("Limit", ["20"])[0])])
        if path == "/UserItems/Resume":
            return self.reply(200, page([BY_ID["ep-e2"]], query))
        if path == "/Shows/NextUp":
            return self.reply(200, page([BY_ID["ep-e2"]], query))
        m = re.match(r"^/Shows/([^/]+)/(Seasons|Episodes)$", path)
        if m:
            if m.group(1) != "ser-edge":
                return self.reply(404)
            if m.group(2) == "Seasons":
                return self.reply(200, page([BY_ID["sea-edge-1"]], query))
            eps = [i for i in ITEMS if i["Type"] == "Episode"]
            if query.get("seasonId") and query["seasonId"][0] != "sea-edge-1":
                eps = []
            return self.reply(200, page(eps, query))
        m = re.match(r"^/Items/([^/]+)$", path)
        if m and method == "GET":
            item = BY_ID.get(m.group(1))
            return self.reply(200, full(item)) if item else self.reply(404)
        m = re.match(r"^/(UserPlayedItems|UserFavoriteItems)/([^/]+)$", path)
        if m:
            if m.group(2) not in BY_ID:
                return self.reply(404)
            return self.reply(200, {"Played": method == "POST"})
        m = re.match(r"^/Playlists/([^/]+)/Items$", path)
        if m and method == "POST":
            return self.reply(204)
        m = re.match(r"^/Sessions/([^/]+)/(Playing|Command)(?:/(\w+))?$", path)
        if m and method == "POST":
            sid = m.group(1)
            if m.group(2) == "Playing" and not m.group(3) and query.get("playCommand", [""])[0] == "PlayNow":
                first = query["itemIds"][0].split(",")[0]
                LIVE[sid] = {"NowPlayingItem": BY_ID.get(first, {"Id": first}),
                             "PlayState": {"PositionTicks": 0, "IsPaused": False,
                                           "AudioStreamIndex": int(query.get("audioStreamIndex", ["1"])[0]),
                                           "SubtitleStreamIndex": int(query.get("subtitleStreamIndex", ["-1"])[0])}}
            elif m.group(2) == "Command" and isinstance(body, dict) and sid in LIVE:
                field = {"SetAudioStreamIndex": "AudioStreamIndex",
                         "SetSubtitleStreamIndex": "SubtitleStreamIndex"}.get(body.get("Name"))
                if field:
                    LIVE[sid]["PlayState"][field] = int(body["Arguments"]["Index"])
            return self.reply(204)
        return self.reply(404)


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
