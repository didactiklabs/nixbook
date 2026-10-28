"""A fake Seerr for seerr-mcp's tests (stdlib only).

  fake-seerr.py PORTFILE LOGFILE

Listens on 127.0.0.1 (a free port, written to PORTFILE) and logs every
request as a JSON line {method, path, raw_query, query, body, as} to LOGFILE
(`as`: the X-API-User header; never the key). Only X-Api-Key: test-key-123
is accepted; X-API-User makes the request that user's. Requests made are
kept in memory: a request's media turns "requested".
"""

import json
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = "test-key-123"
port_file, log_file = sys.argv[1:3]

USERS = [
    {"id": 1, "displayName": "Admin", "email": "admin@example.org", "permissions": 2},
    {"id": 2, "displayName": "Khoa", "email": "khoa@example.org", "jellyfinUsername": "khoa", "permissions": 32},
]
MOVIES = {
    438631: {"id": 438631, "title": "Dune", "releaseDate": "2021-09-15", "runtime": 155, "overview": "Paul Atreides.",
             "genres": [{"name": "Science Fiction"}], "mediaInfo": {"status": 5, "status4k": 1, "requests": []}},
    693134: {"id": 693134, "title": "Dune: Part Two", "releaseDate": "2024-02-27", "runtime": 166,
             "overview": "Paul unites with Chani.", "genres": [{"name": "Science Fiction"}]},
}
TV = {
    105248: {"id": 105248, "name": "Cyberpunk: Edgerunners", "firstAirDate": "2022-09-13", "overview": "Night City.",
             "seasons": [{"seasonNumber": 0, "episodeCount": 2}, {"seasonNumber": 1, "episodeCount": 10},
                         {"seasonNumber": 2, "episodeCount": 10}, {"seasonNumber": 3, "episodeCount": 8}],
             "mediaInfo": {"status": 4, "seasons": [{"seasonNumber": 1, "status": 5}], "requests": []}},
}
REQUESTS = []
# Logins (the session cookie connect.sid): one live, Khoa's; any other has
# ended (Seerr answers it 403, as a missing permission).
SESSIONS = {"s%3Akhoa-session.sig": USERS[1]}


def media_of(kind, tmdb):
    item = (MOVIES if kind == "movie" else TV).get(tmdb)
    return item


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

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
        query = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else None
        who = self.headers.get("X-API-User")
        cookie = dict(p.strip().split("=", 1) for p in (self.headers.get("Cookie") or "").split(";") if "=" in p)
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps({"method": method, "path": url.path, "raw_query": url.query, "query": query,
                                "body": body, "as": who, "session": "connect.sid" in cookie,
                                "key": self.headers.get("X-Api-Key") is not None}) + "\n")
        path = url.path
        if not path.startswith("/api/v1/"):
            return self.reply(404)
        path = path[len("/api/v1"):]
        if "connect.sid" in cookie:
            me = SESSIONS.get(cookie["connect.sid"])
            if not me:
                return self.reply(403, {"message": "You do not have permission to access this endpoint."})
        elif self.headers.get("X-Api-Key") != KEY:
            return self.reply(401, {"message": "Unauthorized"})
        else:
            me = next((u for u in USERS if str(u["id"]) == str(who)), USERS[0]) if who else USERS[0]
        if path == "/user" and me["id"] != 1:
            return self.reply(403, {"message": "You do not have permission to access this endpoint."})
        if path == "/status":
            return self.reply(200, {"version": "3.0.0", "commitTag": "test"})
        if path == "/auth/me":
            return self.reply(200, me)
        if path == "/user":
            return self.reply(200, {"pageInfo": {"results": len(USERS)}, "results": USERS})
        m = re.match(r"^/user/(\d+)/quota$", path)
        if m:
            return self.reply(200, {"movie": {"limit": 10, "used": len([r for r in REQUESTS if r["type"] == "movie"]),
                                              "remaining": 10 - len([r for r in REQUESTS if r["type"] == "movie"]), "days": 7},
                                    "tv": {"limit": 0, "used": 0, "remaining": 0, "days": 7}})
        if path == "/search":
            q = query.get("query", "").casefold()
            # Like TMDB: every word of the query in the title.
            words = re.findall(r"\w+", q)
            hit = lambda t: all(w in re.findall(r"\w+", t.casefold()) for w in words)  # noqa: E731
            res = [{**v, "mediaType": "movie"} for v in MOVIES.values() if hit(v["title"])]
            res += [{**v, "mediaType": "tv"} for v in TV.values() if hit(v["name"])]
            res += [{"id": 1, "mediaType": "person", "name": "Dune Person"}] if "dune" in q else []
            return self.reply(200, {"page": 1, "totalPages": 1, "totalResults": len(res), "results": res})
        m = re.match(r"^/(movie|tv)/(\d+)$", path)
        if m:
            item = media_of(m.group(1), int(m.group(2)))
            return self.reply(200, item) if item else self.reply(404, {"message": "Not found"})
        if path == "/request/count":
            return self.reply(200, {"total": len(REQUESTS), "pending": len([r for r in REQUESTS if r["status"] == 1])})
        if path == "/request" and method == "GET":
            res = [r for r in REQUESTS if not query.get("requestedBy") or str(r["requestedBy"]["id"]) == query["requestedBy"]]
            if query.get("filter") == "pending":
                res = [r for r in res if r["status"] == 1]
            return self.reply(200, {"pageInfo": {"results": len(res)}, "results": list(reversed(res))[: int(query.get("take", 20))]})
        if path == "/request" and method == "POST":
            kind, tmdb = body["mediaType"], body["mediaId"]
            item = media_of(kind, tmdb)
            if not item:
                return self.reply(404, {"message": "Not found"})
            r = {"id": 100 + len(REQUESTS), "status": 1, "type": kind, "is4k": bool(body.get("is4k")),
                 "createdAt": "2026-10-28T20:00:00.000Z", "requestedBy": me,
                 "media": {"tmdbId": tmdb, "mediaType": kind, "status": 2},
                 "seasons": [{"seasonNumber": s} for s in body.get("seasons") or []]}
            REQUESTS.append(r)
            info = item.setdefault("mediaInfo", {"status": 2, "requests": []})
            info.setdefault("requests", []).append(r)
            if kind == "movie":
                info["status"] = 2
            return self.reply(201, r)
        m = re.match(r"^/request/(\d+)(?:/(approve|decline))?$", path)
        if m:
            r = next((x for x in REQUESTS if x["id"] == int(m.group(1))), None)
            if not r:
                return self.reply(404, {"message": "Not found"})
            if method == "DELETE":
                if r["requestedBy"]["id"] != me["id"] and me["id"] != 1:
                    return self.reply(403, {"message": "You do not have permission to delete this request."})
                REQUESTS.remove(r)
                return self.reply(204)
            if m.group(2):
                if me["id"] != 1:
                    return self.reply(403, {"message": "You do not have permission to modify this request."})
                r["status"] = 2 if m.group(2) == "approve" else 3
                return self.reply(200, r)
        if path in ("/discover/trending", "/discover/movies", "/discover/movies/upcoming"):
            res = [{**v, "mediaType": "movie"} for v in MOVIES.values()]
            if path == "/discover/trending":
                res += [{**v, "mediaType": "tv"} for v in TV.values()]
            return self.reply(200, {"page": 1, "results": res})
        if path in ("/discover/tv", "/discover/tv/upcoming"):
            return self.reply(200, {"page": 1, "results": [{k: v for k, v in x.items()} for x in TV.values()]})
        return self.reply(404, {"message": "Not found"})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
