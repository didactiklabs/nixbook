# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The session context, the trust ladder, and pages (Zen, bridged Electron apps).

# Dispatch
# --------------------------------------------------------------------------


class Context:
    def __init__(self, cfg, transport, client, notify=True):
        self.cfg = cfg
        self.transport = transport
        self.client = client
        self.guard = Guard(cfg, client, notify)
        self.lock = threading.Lock()
        # Just-in-time memory: the apps and notes this session was given.
        self.apps_seen = set()
        self.notes_shown = set()
        # The personal memory entries this session was given.
        self.entries_shown = set()
        # The MCP session of the call running (call_tool), and the last
        # monitor capture each was sent (monitor_screenshot).
        self.session = None
        self.frames = {}
        # The task the client was last told the notes of (task_note).
        self.task_told = None
        # What the agent does for a task, to learn from (finish_episode).
        self.episode = new_episode()
        self.last_note = None
        # The app of the last action's focused window (its desktop id).
        self.last_app = None


def offered_tools(cfg):
    """The tools/list: the enabled tools but the hidden ones (steps only)."""
    return [t["spec"] for t in enabled_tools(cfg).values() if not t.get("hidden")]


def enabled_tools(cfg):
    only = cfg.get("onlyTools")
    return {n: t for n, t in TOOLS.items() if t["group"] in cfg["tools"] and (only is None or n in only)
            and (n not in ("report_problem", "request_feature", "list_requests", "list_improvements",
                           "start_improvement") or cfg.get("improve"))}


# --------------------------------------------------------------------------
# Pages: Zen's tabs and the Electron apps' windows, through the page itself.
# Zen: nixbook-shell's extension (zen/) and its native host
# nixbook-zen-bridge. The Electron apps nixbook starts through
# nixbook-electron-app (Vesktop, Slack, YouTube Music, Actual…): the app's
# DevTools protocol on a private pipe, behind a Unix socket per app
# ($XDG_RUNTIME_DIR/nixbook-electron/APP.sock). Both run the same page code
# (zen/page.js) and only answer fixed operations; both sockets are only this
# user's. No pointer, no keys, no screenshot: background tabs, other
# workspaces and hidden windows work the same, and the user keeps working.
# A target names a page: `zen` (the tab shown), `zen:<tab id>`, `discord`
# (an app's main window), `discord:<page id>`.
# --------------------------------------------------------------------------

PAGE_ACTS = ("page_go", "page_act", "browser_open", "browser_tab", "browser_act")
# Never reached through a bridge, whatever its name (the launcher refuses them too).
PASSWORD_APP_NAMES = re.compile(r"keepass|bitwarden|vaultwarden|1password|enpass|proton-?pass|lastpass|dashlane|"
                                r"keeper|nordpass|roboform|passbolt|seahorse|kwallet|authenticator|authy", re.I)
APP_LABELS = {"discord": "Discord (Vesktop)", "slack": "Slack", "youtube-music": "YouTube Music",
              "actual": "Actual Budget"}
TARGET_RE = re.compile(r"^([a-z0-9][a-z0-9-]{0,31})(?::([A-Za-z0-9]{1,40}))?$")


# What speaks, pays or deletes in the user's name through a page: a click,
# submit or key on an element named so, or Enter (a submit) in a chat app's
# message box.
RISKY_TARGET = re.compile(r"\b(delete|remove|send|reply|post|pay|buy|purchase|order|checkout|unsubscribe|empty trash|"
                          r"erase|format|uninstall|transfer|supprimer|envoyer|r[ée]pondre|publier|payer|"
                          r"acheter|commander|l(ö|oe)schen|senden|antworten|bezahlen|kaufen|bestellen|x(ó|o)a|"
                          r"g(ử|u)i|thanh to(á|a)n|mua)\b", re.I)
CHAT_TARGETS = re.compile(r"^(discord|slack)(:|$)", re.I)


PAGE_ACTIONS = ["click", "type", "select", "check", "submit", "press", "focus", "scroll"]


def page_act_risky(args):
    """A page click/submit/key on a "Send", "Pay"… element, or Enter in a chat app."""
    action = str(args.get("action") or "")
    if action not in ("click", "submit", "press"):
        return False
    if RISKY_TARGET.search(str(args.get("name") or "")):
        return True
    key = str(args.get("value") or "Enter")
    return bool(CHAT_TARGETS.match(str(args.get("target") or ""))) and (
        action == "submit" or (action == "press" and re.search(r"(^|\+)\s*(enter|return)$", key, re.I) is not None
                               and not re.search(r"shift", key, re.I)))


ASK_TIMEOUT = 120


# -- the trust ladder ---------------------------------------------------------
# Each kind of action (a class: the tool, `:<action>` for the multi-purpose
# tools, `@<app>` for the window and input tools acting on an app —
# `media_control:pause`, `close_window@firefox`, `jellyfin__play`) is at one
# of three levels for the shell's own Claude sessions: `ask` (Allow /
# Always / No in the side panel or the bubble, before it runs), `tell` (done,
# then a "Did: …" line) or `silent`. Asked by default for what is risky,
# told for what acts, silent for what only reads. Three yeses in a row
# within TRUST_STREAK_DAYS, nothing refused since, and the user is offered
# to stop being asked (they decide: `trust set`, their click); a no brings
# it a step down and starts the count over. What sends, pays, deletes,
# merges or touches credentials is never offered past ask; the user may
# still raise it themselves (Always, or Settings), to tell at most.
# Claude Code's PreToolUse hook asks here (trust_gate, the helper's
# /trust): the desktop tools that ask the user themselves (ask_user_yes:
# what speaks, pays or deletes) aren't asked twice, and a kind the user
# let go (tell) isn't asked by them either. Their notification's "Always
# allow" is the same ladder: the one thing asked (its key, one Discord
# channel, one button on one site, as a class: key_class) set to tell, so
# Settings > Privacy & trust > Trust lists it and Ask takes it back. An
# agent never sets a level: `trust set` is the shell's (its helper's
# stdin) and the user's.
TRUST_LEVELS = ("ask", "tell", "silent")
TRUST_STREAK = 3
TRUST_STREAK_DAYS = 30
TRUST_CLASSES_MAX = 500
TRUST_ASK_TIMEOUT = 120
TRUST_CLASS = r"[\w.:@+-]{1,200}"
TRUST_NEVER = re.compile(r"(^|_)(delete|send|sms|reply|pay|payment|buy|purchase|checkout|credentials|merge|"
                         r"resolve_duplicates|wipe|purge)", re.I)
TRUST_NEVER_ACTION = re.compile(r"^(delete|send|reply|react|pay|purchase|merge|purge|credentials)", re.I)
TRUST_DOWN = {"silent": "tell", "tell": "ask", "ask": "ask"}
# The tools that both read and write say which with their `action`: these
# only read.
TRUST_READ_ACTIONS = {"list", "lists", "upcoming", "get", "search", "find", "show", "status", "layout", "day",
                      "events", "read", "next", "agenda", "info", "count", "check", "history", "channels", "guilds",
                      "dms", "members", "lookup", "query", "sessions", "playlists"}
# Another server's tool named for reading (search, list_…, …_details).
TRUST_READ_NAME = re.compile(r"^(list|get|search|find|show|status|read|query|fetch|lookup|describe|info|check|count|"
                             r"recall|view|browse|whoami|upcoming|current|now)(_|$)|_(list|get|search|find|status|info|"
                             r"details?|show|read|lookup)$|^(item|details|sessions|trending)$", re.I)
TRUST_RISKY_TOOL = re.compile(r"(^|_)(delete|remove|empty_trash|purge|wipe|clear|merge|resolve_duplicates|"
                              r"credentials|send|sms|reply|connect_with|partner|uninstall|format|buy|pay|purchase|cancel|decline|"
                              r"order)", re.I)
TRUST_RISKY_ACTION = re.compile(r"^(delete|remove|clear|purge|empty|reply|send|react)", re.I)
TRUST_HARMLESS_TOOL = re.compile(r"(queue|playlist|playback|volume|seek|repeat|shuffle)", re.I)
TRUST_IPC_RISKY = re.compile(r"^(delete|remove|clear|purge|empty|reply|send|react|invoke|forget|wipe)", re.I)
# The tools acting on an app: the app is part of the class ("typing in
# Firefox" and "typing in the terminal" are trusted apart).
TRUST_APP_TOOLS = {"launch_app", "close_window", "focus_window", "window_action", "move_window_to_workspace",
                   "set_aside", "ui_act", "type_text", "press_keys", "click", "drag", "scroll", "run_steps",
                   "run_recipe", "move_pointer"}


def trust_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "trust.json")


def empty_trust():
    return {"version": 1, "classes": {}}


class Trust(Memory):
    path = staticmethod(trust_path)
    empty = staticmethod(empty_trust)

    def migrate(self):
        if not isinstance(self.data.get("classes"), dict):
            self.data["classes"] = {}
            self.changed = True


def read_trust():
    try:
        with Trust() as t:
            return t.data["classes"]
    except OSError:
        return {}


def class_part(value, limit):
    """A piece of a class name: lower case, letters, digits, . _ - only."""
    return re.sub(r"[^a-z0-9._-]+", "-", str(value or "").strip().lower()).strip("-")[:limit]


def class_parts(cls):
    """(tool, action, app) of `tool:action@app`."""
    head, _, app = str(cls).partition("@")
    tool, _, action = head.partition(":")
    return tool, action, app


def action_class(tool, args, app=None):
    """A call's class: `media_control:pause`, `close_window@firefox`,
    `shell_ipc:reply@notifications`."""
    args = args if isinstance(args, dict) else {}
    cls = class_part(tool, 80) or "tool"
    if tool == "shell_ipc":
        fn, target = class_part(args.get("function"), 40), class_part(args.get("target"), 40)
        return cls + (":" + fn if fn else "") + ("@" + target if target else "")
    action = class_part(args.get("action"), 40)
    if action:
        cls += ":" + action
    if tool in TRUST_APP_TOOLS:
        who = app or (args.get("app") if isinstance(args.get("app"), str) else "")
        who = class_part(re.sub(r"\.desktop$", "", str(who or "").strip(), flags=re.I), 80)
        if who:
            cls += "@" + who
    return cls


def trust_reads(tool, args, desktop):
    """True for a call that only reads: a desktop tool marked read-only, a
    reading action, another server's tool named for reading."""
    args = args if isinstance(args, dict) else {}
    if desktop and (TOOLS.get(tool) or {}).get("read_only"):
        return True
    if str(args.get("action") or "").lower() in TRUST_READ_ACTIONS:
        return True
    return not desktop and bool(TRUST_READ_NAME.search(tool))


def trust_risky(tool, args):
    """What deletes, sends in the user's name, pays or touches credentials."""
    args = args if isinstance(args, dict) else {}
    if tool == "shell_ipc":
        return bool(TRUST_IPC_RISKY.match(str(args.get("function") or "")))
    if TRUST_HARMLESS_TOOL.search(tool):
        return False
    if TRUST_RISKY_TOOL.search(tool) or TRUST_RISKY_ACTION.match(str(args.get("action") or "")):
        return True
    if tool in ("browser_act", "page_act"):
        return page_act_risky(args)
    if tool in ("ui_act", "click", "notification_action"):
        return bool(RISKY_TARGET.search(" ".join(str(v) for v in args.values() if isinstance(v, str))))
    return False


def never_promote(cls):
    tool, action, _ = class_parts(cls)
    tool = tool.rpartition("__")[2]
    return bool(TRUST_NEVER.search(tool) or (action and TRUST_NEVER_ACTION.match(action)))


def trust_max(cls):
    """The highest level `trust set` accepts for this class: tell for what
    sends, pays, deletes… (each still said), else silent."""
    return "tell" if never_promote(cls) else "silent"


def trust_default(cls, risky=None):
    """(level, why) before the user said anything (risky: as the call
    says; else as its class says)."""
    if risky is None:
        tool, action, _ = class_parts(cls)
        risky = trust_risky(tool.rpartition("__")[2], {"action": action} if action else {})
    if risky or never_promote(cls):
        return "ask", "a risky step: asked each time"
    return "tell", "it acts: done, then said"


def trust_state(cls, e, risky=None, now=None):
    """(level, why, allows in the window, suggest promotion, user set)."""
    now = now or time.time()
    level, why = trust_default(cls, risky)
    if e.get("level") in TRUST_LEVELS:
        level, why = e["level"], e.get("why") or why
    if TRUST_LEVELS.index(level) > TRUST_LEVELS.index(trust_max(cls)) or (
            never_promote(cls) and level != "ask" and not e.get("userSet")):
        level, why = "ask", "never done without asking (it sends, pays, deletes, merges or touches credentials)"
    allows = [a for a in e.get("allows") or [] if isinstance(a, (int, float)) and now - a < TRUST_STREAK_DAYS * 86400]
    suggest = (level == "ask" and not never_promote(cls) and len(allows) >= TRUST_STREAK
               and not e.get("suggested"))
    return level, why, allows, suggest, bool(e.get("userSet"))


def trust_class(cls):
    cls = str(cls or "").strip()
    if not re.fullmatch(TRUST_CLASS, cls):
        raise ToolError("a class is `tool`, `tool:action` or `tool@app` (letters, digits, . _ - : @)")
    return cls


def trust_check(cls, risky=None):
    cls = trust_class(cls)
    level, why, allows, suggest, user = trust_state(cls, read_trust().get(cls) or {}, risky)
    return {"class": cls, "level": level, "why": why, "suggestPromote": suggest, "userSet": user,
            "default": trust_default(cls, risky)[0], "streak": len(allows)}


def trust_record(cls, outcome, now=None):
    """The user's answer to a step of this kind: {level, suggestPromote,
    streak}."""
    cls = trust_class(cls)
    if outcome not in ("allowed", "denied"):
        raise ToolError("trust record: allowed or denied")
    now = int(now or time.time())
    with Trust() as t:
        classes = t.data["classes"]
        e = classes.setdefault(cls, {})
        level, _, allows, _, _ = trust_state(cls, e, now=now)
        e["last"], e["lastOutcome"] = now, outcome
        if outcome == "allowed":
            e["allows"] = (allows + [now])[-TRUST_STREAK * 4:]
            level, _, allows, suggest, _ = trust_state(cls, e, now=now)
            if suggest:
                e["suggested"] = now  # offered once a streak
        else:
            # A step down, the count over: a no says it was too much.
            e["level"], e["why"], e["userSet"], e["allows"] = TRUST_DOWN[level], "you said no to one", False, []
            e.pop("suggested", None)
            e["denied"] = e.get("denied", 0) + 1
            level, allows, suggest = e["level"], [], False
        if len(classes) > TRUST_CLASSES_MAX:
            for old in sorted(classes, key=lambda k: classes[k].get("last", 0))[:len(classes) - TRUST_CLASSES_MAX]:
                classes.pop(old, None)
        t.save()
    return {"class": cls, "level": level, "suggestPromote": suggest, "streak": len(allows)}


def key_class(key):
    """The class of one thing ask_user_yes asks about (`discord:send:<channel>`,
    `page:<app>:<action>:<element>`): narrower than its tool's."""
    cls = re.sub(r"[^\w.:@+-]+", "-", str(key or "").strip().lower()).strip("-")[:200]
    return cls or None


def trust_set(cls, level, label=None):
    """The user's choice (Settings, Always, a "Stop asking" chip): never an agent's."""
    cls = trust_class(cls)
    if level not in TRUST_LEVELS:
        raise ToolError("trust set: ask, tell or silent")
    if TRUST_LEVELS.index(level) > TRUST_LEVELS.index(trust_max(cls)):
        raise ToolError(f"refused: {cls} sends, pays, deletes, merges or touches credentials: at most told after")
    with Trust() as t:
        e = t.data["classes"].setdefault(cls, {})
        e.update(level=level, userSet=True, why="you chose it", set=int(time.time()))
        if label:
            e["label"] = short(str(label), 200)
        e.pop("suggested", None)
        t.save()
    return {"class": cls, "level": level}


def trust_list():
    out = []
    for cls, e in read_trust().items():
        if not isinstance(e, dict) or not re.fullmatch(TRUST_CLASS, cls):
            continue
        level, why, allows, suggest, user = trust_state(cls, e)
        out.append({"class": cls, "level": level, "default": trust_default(cls)[0], "why": why, "streak": len(allows),
                    "last": e.get("last"), "userSet": user, "neverPromote": never_promote(cls),
                    "maxLevel": trust_max(cls), "suggestPromote": suggest,
                    "summary": e.get("label") or class_words(cls)})
    return sorted(out, key=lambda x: -(x["last"] or 0))


def class_words(cls):
    """A class in words: `close_window@firefox` → "close window in firefox",
    `jellyfin__play` → "jellyfin: play"."""
    tool, action, app = class_parts(cls)
    server, _, tool = tool.rpartition("__")
    out = (server + ": " if server else "") + tool.replace("_", " ")
    return out + (f": {action.replace('_', ' ')}" if action else "") + (f" in {app}" if app else "")


def trust_user_lets(cls):
    """True when the user themselves let this kind go without asking (tell
    or silent): the desktop tools' own asking (ask_user_yes) skips it too."""
    if not cls:
        return False
    try:
        e = read_trust().get(cls) or {}
    except (OSError, ValueError):
        return False
    return bool(e.get("userSet")) and trust_state(cls, e)[0] != "ask"


def step_words(tool, args):
    """A step as the user reads it: "discord (action=send, channel=…)"."""
    keys = ("app", "name", "action", "channel", "who", "title", "text", "content", "message", "query", "target",
            "function", "theme", "variant", "id", "workspace")
    bits = [f"{k}={short(str(args[k]), 40)}" for k in keys if isinstance(args, dict) and k in args]
    return tool.replace("_", " ") + (f" ({', '.join(bits)})" if bits else "")


_trust_waiting = {}
_trust_lock = threading.Lock()


def trust_answer(rid, allow):
    """The shell's answer to an approval (the user's click)."""
    with _trust_lock:
        slot = _trust_waiting.get(str(rid))
    if slot:
        slot["allow"] = allow is True
        slot["event"].set()


def trust_gate(event, send):
    """Claude Code's PreToolUse for the shell's sessions (the helper's
    /trust): None (it goes on) or the hook's answer. send: a line to the
    shell ({approval}, {told}, {trustSuggest}, {approvalExpired})."""
    if not isinstance(event, dict) or event.get("hook_event_name") != "PreToolUse":
        return None
    m = re.match(r"^mcp__(.+?)__(.+)$", str(event.get("tool_name") or ""))
    if not m:
        return None
    server, tool = m.groups()
    args = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
    desktop = server == "desktop"
    if desktop and tool not in TOOLS:
        tool, args = resolve_alias(tool, args)
    if trust_reads(tool, args, desktop):
        return None
    cls = action_class(tool, args) if desktop else f"{class_part(server, 40)}__{action_class(tool, args)}"
    risky = trust_risky(tool, args)
    info = trust_check(cls, risky)
    level = info["level"]
    # The desktop tools ask the user themselves before what speaks, pays or
    # deletes (a notification): not twice.
    if desktop and level == "ask" and not info["userSet"] and (risky or never_promote(cls)):
        return None
    shown = unmask_obj(args) if privacy_on() else args
    session = str(event.get("session_id") or "")
    if level == "silent":
        return None
    if level == "tell":
        send({"told": {"session": session, "class": cls, "summary": step_words(tool, shown)}})
        return None
    rid = secrets.token_hex(8)
    slot = {"event": threading.Event(), "allow": None}
    with _trust_lock:
        _trust_waiting[rid] = slot
    asked = time.time()
    send({"approval": {"id": rid, "session": session, "server": server, "tool": tool, "class": cls,
                       "summary": step_words(tool, shown)}})
    slot["event"].wait(TRUST_ASK_TIMEOUT)
    with _trust_lock:
        _trust_waiting.pop(rid, None)

    def deny(why):
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                       "permissionDecisionReason": why}}
    if slot["allow"] is None:
        send({"approvalExpired": rid})
        return deny("Not done: it waited for the user's OK, which didn't come. Ask them in your answer.")
    # Keys or a click from an agent while it waited: the yes may be its own.
    if slot["allow"] and agent_input_since(asked):
        return deny("Not done: an agent typed or clicked while the user was being asked, so the answer can't be "
                    "trusted. Ask again, with no input meanwhile.")
    try:
        got = trust_record(cls, "allowed" if slot["allow"] else "denied")
    except ToolError:
        got = {}
    if not slot["allow"]:
        return deny("Not done: the user said no. Don't try it again unless they ask you to.")
    if got.get("suggestPromote"):
        send({"trustSuggest": {"session": session, "class": cls, "summary": class_words(cls)}})
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                   "permissionDecisionReason": "the user allowed it"}}


def agent_environment():
    """True in a process an agent started (Claude Code's Bash: CLAUDECODE)."""
    return bool(os.environ.get("CLAUDECODE") or os.environ.get("CLAUDE_CODE_ENTRYPOINT"))


def trust_command(argv):
    sub = argv[0] if argv else "list"
    try:
        if sub == "check" and len(argv) >= 2:
            risky = None
            if "--risky" in argv:
                risky = argv[argv.index("--risky") + 1] == "1"
            print(json.dumps(trust_check(argv[1], risky)))
            return 0
        if sub == "set" and len(argv) == 3:
            if agent_environment():
                raise ToolError("refused: only the user sets how much an agent may do on its own")
            print(json.dumps(trust_set(argv[1], argv[2])))
            return 0
        if sub == "list":
            print(json.dumps(trust_list(), ensure_ascii=False))
            return 0
    except (ToolError, IndexError) as e:
        print(json.dumps({"error": str(e) or "trust: bad arguments"}, ensure_ascii=False))
        return 1
    print("usage: nixbook-desktop-mcp trust [list] | check CLASS [--risky 0|1] | set CLASS ask|tell|silent",
          file=sys.stderr)
    return 2


def ask_user_yes(ctx, title, body, key=None, label=None):
    """The user's own yes, asked in a notification (Allow / No; no answer in
    ASK_TIMEOUT seconds is a no), before what speaks, pays or deletes in
    their name: whatever the agent or its client says, they can't answer it
    for the user. key: the one thing asked (discord:send:<channel>…): the
    notification then offers Always allow too, which sets that one thing
    to tell on the trust ladder (key_class; label: how Settings names it),
    and it isn't asked again until the user sets it back to Ask. askBeforeSending
    false: not asked (a client that asks the user itself before each such
    call)."""
    if ctx.cfg.get("askBeforeSending", True) is False:
        return
    narrow = key_class(key) if key else None
    # The user let this thing, or this kind, go themselves (the trust
    # ladder: Always allow, Always, or Tell after in Settings).
    if trust_user_lets(narrow) or trust_user_lets(getattr(ctx, "trust_class", None)):
        return
    if not shutil.which("notify-send"):
        raise ToolError("not done: the user can't be asked (no notify-send), and this acts in their name")
    if privacy_on():
        # Asked with the real names (a chat app's reply hides people's).
        title, body = unmask_text(title), unmask_text(body)
        label = unmask_text(label) if label else label
    asked = time.time()
    try:
        out = subprocess.run(["notify-send", "-a", "Desktop agent", "-i", "dialog-question", "-u", "critical",
                              "-A", "allow=Allow", *(["-A", "always=Always allow"] if narrow else []),
                              "-A", "deny=No", "--", title, short(body, 600)],
                             capture_output=True, text=True, timeout=ASK_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise ToolError("not done: the user didn't answer the notification asking for their yes")
    except OSError as e:
        raise ToolError(f"not done: the user couldn't be asked ({e})")
    answer = out.stdout.strip()
    if answer not in ("allow", "always"):
        raise ToolError("not done: the user said no. Don't try again unless they ask you to")
    # Keys or a click from an agent while it waited: the yes may be its own.
    if agent_input_since(asked):
        raise ToolError("not done: an agent typed or clicked while the user was being asked, so the answer "
                        "can't be trusted. Ask again, with no input meanwhile")
    if answer == "always" and narrow:
        trust_set(narrow, "tell", label or title)


def zen_socket():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(base, "nixbook-zen", "bridge.sock")


def electron_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(base, "nixbook-electron")


def own_socket(path, missing):
    try:
        st = os.stat(path)
    except FileNotFoundError:
        raise ToolError(missing)
    if st.st_uid != os.getuid() or not stat.S_ISSOCK(st.st_mode):
        raise ToolError(f"{path} isn't this user's socket: not used")


def socket_request(path, request, gone):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(55)
    try:
        s.connect(path)
        s.sendall(json.dumps(request).encode() + b"\n")
        line = s.makefile("rb").readline(8 * 1024 * 1024)
    except (OSError, socket.timeout) as e:
        raise ToolError(f"{gone} ({e})")
    finally:
        s.close()
    try:
        reply = json.loads(line)
    except ValueError:
        raise ToolError(gone)
    if not reply.get("ok"):
        raise ToolError(str(reply.get("error") or "refused"))
    return reply.get("result")


def zen(ctx, cmd, **args):
    """One request to the extension: its result (ToolError when refused)."""
    path = zen_socket()
    own_socket(path, "Zen isn't running, or its nixbook extension isn't installed (nixbookShellConfig.zenAgent "
                     "with zenBrowserConfig): start Zen (launch_app) and try again")
    guard = ctx.cfg.get("browser") or {}
    request = {"cmd": cmd, **{k: v for k, v in args.items() if v is not None},
               "guard": {"sites": guard.get("blockedSites") or [], "containers": guard.get("blockedContainers") or []}}
    return socket_request(path, request, "the browser didn't answer: is Zen still running?")


def bridged_apps():
    """The apps whose bridge runs now (their sockets, this user's)."""
    try:
        names = sorted(os.listdir(electron_dir()))
    except OSError:
        return []
    out = []
    for n in names:
        app = n[:-5] if n.endswith(".sock") else ""
        if not TARGET_RE.match(app or "-"):
            continue
        with contextlib.suppress(OSError):
            st = os.stat(os.path.join(electron_dir(), n))
            if st.st_uid == os.getuid() and stat.S_ISSOCK(st.st_mode):
                out.append(app)
    return out


def unbridged_apps():
    """The bridged apps running without their bridge now (nixbook-electron-app's
    watcher writes them): {app: {pid, label, age, inCall}}."""
    path = os.path.join(electron_dir(), "unbridged.json")
    try:
        if time.time() - os.stat(path).st_mtime > 60:
            return {}  # the watcher isn't running: nothing known
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


UNBRIDGED_HINT = ("{label} runs without nixbook's bridge (started before it, or it restarted itself): the user got a "
                  "notification to restart it with the bridge (\"Restart with bridge\"); ask them to, never close or "
                  "restart it yourself. Meanwhile ui_read/ui_act or screenshots reach its window")


def ask_watcher(app):
    """The watcher tells the user again (at most every 10 minutes): an agent needs the app."""
    with contextlib.suppress(OSError):
        fd = os.open(os.path.join(electron_dir(), f"{app}.ask"), os.O_WRONLY | os.O_CREAT, 0o600)
        os.close(fd)


def app_refused(ctx, app):
    if PASSWORD_APP_NAMES.search(app):
        return True
    for rx in (ctx.cfg.get("pages") or {}).get("blockedApps") or []:
        with contextlib.suppress(re.error):
            if re.search(rx, app, re.I):
                return True
    return False


def electron(ctx, app, cmd, **args):
    """One request to an Electron app's bridge (nixbook-electron-app)."""
    if app_refused(ctx, app):
        raise ToolError(f"refused: {app} is off limits to the agents (pages.blockedApps); ask the user")
    label = APP_LABELS.get(app, app)
    path = os.path.join(electron_dir(), f"{app}.sock")
    if not os.path.exists(path) and app in unbridged_apps():
        ask_watcher(app)
        raise ToolError(UNBRIDGED_HINT.format(label=label))
    own_socket(path, f"{label} isn't reachable: it isn't running, or it was started before nixbook's bridge "
                     "(quit it completely, its tray icon too, and start it again from the launcher). page_list "
                     "lists what is reachable")
    request = {"cmd": cmd, **{k: v for k, v in args.items() if v is not None}}
    reply = socket_request(path, request, f"{label} didn't answer: is it still running?")
    if cmd == "app" and app in CHAT_PEOPLE_APPS and privacy_on():
        return mask_chat_people(reply)
    return reply


# The chat apps' adapters say which fields are people (a message's author,
# a member, a friend, a DM's @name): those are hidden whoever they are, not
# only the contacts the mask knows, and their names wherever else they
# appear in the same reply (a message mentioning them). A display name
# becomes a person (a stand-in name, or ⟦Person N⟧), a username a
# ⟦Handle N⟧ (the same as the one a contact's notes give). Bots aren't
# people. The rest of the reply is masked as usual (call_tool).
CHAT_PEOPLE_APPS = ("discord", "slack")
CHAT_PERSON_KEYS = ("author", "user")
CHAT_PEOPLE_LISTS = ("members", "friends", "users")


def mask_chat_people(reply):
    vocab = privacy_vocab()
    found = {}  # real value -> its token

    def known(v):
        # A contact (or already a placeholder): the usual mask's, so the
        # same person keeps one name.
        spans = privacy_spans(v, vocab)
        return "⟦" in v or (len(spans) == 1 and spans[0][0] == 0 and spans[0][1] == len(v))

    def person(v, m):
        v = " ".join(v.split()) if isinstance(v, str) else v
        if not isinstance(v, str) or len(v) < 2 or known(v):
            return v
        if v not in found:
            found[v] = m.token(("Person", "chat:" + fold(v), None, v, v))
        return found[v]

    def handle(v, m):
        if not isinstance(v, str) or len(v) < 2 or known(v):
            return v
        if v not in found:
            found[v] = m.token(("Handle", v.lower(), None, v))
        return found[v]

    def at_name(v, m):
        if isinstance(v, str) and v.startswith("@") and len(v) > 2:
            return "@" + person(v[1:], m)
        return v

    def fields(obj, m, listed=False):
        if isinstance(obj, list):
            return [fields(v, m, listed) for v in obj]
        if not isinstance(obj, dict):
            return obj
        bot = obj.get("bot") is True
        out = {}
        for k, v in obj.items():
            if bot and k in ("name", "username", "author"):
                out[k] = v
            elif k in CHAT_PERSON_KEYS and isinstance(v, str):
                out[k] = person(v, m)
            elif k == "username" and isinstance(v, str):
                out[k] = handle(v, m)
            elif k == "name" and isinstance(v, str):
                out[k] = person(v, m) if listed else at_name(v, m)
            elif isinstance(v, (dict, list)):
                out[k] = fields(v, m, listed or k in CHAT_PEOPLE_LISTS)
            else:
                out[k] = v
        return out

    with PrivacyMap() as m:
        masked = fields(reply, m)
    # Their names elsewhere in the reply (a message's text): as written,
    # whole words, a single common word left alone.
    names = sorted((v for v in found if v != found[v] and len(v) >= 3
                    and not (" " not in v and v.lower() in PRIVACY_NAME_WORDS)), key=len, reverse=True)
    if not names:
        return masked
    rx = re.compile(r"(?<![\w])(" + "|".join(re.escape(v) for v in names) + r")(?![\w])")
    tokens = set(found.values())

    def rest(obj):
        if isinstance(obj, str):
            return obj if obj in tokens or obj[1:] in tokens else rx.sub(lambda x: found[x.group()], obj)
        if isinstance(obj, list):
            return [rest(v) for v in obj]
        if isinstance(obj, dict):
            return {k: rest(v) for k, v in obj.items()}
        return obj
    return rest(masked)


def page_target(args):
    """(app, page) of the call's `target`: ("zen", tab id or None) or (app, page id or None)."""
    raw = args.get("target")
    raw = "zen" if raw in (None, "") else str(raw).strip().lower()
    m = TARGET_RE.match(raw)
    if not m:
        raise ToolError("`target`: zen, zen:<tab>, or an app (discord, slack…) from page_list")
    app, page = m.groups()
    if app == "zen":
        if page is not None and not page.isdigit():
            raise ToolError("`target`: zen:<tab id> (page_list gives them)")
        return "zen", int(page) if page else None
    return app, page


def page_call(ctx, args, cmd, **kw):
    app, page = page_target(args)
    if app == "zen":
        return app, zen(ctx, cmd, tab=page, **kw)
    return app, electron(ctx, app, cmd, page=page, **kw)


def page_site(ctx, args):
    """(key part, name) of the site a page call acts on, for a standing
    permission: a bridged app itself, a Zen tab's host; (None, None) when it
    can't be told (no single tab, a private one)."""
    app, page = page_target(args)
    if app != "zen":
        return app, APP_LABELS.get(app, app)
    try:
        tabs = zen(ctx, "tabs") or []
    except ToolError:
        return None, None
    found = [t for t in tabs if (str(t.get("id")) == page if page is not None else t.get("active"))]
    if len(found) != 1 or found[0].get("private"):
        return None, None
    host = (re.match(r"^[a-z][a-z0-9+.-]*://([^/:?#]+)", str(found[0].get("url") or ""), re.I) or [None, None])[1]
    return (f"zen:{host.lower()}", host.lower()) if host else (None, None)


def page_label(app, r):
    return f"zen:{r.get('tab')}" if app == "zen" else f"{app}:{r.get('page')}"


def zen_tab_line(t):
    bits = [f"zen:{t['id']}"] + (["(shown)"] if t.get("active") else [])
    if t.get("private"):
        bits.append(f"private: {t['private']}")
    else:
        bits.append(f"{short(t.get('title') or '', 90)!r} {short(t.get('url') or '', 160)}")
    for k, label in (("container", "container {}"), ("otherWorkspace", "other workspace"), ("pinned", "pinned"),
                     ("audible", "playing sound"), ("loading", "loading")):
        if t.get(k):
            bits.append("· " + label.format(t[k]))
    return " ".join(bits)


@tool(
    "page_list",
    "pages",
    "The pages you can read and use through the page itself: Zen's tabs (zen:<id>; private windows "
    "never, blocked sites listed as private) and the bridged apps' windows (discord, slack, "
    "youtube-music…). Each line starts with its target.",
    obj({"target": {"type": "string", "description": "Only zen, or one app"}}),
    read_only=True,
)
def t_page_list(ctx, args):
    only = page_target(args)[0] if args.get("target") else None
    lines = []
    if only in (None, "zen"):
        try:
            tabs = zen(ctx, "tabs") or []
            lines += [zen_tab_line(t) for t in tabs] or ["zen: no tabs"]
        except ToolError as e:
            if only == "zen":
                raise
            lines.append(f"zen: {short(str(e), 80)}")
    apps = [a for a in bridged_apps() if only in (None, a) and not app_refused(ctx, a)]
    if only not in (None, "zen") and only not in apps and only not in unbridged_apps():
        electron(ctx, only, "pages")  # says why it can't be reached
    for app in apps:
        try:
            pages = electron(ctx, app, "pages") or []
        except ToolError as e:
            lines.append(f"{app}: {short(str(e), 120)}")
            continue
        label = APP_LABELS.get(app, app) + {"discord": " (also the discord tool)",
                                            "actual": " (also the budget tool)"}.get(app, "")
        for p in pages:
            lines.append(f"{app if p.get('main') else app + ':' + str(p.get('id'))} {short(p.get('title') or '', 90)!r} "
                         f"{short(p.get('url') or '', 120)} · {label}")
        if not pages:
            lines.append(f"{app}: no window open · {label}")
    for app, u in sorted(unbridged_apps().items()):
        if app in apps or only not in (None, app) or app_refused(ctx, app):
            continue
        lines.append(f"{app}: unbridged · {UNBRIDGED_HINT.format(label=u.get('label') or APP_LABELS.get(app, app))}")
        apps.append(app)
    if only is None and not apps:
        lines.append("apps: none bridged now (Vesktop, Slack, YouTube Music… started from the launcher show here)")
    return [text("\n".join(lines))]


@tool(
    "page_go",
    "pages",
    "Open or move a page. Zen: `open` a `url` in a new tab (in the background unless `active`), "
    "`search` the web for `query` with Zen's own search engine (a new tab in the background: then "
    "page_read it), or on a tab `activate`, `navigate` (to `url`), `back`, `forward`, `reload`, `mute`, "
    "`unmute`, `close`. Apps: `back`, `forward`, `reload`.",
    obj({"target": {"type": "string", "description": "From page_list (default zen)"},
         "action": {"type": "string", "enum": ["open", "search", "activate", "navigate", "back", "forward", "reload",
                                               "mute", "unmute", "close"]},
         "url": {"type": "string"}, "query": {"type": "string"}, "active": {"type": "boolean"}}, ["action"]),
)
def t_page_go(ctx, args):
    action = as_str(args, "action", max_len=20)
    url = as_str(args, "url", max_len=2000, required=False) or None
    app, page = page_target(args)
    if app != "zen":
        r = electron(ctx, app, "go", page=page, action=action)
        return [text(f"{app}:{r.get('page')} now: {r.get('title')!r} {r.get('url')}")]
    if action == "search":
        query = as_str(args, "query", max_len=300)
        ctx.guard.check_text(query)
        return [text(zen_tab_line(zen(ctx, "search", query=query)))]
    if action == "open":
        if not url:
            raise ToolError("open needs `url`")
        return [text(zen_tab_line(zen(ctx, "open", url=url, active=bool(args.get("active")))))]
    r = zen(ctx, "tab", tab=page, action=action, url=url)
    if r and r.get("closed") is not None:
        return [text(f"closed zen:{r['closed']}")]
    return [text(zen_tab_line(r))]


def page_element_line(e):
    line = f"[{e['ref']}] {e['role']} {e.get('name')!r}"
    if e.get("password"):
        line += " (password: off limits)"
    if "value" in e:
        line += f" = {e['value']!r}"
    if e.get("checked") is not None:
        line += " (checked)" if e["checked"] else " (unchecked)"
    if e.get("selected"):
        line += " (selected)"
    if e.get("disabled"):
        line += " (disabled)"
    if e.get("options"):
        line += f" options: {', '.join(e['options'])}"
    if e.get("href"):
        line += f" → {e['href']}"
    if e.get("offscreen"):
        line += " (scrolled away)"
    return line


def page_changes_lines(c):
    """What an action changed in the page (page.js "changes"), for its reply."""
    if not isinstance(c, dict):
        return []
    if c.get("fresh"):
        return [f"A new page ({c.get('total')} elements): page_read it."]
    added, gone, new_text = c.get("appeared") or [], c.get("gone") or 0, c.get("newText") or []
    if not added and not gone and not new_text:
        return ["Nothing else changed on the page."]
    lines = []
    if added:
        more = (c.get("appearedTotal") or len(added)) - len(added)
        lines.append("Appeared:" + (f" (and {more} more: page_read)" if more > 0 else ""))
        lines += ["  " + page_element_line(e) for e in added]
    if gone:
        lines.append(f"Gone: {gone} element{'s' if gone != 1 else ''}.")
    if new_text:
        lines.append("New text: " + " · ".join(new_text))
    return lines


def page_read_lines(label, r):
    lines = [f"{label}: {r.get('title')!r} {r.get('url')}"]
    els = r.get("elements") or []
    lines.append(f"Elements ({len(els)} of {r.get('total')}):" if els else "No elements found.")
    lines += [page_element_line(e) for e in els]
    if r.get("selection"):
        lines.append(f"Selected text: {r['selection']!r}")
    if r.get("text"):
        more = r.get("textTotal", 0) - len(r["text"])
        lines.append("Text:\n" + r["text"] + (f"\n… ({more} more characters: `chars` for more)" if more > 0 else ""))
    return lines


TARGET_PROP = {"type": "string", "description": "A target from page_list: zen (the tab shown), zen:<tab>, discord, "
                                                "slack… (default zen)"}


@tool(
    "page_read",
    "pages",
    "Read a page through the page itself (a Zen tab or a bridged app's window, in the background "
    "too): title, address, text, and the elements you can act on, numbered: [ref] role 'name' = "
    "value (an element keeps its number while it stays on the page). With `query`, only the elements "
    "whose name has one of its words. Then page_act on a ref. Password fields show no value. Costs far "
    "less than a screenshot and is exact.",
    obj({"target": TARGET_PROP,
         "query": {"type": "string", "description": "Words: only the elements named so (a button, a field)"},
         "text": {"type": "boolean", "description": "The page's text too (default true)"},
         "chars": {"type": "integer", "description": "At most this much text (default 12000)"},
         "max": {"type": "integer", "description": "At most this many elements (default 150)"}}),
    read_only=True,
)
def t_page_read(ctx, args):
    app, r = page_call(ctx, args, "read", query=as_str(args, "query", max_len=200, required=False) or None,
                       text=args.get("text") is not False, chars=args.get("chars"), max=args.get("max"))
    return [text("\n".join(page_read_lines(page_label(app, r), r)))]


@tool(
    "page_act",
    "pages",
    "Act on an element of a page, in the page itself (no pointer, no keys: the user keeps working): "
    "`click`, `type` (`value` replaces the field's text, `append` adds it; rich editors too, e.g. a "
    "chat's message box), `select` (a list's option by its text), `check` (`value` \"false\" "
    "unchecks), `submit` (its form), `press` (a key: Enter, Escape, Shift+Enter…), `focus`, `scroll`. "
    "Give the element's `name` (as page_read showed it) and its `ref`; the name alone works when one "
    "element has it (no page_read first: \"click Save\"). If the page re-rendered, the element is "
    "found again by its name; several with that name, or none, it says so instead of guessing. The "
    "reply tells what appeared and went since, so you needn't read the page again. `steps` does "
    "several in a row in one call (each {ref?, name, action, value?, append?}; it stops at the first "
    "that fails). Password fields are refused. In a chat app, Enter in the message box sends it: the "
    "discord tool is plainer for messages. A click, submit or key that sends, pays or deletes (Send, "
    "Pay, Delete…; Enter in Discord's or Slack's message box) waits for the user's yes (Allow / No): "
    "say what it does first.",
    obj({"target": TARGET_PROP, "ref": {"type": "integer"},
         "name": {"type": "string", "description": "The element's name, as page_read listed it"},
         "action": {"type": "string", "enum": PAGE_ACTIONS},
         "value": {"type": "string"}, "append": {"type": "boolean"},
         "steps": {"type": "array", "maxItems": 10, "items": obj(
             {"ref": {"type": "integer"}, "name": {"type": "string"},
              "action": {"type": "string", "enum": PAGE_ACTIONS},
              "value": {"type": "string"}, "append": {"type": "boolean"}}, ["name", "action"])}}),
    destructive=True,
)
def t_page_act(ctx, args):
    steps = args.get("steps")
    if steps is None:
        return page_act_one(ctx, args, args)
    if not isinstance(steps, list) or not 1 <= len(steps) <= 10 or not all(isinstance(x, dict) for x in steps):
        raise ToolError("`steps`: 1 to 10 actions, each {ref?, name, action, value?, append?}")
    done = []
    for i, step in enumerate(steps, 1):
        try:
            out = page_act_one(ctx, {"target": args.get("target"), **step}, step, changes=i == len(steps))
        except ToolError as e:
            done.append(f"step {i} failed: {e}" + ("; nothing after it was done" if i < len(steps) else ""))
            raise ToolError("\n".join(done))
        done.append(f"step {i}: {out[0]['text']}")
    return [text("\n".join(done))]


def page_act_one(ctx, args, step, changes=True):
    """One page_act action (args: it with its target)."""
    if not isinstance(step.get("name"), str) or not step["name"].strip():
        raise ToolError("`name`: the element's name, as page_read listed it")
    if step.get("action") not in PAGE_ACTIONS:
        raise ToolError("`action`: " + ", ".join(PAGE_ACTIONS))
    value = args.get("value")
    if isinstance(value, str):
        ctx.guard.check_text(value)
    ctx.guard.check_rate()
    if page_act_risky(args):
        target = str(args.get("target") or "zen")
        action, name = as_str(args, 'action', max_len=20), as_str(args, 'name', max_len=200)
        site, where = page_site(ctx, args)
        ask_user_yes(ctx, f"Let the agent {action} \u201c{name}\u201d "
                     f"in {'Zen' if page_target(args)[0] == 'zen' else APP_LABELS.get(page_target(args)[0], target)}?",
                     "It acts in your name (it may send, pay or delete).",
                     key=site and f"page:{site}:{action}:{' '.join(name.lower().split())}",
                     label=f"{action.capitalize()} \u201c{name}\u201d on {where}")
    ref = args.get("ref")
    app, r = page_call(ctx, args, "act", ref=as_int(args, "ref") if ref is not None else None,
                       name=as_str(args, "name", max_len=200),
                       action=as_str(args, "action", max_len=20), value=value if isinstance(value, str) else None,
                       append=bool(args.get("append")))
    el = r.get("element")
    after = (f"{el['role']} {el.get('name')!r}" + (f" = {el['value']!r}" if "value" in el else "")
             + ("" if el.get("checked") is None else (" (checked)" if el["checked"] else " (unchecked)"))) if el \
        else "(the element is gone: the page changed)"
    which = f"[{r['ref']}] " if r.get("ref") else ""
    note = f" (the page had re-rendered: found by its name, now [{r['ref']}])" if r.get("refound") else ""
    lines = [f"done ({r.get('done')}): {which}{after}{note}. {page_label(app, r)} now: {r.get('title')!r} {r.get('url')}"]
    if changes:
        lines += page_changes_lines(r.get("changes"))
    return [text("\n".join(lines))]


@tool(
    "page_history",
    "pages",
    "Search the user's Zen history or bookmarks (`kind`), newest first: a page they saw or saved, by "
    "words of its title or address (`query`; empty: the latest). Sites agents may not use are left "
    "out. Then page_go open its url.",
    obj({"query": {"type": "string"}, "kind": {"type": "string", "enum": ["history", "bookmarks"]},
         "max": {"type": "integer", "description": "At most this many (default 15, at most 50)"}}),
    read_only=True,
)
def t_page_history(ctx, args):
    if (ctx.cfg.get("browser") or {}).get("history", True) is False:
        raise ToolError("reading Zen's history and bookmarks is off (browser.history in desktop-mcp.json)")
    kind = as_str(args, "kind", max_len=20, required=False) or "history"
    if kind not in ("history", "bookmarks"):
        raise ToolError("`kind`: history or bookmarks")
    r = zen(ctx, "history", kind=kind, query=as_str(args, "query", max_len=200, required=False) or "",
            max=max(1, min(50, int(args.get("max") or 15)))) or []
    if not r:
        return [text(f"nothing in the {kind} matches")]
    lines = []
    for it in r:
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(it["when"] / 1000)) if it.get("when") else ""
        visits = f", {it['visits']} visits" if it.get("visits") else ""
        lines.append(f"- {it.get('title')!r} {it.get('url')} ({when}{visits})" if when or visits
                     else f"- {it.get('title')!r} {it.get('url')}")
    return [text("\n".join(lines))]


@tool(
    "page_wait",
    "pages",
    "Wait in a page until it has loaded (`until` load), its text shows `text` (`until` text) or its "
    "address contains `text` (`until` url), at most `timeout_ms` (default 10000).",
    obj({"target": TARGET_PROP, "until": {"type": "string", "enum": ["load", "text", "url"]},
         "text": {"type": "string"}, "timeout_ms": {"type": "integer"}}, ["until"]),
    read_only=True,
)
def t_page_wait(ctx, args):
    app, r = page_call(ctx, args, "wait", until=as_str(args, "until", max_len=10),
                       text=as_str(args, "text", max_len=300, required=False) or None,
                       timeout=max(100, min(30000, int(args.get("timeout_ms") or 10000))))
    if not r.get("ok"):
        return [text(f"not yet: {page_label(app, r)} still isn't there (timed out)")]
    return [text(f"there: {page_label(app, r)}: {r.get('title')!r} {r.get('url')}")]


@tool(
    "page_screenshot",
    "pages",
    "A picture of a page (a Zen tab or an app's window, without showing it), for what text doesn't "
    "tell (layout, pictures). page_read is cheaper and exact for text and controls.",
    obj({"target": TARGET_PROP}),
    read_only=True,
)
def t_page_screenshot(ctx, args):
    app, r = page_call(ctx, args, "screenshot")
    data = str(r.get("data") or "")
    if not data.startswith("data:image/"):
        raise ToolError("the page gave no picture")
    path = os.path.join(runtime_dir(), f"screenshot-{secrets.token_hex(4)}.jpg")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(base64.b64decode(data.split(",", 1)[1]))
    return screenshot_reply(ctx, path, f"{page_label(app, r)}: {r.get('title')!r} {r.get('url')}")


# The browser_* tools of before: still callable (saved routines, recipes and
# memory name them), not offered; they are the page tools on Zen.
TOOL_ALIASES = {"browser_tabs": "page_list", "browser_open": "page_go", "browser_tab": "page_go",
                "browser_read": "page_read", "browser_act": "page_act", "browser_wait": "page_wait",
                "browser_screenshot": "page_screenshot",
                # Project contexts, by the names they were first asked for.
                "context_list": "project", "context_open": "project", "context_save": "project",
                "project_list": "project", "project_open": "project", "project_save": "project"}


def resolve_alias(name, args):
    if name not in TOOL_ALIASES:
        return name, args
    if not name.startswith("browser_"):
        # context_open {name} → project {action: open, name}; *_save with
        # pause: true → pause.
        a = dict(args)
        verb = name.split("_", 1)[1]
        a["action"] = "pause" if verb == "save" and a.pop("pause", False) is True else verb
        return TOOL_ALIASES[name], a
    a = dict(args)
    tab = a.pop("tab", None)
    a["target"] = f"zen:{tab}" if isinstance(tab, int) and not isinstance(tab, bool) else "zen"
    if name == "browser_open":
        a["action"] = "open"
    return TOOL_ALIASES[name], a
