"""Moonlight companion, the game machine's side.

What a machine streaming its games (Sunshine) tells the machine watching them
(Moonlight), with no service of its own on the network: Sunshine serves each
app's cover picture to paired clients on its own port, so this keeps a copy of
the Desktop app's cover with a few text lines after the picture's end (image
readers stop at the end of a PNG; Sunshine sends the file as it is):

  - which Steam game runs, for the client's Discord activity;
  - the files the Cyberpunk 2077 mod Music Radio (Nexus 38098) writes for its
    companion program, which here is the client: the acoustics of the moment
    and the station's commands.

    moonlight-companion --out FILE --base PNG [--radio DATA_DIR]

FILE = PNG, then "\\nMLC1\\n" and one line per value:
    G <Steam app id>\\t<start, epoch s>\\t<name>     (nothing after G: no game)
    F <fx.txt>     A <active.txt>     C <cmd.txt>
Nothing is read outside /proc, Steam's manifests and those three files.
"""

import os
import re
import sys
import time

MARK = b"\nMLC1\n"
FAST = 0.05
SLOW = 1.0
GAME_EVERY = 5
FILES = (("F", "fx.txt"), ("A", "active.txt"), ("C", "cmd.txt"))


def log(*words):
    print(*words, file=sys.stderr, flush=True)


def steam_game():
    """The game Steam runs (it starts each through its reaper): "id\\tstart\\tname" or ""."""
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = f.read(4096).split(b"\0")
            if len(args) < 3 or not args[0].endswith(b"reaper") or args[1] != b"SteamLaunch":
                continue
            app = next((a[6:].decode() for a in args if a.startswith(b"AppId=")), "")
            if not app.isdigit():
                continue
            start = int(os.stat(f"/proc/{entry}").st_mtime)
        except (OSError, ValueError):
            continue
        return f"{app}\t{start}\t{steam_name(app)}"
    return ""


def steam_name(app):
    home = os.path.expanduser("~")
    for root in (home + "/.local/share/Steam", home + "/.steam/steam"):
        try:
            with open(root + "/steamapps/libraryfolders.vdf", encoding="utf-8", errors="replace") as f:
                folders = re.findall(r'"path"\s*"([^"]*)"', f.read())
        except OSError:
            continue
        for folder in folders:
            try:
                path = f"{folder}/steamapps/appmanifest_{app}.acf"
                with open(path, encoding="utf-8", errors="replace") as f:
                    found = re.search(r'"name"\s*"([^"]*)"', f.read())
                if found:
                    return found.group(1).replace("\t", " ")
            except OSError:
                pass
    return ""


def read_small(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read(2000).split("\n")[0].rstrip("\r")
    except OSError:
        return ""


def publish(out, base, values):
    text = "".join(f"{kind} {values.get(kind, '')}\n" for kind in ("G", "F", "A", "C"))
    tmp = out + ".part"
    with open(tmp, "wb") as f:
        f.write(base + MARK + text.encode())
    os.replace(tmp, out)


def main():
    args = sys.argv[1:]
    opts = {"--out": "", "--base": "", "--radio": ""}
    while args:
        key = args.pop(0)
        if key not in opts or not args:
            sys.exit(__doc__)
        opts[key] = args.pop(0)
    if not opts["--out"] or not opts["--base"]:
        sys.exit(__doc__)
    with open(opts["--base"], "rb") as f:
        base = f.read()
    out, radio = opts["--out"], opts["--radio"]
    os.makedirs(os.path.dirname(out), mode=0o755, exist_ok=True)
    values = {}
    stamps = {}
    looked = -GAME_EVERY
    written = None
    said_playing = False
    log(f"keeping {out}" + (f", Music Radio in {radio}" if radio else ""))
    while True:
        now = time.monotonic()
        if now - looked >= GAME_EVERY:
            looked = now
            values["G"] = steam_game()
        # The mod's files only move while a game runs.
        playing = bool(values.get("G"))
        if radio and playing:
            for kind, name in FILES:
                path = os.path.join(radio, name)
                try:
                    st = os.stat(path)
                    stamp = (st.st_mtime_ns, st.st_size)
                except OSError:
                    stamp = None
                # Empty: the game is rewriting it (active.txt every 2 s).
                # Read as it was, it said "station off" for a moment and the
                # client took its effects out and put them back.
                if stamp and stamp[1] == 0:
                    continue
                if stamp != stamps.get(name, 0):
                    stamps[name] = stamp
                    values[kind] = read_small(path) if stamp else ""
            # The mod only lets a club's room play the music while its
            # companion says something plays; the client can't say (the link
            # goes one way), so it is taken as playing.
            if not said_playing:
                try:
                    with open(os.path.join(radio, "now.txt"), "w", encoding="utf-8") as f:
                        f.write("1\tMusic\t")
                    said_playing = True
                except OSError:
                    pass
        elif "A" in values:
            said_playing = False
            for kind, _ in FILES:
                values.pop(kind, None)
            stamps.clear()
        state = tuple(sorted(values.items()))
        if state != written:
            try:
                publish(out, base, values)
                written = state
            except OSError as error:
                log("can't write", out, error)
        time.sleep(FAST if radio and playing else SLOW)


if __name__ == "__main__":
    main()
