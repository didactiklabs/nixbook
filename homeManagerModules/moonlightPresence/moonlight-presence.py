"""Show the game streamed with Moonlight as this desktop's Discord activity.

Discord only sees local processes, so a game running on another machine and
watched through Moonlight shows nothing. While Moonlight runs here, this asks
each host (over ssh) which Steam game it is running, finds that game in
Discord's public list of known games, and announces it on Discord's local
rich-presence socket (the Discord client's, or Vesktop's arRPC).

    moonlight-presence HOST...     the loop (a user service)
    moonlight-presence --once HOST...   one look, printed, nothing announced
"""

import json
import os
import select
import socket
import struct
import subprocess
import sys
import time
import urllib.request

INTERVAL = 15
LIST_URL = "https://discord.com/api/v9/applications/detectable"
LIST_MAX_AGE = 7 * 86400
LIST_RETRY = 3600

# Printed by the host: "<Steam app id>\t<start, epoch seconds>\t<name>" of the
# game Steam is running (Steam starts every game through its reaper), or
# nothing. A non-Steam shortcut has no manifest, hence no name.
REMOTE = r"""
id=
for pid in $(pgrep -f 'reaper SteamLaunch AppId='); do
  id=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | sed -n 's/^AppId=\([0-9]*\)$/\1/p' | head -n 1)
  [ -z "$id" ] || break
done
[ -n "$id" ] || exit 0
name=
for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
  [ -f "$root/steamapps/libraryfolders.vdf" ] || continue
  while IFS= read -r dir; do
    f="$dir/steamapps/appmanifest_$id.acf"
    [ -f "$f" ] || continue
    name=$(sed -n 's/^[[:space:]]*"name"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$f" | head -n 1)
    break 2
  done <<EOF
$(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$root/steamapps/libraryfolders.vdf")
EOF
done
printf '%s\t%s\t%s\n' "$id" "$(stat -c %Y "/proc/$pid")" "$name"
"""


def log(*words):
    print(*words, file=sys.stderr, flush=True)


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "moonlight-presence")


def moonlight_runs():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm") as f:
                if f.read().strip() == "moonlight":
                    return True
        except OSError:
            pass
    return False


def game_on(host):
    """The game HOST runs: {steam, start, name}, or None."""
    control = os.path.join(runtime_dir(), "moonlight-presence-%C")
    try:
        out = subprocess.run(
            [
                "ssh",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                "-o", "ControlMaster=auto",
                "-o", f"ControlPath={control}",
                "-o", "ControlPersist=120",
                host,
                "sh",
            ],
            input=REMOTE,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    line = out.stdout.strip().split("\n")[-1] if out.stdout.strip() else ""
    parts = line.split("\t")
    if len(parts) != 3 or not parts[0].isdigit():
        return None
    start = int(parts[1]) if parts[1].isdigit() else int(time.time())
    return {"steam": parts[0], "start": start, "name": parts[2]}


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


def look(hosts):
    for host in hosts:
        game = game_on(host)
        if game:
            return host, game
    return None, None


def main():
    args = sys.argv[1:]
    once = "--once" in args
    hosts = [a for a in args if not a.startswith("-")]
    if not hosts:
        sys.exit(__doc__)
    games = Games()
    if once:
        host, game = look(hosts)
        print(json.dumps({
            "moonlight": moonlight_runs(),
            "host": host,
            "game": game,
            "discord": games.find(game) if game else None,
        }))
        return
    presence = Presence()
    said = None
    while True:
        host, game = look(hosts) if moonlight_runs() else (None, None)
        app_id = games.find(game) if game else None
        if app_id:
            shown = presence.show(app_id, game["start"])
            now = (game["steam"], shown)
            if now != said:
                log(
                    f"{game['name'] or game['steam']} on {host}:",
                    "shown on Discord" if shown else "Discord isn't there to show it",
                )
        else:
            presence.clear()
            now = (game["steam"], None) if game else None
            if game and now != said:
                log(f"{game['name'] or game['steam']} on {host}: not a game Discord knows")
        said = now
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
