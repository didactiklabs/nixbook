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


def graph(t1, t2):
    return (
        "highpass@hp=f=20:p=2,lowpass@lp=f=20000:p=2,"
        "equalizer@pk=f=1000:t=q:w=1:g=0,bass@bs=g=0,treble@tr=g=0,"
        "asplit=3[d][a][b];"
        f"[a]adelay@d1=delays={t1:.0f}:all=1,volume@g1=volume=0[x];"
        f"[b]adelay@d2=delays={t2:.0f}:all=1,volume@g2=volume=0[y];"
        "[d][x][y]amix=inputs=3:normalize=0,"
        "stereotools@st=slev=1:balance_out=0,volume@vol=volume=1,"
        "alimiter=limit=0.95"
    )


class Mpv:
    """The panel's mpv, through its IPC socket (a connection per request)."""

    def __init__(self, path):
        self.path = path

    def command(self, *args):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.settimeout(2)
                s.connect(self.path)
                s.sendall((json.dumps({"command": list(args), "request_id": 7}) + "\n").encode())
                buf = b""
                while True:
                    chunk = s.recv(65536)
                    if not chunk:
                        return False, None
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        try:
                            reply = json.loads(line)
                        except ValueError:
                            continue
                        if reply.get("request_id") == 7:
                            return reply.get("error") == "success", reply.get("data")
        except OSError:
            return False, None


class Effects:
    """The effect chain on the player, following the game's fx lines."""

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

    def __init__(self, mpv):
        self.mpv = mpv
        self.on = False
        self.sent = {}
        self.delays = None
        self.want = None
        self.failed = set()

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
            "pan": min(max(pan, -1), 1),
            "slev": max(0.02, 1 - min(max(mono, 0), 1)),
            "bass": min(max(bass, -24), 24),
            "treble": min(max(treble, -24), 24),
        }

    def present(self):
        ok, filters = self.mpv.command("get_property", "af")
        return bool(ok and any(f.get("label") == LABEL for f in filters or []))

    def build(self, values):
        self.mpv.command("af", "remove", "@" + LABEL)
        ok, _ = self.mpv.command(
            "af", "add", f"@{LABEL}:lavfi=[{graph(values['t1'], values['t2'])}]"
        )
        self.on = ok
        self.sent = {}
        self.delays = (values["t1"], values["t2"]) if ok else None
        return ok

    def apply(self, values):
        self.want = values
        if not self.on or not self.present():
            if not self.build(values):
                return False
        # The echo taps' delays: changed in place when the player takes it,
        # else the chain is rebuilt, and only for a change one can hear.
        old = self.delays or (0, 0)
        if any(abs(new - was) > max(2, 0.15 * was) for new, was in zip((values["t1"], values["t2"]), old)):
            moved = all(
                self.mpv.command("af-command", LABEL, "delays", f"{values[t]:.0f}", name)[0]
                for t, name in (("t1", "adelay@d1"), ("t2", "adelay@d2"))
            )
            if moved:
                self.delays = (values["t1"], values["t2"])
            else:
                log("delays not changed in place: chain rebuilt")
                if not self.build(values):
                    return False
        for key, (target, command, form) in self.PARAMS.items():
            text = form.format(values[key])
            if self.sent.get(key) != text:
                ok, _ = self.mpv.command("af-command", LABEL, command, text, target)
                if ok:
                    self.sent[key] = text
                elif key not in self.failed:
                    self.failed.add(key)
                    log(f"the player refused {target} {command} {text}")
        return True

    def remove(self):
        if self.on or self.present():
            self.mpv.command("af", "remove", "@" + LABEL)
        self.on = False
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
    try:
        subprocess.run([binary, "control", what], capture_output=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as error:
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
            while True:
                values = link.read(host, app)
                if values is None:
                    misses += 1
                    if misses >= 5:
                        break
                    time.sleep(1)
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
                    fx = effects.parse(values.get("F", ""))
                    if active and fx:
                        effects.apply(fx)
                    elif not active:
                        effects.remove()
                    # cmd.txt keeps the game's last order: one seen when the
                    # following starts is an old one.
                    cmd = values.get("C", "")
                    if last_cmd is None:
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
                # Often while the station plays (the acoustics follow V), each
                # second otherwise with the radio, else at the activity's pace.
                time.sleep(0.1 if radio and active else 1.0 if radio else 10)
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
