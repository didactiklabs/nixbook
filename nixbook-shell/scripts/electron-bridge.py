"""nixbook-electron-app: starts an Electron app (Vesktop, Slack, YouTube
Music, Actual…) for nixbook's desktop agents, so they read and use it
through the page itself, without the mouse or keyboard, like Zen's tabs
(nixbook-desktop-mcp's page_* tools; Discord also its `discord` tool).

  nixbook-electron-app [--page-js FILE] [--adapters DIR] [--no-a11y] [--marker PATH…] APP -- BINARY [ARGS…]
  nixbook-electron-app --socket APP          (prints the app's socket path)
  nixbook-electron-app watch [--once]        (the watcher, a user service)
  nixbook-electron-app restart APP           (an unbridged APP, again through the bridge)
  nixbook-electron-app status

The app runs as this launcher's child with Chromium's DevTools protocol on
a private pipe (--remote-debugging-pipe: file descriptors 3 and 4, no TCP
port, nothing another process can connect to) and its accessibility tree on
(--force-renderer-accessibility, as nixbook's other Electron apps). The
launcher keeps the pipe to itself and serves a Unix socket only this user
can reach, $XDG_RUNTIME_DIR/nixbook-electron/APP.sock (directory 0700,
socket 0600, the peer's uid checked): one JSON request per line ({cmd, …}),
one answer per line ({ok, result} or {ok: false, error}).

What a client can do is a fixed list of operations (OPS), each a fixed
piece of JavaScript: nothing sent to the socket is ever run as code. The
page operations run nixbook's page code (zen/page.js, shared with Zen's
extension) in an isolated world of their own: the app's scripts see
neither the code nor the element references it keeps. Typing and keys go
through DevTools' Input domain to the page (Input.insertText, which rich
editors such as Discord's accept), never through the compositor: the app
may be in the background, on another workspace, the user keeps working.
An app with an adapter (adapters/APP.js: discord) also has its own
operations, run in the page's main world through the app's own client
code (Discord: Vencord's webpack modules), which never return a token,
a cookie or a header (and the answers are scrubbed for tokens anyway).
Password fields are refused; password managers are never bridged (the app
starts without the bridge); sends are rate-limited and written to the audit
log ($XDG_STATE_HOME/nixbook-shell/electron-bridge.log, lengths only).

Started while the app already runs (Electron apps are single-instance):
when that one has the bridge, this one just starts the app (it hands over
to it); when it doesn't, the app hands over too and there is no bridge
until it is quit and started again through this launcher.
NIXBOOK_ELECTRON_BRIDGE=0 starts the app without the bridge.

The app relaunching itself (app.relaunch(), an update applied): its process
ends and a new one, unbridged, starts. The launcher watches RELAUNCH_WATCH
seconds after its app quits for a new instance (this user's, its command
line or executable under one of the app's store paths, --marker, given by
Nix; not under a launcher; started since): it stops it (SIGTERM, SIGKILL
after 5 s) and starts the app again through the bridge, once per
RESTART_GAP (twice in a row: it gives up and says so).

`watch` (the nixbook-electron-watch user service) checks every POLL seconds,
from /proc alone, the apps of ~/.config/nixbook-shell/electron-bridge.json
(written by Nix) running without their socket: started less than YOUNG
seconds ago (an autostart entry, another launcher) and not in a call (a
PipeWire recording stream of its own, pactl): restarted through the bridge
at once; otherwise never stopped: one notification ("Desktop agent", "Restart with
bridge", which restarts it), again when an agent asked for it
(APP.ask, from desktop-mcp; at most every 10 minutes). It writes what runs
unbridged to $XDG_RUNTIME_DIR/nixbook-electron/unbridged.json for desktop-mcp.
"""

import base64
import contextlib
import shutil
import itertools
import json
import os
import re
import signal
import socket
import stat
import struct
import subprocess
import sys
import threading
import time

TIMEOUT = 20.0
MAX_LINE = 1024 * 1024
APP_NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
# Never bridged, whatever the Nix list says: their pages hold the vault.
PASSWORD_APPS = re.compile(r"keepass|bitwarden|vaultwarden|1password|enpass|proton-?pass|lastpass|dashlane|keeper|"
                           r"nordpass|roboform|passbolt|seahorse|kwallet|gnome-keyring|authenticator|authy|"
                           r"(^|/)(bw|rbw|pass|gopass)$", re.I)
CONTENT_MAX = 2000
SENDS_PER_MINUTE = 10
ACTS_PER_MINUTE = 60
# Discord/Slack tokens and bearer-looking strings, scrubbed from every answer.
TOKEN_LIKE = re.compile(r"\b(mfa\.[\w-]{20,}|[\w-]{23,28}\.[\w-]{6,7}\.[\w-]{25,}|xox[abprs]-[\w-]{10,}|"
                        r"Bearer\s+[\w.~+/-]{20,}=*)")
SECRET_KEYS = re.compile(r"token|authorization|cookie|password|secret|session", re.I)
KEYS = {
    "enter": ("Enter", "Enter", 13, "\r"), "return": ("Enter", "Enter", 13, "\r"),
    "tab": ("Tab", "Tab", 9, "\t"), "escape": ("Escape", "Escape", 27, ""), "esc": ("Escape", "Escape", 27, ""),
    "backspace": ("Backspace", "Backspace", 8, ""), "delete": ("Delete", "Delete", 46, ""),
    "space": (" ", "Space", 32, " "), "home": ("Home", "Home", 36, ""), "end": ("End", "End", 35, ""),
    "pageup": ("PageUp", "PageUp", 33, ""), "pagedown": ("PageDown", "PageDown", 34, ""),
    "arrowup": ("ArrowUp", "ArrowUp", 38, ""), "up": ("ArrowUp", "ArrowUp", 38, ""),
    "arrowdown": ("ArrowDown", "ArrowDown", 40, ""), "down": ("ArrowDown", "ArrowDown", 40, ""),
    "arrowleft": ("ArrowLeft", "ArrowLeft", 37, ""), "left": ("ArrowLeft", "ArrowLeft", 37, ""),
    "arrowright": ("ArrowRight", "ArrowRight", 39, ""), "right": ("ArrowRight", "ArrowRight", 39, ""),
}
MODIFIERS = {"alt": 1, "ctrl": 2, "control": 2, "meta": 4, "super": 4, "shift": 8}
HERE = os.path.dirname(os.path.abspath(__file__))


def runtime_base():
    return os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"


def socket_path(app):
    return os.path.join(runtime_base(), "nixbook-electron", f"{app}.sock")


def audit_path():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "nixbook-shell", "electron-bridge.log")


def log(msg):
    print(f"nixbook-electron-app: {msg}", file=sys.stderr, flush=True)


def audit(app, op, outcome, **fields):
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "app": app, "op": op, **fields, "outcome": outcome}
    path = audit_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        log(f"audit log: {e}")


def scrub(value, keys=False):
    """No token, cookie or header in an answer, whatever the page returned
    (keys: nor any field named after a secret)."""
    if isinstance(value, str):
        return TOKEN_LIKE.sub("[hidden]", value)
    if isinstance(value, list):
        return [scrub(v, keys) for v in value]
    if isinstance(value, dict):
        return {k: scrub(v, keys) for k, v in value.items() if not (keys and SECRET_KEYS.search(str(k)))}
    return value


class Refused(Exception):
    pass


# ── The DevTools pipe ──

class Cdp:
    """Chromium's DevTools protocol over --remote-debugging-pipe: one JSON
    message per \\0-terminated frame, ours on fd 3, the browser's on fd 4."""

    def __init__(self, rfd, wfd):
        self.rfd, self.wfd = rfd, wfd
        self.ids = itertools.count(1)
        self.pending = {}
        self.lock = threading.Lock()
        self.write_lock = threading.Lock()
        self.closed = threading.Event()
        self.on_event = None
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        buf = b""
        while True:
            try:
                chunk = os.read(self.rfd, 1 << 16)
            except OSError:
                chunk = b""
            if not chunk:
                break
            buf += chunk
            while b"\0" in buf:
                frame, _, buf = buf.partition(b"\0")
                try:
                    msg = json.loads(frame)
                except ValueError:
                    continue
                if "id" in msg:
                    with self.lock:
                        slot = self.pending.get(msg["id"])
                    if slot:
                        slot["reply"] = msg
                        slot["event"].set()
                elif self.on_event:
                    try:
                        self.on_event(msg)
                    except Exception as e:  # an event never stops the reader
                        log(f"event: {e!r}")
        self.closed.set()
        with self.lock:
            for slot in self.pending.values():
                slot["event"].set()

    def call(self, method, params=None, session=None, timeout=TIMEOUT):
        if self.closed.is_set():
            raise Refused("the app is gone")
        mid = next(self.ids)
        slot = {"event": threading.Event()}
        with self.lock:
            self.pending[mid] = slot
        msg = {"id": mid, "method": method, "params": params or {}}
        if session:
            msg["sessionId"] = session
        try:
            with self.write_lock:
                os.write(self.wfd, json.dumps(msg).encode() + b"\0")
            if not slot["event"].wait(timeout):
                raise Refused(f"the app didn't answer within {int(timeout)} s")
        except OSError:
            raise Refused("the app is gone")
        finally:
            with self.lock:
                self.pending.pop(mid, None)
        reply = slot.get("reply")
        if reply is None:
            raise Refused("the app is gone")
        if "error" in reply:
            raise CdpError(str((reply["error"] or {}).get("message") or reply["error"]))
        return reply.get("result") or {}


class CdpError(Exception):
    pass


# ── The app, through its pages ──

class Bridge:
    def __init__(self, app, cdp, page_js, adapter_js=None):
        self.app, self.cdp = app, cdp
        self.page_js, self.adapter_js = page_js, adapter_js
        self.short = {}  # targetId → its short id ("1", "2"…), stable while it lives
        self.counter = itertools.count(1)
        self.sessions = {}  # targetId → sessionId
        self.worlds = {}  # sessionId → isolated world's executionContextId
        self.lock = threading.RLock()
        self.sends, self.acts = [], []
        cdp.on_event = self.event

    def event(self, msg):
        method, params = msg.get("method"), msg.get("params") or {}
        if method == "Target.detachedFromTarget":
            sid = params.get("sessionId")
            self.worlds.pop(sid, None)
            for t, s in list(self.sessions.items()):
                if s == sid:
                    self.sessions.pop(t, None)
        elif method in ("Runtime.executionContextsCleared", "Page.frameNavigated"):
            self.worlds.pop(msg.get("sessionId"), None)

    def pages(self):
        infos = self.cdp.call("Target.getTargets").get("targetInfos") or []
        out = []
        for t in infos:
            if t.get("type") not in ("page", "webview"):
                continue
            url = str(t.get("url") or "")
            if url.startswith(("devtools:", "chrome-extension:", "chrome:")):
                continue
            tid = t["targetId"]
            if tid not in self.short:
                self.short[tid] = str(next(self.counter))
            out.append({"id": self.short[tid], "targetId": tid, "title": str(t.get("title") or ""), "url": url,
                        "type": t["type"]})
        live = {p["targetId"] for p in out}
        for tid in list(self.short):
            if tid not in live:
                self.short.pop(tid, None)
                self.sessions.pop(tid, None)
        # The main page: the first one on the web (the splash or a settings
        # window comes after it).
        main = next((p for p in out if p["url"].startswith(("http:", "https:"))), out[0] if out else None)
        for p in out:
            p["main"] = p is main
        return out

    def page(self, which):
        pages = self.pages()
        if not pages:
            raise Refused(f"{self.app} has no window open yet")
        if which in (None, ""):
            return next(p for p in pages if p["main"])
        which = str(which)
        for p in pages:
            if which in (p["id"], p["targetId"]):
                return p
        raise Refused(f"no page {which!r} in {self.app} (page_list lists them)")

    def session(self, page):
        tid = page["targetId"]
        sid = self.sessions.get(tid)
        if sid:
            return sid
        sid = self.cdp.call("Target.attachToTarget", {"targetId": tid, "flatten": True})["sessionId"]
        self.sessions[tid] = sid
        return sid

    def world(self, sid, fresh=False):
        if not fresh and sid in self.worlds:
            return self.worlds[sid]
        frame = self.cdp.call("Page.getFrameTree", session=sid)["frameTree"]["frame"]["id"]
        ctx = self.cdp.call("Page.createIsolatedWorld", {"frameId": frame, "worldName": "nixbook"},
                            session=sid)["executionContextId"]
        self.worlds[sid] = ctx
        return ctx

    def evaluate(self, sid, expression, context=None, timeout=TIMEOUT):
        params = {"expression": expression, "returnByValue": True, "awaitPromise": True,
                  "userGesture": True, "timeout": int(timeout * 1000)}
        if context is not None:
            params["contextId"] = context
        r = self.cdp.call("Runtime.evaluate", params, session=sid, timeout=timeout + 2)
        if r.get("exceptionDetails"):
            d = r["exceptionDetails"]
            raise Refused("the page failed: " + str((d.get("exception") or {}).get("description") or d.get("text"))[:300])
        return (r.get("result") or {}).get("value")

    def in_page(self, page, op, o):
        """nixbook's page code (zen/page.js), in the page's isolated world."""
        sid = self.session(page)
        expr = f"{self.page_js}\n;nixbookPage({json.dumps(op)}, {json.dumps(o)})"
        for attempt in (0, 1):
            try:
                r = self.evaluate(sid, expr, self.world(sid, fresh=attempt == 1))
                break
            except CdpError as e:
                # The page navigated: its world is gone, a new one is made.
                if attempt or "context" not in str(e).lower():
                    raise Refused(f"the page can't be read ({e})")
        if not isinstance(r, dict):
            raise Refused("the page gave no answer (still loading?)")
        if r.get("error"):
            raise Refused(str(r["error"]))
        return r

    def described(self, page):
        fresh = self.page(page["id"])
        return {"page": fresh["id"], "title": fresh["title"], "url": fresh["url"]}

    def rate(self, kind, limit):
        now = time.monotonic()
        log_ = self.sends if kind == "send" else self.acts
        log_[:] = [t for t in log_ if now - t < 60]
        if len(log_) >= limit:
            raise Refused(f"refused: more than {limit} {'sends' if kind == 'send' else 'actions'} a minute "
                          f"in {self.app}; wait a little")
        log_.append(now)

    # ── Operations ──

    def op_status(self, req):
        version = self.cdp.call("Browser.getVersion")
        pages = self.pages()
        return {"app": self.app, "running": True, "pid": os.getpid(), "pages": len(pages),
                "product": version.get("product"), "adapter": bool(self.adapter_js)}

    def op_pages(self, req):
        return [{k: p[k] for k in ("id", "title", "url", "main")} for p in self.pages()]

    def op_read(self, req):
        page = self.page(req.get("page"))
        r = self.in_page(page, "read", {
            "text": req.get("text") is not False,
            "chars": max(500, min(60000, int(req.get("chars") or 12000))),
            "max": max(10, min(400, int(req.get("max") or 150))),
            "query": str(req.get("query") or "")[:200],
        })
        r["page"] = page["id"]
        return r

    def op_act(self, req):
        self.rate("act", ACTS_PER_MINUTE)
        page = self.page(req.get("page"))
        action = str(req.get("action") or "")
        value = req.get("value")
        value = "" if value is None else str(value)
        if len(value) > 20000:
            raise Refused("refused: text too long")
        o = {"ref": req.get("ref"), "name": req.get("name"), "action": action, "value": value,
             "append": bool(req.get("append")), "host": action in ("type", "press")}
        sid = self.session(page)
        # Focus as if the window had it, for the time of the action only (a
        # page that thinks it is in front marks messages read).
        focus = action in ("type", "press", "focus")
        if focus:
            self.cdp.call("Emulation.setFocusEmulationEnabled", {"enabled": True}, session=sid)
        try:
            r = self.in_page(page, "act", o)
            if r.get("host") == "insert":
                if value:
                    self.cdp.call("Input.insertText", {"text": value}, session=sid)
                elif not o["append"]:
                    self.key(sid, "Backspace")  # the selected text: emptied
                r = {"done": "type", **self.in_page(page, "state", {"ref": req.get("ref")})}
            elif r.get("host") == "key":
                self.key(sid, r.get("key") or "Enter")
                r = {"done": "press", **self.in_page(page, "state", {"ref": req.get("ref")})}
        finally:
            if focus:
                try:
                    self.cdp.call("Emulation.setFocusEmulationEnabled", {"enabled": False}, session=sid)
                except (Refused, CdpError):
                    pass
        # A click that leads elsewhere: once loaded.
        time.sleep(0.3)
        self.wait_loaded(page, 10)
        return {**r, **self.described(page)}

    def key(self, sid, combo):
        parts = [p for p in re.split(r"\s*\+\s*", str(combo)) if p]
        if not parts or len(parts) > 4:
            raise Refused("a key: Enter, Escape, Tab, a letter, or Ctrl+A, Shift+Enter…")
        mods = 0
        for m in parts[:-1]:
            if m.lower() not in MODIFIERS:
                raise Refused(f"unknown modifier {m!r}")
            mods |= MODIFIERS[m.lower()]
        name = parts[-1]
        if name.lower() in KEYS:
            key, code, vk, txt = KEYS[name.lower()]
        elif len(name) == 1:
            key, txt = name, name
            code = f"Key{name.upper()}" if name.isalpha() else (f"Digit{name}" if name.isdigit() else "")
            vk = ord(name.upper())
        else:
            raise Refused(f"unknown key {name!r}")
        if mods & (1 | 2 | 4):
            txt = ""  # a shortcut types nothing
        down = {"type": "keyDown" if txt else "rawKeyDown", "key": key, "code": code, "modifiers": mods,
                "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk}
        if txt:
            down.update(text=txt, unmodifiedText=txt)
        self.cdp.call("Input.dispatchKeyEvent", down, session=sid)
        self.cdp.call("Input.dispatchKeyEvent", {"type": "keyUp", "key": key, "code": code, "modifiers": mods,
                                                 "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk},
                      session=sid)

    def wait_loaded(self, page, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                if self.in_page(page, "ready", {}).get("state") == "complete":
                    return True
            except Refused:
                pass
            time.sleep(0.2)
        return False

    def op_wait(self, req):
        page = self.page(req.get("page"))
        until = str(req.get("until") or "load")
        want = str(req.get("text") or "")
        end = time.monotonic() + max(0.1, min(30.0, (int(req.get("timeout") or 10000)) / 1000))
        while time.monotonic() < end:
            try:
                if until == "url":
                    ok = want in self.page(page["id"])["url"]
                elif until == "text":
                    ok = bool(self.in_page(page, "has", {"text": want}).get("found"))
                else:
                    ok = self.in_page(page, "ready", {}).get("state") == "complete"
            except Refused:
                ok = False
            if ok:
                return {"ok": True, **self.described(page)}
            time.sleep(0.3)
        return {"ok": False, "page": page["id"]}

    def op_screenshot(self, req):
        page = self.page(req.get("page"))
        sid = self.session(page)
        try:
            r = self.cdp.call("Page.captureScreenshot", {"format": "jpeg", "quality": 80}, session=sid, timeout=12)
        except Refused:
            raise Refused(f"{self.app}'s window drew nothing to capture (minimized or hidden?): page_read reads it "
                          "anyway, or screenshot its window")
        data = str(r.get("data") or "")
        base64.b64decode(data[:64] + "=" * (-len(data[:64]) % 4))  # it is base64
        return {"page": page["id"], "title": page["title"], "url": page["url"], "data": "data:image/jpeg;base64," + data}

    def op_go(self, req):
        page = self.page(req.get("page"))
        sid = self.session(page)
        action = str(req.get("action") or "")
        if action == "reload":
            self.cdp.call("Page.reload", {}, session=sid)
        elif action in ("back", "forward"):
            h = self.cdp.call("Page.getNavigationHistory", session=sid)
            i = int(h.get("currentIndex", 0)) + (-1 if action == "back" else 1)
            entries = h.get("entries") or []
            if not 0 <= i < len(entries):
                raise Refused(f"nothing to go {action} to")
            self.cdp.call("Page.navigateToHistoryEntry", {"entryId": entries[i]["id"]}, session=sid)
        else:
            raise Refused("in an app: back, forward or reload (open, navigate, activate, mute and close are Zen's)")
        time.sleep(0.3)
        self.wait_loaded(page, 15)
        return self.described(page)

    def op_app(self, req):
        """The adapter's own operations (adapters/APP.js), in the page's main world."""
        if not self.adapter_js:
            raise Refused(f"{self.app} has no operations of its own: use the page tools")
        op = str(req.get("op") or "")
        args = req.get("args") if isinstance(req.get("args"), dict) else {}
        sending = op in ("send", "react")
        if op not in ADAPTER_OPS.get(self.app, ()):
            raise Refused(f"no operation {op!r} for {self.app}")
        if sending:
            if op == "send":
                content = args.get("content")
                if not isinstance(content, str) or not content.strip():
                    raise Refused("nothing to send: `content` is empty")
                if len(content) > CONTENT_MAX:
                    raise Refused(f"refused: a message is at most {CONTENT_MAX} characters")
            self.rate("send", SENDS_PER_MINUTE)
        if "limit" in args:
            try:
                args["limit"] = max(1, min(50, int(args["limit"])))
            except (TypeError, ValueError):
                args["limit"] = 20
        page = self.page(req.get("page"))
        sid = self.session(page)
        expr = f"{self.adapter_js}\n;nixbookApp({json.dumps(op)}, {json.dumps(args)})"
        logged = {"channel": str(args.get("channel") or "")[:80]}
        if op == "send":
            logged["chars"] = len(args.get("content") or "")
            logged["reply"] = bool(args.get("reply_to"))
        try:
            r = self.evaluate(sid, expr, timeout=25)
        except (Refused, CdpError) as e:
            if sending:
                audit(self.app, op, f"error: {e}", **logged)
            raise Refused(str(e))
        if not isinstance(r, dict):
            raise Refused(f"{self.app} gave no answer (still loading?)")
        if r.get("error"):
            if sending:
                audit(self.app, op, f"error: {r['error']}", **logged)
            raise Refused(str(r["error"]))
        if sending:
            audit(self.app, op, "ok", **logged, id=str(r.get("id") or ""))
        return r


# The adapters' operations: everything else is refused before any code runs.
ADAPTER_OPS = {"discord": ("status", "current", "guilds", "channels", "dms", "find", "read", "send", "react")}
OPS = {"status": "op_status", "pages": "op_pages", "read": "op_read", "act": "op_act", "wait": "op_wait",
       "screenshot": "op_screenshot", "go": "op_go", "app": "op_app"}


# What can run again after the page's session went away (a reload in
# another process, a crashed renderer): nothing that acts.
RETRYABLE = {"op_status", "op_pages", "op_read", "op_wait", "op_screenshot"}


def handle(bridge, request):
    name = OPS.get(request.get("cmd"))
    if not name:
        return {"ok": False, "error": f"unknown command {request.get('cmd')!r}"}
    try:
        with bridge.lock:
            try:
                result = getattr(bridge, name)(request)
            except CdpError as e:
                if "session" not in str(e).lower():
                    raise
                # Attached again next time.
                bridge.sessions.clear()
                bridge.worlds.clear()
                if name not in RETRYABLE:
                    raise Refused("the page reloaded meanwhile: read it again")
                result = getattr(bridge, name)(request)
        # Tokens never; and an adapter's answer, no key that names a secret.
        return {"ok": True, "result": scrub(result, keys=name == "op_app")}
    except (Refused, CdpError) as e:
        return {"ok": False, "error": str(e)}
    except (TypeError, ValueError, KeyError) as e:
        return {"ok": False, "error": f"bad request: {e}"}


def peer_uid(conn):
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", creds)[1]


def serve_client(conn, bridge):
    with conn:
        try:
            if peer_uid(conn) != os.getuid():
                return
        except OSError:
            return
        f = conn.makefile("rwb")
        for line in f:
            if len(line) > MAX_LINE:
                break
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or not isinstance(request.get("cmd"), str):
                    raise ValueError
                reply = handle(bridge, request)
            except ValueError:
                reply = {"ok": False, "error": "a request is one JSON object per line, with its cmd"}
            try:
                f.write(json.dumps(reply).encode() + b"\n")
                f.flush()
            except OSError:
                return


def listening(path):
    """Another launcher of this app serves its socket already."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(path)
        return True
    except OSError:
        return False
    finally:
        s.close()


def serve(path, bridge):
    d = os.path.dirname(path)
    os.makedirs(d, mode=0o700, exist_ok=True)
    st = os.lstat(d)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise OSError(f"{d} is not a directory of this user")
    os.chmod(d, 0o700)
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    old = os.umask(0o177)
    try:
        server.bind(path)
    finally:
        os.umask(old)
    os.chmod(path, 0o600)
    server.listen(8)

    def accept():
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=serve_client, args=(conn, bridge), daemon=True).start()

    threading.Thread(target=accept, daemon=True).start()
    return server, os.stat(path).st_ino


def read_file(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


# ── The app's processes (/proc, no DevTools): relaunches and the watcher ──

RELAUNCH_WATCH = 15.0  # after the app quits, how long a new instance counts as its relaunch
RESTART_GAP = 30.0  # at most one restart through the bridge per app in this time
YOUNG = 60.0  # the watcher restarts an unbridged instance this young by itself
POLL = 10.0
# Never taken for the app: shells, the tools that name it in their arguments.
NOT_THE_APP = {"bash", "sh", "dash", "zsh", "fish", "grep", "rg", "pgrep", "pkill", "ps", "cat", "less", "tail",
               "head", "nix", "nix-store", "strace", "gdb", "systemd-run", "notify-send"}
LABELS = {"discord": "Vesktop", "slack": "Slack", "youtube-music": "YouTube Music", "actual": "Actual Budget"}


def electron_dir():
    return os.path.join(runtime_base(), "nixbook-electron")


def private_dir():
    d = electron_dir()
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def proc(pid):
    """{pid, ppid, cmd, exe, start (seconds since boot), state}, or None."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
        with open(f"/proc/{pid}/stat") as f:
            stat_ = f.read()
        if os.stat(f"/proc/{pid}").st_uid != os.getuid():
            return None
    except OSError:
        return None
    fields = stat_[stat_.rindex(")") + 2:].split()
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        exe = ""
    return {"pid": pid, "ppid": int(fields[1]), "state": fields[0], "cmd": cmd, "exe": exe,
            "start": int(fields[19]) / os.sysconf("SC_CLK_TCK")}


def uptime():
    with open("/proc/uptime") as f:
        return float(f.read().split()[0])


def alive(pid):
    p = proc(pid)
    return p is not None and p["state"] != "Z"


def matches(p, markers):
    # Chromium sets its process title: the whole command line in one string.
    words = [w for a in p["cmd"] for w in a.split(" ") if w]
    if not words or any(a.startswith("--type=") for a in words):
        return False  # Chromium's helper processes: the app is their parent
    if os.path.basename(p["exe"] or words[0]) in NOT_THE_APP or os.path.basename(words[0]) in NOT_THE_APP:
        return False
    if any("electron-bridge.py" in a or a.endswith("nixbook-electron-app") for a in words):
        return False
    paths = words + ([p["exe"]] if p["exe"] else [])
    return any(a == m or a.startswith(m.rstrip("/") + "/") for a in paths for m in markers if m)


def bridged_by_us(p, table):
    """Started by a launcher (its descendant): bridged, never touched."""
    seen = 0
    while p and seen < 8:
        parent = table.get(p["ppid"]) or proc(p["ppid"])
        if not parent:
            return False
        if any("electron-bridge.py" in a or a.endswith("nixbook-electron-app") for a in parent["cmd"]):
            return True
        p, seen = parent, seen + 1
    return False


def instances(markers):
    """The app's main processes running unbridged (this user's), oldest first."""
    table = {}
    for name in os.listdir("/proc"):
        if name.isdigit() and int(name) != os.getpid():
            p = proc(int(name))
            if p and p["state"] != "Z":
                table[p["pid"]] = p
    found = [p for p in table.values() if matches(p, markers) and not bridged_by_us(p, table)]
    # The app's own children that also name it (a sandbox around it): the top one.
    ids = {p["pid"] for p in found}
    return sorted((p for p in found if p["ppid"] not in ids), key=lambda p: p["start"])


def stop_gracefully(pid, markers):
    """SIGTERM (the app quits as when the user does), SIGKILL after 5 s, to
    it and to what is left of the app unbridged (a sandbox's child), until
    none is (its single-instance lock freed)."""
    signalled = set()
    start = time.monotonic()
    targets = [pid]
    while time.monotonic() - start < 10:
        late = time.monotonic() - start > 5
        for t in targets:
            if t not in signalled or late:
                with contextlib.suppress(OSError):
                    os.kill(t, signal.SIGKILL if late else signal.SIGTERM)
                signalled.add(t)
        time.sleep(0.2)
        targets = [t for t in targets if alive(t)] + [p["pid"] for p in instances(markers)]
        if not targets:
            break
    time.sleep(0.5)


def restarted_recently(app):
    try:
        return time.time() - os.stat(os.path.join(electron_dir(), f"{app}.restarted")).st_mtime < RESTART_GAP
    except OSError:
        return False


def mark_restarted(app):
    path = os.path.join(private_dir(), f"{app}.restarted")
    with open(path, "w") as f:
        f.write(str(int(time.time())))


def notify(title, body, action=None, on_action=None):
    """A notification from the desktop agents; with action, on_action() runs once it is clicked."""
    cmd = [os.environ.get("NIXBOOK_NOTIFY_SEND") or "notify-send", "-a", "Desktop agent"]
    if action:
        cmd += ["-A", f"restart={action}", "--wait"]
    try:
        child = subprocess.Popen(cmd + [title, body], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, text=True)
    except OSError as e:
        log(f"notify-send: {e}")
        return

    def wait():
        out = child.communicate()[0] or ""
        if on_action and out.strip().splitlines()[-1:] == ["restart"]:
            on_action()

    threading.Thread(target=wait, daemon=True).start()


def label_of(app):
    return LABELS.get(app, app)


def run_bridged(opts, app, command, markers):
    """The app through the bridge, again when it relaunches itself (its
    app.relaunch(), an update applied): that new instance, unbridged, is
    stopped and started through the bridge, once per RESTART_GAP."""
    path = socket_path(app)
    page_js = read_file(opts["page_js"])
    adapter = os.path.join(opts["adapters"], f"{app}.js")
    adapter_js = read_file(adapter) if os.path.exists(adapter) else None
    state = {"child": None, "stopping": False}

    def forward(s, _f):
        state["stopping"] = True
        if state["child"] is not None:
            state["child"].send_signal(s)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, forward)
    while True:
        started = uptime()
        code = run_once(opts, app, command, path, page_js, adapter_js, state)
        if state["stopping"] or not markers:
            return code
        relaunched = catch_relaunch(app, markers, started, path)
        if not relaunched:
            return code
        log(f"{app}: it restarted itself without the bridge (pid {relaunched}); starting it again through it")


def catch_relaunch(app, markers, since, path):
    """A new unbridged instance of the app started since `since`, within
    RELAUNCH_WATCH of its quitting: stopped (its pid returned), or None."""
    watching = os.path.join(private_dir(), f"{app}.watching")
    with open(watching, "w") as f:
        f.write(str(os.getpid()))
    try:
        end = time.monotonic() + RELAUNCH_WATCH
        while time.monotonic() < end:
            if listening(path):
                return None  # started through the bridge by someone else
            new = [p for p in instances(markers) if p["start"] >= since - 0.5]
            if new:
                if restarted_recently(app):
                    log(f"{app}: it restarted itself again unbridged within {int(RESTART_GAP)} s; giving up")
                    notify(f"{label_of(app)} runs without nixbook's bridge",
                           "It restarted itself twice in a row, so it was left as it is: the desktop agents can't read or use it "
                           "until you quit it (its tray icon too) and start it again.")
                    return None
                mark_restarted(app)
                stop_gracefully(new[0]["pid"], markers)
                return new[0]["pid"]
            time.sleep(0.5)
        return None
    finally:
        with contextlib.suppress(OSError):
            os.unlink(watching)


def run_once(opts, app, command, path, page_js, adapter_js, state):
    # The pipe on fds 3 (the browser reads) and 4 (it writes), above the
    # numbers it lands on in the child first so they can't collide.
    r3, w3 = os.pipe()
    r4, w4 = os.pipe()
    child_r = os.dup2(r3, 103, inheritable=False) if r3 != 103 else r3
    child_w = os.dup2(w4, 104, inheritable=False) if w4 != 104 else w4
    os.close(r3)
    os.close(w4)

    def pipe_fds():
        os.dup2(child_r, 3)
        os.dup2(child_w, 4)

    args = command + ["--remote-debugging-pipe"] + (["--force-renderer-accessibility"] if opts["a11y"] else [])
    child = subprocess.Popen(args, preexec_fn=pipe_fds, pass_fds=(3, 4))
    state["child"] = child
    os.close(child_r)
    os.close(child_w)
    cdp = Cdp(r4, w3)
    bridge = Bridge(app, cdp, page_js, adapter_js)
    server, ino = None, None
    try:
        # Serve once the app answers on its pipe (one handing over to an
        # instance already running closes it at once).
        end = time.monotonic() + 30
        while time.monotonic() < end and child.poll() is None and not cdp.closed.is_set():
            try:
                cdp.call("Browser.getVersion", timeout=5)
                server, ino = serve(path, bridge)
                break
            except (Refused, CdpError):
                time.sleep(0.2)
        if server is None and child.poll() is None and not cdp.closed.is_set():
            log(f"{app} doesn't answer on its DevTools pipe: no bridge this time")
        child.wait()
    finally:
        if server is not None:
            try:
                if os.stat(path).st_ino == ino:
                    os.unlink(path)
            except OSError:
                pass
            server.close()
        with contextlib.suppress(OSError):
            os.close(r4)
            os.close(w3)
    return child.returncode if child.returncode >= 0 else 128 - child.returncode


# ── The watcher (nixbook-electron-app watch): apps running without the bridge ──

def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "nixbook-shell", "electron-bridge.json")


def read_config(path=None):
    try:
        with open(path or config_path(), encoding="utf-8") as f:
            apps = json.load(f).get("apps") or []
    except (OSError, ValueError) as e:
        log(f"no bridged apps ({e})")
        return {}
    out = {}
    for a in apps:
        if isinstance(a, dict) and APP_NAME.match(str(a.get("app") or "")) and a.get("command") \
                and not PASSWORD_APPS.search(a["app"]):
            out[a["app"]] = {"command": [str(x) for x in a["command"]], "markers": [str(m) for m in a.get("markers") or []],
                             "a11y": a.get("a11y", True) is not False}
    return out


def launcher(opts):
    return [sys.executable, "-I", os.path.abspath(__file__), "--page-js", opts["page_js"], "--adapters", opts["adapters"]]


def spawn_bridged(opts, app, cfg):
    """The app started through the bridge, in a scope of its own (the
    watcher's service stopping never takes it along)."""
    argv = launcher(opts) + (["--no-a11y"] if not cfg["a11y"] else []) + \
        [m for marker in cfg["markers"] for m in ("--marker", marker)] + [app, "--"] + cfg["command"]
    run = os.environ.get("NIXBOOK_SYSTEMD_RUN") or "systemd-run"
    if os.environ.get("NIXBOOK_ELECTRON_SPAWN") != "plain" and (os.path.isabs(run) or shutil.which(run)):
        argv = [run, "--user", "--scope", "--quiet", "--collect", f"--unit=app-nixbook-{app}-{int(time.time())}",
                "--"] + argv
    subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def in_call(pid):
    """The app captures a microphone (a call): one of PipeWire's recording
    streams belongs to it or to one of its processes."""
    pactl = os.environ.get("NIXBOOK_PACTL") or "pactl"
    try:
        out = subprocess.run([pactl, "-f", "json", "list", "source-outputs"], capture_output=True, text=True,
                             timeout=5).stdout
        streams = json.loads(out or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False
    pids = set()
    for s in streams if isinstance(streams, list) else []:
        with contextlib.suppress(TypeError, ValueError, AttributeError):
            pids.add(int((s.get("properties") or {}).get("application.process.id")))
    for p in pids:
        seen = 0
        while p and p > 1 and seen < 8:
            if p == pid:
                return True
            info = proc(p)
            p, seen = (info["ppid"] if info else 0), seen + 1
    return False


def restart(opts, app, cfg, pid=None, why="restart"):
    """Stop the unbridged instance and start the app through the bridge."""
    if listening(socket_path(app)):
        return f"{app} already runs through the bridge"
    found = [p for p in instances(cfg["markers"]) if pid is None or p["pid"] == pid]
    if pid is not None and not found:
        return f"{app}: that instance is gone"
    mark_restarted(app)
    for p in found:
        stop_gracefully(p["pid"], cfg["markers"])
    spawn_bridged(opts, app, cfg)
    log(f"{app}: started through the bridge ({why})")
    return f"{app}: started again through the bridge"


class Watcher:
    def __init__(self, opts, apps):
        self.opts, self.apps = opts, apps
        self.notified = {}  # app → the pid already told about
        self.asked = {}  # (app, pid) → when an agent's request was last told
        self.lock = threading.Lock()

    def tell(self, app, pid, why):
        label = label_of(app)

        def clicked():
            with self.lock:
                restart(self.opts, app, self.apps[app], pid, "the user's click")

        notify(f"{label} runs without nixbook's bridge",
               f"{why} The desktop agents can't read or use it until it restarts through the bridge. Restart it now? "
               "(It closes and opens again.)", "Restart with bridge", clicked)
        log(f"{app}: running unbridged (pid {pid}): the user was told")

    def poll(self):
        unbridged = {}
        d = private_dir()
        now = uptime()
        for app, cfg in self.apps.items():
            if listening(socket_path(app)):
                self.notified.pop(app, None)
                continue
            w = os.path.join(d, f"{app}.watching")
            with contextlib.suppress(OSError, ValueError):
                with open(w) as f:
                    if alive(int(f.read().strip())):
                        continue  # its launcher is catching a relaunch
            found = instances(cfg["markers"])
            ask = os.path.join(d, f"{app}.ask")
            asked = os.path.exists(ask)
            with contextlib.suppress(OSError):
                os.unlink(ask)
            if not found:
                self.notified.pop(app, None)
                continue
            p = found[0]
            age = now - p["start"]
            call = in_call(p["pid"])
            unbridged[app] = {"pid": p["pid"], "label": label_of(app), "age": int(age), "inCall": call}
            if self.notified.get(app) == p["pid"]:
                last = self.asked.get((app, p["pid"]), 0)
                if asked and time.monotonic() - last > 600:
                    self.asked[(app, p["pid"])] = time.monotonic()
                    self.tell(app, p["pid"], "An agent tried to use it.")
                continue
            self.notified[app] = p["pid"]
            if age < YOUNG_LIMIT() and not call and not restarted_recently(app):
                with self.lock:
                    restart(self.opts, app, cfg, p["pid"], "it had just started without it")
                unbridged.pop(app, None)
                continue
            self.asked[(app, p["pid"])] = time.monotonic()
            self.tell(app, p["pid"], "It was in a call, so it was left as it is." if call else
                      "It was started before the bridge, or by itself.")
        tmp = os.path.join(d, ".unbridged.json.tmp")
        with open(tmp, "w") as f:
            json.dump(unbridged, f)
        os.replace(tmp, os.path.join(d, "unbridged.json"))
        return unbridged


def YOUNG_LIMIT():
    try:
        return float(os.environ.get("NIXBOOK_ELECTRON_YOUNG", YOUNG))
    except ValueError:
        return YOUNG


def parse(argv):
    opts = {"page_js": os.path.join(HERE, "..", "zen", "page.js"), "adapters": os.path.join(HERE, "..", "electron"),
            "a11y": True, "markers": [], "config": None, "once": False}
    i = 0
    while i < len(argv) and argv[i].startswith("--"):
        a = argv[i]
        if a in ("--page-js", "--adapters", "--marker", "--config") and i + 1 < len(argv):
            key = {"--page-js": "page_js", "--adapters": "adapters", "--config": "config"}.get(a)
            if key:
                opts[key] = argv[i + 1]
            else:
                opts["markers"].append(argv[i + 1])
            i += 2
        elif a == "--no-a11y":
            opts["a11y"] = False
            i += 1
        elif a == "--once":
            opts["once"] = True
            i += 1
        elif a == "--":
            break
        else:
            raise SystemExit(f"nixbook-electron-app: unknown option {a}")
    rest = argv[i:]
    if rest[:1] in (["watch"], ["restart"], ["status"]):
        return opts, rest[0], rest[1:]
    if len(rest) < 3 or rest[1] != "--":
        raise SystemExit(__doc__.split("\n\n")[1])
    return opts, rest[0], rest[2:]


def main(argv):
    if "--socket" in argv:
        i = argv.index("--socket")
        if i + 1 < len(argv):
            print(socket_path(argv[i + 1]))
            return 0
    opts, app, command = parse(argv)
    if app in ("watch", "restart", "status"):
        if "--once" in command:
            opts["once"] = True
            command = [c for c in command if c != "--once"]
        apps = read_config(opts["config"])
        if app == "restart":
            if not command or command[0] not in apps:
                raise SystemExit(f"nixbook-electron-app restart: one of {', '.join(sorted(apps)) or 'no app'}")
            print(restart(opts, command[0], apps[command[0]], why="asked"))
            return 0
        watcher = Watcher(opts, apps)
        if app == "status" or opts["once"]:
            print(json.dumps(watcher.poll() if app == "watch" else {
                a: {"bridged": listening(socket_path(a)), "running": bool(instances(c["markers"]))}
                for a, c in apps.items()}))
            if app == "watch":
                time.sleep(float(os.environ.get("NIXBOOK_ELECTRON_LINGER", "0")))  # tests: a click's restart
            return 0
        while True:
            try:
                watcher.poll()
            except OSError as e:
                log(f"watch: {e}")
            time.sleep(POLL)
    plain = command + (["--force-renderer-accessibility"] if opts["a11y"] else [])
    if not APP_NAME.match(app):
        raise SystemExit(f"nixbook-electron-app: {app!r} isn't an app name (a-z, 0-9, -)")
    if PASSWORD_APPS.search(app) or PASSWORD_APPS.search(os.path.basename(command[0])):
        log(f"{app}: a password manager is never bridged; starting it without")
        os.execvp(plain[0], plain)
    if os.environ.get("NIXBOOK_ELECTRON_BRIDGE") == "0" or listening(socket_path(app)):
        # Off, or a bridged instance runs: this start hands over to it.
        os.execvp(plain[0], plain)
    markers = [m for m in opts["markers"] if m.startswith("/") and m.rstrip("/").count("/") >= 2]
    # Without markers (the app's own store paths, from Nix: --marker) nothing
    # is matched: a guess (the binary's interpreter…) could stop other programs.
    return run_bridged(opts, app, command, markers)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
