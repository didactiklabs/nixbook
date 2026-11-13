"""nixbook_youtube_links: the native messaging host of nixbook-shell's YouTube
links Zen extension (zen-youtube/). The extension keeps it running
(runtime.connectNative) for two things:

- the shell's choice (the setting media.youtubeLinks, written by the shell to
  $XDG_RUNTIME_DIR/nixbook-shell/youtube-links.json): sent as
  {"choice": {enable, videos, music} | null} when the host starts and each
  time the file changes (null: no shell, or nothing written yet), so the
  extension only takes the links the shell wants, without asking;
- a link to hand over, {"id": N, "url": …}: `OPEN URL` (i.e.
  `nixbook-youtube-link URL`: exit 0 the shell took it, 3 the settings don't
  take it), answered {"id": N, "ok": bool, "off": bool}; the page then loads
  in Zen as usual unless ok.

  youtube-links-host.py OPEN [Zen's arguments…]

NIXBOOK_YOUTUBE_LINKS_CHOICE overrides the choice file (tests).
"""

import json
import os
import struct
import subprocess
import sys
import threading
import urllib.parse

HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"}
POLL = 1.0

out_lock = threading.Lock()


def choice_path():
    if os.environ.get("NIXBOOK_YOUTUBE_LINKS_CHOICE"):
        return os.environ["NIXBOOK_YOUTUBE_LINKS_CHOICE"]
    run = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/nixbook-shell-{os.environ.get('USER', '')}"
    return os.path.join(run, "nixbook-shell", "youtube-links.json")


def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) != 4:
        return None
    (size,) = struct.unpack("=I", raw)
    if size > 64 * 1024:
        return None
    body = sys.stdin.buffer.read(size)
    if len(body) != size:
        return None
    try:
        return json.loads(body)
    except ValueError:
        return {}


def send(obj):
    data = json.dumps(obj).encode()
    with out_lock:
        sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
        sys.stdout.buffer.flush()


def youtube_link(url):
    """`url` when it is an http(s) link on a YouTube host, else None (the
    shell decides what it is)."""
    if not isinstance(url, str) or len(url) > 4000 or any(c in url for c in "\0\r\n"):
        return None
    try:
        u = urllib.parse.urlsplit(url)
        host = (u.hostname or "").lower()
    except ValueError:
        return None
    return url if u.scheme in ("http", "https") and host in HOSTS and "@" not in u.netloc else None


def read_choice(path):
    try:
        with open(path, encoding="utf-8") as f:
            c = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(c, dict):
        return None
    return {"enable": c.get("enable") is True, "videos": c.get("videos") is not False,
            "music": c.get("music") is not False}


def watch_choice(path, stop):
    """Sends the choice now and whenever the file changes (replaced by
    rename: its inode or mtime changes)."""
    last_stamp, last = object(), object()
    while not stop.is_set():
        try:
            st = os.stat(path)
            stamp = (st.st_ino, st.st_mtime_ns, st.st_size)
        except OSError:
            stamp = None
        if stamp != last_stamp:
            last_stamp = stamp
            choice = read_choice(path) if stamp else None
            if choice != last:
                last = choice
                send({"choice": choice})
        stop.wait(POLL)


def hand(opener, msg):
    mid = msg.get("id")
    url = youtube_link(msg.get("url"))
    if not url:
        send({"id": mid, "ok": False, "off": False, "error": "not a YouTube link"})
        return
    try:
        r = subprocess.run([opener, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=10, check=False)
        code = r.returncode
    except (OSError, subprocess.TimeoutExpired):
        code = 1
    send({"id": mid, "ok": code == 0, "off": code == 3})


def main(argv):
    opener = argv[1]
    stop = threading.Event()
    threading.Thread(target=watch_choice, args=(choice_path(), stop), daemon=True).start()
    while True:
        msg = read_message()
        if msg is None:
            break
        if isinstance(msg, dict) and "url" in msg:
            threading.Thread(target=hand, args=(opener, msg), daemon=True).start()
    stop.set()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
