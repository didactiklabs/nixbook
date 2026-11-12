# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Window layouts and project contexts.

# A maximized column (maximize-column, Mod+Z) is as wide as its monitor less
# the gaps, and niri doesn't say whether a column is maximized: a column at
# least this share of its monitor's width counts as one. Restored as a fixed
# width, it couldn't be unmaximized (maximize-column would toggle between
# two full widths).
MAXIMIZED_SHARE = 0.9
# The width under a maximized column restored: what Mod+Z goes back to.
UNMAXIMIZED_WIDTH = "50%"


def monitor_widths():
    return {n: o["logical"]["width"] for n, o in (niri_json("outputs") or {}).items()
            if (o.get("logical") or {}).get("width")}


def is_maximized(e, widths):
    """Whether a saved tiled window's column was maximized: so marked when
    saved, or (a layout saved before) about as wide as its monitor."""
    if "maximized" in e:
        return bool(e["maximized"])
    width = widths.get(e.get("monitor")) or max(widths.values(), default=0)
    size = e.get("size") or []
    return bool(width and size and size[0] >= MAXIMIZED_SHARE * width)


def layout_entry(w, ws, apps, widths=None):
    layout = w.get("layout") or {}
    e = {
        "app_id": w.get("app_id"),
        "title": w.get("title"),
        "desktop": desktop_for_app(w.get("app_id"), apps),
        "monitor": ws.get("output"),
        "workspace": {"index": ws.get("idx"), "name": ws.get("name")},
        "floating": bool(w.get("is_floating")),
        "size": layout.get("window_size"),
    }
    if e["floating"]:
        pos = layout.get("tile_pos_in_workspace_view")
        e["position"] = [round(v) for v in pos] if pos else None
    else:
        col = layout.get("pos_in_scrolling_layout") or [None, None]
        e["column"], e["tile"] = col
        width = (widths or {}).get(e["monitor"])
        tile = layout.get("tile_size") or layout.get("window_size") or [0]
        e["maximized"] = bool(width and tile[0] >= MAXIMIZED_SHARE * width)
    return e


@tool(
    "save_layout",
    "observe",
    "Remember the window layout under a name: every window's monitor, "
    "workspace, column (or floating position) and size, and the app that "
    "opens it, for the monitors connected now (the layout keeps the one "
    "saved with other monitors). restore_layout puts it back.",
    obj({"name": {"type": "string", "description": "e.g. work, gaming, default"}}, ["name"]),
)
def t_save_layout(ctx, args):
    name = as_str(args, "name", max_len=64, pattern=LAYOUT_NAME)
    path = os.path.join(layouts_dir(), f"{name}.json")
    wss = {w["id"]: w for w in niri_json("workspaces")}
    apps = applications()
    widths = monitor_widths()
    entries = [layout_entry(w, wss[w["workspace_id"]], apps, widths) for w in windows() if w.get("workspace_id") in wss]
    # One arrangement per set of monitors: saving off the dock replaces the
    # laptop's and keeps the docked one, for when the dock is back.
    connected = sorted(connected_monitors())
    saved = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    try:
        with open(path, encoding="utf-8") as f:
            kept = [x for x in layout_setups(json.load(f)) if x["monitors"] != connected]
    except (OSError, ValueError, AttributeError):
        kept = []
    kept = sorted(kept, key=lambda x: x.get("saved") or "")[-(MAX_SETUPS - 1):]
    doc = {"name": name, "saved": saved, "setups": [*kept, {"monitors": connected, "saved": saved, "windows": entries}]}
    fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    os.replace(path + ".tmp", path)
    set_current_layout(name)
    monitors = sorted({e["monitor"] for e in entries})
    no_launcher = sorted({e["app_id"] or "?" for e in entries if not e["desktop"]})
    summary = f"saved layout {name!r}: {len(entries)} windows on {', '.join(monitors) or 'no monitor'}"
    if kept:
        summary += ". Kept for other monitors: " + "; ".join(", ".join(x["monitors"]) or "none" for x in kept)
    if no_launcher:
        summary += f". Can't be reopened if closed (no .desktop entry found): {', '.join(no_launcher)}"
    return [text(summary)]


MAX_SETUPS = 8


def layout_setups(doc):
    """A layout's arrangements, one per set of monitors it was saved with:
    [{monitors, saved, windows}]. A layout saved before there were several
    has its windows' monitors."""
    if isinstance(doc.get("setups"), list):
        return [x for x in doc["setups"] if isinstance(x, dict) and isinstance(x.get("windows"), list)]
    entries = doc.get("windows")
    if not isinstance(entries, list):
        return []
    return [{"monitors": sorted({e.get("monitor") for e in entries if e.get("monitor")}),
             "saved": doc.get("saved"), "windows": entries}]


def pick_setup(setups, connected):
    """The arrangement for these monitors: the largest one they all are in
    (exactly the monitors connected, a dock's), else the largest one, its
    unplugged monitors folded onto the connected ones."""
    fits = [x for x in setups if set(x["monitors"]) <= connected]
    return max(fits or setups, key=lambda x: (len(x["monitors"]), x.get("saved") or ""), default=None)


@tool(
    "list_layouts",
    "observe",
    "List the saved window layouts.",
    read_only=True,
)
def t_list_layouts(ctx, args):
    return [text(layouts_index() or "no saved layout")]


def layouts_index():
    out = []
    connected = connected_monitors()
    for fn in sorted(os.listdir(layouts_dir())):
        # _project-NAME, _before-undo: kept by projects, not the user's list.
        if not fn.endswith(".json") or fn.startswith("_"):
            continue
        try:
            with open(os.path.join(layouts_dir(), fn), encoding="utf-8") as f:
                doc = json.load(f)
            setup = pick_setup(layout_setups(doc), connected) or {"windows": []}
            apps = sorted({w.get("app_id") or "?" for w in setup["windows"]})
            out.append({"name": fn[:-5], "saved": doc.get("saved"), "windows": len(setup["windows"]), "apps": apps})
        except (OSError, ValueError, AttributeError):
            continue
    return out


def connected_monitors():
    """The enabled outputs (a disabled one has no logical size)."""
    return {n for n, o in (niri_json("outputs") or {}).items() if o.get("logical")}


def current_layout_path():
    return os.path.join(layouts_dir(), ".current")


def set_current_layout(name):
    try:
        with open(current_layout_path(), "w", encoding="utf-8") as f:
            f.write(name)
    except OSError:
        pass


def current_layout():
    try:
        with open(current_layout_path(), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def on_workspace(e, w, wss):
    """Whether window w is on entry e's monitor and workspace already."""
    ws = wss.get(w.get("workspace_id")) or {}
    if e.get("monitor") and ws.get("output") != e["monitor"]:
        return False
    saved = e.get("workspace") or {}
    if saved.get("id"):
        return ws.get("id") == saved["id"]
    if saved.get("name"):
        return ws.get("name") == saved["name"]
    return not saved.get("index") or ws.get("idx") == saved["index"]


def close(a, b, slack=2):
    """Two sizes or positions the same, give or take rounding."""
    return bool(a) and bool(b) and all(abs(x - y) <= slack for x, y in zip(a, b))


def same_app(a, b):
    """Two Wayland app-ids naming the same app: Electron apps change `_` for
    `-` between XWayland and native Wayland (YouTube Music was
    com.github.th_ch.youtube_music as an AppImage, is
    com.github.th-ch.youtube-music natively), and saved layouts keep the old."""
    return bool(a) and bool(b) and a.replace("_", "-").lower() == b.replace("_", "-").lower()


def match_windows(entries, current, wss=None):
    """Pairs saved entries with open windows: same app_id, the same title
    first, then (titles change: a terminal's directory) the window already
    where the entry was saved, so two windows of an app aren't swapped.
    Returns (pairs, unmatched entries, windows not in the layout)."""
    wss = wss or {}
    free = list(current)
    pairs, missing = [], []

    def misplacement(e, w):
        layout = w.get("layout") or {}
        if not on_workspace(e, w, wss):
            return 3
        if e.get("floating"):
            return 0 if close(e.get("position"), layout.get("tile_pos_in_workspace_view")) else 1
        pos = layout.get("pos_in_scrolling_layout") or [None, None]
        return 0 if [e.get("column"), e.get("tile")] == list(pos) else 1 if e.get("column") == pos[0] else 2

    for exact in (True, False):
        rest = []
        for e in (entries if exact else missing):
            w = min(
                (w for w in free if same_app(w.get("app_id"), e.get("app_id")) and (not exact or w.get("title") == e.get("title"))),
                key=lambda w: misplacement(e, w),
                default=None,
            )
            if w:
                free.remove(w)
                pairs.append((e, w))
            else:
                rest.append(e)
        missing = rest
    return pairs, missing, free


def in_order(stacks, placed):
    """Whether the tiled windows of a workspace (columns in the saved order,
    each its tiles in order) are arranged so: each stack in one column of its
    own, top to bottom, the columns left to right (other windows between
    them are fine)."""
    last = 0
    for tiles in stacks:
        cols = {placed(w)[0][0] for e, w in tiles}
        rows = [placed(w)[0][1] for e, w in tiles]
        if len(cols) != 1 or None in cols or None in rows or rows != sorted(rows):
            return False
        col = cols.pop()
        if col <= last:
            return False
        last = col
    return True


def fold_unplugged(pairs, outputs):
    """Moves the entries saved on monitors not connected now onto the focused
    one. A named workspace niri still has (it parks an unplugged monitor's
    workspaces on another) is used as it is; each other saved (monitor,
    workspace) gets the empty last workspace of the focused monitor, named
    for the restore. Returns (pairs, the names to unset, that monitor)."""
    target = (niri_json("focused-output") or {}).get("name")
    if target not in outputs:
        target = min(outputs, default=None)
    taken = {ws.get("name") for ws in niri_json("workspaces") if ws.get("name")}
    existing = set(taken)
    named, out = {}, []
    for e, w in pairs:
        monitor = e.get("monitor")
        ws = e.get("workspace") or {}
        if not monitor or monitor in outputs:
            out.append((e, w))
            continue
        if ws.get("name") in existing:
            out.append(({**e, "monitor": None}, w))
            continue
        key = (monitor, ws.get("name") or ws.get("index"))
        if key not in named and target:
            # niri keeps an empty workspace last on each monitor, and adds
            # another when that one gets a name.
            last = max(
                (x["idx"] for x in niri_json("workspaces")
                 if x.get("output") == target and x.get("active_window_id") is None),
                default=None,
            )
            if last is not None:
                ref = base = f"{monitor}-{ws.get('name') or ws.get('index') or 1}"
                n = 1
                while ref in taken:
                    n += 1
                    ref = f"{base}-{n}"
                taken.add(ref)
                # An index is on the focused monitor: the target.
                niri_action("set-workspace-name", "--workspace", str(last), ref)
                named[key] = ref
        if key in named:
            out.append(({**e, "monitor": target, "workspace": {"index": None, "name": named[key]}}, w))
        else:
            out.append(({**e, "monitor": None}, w))
    return out, list(named.values()), target


def pin_workspaces(pairs, outputs):
    """Names the workspaces 1…N of each connected monitor that windows go to
    by index, so they stay put while the windows move: niri removes a
    workspace that empties and adds one where a window lands, so the indices
    shift (workspace 2's windows closed, 3 became 2: a window restored to 2
    joins them and the ones for 3 go after). Only when a window isn't on its
    saved workspace already. Returns (pairs, the names to unset)."""
    wss = {ws["id"]: ws for ws in niri_json("workspaces")}
    now = {w["id"]: w for w in windows()}
    want = {}
    for e, w in pairs:
        ws = e.get("workspace") or {}
        if e.get("monitor") in outputs and not ws.get("name") and ws.get("index"):
            want.setdefault(e["monitor"], [0, False])
            want[e["monitor"]][0] = max(want[e["monitor"]][0], min(int(ws["index"]), 255))
            want[e["monitor"]][1] |= not on_workspace(e, now.get(w["id"], w), wss)
    want = {m: n for m, (n, moves) in want.items() if moves}
    if not want:
        return pairs, []
    focused = (niri_json("focused-output") or {}).get("name")
    taken = {ws.get("name") for ws in wss.values() if ws.get("name")}
    slots, temp = {}, []
    for monitor, count in sorted(want.items()):
        # An index is on the focused monitor. Each one named that is the last
        # (empty) workspace gives the monitor another: slot i is always there.
        niri_action("focus-monitor", monitor)
        for i in range(1, count + 1):
            ws = next((x for x in niri_json("workspaces") if x.get("output") == monitor and x.get("idx") == i), None)
            if ws is None:
                break
            if ws.get("name"):
                slots[(monitor, i)] = ws["name"], ws["id"]
                continue
            ref = base = f"{monitor}-{i}"
            n = 1
            while ref in taken:
                n += 1
                ref = f"{base}-{n}"
            taken.add(ref)
            niri_action("set-workspace-name", "--workspace", str(i), ref)
            slots[(monitor, i)] = ref, ws["id"]
            temp.append(ref)
    if focused and focused != monitor:
        niri_action("focus-monitor", focused)
    out = []
    for e, w in pairs:
        ws = e.get("workspace") or {}
        slot = None if ws.get("name") else slots.get((e.get("monitor"), ws.get("index")))
        out.append(({**e, "workspace": {"index": None, "name": slot[0], "id": slot[1]}}, w) if slot else (e, w))
    return out, temp


@tool(
    "restore_layout",
    "windows",
    "Put the windows back as a saved layout had them (see list_layouts): "
    "monitors, workspaces, column order and widths, floating positions and "
    "sizes; apps that aren't open are started first (launch_missing, default "
    "true). A layout saved with several monitor setups uses the one for the "
    "monitors connected now; each workspace of a monitor that isn't "
    "connected goes on a new workspace of the focused monitor. One call "
    "does it all.",
    obj(
        {
            "name": {"type": "string"},
            "launch_missing": {"type": "boolean", "description": "Start the apps that aren't open (default true)"},
        },
        ["name"],
    ),
)
def t_restore_layout(ctx, args, close_others=False):
    # On the user's desktop, the shell covers the screens and takes the input
    # while the windows move, as for the user's own restore (Mod+G,
    # WindowLayouts.qml: `layouts coverBegin|coverEnd`; it lifts by itself
    # after 30 s), so a click or a key doesn't land on a window being moved.
    # Best effort: without the shell, the restore goes on uncovered.
    name = as_str(args, "name", max_len=64, pattern=LAYOUT_NAME)
    covered = False
    try:
        covered = widget_call("layouts", "coverBegin", name).startswith("ok")
    except (ToolError, OSError, subprocess.SubprocessError):
        pass
    try:
        return restore_layout_now(ctx, args, close_others)
    finally:
        if covered:
            try:
                widget_call("layouts", "coverEnd")
            except (ToolError, OSError, subprocess.SubprocessError):
                pass


def restore_layout_now(ctx, args, close_others=False):
    # close_others (the user's setting, not the agents' tool): close the
    # windows the layout doesn't have, as their close button would.
    name = as_str(args, "name", max_len=64, pattern=LAYOUT_NAME)
    path = os.path.join(layouts_dir(), f"{name}.json")
    try:
        with open(path, encoding="utf-8") as f:
            setups = layout_setups(json.load(f))
    except (OSError, ValueError, AttributeError):
        setups = []
    setup = pick_setup(setups, connected_monitors())
    if setup is None:
        raise ToolError(f"no saved layout {name!r} (see list_layouts)")
    entries = setup["windows"]
    ctx.guard.check_rate()
    current = windows()
    focused_before = next((w["id"] for w in current if w.get("is_focused")), None)
    pairs, missing, others = match_windows(entries, current, {ws["id"]: ws for ws in niri_json("workspaces")})
    report = []
    if len(setups) > 1:
        report.append(f"the arrangement saved with {', '.join(setup['monitors']) or 'no monitor'}")
    started = []  # [entry, window, when it appeared] of the apps started here

    # Start what isn't open, all at once, then wait for their windows.
    if missing and args.get("launch_missing", True) is not False:
        apps = applications()
        before = {w["id"] for w in current}
        waiting = []
        for e in missing:
            entry = apps.get(e.get("desktop") or "")
            if entry and entry.get("Terminal") != "true":
                niri_action("spawn", "--", *exec_argv(entry))
                waiting.append(e)
            else:
                report.append(f"not reopened (no app to start): {e.get('app_id')} {e.get('title')!r}")
        taken = set()
        deadline = time.monotonic() + 15
        while waiting and time.monotonic() < deadline:
            time.sleep(0.3)
            for w in windows():
                if w["id"] in before or w["id"] in taken:
                    continue
                e = next((e for e in waiting if same_app(e.get("app_id"), w.get("app_id"))), None)
                if e:
                    taken.add(w["id"])
                    waiting.remove(e)
                    pairs.append((e, w))
                    started.append([e, w, time.monotonic()])
                    report.append(f"started {e.get('desktop')}")
        for e in waiting:
            report.append(f"started {e.get('desktop')}, but its window didn't appear within 15 s")
    else:
        report += [f"not open: {e.get('app_id')} {e.get('title')!r}" for e in missing]

    # The saved workspaces by index held in place while windows move (the
    # unplugged monitors' new workspaces then go after them).
    outputs = connected_monitors()
    pairs, temp_names = pin_workspaces(pairs, outputs)

    # Windows saved on a monitor that isn't connected now (a laptop off its
    # dock): each of its workspaces goes on a new workspace of the focused
    # monitor, with its columns, widths and floating windows, so a layout
    # works with any monitors. Put on the saved workspace index instead, they
    # would pile up on this monitor's workspace 1, 2… with its own windows.
    gone = sorted({e["monitor"] for e, w in pairs if e.get("monitor") and e["monitor"] not in outputs})
    target = None
    if gone:
        pairs, folded, target = fold_unplugged(pairs, outputs)
        temp_names += folded
        report.append(
            f"windows of {', '.join(gone)} (not connected) on "
            + (f"{len(folded)} new workspace(s) of {target}" if folded else "their named workspaces")
        )

    # Every step leaves alone what is where the layout has it already: a
    # restore of a layout the windows are in moves nothing.
    def arrange(pairs):
        # 1. Monitor, workspace, floating or tiled.
        now = {w["id"]: w for w in windows()}
        wss = {ws["id"]: ws for ws in niri_json("workspaces")}
        for e, w in pairs:
            wid = str(w["id"])
            if not on_workspace(e, now.get(w["id"], w), wss):
                if e.get("monitor"):
                    niri_action("move-window-to-monitor", "--id", wid, e["monitor"])
                ws = e.get("workspace") or {}
                ref = ws.get("name") or (str(ws["index"]) if ws.get("index") else None)
                if ref:
                    # An index is on the window's monitor, where it just went.
                    niri_action("move-window-to-workspace", "--window-id", wid, "--focus", "false", ref)
            if e.get("floating") != bool(now.get(w["id"], w).get("is_floating")):
                niri_action("move-window-to-floating" if e.get("floating") else "move-window-to-tiling", "--id", wid)

        # 2. Tiled: columns in order, stacked tiles into their column, widths.
        groups = {}
        for e, w in pairs:
            if not e.get("floating") and e.get("column"):
                ws = e.get("workspace") or {}
                groups.setdefault((e.get("monitor"), ws.get("name") or ws.get("index")), []).append((e, w))

        def placed(w):
            # [column, tile] where the window is now, its size.
            layout = (now.get(w["id"]) or {}).get("layout") or {}
            return layout.get("pos_in_scrolling_layout") or [None, None], layout.get("window_size")

        now = {w["id"]: w for w in windows()}
        widths = monitor_widths()
        for group in groups.values():
            columns = {}
            for e, w in group:
                columns.setdefault(e["column"], []).append((e, w))
            stacks = [sorted(columns[col], key=lambda ew: ew[0].get("tile") or 0) for col in sorted(columns)]
            if not in_order(stacks, placed):
                for index, tiles in enumerate(stacks, 1):
                    head = str(tiles[0][1]["id"])
                    niri_action("focus-window", "--id", head)
                    niri_action("move-column-to-index", str(index))
                    for e, w in tiles[1:]:
                        # consume-or-expel expels a window already in the
                        # column: only the ones in another are taken in.
                        now = {w["id"]: w for w in windows()}
                        if placed(w)[0][0] == placed(tiles[0][1])[0][0]:
                            continue
                        wid = str(w["id"])
                        niri_action("focus-window", "--id", wid)
                        niri_action("move-column-to-index", str(index + 1))
                        niri_action("consume-or-expel-window-left", "--id", wid)
                now = {w["id"]: w for w in windows()}
            for tiles in stacks:
                head = tiles[0][1]
                size = tiles[0][0].get("size")
                if is_maximized(tiles[0][0], widths):
                    # Maximized over a width of its own, whatever it is now
                    # (a fixed full width from an older restore included).
                    niri_action("set-window-width", "--id", str(head["id"]), UNMAXIMIZED_WIDTH)
                    niri_action("focus-window", "--id", str(head["id"]))
                    niri_action("maximize-column")
                elif size and not close(size[:1], (placed(head)[1] or [])[:1]):
                    niri_action("set-window-width", "--id", str(head["id"]), str(int(size[0])))
                if len(tiles) > 1:
                    for e, w in tiles:
                        if e.get("size") and not close(e["size"][1:], (placed(w)[1] or [])[1:]):
                            niri_action("set-window-height", "--id", str(w["id"]), str(int(e["size"][1])))

        # 3. Floating: size, then position. niri places a fixed position within
        # the working area (without the bar), the saved one is on the whole
        # monitor: measure where it landed and correct by the difference.
        now = {w["id"]: w for w in windows()}

        def floating_placed(e, w):
            layout = (now.get(w["id"]) or {}).get("layout") or {}
            return (not e.get("size") or close(e["size"], layout.get("window_size"))) \
                and close(e["position"], layout.get("tile_pos_in_workspace_view"))

        floating = [(e, w) for e, w in pairs if e.get("floating") and e.get("position") and not floating_placed(e, w)]
        for e, w in floating:
            wid = str(w["id"])
            if e.get("size"):
                niri_action("set-window-width", "--id", wid, str(int(e["size"][0])))
                niri_action("set-window-height", "--id", wid, str(int(e["size"][1])))
            niri_action("move-floating-window", "--id", wid, "-x", str(max(0, e["position"][0])), "-y", str(max(0, e["position"][1])))
        if floating:
            now = {w["id"]: w for w in windows()}
            for e, w in floating:
                pos = ((now.get(w["id"]) or {}).get("layout") or {}).get("tile_pos_in_workspace_view")
                if pos:
                    dx, dy = round(e["position"][0] - pos[0]), round(e["position"][1] - pos[1])
                    if dx or dy:
                        niri_action("move-floating-window", "--id", str(w["id"]), "-x", f"{dx:+d}", "-y", f"{dy:+d}")


    arrange(pairs)

    # An app's first window may be a splash with the app's id (Vesktop's
    # "Loading"), gone a few seconds later for the app's own: watch the
    # started apps' windows for 5 s after they appeared, and arrange again
    # with the one that replaced a window gone.
    settle = max((s[2] for s in started), default=0) + 5
    while time.monotonic() < settle:
        time.sleep(0.3)
        now = windows()
        ids = {w["id"] for w in now}
        swapped = {}
        for s in started:
            if s[1]["id"] in ids:
                continue
            new = next((w for w in now if w["id"] not in before and w["id"] not in taken
                        and same_app(w.get("app_id"), s[0].get("app_id"))), None)
            if new:
                taken.add(new["id"])
                swapped[s[1]["id"]] = new
                s[1] = new
        if swapped:
            pairs = [(e, swapped.get(w["id"], w)) for e, w in pairs]
            arrange(pairs)

    # The new workspaces were named only to be found while arranging (an
    # index shifts as windows leave others).
    for ref in temp_names:
        niri_action("unset-workspace-name", ref)

    # 4. Close the windows the layout doesn't have.
    closed = []
    if close_others and others:
        for w in others:
            niri_action("close-window", "--id", str(w["id"]))
            closed.append(w)
        report.append("closed: " + ", ".join(sorted({w.get("app_id") or "?" for w in closed})))

    if focused_before is not None and not any(w["id"] == focused_before for w in closed) \
            and any(w["id"] == focused_before for w in windows()):
        niri_action("focus-window", "--id", str(focused_before))
    set_current_layout(name)
    count_use("layouts", name)
    summary = f"restored layout {name!r}: {len(pairs)} of {len(entries)} windows placed"
    if gone:
        summary += f" ({', '.join(gone)} not connected: on workspaces of {target or 'the others'})"
    if closed:
        summary += f", {len(closed)} other{'s' if len(closed) > 1 else ''} closed"
    report.insert(0, summary)
    return [text("\n".join(report))]


# -- project contexts ------------------------------------------------------------
# A project is a whole context to come back to: its window layout (saved as
# the hidden layout _project-NAME, or a layout of the user's by name), its
# Zen tabs, Do Not Disturb on or off while it is open, and a focus timer.
# "Work on the hackathon" (project open) puts the windows back, opens the
# tabs that aren't open, then DND and the timer; "pause the hackathon"
# (project pause) saves all that as it is now and, as the project's own
# rule says (onPause), leaves it (keep) or closes its tabs (tabs).
# Saved in $XDG_STATE_HOME/nixbook-shell/contexts/NAME.json (0600); the one
# open last in contexts/.current. The user's side: `nixbook-desktop-mcp
# project` (services/Projects.qml), without the agents' pause and tool groups.

PROJECT_NAME = r"[A-Za-z0-9][\w.\-]{0,47}"
PROJECT_LAYOUT_PREFIX = "_project-"
PROJECT_TABS_MAX = 30
PROJECT_PAUSE_RULES = ("keep", "tabs")
PROJECT_FOCUS_MAX = 240


def projects_dir():
    path = os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "contexts")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def project_path(name):
    if not re.fullmatch(PROJECT_NAME, str(name or "")):
        raise ToolError("a project name: letters, digits, '.', '-' and '_' (not first), at most 48")
    return os.path.join(projects_dir(), f"{name}.json")


def project_name_of(value):
    """A name as said ("Hackathon 2026") to a project's file name, or
    an existing project's whose name it is, whatever the case."""
    raw = str(value or "").strip()
    want = re.sub(r"\s+", "-", raw)
    for p in projects_index():
        if p["name"].lower() in (want.lower(), raw.lower()) or p["name"].lower().replace("-", " ") == raw.lower():
            return p["name"]
    return want


def read_project(name):
    try:
        with open(project_path(name), encoding="utf-8") as f:
            doc = json.load(f)
        if not isinstance(doc, dict):
            raise ValueError
    except (OSError, ValueError):
        raise ToolError(f"no project {name!r} (project_list lists them)")
    doc["name"] = name
    return doc


def write_project(doc):
    path = project_path(doc["name"])
    fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    os.replace(path + ".tmp", path)


def current_project():
    try:
        with open(os.path.join(projects_dir(), ".current"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def set_current_project(name):
    path = os.path.join(projects_dir(), ".current")
    try:
        if name:
            with open(path, "w", encoding="utf-8") as f:
                f.write(name)
        else:
            os.unlink(path)
    except OSError:
        pass


def project_summary(doc):
    return {
        "name": doc["name"], "state": doc.get("state") or "paused", "saved": doc.get("saved"),
        "opened": doc.get("opened"), "paused": doc.get("paused"), "layout": doc.get("layout") or "",
        "apps": doc.get("apps") or [], "tabs": [t.get("title") or t.get("url") for t in doc.get("tabs") or []],
        "dnd": doc.get("dnd"), "focus": doc.get("focus"), "onPause": doc.get("onPause") or "keep",
    }


def projects_index():
    out = []
    try:
        names = sorted(os.listdir(projects_dir()))
    except OSError:
        return out
    for fn in names:
        if not fn.endswith(".json") or not re.fullmatch(PROJECT_NAME, fn[:-5]):
            continue
        try:
            out.append(project_summary(read_project(fn[:-5])))
        except ToolError:
            continue
    return out


def url_key(url):
    """A page's address as compared: no fragment, no trailing slash."""
    return str(url or "").split("#", 1)[0].rstrip("/").lower()


def project_tabs_now(ctx, doc):
    """The Zen tabs of the project's window: the window with most of its
    saved tabs (else the one with most tabs), not the private ones, the
    pinned ones (Zen keeps those everywhere) or another Zen workspace's.
    [] when Zen isn't reachable."""
    try:
        tabs = zen(ctx, "tabs") or []
    except ToolError:
        return None
    tabs = [t for t in tabs if isinstance(t, dict) and not t.get("private") and not t.get("pinned")
            and not t.get("otherWorkspace") and re.match(r"(?i)^https?://", str(t.get("url") or ""))]
    by_window = {}
    for t in tabs:
        by_window.setdefault(t.get("window"), []).append(t)
    if not by_window:
        return []
    saved = {url_key(t.get("url")) for t in doc.get("tabs") or []}
    best = max(by_window.values(), key=lambda ts: (sum(url_key(t.get("url")) in saved for t in ts), len(ts)))
    return best[:PROJECT_TABS_MAX]


def project_snapshot(ctx, doc):
    """The project as it is now: its layout saved, its tabs. Returns (doc,
    the Zen tabs seen)."""
    layout = doc.get("layout") or ""
    if not layout or layout.startswith(PROJECT_LAYOUT_PREFIX):
        # Its own layout (a user's layout it names is theirs: left as it is).
        layout = PROJECT_LAYOUT_PREFIX + doc["name"]
        # The user's current layout stays theirs.
        current = current_layout()
        t_save_layout(ctx, {"name": layout})
        if current:
            set_current_layout(current)
        else:
            with contextlib.suppress(OSError):
                os.unlink(current_layout_path())
    doc["layout"] = layout
    tabs = project_tabs_now(ctx, doc)
    if tabs is not None:
        doc["tabs"] = [{"url": t["url"], "title": short(t.get("title") or "", 120)} for t in tabs]
    try:
        with open(os.path.join(layouts_dir(), f"{layout}.json"), encoding="utf-8") as f:
            setup = pick_setup(layout_setups(json.load(f)), connected_monitors()) or {"windows": []}
        doc["apps"] = sorted({w.get("desktop") or w.get("app_id") or "?" for w in setup["windows"]})
    except (OSError, ValueError, AttributeError):
        pass
    doc["saved"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    return doc, tabs or []


def project_settings(doc, args, user=False):
    """The project's own options from a call: dnd (true, false, null = left
    alone), focus_minutes (0 = none; or "pomodoro"), on_pause (keep, tabs)."""
    if "dnd" in args:
        if args["dnd"] not in (True, False, None):
            raise ToolError("`dnd`: true, false or null")
        doc["dnd"] = args["dnd"]
    if "focus_minutes" in args:
        v = args["focus_minutes"]
        if v == "pomodoro":
            doc["focus"] = {"kind": "pomodoro"}
        elif isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= PROJECT_FOCUS_MAX:
            doc["focus"] = {"kind": "countdown", "minutes": v} if v else None
        else:
            raise ToolError(f"`focus_minutes`: 0 to {PROJECT_FOCUS_MAX}, or \"pomodoro\"")
    if "on_pause" in args:
        rule = args["on_pause"]
        if rule not in PROJECT_PAUSE_RULES:
            raise ToolError(f"`on_pause`: one of {', '.join(PROJECT_PAUSE_RULES)}")
        doc["onPause"] = rule
    return doc


def shell_dnd(state):
    """Do Not Disturb through the shell (its `notifications` IPC target):
    on, off, or status (whether it is on)."""
    out = (qs_ipc("call", "notifications", "dnd", state).stdout or "").strip()
    if out.startswith("error"):
        raise ToolError(out)
    try:
        return bool(json.loads(out).get("silent"))
    except (ValueError, AttributeError):
        raise ToolError(f"the shell didn't answer: {short(out, 80)!r}")


def zen_ready(ctx, timeout):
    """Zen's bridge answering, waited for up to `timeout` s."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            zen(ctx, "ping")
            return True
        except ToolError:
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.5)


def start_zen(ctx):
    apps = applications()
    entry_id = next((i for i in sorted(apps) if re.search(r"(?i)\bzen\b|zen[-_.]browser|zen-twilight", i)
                     and apps[i].get("NoDisplay") != "true"), None)
    if not entry_id:
        return False
    niri_action("spawn", "--", *exec_argv(apps[entry_id]))
    return True


def first_text(content):
    return next((c.get("text", "") for c in content or [] if c.get("type") == "text"), "")


def project_open_now(ctx, name, user=False):
    doc = read_project(name)
    report = []
    pages_on = user or "pages" in ctx.cfg["tools"]
    # 1. The windows where they were.
    layout = doc.get("layout") or ""
    if layout and os.path.exists(os.path.join(layouts_dir(), f"{layout}.json")):
        current = current_layout()
        report.append(first_text(t_restore_layout(ctx, {"name": layout})))
        if layout.startswith(PROJECT_LAYOUT_PREFIX):
            # Its own hidden layout isn't the user's current one.
            set_current_layout(current)
    elif layout:
        report.append(f"its layout {layout!r} is gone: windows left as they are")
    # 2. Its tabs that aren't open.
    tabs = doc.get("tabs") or []
    if tabs and not pages_on:
        report.append("tabs not opened: the page tools are off")
    elif tabs:
        ready = zen_ready(ctx, 0)
        if not ready and start_zen(ctx):
            ready = zen_ready(ctx, 15)
        if not ready:
            report.append("tabs not opened: Zen isn't reachable (its nixbook extension)")
        else:
            try:
                have = {url_key(t.get("url")) for t in zen(ctx, "tabs") or [] if isinstance(t, dict)}
            except ToolError:
                have = set()
            opened, refused = 0, []
            for t in tabs:
                if url_key(t.get("url")) in have:
                    continue
                try:
                    zen(ctx, "open", url=t["url"], active=False, wait=False)
                    have.add(url_key(t.get("url")))
                    opened += 1
                except ToolError as e:
                    refused.append(f"{short(t.get('url') or '', 60)} ({e})")
            report.append(f"{opened} tab{'s' if opened != 1 else ''} opened, {len(tabs) - opened - len(refused)} "
                          "already open" + (f"; not opened: {'; '.join(refused)}" if refused else ""))
    # 3. Do Not Disturb and the focus timer, as it wants them (what DND was
    #    before kept, for its pause).
    started = {}
    if doc.get("dnd") in (True, False):
        try:
            started["dnd"] = shell_dnd("status")
            shell_dnd("on" if doc["dnd"] else "off")
            report.append("Do Not Disturb " + ("on" if doc["dnd"] else "off"))
        except ToolError as e:
            started.pop("dnd", None)
            report.append(f"Do Not Disturb not changed: {e}")
    focus = doc.get("focus") or {}
    try:
        if focus.get("kind") == "countdown" and focus.get("minutes"):
            qs_ipc("call", "timers", "countdownReset")
            qs_ipc("call", "timers", "countdownAdd", str(int(focus["minutes"])))
            started["focus"] = "countdown"
            report.append(f"focus timer: {int(focus['minutes'])} min")
        elif focus.get("kind") == "pomodoro":
            status = json.loads(qs_ipc("call", "timers", "status").stdout or "{}")
            if not (status.get("pomodoro") or {}).get("running"):
                qs_ipc("call", "timers", "pomodoroToggle")
                started["focus"] = "pomodoro"
            report.append("pomodoro running")
    except (ToolError, ValueError) as e:
        report.append(f"focus timer not started: {e}")
    doc["state"], doc["opened"], doc["started"] = "open", time.strftime("%Y-%m-%dT%H:%M:%S%z"), started
    write_project(doc)
    set_current_project(name)
    count_use("layouts", f"project:{name}")
    return [text(f"opened project {name!r}: " + "; ".join(r for r in report if r) if report
                 else f"opened project {name!r}")]


def project_pause_now(ctx, name, user=False, create=False):
    """Saves the project as it is now; then its pause rule, DND and the
    timer back as they were. create: a new project (project_save)."""
    try:
        doc = read_project(name)
    except ToolError:
        if not create:
            raise
        doc = {"name": name, "onPause": "keep", "dnd": None, "focus": None, "created": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    doc, tabs = project_snapshot(ctx, doc)
    report = [f"saved project {name!r}: {len(doc.get('apps') or [])} apps, {len(doc.get('tabs') or [])} tabs"]
    rule = doc.get("onPause") or "keep"
    if rule == "tabs" and tabs:
        closed = 0
        for t in tabs:
            with contextlib.suppress(ToolError):
                zen(ctx, "tab", tab=t["id"], action="close")
                closed += 1
        report.append(f"{closed} tab{'s' if closed != 1 else ''} closed")
    started = doc.pop("started", None) or {}
    if "dnd" in started:
        with contextlib.suppress(ToolError):
            shell_dnd("on" if started["dnd"] else "off")
            report.append("Do Not Disturb back " + ("on" if started["dnd"] else "off"))
    if started.get("focus") == "countdown":
        with contextlib.suppress(ToolError):
            qs_ipc("call", "timers", "countdownReset")
            report.append("focus timer stopped")
    elif started.get("focus") == "pomodoro":
        with contextlib.suppress(ToolError):
            qs_ipc("call", "timers", "pomodoroReset")
            report.append("pomodoro stopped")
    doc["state"], doc["paused"] = "paused", time.strftime("%Y-%m-%dT%H:%M:%S%z")
    if current_project() == name:
        set_current_project("")
    write_project(doc)
    return [text("; ".join(report))]


PROJECT_ACTIONS = ("list", "open", "save", "pause")


@tool(
    "project",
    "windows",
    "The user's projects, each a whole context: its window layout, the Zen tabs of its window, Do Not "
    "Disturb and a focus timer. list: them all (open or paused, their apps and tabs, the one open now). "
    "open: as the user left it, in one call (\"work on the hackathon\"): the windows where they were "
    "(apps not open started), its tabs that aren't open, DND and its timer. save: the desktop as it is now into it "
    "(a new one, or update it). pause: saved, then its tabs closed if its rule says so, DND and the timer "
    "back as they were (\"pause the hackathon\"). dnd (true, false, null: left alone), focus_minutes (0: "
    "none, or \"pomodoro\") and on_pause (keep, or tabs: close its tabs) set what opening and pausing it do.",
    obj({
        "action": {"type": "string", "enum": list(PROJECT_ACTIONS)},
        "name": {"type": "string"},
        "dnd": {"type": ["boolean", "null"]},
        "focus_minutes": {"type": ["integer", "string"]},
        "on_pause": {"type": "string", "enum": ["keep", "tabs"]},
    }, ["action"]),
    brief="Projects (windows, Zen tabs, DND, timer): list, open (\"work on X\"), save the "
          "desktop into one, pause (\"pause X\").",
)
def t_project(ctx, args):
    action = args.get("action")
    if action not in PROJECT_ACTIONS:
        raise ToolError(f"`action`: one of {', '.join(PROJECT_ACTIONS)}")
    if action == "list":
        return [text({"current": current_project(), "projects": projects_index()})]
    name = project_name_of(as_str(args, "name", max_len=64))
    project_path(name)
    if action == "open":
        return project_open_now(ctx, name)
    ctx.guard.check_rate()
    return project_save_now(ctx, name, args, pause=action == "pause")


def new_project(name):
    return {"name": name, "onPause": "keep", "dnd": None, "focus": None,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S%z")}


def project_save_now(ctx, name, args, pause=False, user=False):
    """Saves (and with pause, pauses) a project, its options from args first."""
    if any(k in args for k in ("dnd", "focus_minutes", "on_pause")):
        try:
            doc = read_project(name)
        except ToolError:
            # Saved from the desktop as it is: the one being worked on.
            doc = {**new_project(name), "state": "open"}
        write_project(project_settings(doc, args, user))
    if pause:
        return project_pause_now(ctx, name, user, create=True)
    try:
        doc = read_project(name)
    except ToolError:
        # Saved from the desktop as it is: the one being worked on.
        doc = {**new_project(name), "state": "open"}
    doc, _ = project_snapshot(ctx, doc)
    write_project(doc)
    if doc.get("state") == "open":
        set_current_project(name)
    return [text(f"saved project {name!r}: {len(doc.get('apps') or [])} apps, {len(doc.get('tabs') or [])} tabs")]


# -- screen and clipboard ----------------------------------------------------

COORD = {"type": "number"}


@tool(
    "screenshot",
    "screen",
    "Take a screenshot of a monitor (default: the focused one); of a `region` "
    "of the desktop, at full resolution, to zoom in on small things before "
    "clicking; or of a window on screen with `window_id` (a floating one "
    "exactly, a tiled one with its monitor). All of these are silent. Every "
    "screenshot comes with a `mapping`: pass it as `screenshot` to "
    "click/move_pointer/drag/scroll to give them this image's pixel "
    "coordinates. A window not on screen: focus it first (focus_window with "
    "screenshot_after does both in one call). A monitor screenshot sends only "
    "what changed since your last one of it (the rest is as you saw it), or "
    "says nothing did; `full` sends it all. To read a window's buttons, "
    "fields or text, or to check that something showed, ui_read and "
    "ui_wait cost far less and are exact: screenshot when they show "
    "nothing (games, canvases) or for the look of things.",
    obj(
        {
            "monitor": {"type": "string", "description": "Monitor name (see list_workspaces)"},
            "region": {
                "type": "object",
                "description": "A desktop rectangle in logical pixels (e.g. around a button, from an earlier screenshot)",
                "properties": {"x": COORD, "y": COORD, "width": COORD, "height": COORD},
                "required": ["x", "y", "width", "height"],
            },
            "window_id": {"type": "integer", "description": "A window id (see list_windows), on screen"},
            "offscreen": {
                "type": "boolean",
                "description": "Capture a window that isn't on screen through niri. Avoid: it "
                "copies the capture to the user's clipboard and notifies them",
            },
            "full": {"type": "boolean", "description": "The whole monitor, even when little or nothing changed"},
        }
    ),
    read_only=True,
)
def t_screenshot(ctx, args):
    with overlays_hidden(ctx) as shown:
        out = screenshot_now(ctx, args)
    note = overlays_note(ctx, shown) if getattr(ctx, "hiding", 0) == 0 else None
    return out + [note] if note else out


def screenshot_now(ctx, args):
    outputs = {n: o for n, o in (niri_json("outputs") or {}).items() if o.get("logical")}
    if args.get("window_id") is not None:
        wid = as_int(args, "window_id")
        w = window_by_id(wid)
        ws = next((x for x in niri_json("workspaces") if x.get("id") == w.get("workspace_id")), None)
        on_screen = bool(ws and ws.get("is_active") and ws.get("output") in outputs)
        if not on_screen:
            if args.get("offscreen") is not True:
                raise ToolError(
                    f"window {wid} isn't on screen. Focus it first (focus_window with "
                    "screenshot_after: true), or pass offscreen: true to capture it through niri, "
                    "which copies it to the user's clipboard and notifies them."
                )
            return screenshot_window(ctx, wid)
        # On screen: grim, silent. niri gives the position of floating windows
        # only; a tiled one comes with its whole monitor.
        lg = outputs[ws["output"]]["logical"]
        layout = w.get("layout") or {}
        pos, size = layout.get("tile_pos_in_workspace_view"), layout.get("window_size")
        if w.get("is_floating") and pos and size:
            off = layout.get("window_offset_in_tile") or [0, 0]
            region = {"x": lg["x"] + pos[0] + off[0], "y": lg["y"] + pos[1] + off[1], "width": size[0], "height": size[1]}
            return screenshot_now(ctx, {"region": region})
        out = screenshot_now(ctx, {"monitor": ws["output"]})
        out[0]["text"] = f"Window {wid} ({w.get('app_id')}) is tiled on {ws['output']}: the whole monitor.\n" + out[0]["text"]
        return out
    max_edge = int(ctx.cfg.get("screenshotMaxEdge", 1280))
    if args.get("region") is not None:
        r = args["region"]
        if not isinstance(r, dict):
            raise ToolError("`region` must be {x, y, width, height}")
        x, y = point(r)
        w, h = point(r, "width", "height")
        x, y, w, h = round(x), round(y), round(w), round(h)
        if w < 4 or h < 4:
            raise ToolError("`region` must be at least 4x4 logical pixels")
        bx, by, bw, bh = desktop_bbox()
        x, y = max(x, bx), max(y, by)
        w, h = min(w, bx + bw - x), min(h, by + bh - y)
        if w < 4 or h < 4:
            raise ToolError(f"`region` is outside the desktop ({bx},{by} {bw}x{bh})")
        # As sharp as the sharpest monitor it covers, within the size limit.
        covered = [
            o["logical"].get("scale") or 1
            for o in outputs.values()
            if o["logical"]["x"] < x + w and x < o["logical"]["x"] + o["logical"]["width"]
            and o["logical"]["y"] < y + h and y < o["logical"]["y"] + o["logical"]["height"]
        ] or [1]
        scale = min(max(covered), max_edge / max(w, h))
        grim = ["-g", f"{x},{y} {w}x{h}"]
        what = f"Region {w}x{h} at ({x},{y})"
        private_in_view(ctx, x, y, w, h)
    else:
        name = as_str(args, "monitor", required=False, max_len=64, pattern=r"[\w.\-]+")
        if not name:
            name = (niri_json("focused-output") or {}).get("name")
        if name not in outputs:
            raise ToolError(f"no monitor {name!r}; monitors: {', '.join(outputs)}")
        lg = outputs[name]["logical"]
        x, y, w, h = lg.get("x", 0), lg.get("y", 0), lg.get("width") or 1, lg.get("height") or 1
        scale = min(1.0, max_edge / max(w, h))
        grim = ["-o", name]
        what = f"Monitor {name}: {w}x{h} logical pixels at ({x},{y})"
        private_in_view(ctx, x, y, w, h)
        if ctx.transport != "cli" and shutil.which("magick"):
            return monitor_screenshot(ctx, name, grim, round(scale, 4), x, y, what, args.get("full") is True)
    scale = round(scale, 4)
    if ctx.cfg.get("screenshotFormat") == "png":
        path = os.path.join(runtime_dir(), f"screenshot-{secrets.token_hex(4)}.png")
        run(["grim", *grim, "-s", f"{scale:.4f}", "-t", "png", path], timeout=15)
    else:
        path = os.path.join(runtime_dir(), f"screenshot-{secrets.token_hex(4)}.jpg")
        quality = min(max(int(ctx.cfg.get("screenshotQuality", 80)), 10), 100)
        run(["grim", *grim, "-s", f"{scale:.4f}", "-t", "jpeg", "-q", str(quality), path], timeout=15)
    mapping = {"x": x, "y": y, "scale": scale}
    info = (
        f"{what}, image scale {scale:g}.\n"
        f"mapping: {json.dumps(mapping)}\n"
        "To click something in this image, pass its pixel coordinates as x, y "
        "with this mapping as `screenshot` (desktop x = mapping.x + image_x / scale). "
        "To see small things better, take a `region` screenshot around them."
    )
    return screenshot_reply(ctx, path, info)
