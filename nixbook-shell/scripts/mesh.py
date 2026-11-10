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
"Private messages" below): the other members can't read it. Files (images,
GIFs, documents) go as encrypted ntfy attachments, their key in the message
(see "Files" below).

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
  sendfile SERVER               a file (stdin: {path, to, text, mid, name}):
                                encrypted, uploaded, then its message; progress
                                lines {"event": "progress", "done", "total"}
  fetch SERVER                  a received file (stdin: {file}), downloaded,
                                decrypted, checked (see "Files" below)
  save | prune                  a copy in Downloads (stdin: {path}) / delete the
                                files of messages gone (stdin: {keep: [sha…]})
  limits SERVER                 the largest file the server takes, and expiry
  send SERVER delete            delete one of your messages for everyone
                                (stdin: {target: its mid, to}): see "Deleting"
  match                         a song on YouTube Music like a Spotify one
                                (stdin: {title, artist, album, length}), for
                                listening together: {videoId, title, …}
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
import hmac
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

SERVICE = "nixbook-mesh"
VERSION = "m1"
# The server's ACL allows each member `mesh-*`.
TOPIC_PREFIX = "mesh-"
TOKEN_RE = re.compile(r"^tk_[A-Za-z0-9]{29}$")
MEMBER_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
KINDS = ("message", "presence", "read", "listen", "delete")
# What travels sealed when it is for one member.
PRIVATE_KINDS = ("message", "read", "listen", "delete")
MID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
MAX_TEXT = 1000
# ntfy sends a keepalive every 45s: nothing for this long means the
# connection is dead.
READ_TIMEOUT = 120
# Catching up, status updates older than this are skipped.
STALE_PRESENCE = 30 * 60
# Listening together: a session's state older than this says nothing now.
STALE_LISTEN = 2 * 60
LISTEN_OPS = ("state", "end", "join", "leave")
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


# Deleting. A message can be deleted for everyone by its sender only. Each
# message carries `dh`, the SHA-256 of a proof only its sender can make: an
# HMAC of the message's id under the sender's private key. Deleting it
# (kind `delete`, {target, proof}) shows the proof; the listener gives the
# shell its hash (`proofHash`), which must be the message's `dh`. So no
# member can delete someone else's message (the `from` of a message to
# everyone isn't proven), and a member joining later, who replays the
# history, sees the deletion too. A deletion in a private conversation is
# sealed like the message (which also proves its sender: messages from
# before `dh` can be deleted there). It is the desktops that delete: the
# server keeps its ciphertext until it expires, and a desktop that already
# showed the message can't be made to forget it.


def delete_proof(sk, topic, mid):
    raw = sk.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    return hmac.new(raw, b"nixbook-mesh delete v1\0" + topic.encode() + b"\0" + mid.encode(), hashlib.sha256).digest()


def delete_commitment(sk, topic, mid):
    return hashlib.sha256(delete_proof(sk, topic, mid)).hexdigest()


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
        if e.code == 413:
            return "too large for the mesh's server, or your daily transfer there is used up (413)"
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
    # A file only goes with `sendfile`, which uploads it first.
    data.pop("file", None)
    # Who it is for: a member, or everyone ("").
    to = str(data.pop("to", "") or "")
    if to and not MEMBER_RE.match(to):
        fail("not a member's name")
    if kind == "message":
        text = str(data.get("text") or "").strip()
        if not text:
            fail("nothing to send")
        data["text"] = text[:MAX_TEXT]
    if kind == "listen":
        data = listen_data(data)
    if kind == "delete":
        target = str(data.get("target") or "")
        if not MID_RE.match(target):
            fail("which message to delete?")
        data = {"target": target, "mid": data.get("mid"), "name": data.get("name")}
    token = token_or_fail()
    key = key_or_fail()
    mid = str(data.pop("mid", "") or secrets.token_hex(8))
    name = str(data.pop("name", "") or "")[:64]
    readers = readers_or_fail(to, kind)
    answer, now = publish(server, token, key, kind, to, data, mid, name, readers)
    reply = {"ok": True, "id": answer.get("id"), "mid": mid, "time": now}
    if kind == "message":
        reply["dh"] = delete_commitment(readers[0], topic_of(key), mid)
    out(reply)


def listen_data(data):
    """A listening-together event, kept to what it needs: {op, sid, service,
    track: {id, title, artist, album, length, art}, position, playing, at}."""
    op = str(data.get("op") or "")
    sid = str(data.get("sid") or "")
    if op not in LISTEN_OPS or not re.match(r"^[0-9a-f]{8,32}$", sid):
        fail("not a listening-together event")
    clean = {"op": op, "sid": sid}
    if op == "state":
        service = str(data.get("service") or "")
        if service not in ("spotify", "youtube-music", "jellyfin"):
            fail("only YouTube Music, Spotify and Jellyfin can be shared")
        t = data.get("track") if isinstance(data.get("track"), dict) else {}
        track = {k: str(t.get(k) or "")[:300] for k in ("id", "title", "artist", "album", "art")}
        if not re.match(r"^[A-Za-z0-9_-]{1,64}$", track["id"]):
            fail("no track to share")
        if not re.match(r"^https://", track["art"]):
            track["art"] = ""
        try:
            track["length"] = max(0.0, float(t.get("length") or 0))
            clean["position"] = max(0.0, float(data.get("position") or 0))
            clean["at"] = int(data.get("at") or time.time() * 1000)
        except (TypeError, ValueError):
            fail("not a listening-together event")
        clean.update(service=service, track=track, playing=bool(data.get("playing")))
        if service == "jellyfin" and isinstance(data.get("jf"), dict):
            clean["jf"] = jellyfin_item(data["jf"])
    return clean


def jellyfin_item(jf):
    """What finds a Jellyfin item on another server (jellyfin-mcp
    listen-info): the server, the item, its kind, names, numbers, the ids
    of IMDb/TMDb/TVDb."""
    def num(v):
        try:
            return int(v) if v is not None else None
        except (TypeError, ValueError):
            return None

    def ids(d):
        return {k: str(v)[:40] for k, v in (d or {}).items()
                if k in ("imdb", "tmdb", "tvdb") and re.match(r"^[\w.-]{1,40}$", str(v))} if isinstance(d, dict) else {}

    kind = str(jf.get("type") or "")
    return {"serverId": str(jf.get("serverId") or "")[:64], "id": str(jf.get("id") or "")[:64],
            "type": kind if kind in ("Movie", "Episode", "Audio", "MusicVideo", "Video") else "",
            "name": str(jf.get("name") or "")[:200], "seriesName": str(jf.get("seriesName") or "")[:200],
            "season": num(jf.get("season")), "episode": num(jf.get("episode")), "year": num(jf.get("year")),
            "providers": ids(jf.get("providers")), "seriesProviders": ids(jf.get("seriesProviders"))}


def readers_or_fail(to, kind):
    """Who can open a private message or receipt to `to`: (sk, my_pk,
    their keys), checked before anything leaves (a file is uploaded first).
    None for what goes to everyone."""
    sk, my_pk = load_identity()
    if not (to and kind in PRIVATE_KINDS):
        return sk, my_pk, None
    myself = me()
    # Sealed: for the recipient's key alone (and the sender's own copy).
    their_pk, changed = (my_pk, False) if to == myself else pinned(to)
    if not their_pk:
        fail(f"{to}'s desktop hasn't been seen yet, so there is no key to write to them privately: "
             "they need to come online once")
    if changed:
        fail(f"{to}'s key changed: check it in the Mesh tab (Trust the new key) before writing privately")
    return sk, my_pk, [their_pk] if to == myself else [their_pk, my_pk]


def publish(server, token, key, kind, to, data, mid, name, readers):
    topic = topic_of(key)
    sk, my_pk, sealed_for = readers
    myself = me()
    now = int(time.time())
    if kind == "message":
        data = dict(data, dh=delete_commitment(sk, topic, mid))
    if kind == "delete":
        data = dict(data, proof=delete_proof(sk, topic, data["target"]).hex())
    if sealed_for:
        inner = {"kind": kind, "from": myself, "name": name, "to": to, "time": now, "mid": mid, "data": data}
        payload = seal_private(sk, my_pk, sealed_for, inner, topic)
    else:
        payload = {"kind": kind, "from": myself, "name": name, "to": to, "time": now,
                   "mid": mid, "pk": b64(my_pk), "data": data}
    body = seal(key, topic, payload).encode()
    try:
        with request(f"{server}/{topic}", token, data=body, method="POST") as r:
            answer = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(http_error(e))
    return answer, now


# -- Files ------------------------------------------------------------------------------
#
# A file (an image, a GIF, a PDF…) is encrypted on the sender's desktop with
# a key of its own (AES-256-GCM, streamed: memory stays flat whatever its
# size) and uploaded as an ntfy attachment, on a topic of its own (derived
# from the mesh key, like the mesh's; nobody listens to it). Only its path
# on the server, its key and what it is travel in the message, which is
# sealed like any other (for its recipient alone when private): the server
# keeps ciphertext under a random name. ntfy deletes attachments after a
# while (a year on nixbook's server), so the shell downloads each file up to
# 250 MB as soon as its message arrives (`fetch`; bigger ones on a click),
# into $XDG_DATA_HOME/nixbook-shell/mesh/files/<sha256>/<name>; the sender
# keeps a copy there too (up to COPY_MAX). How big a file
# may be is the server's to say (`limits`: /v1/account).

CHUNK = 1 << 20
FILE_PATH_RE = re.compile(r"^/file/[A-Za-z0-9]{1,32}(\.[A-Za-z0-9]{1,8})?$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
DIR_RE = re.compile(r"^[0-9a-f]{32}$")
TAG = 16
# The sender keeps a copy of what it sends, up to this size (bytes): a
# bigger file is shown from where it was picked, not doubled on the disk.
COPY_MAX = int(os.environ.get("NIXBOOK_MESH_COPY_MAX") or 250 * 1000 * 1000)


class NoCopy:
    def write(self, _data):
        pass


def files_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return Path(base) / "nixbook-shell" / "mesh" / "files"


def files_topic_of(key):
    return TOPIC_PREFIX + hashlib.sha256(b"nixbook-mesh files\0" + key).hexdigest()[:24]


def safe_name(name):
    """A file name that stays a file name: no folders, no control
    characters, not hidden, not too long (its extension kept)."""
    name = re.sub(r"[\x00-\x1f\x7f/\\]", "", os.path.basename(str(name or ""))).strip().lstrip(".")
    if not name:
        return "file"
    if len(name) > 120:
        stem, dot, ext = name.rpartition(".")
        name = (stem[:110] + "." + ext[:9]) if dot and len(ext) <= 9 else name[:120]
    return name


def sniff(path):
    """What a file is, from its first bytes (never from its name or what
    the sender said): {mime, image, animated, w, h}."""
    try:
        with open(path, "rb") as f:
            head = f.read(CHUNK)
    except OSError:
        head = b""
    info = {"mime": "", "image": False, "animated": False, "w": 0, "h": 0}
    if head.startswith(b"\x89PNG\r\n\x1a\n") and len(head) >= 24:
        info.update(mime="image/png", image=True, w=int.from_bytes(head[16:20], "big"),
                    h=int.from_bytes(head[20:24], "big"), animated=b"acTL" in head[:4096])
    elif head[:6] in (b"GIF87a", b"GIF89a") and len(head) >= 10:
        info.update(mime="image/gif", image=True, animated=True, w=int.from_bytes(head[6:8], "little"),
                    h=int.from_bytes(head[8:10], "little"))
    elif head.startswith(b"\xff\xd8"):
        info.update(mime="image/jpeg", image=True)
        i = 2
        while i + 9 < len(head):
            if head[i] != 0xFF:
                i += 1
                continue
            marker = head[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7 or marker == 0xFF:
                i += 1 if marker == 0xFF else 2
                continue
            length = int.from_bytes(head[i + 2:i + 4], "big")
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                info.update(h=int.from_bytes(head[i + 5:i + 7], "big"), w=int.from_bytes(head[i + 7:i + 9], "big"))
                break
            i += 2 + length
    elif head[:4] == b"RIFF" and head[8:12] == b"WEBP" and len(head) >= 30:
        info.update(mime="image/webp", image=True)
        chunk = head[12:16]
        if chunk == b"VP8X":
            info.update(animated=bool(head[20] & 0x02), w=1 + int.from_bytes(head[24:27], "little"),
                        h=1 + int.from_bytes(head[27:30], "little"))
        elif chunk == b"VP8 ":
            info.update(w=int.from_bytes(head[26:28], "little") & 0x3FFF, h=int.from_bytes(head[28:30], "little") & 0x3FFF)
        elif chunk == b"VP8L":
            bits = int.from_bytes(head[21:25], "little")
            info.update(w=(bits & 0x3FFF) + 1, h=((bits >> 14) & 0x3FFF) + 1)
    if not info["mime"]:
        import mimetypes
        info["mime"] = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
    return info


def account_limits(server, token):
    """The server's attachment limits for this account (bytes, seconds)."""
    try:
        account = api(server, "/v1/account", token=token)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(http_error(e))
    limits = account.get("limits") or {}
    stats = account.get("stats") or {}
    return {
        "maxFile": int(limits.get("attachment_file_size") or 0),
        "remaining": int(stats.get("attachment_total_size_remaining") or limits.get("attachment_total_size") or 0),
        "expiry": int(limits.get("attachment_expiry_duration") or 0),
    }


def cmd_limits(args):
    server = server_url(args[0] if args else "")
    limits = account_limits(server, token_or_fail())
    # The file's own size: what the server stores is 16 bytes more (the tag).
    out({"ok": True, "maxFile": max(0, limits["maxFile"] - TAG), "remaining": max(0, limits["remaining"] - TAG),
         "expiry": limits["expiry"]})


class Progress:
    """`{"event": "progress", "done", "total"}` lines, at most 5 a second."""

    def __init__(self, total):
        self.total, self.done, self.last = total, 0, 0.0

    def add(self, n):
        self.done += n
        now = time.monotonic()
        if now - self.last >= 0.2 or self.done >= self.total:
            self.last = now
            out({"event": "progress", "done": self.done, "total": self.total})


class EncryptingReader:
    """The upload's body: the file encrypted chunk by chunk, then the GCM
    tag; also hashes it and writes the sender's own copy."""

    def __init__(self, src, key, nonce, copy, progress):
        self.src, self.copy, self.progress = src, copy, progress
        self.enc = Cipher(algorithms.AES(key), modes.GCM(nonce)).encryptor()
        self.sha = hashlib.sha256()
        self.done = False

    def read(self, n=-1):
        if self.done:
            return b""
        plain = self.src.read(CHUNK if n is None or n < 0 else max(n, 1))
        if plain:
            self.sha.update(plain)
            self.copy.write(plain)
            self.progress.add(len(plain))
            return self.enc.update(plain)
        self.done = True
        return self.enc.finalize() + self.enc.tag


def private_file(directory):
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)


def cmd_sendfile(args):
    """sendfile SERVER, stdin {path, to, text, mid, name}: uploads the file,
    then sends its message."""
    server = server_url(args[0] if args else "")
    try:
        data = json.loads(sys.stdin.readline() or "{}")
    except ValueError:
        fail("the data isn't JSON")
    if not isinstance(data, dict):
        fail("the data must be an object")
    path = Path(str(data.get("path") or "").removeprefix("file://")).expanduser()
    to = str(data.get("to") or "")
    if to and not MEMBER_RE.match(to):
        fail("not a member's name")
    try:
        st = path.stat()
    except OSError:
        fail(f"{path.name or 'the file'} can't be read")
    if not path.is_file():
        fail(f"{path.name} isn't a file")
    if st.st_size == 0:
        fail(f"{path.name} is empty")
    token = token_or_fail()
    key = key_or_fail()
    mid = str(data.get("mid") or secrets.token_hex(8))
    name = str(data.get("name") or "")[:64]
    readers = readers_or_fail(to, "message")
    limits = account_limits(server, token)
    size = st.st_size
    if limits["maxFile"] and size + TAG > limits["maxFile"]:
        fail(f"{path.name} is {human_size(size)}: the mesh's server takes files up to "
             f"{human_size(max(0, limits['maxFile'] - TAG))}")
    if limits["remaining"] and size + TAG > limits["remaining"]:
        fail(f"the server holds too many of your files right now ({human_size(limits['remaining'])} left): "
             "try again later, they are deleted after a while")
    file_key, nonce = secrets.token_bytes(32), secrets.token_bytes(12)
    info = sniff(path)
    fdir = files_dir()
    private_file(fdir)
    tmp = fdir / f".send.{os.getpid()}.tmp"
    keep_copy = size <= COPY_MAX
    try:
        with open(path, "rb") as src, \
                (open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") if keep_copy
                 else contextlib.nullcontext(NoCopy())) as copy:
            body = EncryptingReader(src, file_key, nonce, copy, Progress(size))
            req = urllib.request.Request(f"{server}/{files_topic_of(key)}", data=body, method="PUT")
            req.add_header("Authorization", f"Bearer {token}")
            req.add_header("User-Agent", USER_AGENT)
            req.add_header("Content-Length", str(size + TAG))
            req.add_header("Filename", "f.bin")
            req.add_header("X-Firebase", "no")
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    answer = json.load(r)
            except (urllib.error.URLError, OSError, ValueError) as e:
                fail(http_error(e))
        sha = body.sha.hexdigest()
        attachment = answer.get("attachment") or {}
        server_path = urllib.parse.urlparse(str(attachment.get("url") or "")).path
        if not FILE_PATH_RE.match(server_path):
            fail("the server didn't take the file (are attachments turned on there?)")
        if keep_copy:
            local = fdir / sha[:32] / safe_name(path.name)
            private_file(local.parent)
            os.replace(tmp, local)
        else:
            local = path.resolve()
    finally:
        with contextlib.suppress(OSError):
            tmp.unlink()
    meta = {"u": server_path, "k": b64(file_key), "n": b64(nonce), "name": safe_name(path.name), "size": size,
            "sha": sha, "mime": info["mime"], "w": info["w"], "h": info["h"],
            "exp": int(attachment.get("expires") or 0)}
    text = str(data.get("text") or "").strip()[:MAX_TEXT]
    _, now = publish(server, token, key, "message", to, {"text": text, "file": meta}, mid, name, readers)
    out({"ok": True, "mid": mid, "time": now, "text": text, "dh": delete_commitment(readers[0], topic_of(key), mid),
         "file": local_meta(local, sha, size, info, meta["exp"])})


def local_meta(path, sha, size, info, exp=0):
    return {"path": str(path), "name": path.name, "size": size, "sha": sha, "mime": info["mime"],
            "image": info["image"], "animated": info["animated"], "w": info["w"], "h": info["h"], "exp": exp}


def human_size(n):
    for unit in ("bytes", "KB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1000


def cmd_fetch(args):
    """fetch SERVER, stdin {file}: a received file, downloaded and
    decrypted into the files folder (checked against its hash)."""
    server = server_url(args[0] if args else "")
    try:
        meta = (json.loads(sys.stdin.readline() or "{}") or {}).get("file") or {}
    except (ValueError, AttributeError):
        fail("the data isn't JSON")
    if not isinstance(meta, dict):
        fail("no file")
    sha = str(meta.get("sha") or "")
    u = str(meta.get("u") or "")
    try:
        size = int(meta.get("size") or 0)
        file_key = base64.b64decode(str(meta.get("k") or ""), validate=True)
        nonce = base64.b64decode(str(meta.get("n") or ""), validate=True)
    except (ValueError, TypeError, binascii.Error):
        fail("this file's details aren't right")
    # Only from this mesh's own server, only its attachments: a member can't
    # make this desktop fetch anything else (nor send its token elsewhere).
    if not SHA_RE.match(sha) or not FILE_PATH_RE.match(u) or len(file_key) != 32 or len(nonce) != 12 \
            or not 0 < size < 1 << 34:
        fail("this file's details aren't right")
    local = files_dir() / sha[:32] / safe_name(meta.get("name"))
    if local.is_file() and local.stat().st_size == size:
        out({"ok": True, "file": local_meta(local, sha, size, sniff(local))})
        return
    token = token_or_fail()
    private_file(local.parent)
    tmp = local.parent / f".fetch.{os.getpid()}.tmp"
    try:
        try:
            r = request(f"{server}{u}", token, timeout=120)
        except urllib.error.HTTPError as e:
            if e.code in (404, 410):
                out({"ok": False, "expired": True, "error": "the file is no longer on the server"})
                sys.exit(1)
            fail(http_error(e))
        except (urllib.error.URLError, OSError) as e:
            fail(http_error(e))
        dec = Cipher(algorithms.AES(file_key), modes.GCM(nonce)).decryptor()
        digest = hashlib.sha256()
        progress = Progress(size)
        held = b""
        got = 0
        with r, open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as f:
            while True:
                try:
                    chunk = r.read(CHUNK)
                except (OSError, socket.timeout) as e:
                    fail(http_error(e))
                if not chunk:
                    break
                got += len(chunk)
                if got > size + TAG:
                    fail("the file on the server isn't the one sent")
                held += chunk
                body, held = held[:-TAG], held[-TAG:]
                plain = dec.update(body)
                digest.update(plain)
                f.write(plain)
                progress.add(len(plain))
            try:
                f.write(dec.finalize_with_tag(held))
            except (InvalidTag, ValueError):
                fail("the file couldn't be decrypted: it isn't the one sent")
        if got != size + TAG or digest.hexdigest() != sha:
            fail("the file on the server isn't the one sent")
        os.replace(tmp, local)
    finally:
        with contextlib.suppress(OSError):
            tmp.unlink()
    out({"ok": True, "file": local_meta(local, sha, size, sniff(local))})


def in_files(path):
    """`path` if it is one of the files folder's files, else fail."""
    try:
        p = Path(str(path or "").removeprefix("file://")).resolve(strict=True)
        root = files_dir().resolve(strict=True)
    except OSError:
        fail("that file isn't there any more")
    if p.parent.parent != root or not DIR_RE.match(p.parent.name) or not p.is_file():
        fail("not one of the mesh's files")
    return p


def downloads_dir():
    try:
        r = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=5)
        d = r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        d = ""
    home = os.path.expanduser("~")
    return Path(d if d and d != home else os.path.join(home, "Downloads"))


def cmd_save(_args):
    """save, stdin {path}: a copy of a mesh file in the Downloads folder
    (a free name: "photo (2).jpg")."""
    try:
        data = json.loads(sys.stdin.readline() or "{}")
    except ValueError:
        fail("the data isn't JSON")
    src = in_files(data.get("path") if isinstance(data, dict) else "")
    dest_dir = downloads_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    stem, dot, ext = src.name.rpartition(".")
    if not dot or not stem:
        stem, ext = src.name, ""
    for i in range(1, 1000):
        name = src.name if i == 1 else (f"{stem} ({i}).{ext}" if ext else f"{stem} ({i})")
        dest = dest_dir / name
        try:
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError:
            continue
        with open(src, "rb") as s, os.fdopen(fd, "wb") as d:
            shutil.copyfileobj(s, d, CHUNK)
        out({"ok": True, "path": str(dest)})
        return
    fail("no free name in the Downloads folder")


def cmd_prune(_args):
    """prune, stdin {keep: [sha…]}: the files of messages no longer kept go."""
    try:
        data = json.loads(sys.stdin.readline() or "{}")
        keep = {str(s)[:32] for s in data.get("keep") or []}
    except (ValueError, AttributeError, TypeError):
        fail("the data isn't JSON")
    removed = 0
    root = files_dir()
    for d in root.iterdir() if root.is_dir() else []:
        if d.is_dir() and DIR_RE.match(d.name) and d.name not in keep:
            shutil.rmtree(d, ignore_errors=True)
            removed += 1
    out({"ok": True, "removed": removed})


# -- Listening together: a Spotify track on YouTube Music -------------------
#
# A listener without the host's app follows on the other one. Spotify has no
# search without an account, YouTube Music's own web client (InnerTube) has:
# `match`, stdin {title, artist, album, length}, finds the song there (the
# closest title, artist and length) and answers its videoId.

YT_SEARCH = "https://music.youtube.com/youtubei/v1/search?prettyPrint=false"
# The "Songs" filter of YouTube Music's search.
YT_SONGS = "EgWKAQIIAWoMEA4QChADEAQQCRAF"


def _fold(text):
    import unicodedata
    text = unicodedata.normalize("NFKD", str(text or "").lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return set(re.findall(r"[a-z0-9]+", text))


def _duration(text):
    m = re.search(r"\b(?:(\d+):)?(\d{1,2}):(\d\d)\b", text)
    if not m:
        return 0
    return int(m.group(1) or 0) * 3600 + int(m.group(2)) * 60 + int(m.group(3))


def yt_results(query):
    body = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "en"}},
            "query": query, "params": YT_SONGS}
    req = urllib.request.Request(YT_SEARCH, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0",
                                          "Origin": "https://music.youtube.com"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)

    def walk(o):
        if isinstance(o, dict):
            if "musicResponsiveListItemRenderer" in o:
                yield o["musicResponsiveListItemRenderer"]
            for v in o.values():
                yield from walk(v)
        elif isinstance(o, list):
            for v in o:
                yield from walk(v)

    out = []
    for item in walk(data):
        vid = (item.get("playlistItemData") or {}).get("videoId") or ""
        cols = []
        for c in item.get("flexColumns") or []:
            runs = ((c.get("musicResponsiveListItemFlexColumnRenderer") or {}).get("text") or {}).get("runs") or []
            cols.append("".join(str(x.get("text") or "") for x in runs))
        if re.match(r"^[\w-]{11}$", vid) and cols:
            out.append({"videoId": vid, "title": cols[0], "line": cols[1] if len(cols) > 1 else "",
                        "length": _duration(cols[1] if len(cols) > 1 else "")})
    return out


def best_match(want, results):
    """The result closest to `want` {title, artist, length}: title words,
    then artist words, then length (a radio edit isn't the album version)."""
    title, artist = _fold(want.get("title")), _fold(want.get("artist"))
    length = float(want.get("length") or 0)
    best, best_score = None, 0.0
    for r in results:
        got_title, got_line = _fold(r["title"]), _fold(r["line"])
        if not title:
            continue
        t = len(title & got_title) / len(title)
        a = len(artist & got_line) / len(artist) if artist else 0.5
        d = 1.0
        if length and r["length"]:
            d = max(0.0, 1 - abs(r["length"] - length) / 30)
        score = 0.5 * t + 0.3 * a + 0.2 * d
        if t >= 0.5 and score > best_score:
            best, best_score = r, score
    return best, best_score


def cmd_match(_args):
    try:
        want = json.loads(sys.stdin.readline() or "{}")
    except ValueError:
        fail("the data isn't JSON")
    if not isinstance(want, dict) or not str(want.get("title") or "").strip():
        fail("no track to look for")
    query = f"{want.get('artist') or ''} {want.get('title')}".strip()
    try:
        results = yt_results(query[:200])
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail(f"YouTube Music can't be searched ({getattr(e, 'reason', e)})")
    best, score = best_match(want, results)
    if not best:
        fail(f"no song like \"{want.get('title')}\" on YouTube Music")
    out({"ok": True, "videoId": best["videoId"], "title": best["title"], "line": best["line"],
         "length": best["length"], "score": round(score, 2)})


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
        if inner.get("kind") not in PRIVATE_KINDS or not MEMBER_RE.match(sender) \
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
        if inner["kind"] == "listen" and time.time() - float(inner.get("time") or 0) > STALE_LISTEN:
            return None
        if inner["kind"] == "delete":
            data = deletion(data)
            if data is None:
                return None
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
    if kind == "listen" and time.time() - float(payload.get("time") or 0) > STALE_LISTEN:
        return None
    if kind == "presence" and time.time() - float(payload.get("time") or 0) > STALE_PRESENCE:
        # Catching up: an old status says nothing about now (members count as
        # offline after 25 min), and months of them would only flood the shell.
        return None
    if payload.get("to"):
        # Private messages and receipts only travel sealed: an open one is a
        # forgery or an old client.
        return None
    if kind == "delete":
        payload["data"] = deletion(payload.get("data"))
        if payload["data"] is None:
            return None
    payload.pop("pk", None)
    payload["event"] = "message"
    payload["mine"] = sender == myself
    return payload


def deletion(data):
    """A deletion for the shell: {target, proofHash} (see "Deleting"), the
    proof itself kept back; None when it isn't one."""
    if not isinstance(data, dict):
        return None
    target = str(data.get("target") or "")
    proof = str(data.get("proof") or "")
    if not MID_RE.match(target):
        return None
    clean = {"target": target, "proofHash": ""}
    if re.match(r"^[0-9a-f]{64}$", proof):
        clean["proofHash"] = hashlib.sha256(bytes.fromhex(proof)).hexdigest()
    return clean


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
        # server still has (a year on nixbook's server).
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
        "sendfile": cmd_sendfile,
        "fetch": cmd_fetch,
        "save": cmd_save,
        "prune": cmd_prune,
        "limits": cmd_limits,
        "match": cmd_match,
    }
    command = commands.get(args[0]) if args else None
    if not command:
        fail("usage: nixbook-mesh status|token|mesh|test|send|sendfile|fetch|save|prune|limits|listen|invite|members|"
             "remove|accept|keys")
    try:
        command(args[1:])
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)


if __name__ == "__main__":
    main()
