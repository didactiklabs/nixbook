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
  FAKE_CDP_HANDOVER=1: quits at once, like an app handing over to one already running.
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

TARGETS = [
    {"targetId": "T0", "type": "page", "title": "Vesktop", "url": "vesktop://static/views/splash.html"},
    {"targetId": "T1", "type": "page", "title": "Discord | #general", "url": "https://discord.com/channels/111/222"},
    {"targetId": "TD", "type": "page", "title": "DevTools", "url": "devtools://devtools/bundled/inspector.html"},
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
    if op == "state":
        return {"element": {"role": "text editor", "name": "Message #general", "value": typed["text"]}}
    if op == "ready":
        return {"state": "complete", "url": TARGETS[1]["url"], "title": TARGETS[1]["title"]}
    if op == "has":
        return {"found": str(o.get("text") or "") in "Hello from #general"}
    return {"error": f"unknown page operation {op}"}


def app(op, o, params):
    if params.get("contextId") is not None:
        return {"error": "fake: the app's code ran in an isolated world"}
    if op == "status":
        # A key the bridge must never pass on.
        return {"loggedIn": True, "user": "Me", "current": CHANNEL, "token": "fake-secret"}
    if op == "find":
        if o.get("query") == "Bob":
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
    if method in ("Input.dispatchKeyEvent", "Emulation.setFocusEmulationEnabled", "Page.reload",
                  "Page.navigateToHistoryEntry"):
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
