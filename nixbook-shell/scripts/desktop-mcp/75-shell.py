# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The shell: desktop widgets, notes, wallpaper, screen capture, settings.

# The shell's desktop widgets (DesktopWidgets.qml, Notes.qml, Todo.qml,
# TimerService.qml IPC targets): widget -> action -> (target, function, the
# arguments it takes, whether it changes something).
WIDGET_ACTIONS = {
    "notes": {
        "list": ("notes", "listToFile", (), False),
        "add": ("notes", "addFromFile", ("text",), True),
        "update": ("notes", "updateFromFile", ("id", "text"), True),
        "remove": ("notes", "remove", ("id",), True),
        "open": ("notes", "open", ("note",), True),
    },
    "todo": {
        "list": ("todo", "list", (), False),
        "add": ("todo", "add", ("text",), True),
        "done": ("todo", "done", ("index",), True),
        "undone": ("todo", "undone", ("index",), True),
        "remove": ("todo", "remove", ("index",), True),
    },
    "timers": {
        "status": ("timers", "status", (), False),
        "pomodoro_toggle": ("timers", "pomodoroToggle", (), True),
        "pomodoro_reset": ("timers", "pomodoroReset", (), True),
        "stopwatch_toggle": ("timers", "stopwatchToggle", (), True),
        "stopwatch_lap": ("timers", "stopwatchLap", (), True),
        "stopwatch_reset": ("timers", "stopwatchReset", (), True),
        "countdown_add": ("timers", "countdownAdd", ("minutes",), True),
        "countdown_toggle": ("timers", "countdownToggle", (), True),
        "countdown_reset": ("timers", "countdownReset", (), True),
        "countdown_dismiss": ("timers", "countdownDismiss", (), True),
        "alarm_set": ("timers", "alarmSet", ("when", "label", "daily"), True),
        "alarm_toggle": ("timers", "alarmToggle", (), True),
        "alarm_clear": ("timers", "alarmClear", (), True),
        "alarm_dismiss": ("timers", "alarmDismiss", (), True),
        "alarm_snooze": ("timers", "alarmSnooze", (), True),
    },
    # The custom images (DesktopWidgets.qml `images` target).
    "images": {
        "list": ("images", "list", (), False),
        "add": ("images", "add", ("path", "monitor"), True),
        "remove": ("images", "remove", ("image",), True),
        "set": ("images", "set", ("image", "key", "value"), True),
        "recenter": ("images", "recenter", ("image",), True),
        "monitors": ("images", "monitors", ("image", "monitors"), True),
    },
}
WIDGET_NAMES = {"note": "notes", "todos": "todo", "todolist": "todo", "task": "todo", "tasks": "todo",
                "timer": "timers", "pomodoro": "timers", "stopwatch": "timers", "countdown": "timers", "alarm": "timers",
                "image": "images", "customimage": "images", "customimages": "images", "picture": "images",
                "pictures": "images", "photo": "images", "photos": "images"}


# The notes' functions that take a transfer file (services/Notes.qml): only
# through the widget tool, which writes and reads those files itself.
NOTES_FILE_FUNCTIONS = {"addFromFile", "updateFromFile", "listToFile"}

# The shell's IPC functions that take a picture's path: only through the
# tools that check it is an image in a folder the user shares with agents
# (shared_image), not any file of theirs. images.set only with key "path".
IPC_IMAGE_PATH_FUNCTIONS = {("wallpapers", "apply"): "set_wallpaper", ("images", "add"): "widget",
                            ("images", "set"): "widget"}


def notes_call(fn, *args):
    """A notes call, the text going through a private file: a large IPC
    argument or reply can wedge the shell's IPC. add/update: the last
    argument (the text) is written to the file; list: the shell writes it."""
    path = os.path.join(runtime_dir(), f"notes-{secrets.token_hex(8)}.{'json' if fn == 'listToFile' else 'txt'}")
    try:
        if fn != "listToFile":
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(args[-1])
            args = args[:-1]
        out = widget_call("notes", fn, *args, path)
        if fn == "listToFile":
            with open(path, encoding="utf-8") as f:
                return f.read()
        return out
    except OSError as e:
        raise ToolError(f"notes: {e}")
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def widget_call(target, fn, *args):
    out = qs_ipc("call", "--", target, fn, *args).stdout.strip()
    if not out:
        raise ToolError("the desktop shell didn't answer (is nixbook-shell running?)")
    if out.startswith("error:"):
        raise ToolError(out[6:].strip())
    return out


def shared_folders():
    """The folders the user shares with AI agents (shell settings
    ai.allowedFolders, read, and ai.writableFolders, written by DAI),
    resolved; the home itself and / never count."""
    path = os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "nixbook-shell", "config.json")
    try:
        with open(path, encoding="utf-8") as f:
            ai = (json.load(f) or {}).get("ai") or {}
    except (OSError, ValueError):
        return []
    home = os.path.realpath(os.path.expanduser("~"))
    out = []
    for key in ("allowedFolders", "writableFolders"):
        for folder in ai.get(key) or []:
            if not isinstance(folder, str) or not folder.strip():
                continue
            folder = folder.strip()
            if folder == "~" or folder.startswith("~/"):
                folder = os.path.expanduser(folder)
            if not os.path.isabs(folder):
                continue
            real = os.path.realpath(folder)
            # Never a folder holding the home, nor a hidden one of it
            # (settings, keys).
            if (home + os.sep).startswith(real.rstrip(os.sep) + os.sep) or real.startswith(home + os.sep + "."):
                continue
            if real not in out:
                out.append(real)
    return out


# The image types the wallpaper script handles, by their first bytes.
def image_kind(head):
    if head[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    if head[4:8] == b"ftyp" and head[8:12] in (b"avif", b"avis"):
        return "avif"
    return None


def shared_image(want, fallback):
    """The real path of `want`, an image file (JPEG, PNG, WebP, AVIF) in a
    folder the user shares with agents; else a ToolError. `fallback`: how the
    user can do it themselves, when no folder is shared."""
    if re.match(r"(?i)^[a-z][a-z0-9+.-]*://", want):
        raise ToolError("that's a web address: download the image into a shared folder first, then give its path")
    path = os.path.realpath(os.path.expanduser(want))
    folders = shared_folders()
    if not folders:
        raise ToolError("the user shares no folder with agents: ask them to add one in Settings > Assistant > DAI in the side panel "
                        f"(e.g. a writable ~/Pictures/Assistant), or to {fallback}")
    if not any(path == f or path.startswith(f + os.sep) for f in folders):
        raise ToolError(f"refused: {want} isn't in a folder the user shares with agents ({', '.join(folders)})")
    try:
        st = os.stat(path)
        with open(path, "rb") as f:
            head = f.read(16)
    except OSError as e:
        raise ToolError(f"can't read {want}: {e.strerror}")
    if not stat.S_ISREG(st.st_mode):
        raise ToolError(f"{want} isn't a file")
    if st.st_size > 200 * 1024 * 1024:
        raise ToolError(f"{want} is over 200 MB")
    if not image_kind(head):
        raise ToolError(f"{want} isn't a JPEG, PNG, WebP or AVIF image")
    return path


@tool(
    "set_wallpaper",
    "shell",
    "Set the user's wallpaper to an image file on their computer (JPEG, PNG, "
    "WebP, AVIF), from a folder they share with agents (Settings > Assistant > "
    "DAI in the side panel: the folders agents may read or write; what your desktop's "
    "browser downloads lands in the first writable one). The palette "
    "follows, as when the user picks it with Mod+W. A web address won't do: "
    "download the image first.",
    obj({"path": {"type": "string", "description": "Absolute path (or ~/…) of the image"}}, ["path"]),
)
def t_set_wallpaper(ctx, args):
    path = shared_image(as_str(args, "path", max_len=1024), "set the wallpaper with Mod+W")
    ctx.guard.check_rate()
    qs_ipc("call", "--", "wallpapers", "apply", path)
    return [text(f"wallpaper set to {path}; the palette follows in a few seconds")]



def shell_setting(path, default):
    """A value of the shell's settings (config.json), by dotted path."""
    try:
        with open(os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "nixbook-shell", "config.json"), encoding="utf-8") as f:
            value = json.load(f)
        for key in path.split("."):
            value = value[key]
        return value if value not in (None, "") else default
    except (OSError, ValueError, KeyError, TypeError):
        return default


def capture_geometry(args):
    """grim's target for screen_capture: {window_id} (a floating window
    exactly, a tiled one with its monitor), {region}, or {monitor} (default:
    the focused one). Returns (grim arguments, what, the region "X,Y WxH" or
    monitor name for a recording)."""
    outputs = {n: o for n, o in (niri_json("outputs") or {}).items() if o.get("logical")}
    if args.get("window_id") is not None:
        wid = as_int(args, "window_id")
        w = window_by_id(wid)
        ws = next((x for x in niri_json("workspaces") if x.get("id") == w.get("workspace_id")), None)
        if not (ws and ws.get("is_active") and ws.get("output") in outputs):
            raise ToolError(f"window {wid} isn't on screen: focus it first")
        lg = outputs[ws["output"]]["logical"]
        layout = w.get("layout") or {}
        pos, size = layout.get("tile_pos_in_workspace_view"), layout.get("window_size")
        if w.get("is_floating") and pos and size:
            off = layout.get("window_offset_in_tile") or [0, 0]
            args = {"region": {"x": lg["x"] + pos[0] + off[0], "y": lg["y"] + pos[1] + off[1], "width": size[0], "height": size[1]}}
        else:
            args = {"monitor": ws["output"]}
    if args.get("region") is not None:
        r = args["region"]
        if not isinstance(r, dict):
            raise ToolError("`region` must be {x, y, width, height}")
        x, y = point(r)
        w, h = point(r, "width", "height")
        x, y, w, h = round(x), round(y), round(w), round(h)
        bx, by, bw, bh = desktop_bbox()
        x, y = max(x, bx), max(y, by)
        w, h = min(w, bx + bw - x), min(h, by + bh - y)
        if w < 4 or h < 4:
            raise ToolError(f"`region` must be at least 4x4 logical pixels on the desktop ({bx},{by} {bw}x{bh})")
        geometry = f"{x},{y} {w}x{h}"
        return ["-g", geometry], f"region {geometry}", geometry
    name = as_str(args, "monitor", required=False, max_len=64, pattern=r"[\w.\-]+")
    if not name:
        name = (niri_json("focused-output") or {}).get("name")
    if name not in outputs:
        raise ToolError(f"no monitor {name!r}; monitors: {', '.join(outputs)}")
    return ["-o", name], f"monitor {name}", name


@tool(
    "set_aside",
    "windows",
    "Hide something of the shell that is over the apps and in your way "
    "while you work (your screenshots and actions say when they are on "
    "screen; it comes back for the user a few seconds after your last "
    "action, nothing is dismissed): notificationPopups, cutIn (a theme's "
    "full-screen alert), speechBubble (DAI's bubble). Rarely needed: they "
    "let your clicks and keys through and are hidden from your screenshots "
    "already. Never the sidePanel (the user's chat with you), the lock "
    "screen or a password prompt.",
    obj({"name": {"type": "string", "enum": ["notificationPopups", "cutIn", "speechBubble"]}}, ["name"]),
)
def t_set_aside(ctx, args):
    name = as_str(args, "name", max_len=32)
    ctx.guard.check_rate()
    return [text(widget_call("makeWay", "setAside", name).removeprefix("ok:").strip())]


@tool(
    "screen_capture",
    "screen",
    "Screenshots and screen recordings for the user (to look at the screen "
    "yourself, use `screenshot`). screenshot {monitor | region | window_id, "
    "to: file (default), clipboard or both}: full resolution, saved where "
    "the shell saves screenshots (its path in the reply). record_start "
    "{monitor | region, sound?}: records the user's screen (default: the "
    "focused monitor; sound: the desktop audio, off unless asked) with the "
    "shell's recorder, its indicator showing; record_stop: ends it and gives "
    "the video's path; record_status.",
    obj({
        "action": {"type": "string", "enum": ["screenshot", "record_start", "record_stop", "record_status"]},
        "monitor": {"type": "string", "description": "Monitor name (see list_workspaces)"},
        "region": {
            "type": "object",
            "description": "A desktop rectangle in logical pixels",
            "properties": {"x": COORD, "y": COORD, "width": COORD, "height": COORD},
            "required": ["x", "y", "width", "height"],
        },
        "window_id": {"type": "integer", "description": "screenshot: a window on screen (see list_windows)"},
        "to": {"type": "string", "enum": ["file", "clipboard", "both"]},
        "sound": {"type": "boolean", "description": "record_start: with the desktop audio"},
    }, ["action"]),
)
def t_screen_capture(ctx, args):
    action = as_str(args, "action", max_len=16)
    if action == "screenshot":
        to = args.get("to", "file")
        if to not in ("file", "clipboard", "both"):
            raise ToolError("`to` is file, clipboard or both")
        grim, what, _ = capture_geometry(args)
        ctx.guard.check_rate()
        if to == "clipboard":
            path = os.path.join(runtime_dir(), f"capture-{secrets.token_hex(4)}.png")
        else:
            folder = os.path.expanduser(str(shell_setting("screenSnip.savePath", "~/Pictures/Screenshots")))
            os.makedirs(folder, exist_ok=True)
            path = os.path.join(folder, time.strftime("Screenshot-%Y-%m-%d-%H-%M-%S.png"))
        try:
            run(["grim", *grim, "-t", "png", path], timeout=15)
            if to != "file":
                with open(path, "rb") as f:
                    wl_copy(f.read(), "image/png")
        finally:
            # Only in the clipboard: no copy of the screen left behind.
            if to == "clipboard" and os.path.exists(path):
                os.unlink(path)
        if to == "clipboard":
            return [text(f"screenshot of the {what} copied to the clipboard")]
        return [text(f"screenshot of the {what} saved to {path}" + (" and copied to the clipboard" if to == "both" else ""))]
    if action == "record_status":
        return [text(json.loads(widget_call("region", "recordStatus")))]
    if action == "record_start":
        if args.get("window_id") is not None:
            raise ToolError("record a `monitor` or a `region` (a window: its region from list_windows)")
        sound = args.get("sound", False)
        if not isinstance(sound, bool):
            raise ToolError("`sound` must be true or false")
        _, what, target = capture_geometry(args)
        ctx.guard.check_rate()
        widget_call("region", "recordStart", target, "true" if sound else "false")
        # The script marks the recording as started once wf-recorder runs.
        for _ in range(20):
            time.sleep(0.25)
            if json.loads(widget_call("region", "recordStatus")).get("recording"):
                return [text(f"recording the {what}{' with sound' if sound else ''}; record_stop to end it")]
        raise ToolError("the recording didn't start (is wf-recorder installed? see the user's notifications)")
    if action == "record_stop":
        status = json.loads(widget_call("region", "recordStatus"))
        if not status.get("recording"):
            raise ToolError("not recording")
        stopped = time.time()
        ctx.guard.check_rate()
        widget_call("region", "recordStop")
        for _ in range(40):
            time.sleep(0.25)
            if not json.loads(widget_call("region", "recordStatus")).get("recording"):
                break
        folder = os.path.expanduser(status.get("folder") or "~/Videos")
        try:
            videos = [os.path.join(folder, n) for n in os.listdir(folder) if n.startswith("recording_") and n.endswith(".mp4")]
        except OSError:
            videos = []
        latest = max(videos, key=os.path.getmtime, default=None)
        if latest and os.path.getmtime(latest) >= stopped - 5:
            return [text(f"recording stopped: {latest} (also in the user's clipboard)")]
        return [text(f"recording stopped; the video is in {folder}")]
    raise ToolError("`action`: screenshot, record_start, record_stop or record_status")


ARRANGE_ACTIONS = {"layout", "place", "hide_on", "raise", "placement"}


def arrange_widget(ctx, action, want, args):
    """layout / place / hide_on / raise / placement: any widget, through the
    shell's `widgets` target (DesktopWidgets.qml)."""
    if action == "layout":
        return [text(json.loads(widget_call("widgets", "layout")))]
    if not want:
        raise ToolError(f"`{action}` needs `widget` (a name from layout or list)")
    layout = json.loads(widget_call("widgets", "layout"))
    names = {w["name"] for w in json.loads(widget_call("widgets", "list"))} | {w["name"] for w in layout["widgets"]}
    key = re.sub(r"[^a-z0-9:]", "", want.lower())
    name = next((n for n in sorted(names) if n.lower() == key or re.sub(r"[^a-z0-9:]", "", n.lower()) == key), None)
    if not name:
        raise ToolError(f"no widget {want!r}: {', '.join(sorted(names))}")
    if action == "placement":
        strategy = as_str(args, "strategy", max_len=16)
        if strategy not in ("free", "leastBusy", "mostBusy"):
            raise ToolError("`strategy` is free, leastBusy or mostBusy")
        ctx.guard.check_rate()
        return [text(widget_call("widgets", "placement", name, strategy)[3:].strip())]
    monitor = as_str(args, "monitor", required=False, max_len=64, pattern=r"[\w.:-]{1,64}")
    if not monitor:
        shown = [w["monitor"] for w in layout["widgets"] if w["name"] == name]
        monitors = [m["name"] for m in layout["monitors"]]
        if len(shown) == 1 or len(monitors) == 1:
            monitor = shown[0] if len(shown) == 1 else monitors[0]
        else:
            raise ToolError(f"which `monitor`? {', '.join(monitors)}")
    ctx.guard.check_rate()
    if action == "place":
        argv = []
        for k in ("x", "y"):
            v = args.get(k)
            if not isinstance(v, (int, float)) or isinstance(v, bool) or v < 0:
                raise ToolError(f"`{k}` must be a position in logical pixels (0 or more)")
            argv.append(str(round(v)))
        out = widget_call("widgets", "place", name, monitor, *argv)
    elif action == "hide_on":
        out = widget_call("widgets", "hideOn", name, monitor)
    else:
        out = widget_call("widgets", "raise", name, monitor)
    return [text(out[3:].strip() if out.startswith("ok:") else out)]


@tool(
    "widget",
    "shell",
    "The desktop widgets, without clicking them. No widget: `list` them "
    "(shown or not); any widget: `show` or `hide` it. Arranging: `layout` "
    "(each monitor's size and the box {x, y, width, height} of every widget "
    "showing, per monitor); place {widget, monitor?, x, y} (its top left, "
    "logical pixels from the monitor's corner; shows it there and stops it "
    "following the wallpaper), hide_on {widget, monitor?}, raise {widget, "
    "monitor?} (in front), placement {widget, strategy: free, leastBusy, "
    "mostBusy}. Lay widgets out from `layout` so they don't overlap. notes (the notes "
    "widget and the Notes app; the overlay's scratchpad is the one listed with "
    "scratchpad: true): list, add {text}, update {id, text}, remove {id}, open {id?} (the "
    "Notes app on the user's screen, on that note). todo (the "
    "task list, simply; the `tasks` tool does lists, deadlines, moves): list, "
    "add {text}, done/undone/remove {index}. timers: "
    "status, pomodoro_toggle, pomodoro_reset, stopwatch_toggle, "
    "stopwatch_lap, stopwatch_reset, countdown_add {minutes} (starts it), "
    "countdown_toggle, countdown_reset, countdown_dismiss (it rings at "
    "zero, until dismissed), alarm_set {when: \"YYYY-MM-DD HH:MM\" "
    "or \"HH:MM\" (today), label?, daily?}, alarm_toggle, alarm_clear, "
    "alarm_dismiss, alarm_snooze (while it rings). images (the custom image "
    "widgets): list, add {path, monitor?} (an image from a folder the user "
    "shares with agents; on that monitor, else all), remove {image}, set "
    "{image, key, value} (key: path, shape, size 80-1000, zoom 1-4, offsetX / "
    "offsetY -1..1 (which part of the picture shows, 0 = centre), rotation, "
    "opacity 0.1-1, mirror, grayscale), recenter {image}, monitors {image, "
    "monitors: all, none, or names}; `image` is a number from list.",
    obj({
        "widget": {"type": "string", "description": "notes, todo, timers, images, or a widget name from list"},
        "action": {"type": "string"},
        "text": {"type": "string", "description": "A note's or task's text"},
        "id": {"type": "string", "description": "A note's id (from list)"},
        "index": {"type": "integer", "description": "A task's index (from list)"},
        "minutes": {"type": "integer"},
        "x": {"type": "number", "description": "place: logical pixels from the monitor's left"},
        "y": {"type": "number", "description": "place: logical pixels from the monitor's top"},
        "strategy": {"type": "string", "enum": ["free", "leastBusy", "mostBusy"]},
        "when": {"type": "string", "description": "alarm_set: local \"YYYY-MM-DD HH:MM\", or \"HH:MM\""},
        "label": {"type": "string", "description": "alarm_set: what the alarm is for"},
        "daily": {"type": "boolean", "description": "alarm_set: every day at that time"},
        "image": {"type": ["integer", "string"], "description": "images: the image's number (from list)"},
        "path": {"type": "string", "description": "images add: the picture (absolute path or ~/…)"},
        "monitor": {"type": "string", "description": "images add, place, hide_on, raise: a monitor's name"},
        "key": {"type": "string", "description": "images set: the setting"},
        "value": {"type": ["string", "number", "boolean"], "description": "images set: its value"},
        "monitors": {"type": ["string", "array"], "items": {"type": "string"},
                     "description": "images monitors: all, none, or monitor names"},
    }, ["action"]),
)
def t_widget(ctx, args):
    action = as_str(args, "action", max_len=32).strip().lower()
    want = (as_str(args, "widget", required=False, max_len=64) or "").strip()
    if action in ARRANGE_ACTIONS:
        return arrange_widget(ctx, action, want, args)
    key = re.sub(r"[^a-z]", "", want.lower())
    widget = WIDGET_NAMES.get(key, key)
    if action in ("list", "show", "hide") and (not want or action != "list" or widget not in WIDGET_ACTIONS):
        widgets = json.loads(widget_call("widgets", "list"))
        if action == "list":
            return [text(widgets)]
        if not want:
            raise ToolError(f"which widget? {', '.join(w['name'] for w in widgets)}")
        # Names are camelCase in the shell (worldClock): matched ignoring case.
        name = next((w["name"] for w in widgets if w["name"].lower() == key or w["name"].lower() == widget), None)
        if not name:
            raise ToolError(f"no widget {want!r}: {', '.join(w['name'] for w in widgets)}")
        ctx.guard.check_rate()
        return [text(widget_call("widgets", action, name))]
    if widget not in WIDGET_ACTIONS:
        raise ToolError("give `widget`: notes, todo, timers, images or music (or list/show/hide for the others)")
    actions = WIDGET_ACTIONS[widget]
    if action == "list" and "status" in actions:
        action = "status"
    if action not in actions:
        raise ToolError(f"{widget} can't {action!r}: {', '.join(actions)}")
    target, fn, needs, changes = actions[action]
    argv = []
    for name in needs:
        if name == "text":
            cap = int(ctx.cfg.get("maxNoteLength", 100000)) if widget == "notes" else int(ctx.cfg.get("maxTextLength", 4000))
            value = as_str(args, "text", max_len=cap)
            if not value.strip():
                raise ToolError("`text` is empty")
        elif name == "id":
            value = as_str(args, "id", max_len=64, pattern=r"[\w.-]{1,64}")
        elif name == "note":
            value = as_str(args, "id", required=False, max_len=64, pattern=r"[\w.-]{1,64}") or ""
        elif name == "when":
            value = as_str(args, "when", max_len=20, pattern=r"(\d{4}-\d{1,2}-\d{1,2}[ T])?\d{1,2}:\d{2}")
        elif name == "label":
            value = (as_str(args, "label", required=False, max_len=100) or "").strip()
        elif name == "daily":
            daily = args.get("daily", False)
            if not isinstance(daily, bool):
                raise ToolError("`daily` must be true or false")
            value = "true" if daily else "false"
        elif name == "path":
            value = shared_image(as_str(args, "path", max_len=1024), "drop the picture on the image widget")
        elif name == "monitor":
            value = as_str(args, "monitor", required=False, max_len=64, pattern=r"[\w.:-]{1,64}") or ""
        elif name == "image":
            image = args.get("image")
            if isinstance(image, int) and not isinstance(image, bool) and image >= 1:
                value = str(image)
            elif isinstance(image, str) and re.fullmatch(r"\d{1,4}|customImage(:[\w]{1,32})?", image):
                value = image
            else:
                raise ToolError("`image` must be an image's number (1, 2, …: images list)")
        elif name == "key":
            value = as_str(args, "key", max_len=16, pattern=r"[A-Za-z]{1,16}")
        elif name == "value":
            raw = args.get("value")
            if isinstance(raw, bool):
                value = "true" if raw else "false"
            elif isinstance(raw, (int, float)):
                value = repr(raw)
            elif isinstance(raw, str) and raw and len(raw) <= 1024:
                value = raw
            else:
                raise ToolError("`value` must be a string, a number or true/false")
            # A new picture: the same check as add.
            if args.get("key") == "path":
                value = shared_image(value, "drop the picture on the image widget")
        elif name == "monitors":
            raw = args.get("monitors")
            if isinstance(raw, list) and raw and all(isinstance(m, str) and re.fullmatch(r"[\w.:-]{1,64}", m) for m in raw):
                value = ",".join(raw)
            elif isinstance(raw, str) and re.fullmatch(r"all|none|[\w.:-]{1,64}(,[\w.:-]{1,64})*", raw):
                value = raw
            else:
                raise ToolError("`monitors` must be all, none, or monitor names")
        else:
            value = args.get(name)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise ToolError(f"`{name}` must be a whole number (0 or more)")
            value = str(value)
        argv.append(value)
    if changes:
        ctx.guard.check_rate()
    out = notes_call(fn, *argv) if target == "notes" and fn in NOTES_FILE_FUNCTIONS else widget_call(target, fn, *argv)
    if not changes:
        try:
            return [text(json.loads(out))]
        except ValueError:
            pass
    return [text(out[3:].strip() if out.startswith("ok:") else out)]


EQ_BANDS_HZ = [32, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]


@tool(
    "equalizer",
    "shell",
    "The user's audio equalizer (EasyEffects, through the shell). status: "
    "the curve (10 bands, dB), the preamp, the presets, Auto (the preset "
    "following each song's genre), and what's playing (app, title, artist, "
    "album, page URL) with its Last.fm genre tags when the user set up a "
    "Last.fm key. preset {name}; bands {gains: 10 numbers in dB, -12..12, for "
    "32, 63, 125, 250, 500 Hz, 1, 2, 4, 8, 16 kHz}; song_curve {gains, db} "
    "(a curve for the song playing only: the user's saved curve comes back "
    "when it ends); preamp {db}; auto {on}; "
    "agent {on} (agent mode: each new song, a Claude Code task tunes it; "
    "replaces Auto); "
    "open / close (the equalizer window, on the user's screen). Setting a "
    "preset or bands turns Auto off. To fit what's playing: read status, "
    "then a preset or your own curve, e.g. electronic / hip-hop: lift "
    "32-125 Hz; rock / metal: lows and 4-8 kHz up, 500 Hz down a little; "
    "acoustic / jazz / classical: nearly flat, a little air at 8-16 kHz; "
    "speech (podcast, video essay): 32-125 Hz down, 1-4 kHz up. Keep boosts "
    "moderate (+6 dB at most) and lower the preamp by about the biggest "
    "boost so it doesn't clip.",
    obj({
        "action": {"type": "string", "enum": ["status", "preset", "bands", "song_curve", "preamp", "auto", "agent", "open", "close"]},
        "name": {"type": "string", "description": "preset: its name (from status)"},
        "gains": {"type": "array", "items": {"type": "number"}, "minItems": 10, "maxItems": 10,
                  "description": "bands: dB for 32 Hz … 16 kHz"},
        "db": {"type": "number", "description": "preamp, song_curve: the preamp in dB, -12..12"},
        "on": {"type": "boolean", "description": "auto, agent: on or off"},
    }, ["action"]),
)
def t_equalizer(ctx, args):
    action = as_str(args, "action", max_len=16)
    if action == "status":
        status = json.loads(widget_call("equalizer", "status"))
        # Genre tags of what's playing: looked up now if they aren't known yet.
        if status.get("playing") and status.get("genreTags") is None:
            try:
                widget_call("equalizer", "lookupGenre")
                for _ in range(12):
                    time.sleep(0.25)
                    status = json.loads(widget_call("equalizer", "status"))
                    if status.get("genreTags") is not None:
                        break
            except ToolError:
                pass
        return [text(status)]
    if action in ("open", "close"):
        return [text(widget_call("equalizer", action)[3:].strip())]
    ctx.guard.check_rate()
    if action == "preset":
        out = widget_call("equalizer", "preset", as_str(args, "name", max_len=64, pattern=r"[\w .()+-]{1,64}"))
    elif action in ("bands", "song_curve"):
        gains = args.get("gains")
        if not isinstance(gains, list) or len(gains) != 10 or not all(
                isinstance(g, (int, float)) and not isinstance(g, bool) and -12 <= g <= 12 for g in gains):
            raise ToolError("`gains`: 10 numbers in dB, -12..12, for " + ", ".join(f"{hz} Hz" for hz in EQ_BANDS_HZ))
        curve = ",".join(f"{round(g, 1):g}" for g in gains)
        if action == "bands":
            out = widget_call("equalizer", "bands", curve)
        else:
            db = args.get("db", 0)
            if not isinstance(db, (int, float)) or isinstance(db, bool) or not -12 <= db <= 12:
                raise ToolError("`db` must be a number from -12 to 12")
            out = widget_call("equalizer", "songCurve", curve, f"{round(db, 1):g}")
    elif action == "preamp":
        db = args.get("db")
        if not isinstance(db, (int, float)) or isinstance(db, bool) or not -12 <= db <= 12:
            raise ToolError("`db` must be a number from -12 to 12")
        out = widget_call("equalizer", "preamp", f"{round(db, 1):g}")
    elif action in ("auto", "agent"):
        on = args.get("on")
        if not isinstance(on, bool):
            raise ToolError("`on` must be true or false")
        out = widget_call("equalizer", action, "true" if on else "false")
    else:
        raise ToolError("`action`: status, preset, bands, song_curve, preamp, auto, agent, open or close")
    return [text(out[3:].strip() if out.startswith("ok:") else out)]


CALENDAR_OPS = ("create", "update", "delete", "show_calendar", "hide_calendar")


def calendar_op(args, op):
    """One change for nixbook-accounts' calendar, from the tool's
    arguments: only the fields given."""
    out = {"op": op}
    for key, cap in (("id", 400), ("occurrence", 40), ("calendar", 400), ("summary", 1000), ("start", 40),
                     ("end", 40), ("location", 1000), ("description", 8000)):
        if key not in args:
            continue
        value = args[key]
        if value is None and key in ("location", "description"):
            value = ""
        if not isinstance(value, str) or len(value) > cap:
            raise ToolError(f"`{key}` must be a string of at most {cap} characters")
        out[key] = value
    for key in ("allDay", "all"):
        if key in args:
            if not isinstance(args[key], bool):
                raise ToolError(f"`{key}` must be true or false")
            out[key] = args[key]
    if "reminders" in args:
        r = args["reminders"]
        if r is not None and (not isinstance(r, list) or len(r) > 10
                              or not all(isinstance(m, int) and not isinstance(m, bool) and 0 <= m <= 40320 for m in r)):
            raise ToolError("`reminders` must be minutes before (0 to 40320), at most 10, or null for the calendar's")
        out["reminders"] = r
    if "recurrence" in args:
        r = args["recurrence"]
        if r is not None and not isinstance(r, str) or isinstance(r, str) and len(r) > 300:
            raise ToolError("`recurrence` must be daily, weekdays, weekly, monthly, yearly, none or an RRULE")
        out["recurrence"] = r or "none"
    return out


@tool(
    "calendar",
    "shell",
    "The user's calendars, every account's merged (Google, iCloud, Fastmail, Nextcloud…, and "
    "\"local\", kept on this computer; the "
    "shell's Calendar window and widgets). Reading: `next` (the next event, with a \"when\" like "
    "\"in 12 min\"), `upcoming` {days: 1 = today, up to 60}, `day` {date: YYYY-MM-DD}, "
    "`calendars` (id, name, account, read-only, hidden); events come with their id and, for an occurrence "
    "of a recurring event, its `occurrence` (its start). Changes: create {summary, start, end?, "
    "allDay?, calendar? (name or id; default the primary), location?, description?, reminders? "
    "(minutes before, [] none, null the calendar's), recurrence? (daily, weekdays, weekly, "
    "monthly, yearly, none, an RRULE)}; update {id, occurrence? (that occurrence only), …the "
    "fields to change, calendar? (move)}; to change a whole series from one of its occurrences: "
    "{id, occurrence, all: true, start?, end?…} (every occurrence moves as that one does); "
    "delete {id, occurrence?} (ask the user first); show_calendar / hide_calendar {calendar}: "
    "a calendar on or off in the shell (off: its events aren't shown, reminded or listed here; "
    "Google Calendar's own selection stays). Times: YYYY-MM-DDTHH:MM (local) or "
    "YYYY-MM-DD (all-day; end: its last day). open {date?}: the Calendar window. Local times.",
    obj({
        "action": {"type": "string", "enum": ["next", "upcoming", "day", "calendars", "open", *CALENDAR_OPS]},
        "days": {"type": "integer", "description": "upcoming: how many days from today (default 7)"},
        "date": {"type": "string", "description": "day, open: YYYY-MM-DD"},
        "id": {"type": "string", "description": "An event's id (from next, upcoming, day)"},
        "occurrence": {"type": "string", "description": "A recurring event's occurrence (its start, as given)"},
        "all": {"type": "boolean", "description": "update: the whole series, from that occurrence"},
        "calendar": {"type": "string", "description": "A calendar's name or id"},
        "summary": {"type": "string"},
        "start": {"type": "string", "description": "YYYY-MM-DDTHH:MM (local) or YYYY-MM-DD"},
        "end": {"type": "string", "description": "Default: an hour later (all-day: that day)"},
        "allDay": {"type": "boolean"},
        "location": {"type": ["string", "null"]},
        "description": {"type": ["string", "null"]},
        "reminders": {"type": ["array", "null"], "items": {"type": "integer"}},
        "recurrence": {"type": ["string", "null"]},
    }, ["action"]),
    destructive=True,
)
def t_calendar(ctx, args):
    action = as_str(args, "action", max_len=16)
    if action == "calendars":
        out = accounts_call("calendar", "calendars")
        return [text({"calendars": [{k: c.get(k, False) for k in ("id", "name", "account", "primary", "readOnly", "hidden")}
                                    for c in out.get("calendars", [])]})]
    if action == "open":
        date = as_str(args, "date", required=False, max_len=10, pattern=r"\d{4}-\d{2}-\d{2}") or ""
        return [text(widget_call("calendar", "open", date) if date else widget_call("calendar", "launch"))]
    if action in CALENDAR_OPS:
        ctx.guard.check_rate()
        r = accounts_call("calendar", "apply", json.dumps(calendar_op(args, action)), timeout=120)[0]
        if not r.get("ok"):
            raise ToolError(r.get("error", "failed"))
        res = r["result"]
        if action == "show_calendar":
            # Its events now (Google's aren't fetched while it is off).
            accounts_call("calendar", "sync", timeout=120)
        if action in ("show_calendar", "hide_calendar"):
            return [text(f"{res.get('name')} {'shown' if action == 'show_calendar' else 'hidden'}")]
        if isinstance(res, dict) and "start" in res:
            res = {k: v for k, v in res.items() if v not in ("", None, []) and k not in ("account", "updated")}
        return [text(res)]
    if action == "next":
        argv = ["next"]
    elif action == "upcoming":
        days = args.get("days", 7)
        if not isinstance(days, int) or isinstance(days, bool) or not 1 <= days <= 60:
            raise ToolError("`days` must be a whole number from 1 to 60")
        argv = ["upcoming", str(days)]
    elif action == "day":
        argv = ["day", as_str(args, "date", max_len=10, pattern=r"\d{4}-\d{2}-\d{2}")]
    else:
        raise ToolError("`action` must be next, upcoming, day, calendars, open, create, update, delete, "
                        "show_calendar or hide_calendar")
    out = widget_call("calendar", *argv)
    try:
        return [text(json.loads(out))]
    except ValueError:
        return [text(out)]


TASK_OPS = ("create", "update", "done", "undone", "delete", "move", "clear_completed", "open",
            "create_list", "rename_list", "delete_list")


def tasks_call(fn, request=None):
    """A todo `query` or `apply` call, through a private transfer file both
    ways (services/Todo.qml): task lists with notes can be long."""
    path = os.path.join(runtime_dir(), f"tasks-{secrets.token_hex(8)}.json")
    try:
        if request is not None:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(request, f)
        widget_call("todo", fn, path)
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise ToolError(f"the tasks transfer failed: {e}")
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def task_op(args, op):
    """One operation for the shell, from the tool's arguments: only the
    fields given (an absent `due` keeps the deadline, "" clears it)."""
    if op not in TASK_OPS:
        raise ToolError(f"unknown action {op!r}: list, {', '.join(TASK_OPS)}, batch")
    out = {"op": op}
    for key, cap in (("task", 128), ("title", 1000), ("notes", 8000), ("list", 200), ("due", 10), ("name", 200)):
        if key not in args or args[key] is None and key != "due":
            continue
        value = args[key]
        if key == "due" and value is None:
            value = ""
        if not isinstance(value, str) or len(value) > cap:
            raise ToolError(f"`{key}` must be a string of at most {cap} characters")
        out[key] = value
    return out


@tool(
    "tasks",
    "shell",
    "The user's to-do lists (the shell's Tasks app and to-do widget; synced "
    "with Google Tasks once the shell's Google account is connected, "
    "else one local list). `list` {list?, include_done?}: today's date, the "
    "lists (id, name, open/completed counts) and the tasks (id, title, list, "
    "notes, due YYYY-MM-DD, deadline: overdue/today/tomorrow/week/later/none, "
    "parent: a subtask's parent id). Changes, by task id from list: create "
    "{title, list?, notes?, due?}, update {task, title?, notes?, due?}, "
    "done/undone/delete {task}, move {task, list} (to another list), "
    "clear_completed {list?} (deletes the completed tasks), open {task?} "
    "(the Tasks window on the user's screen). The lists themselves: "
    "create_list {name}, rename_list {list, name}, delete_list {list} (with "
    "all its tasks: ask the user first); Google's default list can't be "
    "deleted, and a new Google list gets its id after a moment (list again). "
    "`list` is a list's name or id "
    "(default: the first, \"My Tasks\"). `due`: YYYY-MM-DD, today, tomorrow, "
    "+N (days), or \"\" to clear it; Google keeps dates, not times. batch "
    "{ops: [{action, …}, …]} runs up to 50 changes in order (organizing: "
    "moving, dating, renaming many tasks at once), each reported on its own. "
    "A new task gets its id once Google answers: list again before "
    "changing it (a moved one keeps its id). Subtasks are made in Google Tasks.",
    obj({
        "action": {"type": "string", "enum": ["list", *TASK_OPS, "batch"]},
        "task": {"type": "string", "description": "A task's id (from list)"},
        "title": {"type": "string"},
        "notes": {"type": "string", "description": "The task's details"},
        "list": {"type": "string", "description": "A list's name or id"},
        "name": {"type": "string", "description": "create_list, rename_list: the list's (new) name"},
        "due": {"type": ["string", "null"], "description": "YYYY-MM-DD, today, tomorrow, +N, or \"\" to clear"},
        "include_done": {"type": "boolean", "description": "list: also the completed tasks (the last 14 days)"},
        "ops": {"type": "array", "items": {"type": "object"}, "maxItems": 50,
                "description": "batch: [{action, task?, title?, notes?, list?, due?, name?}, …]"},
    }, ["action"]),
    destructive=True,
)
def t_tasks(ctx, args):
    action = as_str(args, "action", max_len=32).strip().lower()
    if action == "list":
        state = tasks_call("query")
        want = args.get("list")
        if want is not None:
            if not isinstance(want, str):
                raise ToolError("`list` must be a list's name or id")
            match = next((l for l in state["lists"] if l["id"] == want or l["name"].lower() == want.lower()), None)
            if not match:
                raise ToolError(f"no list {want!r}: {', '.join(l['name'] for l in state['lists'])}")
            state["tasks"] = [t for t in state["tasks"] if t["listId"] == match["id"]]
        include_done = args.get("include_done", False)
        if not isinstance(include_done, bool):
            raise ToolError("`include_done` must be true or false")
        if not include_done:
            state["tasks"] = [t for t in state["tasks"] if not t["done"]]
        return [text(state)]
    if action == "batch":
        ops = args.get("ops")
        if not isinstance(ops, list) or not ops or len(ops) > 50:
            raise ToolError("`ops` must be a list of 1 to 50 changes")
        request = {"ops": []}
        for i, o in enumerate(ops):
            if not isinstance(o, dict):
                raise ToolError(f"ops[{i}] must be an object")
            op = o.get("action", o.get("op"))
            if not isinstance(op, str):
                raise ToolError(f"ops[{i}]: needs an action")
            request["ops"].append(task_op(o, op.strip().lower()))
    else:
        request = task_op(args, action)
    ctx.guard.check_rate()
    results = tasks_call("apply", request)
    if action != "batch":
        r = results[0]
        if not r.get("ok"):
            raise ToolError(r.get("error", "failed"))
        return [text(r["result"])]
    done = sum(1 for r in results if r.get("ok"))
    lines = [f"{done}/{len(results)} done"]
    for i, r in enumerate(results):
        lines.append(f"{i + 1}. " + (r["result"] if r.get("ok") else f"error: {r.get('error')}"))
    return [text("\n".join(lines))]


CONTACT_OPS = ("create", "update", "delete", "star", "unstar", "set_photo", "create_label", "rename_label",
               "delete_label")
CONTACT_TEXT = {"name": 300, "givenName": 200, "familyName": 200, "nickname": 200, "organization": 300,
                "title": 300, "birthday": 10, "notes": 8000, "id": 300, "label": 300, "account": 200,
                "photo": 2000}
PHOTO_MAX_BYTES = 20 << 20
CONTACT_LISTS = ("emails", "phones", "urls", "addresses", "labels")


def accounts_call(*args, timeout=60):
    """`nixbook-accounts` (the shell's accounts backend) and its JSON answer."""
    proc = run(["nixbook-accounts", *args], timeout=timeout, check=False)
    try:
        out = json.loads(proc.stdout or "null")
    except ValueError:
        out = None
    if proc.returncode == 2:
        raise ToolError("No account is connected (or its provider signed it out): the user adds or signs it "
                        "in again in the Contacts app (`contacts` action open), which walks them through it")
    if proc.returncode != 0:
        msg = out.get("error") if isinstance(out, dict) else (proc.stderr or "").strip()[-300:]
        raise ToolError(msg or f"nixbook-accounts failed ({proc.returncode})")
    return out


def fetch_photo(url, folder):
    """An image on the web, saved in folder for set_photo (nixbook-accounts
    checks it is an image)."""
    import urllib.request
    path = os.path.join(folder, secrets.token_hex(8))
    req = urllib.request.Request(url, headers={"User-Agent": "nixbook-desktop-mcp"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r, open(path, "wb") as f:
            data = r.read(PHOTO_MAX_BYTES + 1)
            if len(data) > PHOTO_MAX_BYTES:
                raise ToolError(f"the image at {short(url, 100)} is over {PHOTO_MAX_BYTES >> 20} MB")
            f.write(data)
    except OSError as e:
        raise ToolError(f"couldn't download {short(url, 100)}: {e}")
    return path


def photo_paths(ops, folder):
    """set_photo's `photo` as nixbook-accounts takes it: an absolute path
    (~ expanded), a web image downloaded first, "" to remove it."""
    for o in ops:
        if o["op"] != "set_photo":
            continue
        photo = (o.get("photo") or "").strip()
        if re.match(r"https?://", photo, re.I):
            o["photo"] = fetch_photo(photo, folder)
        elif photo:
            if not os.path.isabs(os.path.expanduser(photo)):
                raise ToolError("`photo` must be an image file's absolute path or an http(s) URL")
            # Only a picture from a folder the user shares with agents, like
            # the wallpaper and the image widget: not any file of theirs.
            o["photo"] = shared_image(photo, "set the contact's picture in the Contacts app")
        else:
            o["photo"] = ""


def compact_contact(c):
    """A contact without its empty fields or ids it doesn't need; whether it
    has a photo, not its URL."""
    out = {k: v for k, v in c.items() if v not in ("", [], None, False) and k not in ("photo", "updated")}
    if c.get("photo"):
        out["photo"] = True
    for key in ("emails", "phones", "urls"):
        if key in out:
            out[key] = [e["value"] + (f" ({e['type']})" if e.get("type") else "") for e in out[key]]
    if "addresses" in out:
        out["addresses"] = [a["value"].replace("\n", ", ") + (f" ({a['type']})" if a.get("type") else "")
                            for a in out["addresses"]]
    return out


def contact_op(args, op):
    """One change for nixbook-accounts, from the tool's arguments: only the
    fields given (they replace the contact's)."""
    if op not in CONTACT_OPS:
        raise ToolError(f"unknown action {op!r}: list, get, sync, open, {', '.join(CONTACT_OPS)}, batch")
    out = {"op": op}
    for key, cap in CONTACT_TEXT.items():
        if key not in args:
            continue
        value = args[key]
        if value is None and key not in ("id", "label"):
            value = ""
        if not isinstance(value, str) or len(value) > cap:
            raise ToolError(f"`{key}` must be a string of at most {cap} characters")
        out[key] = value
    if "label_name" in args:
        out["name"] = as_str(args, "label_name", max_len=200)
    for key in CONTACT_LISTS:
        if key not in args:
            continue
        value = args[key]
        if value is None:
            value = []
        if isinstance(value, (str, dict)):
            value = [value]
        if not isinstance(value, list) or len(value) > 50 or len(json.dumps(value)) > 20000:
            raise ToolError(f"`{key}` must be a list of at most 50 entries")
        out[key] = value
    if "starred" in args:
        if not isinstance(args["starred"], bool):
            raise ToolError("`starred` must be true or false")
        out["starred"] = args["starred"]
    return out


@tool(
    "contacts",
    "shell",
    "The user's contacts, every account's merged (the shell's Contacts app and widget; through "
    "nixbook-accounts: Google, CalDAV/CardDAV servers, and \"local\", kept on this computer). `list` {query?, label?, account?, starred?, limit? (25)}: the "
    "accounts, the labels (with counts and account) and the matching contacts (every word of query, "
    "accents and case ignored, phone numbers by digits; empty fields left out). Ids are "
    "\"<account>:…\". get {id}: one in full. Changes, by id from list (each goes to its account); "
    "the fields given replace the contact's, the others stay: create {account? (id, name or email; "
    "default the first), name | givenName, "
    "familyName, emails?, phones?, organization?, title?, addresses?, birthday?, notes?, urls?, "
    "nickname?, labels?, starred?}, update {id, …same fields}, star/unstar {id}, delete {id} "
    "(ask the user first; Google keeps it 30 days in its Trash, other servers don't). emails/phones/urls: strings or "
    "{value, type} (home, work, mobile, other…); addresses: strings or {street, city, postalCode, "
    "region, country, type}; birthday YYYY-MM-DD or MM-DD (\"\" clears); labels: names (a new name "
    "makes the label) or ids, replacing the contact's; a contact's labels are its account's. "
    "Labels themselves: create_label {label_name, account?}, rename_label {label, label_name}, "
    "delete_label {label} (its contacts stay); a label name in several accounts needs its id. "
    "sync {full?}: Google's changes now (list reads the local copy, synced every 30 min). open "
    "{id?}: the Contacts app on the user's screen. set_photo {id, photo}: the contact's picture from "
    "an image file (absolute path: a screenshot, a download) or an http(s) image URL (PNG, JPEG or GIF; "
    "sent as a JPEG of at most 720 px); photo \"\" removes it. batch {ops: [{action, …}, …]} runs up to 50 "
    "changes in order (cleaning up, labelling many), each reported on its own.",
    obj({
        "action": {"type": "string", "enum": ["list", "get", "sync", "open", *CONTACT_OPS, "batch"]},
        "id": {"type": "string", "description": "A contact's id (from list)"},
        "query": {"type": "string"},
        "label": {"type": "string", "description": "A label's name or id"},
        "account": {"type": "string", "description": "An account's id, name or email (from list)"},
        "label_name": {"type": "string", "description": "create_label, rename_label: the label's (new) name"},
        "limit": {"type": "integer"},
        "full": {"type": "boolean", "description": "sync: everything again, not only the changes"},
        "name": {"type": "string", "description": "The full name (Google splits it); or givenName/familyName"},
        "givenName": {"type": "string"},
        "familyName": {"type": "string"},
        "nickname": {"type": "string"},
        "emails": {"type": "array", "items": {"type": ["string", "object"]}},
        "phones": {"type": "array", "items": {"type": ["string", "object"]}},
        "urls": {"type": "array", "items": {"type": ["string", "object"]}},
        "addresses": {"type": "array", "items": {"type": ["string", "object"]}},
        "organization": {"type": "string", "description": "Company"},
        "title": {"type": "string", "description": "Job title"},
        "birthday": {"type": ["string", "null"], "description": "YYYY-MM-DD or MM-DD; \"\" clears it"},
        "notes": {"type": "string"},
        "photo": {"type": "string", "description": "set_photo: an image file's absolute path or an "
                                                    "http(s) image URL; \"\" removes the photo"},
        "labels": {"type": "array", "items": {"type": "string"}},
        "starred": {"type": "boolean"},
        "ops": {"type": "array", "items": {"type": "object"}, "maxItems": 50,
                "description": "batch: [{action, id?, …fields}, …]"},
    }, ["action"]),
    destructive=True,
)
def t_contacts(ctx, args):
    action = as_str(args, "action", max_len=32).strip().lower()
    if action == "list":
        argv = ["contacts", "list"]
        for key in ("query", "label", "account"):
            if args.get(key) is not None:
                argv += [f"--{key}", as_str(args, key, max_len=300)]
        if args.get("starred") is True:
            argv.append("--starred")
        limit = args.get("limit", 25)
        if not isinstance(limit, int) or not 1 <= limit <= 500:
            raise ToolError("`limit` must be 1 to 500")
        out = accounts_call(*argv, "--limit", str(limit))
        accounts = accounts_call("status").get("accounts", [])
        return [text({
            "accounts": [{"id": a["id"], "name": a["name"], "connected": a["connected"]} for a in accounts],
            "synced": time.strftime("%Y-%m-%d %H:%M", time.localtime(out["syncedAt"] / 1000)) if out["syncedAt"] else None,
            "total": out["total"],
            "shown": len(out["contacts"]),
            "labels": out["labels"],
            "contacts": [compact_contact(c) for c in out["contacts"]],
        })]
    if action == "get":
        return [text(compact_contact(accounts_call("contacts", "get", as_str(args, "id", max_len=300))))]
    if action == "sync":
        ctx.guard.check_rate()
        full = args.get("full", False)
        if not isinstance(full, bool):
            raise ToolError("`full` must be true or false")
        return [text(accounts_call("contacts", "sync", *(["--full"] if full else []), timeout=120))]
    if action == "open":
        cid = as_str(args, "id", required=False, max_len=300, pattern=r"[\w.:@/-]{1,300}") or ""
        return [text(widget_call("contacts", "open", cid))]
    if action == "batch":
        ops = args.get("ops")
        if not isinstance(ops, list) or not ops or len(ops) > 50:
            raise ToolError("`ops` must be a list of 1 to 50 changes")
        request = {"ops": []}
        for i, o in enumerate(ops):
            if not isinstance(o, dict):
                raise ToolError(f"ops[{i}] must be an object")
            op = o.get("action", o.get("op"))
            if not isinstance(op, str):
                raise ToolError(f"ops[{i}]: needs an action")
            request["ops"].append(contact_op(o, op.strip().lower()))
    else:
        request = contact_op(args, action)
    ctx.guard.check_rate()
    with tempfile.TemporaryDirectory(dir=runtime_dir()) as folder:
        photo_paths(request.get("ops") or [request], folder)
        results = accounts_call("contacts", "apply", json.dumps(request), timeout=120)

    def summary(r):
        res = r.get("result")
        if isinstance(res, dict) and "deleted" in res:
            return f"deleted {res.get('name') or res['deleted']}"
        if isinstance(res, dict) and "emails" in res:
            return compact_contact(res)
        return res

    if action != "batch":
        r = results[0]
        if not r.get("ok"):
            raise ToolError(r.get("error", "failed"))
        return [text(summary(r))]
    done = sum(1 for r in results if r.get("ok"))
    lines = [f"{done}/{len(results)} done"]
    for i, r in enumerate(results):
        if r.get("ok"):
            res = summary(r)
            lines.append(f"{i + 1}. " + (res if isinstance(res, str) else json.dumps(res, ensure_ascii=False)))
        else:
            lines.append(f"{i + 1}. error: {r.get('error')}")
    return [text("\n".join(lines))]


@tool(
    "notify",
    "shell",
    "Show a desktop notification to the user.",
    obj({"title": {"type": "string"}, "body": {"type": "string"}}, ["title"]),
)
def t_notify(ctx, args):
    title = as_str(args, "title", max_len=120)
    body = args.get("body") or ""
    if not isinstance(body, str) or len(body) > 1000:
        raise ToolError("`body` must be a string of at most 1000 characters")
    ctx.guard.check_rate()
    run(["notify-send", "-a", "Desktop agent", "--", title, body])
    return [text("notification shown")]


# -- any app, through its accessibility tree (AT-SPI) --------------------------
#
# What screen readers see: a window's buttons, fields, texts, with names and
# actions. Reading it costs a few hundred tokens where a screenshot costs
# ~1,250, and acting on an element (its own press/toggle action, its text set
# directly) needs no coordinates. Only the windows listed by niri, only what
# is showing, never terminals, password managers or password fields.
