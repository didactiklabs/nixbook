"""nixbook-mesh: the mesh between people's desktops (services/Mesh.qml).

A few people's desktops talk through an ntfy server on the internet: short
messages (to everyone, or to one person), everyone's status (free, in a
meeting, gaming…) and read receipts. No desktop reaches another directly.

Everything that leaves the machine is encrypted (AES-256-GCM) with the
mesh's key, which every member holds and the server never sees: the server
only relays ciphertext, on a topic whose name is derived from that key. One
member creates the mesh (`mesh create`) and can show its code again at any
time (`mesh code`); the others enter it (`mesh join`, the code on stdin).
Every member holds the key, so a message to one person is hidden from the
others' screens, not from their key.

The server needs an access token per person (`tk_…`, set on the server
side; removing it there cuts that person off). The token and the key live in
the keyring (secret-tool, `service=nixbook-mesh kind=token|key`), or, when
there is no keyring (or NIXBOOK_MESH_STORE=file), in
$XDG_CONFIG_HOME/nixbook-shell/mesh/{token,key} (0600), which can also be
written by hand (the key as base64).

Commands (JSON on stdout; secrets only ever on stdin):

  status                        what is set: token, key, where they are
  token set | token forget      the access token (stdin)
  mesh create | mesh code       make a new mesh / show its code again
  mesh join | mesh leave        enter a mesh's code (stdin) / forget the key
  test SERVER                   the token works, and the mesh is reachable
  send SERVER KIND              publish (stdin: the JSON data) as $USER
  listen SERVER                 one JSON line per event, until killed:
                                {"event": "message", "kind", "from", "name",
                                 "time", "mid", "to", "mine", "data"},
                                {"event": "status", "connected", "error"},
                                {"event": "error", "error"}
"""

import base64
import binascii
import hashlib
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SERVICE = "nixbook-mesh"
VERSION = "m1"
# The server's ACL allows each member `mesh-*`.
TOPIC_PREFIX = "mesh-"
TOKEN_RE = re.compile(r"^tk_[A-Za-z0-9]{29}$")
MEMBER_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
KINDS = ("message", "presence", "read")
MAX_TEXT = 1000
# ntfy sends a keepalive every 45s: nothing for this long means the
# connection is dead.
READ_TIMEOUT = 120
USER_AGENT = "nixbook-mesh/1"


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def fail(message, code=1):
    out({"ok": False, "error": message})
    sys.exit(code)


def me():
    return os.environ.get("NIXBOOK_MESH_ME") or os.environ.get("USER") or "me"


# -- Where the secrets live ------------------------------------------------------


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(base) / "nixbook-shell" / "mesh"


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "nixbook-shell" / "mesh"


def use_keyring():
    return os.environ.get("NIXBOOK_MESH_STORE", "keyring") != "file"


def secret_tool(*args, value=None):
    try:
        return subprocess.run(["secret-tool", *args], input=value, capture_output=True,
                              text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None


def keyring_lookup(kind):
    if not use_keyring():
        return None
    r = secret_tool("lookup", "service", SERVICE, "kind", kind)
    value = r.stdout.strip() if r else ""
    return value if r and r.returncode == 0 and value else None


def keyring_store(kind, value, label):
    if not use_keyring():
        return False
    r = secret_tool("store", f"--label={label}", "service", SERVICE, "kind", kind, value=value)
    return bool(r and r.returncode == 0)


def keyring_clear(kind):
    if use_keyring():
        secret_tool("clear", "service", SERVICE, "kind", kind)


def file_read(kind):
    try:
        value = (config_dir() / kind).read_text().strip()
    except OSError:
        return None
    return value or None


def file_write(kind, value):
    d = config_dir()
    d.mkdir(parents=True, exist_ok=True)
    os.chmod(d, 0o700)
    tmp = d / f".{kind}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(value + "\n")
    os.replace(tmp, d / kind)


def file_clear(kind):
    try:
        (config_dir() / kind).unlink()
    except OSError:
        pass


def secret(kind):
    """(value, source): the keyring first, then the file."""
    value = keyring_lookup(kind)
    if value:
        return value, "keyring"
    value = file_read(kind)
    if value:
        return value, "file"
    return None, None


def save_secret(kind, value, label):
    """Into the keyring, else the file. Returns where it went."""
    if keyring_store(kind, value, label):
        file_clear(kind)
        return "keyring"
    file_write(kind, value)
    return "file"


def forget_secret(kind):
    keyring_clear(kind)
    file_clear(kind)


# -- The mesh key ------------------------------------------------------------------

B32 = re.compile(r"[^A-Z2-7]")


def code_of(key):
    """The mesh code: the key and a 2-byte check, base32, in groups of 5."""
    raw = key + hashlib.sha256(key).digest()[:2]
    text = base64.b32encode(raw).decode().rstrip("=")
    return "-".join(text[i:i + 5] for i in range(0, len(text), 5))


def key_of_code(code):
    # Base32 has no 0/1/8: read as the letters they are mistaken for.
    text = B32.sub("", code.upper().replace("0", "O").replace("1", "I").replace("8", "B"))
    try:
        raw = base64.b32decode(text + "=" * (-len(text) % 8))
    except (ValueError, binascii.Error):
        return None
    if len(raw) != 34:
        return None
    key, check = raw[:32], raw[32:]
    return key if hashlib.sha256(key).digest()[:2] == check else None


def load_key():
    value, source = secret("key")
    if not value:
        return None, None
    try:
        key = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        return None, source
    return (key if len(key) == 32 else None), source


def topic_of(key):
    """The mesh's topic: derived from the key, so the code is all it takes,
    and it says nothing about who is talking."""
    return TOPIC_PREFIX + hashlib.sha256(b"nixbook-mesh topic\0" + key).hexdigest()[:24]


def seal(key, topic, payload):
    nonce = secrets.token_bytes(12)
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    ct = AESGCM(key).encrypt(nonce, data, topic.encode())
    return f"{VERSION}:" + base64.urlsafe_b64encode(nonce + ct).decode().rstrip("=")


def unseal(key, topic, text):
    if not text.startswith(f"{VERSION}:"):
        return None
    body = text[len(VERSION) + 1:]
    try:
        raw = base64.urlsafe_b64decode(body + "=" * (-len(body) % 4))
        plain = AESGCM(key).decrypt(raw[:12], raw[12:], topic.encode())
        payload = json.loads(plain)
    except Exception:
        return None
    return payload if isinstance(payload, dict) else None


# -- The server ----------------------------------------------------------------------


def server_url(server):
    server = (server or "").strip().rstrip("/")
    if not re.match(r"^https?://[^/\s]+", server):
        fail("no server set (e.g. https://ntfy.example.org)")
    return server


def token_or_fail():
    token, _ = secret("token")
    if not token:
        fail("no access token yet: paste yours in Settings > General > Mesh")
    return token


def key_or_fail():
    key, _ = load_key()
    if not key:
        fail("not in a mesh yet: create one, or enter a member's mesh code")
    return key


def request(url, token, data=None, method=None, timeout=20, headers=None):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("User-Agent", USER_AGENT)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    return urllib.request.urlopen(req, timeout=timeout)


def http_error(e):
    if isinstance(e, urllib.error.HTTPError):
        if e.code == 401:
            return "the server refused the access token (401)"
        if e.code == 403:
            return "the token isn't allowed on the mesh's topic (403): the server's ACL needs mesh-* for this user"
        if e.code == 429:
            return "too many requests (429): try again in a minute"
        return f"the server answered {e.code}"
    reason = getattr(e, "reason", e)
    return f"the server can't be reached ({reason})"


# -- Commands ------------------------------------------------------------------------


def cmd_status(_args):
    token, token_source = secret("token")
    key, key_source = load_key()
    out({
        "ok": True,
        "token": bool(token),
        "tokenSource": token_source,
        "tokenValid": bool(token and TOKEN_RE.match(token)),
        "joined": bool(key),
        "keySource": key_source,
        "me": me(),
    })


def cmd_token(args):
    what = args[0] if args else ""
    if what == "set":
        token = sys.stdin.readline().strip()
        if not TOKEN_RE.match(token):
            fail("that isn't an ntfy access token (tk_ followed by 29 letters or digits)")
        where = save_secret("token", token, "nixbook mesh: ntfy access token")
        out({"ok": True, "tokenSource": where})
    elif what == "forget":
        forget_secret("token")
        out({"ok": True})
    else:
        fail("usage: token set|forget")


def cmd_mesh(args):
    what = args[0] if args else ""
    label = "nixbook mesh: the mesh key"
    if what == "create":
        key = secrets.token_bytes(32)
        where = save_secret("key", base64.b64encode(key).decode(), label)
        out({"ok": True, "code": code_of(key), "keySource": where})
    elif what == "code":
        key, where = load_key()
        if not key:
            fail("not in a mesh yet")
        out({"ok": True, "code": code_of(key), "keySource": where})
    elif what == "join":
        key = key_of_code(sys.stdin.readline())
        if not key:
            fail("that code isn't right: check it letter by letter")
        where = save_secret("key", base64.b64encode(key).decode(), label)
        # Another mesh: start reading it from the beginning.
        try:
            (state_dir() / "position.json").unlink()
        except OSError:
            pass
        out({"ok": True, "keySource": where})
    elif what == "leave":
        forget_secret("key")
        out({"ok": True})
    else:
        fail("usage: mesh create|code|join|leave")


def cmd_test(args):
    server = server_url(args[0] if args else "")
    token = token_or_fail()
    try:
        with request(f"{server}/v1/account", token) as r:
            account = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(http_error(e))
    user = account.get("username") or ""
    if not user or user == "*":
        fail("the server doesn't know this token")
    result = {"ok": True, "user": user, "joined": False}
    key, _ = load_key()
    if key:
        topic = topic_of(key)
        try:
            with request(f"{server}/{topic}/json?poll=1&since=1m", token):
                pass
        except (urllib.error.URLError, OSError) as e:
            fail(http_error(e))
        result["joined"] = True
    out(result)


def cmd_send(args):
    if len(args) < 2:
        fail("usage: send SERVER KIND (stdin: JSON data)")
    server = server_url(args[0])
    kind = args[1]
    if kind not in KINDS:
        fail(f"unknown kind {kind}")
    try:
        data = json.loads(sys.stdin.readline() or "{}")
    except ValueError:
        fail("the data isn't JSON")
    if not isinstance(data, dict):
        fail("the data must be an object")
    # Who it is for: a member, or everyone ("").
    to = str(data.pop("to", "") or "")
    if to and not MEMBER_RE.match(to):
        fail("not a member's name")
    if kind == "message":
        text = str(data.get("text") or "").strip()
        if not text:
            fail("nothing to send")
        data["text"] = text[:MAX_TEXT]
    token = token_or_fail()
    key = key_or_fail()
    topic = topic_of(key)
    mid = str(data.pop("mid", "") or secrets.token_hex(8))
    name = str(data.pop("name", "") or "")[:64]
    payload = {"kind": kind, "from": me(), "name": name, "to": to, "time": int(time.time()),
               "mid": mid, "data": data}
    body = seal(key, topic, payload).encode()
    try:
        with request(f"{server}/{topic}", token, data=body, method="POST") as r:
            answer = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(http_error(e))
    out({"ok": True, "id": answer.get("id"), "mid": mid, "time": payload["time"]})


SEEN_KEEP = 300


def read_position():
    """Where the last connection stopped: the last message's id, and the ids
    already delivered. ntfy's `since=<id>` returns every message of that
    id's second but that one, so a burst would come again: the ids say."""
    try:
        state = json.loads((state_dir() / "position.json").read_text())
    except (OSError, ValueError):
        return None, []
    return state.get("cursor"), list(state.get("seen") or [])


def write_position(cursor, seen):
    d = state_dir()
    d.mkdir(parents=True, exist_ok=True)
    tmp = d / ".position.tmp"
    tmp.write_text(json.dumps({"cursor": cursor, "seen": seen[-SEEN_KEEP:]}))
    os.replace(tmp, d / "position.json")


def cmd_listen(args):
    server = server_url(args[0] if args else "")
    token = token_or_fail()
    key = key_or_fail()
    topic = topic_of(key)
    myself = me()
    delay = 2
    warned = False
    cursor, seen = read_position()
    seen_set = set(seen)
    while True:
        # Resume where the last connection stopped; the first time, the last
        # day (what was said while this desktop was off).
        since = cursor or "24h"
        url = f"{server}/{topic}/json?since={urllib.parse.quote(since)}"
        try:
            with request(url, token, timeout=READ_TIMEOUT) as r:
                out({"event": "status", "connected": True})
                delay = 2
                for raw in r:
                    try:
                        msg = json.loads(raw)
                    except ValueError:
                        continue
                    if msg.get("event") != "message":
                        continue
                    mid = msg.get("id")
                    if mid and mid in seen_set:
                        continue
                    payload = unseal(key, topic, msg.get("message") or "")
                    if payload is None:
                        if not warned:
                            out({"event": "error",
                                 "error": "a message couldn't be read: was the mesh code changed?"})
                            warned = True
                    elif payload.get("kind") in KINDS and MEMBER_RE.match(str(payload.get("from") or "")):
                        to = str(payload.get("to") or "")
                        # Someone else's private message: not for this screen.
                        if to and to != myself and payload["from"] != myself:
                            pass
                        else:
                            payload["event"] = "message"
                            payload["mine"] = payload["from"] == myself
                            payload["id"] = msg.get("id")
                            out(payload)
                    if mid:
                        cursor = mid
                        seen.append(mid)
                        seen_set.add(mid)
                        if len(seen) > 2 * SEEN_KEEP:
                            seen = seen[-SEEN_KEEP:]
                            seen_set = set(seen)
                        write_position(cursor, seen)
        except urllib.error.HTTPError as e:
            out({"event": "status", "connected": False, "error": http_error(e)})
            # Refused: not going to change on its own, so wait longer.
            delay = 300 if e.code in (401, 403) else delay
        except (urllib.error.URLError, OSError, socket.timeout) as e:
            out({"event": "status", "connected": False, "error": http_error(e)})
        time.sleep(delay)
        delay = 300 if delay >= 300 else min(delay * 2, 60)


def main():
    args = sys.argv[1:]
    commands = {
        "status": cmd_status,
        "token": cmd_token,
        "mesh": cmd_mesh,
        "test": cmd_test,
        "send": cmd_send,
        "listen": cmd_listen,
    }
    command = commands.get(args[0]) if args else None
    if not command:
        fail("usage: nixbook-mesh status|token|mesh|test|send|listen")
    try:
        command(args[1:])
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)


if __name__ == "__main__":
    main()
