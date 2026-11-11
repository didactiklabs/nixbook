# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Screenshots, the clipboard and typing.

# Monitor screenshots send what changed since the session's last one: an
# image costs the model about width x height / 750 tokens, every time it is
# read again, and most screenshots after an action change a small part.
FRAME_GAP = 24  # image pixels: changes closer than this make one crop
FRAME_PAD = 16  # image pixels around each changed area
FRAME_MAX_CROPS = 3
FRAME_MAX_SHARE = 0.5  # crops covering more than this: the whole image


def read_ppm(data):
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
    if not m or len(data) - m.end() != int(m[1]) * int(m[2]) * 3:
        raise ToolError("grim returned an unexpected capture")
    return int(m[1]), int(m[2]), data[m.end():]


# Waiting for the screen to settle: tiny captures of the focused monitor
# until one changes no more than a few rows (a caret, a clock, a spinner)
# from the one before for SETTLE_QUIET_MS; at most SETTLE_MAX_MS.
SETTLE_SCALE = 0.125
SETTLE_MIN_MS = 50
SETTLE_QUIET_MS = 250
SETTLE_MAX_MS = 2500


def nearly_same(a, b, w, h):
    """At most 2% of the rows differ."""
    stride = w * 3
    budget = max(1, h // 50)
    for y in range(h):
        if a[y * stride:(y + 1) * stride] != b[y * stride:(y + 1) * stride]:
            budget -= 1
            if budget < 0:
                return False
    return True


def wait_settled(ctx):
    """Waits until the focused monitor stops changing. Returns whether it
    did within SETTLE_MAX_MS (no screen tools: SETTLE_QUIET_MS, then True).
    The shell's overlays hidden meanwhile: a chat streaming in the side
    panel would never let it settle."""
    with overlays_hidden(ctx):
        return settled_now(ctx)


def settled_now(ctx):
    start = time.monotonic()
    name = None
    if "screen" in ctx.cfg["tools"]:
        try:
            name = (niri_json("focused-output") or {}).get("name")
        except ToolError:
            pass
    if not name or not shutil.which("grim"):
        time.sleep(SETTLE_QUIET_MS / 1000)
        return True
    time.sleep(SETTLE_MIN_MS / 1000)
    prev = stable_since = None
    while True:
        try:
            frame = read_ppm(run(["grim", "-o", name, "-s", str(SETTLE_SCALE), "-t", "ppm", "-"], timeout=5, binary=True).stdout)
        except ToolError:
            return True
        now = time.monotonic()
        if prev and prev[:2] == frame[:2] and nearly_same(prev[2], frame[2], *frame[:2]):
            stable_since = stable_since or prev_time
            if now - stable_since >= SETTLE_QUIET_MS / 1000:
                return True
        else:
            stable_since = None
        if now - start >= SETTLE_MAX_MS / 1000:
            return False
        prev, prev_time = frame, now
        time.sleep(0.05)


def first_diff(a, b):
    """Index of the first differing byte of a and b (they differ)."""
    lo, hi = 0, len(a)  # a[:lo] == b[:lo], a[:hi] != b[:hi]
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if a[:mid] == b[:mid]:
            lo = mid
        else:
            hi = mid
    return lo


def changed_boxes(old, new, w, h):
    """[x0, y0, x1, y1) image rectangles around the pixels that differ."""
    stride = w * 3
    boxes = []
    for y in range(h):
        a, b = old[y * stride:(y + 1) * stride], new[y * stride:(y + 1) * stride]
        if a == b:
            continue
        x0 = first_diff(a, b) // 3
        x1 = w - first_diff(a[::-1], b[::-1]) // 3
        last = boxes[-1] if boxes else None
        if last and y - last[3] < FRAME_GAP:
            last[0], last[2], last[3] = min(last[0], x0), max(last[2], x1), y + 1
        else:
            boxes.append([x0, y, x1, y + 1])
    boxes = [[max(0, b[0] - FRAME_PAD), max(0, b[1] - FRAME_PAD), min(w, b[2] + FRAME_PAD), min(h, b[3] + FRAME_PAD)] for b in boxes]
    merged = True
    while merged:  # padded boxes that overlap: one
        merged = False
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                if a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]:
                    a[:] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                    boxes.remove(b)
                    merged = True
                    break
            if merged:
                break
    if len(boxes) > FRAME_MAX_CROPS:
        boxes = [[min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)]]
    return boxes


def monitor_screenshot(ctx, name, grim, scale, x, y, what, full):
    path = os.path.join(runtime_dir(), f"screenshot-{secrets.token_hex(4)}.ppm")
    try:
        run(["grim", *grim, "-s", f"{scale:.4f}", "-t", "ppm", path], timeout=15)
        os.chmod(path, 0o600)
        hidden = privacy_note(mask_image(path, ctx.cfg)) if privacy_screenshots() else []
        with open(path, "rb") as f:
            iw, ih, pixels = read_ppm(f.read())
        # What this session was sent last of this monitor.
        key = (ctx.session, name, x, y, scale)
        old = ctx.frames.pop(key, None)
        ctx.frames[key] = pixels
        while len(ctx.frames) > 4:  # a few MB each
            ctx.frames.pop(next(iter(ctx.frames)))
        boxes = None if full or old is None or len(old) != len(pixels) else changed_boxes(old, pixels, iw, ih)
        head = f"{what}, image scale {scale:g}."
        if boxes == []:
            return [text(f"{head} Nothing changed since your last screenshot of it (`full: true` sends it again).")]
        if boxes and sum((b[2] - b[0]) * (b[3] - b[1]) for b in boxes) <= FRAME_MAX_SHARE * iw * ih:
            out = [text(
                f"{head} Only {'this part' if len(boxes) == 1 else f'these {len(boxes)} parts'} changed since "
                "your last screenshot of it (the rest is as you saw it; `full: true` sends it all). "
                "To click in a part, pass its pixel coordinates as x, y with its mapping as `screenshot`."
            )]
            for b in boxes:
                mapping = {"x": round(x + b[0] / scale, 2), "y": round(y + b[1] / scale, 2), "scale": scale}
                out.append(text(f"Part {b[2] - b[0]}x{b[3] - b[1]} at image ({b[0]},{b[1]}), mapping: {json.dumps(mapping)}"))
                out.append(encode_frame(ctx, path, f"{b[2] - b[0]}x{b[3] - b[1]}+{b[0]}+{b[1]}"))
            return out + hidden
        mapping = {"x": x, "y": y, "scale": scale}
        info = (
            f"{head}\nmapping: {json.dumps(mapping)}\n"
            "To click something in this image, pass its pixel coordinates as x, y "
            "with this mapping as `screenshot` (desktop x = mapping.x + image_x / scale). "
            "To see small things better, take a `region` screenshot around them."
        )
        return [text(info), encode_frame(ctx, path), *hidden]
    finally:
        if os.path.exists(path):
            os.unlink(path)


def encode_frame(ctx, path, crop=None):
    png = ctx.cfg.get("screenshotFormat") == "png"
    quality = min(max(int(ctx.cfg.get("screenshotQuality", 80)), 10), 100)
    argv = ["magick", path, *(["-crop", crop, "+repage"] if crop else [])]
    argv += ["png:-"] if png else ["-quality", str(quality), "jpeg:-"]
    data = run(argv, timeout=15, binary=True).stdout
    return {"type": "image", "data": base64.b64encode(data).decode(), "mimeType": "image/png" if png else "image/jpeg"}


def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        return None
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


# What the clipboard held, to put back after a window capture (niri hands
# those to the clipboard only). The first type in this order that it offers.
CLIPBOARD_TYPES = ["image/png", "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "text/uri-list"]


def clipboard_types():
    proc = run(["wl-paste", "--list-types"], timeout=3, check=False)
    return proc.stdout.split() if proc.returncode == 0 else []


def wl_copy(data, mime=None):
    exe = shutil.which("wl-copy")
    if not exe:
        raise ToolError("`wl-copy` is not installed or not on PATH")
    argv = [exe] + (["--type", mime] if mime else [])
    # wl-copy forks to serve the selection; don't wait for it.
    p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        p.communicate(data, timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        raise ToolError("`wl-copy` timed out")


def screenshot_window(ctx, wid):
    w = window_by_id(wid)
    # niri writes the capture where asked (--path), but also puts it in the
    # clipboard (no way around that): keep what was there to put it back.
    saved = saved_clipboard()
    path = os.path.join(runtime_dir(), f"screenshot-{secrets.token_hex(4)}.png")
    try:
        niri_action("screenshot-window", "--id", str(wid), "--path", path)
        # niri encodes and writes it from a thread: wait for a stable, non-empty file.
        prev = -1
        for _ in range(80):
            size = os.path.getsize(path) if os.path.exists(path) else 0
            if size > 0 and size == prev:
                break
            prev = size
            time.sleep(0.05)
        else:
            raise ToolError("niri didn't write the window capture")
        os.chmod(path, 0o600)
        with open(path, "rb") as f:
            data = f.read()
    except BaseException:
        if os.path.exists(path):
            os.unlink(path)
        raise
    finally:
        if saved:
            wl_copy(saved[1], saved[0])
    size = png_size(data)
    max_edge = int(ctx.cfg.get("screenshotMaxEdge", 1280))
    if shutil.which("magick"):
        # Scaled down to the size limit, and to JPEG unless PNG is asked for.
        out = path
        if ctx.cfg.get("screenshotFormat") != "png":
            out = path[: -len(".png")] + ".jpg"
        quality = min(max(int(ctx.cfg.get("screenshotQuality", 80)), 10), 100)
        try:
            run(["magick", path, "-resize", f"{max_edge}x{max_edge}>", "-quality", str(quality), out], timeout=15)
        except BaseException:
            for p in {path, out}:
                if os.path.exists(p):
                    os.unlink(p)
            raise
        if out != path:
            os.unlink(path)
            os.chmod(out, 0o600)
            path = out
    info = (
        f"Window {wid} ({w.get('app_id')}: {w.get('title')!r}), captured whole"
        + (f", {size[0]}x{size[1]} pixels" if size else "")
        + ". For pointer coordinates, take a monitor screenshot."
    )
    return screenshot_reply(ctx, path, info)


def screenshot_reply(ctx, path, info):
    if privacy_screenshots():
        boxes = mask_image(path, ctx.cfg)
        if boxes:
            info += "\n" + privacy_note(boxes)[0]["text"]
    if ctx.transport == "cli":
        # The caller reads the file later; drop the ones left from before.
        for old in os.listdir(runtime_dir()):
            p = os.path.join(runtime_dir(), old)
            try:
                if old.startswith("screenshot-") and time.time() - os.path.getmtime(p) > 600:
                    os.unlink(p)
            except FileNotFoundError:  # another server's cleanup
                pass
        os.chmod(path, 0o600)
        return [text(f"{info}\nSaved to {path}")]
    try:
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
    finally:
        os.unlink(path)
    mime = "image/png" if path.endswith(".png") else "image/jpeg"
    return [text(info), {"type": "image", "data": data, "mimeType": mime}]


# read_screen: captured at twice its logical size, in grey, at most this
# many pixels a side (OCR reads small UI text better upscaled).
OCR_SCALE = 2.0
OCR_MAX_EDGE = 4096
OCR_MIN_CONF = 50
OCR_MAX_CHARS = 6000


@tool(
    "read_screen",
    "screen",
    "Read the text on a monitor (default: the focused one) or a `region`, "
    "with where each line is: a few hundred tokens of text instead of a "
    "screenshot's ~1,250, and the positions are desktop pixels, ready for "
    "click/move_pointer as x, y (no mapping). OCR: icons and images aren't "
    "read, and some text may be missed; take a screenshot when the text isn't "
    "enough. `find`: only the lines that contain this text, e.g. to locate "
    "a button before clicking it.",
    obj(
        {
            "monitor": {"type": "string", "description": "Monitor name (see list_workspaces)"},
            "region": {
                "type": "object",
                "description": "A desktop rectangle in logical pixels",
                "properties": {"x": COORD, "y": COORD, "width": COORD, "height": COORD},
                "required": ["x", "y", "width", "height"],
            },
            "find": {"type": "string", "description": "Only the lines containing this text (any case)"},
        }
    ),
    read_only=True,
)
def t_read_screen(ctx, args):
    with overlays_hidden(ctx):
        return read_screen_now(ctx, args)


def read_screen_now(ctx, args):
    find = as_str(args, "find", required=False, max_len=200)
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
            raise ToolError(f"`region` is outside the desktop ({bx},{by} {bw}x{bh}) or smaller than 4x4")
        grim = ["-g", f"{x},{y} {w}x{h}"]
        what = f"region {w}x{h} at ({x},{y})"
    else:
        outputs = {n: o for n, o in (niri_json("outputs") or {}).items() if o.get("logical")}
        name = as_str(args, "monitor", required=False, max_len=64, pattern=r"[\w.\-]+")
        if not name:
            name = (niri_json("focused-output") or {}).get("name")
        if name not in outputs:
            raise ToolError(f"no monitor {name!r}; monitors: {', '.join(outputs)}")
        lg = outputs[name]["logical"]
        x, y, w, h = lg.get("x", 0), lg.get("y", 0), lg.get("width") or 1, lg.get("height") or 1
        grim = ["-o", name]
        what = f"monitor {name}"
    scale = round(min(OCR_SCALE, OCR_MAX_EDGE / max(w, h)), 4)
    capture = run(["grim", *grim, "-s", f"{scale:.4f}", "-t", "ppm", "-"], timeout=15, binary=True).stdout
    gray = run(["magick", "ppm:-", "-colorspace", "gray", "pgm:-"], input=capture, timeout=15, binary=True).stdout
    lang = str(ctx.cfg.get("ocrLanguages") or "eng")
    if not re.fullmatch(r"[A-Za-z_]+(\+[A-Za-z_]+)*", lang):
        raise ToolError("`ocrLanguages` must be like eng or eng+fra")
    tsv = run(["tesseract", "stdin", "stdout", "--psm", "11", "-l", lang, "tsv"], input=gray, timeout=30, binary=True)
    lines = ocr_lines(tsv.stdout.decode(errors="replace"), x, y, scale)
    if find:
        want = fold(find)
        found = [ln for ln in lines if want in fold(ln[2])]
        if not found:
            return [text(f"No line on {what} contains {find!r} ({len(lines)} lines read). "
                         "It may be an icon, or missed by OCR: take a screenshot.")]
        lines = found
    head = (f"Text on {what} (OCR), a line each: x,y (its middle, desktop pixels: click there) "
            "width x height, then the text.")
    out, size = [head], len(head)
    for i, (cx, cy, line, lw, lh) in enumerate(lines):
        entry = f"{cx},{cy} {lw}x{lh} {line}"
        if size + len(entry) > OCR_MAX_CHARS:
            out.append(f"… {len(lines) - i} more lines: read a `region`")
            break
        out.append(entry)
        size += len(entry) + 1
    if len(out) == 1:
        out.append("(no text found)")
    return [text("\n".join(out))]


def ocr_lines(tsv, x, y, scale):
    """tesseract's TSV words, confident enough, joined into lines: [(middle
    x, middle y, text, width, height)] in desktop pixels, top to bottom."""
    groups = {}
    for row in tsv.splitlines()[1:]:
        cols = row.split("\t")
        if len(cols) < 12 or not cols[11].strip():
            continue
        try:
            conf = float(cols[10])
            left, top, width, height = (int(c) for c in cols[6:10])
        except ValueError:
            continue
        if conf < OCR_MIN_CONF:
            continue
        groups.setdefault(tuple(cols[1:5]), []).append((left, top, width, height, cols[11].strip()))
    lines = []
    for words_ in groups.values():
        # An icon read as a letter or two of noise: not a line.
        if sum(c.isalnum() for wd in words_ for c in wd[4]) < 2:
            continue
        words_.sort()
        l0 = min(wd[0] for wd in words_)
        t0 = min(wd[1] for wd in words_)
        r0 = max(wd[0] + wd[2] for wd in words_)
        b0 = max(wd[1] + wd[3] for wd in words_)
        lines.append((
            round(x + (l0 + r0) / 2 / scale), round(y + (t0 + b0) / 2 / scale),
            " ".join(wd[4] for wd in words_),
            round((r0 - l0) / scale), round((b0 - t0) / scale),
        ))
    lines.sort(key=lambda ln: (ln[1] - ln[4] / 2, ln[0]))
    return lines


# Password managers mark what they copy (KeePassXC, KDE's apps, Bitwarden…):
# never read by an agent, never copied back after a paste.
CLIPBOARD_SECRET_TYPES = {"x-kde-passwordManagerHint", "x-kde-passwordmanagerhint"}


def clipboard_secret():
    try:
        return bool(CLIPBOARD_SECRET_TYPES & set(clipboard_types()))
    except ToolError:
        return False


@tool(
    "clipboard_get",
    "screen",
    "Read the clipboard's text.",
    read_only=True,
)
def t_clipboard_get(ctx, args):
    if clipboard_secret():
        raise ToolError("refused: the clipboard holds a secret a password manager copied")
    proc = run(["wl-paste", "--no-newline", "--type", "text"], timeout=3, check=False)
    if proc.returncode != 0:
        return [text("(the clipboard holds no text)")]
    return [text(proc.stdout[:20000])]


def notification_history_path():
    # The shell's history (Directories.notificationHistoryPath), oldest first.
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "quickshell", "user", "notification-history.json")


# Unicode bidi isolates Vesktop wraps names in: noise for the model.
BIDI_MARKS = dict.fromkeys(map(ord, "⁦⁧⁨⁩‎‏"))


@tool(
    "notifications",
    "screen",
    "The desktop's recent notifications, oldest first, as text: new chat "
    "messages (Vesktop: \"sender (#channel, server): message\", or just the "
    "sender for a DM), mail, reminders… Cheaper than a screenshot to see "
    "whether someone answered. Filter by `app` (e.g. vesktop), `contains` "
    "(in the title or text) and `since_minutes`.",
    obj(
        {
            "app": {"type": "string", "description": "App name, case-insensitive substring (e.g. vesktop)"},
            "contains": {"type": "string", "description": "Only those whose title or text contains this"},
            "since_minutes": {"type": "integer", "description": "Only those from the last N minutes"},
            "count": {"type": "integer", "description": "At most this many, the newest (default 10, at most 100)"},
        }
    ),
    read_only=True,
)
def t_notifications(ctx, args):
    app = (as_str(args, "app", max_len=128, required=False) or "").lower()
    contains = (as_str(args, "contains", max_len=256, required=False) or "").lower()
    since = args.get("since_minutes")
    count = args.get("count", 10)
    if not isinstance(count, int) or isinstance(count, bool) or count < 1:
        raise ToolError("`count` must be a positive integer")
    if since is not None and (not isinstance(since, int) or isinstance(since, bool) or since < 1):
        raise ToolError("`since_minutes` must be a positive integer")
    try:
        with open(notification_history_path(), encoding="utf-8") as f:
            history = json.load(f)
    except FileNotFoundError:
        return [text("no notifications yet")]
    except (OSError, ValueError) as e:
        raise ToolError(f"can't read the notification history: {e}")
    cutoff = (time.time() - since * 60) * 1000 if since else 0
    lines = []
    for n in history if isinstance(history, list) else []:
        if not isinstance(n, dict):
            continue
        name = str(n.get("appName") or "")
        summary = str(n.get("summary") or "").translate(BIDI_MARKS)
        body = str(n.get("body") or "").translate(BIDI_MARKS)
        when = n.get("time") if isinstance(n.get("time"), (int, float)) else 0
        if app and app not in name.lower():
            continue
        if contains and contains not in summary.lower() and contains not in body.lower():
            continue
        if when < cutoff:
            continue
        stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(when / 1000))
        lines.append(f"{stamp} [{name}] {summary}: {body}"[:2000])
    if not lines:
        return [text("no notifications match")]
    return [text("\n".join(lines[-min(count, 100):]))]


@tool(
    "clipboard_set",
    "input",
    "Put text on the clipboard (then paste it with press_keys ctrl+v).",
    obj({"text": {"type": "string"}}, ["text"]),
)
def t_clipboard_set(ctx, args):
    value = args.get("text")
    if not isinstance(value, str):
        raise ToolError("`text` must be a string")
    ctx.guard.check_text(value)
    ctx.guard.check_rate()
    wl_copy(value.encode())
    return [text(f"copied {len(value)} characters")]


# -- keyboard and pointer ----------------------------------------------------

# Typed by wtype as is. Anything else is pasted: wtype sends each character
# not on the keymap by swapping in a new keymap, and Chromium/Electron apps
# (Vesktop, Zen) drop or mangle the keys around those swaps ("c'est" came out
# "est"), and a "\n" would press Return (sending a chat message half-written).
PLAIN_TEXT = re.compile(r"[A-Za-z0-9 ]+")


def focus_note(ctx):
    """Where the keys went (the accessibility tree's focused element), so an
    agent needn't screenshot to check; empty when it can't be told."""
    note = ui_focus_summary(ctx.cfg)
    return f"; {note}" if note else ""


def saved_clipboard():
    offered = clipboard_types()
    if CLIPBOARD_SECRET_TYPES & set(offered):
        return None  # a password: not copied back (it would lose its mark, and be kept)
    for mime in CLIPBOARD_TYPES:
        if mime in offered:
            proc = run(["wl-paste", "--no-newline", "--type", mime], timeout=3, check=False, binary=True)
            return (mime, proc.stdout) if proc.returncode == 0 else None
    return None


def paste_text(value):
    """Paste through the clipboard, then put back what it held."""
    saved = saved_clipboard()
    wl_copy(value.encode())
    try:
        # wl-copy serves the selection from its fork: give it a moment.
        time.sleep(0.1)
        run(["wtype", "-M", "ctrl", "-k", "v", "-m", "ctrl"])
        # The app reads the selection after the key: wait before replacing it.
        time.sleep(0.4)
    finally:
        if saved:
            wl_copy(saved[1], saved[0])
        else:
            run(["wl-copy", "--clear"], check=False)

MODIFIERS = {"ctrl": "ctrl", "control": "ctrl", "shift": "shift", "alt": "alt", "altgr": "altgr",
             "super": "logo", "logo": "logo", "meta": "logo", "win": "logo"}
KEY_NAME = r"[A-Za-z0-9_]{1,32}"


def parse_combo(combo, allow_super):
    parts = [p for p in combo.split("+")] if combo != "+" else ["+"]
    if "" in parts[:-1]:
        raise ToolError(f"invalid key combination {combo!r}")
    *mods, key = parts
    mods = [m.lower() for m in mods]
    for m in mods:
        if m not in MODIFIERS:
            raise ToolError(f"unknown modifier {m!r} in {combo!r} (ctrl, shift, alt, altgr, super)")
    mods = [MODIFIERS[m] for m in mods]
    if not re.fullmatch(KEY_NAME, key):
        raise ToolError(f"invalid key {key!r}: use an xkb key name (Return, Tab, Escape, a, F5, slash, comma, …)")
    if "logo" in mods and not allow_super:
        raise ToolError(
            "refused: Super combinations are compositor shortcuts; use the window "
            "and workspace tools instead"
        )
    if "ctrl" in mods and "alt" in mods and re.fullmatch(r"(?i)delete|backspace|f\d{1,2}", key):
        raise ToolError("refused: Ctrl+Alt+Delete/Backspace/F-keys (session and VT switching)")
    return mods, key


# Said by every tool that drives the mouse or keyboard: the headless ways
# first (INSTRUCTIONS gives the order).
INPUT_LAST = (" Input is the last resort: use it only when no tool does it without "
              "(an app's own MCP tools, page_*, ui_act, the window and shell tools).")


@tool(
    "type_text",
    "input",
    "Type text into the focused window, as the keyboard would. Text with "
    "accents, punctuation or line breaks is pasted instead (the clipboard is "
    "put back after), so type it as is: accents, apostrophes and commas come "
    "out right, and a line break doesn't press Return. Refused in terminals, "
    "password managers and password prompts." + INPUT_LAST,
    obj({"text": {"type": "string"}}, ["text"]),
)
def t_type_text(ctx, args):
    value = args.get("text")
    if not isinstance(value, str) or not value:
        raise ToolError("`text` must be a non-empty string")
    ctx.guard.check_text(value)
    ctx.guard.check_input_target()
    ctx.guard.check_rate()
    if shutil.which("wtype") and PLAIN_TEXT.fullmatch(value) is None and shutil.which("wl-copy"):
        paste_text(value)
        return [text(f"pasted {len(value)} characters" + focus_note(ctx))]
    if shutil.which("wtype"):
        run(["wtype", "-"], input=value, timeout=60)
    else:
        run(["ydotool", "type", "--file", "-"], input=value, timeout=60)
    return [text(f"typed {len(value)} characters" + focus_note(ctx))]


@tool(
    "press_keys",
    "input",
    "Press key combinations in the focused window, in order, e.g. "
    "[\"ctrl+l\", \"Return\"]. xkb key names: Return, Tab, Escape, BackSpace, "
    "Up, Page_Down, F5, a, … Super combos are refused (use the window tools)." + INPUT_LAST,
    obj(
        {
            "keys": {"type": "array", "items": {"type": "string"}, "minItems": 1, "maxItems": 20},
        },
        ["keys"],
    ),
)
def t_press_keys(ctx, args):
    keys = args.get("keys")
    if isinstance(keys, str):
        keys = [keys]
    if not isinstance(keys, list) or not keys or len(keys) > 20 or not all(isinstance(k, str) for k in keys):
        raise ToolError("`keys` must be a list of 1 to 20 key combinations")
    allow_super = bool(ctx.cfg.get("allowSuperKey"))
    combos = [parse_combo(k, allow_super) for k in keys]
    ctx.guard.check_input_target(combos)
    ctx.guard.check_rate()
    argv = ["wtype"]
    for mods, key in combos:
        for m in mods:
            argv += ["-M", m]
        argv += ["-k", key]
        for m in reversed(mods):
            argv += ["-m", m]
    run(argv)
    return [text(f"pressed {', '.join(keys)}" + focus_note(ctx))]
