"""nixbook_open_in_app: the native messaging host of nixbook's "open in
apps" Zen extension (zenBrowserConfig.openInApps). Zen starts it for one
message, {"url": …}; a link on one of the hosts the configuration names
is handed to its app (`COMMAND URL`, as the nixbook-open-url router does
for xdg-open), started detached: through niri when it can (a scope of its
own, not Zen's), else in a session of its own. Answers {"ok": true} when it
did, else {"ok": false, "error": …}, and the page then loads in Zen as usual.

  host.py CONFIG.json [Zen's arguments…]

CONFIG.json: {"apps": {"music.youtube.com": "/nix/store/…/bin/pear-desktop"}}.
"""

import json
import os
import shutil
import struct
import subprocess
import sys
import urllib.parse


def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) != 4:
        return None
    (size,) = struct.unpack("=I", raw)
    if size > 64 * 1024:
        return None
    return json.loads(sys.stdin.buffer.read(size))


def send(obj):
    data = json.dumps(obj).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()


def app_for(apps, url):
    """The command opening `url`, or None."""
    if not isinstance(url, str) or len(url) > 4000 or any(c in url for c in "\0\r\n"):
        return None
    try:
        u = urllib.parse.urlsplit(url)
        host = (u.hostname or "").lower()
    except ValueError:
        return None
    return apps.get(host) if u.scheme in ("http", "https") else None


def start(command, url):
    niri = shutil.which("niri")
    if os.environ.get("NIRI_SOCKET") and niri:
        r = subprocess.run([niri, "msg", "action", "spawn", "--", command, url], stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        if r.returncode == 0:
            return
    subprocess.Popen([command, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        cfg = json.load(f)
    apps = {h.lower(): c for h, c in cfg["apps"].items()}
    try:
        msg = read_message()
    except ValueError:
        msg = None
    url = msg.get("url") if isinstance(msg, dict) else None
    command = app_for(apps, url)
    if not command:
        send({"ok": False, "error": "not a link an app opens"})
        return 0
    if not os.access(command, os.X_OK):
        send({"ok": False, "error": f"{command} isn't there"})
        return 0
    try:
        start(command, url)
    except (OSError, subprocess.TimeoutExpired) as e:
        send({"ok": False, "error": str(e)})
        return 0
    send({"ok": True})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
