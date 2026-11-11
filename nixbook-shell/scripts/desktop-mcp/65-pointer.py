# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The pointer, through the compositor's virtual pointer.

# The pointer goes through the compositor's virtual pointer
# (wlr-virtual-pointer-unstable-v1, niri has it): absolute positions in
# desktop coordinates, no pointer acceleration, so clicks land exactly. A tiny
# Wayland client below speaks it; ydotool (a uinput mouse: relative moves,
# accelerated, approximate) is the fallback where the protocol is missing.

BTN_CODES = {"left": 0x110, "right": 0x111, "middle": 0x112}  # linux/input-event-codes.h
YDOTOOL_BUTTONS = {"left": "0xC0", "right": "0xC1", "middle": "0xC2"}
# motion_absolute takes integers over an extent: 8 steps per logical pixel.
SUBPIXEL = 8


class WaylandError(ToolError):
    """The compositor can't be reached or refused a request: reported to the
    agent like any other tool error."""


class VirtualPointer:
    """A minimal Wayland client for zwlr_virtual_pointer_v1: binds wl_seat and
    the manager from the registry, creates a pointer, sends requests, and
    waits for the compositor to have handled them (wl_display.sync)."""

    DISPLAY = 1
    MANAGER_IFACE = "zwlr_virtual_pointer_manager_v1"

    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
        path = name if name.startswith("/") else os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "", name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(3)
        try:
            self.sock.connect(path)
        except OSError as e:
            self.sock.close()
            raise WaylandError(f"can't reach the Wayland compositor at {path}: {e}")
        self.buf = b""
        self.next_id = 2
        self.globals = {}  # interface -> (name, version)
        registry = self.new_id()
        self.send(self.DISPLAY, 1, self.u32(registry))  # wl_display.get_registry
        self.registry = registry
        self.roundtrip()
        if self.MANAGER_IFACE not in self.globals:
            self.close()
            raise WaylandError("the compositor has no virtual pointer (wlr-virtual-pointer)")
        seat = self.bind("wl_seat", 1) if "wl_seat" in self.globals else 0
        manager = self.bind(self.MANAGER_IFACE, 1)
        self.pointer = self.new_id()
        # create_virtual_pointer(seat, id): no output, so absolute positions
        # span the bounding box of every output (niri: global_bounding_rectangle).
        self.send(manager, 0, self.u32(seat) + self.u32(self.pointer))
        self.manager = manager

    # -- wire format: little-endian 32-bit words, strings NUL-terminated and padded
    @staticmethod
    def u32(v):
        return struct.pack("<I", v & 0xFFFFFFFF)

    @staticmethod
    def i32(v):
        return struct.pack("<i", v)

    @staticmethod
    def fixed(v):
        return struct.pack("<i", int(round(v * 256)))

    @staticmethod
    def string(v):
        data = v.encode() + b"\0"
        return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj_id, opcode, payload=b""):
        size = 8 + len(payload)
        self.sock.sendall(struct.pack("<II", obj_id, (size << 16) | opcode) + payload)

    def bind(self, iface, version):
        name, advertised = self.globals[iface]
        new = self.new_id()
        # wl_registry.bind(name, new_id of an interface given as (string, version))
        self.send(self.registry, 0, self.u32(name) + self.string(iface) + self.u32(min(version, advertised)) + self.u32(new))
        return new

    def read_event(self):
        while len(self.buf) < 8 or len(self.buf) < (struct.unpack_from("<I", self.buf, 4)[0] >> 16):
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                raise WaylandError("the compositor didn't answer")
            if not chunk:
                raise WaylandError("the compositor closed the connection")
            self.buf += chunk
        obj, word = struct.unpack_from("<II", self.buf)
        size, opcode = word >> 16, word & 0xFFFF
        body, self.buf = self.buf[8:size], self.buf[size:]
        return obj, opcode, body

    @staticmethod
    def read_string(body, off):
        n = struct.unpack_from("<I", body, off)[0]
        value = body[off + 4 : off + 4 + n - 1].decode(errors="replace")
        return value, off + 4 + n + (-n % 4)

    def roundtrip(self):
        """wl_display.sync, then handle events until its callback is done."""
        cb = self.new_id()
        self.send(self.DISPLAY, 0, self.u32(cb))
        while True:
            obj, opcode, body = self.read_event()
            if obj == cb and opcode == 0:  # wl_callback.done
                return
            if obj == self.DISPLAY and opcode == 0:  # wl_display.error
                _, code = struct.unpack_from("<II", body)
                msg, _ = self.read_string(body, 8)
                raise WaylandError(f"Wayland protocol error {code}: {msg}")
            if obj == self.registry and opcode == 0:  # wl_registry.global
                name = struct.unpack_from("<I", body)[0]
                iface, off = self.read_string(body, 4)
                version = struct.unpack_from("<I", body, off)[0]
                self.globals.setdefault(iface, (name, version))
            # Anything else (wl_seat capabilities, delete_id…) is irrelevant.

    @staticmethod
    def now():
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    def move(self, x, y, bbox):
        bx, by, bw, bh = bbox
        # zwlr_virtual_pointer_v1.motion_absolute(time, x, y, x_extent, y_extent) + frame
        px = min(max(round((x - bx) * SUBPIXEL), 0), bw * SUBPIXEL - 1)
        py = min(max(round((y - by) * SUBPIXEL), 0), bh * SUBPIXEL - 1)
        self.send(self.pointer, 1, self.u32(self.now()) + self.u32(px) + self.u32(py) + self.u32(bw * SUBPIXEL) + self.u32(bh * SUBPIXEL))
        self.send(self.pointer, 4)

    def button(self, code, pressed):
        self.send(self.pointer, 2, self.u32(self.now()) + self.u32(code) + self.u32(1 if pressed else 0))
        self.send(self.pointer, 4)

    def scroll(self, dx, dy):
        self.send(self.pointer, 5, self.u32(0))  # axis_source(wheel)
        for axis, notches in ((0, dy), (1, dx)):  # vertical, horizontal
            if notches:
                # axis_discrete(time, axis, value, discrete): 15 per notch, as libinput
                self.send(self.pointer, 7, self.u32(self.now()) + self.u32(axis) + self.fixed(15 * notches) + self.i32(notches))
        self.send(self.pointer, 4)

    def sync(self):
        self.roundtrip()

    def close(self):
        try:
            if getattr(self, "pointer", None):
                self.send(self.pointer, 8)  # destroy
                self.send(self.manager, 1)  # destroy
                self.roundtrip()
        except (OSError, WaylandError):
            pass
        finally:
            self.sock.close()


def desktop_bbox():
    """The bounding box of the enabled outputs, in logical pixels: what an
    output-less virtual pointer's absolute positions span."""
    boxes = []
    for o in (niri_json("outputs") or {}).values():
        lg = o.get("logical")
        if lg and lg.get("width") and lg.get("height"):
            boxes.append((lg["x"], lg["y"], lg["x"] + lg["width"], lg["y"] + lg["height"]))
    if not boxes:
        raise ToolError("no enabled monitor")
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    return x0, y0, max(b[2] for b in boxes) - x0, max(b[3] for b in boxes) - y0


class Pointer:
    """One pointer action: the virtual pointer when there is one, else ydotool."""

    def __enter__(self):
        self.vp = None
        try:
            self.vp = VirtualPointer()
            self.bbox = desktop_bbox()
        except WaylandError as e:
            if self.vp:
                self.vp.close()
                self.vp = None
            log(f"virtual pointer unavailable ({e}), falling back to ydotool")
        return self

    @property
    def precise(self):
        return self.vp is not None

    def move(self, x, y):
        if self.vp:
            bx, by, bw, bh = self.bbox
            if not (bx <= x < bx + bw and by <= y < by + bh):
                raise ToolError(f"({x},{y}) is outside the desktop ({bx},{by} {bw}x{bh})")
            self.vp.move(x, y, self.bbox)
            self.vp.sync()
        else:
            run(["ydotool", "mousemove", "--absolute", "-x", str(round(x)), "-y", str(round(y))])

    def click(self, button, count=1):
        for i in range(count):
            if i:
                time.sleep(0.08)
            if self.vp:
                self.vp.button(BTN_CODES[button], True)
                self.vp.sync()
                time.sleep(0.02)
                self.vp.button(BTN_CODES[button], False)
                self.vp.sync()
            else:
                run(["ydotool", "click", YDOTOOL_BUTTONS[button]])

    def press(self, button, pressed):
        if self.vp:
            self.vp.button(BTN_CODES[button], pressed)
            self.vp.sync()
        else:
            # ydotool click codes: the button in the low nibble, 0x40 down, 0x80 up.
            low = int(YDOTOOL_BUTTONS[button], 16) & 0x0F
            run(["ydotool", "click", hex(low | (0x40 if pressed else 0x80))])

    def scroll(self, dx, dy):
        if self.vp:
            self.vp.scroll(dx, dy)
            self.vp.sync()
        else:
            # ydotool: positive wheel y scrolls up.
            run(["ydotool", "mousemove", "--wheel", "-x", str(dx), "-y", str(-dy)])

    def __exit__(self, *exc):
        if self.vp:
            self.vp.close()


SCREENSHOT_MAPPING = {
    "type": "object",
    "description": "The `mapping` of the screenshot x and y were read from: then x and y "
    "are that image's pixels, converted here. Without it they are desktop coordinates.",
    "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "scale": {"type": "number"}},
    "required": ["x", "y", "scale"],
}


def point(args, kx="x", ky="y"):
    """Desktop coordinates (logical pixels, fractional allowed) from x/y,
    converted from screenshot pixels when a `screenshot` mapping is given."""
    x, y = args.get(kx), args.get(ky)
    for key, v in ((kx, x), (ky, y)):
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not (-100000 <= v <= 100000):
            raise ToolError(f"`{key}` must be a number")
    m = args.get("screenshot")
    if m is None:
        return float(x), float(y)
    if not isinstance(m, dict) or not all(
        isinstance(m.get(k), (int, float)) and not isinstance(m.get(k), bool) for k in ("x", "y", "scale")
    ) or not (0 < m["scale"] <= 16):
        raise ToolError("`screenshot` must be a screenshot's mapping: {x, y, scale}")
    return m["x"] + x / m["scale"], m["y"] + y / m["scale"]


def fmt(x, y):
    return f"({x:g},{y:g})"


def precision_note(p):
    return "" if p.precise else " (ydotool fallback: approximate, check with a screenshot)"



@tool(
    "move_pointer",
    "input",
    "Move the mouse pointer to a point: desktop coordinates (logical pixels), "
    "or a screenshot's pixels with its `mapping` as `screenshot`.",
    obj({"x": COORD, "y": COORD, "screenshot": SCREENSHOT_MAPPING}, ["x", "y"]),
)
def t_move_pointer(ctx, args):
    x, y = point(args)
    mark_agent_input()
    ctx.guard.check_rate()
    with Pointer() as p:
        p.move(x, y)
    return [text(f"pointer at {fmt(x, y)}" + precision_note(p))]


@tool(
    "click",
    "input",
    "Click a mouse button at a point (desktop coordinates, or a screenshot's "
    "pixels with its `mapping` as `screenshot`), or where the pointer is. "
    "After the keyboard: an app's shortcut or search box first." + INPUT_LAST,
    obj(
        {
            "x": COORD,
            "y": COORD,
            "screenshot": SCREENSHOT_MAPPING,
            "button": {"type": "string", "enum": list(BTN_CODES)},
            "double": {"type": "boolean"},
        }
    ),
)
def t_click(ctx, args):
    button = args.get("button") or "left"
    if button not in BTN_CODES:
        raise ToolError("`button` must be left, right or middle")
    has_xy = "x" in args or "y" in args
    if has_xy:
        x, y = point(args)
    ctx.guard.check_input_target()
    ctx.guard.check_rate()
    with Pointer() as p:
        if has_xy:
            p.move(x, y)
            time.sleep(0.03)  # let the app see the pointer enter first
        p.click(button, 2 if args.get("double") is True else 1)
    return [text(f"{button} click" + (f" at {fmt(x, y)}" if has_xy else "") + precision_note(p))]


@tool(
    "drag",
    "input",
    "Press a mouse button at one point, move to another, release: drag and "
    "drop, select text, move a slider. Points as for click." + INPUT_LAST,
    obj(
        {
            "x": COORD,
            "y": COORD,
            "to_x": COORD,
            "to_y": COORD,
            "screenshot": SCREENSHOT_MAPPING,
            "button": {"type": "string", "enum": list(BTN_CODES)},
        },
        ["x", "y", "to_x", "to_y"],
    ),
)
def t_drag(ctx, args):
    button = args.get("button") or "left"
    if button not in BTN_CODES:
        raise ToolError("`button` must be left, right or middle")
    x, y = point(args)
    tx, ty = point(args, "to_x", "to_y")
    ctx.guard.check_input_target()
    ctx.guard.check_rate()
    with Pointer() as p:
        p.move(x, y)
        time.sleep(0.03)
        p.press(button, True)
        try:
            # In steps, so apps see a drag and not a jump.
            steps = 12
            for i in range(1, steps + 1):
                p.move(x + (tx - x) * i / steps, y + (ty - y) * i / steps)
                time.sleep(0.015)
        finally:
            p.press(button, False)
    return [text(f"dragged {fmt(x, y)} → {fmt(tx, ty)}" + precision_note(p))]


@tool(
    "scroll",
    "input",
    "Scroll the window under the pointer (or at a point, as for click): "
    "positive dy scrolls down, dx right, in wheel notches." + INPUT_LAST,
    obj({"dy": {"type": "integer"}, "dx": {"type": "integer"}, "x": COORD, "y": COORD, "screenshot": SCREENSHOT_MAPPING}),
)
def t_scroll(ctx, args):
    dy = as_int(args, "dy", required=False) or 0
    dx = as_int(args, "dx", required=False) or 0
    if abs(dy) > 50 or abs(dx) > 50:
        raise ToolError("scroll at most 50 notches at a time")
    has_xy = "x" in args or "y" in args
    if has_xy:
        x, y = point(args)
    mark_agent_input()
    ctx.guard.check_rate()
    with Pointer() as p:
        if has_xy:
            p.move(x, y)
        p.scroll(dx, dy)
    return [text(f"scrolled dx={dx} dy={dy}" + (f" at {fmt(x, y)}" if has_xy else ""))]


@tool(
    "run_steps",
    "input",
    "Do several actions in one call, in order: each step is {tool, args} for "
    "a window or input tool (launch_app, focus_app, focus_window, press_keys, type_text, "
    "click, drag, scroll, clipboard_set…, and page_go to open a link in Zen), optionally with wait_ms to wait "
    "after it (default 200), or settle: true to wait until the screen stops "
    "changing (a page loading, a dialog opening). Stops at the first step that fails or is "
    "refused. E.g. open a chat and send a message: [{tool: press_keys, args: "
    "{keys: [ctrl+k]}}, {tool: type_text, args: {text: Alesio}, wait_ms: 600}, "
    "{tool: press_keys, args: {keys: [Return]}}, …]. Every step passes the "
    "same guardrails as when called alone; a pause stops the remaining steps.",
    obj(
        {
            "steps": {
                "type": "array",
                "minItems": 1,
                "maxItems": 20,
                "items": {
                    "type": "object",
                    "properties": {
                        "tool": {"type": "string"},
                        "args": {"type": "object"},
                        "wait_ms": {"type": "integer"},
                        "settle": {"type": "boolean"},
                    },
                    "required": ["tool"],
                },
            },
            "remember_as": {
                "type": "string",
                "description": "When the steps worked, save them as a recipe under this topic (e.g. \"discord: send a DM\"), run next time with run_recipe in one call; the same topic replaces it",
            },
            "vars": {
                "type": "object",
                "description": "Values for {name} placeholders in the steps' text (e.g. {\"name\": \"Lan\"}); a recipe saved with remember_as keeps the placeholders, to be run with other values",
            },
        },
        ["steps"],
    ),
)
def t_run_steps(ctx, args):
    steps = args.get("steps")
    if not isinstance(steps, list) or not 1 <= len(steps) <= 20:
        raise ToolError("`steps` must be a list of 1 to 20 steps")
    values = recipe_values(args.get("vars"))
    template = parametrize(substitute(steps, values), values) if values else steps
    steps = substitute(steps, values)
    enabled = enabled_tools(ctx.cfg)
    plan = []
    for i, step in enumerate(steps, 1):
        if not isinstance(step, dict):
            raise ToolError(f"step {i} must be an object {{tool, args, wait_ms}}")
        name = step.get("tool")
        t = enabled.get(name)
        if not t or (t["group"] not in ACTION_GROUPS and name not in RUN_STEPS_EXTRA) \
                or name in ("run_steps", "run_recipe"):
            raise ToolError(f"step {i}: {name!r} is not a window or input tool that is enabled")
        if name == "page_go" and (step.get("args") or {}).get("action") not in RUN_STEPS_PAGE_ACTIONS:
            raise ToolError(f"step {i}: page_go in steps only opens or moves a page "
                            f"({', '.join(RUN_STEPS_PAGE_ACTIONS)})")
        step_args = step.get("args") or {}
        if not isinstance(step_args, dict):
            raise ToolError(f"step {i}: `args` must be an object")
        # One screenshot at the end at most (run_steps' own screenshot_after).
        step_args = {k: v for k, v in step_args.items() if k not in AFTER_PROPS}
        wait = step.get("wait_ms", 200)
        if isinstance(wait, bool) or not isinstance(wait, int) or not 0 <= wait <= 5000:
            raise ToolError(f"step {i}: `wait_ms` must be 0 to 5000")
        plan.append((name, t, step_args, "settle" if step.get("settle") is True else wait))
    done = []
    for i, (name, t, step_args, wait) in enumerate(plan, 1):
        if is_paused():
            audit(ctx.client, name, step_args, "paused (run_steps)")
            raise ToolError("\n".join(done + [f"stopped before step {i}: desktop control was paused by the user"]))
        try:
            out = t["fn"](ctx, step_args)
        except ToolError as e:
            audit(ctx.client, name, step_args, f"error (run_steps): {e}")
            raise ToolError("\n".join(done + [f"{i}. {name} failed: {e}", f"steps {i + 1}-{len(plan)} not run"]))
        audit(ctx.client, name, step_args, "ok (run_steps)")
        summary = next((c["text"] for c in out if c.get("type") == "text"), "done")
        done.append(f"{i}. {name}: {summary.splitlines()[0] if summary else 'done'}")
        write_state(last={"time": int(time.time() * 1000), "client": ctx.client, "tool": name, "outcome": "ok"})
        if wait != "settle":
            time.sleep(wait / 1000)
        elif not wait_settled(ctx):
            done.append(f"(the screen was still changing after {SETTLE_MAX_MS / 1000:g} s)")
    if isinstance(args.get("remember_as"), str) and args["remember_as"].strip() and "memory" in ctx.cfg["tools"]:
        topic = clean_text(args["remember_as"], NOTE_TOPIC_MAX)
        if len(json.dumps(template, ensure_ascii=False)) > RECIPE_TEXT_MAX:
            done.append(f"not saved: a recipe holds at most {RECIPE_TEXT_MAX} characters of steps")
        else:
            reply = add_note(ctx, topic, recipe_gist(template), kind="recipe", steps=template)
            record_recipe(ctx.last_note, True)
            done.append(reply + " (run it with run_recipe)")
    return [text("\n".join(done))]
