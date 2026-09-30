#!/usr/bin/env python3
"""Recolour a running YouTube Music (pear-desktop) without reloading it.

Usage: youtube-music-live.py CSS_FILE   swap the live copy for CSS_FILE's content
       youtube-music-live.py --remove   drop the live copy

pear-desktop only reads its CSS themes (options.themes) when a page loads, so
a new palette would need a restart. Its Electron build keeps Node's
`--inspect` support (the EnableNodeCliInspectArguments fuse), so SIGUSR1 opens
the main process's inspector on 127.0.0.1:9229; through it the CSS is
inserted into its windows (webContents.insertCSS, the copy inserted last time
removed) and the inspector is closed again straight away. The copy pear
injected at start stays underneath; the rules are `!important`, and the later
insert wins. A page (re)load drops the live copy and pear reinjects the file,
which by then holds the same colours.

While the inspector is open (about a second) any local process could run code
in YouTube Music. Nothing is done when another process already listens on the
port (it can't be told apart from ours) or when YouTube Music doesn't handle
SIGUSR1 yet (the signal would kill it), nor in its first seconds: it's
loading the theme file itself, and its inspector isn't ready to answer.
"""
import json
import os
import signal
import socket
import sys
import time
import urllib.request

PORT = 9229
BINARY = "youtube-music"
MIN_AGE = 15  # seconds

# Runs in YouTube Music's main process. `require` comes from the inspector's
# command-line API, gone after the first `await`: taken as an argument. The
# inspector is closed once this connection has gone (close() waits for it).
EXPRESSION = """((req, css) => {
  const insp = req('inspector');
  setTimeout(() => insp.close(), 200);
  const { app, BrowserWindow } = req('electron');
  if (!process.execPath.endsWith('/%s')) return 'not YouTube Music: ' + process.execPath;
  const keys = globalThis.__nixbookShellCss ??= new Map();
  return (async () => {
    for (const win of BrowserWindow.getAllWindows()) {
      const wc = win.webContents;
      const old = keys.get(wc.id);
      keys.delete(wc.id);
      if (old) await wc.removeInsertedCSS(old).catch(() => {});
      if (css !== null) keys.set(wc.id, await wc.insertCSS(css));
    }
    return 'ok ' + app.getName();
  })();
})(require, %s)"""


def main_processes():
    """YouTube Music's main processes: the binary without Chromium's --type=."""
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        if os.path.basename(argv[0]).decode(errors="replace") == BINARY and not any(
            a.startswith(b"--type=") for a in argv[1:]
        ):
            yield int(pid)


def catches_sigusr1(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("SigCgt:"):
                    return bool(int(line.split()[1], 16) & (1 << (signal.SIGUSR1 - 1)))
    except OSError:
        pass
    return False


def age(pid):
    """Seconds since PID started."""
    with open(f"/proc/{pid}/stat") as f:
        # Field 22, counted after the command name (which may hold spaces).
        start = int(f.read().rsplit(")", 1)[1].split()[19])
    with open("/proc/uptime") as f:
        uptime = float(f.read().split()[0])
    return uptime - start / os.sysconf("SC_CLK_TCK")


def port_in_use():
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", PORT)) == 0


def debugger_url(timeout=3.0):
    deadline = time.monotonic() + timeout
    while True:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list", timeout=0.5) as r:
                return json.load(r)[0]["webSocketDebuggerUrl"]
        except Exception:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.1)


def recolour(pid, css):
    if age(pid) < MIN_AGE or not catches_sigusr1(pid):
        return f"{pid}: starting (it loads the theme file itself), skipped"
    if port_in_use():
        return f"port {PORT} is already taken, skipped"
    import websocket  # only once there is an app to talk to

    os.kill(pid, signal.SIGUSR1)
    ws = websocket.create_connection(debugger_url(), timeout=5, suppress_origin=True)
    try:
        ws.send(json.dumps({
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": EXPRESSION % (BINARY, json.dumps(css)),
                "includeCommandLineAPI": True,
                "awaitPromise": True,
                "returnByValue": True,
            },
        }))
        reply = json.loads(ws.recv())
    finally:
        ws.close()
    result = reply.get("result", {})
    if "exceptionDetails" in result:
        return f"{pid}: {result['exceptionDetails'].get('exception', {}).get('description', 'error')}"
    return f"{pid}: {result.get('result', {}).get('value')}"


def main(args):
    if args == ["--remove"]:
        css = None
    elif len(args) == 1 and not args[0].startswith("-"):
        with open(args[0]) as f:
            css = f.read()
    else:
        sys.exit(__doc__)
    status = 0
    for pid in main_processes():
        try:
            print(recolour(pid, css))
        except Exception as e:
            print(f"{pid}: {e}", file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
