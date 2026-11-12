# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Apps' accessibility trees (the ui_* tools).

# Roles listed (with their name, value or text); the others only hold them.
UI_ROLES = {
    "push button", "toggle button", "check box", "radio button", "menu item", "check menu item",
    "radio menu item", "menu", "combo box", "list item", "tree item", "page tab", "link", "entry",
    "text", "spin button", "slider", "label", "heading", "table cell", "icon", "image", "button",
    "switch", "search", "notification", "alert", "dialog", "status bar", "editbar", "terminal",
    "paragraph", "static", "tool bar", "list box", "option",
}
UI_MAX_VISITS = 4000
UI_TIMEOUT_S = 8


def atspi_bus_check(Gio, GLib):
    """Connect to the accessibility bus the way libatspi will, first: when it
    can't, libatspi calls g_error(), which aborts the whole process (no
    exception) — e.g. once another at-spi bus launcher sharing
    $XDG_RUNTIME_DIR replaced at-spi/bus_0 with a socket nobody listens on."""
    try:
        address = os.environ.get("AT_SPI_BUS_ADDRESS")
        if not address:
            session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            reply = session.call_sync(
                "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress",
                None, GLib.VariantType.new("(s)"), Gio.DBusCallFlags.NONE, 3000, None)
            address = reply.unpack()[0]
        conn = Gio.DBusConnection.new_for_address_sync(
            address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        conn.close_sync(None)
    except GLib.Error as e:
        raise ToolError(
            f"the accessibility bus is unreachable ({e.message}); restart it with "
            "`systemctl --user restart at-spi-dbus-bus`, or log out and in again"
        )


def atspi():
    try:
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi, Gio, GLib
    except (ImportError, ValueError) as e:
        raise ToolError(f"the accessibility tools need PyGObject and at-spi2-core's typelib ({e})")
    atspi_bus_check(Gio, GLib)
    Atspi.set_timeout(1500, 5000)
    return Atspi


def ui_refs_path():
    return os.path.join(runtime_dir(), "ui-refs.json")


def ui_window(ctx, args):
    """The niri window asked for (or the focused one), once checked."""
    wid = args.get("window_id")
    w = window_by_id(wid) if wid is not None else focused_window()
    if not w:
        raise ToolError("no window: give `window_id` (list_windows)")
    app, title = w.get("app_id") or "", w.get("title") or ""
    for pat in ctx.cfg.get("inputDenyApps", []):
        if re.search(pat, app, re.IGNORECASE):
            raise ToolError(f"refused: {app!r} is off limits (terminals, password managers)")
    for pat in ctx.cfg.get("inputDenyTitles", []):
        if re.search(pat, title, re.IGNORECASE):
            raise ToolError("refused: that window looks like a password or authentication prompt")
    if window_private(w, ctx.cfg):
        raise ToolError("refused: that window is private (private browsing, or a password manager's): "
                        "neither read nor used")
    return w


def ui_frame(Atspi, w):
    """The window's frame in the accessibility tree: its app by pid, then
    the frame with its title (or the active one)."""
    pid = w.get("pid")
    desktop = Atspi.get_desktop(0)
    apps = []
    for i in range(desktop.get_child_count()):
        a = desktop.get_child_at_index(i)
        try:
            if a is not None and a.get_process_id() == pid:
                apps.append((i, a))
        except Exception:
            continue
    if not apps:
        raise ToolError(
            f"{w.get('app_id')} shows no accessibility tree: it may not support it, or it was started "
            "before accessibility was on (restart it). Chromium/Electron apps need ACCESSIBILITY_ENABLED=1, "
            "Firefox-based ones GNOME_ACCESSIBILITY=1 (the Home Manager module sets both)."
        )
    title = w.get("title") or ""
    frames = []
    for ai, app in apps:
        for j in range(app.get_child_count()):
            f = app.get_child_at_index(j)
            if f is not None:
                frames.append(([ai, j], f))
    if not frames:
        raise ToolError(f"{w.get('app_id')}'s accessibility tree has no window")
    for path, f in frames:
        if (f.get_name() or "") == title:
            return path, f
    for path, f in frames:
        if f.get_state_set().contains(Atspi.StateType.ACTIVE):
            return path, f
    return frames[0]


def ui_states(Atspi, node):
    s = node.get_state_set()
    out = []
    for state, label in ((Atspi.StateType.FOCUSED, "focused"), (Atspi.StateType.CHECKED, "checked"),
                         (Atspi.StateType.SELECTED, "selected"), (Atspi.StateType.EXPANDED, "expanded"),
                         (Atspi.StateType.PRESSED, "pressed")):
        if s.contains(state):
            out.append(label)
    if not s.contains(Atspi.StateType.ENABLED) and not s.contains(Atspi.StateType.SENSITIVE):
        out.append("disabled")
    if s.contains(Atspi.StateType.EDITABLE):
        out.append("editable")
    return out


def ui_text(Atspi, node, role):
    """An element's own text, short; never a password field's."""
    if role == "password text":
        return ""
    try:
        if node.get_text_iface() is not None:
            n = Atspi.Text.get_character_count(node)
            # U+FFFC: an embedded object (a link, an image) in the text.
            return (Atspi.Text.get_text(node, 0, min(n, 200)) or "").replace("￼", "").strip()
    except Exception:
        pass
    try:
        if node.get_value_iface() is not None:
            return f"{Atspi.Value.get_current_value(node):g}"
    except Exception:
        pass
    return ""


def ui_walk(Atspi, frame, frame_path, find, cap):
    """The showing, named or actionable elements of a window: [(path, role, name, text, states)]."""
    out, visits, deadline = [], 0, time.monotonic() + UI_TIMEOUT_S
    stack = [(frame, frame_path, 0)]
    truncated = False
    while stack:
        node, path, depth = stack.pop()
        visits += 1
        if visits > UI_MAX_VISITS or time.monotonic() > deadline or len(out) >= cap:
            truncated = True
            break
        try:
            states = node.get_state_set()
            if depth and not states.contains(Atspi.StateType.SHOWING):
                continue
            role = node.get_role_name() or ""
            name = (node.get_name() or "").strip()
            count = node.get_child_count()
        except Exception:
            continue
        if depth and (role in UI_ROLES or role == "password text"):
            text_ = ui_text(Atspi, node, role)
            if name or text_ or role in ("entry", "text", "password text", "push button", "check box", "toggle button"):
                line = f"{role} {name!r}" + (f" = {text_[:80]!r}" if text_ and text_ != name else "")
                if not find or find in line.lower():
                    out.append((path, role, name, line, ui_states(Atspi, node)))
        if depth < 60:
            # Children pushed in reverse: read in document order.
            for i in reversed(range(min(count, 500))):
                try:
                    child = node.get_child_at_index(i)
                except Exception:
                    continue
                if child is not None:
                    stack.append((child, path + [i], depth + 1))
    return out, truncated


def ui_resolve(Atspi, path):
    node = Atspi.get_desktop(0)
    for i in path:
        node = node.get_child_at_index(i) if node is not None else None
    return node


@tool(
    "ui_read",
    "ui",
    "Read a window as text through its accessibility tree (what screen "
    "readers see): its buttons, fields, labels, list items… numbered for "
    "ui_act, with their text and state (focused, checked…). A few hundred "
    "tokens instead of a screenshot, and exact. The focused window unless "
    "`window_id`; only what's showing. To wait for something to show, "
    "ui_wait. Prefer `find`: what you read goes to "
    "the model provider. Password fields never show their text; terminals "
    "and password managers are refused.",
    obj({
        "window_id": {"type": "integer", "description": "From list_windows; default: the focused window"},
        "find": {"type": "string", "description": "Only the elements whose line contains this"},
        "max_elements": {"type": "integer", "description": "At most this many (default 80, at most 400)"},
    }),
    read_only=True,
)
def t_ui_read(ctx, args):
    w = ui_window(ctx, args)
    Atspi = atspi()
    find = (as_str(args, "find", max_len=200, required=False) or "").lower()
    cap = min(max(int(args.get("max_elements") or 80), 1), 400)
    frame_path, frame = ui_frame(Atspi, w)
    found, truncated = ui_walk(Atspi, frame, frame_path, find, cap)
    head = f"{w.get('app_id')} — {w.get('title')!r} (window {w.get('id')})"
    if not found:
        ui_listing(w, found, frame_path)
        return [text(head + "\n" + ("nothing matches" if find else "no element showing"))]
    more = "\n… (more: raise max_elements or use find)" if truncated else ""
    return [text(head + "\n" + ui_listing(w, found, frame_path) + more)]


def ui_listing(w, found, frame_path=None):
    """The elements as numbered lines, saved for ui_act's `index` (with the
    window's frame, for the targets ui_act learns)."""
    refs = {"window": w.get("id"), "pid": w.get("pid"), "frame": frame_path, "items": []}
    lines = []
    for n, (path, role, name, line, states) in enumerate(found, 1):
        refs["items"].append({"path": path, "role": role, "name": name})
        lines.append(f"[{n}] {line}" + (f" ({', '.join(states)})" if states else ""))
    fd = os.open(ui_refs_path(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(refs, f)
    return "\n".join(lines)


# What makes ui_wait read the window again: the tree or a text changed.
UI_WAIT_EVENTS = (
    "object:children-changed", "object:state-changed", "object:text-changed",
    "object:property-change:accessible-name", "document:load-complete", "window:activate",
)
# One ui_wait at a time pumps the GLib main context (libatspi's events come
# through it); a second one meanwhile polls.
_ui_events_lock = threading.Lock()


def ui_event_waiter(Atspi):
    """A function waiting up to `seconds` for an accessibility event (True
    when one came) and its cleanup, or (None, None) when events can't be
    listened to: ui_wait then polls."""
    try:
        from gi.repository import GLib
        if not _ui_events_lock.acquire(blocking=False):
            return None, None
        changed = [False]

        def on_event(_event):
            changed[0] = True

        listener = Atspi.EventListener.new(on_event)
        registered = [e for e in UI_WAIT_EVENTS if listener.register(e)]
    except Exception:
        if _ui_events_lock.locked():
            _ui_events_lock.release()
        return None, None
    context = GLib.MainContext.default()

    def wait(seconds):
        end = time.monotonic() + seconds
        while not changed[0] and time.monotonic() < end:
            if not context.iteration(False):
                time.sleep(0.02)
        hit, changed[0] = changed[0], False
        return hit

    def close():
        try:
            for e in registered:
                listener.deregister(e)
        finally:
            _ui_events_lock.release()

    if not registered:
        close()
        return None, None
    return wait, close


@tool(
    "ui_wait",
    "ui",
    "Wait until an element whose line contains `find` shows in a window's "
    "accessibility tree (a page loaded, a dialog or result appeared), or "
    "with `gone` until none does (a spinner, a dialog closed); it reads "
    "the window again whenever the app reports a change. Use it instead of "
    "a fixed wait and a screenshot. Returns the matching elements numbered "
    "for ui_act, like ui_read. The focused window unless `window_id`.",
    obj({
        "find": {"type": "string", "description": "Text of the element's line (role, name or text), any case"},
        "gone": {"type": "boolean", "description": "Wait until nothing matches instead"},
        "window_id": {"type": "integer", "description": "From list_windows; default: the focused window"},
        "timeout_ms": {"type": "integer", "description": "Give up after this long (default 5000, at most 15000)"},
    }, ["find"]),
    read_only=True,
)
def t_ui_wait(ctx, args):
    find = as_str(args, "find", max_len=200).lower()
    gone = args.get("gone") is True
    timeout = args.get("timeout_ms", 5000)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or not 100 <= timeout <= 15000:
        raise ToolError("`timeout_ms` must be 100 to 15000")
    w = ui_window(ctx, args)
    Atspi = atspi()
    start = time.monotonic()
    deadline = start + timeout / 1000
    wait, close = ui_event_waiter(Atspi)
    try:
        while True:
            now_w = window_by_id(w.get("id"))
            if not now_w or now_w.get("pid") != w.get("pid"):
                raise ToolError("the window closed while waiting")
            frame_path, frame = ui_frame(Atspi, now_w)
            found, _ = ui_walk(Atspi, frame, frame_path, find, 1 if gone else 20)
            if bool(found) != gone:
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                state = "still showing" if gone else "not showing"
                raise ToolError(f"{find!r} {state} after {timeout} ms: ui_read to see what is")
            if is_paused():
                raise ToolError("stopped: desktop control was paused by the user")
            if wait:
                # Woken by an event: let the burst that follows land first.
                if wait(min(remaining, 1.0)):
                    time.sleep(min(0.15, max(deadline - time.monotonic(), 0)))
            else:
                time.sleep(min(remaining, 0.4))
    finally:
        if close:
            close()
    took = f"after {int((time.monotonic() - start) * 1000)} ms"
    head = f"{now_w.get('app_id')} — {now_w.get('title')!r} (window {now_w.get('id')})"
    if gone:
        return [text(f"{head}\n{find!r} gone {took}")]
    return [text(f"{head}\n{find!r} showing {took}:\n" + ui_listing(now_w, found, frame_path))]


# Actions an element offers, by what ui_act's `click` may use.
UI_CLICK_ACTIONS = ("click", "press", "activate", "toggle", "jump", "open", "select")


# -- learned targets ---------------------------------------------------------
# A control the agent acted on (a button, a tab, a menu item…) is remembered
# per app with its place in the window's tree, so the next time ui_act's
# `target` (its name) reaches it directly: no ui_read, one call instead of
# two, and no walk through a large tree. The place is checked before use
# (same role, same name, showing); a stale one falls back to a search and
# is learned again. Only controls with short names: never list items,
# links, texts or cells, whose names are content (a message, a subject).
# Learned from the agent's own actions only, never from the user's input.
# In the desktop memory (`targets`), cleared with it.

UI_TARGET_ROLES = {
    "push button", "toggle button", "check box", "radio button", "menu item", "check menu item",
    "radio menu item", "menu", "page tab", "combo box", "switch", "button", "spin button", "slider",
}
UI_TARGET_NAME_MAX = 40
UI_TARGETS_PER_APP = 40
UI_TARGET_APPS = 60


def ui_learn(w, frame_path, path, role, name):
    """Remember a control acted on (best effort)."""
    if role not in UI_TARGET_ROLES or not name or len(name) > UI_TARGET_NAME_MAX:
        return
    if not frame_path or list(path[: len(frame_path)]) != list(frame_path):
        return
    app = w.get("app_id") or ""
    if not app:
        return
    rel, now = list(path[len(frame_path):]), int(time.time())
    try:
        with Memory() as m:
            targets = m.data.setdefault("targets", {})
            known = targets.setdefault(app, [])
            t = next((t for t in known if t["role"] == role and t["name"] == name), None)
            if t:
                t.update(path=rel, uses=t.get("uses", 0) + 1, last=now)
            else:
                known.append({"role": role, "name": name, "path": rel, "uses": 1, "last": now})
                if len(known) > UI_TARGETS_PER_APP:
                    known.sort(key=lambda t: (-t.get("uses", 0), -t.get("last", 0)))
                    del known[UI_TARGETS_PER_APP:]
            if len(targets) > UI_TARGET_APPS:
                oldest = min(targets, key=lambda a: max((t.get("last", 0) for t in targets[a]), default=0))
                del targets[oldest]
            m.save()
    except (OSError, ValueError, KeyError, TypeError):
        pass


def ui_targets_for(app_id):
    """The controls learned in an app, most used first: their names."""
    known = (read_memory().get("targets") or {}).get(app_id or "", [])
    return [t["name"] for t in sorted(known, key=lambda t: (-t.get("uses", 0), -t.get("last", 0)))]


def ui_node_is(Atspi, node, role, name):
    try:
        return (node is not None and node.get_role_name() == role
                and (node.get_name() or "").strip() == name
                and node.get_state_set().contains(Atspi.StateType.SHOWING))
    except Exception:
        return False


def ui_find_target(Atspi, w, frame_path, frame, target, role=None):
    """The element named `target` (any case; `role` to tell same names
    apart): where it was learned if it's still there, else searched.
    (node, path, role, name, how)."""
    want = target.strip().lower()
    known = [t for t in (read_memory().get("targets") or {}).get(w.get("app_id") or "", [])
             if t["name"].lower() == want and (not role or t["role"] == role)]
    for t in sorted(known, key=lambda t: -t.get("uses", 0)):
        path = list(frame_path) + t["path"]
        node = ui_resolve(Atspi, path)
        if ui_node_is(Atspi, node, t["role"], t["name"]):
            return node, path, t["role"], t["name"], "learned"
    found, _ = ui_walk(Atspi, frame, frame_path, want, 60)
    exact = [f for f in found if f[2].lower() == want and (not role or f[1] == role)]
    if len(exact) > 1:
        controls = [f for f in exact if f[1] in UI_TARGET_ROLES]
        exact = controls or exact
    if not exact:
        raise ToolError(f"no element named {target!r} showing in {w.get('app_id')}: ui_read (with `find`) to see what is")
    if len(exact) > 1:
        listing = ui_listing(w, exact, frame_path)
        raise ToolError(f"{len(exact)} elements are named {target!r}: give `role`, or ui_act with an `index`:\n{listing}")
    path, role_, name = exact[0][0], exact[0][1], exact[0][2]
    return ui_resolve(Atspi, path), path, role_, name, "found"


@tool(
    "ui_act",
    "ui",
    "Act on an element through the app itself (no coordinates): `index` "
    "from the last ui_read, or `target`, an element's name (e.g. \"Send\", "
    "with `role` when names repeat) to act without reading first: controls "
    "you used before are reached directly, others are searched for. "
    "Actions: `click` (its press/toggle/activate action), `focus`, "
    "`set_text` (replaces a field's text with `value`, accents and all), or "
    "any action name the app lists for it. Returns the element after. "
    "Password fields are refused.",
    obj({
        "index": {"type": "integer"},
        "target": {"type": "string", "description": "An element's name, instead of index"},
        "role": {"type": "string", "description": "With target: its role (push button, page tab…)"},
        "window_id": {"type": "integer", "description": "With target: from list_windows; default: the focused window"},
        "action": {"type": "string", "description": "click, focus, set_text, or an action name"},
        "value": {"type": "string", "description": "The text, for set_text"},
    }, ["action"]),
    destructive=True,
)
def t_ui_act(ctx, args):
    action = as_str(args, "action", max_len=40).lower()
    target = as_str(args, "target", max_len=UI_TARGET_NAME_MAX * 2, required=False)
    if target:
        w = ui_window(ctx, args)
        Atspi = atspi()
        frame_path, frame = ui_frame(Atspi, w)
        role_want = as_str(args, "role", max_len=40, required=False) or None
        node, path, role, name, how = ui_find_target(Atspi, w, frame_path, frame, target, role_want)
    else:
        index = args.get("index")
        try:
            with open(ui_refs_path(), encoding="utf-8") as f:
                refs = json.load(f)
            item = refs["items"][index - 1] if isinstance(index, int) and index >= 1 else None
        except (OSError, ValueError, KeyError, IndexError):
            item = None
        if not item:
            raise ToolError(f"no element [{index}]: ui_read first (or give a `target` name)")
        w = window_by_id(refs["window"])
        if not w or w.get("pid") != refs["pid"]:
            raise ToolError("that window is gone: ui_read again")
        ui_window(ctx, {"window_id": refs["window"]})
        Atspi = atspi()
        frame_path, path, how = refs.get("frame"), item["path"], ""
        node = ui_resolve(Atspi, path)
        try:
            role, name = node.get_role_name(), (node.get_name() or "").strip()
        except Exception:
            node, role, name = None, None, None
        if node is None or role != item["role"] or name != item["name"]:
            raise ToolError("the window changed since ui_read: read it again")
    if role == "password text":
        raise ToolError("refused: password fields are off limits; ask the user to do this step")
    if role == "terminal":
        raise ToolError("refused: terminals are off limits; ask the user to do this step")
    ctx.guard.check_rate()
    if action == "focus":
        if node.get_component_iface() is None or not Atspi.Component.grab_focus(node):
            raise ToolError("that element can't take the focus")
    elif action == "set_text":
        value = args.get("value")
        if not isinstance(value, str):
            raise ToolError("`set_text` needs a `value`")
        ctx.guard.check_text(value)
        if node.get_editable_text_iface() is None or not Atspi.EditableText.set_text_contents(node, value):
            raise ToolError("that element's text can't be set: focus it and use type_text")
    else:
        has_actions = node.get_action_iface() is not None
        with warnings.catch_warnings():  # get_action_name: deprecated, but the only one in at-spi 2.60
            warnings.simplefilter("ignore", DeprecationWarning)
            names = [(Atspi.Action.get_action_name(node, i) or "").lower()
                     for i in range(Atspi.Action.get_n_actions(node))] if has_actions else []
        wanted = [action] if action != "click" else list(UI_CLICK_ACTIONS)
        pick = next((names.index(a) for a in wanted if a in names), None)
        if pick is None:
            raise ToolError(f"{role} {name!r} has no {action!r} action (it has: {', '.join(names) or 'none'}); "
                            "click it at its position from a screenshot instead")
        Atspi.Action.do_action(node, pick)
    ui_learn(w, frame_path, path, role, name)
    time.sleep(0.3)
    try:
        after = f"{node.get_role_name()} {(node.get_name() or '').strip()!r}"
        t = ui_text(Atspi, node, role)
        states = ui_states(Atspi, node)
        after += (f" = {t[:80]!r}" if t else "") + (f" ({', '.join(states)})" if states else "")
    except Exception:
        after = "(the element is gone: the window changed)"
    return [text(f"done{f' ({how})' if how else ''}: {after}")]


def ui_focus_summary(cfg):
    """The focused element of the focused window, in a few words (after
    typing: where the keys went), or None when it can't be told cheaply."""
    if "ui" not in cfg.get("tools", []):
        return None
    try:
        Atspi = atspi()
        w = focused_window()
        if not w:
            return None
        _, frame = ui_frame(Atspi, w)
        stack, visits = [(frame, 0)], 0
        while stack and visits < 600:
            node, depth = stack.pop()
            visits += 1
            s = node.get_state_set()
            if s.contains(Atspi.StateType.FOCUSED) and depth:
                role = node.get_role_name()
                editable = s.contains(Atspi.StateType.EDITABLE)
                return f"keyboard focus: {role} {(node.get_name() or '').strip()!r}" + (
                    "" if editable else " (not editable: the text may not have gone into a field)")
            if depth < 40 and s.contains(Atspi.StateType.SHOWING) or not depth:
                for i in range(min(node.get_child_count(), 300)):
                    c = node.get_child_at_index(i)
                    if c is not None:
                        stack.append((c, depth + 1))
    except Exception:
        return None
    return None


# --------------------------------------------------------------------------
