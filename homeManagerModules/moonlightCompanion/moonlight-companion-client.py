"""Moonlight companion, the watching machine's side.

While Moonlight runs here and a paired Sunshine host is streaming, this reads
what the host's moonlight-companion keeps after the end of its Desktop app's
cover picture (Sunshine's own port, with Moonlight's own pairing: no login,
no other service) and does two things with it:

  --discord   shows the Steam game the host runs as this desktop's Discord
              activity (Discord only sees local processes): the game is looked
              up in Discord's public list of known games and announced on the
              local rich-presence socket (the Discord client's, or Vesktop's
              arRPC);
  --radio     is the companion program of the Cyberpunk 2077 mod Music Radio
              (Nexus 38098): the mod writes the acoustics of the moment (in
              the car, beside it, a tunnel, a club...) and the station's
              commands, and this applies them to the YouTube Music panel's own
              player (nixbook-ytmusic's mpv) as a filter chain changed in
              place, and runs play / pause / next / previous on it.

    moonlight-companion-client [--discord] [--radio] [--ytmusic BINARY]
                               [--mpv SOCKET] [--once]
    (tests: --base http://HOST:PORT reads there, without Moonlight)

The mod's effect line: P hp lp pkf pkdb gain t1 g1 t2 g2 pan mono bass treble
(high-pass and low-pass Hz, a peak filter, the volume, two echo taps in ms
with their levels, left/right, how mono, two tone shelves in dB).
"""

import base64
import http.client
import json
import math
import os
import re
import select
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

MARK = b"\nMLC1\n"
CONF = "~/.config/Moonlight Game Streaming Project/Moonlight.conf"
CLIENT_ID = "0123456789ABCDEF"
LIST_URL = "https://discord.com/api/v9/applications/detectable"
LIST_MAX_AGE = 7 * 86400
LIST_RETRY = 3600
LABEL = "gameradio"
MAX_DELAY = 400
READ = 0.12
STEP = 0.04
OFF_GRACE = 2.0
IDLE = 15


def log(*words):
    print(time.strftime("%H:%M:%S"), *words, file=sys.stderr, flush=True)


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "moonlight-companion")


def moonlight_runs():
    # Nix wraps the program: its process is ".moonlight-wrapped", which the
    # kernel shortens to 15 characters.
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm") as f:
                if f.read().strip() in ("moonlight", ".moonlight-wrap"):
                    return True
        except OSError:
            pass
    return False


# ---------------------------------------------------------------- the link


def qt_value(text):
    """A value of Moonlight's settings file (Qt): quotes, @ByteArray(), escapes."""
    text = text.strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    if text.startswith("@ByteArray(") and text.endswith(")"):
        text = text[11:-1]
    return text.replace("\\n", "\n").replace("\\r", "").replace('\\"', '"')


def der(pem):
    body = "".join(line for line in pem.splitlines() if line and not line.startswith("-----"))
    try:
        return base64.b64decode(body)
    except ValueError:
        return b""


class Link:
    """The paired Sunshine hosts, as Moonlight itself knows them."""

    def __init__(self, base=None):
        self.base = base
        self.stamp = None
        self.context = None
        self.hosts = []
        self.conn = None
        self.conn_key = None

    def load(self):
        path = os.path.expanduser(CONF)
        try:
            stamp = os.stat(path).st_mtime
        except OSError:
            self.hosts, self.context = [], None
            return
        if stamp == self.stamp:
            return
        self.stamp = stamp
        with open(path, encoding="utf-8", errors="replace") as f:
            raw = f.read()
        found = {}
        for n, key, value in re.findall(r"^(\d+)\\(\w+)=(.*)$", raw, re.M):
            found.setdefault(n, {})[key] = qt_value(value)
        self.hosts = []
        for h in found.values():
            for kind in ("local", "manual", "remote"):
                address, port = h.get(kind + "address"), h.get(kind + "port") or "0"
                if address and port.isdigit() and int(port) > 5:
                    entry = (h.get("hostname") or address, address, int(port) - 5, der(h.get("srvcert", "")))
                    if entry[1:3] not in [e[1:3] for e in self.hosts]:
                        self.hosts.append(entry)
        cert = re.search(r"^certificate=(.*)$", raw, re.M)
        key = re.search(r"^key=(.*)$", raw, re.M)
        self.context = None
        if cert and key:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            # The host's certificate is self-made: it is compared with the one
            # Moonlight kept at the pairing instead (see get()).
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            folder = tempfile.mkdtemp(prefix="moonlight-companion-", dir=runtime_dir())
            try:
                paths = []
                for name, text in (("cert.pem", qt_value(cert.group(1))), ("key.pem", qt_value(key.group(1)))):
                    paths.append(os.path.join(folder, name))
                    fd = os.open(paths[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    with os.fdopen(fd, "w") as f:
                        f.write(text)
                context.load_cert_chain(paths[0], paths[1])
                self.context = context
            except (OSError, ssl.SSLError) as error:
                log("Moonlight's pairing couldn't be read:", error)
            finally:
                for name in os.listdir(folder):
                    os.remove(os.path.join(folder, name))
                os.rmdir(folder)

    def close(self):
        if self.conn:
            try:
                self.conn.close()
            except OSError:
                pass
        self.conn = None
        self.conn_key = None

    def get(self, host, path, timeout=4):
        """GET on a host's GameStream port, the connection kept; None when it fails."""
        if self.base:
            key = self.base
        else:
            key = host[1:3]
        for attempt in (0, 1):
            try:
                if self.conn is None or self.conn_key != key:
                    self.close()
                    if self.base:
                        url = urllib.parse.urlsplit(self.base)
                        self.conn = http.client.HTTPConnection(url.hostname, url.port, timeout=timeout)
                    else:
                        if not self.context:
                            return None
                        self.conn = http.client.HTTPSConnection(host[1], host[2], context=self.context, timeout=timeout)
                        self.conn.connect()
                        if not host[3] or self.conn.sock.getpeercert(binary_form=True) != host[3]:
                            log(host[0], "isn't the machine Moonlight paired with")
                            self.close()
                            return None
                    self.conn_key = key
                self.conn.request("GET", path)
                reply = self.conn.getresponse()
                body = reply.read()
                return body if reply.status == 200 else None
            except (OSError, http.client.HTTPException, ssl.SSLError):
                self.close()
                if attempt:
                    return None
        return None

    def streaming(self):
        """The first paired host that streams now: (host, its running app's id)."""
        if self.base:
            return ("test", "", 0, b""), "1"
        self.load()
        for host in self.hosts:
            body = self.get(host, f"/serverinfo?uniqueid={CLIENT_ID}", timeout=3)
            text = (body or b"").decode(errors="replace")
            state = re.search(r"<state>([^<]*)</state>", text)
            game = re.search(r"<currentgame>(\d+)</currentgame>", text)
            if state and state.group(1).endswith("_BUSY") and game and game.group(1) != "0":
                return host, game.group(1)
        self.close()
        return None, None

    def read(self, host, app):
        """What the host's companion says: {G, F, A, C}, or None."""
        path = f"/appasset?uniqueid={CLIENT_ID}&appid={app}&AssetType=2&AssetIdx=0"
        body = self.get(host, path)
        if body is None:
            return None
        at = body.rfind(MARK)
        values = {}
        if at >= 0:
            for line in body[at + len(MARK):].decode(errors="replace").split("\n"):
                if len(line) >= 2 and line[1] == " ":
                    values[line[0]] = line[2:]
        return values


# ---------------------------------------------------------------- Discord


def norm(name):
    return "".join(c for c in name.lower() if c.isalnum())


class Games:
    """Discord's list of known games: Steam app id or name -> application id."""

    def __init__(self):
        self.path = os.path.join(cache_dir(), "detectable.json")
        self.by_steam = {}
        self.by_name = {}
        self.loaded = 0
        self.tried = 0

    def refresh(self):
        now = time.time()
        try:
            age = now - os.stat(self.path).st_mtime
        except OSError:
            age = None
        if (age is None or age > LIST_MAX_AGE) and now - self.tried > LIST_RETRY:
            self.tried = now
            try:
                request = urllib.request.Request(
                    LIST_URL, headers={"User-Agent": "moonlight-presence"}
                )
                with urllib.request.urlopen(request, timeout=30) as reply:
                    data = reply.read()
                json.loads(data)
                os.makedirs(cache_dir(), exist_ok=True)
                tmp = self.path + ".part"
                with open(tmp, "wb") as f:
                    f.write(data)
                os.replace(tmp, self.path)
                age = 0
            except (OSError, ValueError) as error:
                log("Discord's list of games couldn't be fetched:", error)
        try:
            stamp = os.stat(self.path).st_mtime
        except OSError:
            return
        if stamp == self.loaded:
            return
        try:
            with open(self.path) as f:
                apps = json.load(f)
        except (OSError, ValueError):
            return
        self.by_steam, self.by_name = {}, {}
        for app in apps:
            if not isinstance(app, dict) or not app.get("id"):
                continue
            for sku in app.get("third_party_skus") or []:
                if sku.get("distributor") == "steam" and sku.get("id"):
                    self.by_steam.setdefault(str(sku["id"]), app["id"])
            for name in [app.get("name") or ""] + (app.get("aliases") or []):
                if norm(name):
                    self.by_name.setdefault(norm(name), app["id"])
        self.loaded = stamp

    def find(self, game):
        self.refresh()
        return self.by_steam.get(game["steam"]) or self.by_name.get(norm(game["name"]))


class Presence:
    """One activity on Discord's local socket; closing it clears the activity."""

    def __init__(self):
        self.sock = None
        self.shown = None

    def _send(self, op, payload):
        data = json.dumps(payload).encode()
        self.sock.sendall(struct.pack("<II", op, len(data)) + data)

    def _read(self):
        head = b""
        while len(head) < 8:
            chunk = self.sock.recv(8 - len(head))
            if not chunk:
                raise OSError("closed")
            head += chunk
        _, size = struct.unpack("<II", head)
        body = b""
        while len(body) < size:
            chunk = self.sock.recv(size - len(body))
            if not chunk:
                raise OSError("closed")
            body += chunk
        return json.loads(body or b"{}")

    def alive(self):
        if not self.sock:
            return False
        try:
            readable, _, _ = select.select([self.sock], [], [], 0)
            while readable:
                self._read()
                readable, _, _ = select.select([self.sock], [], [], 0)
            return True
        except (OSError, ValueError):
            self.clear()
            return False

    def show(self, app_id, start):
        key = (app_id, start)
        if self.shown == key and self.alive():
            return True
        self.clear()
        for n in range(10):
            path = os.path.join(runtime_dir(), f"discord-ipc-{n}")
            if not os.path.exists(path):
                continue
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5)
            try:
                sock.connect(path)
                self.sock = sock
                self._send(0, {"v": 1, "client_id": app_id})
                self._read()
                self._send(
                    1,
                    {
                        "cmd": "SET_ACTIVITY",
                        "nonce": str(time.time()),
                        "args": {
                            "pid": os.getpid(),
                            "activity": {"timestamps": {"start": start * 1000}},
                        },
                    },
                )
                self._read()
                self.shown = key
                return True
            except (OSError, ValueError):
                sock.close()
                self.sock = None
        return False

    def clear(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.shown = None


# ---------------------------------------------------------------- the radio


def graph(v):
    """The chain, starting at these values: a new song starts with them too."""
    return (
        f"highpass@hp=f={v['hp']:.0f}:p=2,lowpass@lp=f={v['lp']:.0f}:p=2,"
        f"equalizer@pk=f={v['pkf']:.0f}:t=q:w=1:g={v['pkdb']:.2f},"
        f"bass@bs=g={v['bass']:.1f},treble@tr=g={v['treble']:.1f},"
        "asplit=3[d][a][b];"
        f"[a]adelay@d1=delays={v['t1']:.0f}:all=1,volume@g1=volume={v['g1']:.3f}[x];"
        f"[b]adelay@d2=delays={v['t2']:.0f}:all=1,volume@g2=volume={v['g2']:.3f}[y];"
        "[d][x][y]amix=inputs=3:normalize=0,"
        f"stereotools@st=slev={v['slev']:.2f}:balance_out={v['pan']:.2f},"
        f"volume@vol=volume={v['gain']:.3f},"
        "alimiter=limit=0.95"
    )


class Mpv:
    """The panel's mpv, through its IPC socket: one connection, kept."""

    # The player made its filters anew (another song, a seek, a changed
    # chain): they are back at the values the chain was built with.
    RESTARTS = ("file-loaded", "playback-restart", "audio-reconfig")

    def __init__(self, path):
        self.path = path
        self.sock = None
        self.buf = b""
        self.n = 0
        self.restarted = False

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.buf = b""

    def _lines(self):
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if message.get("event") in self.RESTARTS:
                self.restarted = True
            yield message

    def pump(self):
        """Reads what the player said by itself, without waiting."""
        if not self.sock:
            return
        try:
            while select.select([self.sock], [], [], 0)[0]:
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise OSError("closed")
                self.buf += chunk
            for _ in self._lines():
                pass
        except OSError:
            self.close()

    def batch(self, commands):
        """Several commands in one go: [(accepted, data)], in their order."""
        if not commands:
            return []
        try:
            if not self.sock:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(2)
                sock.connect(self.path)
                self.sock = sock
                self.restarted = True
            first = self.n + 1
            out = b""
            for args in commands:
                self.n += 1
                out += (json.dumps({"command": list(args), "request_id": self.n}) + "\n").encode()
            self.sock.sendall(out)
            replies = {}
            while len(replies) < len(commands):
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise OSError("closed")
                self.buf += chunk
                for message in self._lines():
                    rid = message.get("request_id")
                    if isinstance(rid, int) and rid >= first:
                        replies[rid] = (message.get("error") == "success", message.get("data"))
            return [replies[first + i] for i in range(len(commands))]
        except (OSError, ValueError, KeyError):
            self.close()
            return [(False, None)] * len(commands)

    def command(self, *args):
        return self.batch([args])[0]


class Effects:
    """The effect chain on the player, gliding to what the game asks for.

    The game writes its values a few times a second at most and leaves the
    smoothing to its companion: each value moves a part of the way at every
    tick() (about 25 a second), and only what changed is sent, in one go.
    """

    # value name -> (filter, command, format)
    PARAMS = {
        "hp": ("highpass@hp", "frequency", "{:.0f}"),
        "lp": ("lowpass@lp", "frequency", "{:.0f}"),
        "pkf": ("equalizer@pk", "frequency", "{:.0f}"),
        "pkdb": ("equalizer@pk", "gain", "{:.2f}"),
        "bass": ("bass@bs", "gain", "{:.1f}"),
        "treble": ("treble@tr", "gain", "{:.1f}"),
        "g1": ("volume@g1", "volume", "{:.3f}"),
        "g2": ("volume@g2", "volume", "{:.3f}"),
        "slev": ("stereotools@st", "slev", "{:.2f}"),
        "pan": ("stereotools@st", "balance_out", "{:.2f}"),
        "gain": ("volume@vol", "volume", "{:.3f}"),
    }
    DELAYS = (("t1", "adelay@d1", "g1"), ("t2", "adelay@d2", "g2"))
    PITCHES = ("hp", "lp", "pkf")  # moved by ratio, as one hears them
    GLIDE = 0.15  # seconds to cover about two thirds of a change
    HUSH = 0.04  # the same towards silence: a menu, the game paused
    PRESENT_EVERY = 1.0

    def __init__(self, mpv):
        self.mpv = mpv
        self.on = False
        self.target = None
        self.now = None
        self.built = None
        self.sent = {}
        self.delays = None
        self.ticked = 0.0
        self.checked = 0.0

    def parse(self, line):
        parts = line.split()
        if len(parts) < 12 or parts[0] != "P":
            return None
        try:
            v = [float(x) for x in parts[1:]]
        except ValueError:
            return None
        v += [0.0] * (13 - len(v))
        hp, lp, pkf, pkdb, gain, t1, g1, t2, g2, pan, mono, bass, treble = v[:13]
        return {
            "hp": min(max(hp, 10), 2000),
            "lp": min(max(lp, 200), 20000),
            "pkf": min(max(pkf, 20), 16000),
            "pkdb": min(max(pkdb, -24), 24),
            "gain": min(max(gain, 0), 2),
            "t1": min(max(t1, 1), MAX_DELAY),
            "g1": min(max(g1, 0), 0.8) if t1 >= 1 else 0.0,
            "t2": min(max(t2, 1), MAX_DELAY),
            "g2": min(max(g2, 0), 0.8) if t2 >= 1 else 0.0,
            "pan": min(max(pan, -1), 1) + 0.0,
            "slev": max(0.02, 1 - min(max(mono, 0), 1)),
            "bass": min(max(bass, -24), 24),
            "treble": min(max(treble, -24), 24),
        }

    def present(self):
        ok, filters = self.mpv.command("get_property", "af")
        return bool(ok and any(f.get("label") == LABEL for f in filters or []))

    def build(self, values):
        ok = self.mpv.batch(
            [
                ("af", "remove", "@" + LABEL),
                ("af", "add", f"@{LABEL}:lavfi=[{graph(values)}]"),
            ]
        )[1][0]
        self.on = ok
        self.built = dict(values) if ok else None
        self._as_built()
        return ok

    def _as_built(self):
        """The player's filters are at the values the chain was built with."""
        self.sent = {}
        self.delays = None
        if self.built:
            self.sent = {key: form.format(self.built[key]) for key, (_, _, form) in self.PARAMS.items()}
            self.delays = {key: self.built[key] for key, _, _ in self.DELAYS}

    def _glide(self, dt):
        target, now = self.target, self.now
        hush = target["gain"] <= 0
        part = 1 - math.exp(-dt / (self.HUSH if hush else self.GLIDE))
        for key in self.PARAMS:
            if key in self.PITCHES:
                now[key] *= (target[key] / now[key]) ** part
            else:
                now[key] += (target[key] - now[key]) * part
            if abs(target[key] - now[key]) <= 0.002 * max(abs(target[key]), 0.05):
                now[key] = target[key]

    def tick(self, values=None):
        """One step towards the game's last values (or these new ones)."""
        if values:
            self.target = values
        if not self.target:
            return False
        clock = time.monotonic()
        dt = min(max(clock - self.ticked, 0.0), 0.25)
        self.ticked = clock
        self.mpv.pump()
        if not self.on or clock - self.checked >= self.PRESENT_EVERY:
            self.checked = clock
            if not self.present():
                self.now = dict(self.target)
                if not self.build(self.target):
                    return False
                self.mpv.pump()
                self.mpv.restarted = False
        if self.mpv.restarted:
            self.mpv.restarted = False
            self._as_built()
        if self.now is None:
            self.now = dict(self.target)
        else:
            self._glide(dt)
        commands, marks = [], []
        for key, (target, command, form) in self.PARAMS.items():
            text = form.format(self.now[key])
            if self.sent.get(key) != text:
                commands.append(("af-command", LABEL, command, text, target))
                marks.append((self.sent, key, text))
        # The echo taps' delays, only for a change one can hear. Changed in
        # place; a player that refuses (between two songs) is asked again at
        # the next step, the chain is never rebuilt for it.
        for key, target, level in self.DELAYS:
            want, was = self.target[key], (self.delays or {}).get(key, 0)
            # (a silent tap's delay is left where it is)
            if self.target[level] > 0 and abs(want - was) > max(2, 0.15 * was):
                commands.append(("af-command", LABEL, "delays", f"{want:.0f}", target))
                marks.append((self.delays, key, want))
        for (ok, _), (store, key, value) in zip(self.mpv.batch(commands), marks):
            if ok and store is not None:
                store[key] = value
        return True

    def remove(self):
        if self.on or self.present():
            self.mpv.command("af", "remove", "@" + LABEL)
        self.on = False
        self.target = None
        self.now = None
        self.built = None
        self.sent = {}
        self.delays = None


# ---------------------------------------------------------------- main


def game_of(value):
    parts = (value or "").split("\t")
    if len(parts) != 3 or not parts[0].isdigit():
        return None
    start = int(parts[1]) if parts[1].isdigit() else int(time.time())
    return {"steam": parts[0], "start": start, "name": parts[2]}


def control(binary, command):
    what = {"toggle": "toggle", "next": "next", "prev": "previous", "pause": "pause", "resume": "play"}.get(command)
    if not what:
        return
    log("game:", command)
    # Not waited for: the effects go on gliding meanwhile.
    try:
        subprocess.Popen(
            [binary, "control", what],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        log("the player couldn't be told:", error)


def main():
    args = sys.argv[1:]
    opts = {
        "--ytmusic": "nixbook-ytmusic",
        "--mpv": os.path.join(runtime_dir(), "nixbook-ytmusic", "mpv.sock"),
        "--base": "",
    }
    flags = set()
    while args:
        a = args.pop(0)
        if a in ("--discord", "--radio", "--once"):
            flags.add(a)
        elif a in opts and args:
            opts[a] = args.pop(0)
        else:
            sys.exit(__doc__)
    discord, radio = "--discord" in flags, "--radio" in flags
    link = Link(opts["--base"] or None)
    games = Games()
    if "--once" in flags:
        host, app = link.streaming() if (opts["--base"] or moonlight_runs()) else (None, None)
        values = link.read(host, app) if host else None
        game = game_of((values or {}).get("G"))
        print(json.dumps({
            "moonlight": moonlight_runs(),
            "host": host[0] if host else None,
            "values": values,
            "discord": games.find(game) if game else None,
        }))
        return
    if not discord and not radio:
        sys.exit(__doc__)
    presence = Presence()
    effects = Effects(Mpv(opts["--mpv"]))
    try:
        while True:
            host, app = (None, None)
            if opts["--base"] or moonlight_runs():
                host, app = link.streaming()
            if not host:
                presence.clear()
                effects.remove()
                time.sleep(IDLE)
                continue
            log("following", host[0])
            checked = time.monotonic()
            said = None
            last_cmd = None
            misses = 0
            active = False
            off_since = None
            next_read = 0.0
            while True:
                clock = time.monotonic()
                if clock >= next_read:
                    values = link.read(host, app)
                    if values is None:
                        misses += 1
                        if misses >= 5:
                            break
                        next_read = time.monotonic() + 1
                        continue
                    misses = 0
                    if discord:
                        game = game_of(values.get("G"))
                        app_id = games.find(game) if game else None
                        if app_id:
                            shown = presence.show(app_id, game["start"])
                            now = (game["steam"], shown)
                            if now != said:
                                log(game["name"] or game["steam"], "shown on Discord" if shown else ": Discord isn't there to show it")
                        else:
                            presence.clear()
                            now = (game["steam"], None) if game else None
                            if game and now != said:
                                log(game["name"] or game["steam"], "isn't a game Discord knows")
                        said = now
                    if radio:
                        was = active
                        active = values.get("A", "").strip() == "1"
                        if active != was:
                            log("Music station", "on" if active else "off")
                            off_since = None if active else time.monotonic()
                        fx = effects.parse(values.get("F", ""))
                        if fx and (active or off_since is not None):
                            effects.tick(fx)
                        # cmd.txt keeps the game's last order, from one
                        # session to the next: the one there when the
                        # following starts, or when a game starts (no line
                        # before it), is an old one. Run, it started the
                        # player with the game instead of with the station.
                        cmd = values.get("C", "")
                        if not cmd:
                            last_cmd = None
                        elif last_cmd is None:
                            last_cmd = cmd
                        elif cmd != last_cmd:
                            last_cmd = cmd
                            parts = cmd.split("\t")
                            if len(parts) >= 2:
                                control(opts["--ytmusic"], parts[1].strip())
                    if time.monotonic() - checked >= IDLE:
                        checked = time.monotonic()
                        if not opts["--base"] and (not moonlight_runs() or link.streaming()[0] != host):
                            break
                    # The game writes its values 6 times a second at most
                    # while the station plays; each second otherwise with the
                    # radio, else at the activity's pace.
                    next_read = time.monotonic() + (READ if radio and active else 1.0 if radio else 10)
                # A station off for a moment keeps its chain: taking it out
                # and putting it back are two gaps in the sound.
                if off_since is not None and time.monotonic() - off_since >= OFF_GRACE:
                    off_since = None
                    effects.remove()
                if radio and (active or off_since is not None):
                    # Between two readings the effects glide to the last one.
                    time.sleep(STEP)
                    effects.tick()
                    continue
                time.sleep(max(0.05, min(next_read - time.monotonic(), 10)))
            log("no longer following", host[0])
            presence.clear()
            effects.remove()
    except KeyboardInterrupt:
        pass
    finally:
        presence.clear()
        effects.remove()


if __name__ == "__main__":
    main()
