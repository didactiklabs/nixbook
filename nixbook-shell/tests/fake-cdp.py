"""A stand-in for an Electron app started with --remote-debugging-pipe, for
tests/electron-bridge.sh and tests/desktop-mcp.sh: the bridge
(scripts/electron-bridge.py) starts it as the app, and it answers the
DevTools protocol on fds 3 (requests) and 4 (answers) with canned pages:
a Discord-like window, a splash and a DevTools page (never listed). It runs
no JavaScript: a Runtime.evaluate is recognised by the call the bridge puts
on its last line (`;nixbookPage(op, args)` in an isolated world, or
`;nixbookApp(op, args)` in the main world) and answered as the real code
would. Each message is logged (one JSON line) to $FAKE_CDP_LOG.

  FAKE_CDP_LOG=FILE fake-cdp.py [ARGS…]
  FAKE_CDP_APP=gmail: Meru's pages (its window, two Gmail accounts).
  FAKE_CDP_HANDOVER=1: quits at once, like an app handing over to one already running.
  FAKE_CDP_QUIT_AFTER=S: quits on its own S seconds in, with FAKE_CDP_QUIT_CODE (default 0).
  FAKE_CDP_RELAUNCH=DIR: relaunches itself as Electron's app.relaunch() does, a
  moment after starting: a new process naming DIR/app.asar (unbridged), then quits.
"""

import json
import os
import re
import sys

LOG = os.environ.get("FAKE_CDP_LOG") or os.devnull
if os.environ.get("FAKE_CDP_HANDOVER") == "1":
    sys.exit(0)

with open(LOG, "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:]}) + "\n")

if os.environ.get("FAKE_CDP_RELAUNCH"):
    import subprocess
    import time
    time.sleep(1)
    subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)",
                      os.environ["FAKE_CDP_RELAUNCH"] + "/opt/app.asar"],
                     start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)
    sys.exit(0)

if os.environ.get("FAKE_CDP_QUIT_AFTER"):
    import threading
    threading.Timer(float(os.environ["FAKE_CDP_QUIT_AFTER"]),
                    lambda: os._exit(int(os.environ.get("FAKE_CDP_QUIT_CODE") or 0))).start()

TARGETS = [
    {"targetId": "T0", "type": "page", "title": "Vesktop", "url": "vesktop://static/views/splash.html"},
    {"targetId": "T1", "type": "page", "title": "Discord | #general", "url": "https://discord.com/channels/111/222"},
    {"targetId": "TD", "type": "page", "title": "DevTools", "url": "devtools://devtools/bundled/inspector.html"},
]
if os.environ.get("FAKE_CDP_APP") == "gmail":
    # Meru: its own window (a file), then one Gmail page per account.
    TARGETS = [
        {"targetId": "T0", "type": "page", "title": "Meru", "url": "file:///opt/meru/renderer/main.html"},
        {"targetId": "T1", "type": "page", "title": "Inbox - me@example.com - Gmail",
         "url": "https://mail.google.com/mail/u/0/#inbox"},
        {"targetId": "T2", "type": "page", "title": "Inbox - work@example.com - Gmail",
         "url": "https://mail.google.com/mail/u/1/#inbox"},
    ]
JPEG = ("/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////"
        "////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AN//Z")
typed = {"text": ""}
CHANNEL = {"id": "222222222222222222", "kind": "channel", "name": "#general", "guild": "Friends"}


def log(entry):
    with open(LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")


def page(op, o, params):
    if params.get("contextId") is None:
        return {"error": "fake: the page code ran in the main world"}
    if op == "read":
        return {"title": "Discord | #general", "url": TARGETS[1]["url"], "text": "Hello from #general",
                "textTotal": 19, "total": 4, "shown": 4, "selection": "", "elements": [
                    {"ref": 1, "role": "text editor", "name": "Message #general"},
                    {"ref": 2, "role": "button", "name": "Send a gift"},
                    {"ref": 3, "role": "password field", "name": "Password", "password": True},
                    {"ref": 4, "role": "button", "name": "Upload a file"}]}
    if op == "act":
        if o.get("ref") == 3:
            return {"error": "refused: password fields are off limits; ask the user to do this step"}
        if o.get("action") == "type" and o.get("host"):
            if not o.get("append"):
                typed["text"] = ""
            return {"host": "insert"}
        if o.get("action") == "press" and o.get("host"):
            return {"host": "key", "key": o.get("value") or "Enter"}
        return {"done": o.get("action"), "element": {"role": "button", "name": o.get("name")}}
    if op == "changes":
        return {"appeared": [{"ref": 5, "role": "button", "name": "Edit message"}], "appearedTotal": 1, "gone": 0,
                "newText": [], "total": 5}
    if op == "state":
        return {"element": {"role": "text editor", "name": "Message #general", "value": typed["text"]}}
    if op == "ready":
        return {"state": "complete", "url": TARGETS[1]["url"], "title": TARGETS[1]["title"]}
    if op == "has":
        return {"found": str(o.get("text") or "") in "Hello from #general"}
    return {"error": f"unknown page operation {op}"}


def actual(op, o):
    """FAKE_CDP_APP=actual: Actual Budget's adapter (electron/actual.js) as it answers."""
    if op == "status":
        return {"ready": True, "open": True, "budget": "Home", "currency": "EUR"}
    if op == "month":
        return {"currency": "EUR", "month": o.get("month") or "2026-11", "income": 2500, "budgeted": -1800,
                "spent": -70.5, "balance": 1729.5, "toBudget": 700, "groups": [
                    {"id": "g1", "name": "Food", "income": False, "hidden": False, "budgeted": 600, "spent": -70.5,
                     "balance": 529.5, "categories": [
                         {"id": "c1", "name": "Groceries", "hidden": False, "budgeted": 400, "spent": -42.5,
                          "balance": 357.5}]}]}
    if op == "categories":
        return {"currency": "EUR", "month": "2026-11", "query": o.get("query"), "matches": [
            {"kind": "category", "group": "Food", "name": "Groceries", "budgeted": 400, "spent": -42.5,
             "balance": 357.5}]}
    if op == "transactions":
        return {"currency": "EUR", "from": "2026-11-01", "to": "2026-11-02", "count": 1, "total": -42.5,
                "spent": -42.5, "received": 0, "transactions": [
                    {"date": "2026-11-01", "amount": -42.5, "payee": "Carrefour", "category": "Groceries",
                     "account": "Checking", "notes": "weekly shop", "id": "t1"}]}
    # The writes, as the adapter answers them (tests/actual-tests.js checks
    # the adapter itself).
    if op == "add":
        return {"currency": "EUR", "added": {"id": "t9", "date": o.get("date") or "2026-11-08",
                                             "amount": o.get("amount"), "payee": o.get("payee") or "",
                                             "category": "Groceries" if o.get("category") else "",
                                             "account": "Checking", "notes": o.get("notes") or ""}}
    if op == "update":
        return {"currency": "EUR", "updated": o.get("id"), "changed": sorted(k for k in o if k != "id")}
    if op == "delete":
        return {"currency": "EUR", "deleted": {"id": o.get("id"), "date": "2026-11-01", "amount": -42.5}}
    if op == "set_budget":
        return {"currency": "EUR", "month": o.get("month") or "2026-11", "category": "Groceries",
                "budgeted": o.get("amount"), "before": 400}
    if op == "move_budget":
        return {"currency": "EUR", "month": "2026-11", "moved": o.get("amount"),
                "from": {"category": "Rent", "budgeted": 1150}, "to": {"category": "Restaurants", "budgeted": 250}}
    if op == "create_category":
        return {"currency": "EUR", "created": {"id": "c9", "name": o.get("name"), "group": "Food"}}
    if op == "schedules":
        return {"currency": "EUR", "schedules": [
            {"id": "s1", "name": "Rent", "next_date": "2026-12-01", "completed": False, "auto_post": True,
             "payee": "Landlord", "account": "Checking", "amount_op": "is", "amount": -1200,
             "date": {"frequency": "monthly", "interval": 1, "start": "2026-01-01", "endMode": "never"}}]}
    if op in ("rules", "payees") or "_" in op or op in ("sync", "call", "hold"):
        # The other operations: what reached the page, said back.
        return {"op": op, "args": o}
    return {"error": f"unknown operation {op}"}


def app(op, o, params):
    if params.get("contextId") is not None:
        return {"error": "fake: the app's code ran in an isolated world"}
    if os.environ.get("FAKE_CDP_APP") == "actual":
        return actual(op, o)
    if os.environ.get("FAKE_CDP_APP") in ("slack", "youtube-music"):
        # Their adapters are checked by app-adapters-tests.js: what reached
        # the page, said back.
        return {"op": op, "args": o}
    if op == "status":
        # A key the bridge must never pass on.
        return {"loggedIn": True, "user": "Me", "current": CHANNEL, "token": "fake-secret"}
    if op == "find":
        if o.get("query") == "Zed":
            return {"results": []}
        return {"results": [dict(CHANNEL, exact=True),
                            {"id": "user:333333333333333333", "kind": "user", "name": "@ana", "exact": False}]}
    if op == "guilds":
        return {"guilds": [{"id": "111111111111111111", "name": "Friends"}]}
    if op == "dms":
        return {"dms": [{"id": "444444444444444444", "kind": "dm", "name": "@ana"}]}
    if op == "channels":
        return {"guild": "Friends", "channels": [CHANNEL]}
    if op == "read":
        return {"channel": CHANNEL, "messages": [
            {"id": "555", "author": "ana", "mine": False, "time": "2026-10-28T09:15:00.000Z",
             "content": "lunch? my token is mfa.abcdefghijklmnopqrstuvwxyz0123456789", "mentionsMe": True},
            {"id": "556", "author": "Me", "mine": True, "time": "2026-10-28T09:16:00.000Z", "content": "sure",
             "replyTo": "555", "reactions": [{"emoji": "👍", "count": 1, "me": False}]}]}
    if op == "send":
        return {"sent": True, "id": "999999999999999999", "channel": CHANNEL}
    if op == "react":
        return {"reacted": True, "id": o.get("message"), "channel": CHANNEL}
    if op in ("unreact", "edit", "delete", "pins", "pin", "unpin", "search", "threads", "thread_create",
              "mark_read", "send_file", "members", "friends", "friend_add", "friend_remove", "presence",
              "voice_join", "voice_leave", "open", "api"):
        return {"op": op, "args": {k: (len(v) if k == "data" else v) for k, v in o.items()}}
    return {"error": f"unknown operation {op}"}


def answer(msg):
    method, params = msg.get("method"), msg.get("params") or {}
    if method == "Browser.getVersion":
        return {"product": "Chrome/150.0 (fake)", "protocolVersion": "1.3"}
    if method == "Target.getTargets":
        return {"targetInfos": TARGETS}
    if method == "Target.attachToTarget":
        return {"sessionId": "S-" + params["targetId"]}
    if method == "Page.getFrameTree":
        return {"frameTree": {"frame": {"id": "F1"}}}
    if method == "Page.createIsolatedWorld":
        return {"executionContextId": 42}
    if method == "Runtime.evaluate":
        expr = params.get("expression") or ""
        if "nixbook-app-style" in expr:
            # The `style` operation: the CSS is the argument of its last line.
            css = json.loads(re.search(r"\}\)\((.*)\)$", expr, re.S).group(1))
            log({"eval": "style", "length": len(css), "isolated": params.get("contextId") is not None,
                 "session": msg.get("sessionId")})
            return {"result": {"type": "object", "value": {"styled": bool(css)}}}
        last = expr.rsplit("\n", 1)[-1]
        m = re.match(r"^;(nixbookPage|nixbookApp)\((.*)\)$", last, re.S)
        if not m:
            raise ValueError("fake: not one of the bridge's calls")
        fn = m.group(1)
        if f"function {fn}(" not in expr:
            raise ValueError(f"fake: {fn} isn't defined in what was sent")
        op, o = json.loads("[" + m.group(2) + "]")
        log({"eval": fn, "op": op, "args": o, "isolated": params.get("contextId") is not None,
             "session": msg.get("sessionId")})
        value = (page if fn == "nixbookPage" else app)(op, o, params)
        return {"result": {"type": "object", "value": value}}
    if method == "Input.insertText":
        typed["text"] += params.get("text") or ""
        return {}
    if method in ("Input.dispatchKeyEvent", "Emulation.setFocusEmulationEnabled", "Page.reload", "Page.enable",
                  "Page.navigateToHistoryEntry", "Page.navigate"):
        return {}
    if method == "Page.getNavigationHistory":
        return {"currentIndex": 1, "entries": [{"id": 7, "url": "https://discord.com/app"}, {"id": 8}]}
    if method == "Page.captureScreenshot":
        return {"data": JPEG}
    raise ValueError(f"fake: no {method}")


def main():
    buf = b""
    while True:
        chunk = os.read(3, 65536)
        if not chunk:
            return
        buf += chunk
        while b"\0" in buf:
            frame, _, buf = buf.partition(b"\0")
            msg = json.loads(frame)
            if msg.get("method") != "Runtime.evaluate":
                log({k: v for k, v in msg.items() if k != "id"})
            try:
                reply = {"id": msg["id"], "result": answer(msg)}
            except ValueError as e:
                reply = {"id": msg["id"], "error": {"code": -32000, "message": str(e)}}
            if msg.get("sessionId"):
                reply["sessionId"] = msg["sessionId"]
            os.write(4, json.dumps(reply).encode() + b"\0")


if __name__ == "__main__":
    main()
