# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The tool registry (@tool, schemas, replies), status, windows and workspaces.

# Tools
# --------------------------------------------------------------------------

TOOLS = {}


# Tools that change something; they can return a screenshot of the result.
ACTION_GROUPS = ("windows", "input")


AFTER_PROPS = {
    "screenshot_after": {
        "type": "boolean",
        "description": "Also return a screenshot of the focused monitor after the action, "
        "to check the result without another call",
    },
    "wait_ms": {"type": "integer", "description": "Wait this long before that screenshot (at most 5000 ms) instead "
                "of until the screen stops changing (the default, at most 2.5 s)"},
}


# What the model is sent of AFTER_PROPS: the same, bare (the full text in
# the guide).
AFTER_PROPS_BRIEF = {"screenshot_after": {"type": "boolean"}, "wait_ms": {"type": "integer"}}
HELP_PROP = {"type": "boolean", "description": "true: the tool's full guide instead of running it"}

# The tools Claude Code loads up front (`_meta["anthropic/alwaysLoad"]`):
# what most requests need, so they need no ToolSearch round trip first. The
# others (and every connector's) stay deferred behind ToolSearch, found
# when a task needs them; tool_help reads any tool's guide meanwhile.
CORE_TOOLS = {
    "get_status", "list_windows", "list_workspaces", "list_apps", "launch_app", "focus_window", "close_window",
    "focus_workspace", "move_window_to_workspace", "window_action", "press_keys", "type_text", "click", "scroll",
    "run_steps", "screenshot", "ui_read", "ui_act", "notifications", "recall", "remember", "recall_about_user",
    "remember_about_user", "page_list", "page_read", "page_act", "page_go", "list_themes", "set_theme",
    "machine_help", "tool_help", "read_document",
}


def brief_schema(schema, props):
    """The schema the model is sent: `props` {name: a shorter description,
    or None for none} over a copy (the full one stays for the guide)."""
    out = json.loads(json.dumps(schema))
    for k, desc in (props or {}).items():
        p = out.get("properties", {}).get(k)
        if p is None:
            continue
        if desc is None:
            p.pop("description", None)
        else:
            p["description"] = desc
    return out


def tool(name, group, description, schema=None, *, read_only=False, destructive=False, title=None, brief=None,
         props=None, hidden=False):
    """brief: the description the model is sent, when `description` is
    long: `description` (and the schema's full argument descriptions)
    become the tool's guide, returned by `help: true` and tool_help, so
    trimming loses nothing. props: shorter argument descriptions. hidden:
    callable (a run_steps step, a recipe's) but not offered in tools/list."""
    schema = schema or {"type": "object", "properties": {}}
    full = schema
    if group in ACTION_GROUPS:
        full = dict(schema)
        full["properties"] = {**schema.get("properties", {}), **AFTER_PROPS}
        schema = dict(schema)
        schema["properties"] = {**schema.get("properties", {}), **AFTER_PROPS_BRIEF}
    shown = brief_schema(schema, props) if props else schema
    if brief:
        shown = dict(shown)
        shown["properties"] = {**shown.get("properties", {}), "help": HELP_PROP}

    def register(fn):
        meta = {"nixbook/group": group}
        if name in CORE_TOOLS:
            meta["anthropic/alwaysLoad"] = True
            meta["nixbook/core"] = True
        TOOLS[name] = {
            "fn": fn,
            "group": group,
            "read_only": read_only,
            "hidden": hidden,
            # The whole guide (help: true, tool_help): what the description was.
            "guide": (description, full) if brief or props or full is not schema else None,
            "spec": {
                "name": name,
                "title": title or name.replace("_", " ").capitalize(),
                "description": (brief.rstrip() + " help: true → its full guide.") if brief else description,
                "inputSchema": shown,
                "annotations": {
                    "readOnlyHint": read_only,
                    "destructiveHint": destructive,
                    "openWorldHint": False,
                },
                # observe: looks at windows and apps; screen: sees the screen
                # or clipboard (private data leaves for the model); windows,
                # input, shell: act. Clients can base their approvals on it.
                # Core: loaded up front by Claude Code.
                "_meta": meta,
            },
        }
        return fn

    return register


def guide_text(name):
    """A tool's full guide: its whole description and every argument's."""
    t = TOOLS[name]
    description, schema = t["guide"] or (t["spec"]["description"], t["spec"]["inputSchema"])
    lines = [f"{name}: {description}"]
    props = (schema or {}).get("properties") or {}
    required = set((schema or {}).get("required") or [])
    if props:
        lines += ["", "Arguments:"]
        for k, p in props.items():
            kind = p.get("enum") and "one of " + ", ".join(map(str, p["enum"])) or p.get("type") or "any"
            if isinstance(kind, list):
                kind = " or ".join(kind)
            line = f"- {k} ({kind}{', required' if k in required else ''})"
            if p.get("description"):
                line += f": {p['description']}"
            if p.get("properties"):
                line += " {" + ", ".join(p["properties"]) + "}"
            lines.append(line)
    return "\n".join(lines)


def text(value):
    # Compact: a reply goes to a model, and indentation is tokens for nothing.
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False)
    return {"type": "text", "text": value}


def obj(props, required=()):
    return {"type": "object", "properties": props, "required": list(required), "additionalProperties": False}


INT = {"type": "integer"}
WS = {
    "type": ["integer", "string"],
    "description": "Workspace index on its monitor (1, 2, …) or workspace name",
}


@tool(
    "get_status",
    "observe",
    "Desktop control status: paused or not, the tool groups enabled, the "
    "focused window, the pointer backend, which helpers are installed. Only "
    "needed when something doesn't work.",
    read_only=True,
)
def t_get_status(ctx, args):
    focused = None
    try:
        focused = focused_window()
    except ToolError:
        pass
    try:
        paused = is_paused()
    except ToolError as e:
        paused = str(e)
    try:
        VirtualPointer().close()
        pointer = "virtual pointer (exact)"
    except WaylandError as e:
        pointer = f"ydotool (approximate): {e}"
    return [
        text(
            {
                "paused": paused,
                "pointer": pointer,
                "enabled_groups": ctx.cfg["tools"],
                "focused_window": focused and slim_window(focused),
                "helpers": {h: bool(shutil.which(h)) for h in ["niri", "grim", "wtype", "ydotool", "wl-copy"]},
                "niri_socket": bool(os.environ.get("NIRI_SOCKET")),
            }
        )
    ]


def slim_window(w):
    s = {
        "id": w.get("id"),
        "app_id": w.get("app_id"),
        "title": w.get("title"),
        "workspace_id": w.get("workspace_id"),
        "focused": w.get("is_focused", False),
        "floating": w.get("is_floating", False),
    }
    # niri's layout (recent niri): the window's size, a floating window's
    # position on its monitor, a tiled one's column and place in it (niri
    # gives no position for tiled windows).
    layout = w.get("layout") or {}
    if layout.get("window_size"):
        s["size"] = layout["window_size"]
    if s["floating"] and layout.get("tile_pos_in_workspace_view"):
        s["position"] = [round(v) for v in layout["tile_pos_in_workspace_view"]]
    if layout.get("pos_in_scrolling_layout"):
        s["column"], s["tile"] = layout["pos_in_scrolling_layout"]
    return s


@tool(
    "list_windows",
    "observe",
    "List the open windows: id, app_id, title, workspace (index, name, "
    "monitor), focused, floating. Use the ids with the window tools.",
    read_only=True,
)
def t_list_windows(ctx, args):
    wss = {w["id"]: w for w in niri_json("workspaces")}
    out = []
    for w in windows():
        s = slim_window(w)
        ws = wss.get(w.get("workspace_id"))
        if ws:
            s["workspace"] = {"index": ws.get("idx"), "name": ws.get("name"), "monitor": ws.get("output")}
        out.append(s)
    return [text(out)]


@tool(
    "list_workspaces",
    "observe",
    "List the workspaces (index, name, monitor, active, focused) and the "
    "monitors with their position and size in logical pixels.",
    read_only=True,
)
def t_list_workspaces(ctx, args):
    wss = [
        {
            "id": w.get("id"),
            "index": w.get("idx"),
            "name": w.get("name"),
            "monitor": w.get("output"),
            "active": w.get("is_active"),
            "focused": w.get("is_focused"),
            "active_window_id": w.get("active_window_id"),
        }
        for w in niri_json("workspaces")
    ]
    outputs = {}
    for name, o in (niri_json("outputs") or {}).items():
        lg = o.get("logical") or {}
        outputs[name] = {k: lg.get(k) for k in ["x", "y", "width", "height", "scale"]}
    return [text({"workspaces": sorted(wss, key=lambda w: (w["monitor"] or "", w["index"] or 0)), "monitors": outputs})]


# -- Find it: universal recall -------------------------------------------------
# "That speech PDF I downloaded Monday", "the link Alex sent about dinner",
# "what did I ask DAI yesterday": one search, on this computer and
# without a model, over what the user saw and kept — recent files
# (Downloads, Documents, Desktop, the screenshots; their names, and the text
# of small text files and PDFs), Zen's history and bookmarks, the clipboard
# history, the notification history and the conversations with DAI — ranked as the memory's notes are
# (note_score: accents and case folded), the time words of the request
# (today, Monday, last week… in English, French, German and Vietnamese) a
# range. Never a secret (a code, a key, a password manager's or a bank's,
# a file named like one), nor a hidden folder of the home or the home
# itself; Zen's sites agents may not use left out. The launcher's find
# prefix shows the same (`nixbook-desktop-mcp find`).
