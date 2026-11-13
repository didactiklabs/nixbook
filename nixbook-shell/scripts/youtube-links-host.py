"""nixbook_youtube_links: the native messaging host of nixbook-shell's YouTube
links Zen extension (zen-youtube/, nixbook's opt-in
nixbookShellConfig.youtubeLinks). Zen starts it for one message,
{"url": …}; the link is handed to the shell (`OPEN URL`, i.e.
`nixbook-youtube-link URL`, which exits 0 when the shell took it: a video in
mpv, a YouTube Music song or playlist in its background player). Answers
{"ok": true} when it did, else {"ok": false, "error": …}, and the page then
loads in Zen as usual.

  youtube-links-host.py OPEN [Zen's arguments…]
"""

import json
import struct
import subprocess
import sys
import urllib.parse

HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"}


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


def main(argv):
    opener = argv[1]
    try:
        msg = read_message()
    except ValueError:
        msg = None
    url = youtube_link(msg.get("url") if isinstance(msg, dict) else None)
    if not url:
        send({"ok": False, "error": "not a YouTube link"})
        return 0
    try:
        r = subprocess.run([opener, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=10, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        send({"ok": False, "error": str(e)})
        return 0
    send({"ok": True} if r.returncode == 0 else {"ok": False, "error": "the shell didn't take it"})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
