"""A stand-in for Zen and nixbook's extension (zen/), for tests/desktop-mcp.sh:
starts the real native host (scripts/zen-bridge.py) the way Zen does, and
answers its requests over native messaging (4-byte length, JSON) with canned
results, logging each request (one JSON line) to the log file.

  fake-zen.py BRIDGE_SCRIPT LOG
"""

import json
import struct
import subprocess
import sys

bridge, log = sys.argv[1], sys.argv[2]
proc = subprocess.Popen([sys.executable, "-I", bridge, "/fake/manifest.json", "desktop-agent@nixbook-shell"],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)

TABS = [
    {"id": 3, "window": 1, "active": True, "title": "Inbox", "url": "https://mail.example.org/", "container": "Work"},
    {"id": 7, "window": 1, "active": False, "private": "the Banking container", "container": "Banking"},
    {"id": 9, "window": 1, "active": False, "title": "News", "url": "https://news.example.org/", "otherWorkspace": True},
]


def answer(msg):
    cmd = msg.get("cmd")
    if cmd == "tabs":
        return TABS
    if cmd == "read":
        return {"tab": 3, "title": "Inbox", "url": "https://mail.example.org/", "total": 3, "textTotal": 5,
                "text": "Hello", "elements": [
                    {"ref": 1, "role": "button", "name": "Send"},
                    {"ref": 2, "role": "text field", "name": "To", "value": "ana@example.org"},
                    {"ref": 3, "role": "password field", "name": "Password", "password": True}]}
    if cmd == "act":
        if msg.get("ref") == 3:
            raise ValueError("refused: password fields are off limits; ask the user to do this step")
        return {"done": msg.get("action"), "element": {"role": "text field", "name": msg.get("name"),
                                                      "value": msg.get("value")}, "tab": 3,
                "title": "Inbox", "url": "https://mail.example.org/"}
    if cmd == "open":
        return {"id": 12, "window": 1, "active": False, "title": "Example", "url": msg.get("url")}
    if cmd == "screenshot":
        # A 1x1 JPEG.
        return {"tab": 3, "title": "Inbox", "url": "https://mail.example.org/",
                "data": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP////////////////////////////"
                        "//////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAA"
                        "AAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AN//Z"}
    raise ValueError(f"unknown command {cmd}")


while True:
    head = proc.stdout.read(4)
    if len(head) < 4:
        break
    (size,) = struct.unpack("=I", head)
    msg = json.loads(proc.stdout.read(size))
    with open(log, "a") as f:
        f.write(json.dumps({k: v for k, v in msg.items() if k != "id"}) + "\n")
    try:
        reply = {"id": msg["id"], "ok": True, "result": answer(msg)}
    except ValueError as e:
        reply = {"id": msg["id"], "ok": False, "error": str(e)}
    data = json.dumps(reply).encode()
    proc.stdin.write(struct.pack("=I", len(data)) + data)
    proc.stdin.flush()
