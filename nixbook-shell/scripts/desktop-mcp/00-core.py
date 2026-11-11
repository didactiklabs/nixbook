# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Configuration, input guards, the audit log, helpers and guardrails.

import base64
import concurrent.futures
import contextlib
import bisect
import datetime
import hmac
import fcntl
import hashlib
import json
import math
import mimetypes
import os
import queue
import random
import re
import secrets
import shlex
import shutil
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import warnings

VERSION = "1.0.0"
PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]
SERVER_NAME = "nixbook-desktop"

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

DEFAULT_CONFIG = {
    # Tool groups on offer; the others are neither listed nor callable.
    "tools": ["observe", "screen", "windows", "input", "shell", "memory", "personal", "ui", "pages"],
    # No keyboard/pointer input while the focused window's app_id (or title)
    # matches one of these (Python regexes, case-insensitive, searched).
    "inputDenyApps": [
        r"^(kitty|foot|footclient|alacritty|wezterm|org\.wezfurlong\.wezterm|"
        r"com\.mitchellh\.ghostty|ghostty|konsole|org\.kde\.konsole|xterm|urxvt|"
        r"st|st-256color|terminator|tilix|com\.gexperts\.tilix|"
        r"org\.gnome\.terminal|gnome-terminal.*|org\.gnome\.console|kgx|"
        r"org\.gnome\.ptyxis|ptyxis|rio|contour|blackbox|com\.raggesilver\.blackbox)$",
        r"keepass|bitwarden|1password|enpass|proton-?pass|seahorse|gnome-keyring|"
        r"gcr-prompter|pinentry|polkit|lxqt-policykit|kdesu",
        # The shell's Settings window: an agent could turn its own rules off there.
        r"^org\.quickshell$",
    ],
    "inputDenyTitles": [r"\bpassword\b|\bpassphrase\b|\bsudo\b|\bauthenticat"],
    # Shell IPC targets the agent can't call (the session screen leads to
    # power off/log out; nixManaged reloads the settings).
    # desktopControl: the bar widget's pause/resume; layouts: the user's
    # window layouts, which don't honour the pause (agents have their own
    # layout tools). Only the user may use them.
    # projects: the user's (agents have the project tool).
    # smartClipboard: run would take the action offered for what the user
    # copied, offer would show chips the user never asked for.
    # "mesh": messages to people in the user's name (services/Mesh.qml).
    # "audio": it could unmute the microphone (services/Audio.qml).
    "shellIpcDenyTargets": ["session", "nixManaged", "desktopControl", "layouts", "settings", "makeWay", "projects",
                            "smartClipboard", "mesh", "audio"],
    "allowSuperKey": False,
    "maxTextLength": 4000,
    # A note written into the notes widget (it goes through a file, not the
    # shell's IPC: see notes_call).
    "maxNoteLength": 100000,
    "actionsPerMinute": 120,
    "notifyOnControl": True,
    "screenshotMaxEdge": 1280,
    # JPEG: a fraction of a PNG's size, so screenshots reach the model sooner.
    "screenshotFormat": "jpeg",
    "screenshotQuality": 80,
    # read_screen's OCR languages (tesseract's -l: "eng", "eng+fra"…).
    "ocrLanguages": "eng",
    # Desktop memory: the digest sent to agents when they connect, at most
    # this many characters; notes kept (the weakest go to the archive first).
    "memoryPromptChars": 1500,
    "memoryMaxNotes": 100,
    # The memory pass on agents' tasks: a small model, in the background,
    # only for a task new to the memory that took work, and the weekly
    # tidy-up (Claude Code: memoryClaude, else `claude` on PATH).
    "memoryLearn": True,
    "memoryModel": "haiku",
    "memoryClaude": "",
    # The agent speaking first (the shell's services/Initiative.qml): at
    # most this many notifications a day, this many minutes apart, none in
    # the quiet hours (the rest waits in the bar); notifications read by the
    # small model, at most this many calls a day.
    "initiative": True,
    "initiativeMaxPerDay": 8,
    "initiativeGapMinutes": 20,
    "initiativeQuietHours": "22-8",
    "initiativeCallsPerDay": 30,
    # Apps (and window titles) whose activity never leaves the machine in the
    # recent context, beside habitsIgnoreApps/Titles: chats and mail.
    "privateIgnoreApps": [
        r"signal|whatsapp|telegram|discord|vesktop|slack|element|fractal|thunderbird|evolution|geary|"
        r"kmail|betterbird|messenger|teams|zoom|kdeconnect|bank|paypal|authenticator",
    ],
    "privateIgnoreTitles": [r"\b(inbox|gmail|outlook|proton ?mail|messenger|whatsapp|telegram|signal|discord|slack|teams|"
                         r"private browsing|incognito|bank|banque|paypal|doctolib|ameli|health|medical)\b"],
    # Routines that take judgment: a short Claude run each, at most this many a day.
    "routineAgentPerDay": 20,
    "routineModel": "haiku",
    # Personal memory (what the user told agents about their life): the part
    # sent when an agent connects, at most this many characters; entries kept.
    "personalPromptChars": 900,
    "personalMaxEntries": 200,
    # A person's entry also in the notes of their contact (added when none
    # has their name, in this account: an id, name or email; "" the first).
    "personalContacts": True,
    "personalContactsAccount": "",
    # Usage habits (desktopMcp.habits.enable, the nixbook-habits service):
    # what the user does, counted on this machine. App ids and times only,
    # kept habitsKeepDays days; never these apps or windows (password
    # managers and prompts, private browser windows).
    "habits": False,
    "habitsKeepDays": 28,
    "habitsIgnoreApps": [
        r"keepass|bitwarden|1password|enpass|proton-?pass|seahorse|gnome-keyring|"
        r"gcr-prompter|pinentry|polkit|lxqt-policykit|kdesu",
    ],
    "habitsIgnoreTitles": [r"private browsing|incognito|inprivate|\bpassword\b|\bpassphrase\b"],
    # What agents get: "digest" (a line: the usual apps and layout now, how
    # sessions start, the week's top apps), "timeline" (also a day hour by
    # hour, on request) or "off".
    "habitsAgents": "digest",
    "habitsWeeklyReport": True,
    # A theme switched to at the same hour on several days: "suggest" it
    # then (a notification), switch to it on its own ("auto"), or "off".
    "habitsTheme": "suggest",
    # Desktop ids of apps opened on their own at the time the user usually
    # opens them (none by default: a window appearing unasked is intrusive).
    "habitsOpenAtUsualTime": [],
    # Music taste: the tracks every player plays (artist, title, album),
    # kept habitsMusicKeepDays days; never from these players (regexes on
    # the MPRIS name: web browsers publish their tabs' videos).
    "habitsMusic": True,
    "habitsMusicKeepDays": 365,
    "habitsMusicIgnorePlayers": [
        r"^(firefox|chromium|chrome|brave|zen|librewolf|floorp|vivaldi|opera|"
        r"microsoft-edge|plasma-browser-integration)",
    ],
    "http": {"port": 7823},
    # The page tools in Zen (through nixbook's extension): tabs whose
    # address matches one of these (Python/JS regexes, case-insensitive), or
    # in one of these containers, are neither read nor used (listed as
    # private), and agents can't open them; private windows never.
    "browser": {
        "blockedSites": [
            r"^(about|chrome|moz-extension|resource|view-source|file|data|javascript):",
            r"://([^/]*\.)?(bitwarden|vaultwarden|1password|lastpass|dashlane|keepersecurity|nordpass|enpass)\.",
            r"://(pass\.proton\.me|account\.proton\.me)",
            r"://(accounts|myaccount)\.google\.com",
            r"://([^/]*\.)?paypal\.",
            r"://[^/]*(bank|banque|boursorama|revolut|n26\.com|qonto|fortuneo|credit-?agricole|creditmutuel|"
            r"societegenerale|bnpparibas|caisse-?epargne|lcl\.fr|labanquepostale|wise\.com)",
        ],
        "blockedContainers": ["Banking"],
    },
    # The page tools in the Electron apps nixbook bridges (nixbook-electron-app):
    # apps whose name matches one of these are never used (password managers
    # never are, whatever this says).
    "pages": {
        "blockedApps": [],
    },
    # What speaks or pays in the user's name (a Discord message or reaction,
    # Enter in a chat app's message box, a click on Send, Pay, Delete… in a
    # page) waits for the user's own yes: a notification with Allow / No.
    # Off only for clients that ask the user themselves before each such call.
    "askBeforeSending": True,
    # The fixer is on this machine (programs.nixbook-shell.selfImprove.enable):
    # report_problem and request_feature are listed only then.
    "improve": False,
}

TOOL_GROUPS = ["observe", "screen", "windows", "input", "shell", "memory", "personal", "ui", "pages"]
# Groups of other versions: the page tools were Zen's browser tools.
RENAMED_GROUPS = {"browser": "pages"}


def xdg(var, fallback):
    return os.environ.get(var) or os.path.expanduser(fallback)


def config_path():
    return os.environ.get("NIXBOOK_DESKTOP_MCP_CONFIG") or os.path.join(
        xdg("XDG_CONFIG_HOME", "~/.config"), "nixbook-shell", "desktop-mcp.json"
    )


def load_config():
    cfg = read_config()
    only = os.environ.get("NIXBOOK_DESKTOP_MCP_GROUPS")
    if only is not None:
        cfg["tools"] = [g for g in cfg["tools"] if g in only.split(",")]
    # Only these tools (a single-purpose agent: the equalizer's): an agent
    # is sent every tool the server offers, allowed or not.
    names = os.environ.get("NIXBOOK_DESKTOP_MCP_TOOLS")
    if names is not None:
        cfg["onlyTools"] = [n for n in names.split(",") if n]
    return cfg


def read_config():
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    path = config_path()
    try:
        with open(path, encoding="utf-8") as f:
            user = json.load(f)
        if not isinstance(user, dict):
            raise ValueError("not a JSON object")
    except FileNotFoundError:
        return cfg
    except (OSError, ValueError) as e:
        log(f"ignoring {path}: {e}")
        return cfg
    for key, value in user.items():
        if key not in DEFAULT_CONFIG:
            log(f"{path}: unknown key {key!r}, ignored")
        elif key in ("http", "browser", "pages") and isinstance(value, dict):
            cfg[key].update(value)
        else:
            cfg[key] = value
    if isinstance(cfg["tools"], list):
        cfg["tools"] = list(dict.fromkeys(RENAMED_GROUPS.get(g, g) for g in cfg["tools"]))
    cfg["tools"] = [g for g in cfg["tools"] if g in TOOL_GROUPS]
    return cfg


def runtime_dir():
    """The private directory for the kill switch, token and screenshots.
    Without one nothing runs (the kill switch couldn't be honoured)."""
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    path = os.path.join(base, "nixbook-desktop-mcp")
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
        st = os.lstat(path)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            raise OSError(f"{path} is not a directory owned by this user")
        os.chmod(path, 0o700)
    except OSError as e:
        raise ToolError(f"no private runtime directory (XDG_RUNTIME_DIR): {e}")
    return path


def allowed_flag():
    """The kill switch: agents may act only while this file exists. It lives
    in the state directory, so the user's choice survives a reboot, and its
    absence (a new install, a wiped state) means paused: desktop control is
    off until the user allows it."""
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "desktop-control-allowed")


def quiet_flag():
    """While this file exists, no notification when an agent starts driving
    the desktop (the user's toggle; config `notifyOnControl: false` turns it
    off for good). In the state directory too, so it survives a reboot."""
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "desktop-control-quiet")


def notify_enabled():
    return not os.path.exists(quiet_flag())


def is_paused():
    runtime_dir()  # no private runtime directory: nothing runs
    return not os.path.exists(allowed_flag())


def state_path():
    return os.path.join(runtime_dir(), "state.json")


def read_state():
    try:
        with open(state_path(), encoding="utf-8") as f:
            state = json.load(f)
        return state if isinstance(state, dict) else {}
    except (OSError, ValueError, ToolError):
        return {}


def write_state(**changes):
    """What the shell's bar widget shows (services/DesktopControl.qml): paused
    or not and the last call. Written in place, the widget re-reads it."""
    try:
        state = read_state()
        state.update(changes)
        state["paused"] = is_paused()
        with open(state_path(), "w", encoding="utf-8") as f:
            json.dump(state, f)
    except (OSError, ToolError) as e:
        log(f"state file: {e}")


def log(msg):
    print(f"nixbook-desktop-mcp: {msg}", file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Input guards
# --------------------------------------------------------------------------

# Apps with a terminal inside (Dolphin's F4 panel, editors'), the keys that
# open it, and browsers with their developer tools (a console running code
# in the page).
TERMINAL_HOSTS = re.compile(
    r"^(org\.kde\.(dolphin|kate|kwrite|kdevelop)|code|code-oss|codium|vscodium|com\.visualstudio\.code.*|"
    r"dev\.zed\.zed|zed|jetbrains-.*|org\.gnome\.builder|com\.vscodium\.codium)$", re.IGNORECASE)
TERMINAL_HOST_KEYS = {"f4", "shift+f4", "ctrl+grave", "ctrl+shift+grave", "ctrl+shift+c", "alt+f12", "ctrl+shift+t"}
BROWSER_APPS = re.compile(r"firefox|zen|librewolf|floorp|chrom|brave|vivaldi|opera|microsoft-edge", re.IGNORECASE)
DEVTOOLS_KEYS = {"f12", "ctrl+shift+i", "ctrl+shift+j", "ctrl+shift+k", "ctrl+shift+c", "ctrl+shift+e",
                 "ctrl+shift+m", "ctrl+shift+u", "ctrl+u"}


def agent_input_since(t):
    """Whether an agent typed or clicked on the user's desktop since time t
    (seconds): what the user answered meanwhile may have been the agent."""
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nixbook-shell")
    try:
        with open(os.path.join(base, "agent-input"), encoding="utf-8") as f:
            return int(f.read().strip() or 0) / 1000 >= t
    except (OSError, ValueError):
        return False


def mark_agent_input():
    """Before any input on the user's desktop: the time, for the shell, which
    then won't run a launcher `$` command or send a side-panel chat message
    for a few seconds (keys and clicks from an agent look like the user's)."""
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nixbook-shell")
    try:
        os.makedirs(base, mode=0o700, exist_ok=True)
        tmp = os.path.join(base, f".agent-input.{os.getpid()}")
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(str(int(time.time() * 1000)))
        os.replace(tmp, os.path.join(base, "agent-input"))
    except OSError:
        pass


# The shell's own windows over the apps (services/MakeWay.qml: the side
# panel, Claude's speech bubble, notification popups, a theme's cut-in)
# make way for an agent on the user's desktop: its clicks and keys go
# through them to the apps, and they are invisible in its screenshots,
# while the user still sees them (faded). The shell lists what is on screen
# in overlays.json, read before each action (a file read: nothing to do,
# no cost, when none is up); make-way.json asks, only while the action or
# the look is going on (MAKE_WAY_ACTION_MS at most, should the server die
# meanwhile) and MAKE_WAY_AFTER_MS after: between the agent's steps, while
# it thinks, the user has them back to use; the shell answers in
# make-way.ack once it is on screen (waited for, at most MAKE_WAY_WAIT s,
# only when it changes). An action (not a look) also dismisses a theme's
# cut-in on screen and those queued (`clearCutIns`), as Escape would: they
# stay in the notification centre.
MAKE_WAY_ACTION_MS = 30000
MAKE_WAY_AFTER_MS = 1500
MAKE_WAY_WAIT = 0.3


def shell_runtime_dir():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nixbook-shell")


def shell_overlays():
    """What of the shell is over the apps now: names (sidePanel, speechBubble,
    notificationPopups, cutIn)."""
    try:
        with open(os.path.join(shell_runtime_dir(), "overlays.json"), encoding="utf-8") as f:
            names = (json.load(f) or {}).get("overlays") or []
        return [n for n in names if isinstance(n, str)][:8]
    except (OSError, ValueError, AttributeError):
        return []


def make_way(capture=False, wait=True, hold_ms=MAKE_WAY_ACTION_MS, clear=False):
    """Asks the shell's overlays to let the agent through (and, `capture`, to
    vanish for a screenshot; `clear`, an action starting, to dismiss a
    cut-in): the ones on screen, [] when none."""
    overlays = shell_overlays()
    if not overlays:
        return []
    path = os.path.join(shell_runtime_dir(), "make-way.json")
    now = int(time.time() * 1000)
    try:
        with open(path, encoding="utf-8") as f:
            before = json.load(f) or {}
    except (OSError, ValueError):
        before = {}
    seq = int(before.get("seq") or 0) + 1 if isinstance(before.get("seq"), int) else 1
    clear = clear and not capture and "cutIn" in overlays
    # Already so on screen: only held on, nothing to wait for.
    same = before.get("until", 0) > now + 500 and bool(before.get("capture")) == capture and not clear
    request = {"seq": seq, "until": now + hold_ms, "capture": capture}
    if clear:
        request["clearCutIns"] = True
    try:
        # Written in place: the shell watches this path.
        with open(path, "w", encoding="utf-8") as f:
            json.dump(request, f)
    except OSError:
        return overlays
    if wait and not same:
        ack = os.path.join(shell_runtime_dir(), "make-way.ack")
        deadline = time.monotonic() + MAKE_WAY_WAIT
        while time.monotonic() < deadline:
            try:
                with open(ack, encoding="utf-8") as f:
                    if f.read().strip() == str(seq):
                        break
            except OSError:
                pass
            time.sleep(0.01)
    return overlays


@contextlib.contextmanager
def overlays_hidden(ctx):
    """The shell's overlays invisible while the agent looks at the screen
    (nested: shown again when the outermost look is done)."""
    depth = getattr(ctx, "hiding", 0)
    ctx.hiding = depth + 1
    shown = make_way(capture=True) if depth == 0 else ctx.hidden_overlays
    if depth == 0:
        ctx.hidden_overlays = shown
    try:
        yield shown
    finally:
        ctx.hiding = depth
        if depth == 0 and shown:
            # Still in the action: held for it, else only a moment more.
            make_way(capture=False, wait=False,
                     hold_ms=MAKE_WAY_ACTION_MS if getattr(ctx, "in_action", False) else MAKE_WAY_AFTER_MS)


def overlays_note(ctx, shown):
    """What the agent is told of the overlays it was let through: once for
    each set of them (a cut-in coming up is told)."""
    if not shown or getattr(ctx, "overlays_told", None) == shown:
        return None
    ctx.overlays_told = shown
    return text("On screen, the shell's " + ", ".join(shown) + ": made click-through, keyboard released and "
                "hidden from your screenshots while you work, so act on the windows under them as if they "
                "weren't there. If one still gets in your way, set_aside hides notificationPopups, a "
                "cutIn or the speechBubble while you work (they come back for the user after; never the "
                "sidePanel: the user's chat with you).")


def focused_a11y_role(w):
    """The accessibility role of the focused element of window w, None when
    it can't be told."""
    try:
        Atspi = atspi()
        _, frame = ui_frame(Atspi, w)
        stack, visits = [(frame, 0)], 0
        while stack and visits < 800:
            node, depth = stack.pop()
            visits += 1
            s = node.get_state_set()
            if s.contains(Atspi.StateType.FOCUSED) and depth:
                return node.get_role_name()
            if depth < 40 and s.contains(Atspi.StateType.SHOWING) or not depth:
                for i in range(min(node.get_child_count(), 300)):
                    c = node.get_child_at_index(i)
                    if c is not None:
                        stack.append((c, depth + 1))
        return "unknown"
    except Exception:
        return None


# --------------------------------------------------------------------------
# Audit log
# --------------------------------------------------------------------------

AUDIT_MAX = 1 << 20
_audit_lock = threading.Lock()


def audit_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "desktop-mcp.log")


# Arguments whose content is private: only their length is logged, also
# inside others (run_steps' steps); vars fill the steps' text.
PRIVATE_ARGS = {"text", "value", "vars", "content"}


def redact(v):
    if isinstance(v, dict):
        return {k: (f"<{len(x)} chars>" if isinstance(x, str) else "<private>") if k in PRIVATE_ARGS
                else redact(x) for k, x in v.items()}
    if isinstance(v, list):
        return [redact(x) for x in v]
    return v


def audit(client, tool, args, outcome):
    safe = {}
    for k, v in redact(args or {}).items():
        safe[k] = v if len(json.dumps(v)) <= 200 else "<long>"
    entry = {
        "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "client": client,
        "tool": tool,
        "args": safe,
        "outcome": outcome,
    }
    path = audit_path()
    with _audit_lock:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.path.exists(path) and os.path.getsize(path) > AUDIT_MAX:
                os.replace(path, path + ".1")
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(fd, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError as e:
            log(f"audit log: {e}")


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


class ToolError(Exception):
    """A refusal or failure reported to the agent (isError: true)."""


def run(argv, *, input=None, timeout=10, check=True, binary=False, env=None):
    exe = shutil.which(argv[0])
    if not exe:
        raise ToolError(f"`{argv[0]}` is not installed or not on PATH")
    try:
        proc = subprocess.run(
            [exe, *argv[1:]],
            input=input,
            capture_output=True,
            timeout=timeout,
            text=not binary and not isinstance(input, bytes),
            env=env,
        )
    except subprocess.TimeoutExpired:
        raise ToolError(f"`{argv[0]}` timed out")
    if check and proc.returncode != 0:
        err = proc.stderr or proc.stdout or ""
        if isinstance(err, bytes):
            err = err.decode(errors="replace")
        err = err.strip()
        raise ToolError(f"`{' '.join(argv[:3])}` failed: {err[:500]}")
    return proc


def niri_json(*what, env=None):
    out = run(["niri", "msg", "--json", *what], env=env).stdout
    try:
        return json.loads(out)
    except ValueError:
        raise ToolError(f"unexpected output from `niri msg {' '.join(what)}`")


def niri_action(*args):
    run(["niri", "msg", "action", *args])


def windows():
    return niri_json("windows")


def window_by_id(wid):
    for w in windows():
        if w.get("id") == wid:
            return w
    raise ToolError(f"no window with id {wid} (see list_windows)")


def focused_window():
    for w in windows():
        if w.get("is_focused"):
            return w
    return None


def as_int(args, key, *, required=True):
    v = args.get(key)
    if v is None and not required:
        return None
    if isinstance(v, bool) or not isinstance(v, (int, float)) or int(v) != v:
        raise ToolError(f"`{key}` must be an integer")
    return int(v)


def as_str(args, key, *, required=True, max_len=256, pattern=None):
    v = args.get(key)
    if v is None and not required:
        return None
    if not isinstance(v, str) or not v:
        raise ToolError(f"`{key}` must be a non-empty string")
    if len(v) > max_len:
        raise ToolError(f"`{key}` is longer than {max_len} characters")
    if pattern and not re.fullmatch(pattern, v):
        raise ToolError(f"`{key}` has an invalid value: {v!r}")
    return v


WORKSPACE_REF = r"[\w .\-]{1,64}"


def workspace_ref(args, key="workspace"):
    v = args.get(key)
    if isinstance(v, (int, float)) and not isinstance(v, bool) and int(v) == v and v >= 0:
        return str(int(v))
    if isinstance(v, str) and re.fullmatch(WORKSPACE_REF, v) and not v.startswith("-"):
        return v
    raise ToolError(f"`{key}` must be a workspace index (1, 2, …) or name")


# --------------------------------------------------------------------------
# Guardrails
# --------------------------------------------------------------------------


class Guard:
    def __init__(self, cfg, client, notify=True):
        self.cfg = cfg
        self.client = client
        self.notify = notify and cfg.get("notifyOnControl", True)
        self.actions = []  # timestamps of recent actions
        # None until the first action: time.monotonic() counts from boot, so a
        # 0.0 start made the first action look recent within 5 minutes of
        # boot and the takeover went unannounced.
        self.last_action = None
        self.lock = threading.Lock()

    def check_rate(self):
        now = time.monotonic()
        limit = int(self.cfg.get("actionsPerMinute", 120))
        with self.lock:
            self.actions = [t for t in self.actions if now - t < 60]
            if limit > 0 and len(self.actions) >= limit:
                raise ToolError(
                    f"rate limit: more than {limit} actions in a minute; slow down"
                )
            self.actions.append(now)
            idle = math.inf if self.last_action is None else now - self.last_action
            self.last_action = now
        # Tell the user an agent took over (again after 5 idle minutes).
        if self.notify and idle > 300 and notify_enabled():
            try:
                run(
                    [
                        "notify-send",
                        "-a",
                        "Desktop agent",
                        "-i",
                        "input-mouse",
                        "--",
                        f"{self.client} is driving the desktop",
                        "Stop it with `nixbook-desktop-mcp pause`.",
                    ],
                    timeout=3,
                    check=False,
                )
            except ToolError:
                pass

    def check_input_target(self, combos=None, keyboard=True):
        """Refuses input where it could run commands or reach secrets: a
        terminal, a password manager or prompt, the shell's Settings; for the
        keyboard also a terminal inside an app (Dolphin's F4 panel, an
        editor's: by its accessibility role) and the keys that open one, and
        browsers' developer tools. Then marks the input (mark_agent_input)."""
        w = focused_window()
        mark_agent_input()
        if not w:
            return
        app = w.get("app_id") or ""
        title = w.get("title") or ""
        if keyboard:
            keys = {"+".join(sorted(m for m in mods) + [key.lower()]) for mods, key in combos or []}
            if TERMINAL_HOSTS.search(app):
                if keys & TERMINAL_HOST_KEYS:
                    raise ToolError(f"refused: in {app!r} those keys open a terminal, which is off limits")
                role = focused_a11y_role(w)
                if role in (None, "terminal"):
                    raise ToolError(f"refused: {app!r} has a built-in terminal, and the keyboard focus "
                                    + ("is in it" if role else "can't be checked (accessibility bus)")
                                    + "; ask the user to do this step")
            if BROWSER_APPS.search(app) and keys & DEVTOOLS_KEYS:
                raise ToolError("refused: the browser's developer tools are off limits")
        for pat in self.cfg.get("inputDenyApps", []):
            if re.search(pat, app, re.IGNORECASE):
                raise ToolError(
                    f"refused: input into {app!r} is not allowed (terminals, password "
                    "managers and password prompts are off limits). Focus another "
                    "window, or ask the user to do this step."
                )
        for pat in self.cfg.get("inputDenyTitles", []):
            if re.search(pat, title, re.IGNORECASE):
                raise ToolError(
                    "refused: the focused window looks like a password or "
                    "authentication prompt; ask the user to do this step."
                )

    def check_text(self, text):
        cap = int(self.cfg.get("maxTextLength", 4000))
        if len(text) > cap:
            raise ToolError(f"refused: text longer than {cap} characters")


# --------------------------------------------------------------------------
