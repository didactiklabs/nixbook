#!/usr/bin/env python3
"""Fake Google APIs for tests/accounts.sh: the OAuth token endpoint, the
People API (contacts and contact groups in memory, sync tokens as a change
counter, etags checked on update), the Tasks API under /tasksapi (lists
and tasks in memory, updatedMin and deletions, two items a page) and the
Calendar API under /calendarapi (a primary and a read-only calendar,
events with sync tokens, an expired one answering 410, instance ids for
one occurrence of a series: "<series>_<start>") and Gmail under
/gmailapi (and /gmailupload: labels, threads made of messages parsed from
what is sent, a tiny search, drafts, attachments, filters; a user
"noscope@…" answers 403 as an account signed in before mail was asked
for). Each
user's data is their own: the sign-in code says who signs in ("the-code":
me@example.com, "work-code": work@example.com), the tokens carry the email
("rt-<email>", "at-<email>"; any other bearer is me@example.com). Each
request is logged to the file in argv[2] as
"METHOD path?query body". Serves on 127.0.0.1:argv[1] (0: any; the port is
printed)."""

import base64
import email
import email.header
import json
import re
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
        "gmail": gmail_seed(),
    }


users_email = [""]


def use_user(who):
    """Points the module's data at that user's."""
    users_email[0] = who
    globals().update(users.setdefault(who, user_data()))


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
                   and (not since or t["updated"] >= since)
                   # As Google does: completedMin leaves out the tasks not completed.
                   and (not q.get("completedMin") or t.get("completed", "") >= q["completedMin"])]
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


def b64(data):
    return base64.urlsafe_b64encode(data if isinstance(data, bytes) else data.encode()).rstrip(b"=").decode()


def unb64(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def part_of(msg, part_id="0"):
    """An email.message as Gmail's payload: headers, each part's body decoded
    from its transfer encoding, attachments behind an attachmentId."""
    out = {"partId": part_id, "mimeType": msg.get_content_type(), "filename": msg.get_filename() or "",
           "headers": [{"name": k, "value": str(email.header.make_header(email.header.decode_header(str(v))))}
                       for k, v in msg.items()], "body": {"size": 0}}
    if msg.is_multipart():
        out["parts"] = [part_of(p, f"{part_id}.{i}" if part_id != "0" else str(i))
                        for i, p in enumerate(msg.get_payload())]
        return out
    data = msg.get_payload(decode=True) or b""
    out["body"]["size"] = len(data)
    if out["filename"]:
        out["body"]["attachmentId"] = "att-" + b64(data)[:12] + str(len(data))
        out["_data"] = b64(data)
    else:
        out["body"]["data"] = b64(data)
    return out


def gmail_seed():
    g = {"labels": {
        "Label_1": {"id": "Label_1", "name": "Receipts", "type": "user"},
    }, "messages": {}, "drafts": {}, "filters": {}, "n": [0]}
    for lid in ("INBOX", "UNREAD", "STARRED", "IMPORTANT", "SENT", "DRAFT", "SPAM", "TRASH", "CATEGORY_PERSONAL",
                "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS"):
        g["labels"][lid] = {"id": lid, "name": lid, "type": "system"}

    def add(mid, tid, raw, labels, when):
        msg = email.message_from_bytes(raw.encode("latin-1") if isinstance(raw, str) else raw)
        g["messages"][mid] = {"id": mid, "threadId": tid, "labelIds": labels, "internalDate": str(when),
                              "snippet": (msg.get("X-Snippet") or ""), "payload": part_of(msg)}
    add("m1", "t1", "From: Ana <ana@x.org>\r\nTo: me@example.com\r\nSubject: Lunch?\r\nMessage-ID: <m1@x.org>\r\n"
        "X-Snippet: Lunch tomorrow?\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nLunch tomorrow?\r\n",
        ["INBOX", "CATEGORY_PERSONAL"], 1762000000000)
    add("m2", "t1", "From: Ana <ana@x.org>\r\nTo: me@example.com\r\nCc: Bob <bob@x.org>\r\nSubject: Re: Lunch?\r\n"
        "Message-ID: <m2@x.org>\r\nReferences: <m1@x.org>\r\nX-Snippet: At noon then\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n\r\nAt noon then.\r\n\r\nOn Mon, Nov 3, 2026 at 9:00 AM Ana <ana@x.org> wrote:\r\n"
        "> Lunch tomorrow?\r\n", ["INBOX", "UNREAD", "CATEGORY_PERSONAL"], 1762003600000)
    add("m3", "t2", "From: Shop <news@shop.com>\r\nTo: me@example.com\r\nSubject: =?iso-8859-1?q?Soldes_d'=E9t=E9?=\r\n"
        "List-Unsubscribe: <mailto:u@shop.com>, <https://shop.com/unsub?u=1>\r\nX-Snippet: Tout &agrave; -50%\r\n"
        "Content-Type: text/html; charset=iso-8859-1\r\n\r\n<html><head><style>p{}</style></head><body><p>Tout \xe0 "
        "-50%</p><a href=\"https://shop.com/sale\">Voir</a></body></html>\r\n",
        ["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"], 1762100000000)
    add("m4", "t3", "From: Bob <bob@x.org>\r\nTo: me@example.com\r\nSubject: Invoice\r\nX-Snippet: Here it is\r\n"
        "Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nContent-Type: text/plain\r\n\r\nHere it is.\r\n--b\r\n"
        "Content-Type: application/pdf\r\nContent-Disposition: attachment; filename=\"../invoice.pdf\"\r\n"
        "Content-Transfer-Encoding: base64\r\n\r\nJVBERi0xLjQK\r\n--b--\r\n", ["INBOX", "Label_1"], 1762200000000)
    add("m5", "t4", "From: Old <old@x.org>\r\nTo: me@example.com\r\nSubject: Archived thing\r\nX-Snippet: old\r\n"
        "Content-Type: text/plain\r\n\r\nold\r\n", ["CATEGORY_PERSONAL"], 1761000000000)
    return g


def gmail_terms(q):
    """A search as (field, value, negated) terms: from:(x), in:inbox,
    is:unread, has:attachment, label:x, larger:N, -(x), words."""
    terms = []
    for m in re.finditer(r'(-?)(?:(\w+):)?(\([^)]*\)|"[^"]*"|\S+)', q or ""):
        neg, field, value = m.group(1) == "-", (m.group(2) or "").lower(), m.group(3).strip('()"').lower()
        terms.append((field, value, neg))
    return terms


def gmail_text(m):
    out = []

    def walk(p):
        out.append(" ".join(h["value"] for h in p["headers"] if h["name"].lower() in ("from", "to", "subject")))
        if "data" in p["body"]:
            out.append(unb64(p["body"]["data"]).decode("latin-1"))
        for c in p.get("parts", []):
            walk(c)
    walk(m["payload"])
    return " ".join(out).lower()


def gmail_header(m, name):
    return next((h["value"] for h in m["payload"]["headers"] if h["name"].lower() == name), "").lower()


def gmail_match(m, q, g):
    for field, value, neg in gmail_terms(q):
        if field == "in":
            ok = value.upper() in m["labelIds"] or value == "anywhere"
        elif field == "is":
            ok = value.upper() in m["labelIds"]
        elif field == "label":
            ok = any(g["labels"][l]["name"].lower() == value for l in m["labelIds"] if l in g["labels"])
        elif field == "has":
            ok = '"filename": "' not in json.dumps(m["payload"]).replace('"filename": ""', "")
        elif field in ("from", "to", "subject"):
            ok = value in gmail_header(m, field)
        elif field in ("larger", "smaller"):
            size = len(json.dumps(m["payload"]))
            ok = size > int(value) if field == "larger" else size < int(value)
        else:
            ok = all(w in gmail_text(m) for w in value.split())
        if ok == neg:
            return False
    # Gmail's default: not the trash nor spam.
    return "in:trash" in (q or "") or "in:spam" in (q or "") or not ({"TRASH", "SPAM"} & set(m["labelIds"]))


def gmail_public(m, fmt="full"):
    out = json.loads(json.dumps(m))

    def strip(p):
        p.pop("_data", None)
        if fmt == "metadata":
            p.pop("parts", None)
            p["body"] = {"size": p["body"].get("size", 0)}
        for c in p.get("parts", []):
            strip(c)
    strip(out["payload"])
    return out


def gmail_store(g, raw, labels, thread=None):
    msg = email.message_from_bytes(raw)
    g["n"][0] += 1
    mid = f"s{g['n'][0]}"
    tid = thread or mid
    body = msg.get_body(("plain",)) if hasattr(msg, "get_body") else None
    g["messages"][mid] = {"id": mid, "threadId": tid, "labelIds": labels, "internalDate": str(1763000000000 + g["n"][0]),
                          "snippet": "", "payload": part_of(msg), "_raw": raw.decode("latin-1")}
    return g["messages"][mid]


def gmail_upload(raw_bytes, content_type):
    """multipart/related: the JSON metadata, then the message."""
    whole = email.message_from_bytes(b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + raw_bytes)
    meta, msg = whole.get_payload()
    inner = msg.get_payload()[0] if msg.get_content_type() == "message/rfc822" else msg
    return json.loads(meta.get_payload()), inner.as_bytes()


def handle_gmail(h, method, path, q, body, g, upload=None):
    """Gmail's API, path without /gmailapi/users/me."""
    parts = path.strip("/").split("/")
    msgs = g["messages"]

    def threads():
        out = {}
        for m in sorted(msgs.values(), key=lambda m: int(m["internalDate"])):
            out.setdefault(m["threadId"], []).append(m)
        return out

    if parts == ["labels"] and method == "GET":
        return h.reply(200, {"labels": [{k: v for k, v in l.items()} for l in g["labels"].values()]})
    if parts == ["labels"] and method == "POST":
        if any(l["name"].lower() == body["name"].lower() for l in g["labels"].values()):
            return h.error(409, "Label name exists or conflicts", "ALREADY_EXISTS")
        g["n"][0] += 1
        lid = f"Label_{g['n'][0] + 100}"
        g["labels"][lid] = {"id": lid, "name": body["name"], "type": "user"}
        return h.reply(200, g["labels"][lid])
    if parts[0] == "labels" and len(parts) == 2:
        l = g["labels"].get(parts[1])
        if not l:
            return h.error(404, "Not Found", "NOT_FOUND")
        if method == "GET":
            mine = [m for m in msgs.values() if l["id"] in m["labelIds"]]
            tids = {m["threadId"] for m in mine}
            unread = {m["threadId"] for m in mine if "UNREAD" in m["labelIds"]}
            return h.reply(200, {**l, "threadsTotal": len(tids), "threadsUnread": len(unread),
                                 "messagesUnread": sum(1 for m in mine if "UNREAD" in m["labelIds"])})
        if method == "PATCH":
            l["name"] = body["name"]
            return h.reply(200, l)
        if method == "DELETE":
            del g["labels"][l["id"]]
            for m in msgs.values():
                m["labelIds"] = [x for x in m["labelIds"] if x != l["id"]]
            return h.reply(204)
    if parts == ["threads"] and method == "GET":
        found = [(tid, ms) for tid, ms in threads().items()
                 if any(gmail_match(m, q.get("q"), g) and (not q.get("labelIds") or q["labelIds"] in m["labelIds"]) for m in ms)]
        found.sort(key=lambda t: -int(t[1][-1]["internalDate"]))
        start, size = int(q.get("pageToken") or 0), int(q.get("maxResults") or 100)
        r = {"threads": [{"id": tid} for tid, _ in found[start:start + size]], "resultSizeEstimate": len(found)}
        if start + size < len(found):
            r["nextPageToken"] = str(start + size)
        return h.reply(200, r)
    if parts[0] == "threads" and len(parts) >= 2:
        ms = threads().get(parts[1])
        if not ms:
            return h.error(404, "Requested entity was not found.", "NOT_FOUND")
        verb = parts[2] if len(parts) > 2 else ""
        if method == "GET" and not verb:
            return h.reply(200, {"id": parts[1], "messages": [gmail_public(m, q.get("format", "full")) for m in ms]})
        for m in ms:
            if verb == "modify":
                m["labelIds"] = [l for l in m["labelIds"] if l not in (body.get("removeLabelIds") or [])]
                m["labelIds"] += [l for l in (body.get("addLabelIds") or []) if l not in m["labelIds"]]
            elif verb == "trash":
                m["labelIds"] = [l for l in m["labelIds"] if l != "INBOX"] + ["TRASH"]
            elif verb == "untrash":
                m["labelIds"] = [l for l in m["labelIds"] if l != "TRASH"]
        return h.reply(200, {"id": parts[1]})
    if parts == ["messages"] and method == "GET":
        found = sorted((m for m in msgs.values() if gmail_match(m, q.get("q"), g)), key=lambda m: -int(m["internalDate"]))
        return h.reply(200, {"messages": [{"id": m["id"], "threadId": m["threadId"]} for m in found]})
    if parts == ["messages", "batchModify"] and method == "POST":
        for mid in body["ids"]:
            m = msgs[mid]
            m["labelIds"] = [l for l in m["labelIds"] if l not in (body.get("removeLabelIds") or [])]
            m["labelIds"] += [l for l in (body.get("addLabelIds") or []) if l not in m["labelIds"]]
        return h.reply(204)
    if parts == ["messages", "send"] and method == "POST":
        meta, raw = upload if upload else (body, unb64(body["raw"]))
        m = gmail_store(g, raw, ["SENT"], meta.get("threadId"))
        return h.reply(200, {"id": m["id"], "threadId": m["threadId"], "labelIds": m["labelIds"]})
    if parts[0] == "messages" and len(parts) >= 2:
        m = msgs.get(parts[1])
        if not m:
            return h.error(404, "Requested entity was not found.", "NOT_FOUND")
        if len(parts) == 2 and method == "GET":
            return h.reply(200, gmail_public(m, q.get("format", "full")))
        if len(parts) == 4 and parts[2] == "attachments":
            found = []

            def walk(p):
                if p["body"].get("attachmentId") == parts[3]:
                    found.append(p)
                for c in p.get("parts", []):
                    walk(c)
            walk(m["payload"])
            if not found:
                return h.error(404, "Invalid attachment token", "NOT_FOUND")
            return h.reply(200, {"size": found[0]["body"]["size"], "data": found[0]["_data"]})
    if parts == ["drafts"] and method == "POST":
        meta, raw = upload if upload else (body, unb64(body["message"]["raw"]))
        m = gmail_store(g, raw, ["DRAFT"], meta["message"].get("threadId"))
        g["n"][0] += 1
        did = f"d{g['n'][0]}"
        g["drafts"][did] = m["id"]
        return h.reply(200, {"id": did, "message": {"id": m["id"], "threadId": m["threadId"]}})
    if parts == ["drafts"] and method == "GET":
        return h.reply(200, {"drafts": [{"id": d, "message": {"id": mid}} for d, mid in g["drafts"].items()]})
    if parts == ["drafts", "send"] and method == "POST":
        mid = g["drafts"].pop(body["id"], None)
        if not mid:
            return h.error(404, "Requested entity was not found.", "NOT_FOUND")
        msgs[mid]["labelIds"] = ["SENT"]
        return h.reply(200, {"id": mid, "threadId": msgs[mid]["threadId"], "labelIds": ["SENT"]})
    if parts[0] == "drafts" and len(parts) == 2:
        mid = g["drafts"].get(parts[1])
        if not mid:
            return h.error(404, "Requested entity was not found.", "NOT_FOUND")
        if method == "GET":
            return h.reply(200, {"id": parts[1], "message": gmail_public(msgs[mid], q.get("format", "full"))})
        if method == "DELETE":
            del g["drafts"][parts[1]]
            del msgs[mid]
            return h.reply(204)
    if parts == ["settings", "filters"]:
        if method == "GET":
            return h.reply(200, {"filter": list(g["filters"].values())} if g["filters"] else {})
        if method == "POST":
            if body.get("action", {}).get("forward"):
                return h.error(403, "Insufficient Permission", "PERMISSION_DENIED")
            if any(f["criteria"] == body["criteria"] and f["action"] == body["action"] for f in g["filters"].values()):
                return h.error(400, "Filter already exists", "FAILED_PRECONDITION")
            g["n"][0] += 1
            fid = f"ANe1Bm{g['n'][0]}"
            g["filters"][fid] = {"id": fid, "criteria": body["criteria"], "action": body["action"]}
            return h.reply(200, g["filters"][fid])
    if parts[:2] == ["settings", "filters"] and len(parts) == 3:
        f = g["filters"].get(parts[2])
        if not f:
            return h.error(404, "Filter not found", "NOT_FOUND")
        if method == "GET":
            return h.reply(200, f)
        if method == "DELETE":
            del g["filters"][parts[2]]
            return h.reply(204)
    return h.error(404, f"no route {method} {path}", "NOT_FOUND")


use_user("me@example.com")


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
        raw_bytes = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        raw = raw_bytes.decode("utf-8", "replace")
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
        for prefix in ("/gmailapi/users/me", "/gmailupload/users/me"):
            if path.startswith(prefix):
                if users_email[0].startswith("noscope@"):
                    return self.reply(403, {"error": {"code": 403, "message": "Request had insufficient authentication scopes.",
                                                      "status": "PERMISSION_DENIED",
                                                      "details": [{"reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}})
                upload = None
                if prefix == "/gmailupload/users/me":
                    upload = gmail_upload(raw_bytes, self.headers.get("Content-Type", ""))
                    body = {}
                else:
                    body = json.loads(raw) if raw else {}
                return handle_gmail(self, method, path[len(prefix):], q, body, gmail, upload)
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
            # The photo: the JPEG's bytes in, a URL out (Google's default
            # silhouette, `default`, once removed); the person back.
            if method == "PATCH" and verb == "updateContactPhoto":
                data = base64.b64decode(body.get("photoBytes", ""))
                if not data.startswith(b"\xff\xd8"):
                    return self.error(400, "Invalid photo.", "INVALID_ARGUMENT")
                counter[0] += 1
                people[pid]["photos"] = [{"url": f"https://lh3.googleusercontent.com/fake/{pid}-{counter[0]}=s100",
                                          "_bytes": len(data)}]
                bump(pid)
                return self.reply(200, {"person": people[pid]})
            if method == "DELETE" and verb == "deleteContactPhoto":
                people[pid]["photos"] = [{"url": "https://lh3.googleusercontent.com/default=s100", "default": True}]
                bump(pid)
                return self.reply(200, {"person": people[pid]})
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
