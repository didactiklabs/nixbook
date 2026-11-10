"""nixbook-mesh: the mesh between people's desktops (services/Mesh.qml).

A few people's desktops talk through an ntfy server on the internet: short
messages (to everyone, or to one person), everyone's status (free, in a
meeting, gaming…) and read receipts. No desktop reaches another directly.

Everything that leaves the machine is encrypted (AES-256-GCM) with the
mesh's key, which every member holds and the server never sees: the server
only relays ciphertext, on a topic whose name is derived from that key. One
member creates the mesh (`mesh create`) and can show its code again at any
time (`mesh code`); the others enter it (`mesh join`, the code on stdin).
A message to one person is also sealed for that person's own key (see
"Private messages" below): the other members can't read it.

The server needs an access token per person (`tk_…`). The server's admin
(an ntfy admin, whose token is set by hand) invites people from their
desktop (`invite`): no server configuration per person. The invited person
pastes the invite code (`accept`), which makes their own token. Removing
someone (`remove`) cuts them off at once. The token and the key live in
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
  invite SERVER NAME            (the server's admin) an account for NAME with
                                the mesh's topics, and their invite code
  members SERVER | remove SERVER NAME   (the admin) who is in / take one out
  keys | keys mine | keys trust MEMBER   the pinned keys / this desktop's /
                                take a member's new key (private messages)
  accept                        join with an invite code (stdin): this
                                desktop's own token, and the mesh key
  listen SERVER                 one JSON line per event, until killed:
                                {"event": "message", "kind", "from", "name",
                                 "time", "mid", "to", "mine", "data"},
                                {"event": "status", "connected", "error"},
                                {"event": "error", "error"}
"""

import base64
import binascii
import contextlib
import fcntl
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

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

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
# Catching up, status updates older than this are skipped.
STALE_PRESENCE = 30 * 60
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
    tmp = d / f".{kind}.{os.getpid()}.tmp"
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


# -- Private messages ---------------------------------------------------------------
#
# Every member holds the mesh key, so private messages and read receipts are
# sealed again, for their recipient alone, in envelopes that show nothing of
# who wrote to whom (see "Sealed envelopes" below). Each desktop has its own
# X25519 key pair (its private half in the keyring, kind=identity); status
# updates and messages to everyone carry the sender's public key ("pk"), and
# each desktop pins the first key it sees for a member (state: keys.json). A
# member whose key changes (a reinstall, or someone posing as them) is held
# back until the user trusts the new key (`keys trust`).


@contextlib.contextmanager
def locked(name):
    """One process at a time (the shell's listener, a send, `keys trust`)."""
    d = state_dir()
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{name}.lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def load_identity():
    """This desktop's key pair: (private key, public key bytes). Made on
    first use, under a lock: the listener and a send starting together must
    not make two."""
    with locked("identity"):
        return _load_identity()


def _load_identity():
    value, _ = secret("identity")
    raw = None
    if value:
        try:
            raw = base64.b64decode(value, validate=True)
        except (ValueError, binascii.Error):
            raw = None
    if not raw or len(raw) != 32:
        sk = X25519PrivateKey.generate()
        raw = sk.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                               serialization.NoEncryption())
        save_secret("identity", base64.b64encode(raw).decode(), "nixbook mesh: this desktop's private key")
    sk = X25519PrivateKey.from_private_bytes(raw)
    pk = sk.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return sk, pk


def b64(raw):
    return base64.b64encode(raw).decode()


def pk_of(text):
    try:
        raw = base64.b64decode(str(text or ""), validate=True)
    except (ValueError, binascii.Error):
        return None
    return raw if len(raw) == 32 else None


def fingerprint(pk):
    h = hashlib.sha256(pk).hexdigest()[:20].upper()
    return " ".join(h[i:i + 4] for i in range(0, 20, 4))


def load_pins():
    try:
        pins = json.loads((state_dir() / "keys.json").read_text())
    except (OSError, ValueError):
        pins = {}
    return pins if isinstance(pins, dict) else {}


def save_pins(pins):
    d = state_dir()
    d.mkdir(parents=True, exist_ok=True)
    tmp = d / f".keys.{os.getpid()}.tmp"
    tmp.write_text(json.dumps(pins))
    os.replace(tmp, d / "keys.json")


def pin(member, pk):
    """Pins `member`'s key the first time; "same", "new" or "changed"."""
    with locked("keys"):
        return _pin(member, pk)


def _pin(member, pk):
    pins = load_pins()
    entry = pins.get(member)
    if not entry:
        pins[member] = {"pk": b64(pk), "since": int(time.time())}
        save_pins(pins)
        return "new"
    if entry.get("pk") == b64(pk):
        return "same"
    if entry.get("changed") != b64(pk):
        entry["changed"] = b64(pk)
        save_pins(pins)
    return "changed"


def pinned(member):
    entry = load_pins().get(member) or {}
    return pk_of(entry.get("pk")), bool(entry.get("changed"))


def dm_key(sk, my_pk, their_pk):
    shared = sk.exchange(X25519PublicKey.from_public_bytes(their_pk))
    a, b = sorted([my_pk, their_pk])
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
                info=b"nixbook-mesh dm v1\0" + a + b).derive(shared)


# Sealed envelopes. A private message (or read receipt) leaves with nothing
# on the outside: no sender, no recipient, no time, its length padded. A
# one-off key pair (`e`) seals one box per reader (the recipient and the
# sender's own copy, in random order): the box's key comes from X25519(e,
# reader), so only that reader opens it, and two envelopes can't be linked
# to the same person. Inside each box: the sender's public key and the
# message sealed with X25519(sender, reader), which proves who wrote it.
PAD = 256


def _sealed_key(shared, eph_pk, reader_pk):
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
                info=b"nixbook-mesh sealed v1\0" + eph_pk + reader_pk).derive(shared)


def seal_private(sk, my_pk, readers, inner, topic):
    eph = X25519PrivateKey.generate()
    eph_pk = eph.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    aad = topic.encode() + eph_pk
    plain = json.dumps(inner, ensure_ascii=False, separators=(",", ":")).encode()
    plain += b" " * (-len(plain) % PAD)
    boxes = []
    for reader_pk in readers:
        n1 = secrets.token_bytes(12)
        inside = AESGCM(dm_key(sk, my_pk, reader_pk)).encrypt(n1, plain, aad)
        wrapper = json.dumps({"s": b64(my_pk), "c": b64(n1 + inside)}).encode()
        key = _sealed_key(eph.exchange(X25519PublicKey.from_public_bytes(reader_pk)), eph_pk, reader_pk)
        n2 = secrets.token_bytes(12)
        boxes.append(b64(n2 + AESGCM(key).encrypt(n2, wrapper, aad)))
    secrets.SystemRandom().shuffle(boxes)
    return {"kind": "sealed", "e": b64(eph_pk), "b": boxes}


def open_private(sk, my_pk, outer, topic):
    """(inner, sender's public key) if a box is for this desktop, else
    (None, None)."""
    eph_pk = pk_of(outer.get("e"))
    boxes = outer.get("b")
    if not eph_pk or not isinstance(boxes, list):
        return None, None
    aad = topic.encode() + eph_pk
    key = _sealed_key(sk.exchange(X25519PublicKey.from_public_bytes(eph_pk)), eph_pk, my_pk)
    for text in boxes[:4]:
        try:
            raw = base64.b64decode(str(text), validate=True)
            wrapper = json.loads(AESGCM(key).decrypt(raw[:12], raw[12:], aad))
            sender_pk = pk_of(wrapper.get("s"))
            inside = base64.b64decode(str(wrapper.get("c")), validate=True)
            inner = json.loads(AESGCM(dm_key(sk, my_pk, sender_pk)).decrypt(inside[:12], inside[12:], aad))
        except Exception:
            continue
        if isinstance(inner, dict) and sender_pk:
            return inner, sender_pk
    return None, None


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


def api(server, path, method="GET", body=None, token=None, basic=None, timeout=20):
    """An ntfy JSON API call, as a token's owner or with a password."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{server}{path}", data=data, method=method)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    elif basic:
        raw = f"{basic[0]}:{basic[1]}".encode()
        req.add_header("Authorization", "Basic " + base64.b64encode(raw).decode())
    req.add_header("User-Agent", USER_AGENT)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        text = r.read().decode() or "null"
    return json.loads(text)


def http_error(e):
    if isinstance(e, urllib.error.HTTPError):
        if e.code == 401:
            return "the server refused the access token (401)"
        if e.code == 403:
            return "this account can't use the mesh (403): ask the server's admin to invite you"
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
    result = {"ok": True, "user": user, "role": account.get("role") or "user", "joined": False}
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


# -- Invites (the server's admin) -------------------------------------------------
#
# The admin's token creates the person's account on the server, with the
# mesh's topics, and an invite code holds what their desktop needs: the
# server, the account with a one-time password, and the mesh key. Accepting
# it changes that password (so the code works once) and makes the desktop's
# own token. Inviting someone again gives them a new password (a new code).

INVITE_PREFIX = "nixbook-mesh-invite:"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,31}$")


def invite_code(server, name, password, key):
    raw = json.dumps({"v": 1, "s": server, "u": name, "p": password,
                      "k": base64.b64encode(key).decode()}, separators=(",", ":")).encode()
    raw += hashlib.sha256(raw).digest()[:4]
    return INVITE_PREFIX + base64.urlsafe_b64encode(raw).decode().rstrip("=")


def parse_invite(code):
    text = re.sub(r"\s+", "", code or "")
    if text.startswith(INVITE_PREFIX):
        text = text[len(INVITE_PREFIX):]
    try:
        raw = base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    except (ValueError, binascii.Error):
        return None
    body, check = raw[:-4], raw[-4:]
    if len(raw) < 8 or hashlib.sha256(body).digest()[:4] != check:
        return None
    try:
        data = json.loads(body)
        key = base64.b64decode(data["k"], validate=True)
    except (ValueError, KeyError, TypeError, binascii.Error):
        return None
    if len(key) != 32 or not NAME_RE.match(str(data.get("u") or "")):
        return None
    return {"server": str(data.get("s") or ""), "name": data["u"], "password": str(data.get("p") or ""), "key": key}


def admin_error(e):
    if isinstance(e, urllib.error.HTTPError) and e.code in (401, 403):
        return "only the server's admin can do this (your token isn't an admin's)"
    if isinstance(e, urllib.error.HTTPError) and e.code == 409:
        return "that person is set in the server's own configuration (Vault), not by invites: change them there"
    return http_error(e)


def cmd_invite(args):
    if len(args) < 2:
        fail("usage: invite SERVER NAME")
    server = server_url(args[0])
    name = args[1].strip().lower()
    if not NAME_RE.match(name):
        fail("a name is lower-case letters, digits, '.', '_' or '-' (up to 32)")
    token = token_or_fail()
    key = key_or_fail()
    password = secrets.token_urlsafe(18)
    try:
        try:
            api(server, "/v1/users", "POST", {"username": name, "password": password}, token=token)
            again = False
        except urllib.error.HTTPError as e:
            if e.code != 409:
                raise
            # Invited before: a new password, so a new code.
            api(server, "/v1/users", "PUT", {"username": name, "password": password}, token=token)
            again = True
        api(server, "/v1/users/access", "PUT", {"username": name, "topic": f"{TOPIC_PREFIX}*", "permission": "rw"},
            token=token)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(admin_error(e))
    out({"ok": True, "name": name, "again": again, "code": invite_code(server, name, password, key)})


def cmd_members(args):
    server = server_url(args[0] if args else "")
    token = token_or_fail()
    try:
        users = api(server, "/v1/users", token=token)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(admin_error(e))
    members = []
    for u in users or []:
        role = u.get("role")
        if role == "anonymous":
            continue
        grants = [g.get("topic") for g in (u.get("grants") or [])]
        if role == "admin" or f"{TOPIC_PREFIX}*" in grants:
            members.append({"name": u.get("username"), "role": role})
    out({"ok": True, "members": members})


def cmd_remove(args):
    if len(args) < 2:
        fail("usage: remove SERVER NAME")
    server = server_url(args[0])
    name = args[1].strip().lower()
    token = token_or_fail()
    try:
        me_ = api(server, "/v1/account", token=token).get("username")
        if name == me_:
            fail("that's you")
        api(server, "/v1/users", "DELETE", {"username": name}, token=token)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(admin_error(e))
    out({"ok": True, "name": name})


def cmd_accept(_args):
    invite = parse_invite(sys.stdin.readline())
    if not invite:
        fail("that isn't an invite code, or it was cut: copy all of it")
    server = server_url(invite["server"])
    name = invite["name"]
    new_password = secrets.token_urlsafe(24)
    try:
        api(server, "/v1/account/password", "POST", {"password": invite["password"], "new_password": new_password},
            basic=(name, invite["password"]))
    except urllib.error.HTTPError as e:
        if e.code == 401:
            fail("this invite was already used, or replaced by a newer one: ask for a new one")
        fail(http_error(e))
    except (urllib.error.URLError, OSError) as e:
        fail(http_error(e))
    try:
        answer = api(server, "/v1/account/token", "POST", {"label": socket.gethostname()[:60] or "desktop"},
                     basic=(name, new_password))
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(http_error(e) + " (the invite is used now: ask for a new one)")
    token = str(answer.get("token") or "")
    if not TOKEN_RE.match(token):
        fail("the server didn't give a token (the invite is used now: ask for a new one)")
    token_where = save_secret("token", token, "nixbook mesh: ntfy access token")
    key_where = save_secret("key", base64.b64encode(invite["key"]).decode(), "nixbook mesh: the mesh key")
    try:
        (state_dir() / "position.json").unlink()
    except OSError:
        pass
    out({"ok": True, "server": server, "user": name, "tokenSource": token_where, "keySource": key_where})


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
    sk, my_pk = load_identity()
    myself = me()
    now = int(time.time())
    if to and kind in ("message", "read"):
        # Sealed: for the recipient's key alone (and the sender's own copy).
        their_pk, changed = (my_pk, False) if to == myself else pinned(to)
        if not their_pk:
            fail(f"{to}'s desktop hasn't been seen yet, so there is no key to write to them privately: "
                 "they need to come online once")
        if changed:
            fail(f"{to}'s key changed: check it in the Mesh tab (Trust the new key) before writing privately")
        inner = {"kind": kind, "from": myself, "name": name, "to": to, "time": now, "mid": mid, "data": data}
        readers = [their_pk] if to == myself else [their_pk, my_pk]
        payload = seal_private(sk, my_pk, readers, inner, topic)
    else:
        payload = {"kind": kind, "from": myself, "name": name, "to": to, "time": now,
                   "mid": mid, "pk": b64(my_pk), "data": data}
    body = seal(key, topic, payload).encode()
    try:
        with request(f"{server}/{topic}", token, data=body, method="POST") as r:
            answer = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(http_error(e))
    out({"ok": True, "id": answer.get("id"), "mid": mid, "time": now})


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
    tmp = d / f".position.{os.getpid()}.tmp"
    tmp.write_text(json.dumps({"cursor": cursor, "seen": seen[-SEEN_KEEP:]}))
    os.replace(tmp, d / "position.json")


def note_key(member, pk, myself, told):
    """Pins a member's key; True when it is the one known (or the first)."""
    state = pin(member, pk)
    if state == "changed" and (member, b64(pk)) not in told:
        told.add((member, b64(pk)))
        out({"event": "keychange", "member": member, "fingerprint": fingerprint(pk), "mine": member == myself})
    return state in ("new", "same")


def receive(payload, topic, sk, my_pk, myself, told):
    """What one decrypted payload becomes for the shell (None: nothing).
    Pins the sender's key, opens sealed envelopes meant for this desktop."""
    if payload.get("kind") == "sealed":
        inner, sender_pk = open_private(sk, my_pk, payload, topic)
        if inner is None:
            # Someone else's private message: not even who it's for.
            return None
        sender = str(inner.get("from") or "")
        to = str(inner.get("to") or "")
        if inner.get("kind") not in ("message", "read") or not MEMBER_RE.match(sender) \
                or not MEMBER_RE.match(to) or myself not in (sender, to):
            return None
        if sender == myself:
            # Our own copy: sealed with our own key, or someone posing as us.
            if sender_pk != my_pk:
                note_key(myself, sender_pk, myself, told)
                return None
        elif not note_key(sender, sender_pk, myself, told):
            out({"event": "error", "error": f"a private message from {sender} was held back: its key isn't "
                                             "the one known for them (Trust the new key in the Mesh tab)"})
            return None
        data = inner.get("data") if isinstance(inner.get("data"), dict) else {}
        event = {"kind": inner["kind"], "from": sender, "name": str(inner.get("name") or "")[:64], "to": to,
                 "time": inner.get("time"), "mid": str(inner.get("mid") or ""), "data": data,
                 "private": True, "event": "message", "mine": sender == myself}
        return event
    sender = str(payload.get("from") or "")
    kind = payload.get("kind")
    if kind not in KINDS or not MEMBER_RE.match(sender):
        return None
    sender_pk = pk_of(payload.get("pk"))
    if sender_pk:
        note_key(sender, sender_pk, myself, told)
    if kind == "presence" and time.time() - float(payload.get("time") or 0) > STALE_PRESENCE:
        # Catching up: an old status says nothing about now (members count as
        # offline after 25 min), and months of them would only flood the shell.
        return None
    if payload.get("to"):
        # Private messages and receipts only travel sealed: an open one is a
        # forgery or an old client.
        return None
    payload.pop("pk", None)
    payload["event"] = "message"
    payload["mine"] = sender == myself
    return payload


def cmd_keys(args):
    """keys: the pinned keys; keys mine: this desktop's; keys trust MEMBER:
    take a member's new key."""
    what = args[0] if args else ""
    if what == "mine":
        _, pk = load_identity()
        out({"ok": True, "fingerprint": fingerprint(pk)})
        return
    if what == "trust":
        member = args[1] if len(args) > 1 else ""
        with locked("keys"):
            pins = load_pins()
            entry = pins.get(member)
            if not entry or not entry.get("changed"):
                fail(f"no new key to trust for {member}")
            entry["pk"] = entry.pop("changed")
            entry["since"] = int(time.time())
            save_pins(pins)
        out({"ok": True, "member": member, "fingerprint": fingerprint(pk_of(entry["pk"]))})
        return
    members = {}
    for member, entry in load_pins().items():
        pk = pk_of(entry.get("pk"))
        if not pk:
            continue
        changed = pk_of(entry.get("changed"))
        members[member] = {"fingerprint": fingerprint(pk),
                           "changed": fingerprint(changed) if changed else None}
    out({"ok": True, "members": members})


def cmd_listen(args):
    server = server_url(args[0] if args else "")
    token = token_or_fail()
    key = key_or_fail()
    topic = topic_of(key)
    myself = me()
    sk, my_pk = load_identity()
    pin(myself, my_pk)
    told = set()
    delay = 2
    warned = False
    cursor, seen = read_position()
    seen_set = set(seen)
    while True:
        # Resume where the last connection stopped; the first time, all the
        # server still has (3 months on nixbook's server).
        since = cursor or "all"
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
                    else:
                        event = receive(payload, topic, sk, my_pk, myself, told)
                        if event:
                            event["id"] = msg.get("id")
                            out(event)
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
            # Refused: it changes when the server's admin does something, so
            # a minute, not the quick retries of a network error.
            delay = 60 if e.code in (401, 403) else delay
        except (urllib.error.URLError, OSError, socket.timeout) as e:
            out({"event": "status", "connected": False, "error": http_error(e)})
        time.sleep(delay)
        delay = min(delay * 2, 60)


def main():
    args = sys.argv[1:]
    commands = {
        "status": cmd_status,
        "token": cmd_token,
        "mesh": cmd_mesh,
        "test": cmd_test,
        "send": cmd_send,
        "listen": cmd_listen,
        "invite": cmd_invite,
        "members": cmd_members,
        "remove": cmd_remove,
        "accept": cmd_accept,
        "keys": cmd_keys,
    }
    command = commands.get(args[0]) if args else None
    if not command:
        fail("usage: nixbook-mesh status|token|mesh|test|send|listen|invite|members|remove|accept|keys")
    try:
        command(args[1:])
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)


if __name__ == "__main__":
    main()
