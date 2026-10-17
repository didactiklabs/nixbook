#!/usr/bin/env python3
"""Fake Google APIs for tests/accounts.sh: the OAuth token endpoint, the
People API (contacts and contact groups in memory, sync tokens as a change
counter, etags checked on update), the Tasks API under /tasksapi (lists
and tasks in memory, updatedMin and deletions, two items a page) and the
Calendar API under /calendarapi (a primary and a read-only calendar,
events with sync tokens, an expired one answering 410, instance ids for
one occurrence of a series: "<series>_<start>"). Each
user's data is their own: the sign-in code says who signs in ("the-code":
me@example.com, "work-code": work@example.com), the tokens carry the email
("rt-<email>", "at-<email>"; any other bearer is me@example.com). Each
request is logged to the file in argv[2] as
"METHOD path?query body". Serves on 127.0.0.1:argv[1] (0: any; the port is
printed)."""

import base64
import json
import sys
from datetime import datetime, timezone
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

counter = [0]
log_path = sys.argv[2]
CODES = {"the-code": "me@example.com", "work-code": "work@example.com"}
users = {}


def user_data():
    return {
        "people": {},   # id -> person
        "deleted": {},  # id -> change number
        "changed": {},  # id -> change number
        "groups": {
            "myContacts": {"resourceName": "contactGroups/myContacts", "groupType": "SYSTEM_CONTACT_GROUP", "name": "myContacts"},
            "starred": {"resourceName": "contactGroups/starred", "groupType": "SYSTEM_CONTACT_GROUP", "name": "starred"},
        },
        "task_lists": {"L1": {"id": "L1", "title": "My Tasks"}},
        "tasks": {},  # id -> task (with "_list"; deleted ones kept, "deleted": true)
        "calendars": [
            {"id": "primary-cal", "summary": "Me", "primary": True, "accessRole": "owner", "backgroundColor": "#039be5",
             "defaultReminders": [{"method": "popup", "minutes": 10}, {"method": "email", "minutes": 60}]},
            {"id": "holidays", "summary": "Holidays", "accessRole": "reader", "backgroundColor": "#0b8043"},
            {"id": "hidden-cal", "summary": "Hidden", "accessRole": "owner", "hidden": True},
        ],
        "events": {},  # id -> event (with "_cal", "_rev"; cancelled ones kept)
    }


def use_user(email):
    """Points the module's data at that user's."""
    globals().update(users.setdefault(email, user_data()))


use_user("me@example.com")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def public(t):
    return {k: v for k, v in t.items() if not k.startswith("_")}


def page(items, q):
    start = int(q.get("pageToken") or 0)
    r = {"items": items[start:start + 2]}
    if start + 2 < len(items):
        r["nextPageToken"] = str(start + 2)
    return r


def handle_calendar(h, method, path, q, body):
    """The Calendar API, path without /calendarapi."""
    parts = path.strip("/").split("/")
    if parts == ["users", "me", "calendarList"] and method == "GET":
        return h.reply(200, {"items": calendars})
    if parts[0] != "calendars" or len(parts) < 3 or parts[2] != "events":
        return h.error(404, f"no route {method} {path}", "NOT_FOUND")
    cal = urllib.parse.unquote(parts[1])
    if len(parts) == 3 and method == "GET":
        since = q.get("syncToken")
        if since == "expired":
            return h.error(410, "Sync token is no longer valid, a full sync is required.", "GONE")
        items = [public(e) for e in events.values() if e["_cal"] == cal and (since or e.get("status") != "cancelled")
                 and (not since or e["_rev"] > int(since))]
        r = {"items": items, "nextSyncToken": str(counter[0])}
        return h.reply(200, r)
    if len(parts) == 3 and method == "POST":
        eid = new_id("ev")
        e = dict(body, id=eid, status="confirmed", updated=now_iso(), _cal=cal, _rev=counter[0])
        events[eid] = e
        return h.reply(200, public(e))
    eid = urllib.parse.unquote(parts[3])
    e = events.get(eid)
    if e is None and "_" in eid and events.get(eid.rsplit("_", 1)[0], {}).get("recurrence"):
        # One occurrence of a series: made on its first change.
        master = events[eid.rsplit("_", 1)[0]]
        stamp = eid.rsplit("_", 1)[1]
        original = ({"date": f"{stamp[:4]}-{stamp[4:6]}-{stamp[6:8]}"} if len(stamp) == 8 else
                    {"dateTime": f"{stamp[:4]}-{stamp[4:6]}-{stamp[6:8]}T{stamp[9:11]}:{stamp[11:13]}:{stamp[13:15]}Z"})
        e = {k: v for k, v in master.items() if k not in ("recurrence", "id")}
        e.update(id=eid, recurringEventId=master["id"], originalStartTime=original, start=original)
        events[eid] = e
    if e is None or e["_cal"] != cal:
        return h.error(404, "Not Found", "NOT_FOUND")
    counter[0] += 1
    if len(parts) == 5 and parts[4] == "move" and method == "POST":
        e.update(_cal=q["destination"], _rev=counter[0], updated=now_iso())
        return h.reply(200, public(e))
    if method == "PATCH":
        e.update(body)
        e.update(_rev=counter[0], updated=now_iso())
        return h.reply(200, public(e))
    if method == "DELETE":
        e.update(status="cancelled", _rev=counter[0])
        return h.reply(204)
    return h.error(404, f"no route {method} {path}", "NOT_FOUND")


def handle_tasks(h, method, path, q, body):
    """The Tasks API, path without /tasksapi."""
    parts = path.strip("/").split("/")
    if parts[:2] == ["users", "@me"] and parts[2:3] == ["lists"]:
        if len(parts) == 3 and method == "GET":
            return h.reply(200, page(list(task_lists.values()), q))
        if len(parts) == 3 and method == "POST":
            lid = new_id("list")
            task_lists[lid] = {"id": lid, "title": body["title"]}
            return h.reply(200, task_lists[lid])
        lid = parts[3]
        if lid not in task_lists:
            return h.error(404, "Task list not found.", "NOT_FOUND")
        if method == "PATCH":
            task_lists[lid]["title"] = body["title"]
            return h.reply(200, task_lists[lid])
        if method == "DELETE":
            if lid == "L1":
                return h.error(400, "Invalid value: the default list can't be deleted.", "INVALID_ARGUMENT")
            del task_lists[lid]
            for t in tasks.values():
                if t["_list"] == lid:
                    t["deleted"] = True
            return h.reply(204)
    if parts[0] == "lists" and len(parts) >= 3 and parts[2] == "tasks":
        lid = parts[1]
        if lid not in task_lists:
            return h.error(404, "Task list not found.", "NOT_FOUND")
        if len(parts) == 3 and method == "GET":
            since = q.get("updatedMin")
            out = [public(t) for t in tasks.values() if t["_list"] == lid
                   and (not t.get("deleted") or (since and q.get("showDeleted") == "true"))
                   and (not since or t["updated"] >= since)]
            return h.reply(200, page(out, q))
        if len(parts) == 3 and method == "POST":
            tid = new_id("t")
            t = {"id": tid, "title": body.get("title", ""), "status": body.get("status", "needsAction"),
                 "position": f"{counter[0]:020d}", "updated": now_iso(), "_list": lid}
            for k in ("notes", "due"):
                if k in body:
                    t[k] = body[k]
            if q.get("parent"):
                t["parent"] = q["parent"]
            if t["status"] == "completed":
                t["completed"] = now_iso()
            tasks[tid] = t
            return h.reply(200, public(t))
        tid = parts[3]
        t = tasks.get(tid)
        if not t or t["_list"] != lid or t.get("deleted"):
            return h.error(404, "Task not found.", "NOT_FOUND")
        if len(parts) == 5 and parts[4] == "move" and method == "POST":
            dest = q.get("destinationTasklist", lid)
            if dest not in task_lists:
                return h.error(400, "Invalid destination list.", "INVALID_ARGUMENT")
            t["_list"], t["updated"] = dest, now_iso()
            return h.reply(200, public(t))
        if method == "GET":
            return h.reply(200, public(t))
        if method == "PUT":
            for k in ("title", "notes", "due", "status", "completed"):
                if k in body:
                    t[k] = body[k]
                else:
                    t.pop(k, None)
            if t.get("status") == "completed" and "completed" not in t:
                t["completed"] = now_iso()
            t["updated"] = now_iso()
            return h.reply(200, public(t))
        if method == "DELETE":
            t["deleted"], t["updated"] = True, now_iso()
            for c in tasks.values():
                if c.get("parent") == tid:
                    c["deleted"], c["updated"] = True, now_iso()
            return h.reply(204)
    return h.error(404, f"no route {method} {path}", "NOT_FOUND")


def bump(pid):
    counter[0] += 1
    changed[pid] = counter[0]


def new_id(prefix):
    counter[0] += 1
    return f"{prefix}{counter[0]}"


def stored(pid, body):
    p = {k: v for k, v in body.items() if k not in ("etag", "resourceName")}
    p["resourceName"] = f"people/{pid}"
    p["etag"] = f"e{counter[0] + 1}"
    for n in p.get("names", []):
        if "unstructuredName" in n and "givenName" not in n:
            parts = n["unstructuredName"].split(" ", 1)
            n["givenName"], n["familyName"] = parts[0], parts[1] if len(parts) > 1 else ""
        n["displayName"] = " ".join(x for x in (n.get("givenName"), n.get("familyName")) if x)
    for a in p.get("addresses", []):
        a["formattedValue"] = "\n".join(x for x in (a.get("streetAddress"), a.get("city")) if x)
    if not any(m.get("contactGroupMembership") for m in p.get("memberships", [])):
        p["memberships"] = [{"contactGroupMembership": {"contactGroupResourceName": "contactGroups/myContacts"}}]
    p["metadata"] = {"sources": [{"type": "CONTACT", "updateTime": f"2026-10-17T10:00:{counter[0] % 60:02d}Z"}]}
    return p


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body=None):
        # 204, as Google answers a delete: no body.
        data = b"" if code == 204 else json.dumps(body if body is not None else {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def error(self, code, message, status):
        self.reply(code, {"error": {"code": code, "message": message, "status": status}})

    def handle_any(self, method):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        with open(log_path, "a") as f:
            f.write(f"{method} {url.path}{'?' + url.query if url.query else ''} {raw}\n")
        path = url.path

        if path == "/token":
            form = {k: v[0] for k, v in urllib.parse.parse_qs(raw).items()}
            if form.get("refresh_token") == "revoked":
                return self.reply(400, {"error": "invalid_grant", "error_description": "Token has been expired or revoked."})
            if form.get("grant_type") == "authorization_code":
                email = CODES.get(form.get("code"))
                claims = base64.urlsafe_b64encode(json.dumps({"email": email}).encode()).rstrip(b"=").decode()
                ok = email and form.get("code_verifier")
                return self.reply(200 if ok else 400, {"access_token": f"at-{email}", "refresh_token": f"rt-{email}",
                                                       "expires_in": 3600, "id_token": f"h.{claims}.s"} if ok else {"error": "invalid_grant"})
            refresh = form.get("refresh_token", "")
            return self.reply(200, {"access_token": "at-" + refresh.removeprefix("rt-"), "expires_in": 3600})
        if path == "/revoke":
            return self.reply(200)
        auth = self.headers.get("Authorization", "")
        if auth == "":
            return self.error(401, "no token", "UNAUTHENTICATED")
        bearer = auth.removeprefix("Bearer ")
        use_user(bearer.removeprefix("at-") if bearer.startswith("at-") and "@" in bearer else "me@example.com")
        body = json.loads(raw) if raw else {}
        if path.startswith("/tasksapi/"):
            return handle_tasks(self, method, path[len("/tasksapi"):], q, body)
        if path.startswith("/calendarapi/"):
            return handle_calendar(self, method, path[len("/calendarapi"):], q, body)

        if path == "/people/me/connections" and method == "GET":
            since = q.get("syncToken")
            if since == "expired":
                return self.error(400, "Sync token is expired. Clear local cache and retry call without the sync token.", "FAILED_PRECONDITION")
            if since:
                n = int(since)
                out = [people[i] for i, c in changed.items() if c > n and i in people]
                out += [{"resourceName": f"people/{i}", "metadata": {"deleted": True}} for i, c in deleted.items() if c > n]
            else:
                out = list(people.values())
            # Two pages, to check paging.
            start = int(q.get("pageToken") or 0)
            page = out[start:start + 2]
            r = {"connections": page}
            if start + 2 < len(out):
                r["nextPageToken"] = str(start + 2)
            else:
                r["nextSyncToken"] = str(counter[0])
            return self.reply(200, r)
        if path == "/people:createContact" and method == "POST":
            pid = new_id("c")
            people[pid] = stored(pid, body)
            bump(pid)
            return self.reply(200, people[pid])
        if path.startswith("/people/"):
            rest = path[len("/people/"):]
            pid, _, verb = rest.partition(":")
            if pid not in people:
                return self.error(404, "Requested entity was not found.", "NOT_FOUND")
            if method == "GET" and not verb:
                return self.reply(200, people[pid])
            if method == "PATCH" and verb == "updateContact":
                if body.get("etag") != people[pid]["etag"]:
                    return self.error(400, "etag mismatch", "FAILED_PRECONDITION")
                p = dict(people[pid])
                for field in q["updatePersonFields"].split(","):
                    p[field] = body.get(field, [])
                people[pid] = stored(pid, p)
                bump(pid)
                return self.reply(200, people[pid])
            if method == "DELETE" and verb == "deleteContact":
                del people[pid]
                counter[0] += 1
                deleted[pid] = counter[0]
                return self.reply(200)
        if path == "/contactGroups" and method == "GET":
            out = []
            for g in groups.values():
                n = sum(1 for p in people.values() for m in p.get("memberships", [])
                        if m.get("contactGroupMembership", {}).get("contactGroupResourceName") == g["resourceName"])
                out.append({**g, "formattedName": g["name"], "memberCount": n})
            return self.reply(200, {"contactGroups": out})
        if path == "/contactGroups" and method == "POST":
            gid = new_id("g")
            groups[gid] = {"resourceName": f"contactGroups/{gid}", "groupType": "USER_CONTACT_GROUP",
                           "name": body["contactGroup"]["name"], "etag": "g1"}
            return self.reply(200, {**groups[gid], "formattedName": groups[gid]["name"]})
        if path.startswith("/contactGroups/"):
            gid = path.split("/")[2]
            if gid not in groups:
                return self.error(404, "Requested entity was not found.", "NOT_FOUND")
            if method == "GET":
                return self.reply(200, groups[gid])
            if method == "PUT":
                groups[gid]["name"] = body["contactGroup"]["name"]
                return self.reply(200, groups[gid])
            if method == "DELETE":
                del groups[gid]
                for p in people.values():
                    p["memberships"] = [m for m in p.get("memberships", [])
                                        if m.get("contactGroupMembership", {}).get("contactGroupResourceName") != f"contactGroups/{gid}"]
                return self.reply(200)
        return self.error(404, f"no route {method} {path}", "NOT_FOUND")

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")

    def do_PUT(self):
        self.handle_any("PUT")

    def do_DELETE(self):
        self.handle_any("DELETE")


server = HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
print(server.server_port, flush=True)
server.serve_forever()
