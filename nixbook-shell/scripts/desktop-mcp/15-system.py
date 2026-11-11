# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# System information, machine help and the apps (.desktop entries).

def os_info():
    rel = {}
    for line in (read_sys("/etc/os-release", "") or "").splitlines():
        k, _, v = line.partition("=")
        rel[k] = v.strip().strip('"')
    u = os.uname()
    out = {
        "name": rel.get("PRETTY_NAME") or rel.get("NAME"),
        "kernel": {"name": u.sysname, "release": u.release, "build": u.version, "architecture": u.machine},
        "hostname": u.nodename,
        "init": os.path.basename(os.path.realpath("/sbin/init")) if os.path.exists("/sbin/init") else None,
    }
    nixos = read_sys("/run/current-system/nixos-version")
    if nixos:
        out["nixos_version"] = nixos
        try:
            m = re.search(r"system-(\d+)-link", os.readlink("/nix/var/nix/profiles/system"))
        except OSError:
            m = None
        if m:
            out["nixos_generation"] = int(m.group(1))
        booted, current = os.path.realpath("/run/booted-system"), os.path.realpath("/run/current-system")
        if os.path.exists("/run/booted-system") and booted != current:
            out["reboot_pending"] = "the running system differs from the one booted (a reboot applies the new kernel or initrd)"
    kver = re.match(r"(\d+)\.(\d+)", u.release)
    if kver:
        out["kernel"]["series"] = f"{kver.group(1)}.{kver.group(2)}"
    tainted = sys_int("/proc/sys/kernel/tainted")
    if tainted:
        out["kernel"]["tainted"] = tainted
    modules = read_sys("/proc/modules")
    if modules is not None:
        out["kernel"]["loaded_modules"] = len(modules.splitlines())
    uptime = read_sys("/proc/uptime", "0").split()[0]
    up = float(uptime)
    out["uptime"] = human_duration(up)
    out["booted_at"] = datetime.datetime.fromtimestamp(time.time() - up).isoformat(timespec="minutes")
    load = read_sys("/proc/loadavg", "").split()
    if len(load) >= 4:
        out["load_average"] = {"1min": float(load[0]), "5min": float(load[1]), "15min": float(load[2])}
        out["processes"] = int(load[3].split("/")[1])
    return out


def cpu_info():
    text = read_sys("/proc/cpuinfo", "") or ""
    first = {}
    cores, mhz = set(), []
    phys = "0"
    for line in text.splitlines():
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip()
        if k == "physical id":
            phys = v
        elif k == "core id":
            cores.add((phys, v))
        elif k == "cpu MHz":
            try:
                mhz.append(float(v))
            except ValueError:
                pass
        if k and k not in first:
            first[k] = v
    model = first.get("model name") or first.get("Model") or first.get("Hardware")
    out = {
        "model": re.sub(r"\s+", " ", model) if model else None,
        "vendor": first.get("vendor_id"),
        "cores": len(cores) or None,
        "threads": os.cpu_count(),
    }
    freq = "/sys/devices/system/cpu/cpu0/cpufreq"
    top = sys_int(f"{freq}/cpuinfo_max_freq")
    if top:
        out["max_mhz"] = round(top / 1000)
    cur = []
    for c in range(os.cpu_count() or 0):
        f = sys_int(f"/sys/devices/system/cpu/cpu{c}/cpufreq/scaling_cur_freq")
        if f:
            cur.append(f / 1000)
    cur = cur or mhz
    if cur:
        out["current_mhz"] = {"average": round(sum(cur) / len(cur)), "highest": round(max(cur))}
    out["governor"] = read_sys(f"{freq}/scaling_governor")
    out["energy_profile"] = read_sys(f"{freq}/energy_performance_preference")
    flags = set(first.get("flags", "").split())
    if flags:
        out["virtualization"] = "VT-x" if "vmx" in flags else "AMD-V" if "svm" in flags else None
    try:
        idle0, total0 = cpu_times()
        time.sleep(0.2)
        idle1, total1 = cpu_times()
        out["usage_percent"] = round(100 * (1 - (idle1 - idle0) / max(1, total1 - total0)))
    except (ValueError, IndexError):
        pass
    return {k: v for k, v in out.items() if v is not None}


def memory_info():
    m = meminfo()
    total, avail = m.get("MemTotal"), m.get("MemAvailable")
    out = {
        "total": human_bytes(total),
        "used": human_bytes(total - avail) if total and avail is not None else None,
        "available": human_bytes(avail),
        "used_percent": round(100 * (total - avail) / total) if total and avail is not None else None,
    }
    if m.get("SwapTotal"):
        out["swap"] = {"total": human_bytes(m["SwapTotal"]), "used": human_bytes(m["SwapTotal"] - m.get("SwapFree", 0))}
        zram = [d for d in os.listdir("/sys/block") if d.startswith("zram")] if os.path.isdir("/sys/block") else []
        if zram:
            out["swap"]["zram"] = True
    return out


def gpu_info():
    gpus = []
    drm = "/sys/class/drm"
    try:
        cards = sorted(c for c in os.listdir(drm) if re.fullmatch(r"card\d+", c))
    except OSError:
        return gpus
    for card in cards:
        dev = f"{drm}/{card}/device"
        g = {"card": card}
        driver = os.path.realpath(f"{dev}/driver") if os.path.exists(f"{dev}/driver") else None
        if driver:
            g["driver"] = os.path.basename(driver)
        slot = os.path.basename(os.path.realpath(dev))
        name = None
        if re.fullmatch(r"[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]", slot) and shutil.which("lspci"):
            try:
                p = run(["lspci", "-mm", "-s", slot], check=False, timeout=3)
                fields = shlex.split(p.stdout.strip()) if p.stdout else []
                if len(fields) >= 4:
                    name = f"{fields[2]} {fields[3]}"
            except (ToolError, ValueError):
                pass
        g["name"] = name or f"PCI {read_sys(f'{dev}/vendor', '?')}:{read_sys(f'{dev}/device', '?')}"
        vram, used = sys_int(f"{dev}/mem_info_vram_total"), sys_int(f"{dev}/mem_info_vram_used")
        if vram:
            g["vram"] = human_bytes(vram)
            if used is not None:
                g["vram_used"] = human_bytes(used)
        busy = sys_int(f"{dev}/gpu_busy_percent")
        if busy is not None:
            g["busy_percent"] = busy
        if sys_int(f"{dev}/boot_vga") == 1:
            g["primary"] = True
        gpus.append(g)
    return gpus


def display_info():
    try:
        outputs = niri_json("outputs") or {}
    except ToolError:
        return None
    out = []
    for name, o in outputs.items():
        mode = None
        modes, cur = o.get("modes") or [], o.get("current_mode")
        if isinstance(cur, int) and 0 <= cur < len(modes):
            m = modes[cur]
            mode = f"{m.get('width')}x{m.get('height')} @ {round((m.get('refresh_rate') or 0) / 1000)} Hz"
        size = o.get("physical_size")
        inches = round(math.hypot(*size) / 25.4, 1) if size and all(size) else None
        out.append({
            "connector": name,
            "screen": " ".join(v for v in (o.get("make"), o.get("model")) if v and v != "Unknown") or None,
            "mode": mode,
            "size_inches": inches,
            "scale": (o.get("logical") or {}).get("scale"),
        })
    return out


def storage_info():
    disks = []
    try:
        names = sorted(os.listdir("/sys/block"))
    except OSError:
        names = []
    for d in names:
        if re.match(r"(loop|ram|zram|dm-|md|sr|fd)", d):
            continue
        base = f"/sys/block/{d}"
        sectors = sys_int(f"{base}/size")
        if not sectors:
            continue
        kind = "NVMe SSD" if d.startswith("nvme") else (
            "HDD" if sys_int(f"{base}/queue/rotational") == 1 else "SSD")
        if d.startswith("mmcblk"):
            kind = "SD/eMMC"
        if sys_int(f"{base}/removable") == 1:
            kind += " (removable)"
        model = read_sys(f"{base}/device/model") or read_sys(f"{base}/device/name")
        disks.append({"device": d, "model": (model or "").strip() or None, "type": kind,
                      "size": human_bytes(sectors * 512)})
    mounts, seen = [], set()
    for line in (read_sys("/proc/self/mounts", "") or "").splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        src, target, fstype = parts[0], parts[1].replace("\\040", " "), parts[2]
        if not src.startswith("/dev/") or target.startswith("/nix/store") or src in seen:
            continue
        seen.add(src)
        try:
            st = os.statvfs(target)
        except OSError:
            continue
        size, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
        if not size:
            continue
        mounts.append({"mount": target, "filesystem": fstype, "size": human_bytes(size),
                       "free": human_bytes(free), "used_percent": round(100 * (1 - free / size))})
    return {"disks": disks, "filesystems": mounts}


def temperature_info():
    out = {}
    try:
        mons = sorted(os.listdir("/sys/class/hwmon"))
    except OSError:
        return out
    for mon in mons:
        base = f"/sys/class/hwmon/{mon}"
        name = read_sys(f"{base}/name", mon)
        try:
            inputs = sorted(f for f in os.listdir(base) if re.fullmatch(r"temp\d+_input", f))
        except OSError:
            continue
        readings = {}
        for f in inputs:
            v = sys_int(f"{base}/{f}")
            if v is None or v <= 0:
                continue
            label = read_sys(f"{base}/{f.replace('_input', '_label')}") or f.split("_")[0]
            readings[label] = round(v / 1000, 1)
        if readings:
            key = name if name not in out else f"{name} ({mon})"
            out[key] = readings
        fans = {}
        for f in sorted(os.listdir(base)):
            if re.fullmatch(r"fan\d+_input", f):
                rpm = sys_int(f"{base}/{f}")
                if rpm is not None:
                    fans[read_sys(f"{base}/{f.replace('_input', '_label')}") or f.split("_")[0]] = rpm
        if fans:
            out.setdefault("fans_rpm", {}).update(fans)
    return out


def power_info():
    out = {"batteries": []}
    base = "/sys/class/power_supply"
    try:
        supplies = sorted(os.listdir(base))
    except OSError:
        return None
    for s in supplies:
        p = f"{base}/{s}"
        kind = read_sys(f"{p}/type")
        if kind == "Mains":
            out["plugged_in"] = sys_int(f"{p}/online") == 1
        elif kind == "Battery" and read_sys(f"{p}/scope") != "Device":
            b = {"name": s, "level_percent": sys_int(f"{p}/capacity"), "status": read_sys(f"{p}/status"),
                 "model": " ".join(v for v in (read_sys(f"{p}/manufacturer"), read_sys(f"{p}/model_name")) if v) or None,
                 "technology": read_sys(f"{p}/technology")}
            full = sys_int(f"{p}/energy_full") or sys_int(f"{p}/charge_full")
            design = sys_int(f"{p}/energy_full_design") or sys_int(f"{p}/charge_full_design")
            if full and design:
                b["health_percent"] = round(100 * full / design)
            cycles = sys_int(f"{p}/cycle_count")
            if cycles:
                b["cycles"] = cycles
            power = sys_int(f"{p}/power_now")
            if power:
                b["power_draw_watts"] = round(power / 1e6, 1)
            limit = sys_int(f"{p}/charge_control_end_threshold")
            if limit:
                b["charge_limit_percent"] = limit
            out["batteries"].append({k: v for k, v in b.items() if v is not None})
    profile = read_sys("/sys/firmware/acpi/platform_profile")
    if profile:
        out["platform_profile"] = profile
    return out if out["batteries"] or "plugged_in" in out else None


def network_info():
    out = []
    try:
        ifaces = sorted(os.listdir("/sys/class/net"))
    except OSError:
        return out
    for i in ifaces:
        p = f"/sys/class/net/{i}"
        if i == "lo" or not os.path.exists(f"{p}/device"):
            continue  # virtual (bridges, VPNs, containers)
        kind = "Wi-Fi" if os.path.isdir(f"{p}/wireless") or os.path.isdir(f"{p}/phy80211") else "Ethernet"
        state = read_sys(f"{p}/operstate")
        n = {"interface": i, "type": kind, "state": state}
        drv = f"{p}/device/driver"
        if os.path.exists(drv):
            n["driver"] = os.path.basename(os.path.realpath(drv))
        speed = sys_int(f"{p}/speed") if state == "up" and kind == "Ethernet" else None
        if speed and speed > 0:
            n["speed_mbps"] = speed
        out.append(n)
    vpns = [i for i in ifaces if re.match(r"(tailscale|wt|wg|tun)\d*", i)]
    if vpns:
        out.append({"vpn_interfaces": vpns})
    return out


SYSTEM_SECTIONS = {
    "os": os_info,
    "machine": machine_info,
    "cpu": cpu_info,
    "memory": memory_info,
    "gpu": gpu_info,
    "displays": display_info,
    "storage": storage_info,
    "temperatures": temperature_info,
    "power": power_info,
    "network": network_info,
}


@tool(
    "system_info",
    "observe",
    "This computer itself, read live: the OS (distribution, NixOS version and "
    "generation, uptime, load), the kernel (release, build, architecture, "
    "modules), the machine (vendor, model, firmware), CPU (model, cores, "
    "frequency, usage), memory and swap, GPUs, displays, disks and free "
    "space, temperatures and fans, battery and power, network adapters. "
    "Use it for any question about the hardware, the OS or the kernel, or "
    "how the machine is doing. Works while desktop control is paused.",
    obj({"sections": {"type": "array", "items": {"enum": list(SYSTEM_SECTIONS)},
                      "description": "Only these sections (default: all)"}}),
    read_only=True,
)
def t_system_info(ctx, args):
    wanted = args.get("sections")
    if not isinstance(wanted, list) or not wanted:
        wanted = list(SYSTEM_SECTIONS)
    out = {}
    for name in wanted:
        fn = SYSTEM_SECTIONS.get(name)
        if not fn:
            continue
        try:
            value = fn()
        except Exception as e:  # one unreadable section must not hide the rest
            log(f"system_info {name}: {e!r}")
            value = None
        if value not in (None, {}, []):
            out[name] = value
    return [text(out)]


@tool(
    "tool_help",
    "observe",
    "A tool's full guide (every action and argument), also for tools not loaded yet; without `name`, "
    "every tool on offer in one line each.",
    obj({"name": {"type": "string", "description": "The tool's name"}}),
    read_only=True,
)
def t_tool_help(ctx, args):
    on = enabled_tools(ctx.cfg)
    name = args.get("name")
    if name is None or name == "":
        return [text("\n".join(f"{n}: {first_sentence(t['spec']['description'])}" for n, t in on.items()))]
    if not isinstance(name, str) or name not in on:
        raise ToolError(f"no tool {short(str(name), 60)!r} on offer (tool_help without a name lists them)")
    return [text(guide_text(name))]


def first_sentence(value, limit=140):
    value = re.split(r"(?<=\.)\s", value.strip(), maxsplit=1)[0]
    return short(value, limit)


# -- the machine's reference (system-context.md) ------------------------------
# The Home Manager module writes what this machine is (its modules, packages,
# key bindings, how-tos, Neovim keymaps) into system-context.md. The prompt
# carries only a summary: machine_help finds the parts a question needs.

MACHINE_HELP_MAX = 3000
MACHINE_HELP_LONG = 700  # a longer line (a list of packages…): only what matches
MACHINE_HELP_ALIASES = (
    (("shortcut", "keybind", "key binding"), {"shortcut", "shortcuts", "keybind", "keybinds", "keybinding", "keybindings",
                                              "bind", "binding", "bindings", "key", "keys", "hotkey", "hotkeys",
                                              "raccourci", "raccourcis", "tastenkurzel", "tastenkombination", "phim", "tat"}),
    (("neovim", "nvim"), {"neovim", "nvim", "vim", "keymap", "keymaps", "leader"}),
    (("package",), {"installed", "install", "package", "packages", "program", "programs", "paquet", "paket"}),
    (("module",), {"module", "modules", "enabled", "option", "options"}),
)
# Verbs any how-to has: they count little ("how do I add a routine": routine).
MACHINE_HELP_WEAK = {"add", "make", "set", "change", "get", "turn", "show", "see", "find", "work", "works", "put",
                     "start", "stop", "run", "ajouter", "mettre", "changer", "hinzufugen", "andern", "them", "doi"}
_MACHINE_DOC = {"key": None, "units": []}


def machine_context_path():
    return os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "nixbook-shell", "system-context.md")


def machine_units():
    """system-context.md as [(section heading, text)], one per line, bullet
    (with its wrapped lines) or paragraph; read again when it changes."""
    path = machine_context_path()
    try:
        st = os.stat(path)
        key = (path, st.st_mtime_ns, st.st_size)
        if _MACHINE_DOC["key"] == key:
            return _MACHINE_DOC["units"]
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    units, heading, cur = [], "", None
    for raw in lines:
        line = raw.rstrip()
        if line.startswith("#"):
            heading, cur = line.lstrip("#").strip(), None
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("```") or stripped in ("binds {", "}"):
            cur = None
            continue
        if stripped.startswith(("- ", "* ")) or re.match(r"[\w+<>-]+\s*\{", stripped) or cur is None:
            units.append([heading, stripped])
            cur = units[-1] if not re.match(r"[\w+<>-]+\s*\{", stripped) else None
        else:
            cur[1] += " " + stripped
    _MACHINE_DOC["key"], _MACHINE_DOC["units"] = key, [tuple(u) for u in units]
    return _MACHINE_DOC["units"]


def machine_help(query, limit=MACHINE_HELP_MAX):
    units = machine_units()
    if not units:
        return "The machine's reference (system-context.md) isn't there: answer from what you know."
    sections = list(dict.fromkeys(h for h, _ in units))
    q = set(words(query))
    combos = [c.lower() for c in re.findall(r"(?i)\b((?:mod|super|ctrl|control|alt|shift)(?:\+[\w-]+)+)", query or "")]
    if not q and not combos:
        return "Sections of the machine's reference (ask about one): " + "; ".join(h for h in sections if h)
    toks = [set(words(t)) for _, t in units]
    n = len(units)
    idf = {w: math.log(1 + n / (1 + sum(1 for u in toks if _match(w, u)))) * (0.3 if w in MACHINE_HELP_WEAK else 1)
           for w in q}
    wanted = {h for h in sections for keys, alias in MACHINE_HELP_ALIASES
              if any(k in h.lower() for k in keys) and q & alias}
    scored = []
    for i, ((heading, body), uw) in enumerate(zip(units, toks)):
        score = sum(idf[w] for w in q if _match(w, uw))
        if score and len(body) > 160:
            # What a long line is about is in its start.
            lead = set(words(body[:120]))
            score += sum(0.5 * idf[w] for w in q if _match(w, lead))
        if heading in wanted and score:
            score += 1
        if any(body.lower().startswith(c + " ") or body.lower().startswith(c + "{") for c in combos):
            score += 10
        if score > 0:
            scored.append((score, i))
    if not scored:
        packages = [h for h in wanted if "package" in h.lower()]
        item_words = q - {w for _, alias in MACHINE_HELP_ALIASES for w in alias}
        if packages and item_words:
            # "Is X installed?" with nothing about X anywhere: it isn't.
            return (f"## Packages\n{', '.join(sorted(item_words))}: not among the installed packages "
                    f"({'; '.join(packages)})")
        return (f"Nothing about {short(query, 80)!r} in the machine's reference; its sections: "
                + "; ".join(h for h in sections if h))
    best = max(sc for sc, _ in scored)
    # Only what is about the question: a floor under the best match; and
    # when it names a section (the key bindings, the packages…), that one.
    kept = [x for x in scored if x[0] >= 0.5 * best]
    if wanted and any(units[i][0] in wanted for _, i in kept):
        kept = [x for x in kept if units[x[1]][0] in wanted or x[0] >= best]
    # Ties: the shorter line, more to the point.
    kept.sort(key=lambda x: (-x[0], len(units[x[1]][1])))
    item_words = q - {w for _, alias in MACHINE_HELP_ALIASES for w in alias}
    by_section, used = {}, 0
    for _, i in kept:
        heading, body = units[i]
        body = machine_excerpt(body, item_words, q)
        if not body:
            continue
        cost = len(body) + 1 + (0 if heading in by_section else len(heading) + 5)
        if used + cost > limit:
            continue
        by_section.setdefault(heading, []).append(body)
        used += cost
    missing = [h for h in wanted if "package" in h.lower() and h not in by_section]
    if missing and item_words and not any("package" in h.lower() for h in by_section):
        # "Is X installed?": not among the packages is the answer.
        by_section = {"Packages": [f"{', '.join(sorted(item_words))}: not among the installed packages "
                                   f"({'; '.join(missing)})"], **by_section}
    if not by_section:
        return (f"Nothing about {short(query, 80)!r} in the machine's reference (not among its packages, modules, "
                "key bindings or how-tos)")
    return "\n".join(f"## {h}\n" + "\n".join(b) for h, b in by_section.items())


# A question about how this machine works (how do I…, which key…, is X
# installed…), in the shell's four languages: what gets the reference's
# matching parts with the message (machine_context), so the answer needs
# no machine_help round trip. Orders ("play some music", "close Slack")
# and other questions get nothing: the parts that matched them by a word
# would only cost tokens and mislead.
MACHINE_ASK = re.compile(
    r"\b(how (do|can|could|would|to|does|should|is)|how's|which (key|shortcut|button|setting)|what (key|shortcut|"
    r"keybind|does (mod|super|ctrl|alt|shift)\b)|shortcut|keybind|hotkey|key binding|keymap|where (is|are|do|can|"
    r"does)|is \S+ installed|do i have|is there a way|can i\b|settings?\b.*\?|comment (je|on|faire|puis|activer|"
    r"changer|mettre)|raccourci|touche|où (est|sont|se)|est[- ]ce que (je|on) peut|est[- ]il install|wie (kann|mache|"
    r"geht|stelle|ändere|aktiviere)|tastenk(ü|ue|u)rzel|wo (ist|sind|finde)|ist \S+ installiert|làm sao|làm thế nào|"
    r"cách (nào|để)|phím tắt|ở đâu|có cài)", re.I)
MACHINE_CONTEXT_MAX = 1500


def machine_context(query, exclude=()):
    """The reference's parts about a help question, for the chat to send
    with it: (text, ids), ids naming its lines (sent once a conversation:
    `exclude`). Nothing for what isn't such a question."""
    if not MACHINE_ASK.search(query or ""):
        return "", []
    found = machine_help(query, limit=MACHINE_CONTEXT_MAX)
    if not found.startswith("## "):
        return "", []
    out, ids, seen = [], [], set(exclude)
    for line in found.split("\n"):
        if line.startswith("## "):
            out.append(line)
            continue
        i = "m:" + hashlib.sha1(line.encode()).hexdigest()[:10]
        if i in seen:
            continue
        out.append(line)
        ids.append(i)
    if not ids:
        return "", []
    # Headings left without a line under them go.
    text_ = "\n".join(l for k, l in enumerate(out) if not (l.startswith("## ") and (k + 1 == len(out) or out[k + 1].startswith("## "))))
    return ("(From this machine's reference, about this question; machine_help has the rest:\n<<<\n"
            + text_ + "\n>>>)"), ids


def machine_excerpt(body, items_asked, q):
    """A line as machine_help gives it: a list (packages, modules) cut to
    the items asked for ("" when none is), a long paragraph to its first
    sentence and those that match."""
    lead, sep, rest = body.partition(": ")
    items = [x.strip() for x in (rest if sep else body).split(",")]
    # A list: items of a word or two, not prose.
    if len(items) >= 8 and sum(1 for x in items if len(x.split()) <= 2) >= 0.8 * len(items):
        if not items_asked:
            return short(body, MACHINE_HELP_LONG)
        hits = [x for x in items if any(_match(w, set(words(x))) for w in items_asked)]
        if not hits:
            return ""
        return (lead + ": " if sep else "") + ", ".join(hits[:40]) + f" (of {len(items)})"
    if len(body) <= MACHINE_HELP_LONG:
        return body
    want = items_asked or q
    sentences = [x if len(x) <= 350 else x[:350].rsplit(" ", 1)[0] + "…" for x in re.split(r"(?<=[.;!?])\s+", body)]
    text_ = sentences[0]
    for x in sentences[1:]:
        if any(_match(w, set(words(x))) for w in want) and len(text_) + len(x) + 1 <= MACHINE_HELP_LONG:
            text_ += " " + x
    return text_


@tool(
    "machine_help",
    "observe",
    "Look up this machine's own reference (its NixOS/Home Manager config: how-tos, niri key bindings, Neovim "
    "keymaps, enabled modules, installed packages): the parts about `query`, at most 3000 characters. For "
    "\"how do I…\", \"which key…\", \"is X installed\" on this computer.",
    obj({"query": {"type": "string", "description": "What to look up, e.g. \"screenshot shortcut\", \"is firefox installed\""}},
        ["query"]),
    read_only=True,
)
def t_machine_help(ctx, args):
    query = args.get("query")
    if not isinstance(query, str):
        raise ToolError("`query` must be a string")
    return [text(machine_help(clean_text(query, 300)))]


# -- applications ------------------------------------------------------------


def desktop_dirs():
    dirs = [os.path.join(xdg("XDG_DATA_HOME", "~/.local/share"), "applications")]
    for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(os.path.join(d, "applications"))
    return dirs


def parse_desktop(path):
    entry, section = {}, None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    section = line
                    continue
                if section != "[Desktop Entry]" or "=" not in line or line.startswith("#"):
                    continue
                k, v = line.split("=", 1)
                entry.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return entry


_apps_cache = {"time": 0.0, "apps": None}


def applications():
    """The installed .desktop entries, read again at most every 30 s."""
    now = time.monotonic()
    if _apps_cache["apps"] is None or now - _apps_cache["time"] > 30:
        _apps_cache["apps"] = read_applications()
        _apps_cache["time"] = now
    return _apps_cache["apps"]


def read_applications():
    apps = {}
    for d in desktop_dirs():
        if not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".desktop"):
                    continue
                path = os.path.join(root, fn)
                app_id = os.path.relpath(path, d)[: -len(".desktop")].replace("/", "-")
                if app_id in apps:  # earlier directories win (XDG order)
                    continue
                e = parse_desktop(path)
                if not e or e.get("Type") != "Application" or not e.get("Exec"):
                    continue
                if e.get("Hidden") == "true":
                    continue
                apps[app_id] = e
    return apps


FIELD_CODE = re.compile(r"%[fFuUdDnNickvm]")


def exec_argv(entry):
    cmd = FIELD_CODE.sub("", entry["Exec"]).replace("%%", "%")
    argv = shlex.split(cmd)
    if not argv:
        raise ToolError("the application has an empty Exec line")
    return argv


@tool(
    "list_apps",
    "observe",
    "Search the installed applications (their .desktop entries). Returns id and name.",
    obj({"query": {"type": "string", "description": "Part of the name or id; omit for all"}}),
    read_only=True,
)
def t_list_apps(ctx, args):
    q = (args.get("query") or "").lower()
    out = [
        {"id": i, "name": e.get("Name"), "comment": e.get("Comment")}
        for i, e in sorted(applications().items())
        if e.get("NoDisplay") != "true" and (not q or q in i.lower() or q in (e.get("Name") or "").lower())
    ]
    return [text(out[:60] + ([f"… {len(out) - 60} more, narrow the query"] if len(out) > 60 else []))]


@tool(
    "launch_app",
    "windows",
    "Start an installed application by its id or name (see list_apps), wait "
    "for its window (up to 10 s) and say which it is. Only .desktop entries "
    "can be started: no arbitrary commands or arguments. On a desktop of "
    "your own it shows one app at a time, fullscreen: the apps you had open "
    "stay in the background (focus_window brings one back).",
    obj({"app": {"type": "string", "description": "Application id (e.g. firefox) or name"}}, ["app"]),
)
def t_launch_app(ctx, args):
    want = as_str(args, "app", max_len=128)
    apps = applications()
    alias = read_memory()["aliases"].get(want.lower())
    if alias in apps:
        want = alias
    entry = apps.get(want) or apps.get(want.removesuffix(".desktop"))
    if not entry:
        visible = {i: e for i, e in apps.items() if e.get("NoDisplay") != "true"}
        exact = [i for i, e in visible.items() if (e.get("Name") or "").lower() == want.lower()]
        partial = [
            i for i, e in visible.items() if want.lower() in i.lower() or want.lower() in (e.get("Name") or "").lower()
        ]
        matches = exact or partial
        if len(matches) != 1:
            if not matches:
                launch_failed(want)
                raise ToolError(f"no application matches {want!r}; see list_apps")
            raise ToolError(f"{want!r} is ambiguous: {', '.join(sorted(matches)[:15])}")
        want, entry = matches[0], visible[matches[0]]
    if entry.get("Terminal") == "true":
        raise ToolError("refused: terminal applications can't be started by the agent")
    ctx.guard.check_rate()
    before = {w.get("id") for w in windows()}
    # Spawned by niri, not as our child: it outlives this server.
    niri_action("spawn", "--", *exec_argv(entry))
    learn_launch(args["app"], next((i for i, e in apps.items() if e is entry), want))
    name = entry.get("Name") or want
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        time.sleep(0.2)
        new = [w for w in windows() if w.get("id") not in before]
        if new:
            # A splash window may come first: give the app a moment to settle.
            time.sleep(0.3)
            new = [w for w in windows() if w.get("id") not in before] or new
            main = next((w for w in new if w.get("is_focused")), new[-1])
            return launched(ctx, name, main, new)
    return [text(f"started {name}, but no new window appeared within 10 s (a single-instance "
                 "app may have raised its existing window instead; see the focused window below)")]


def launched(ctx, name, main, new):
    return [text({"started": name, "window": slim_window(main)})]


# -- windows and workspaces --------------------------------------------------


@tool(
    "focus_window",
    "windows",
    "Focus a window (niri scrolls to it and switches workspace if needed).",
    obj({"id": INT}, ["id"]),
)
def t_focus_window(ctx, args):
    wid = as_int(args, "id")
    window_by_id(wid)
    ctx.guard.check_rate()
    niri_action("focus-window", "--id", str(wid))
    return [text(f"focused window {wid}")]



def app_windows(want, apps):
    """The open windows of an app named by its desktop id, app id or name
    (most recently focused first)."""
    w_ = str(want or "").removesuffix(".desktop").lower()
    if not w_:
        return []
    out = []
    for w in windows():
        app_id = w.get("app_id") or ""
        desktop = desktop_for_app(app_id, apps) or ""
        name = ((apps.get(desktop) or {}).get("Name") or "").lower()
        desktop = desktop.lower()
        if same_app(app_id, w_) or desktop == w_ or desktop.rsplit(".", 1)[-1] == w_ or (name and name == w_):
            out.append(w)

    def recent(w):
        # niri's focus_timestamp (recent niri): {secs, nanos}.
        ts = w.get("focus_timestamp") if isinstance(w.get("focus_timestamp"), dict) else {}
        return bool(w.get("is_focused")), ts.get("secs") or 0, ts.get("nanos") or 0, w.get("id") or 0

    return sorted(out, key=recent, reverse=True)


@tool(
    "focus_app",
    "windows",
    "Bring an app to the front by its id or name (list_apps): its most recently used window, or, "
    "when it has none open, the app started as launch_app does. What a recipe uses to come back to an "
    "app (a window id changes from one day to the next).",
    obj({"app": {"type": "string", "description": "Application id (e.g. zen, kitty) or name"}}, ["app"]),
    # A recipe's step: agents have focus_window with an id.
    hidden=True,
)
def t_focus_app(ctx, args):
    want = as_str(args, "app", max_len=128)
    apps = applications()
    alias = read_memory()["aliases"].get(want.lower())
    found = app_windows(want, apps) or (app_windows(alias, apps) if alias else [])
    if not found:
        return t_launch_app(ctx, {"app": want})
    w = found[0]
    ctx.guard.check_rate()
    niri_action("focus-window", "--id", str(w["id"]))
    return [text(f"focused {w.get('app_id')} — {short(w.get('title') or '', 80)!r} (window {w['id']})")]

@tool(
    "close_window",
    "windows",
    "Close a window (as its close button would: the app may ask to save).",
    obj({"id": INT}, ["id"]),
    destructive=True,
)
def t_close_window(ctx, args):
    wid = as_int(args, "id")
    window_by_id(wid)
    ctx.guard.check_rate()
    niri_action("close-window", "--id", str(wid))
    return [text(f"asked window {wid} to close")]


@tool(
    "focus_workspace",
    "windows",
    "Switch to a workspace on the focused monitor.",
    obj({"workspace": WS}, ["workspace"]),
)
def t_focus_workspace(ctx, args):
    ref = workspace_ref(args)
    ctx.guard.check_rate()
    niri_action("focus-workspace", ref)
    return [text(f"switched to workspace {ref}")]


@tool(
    "move_window_to_workspace",
    "windows",
    "Move a window to another workspace.",
    obj({"id": INT, "workspace": WS, "follow": {"type": "boolean", "description": "Follow the window there (default false)"}}, ["id", "workspace"]),
)
def t_move_window(ctx, args):
    wid = as_int(args, "id")
    ref = workspace_ref(args)
    window_by_id(wid)
    ctx.guard.check_rate()
    follow = "true" if args.get("follow") is True else "false"
    niri_action("move-window-to-workspace", "--window-id", str(wid), "--focus", follow, ref)
    return [text(f"moved window {wid} to workspace {ref}")]


WINDOW_ACTIONS = {
    # action: (niri action, takes --id)
    "fullscreen": ("fullscreen-window", True),
    "toggle_floating": ("toggle-window-floating", True),
    "maximize_column": ("maximize-column", False),
    "center": ("center-column", False),
    "wider": ("set-column-width", False),
    "narrower": ("set-column-width", False),
}


@tool(
    "window_action",
    "windows",
    "Change a window's layout: fullscreen (toggle), toggle_floating, "
    "maximize_column (toggle), center, wider or narrower (±10%).",
    obj({"id": INT, "action": {"type": "string", "enum": list(WINDOW_ACTIONS)}}, ["id", "action"]),
)
def t_window_action(ctx, args):
    wid = as_int(args, "id")
    action = as_str(args, "action", max_len=32)
    if action not in WINDOW_ACTIONS:
        raise ToolError(f"`action` must be one of {', '.join(WINDOW_ACTIONS)}")
    window_by_id(wid)
    ctx.guard.check_rate()
    niri_cmd, takes_id = WINDOW_ACTIONS[action]
    if takes_id:
        niri_action(niri_cmd, "--id", str(wid))
    else:
        niri_action("focus-window", "--id", str(wid))
        extra = {"wider": ["+10%"], "narrower": ["-10%"]}.get(action, [])
        niri_action(niri_cmd, *extra)
    return [text(f"{action}: window {wid}")]


# -- desktop memory -------------------------------------------------------------
# What makes the next task faster: usage counted as agents work (apps
# launched, layouts restored, tools used), aliases learned from launch_app
# (a name that failed, then the app that worked), and notes agents write
# (shortcuts, where things are, run_steps recipes). A digest goes to every
# agent when it connects (MCP `instructions`) and to the shell's AI chat.
# ~/.local/state/nixbook-shell/desktop-memory.json, private; the user
# reviews it in Settings > Desktop agents or with `nixbook-desktop-mcp memory`.
#
# Kept the way a person keeps what they learned, in plain code (no model,
# no tokens):
#   - a note is strong for what it did, not for being read: `ok` and
#     `fail` count the tasks it was given for that went well or not (the
#     episode, below), `shown` only how often agents got it;
#   - it is ranked by ACT-R's base-level activation, ln Σ tⱼ^-d over the
#     times it helped (`hist`, the last NOTE_TRACES; uses within
#     NOTE_SPACING count once: spaced practice), plus what it proved;
#   - a note below NOTE_THRESHOLD isn't offered unasked, and one unused for
#     longer than what it proved holds it (NOTE_FADE_DAYS) moves to the
#     archive, where recall still finds it and brings it back;
#   - where it came from (`source`): seen working, told by the user, or
#     read in content (a page, a message: tentative until it works, and
#     never an instruction); a replaced text is kept as `was`.

NOTE_TOPIC_MAX = 60
NOTE_TEXT_MAX = 600
RECIPE_TEXT_MAX = 1500
NOTE_TRACES = 10
NOTE_SPACING = 3600
NOTE_DECAY = 0.5
NOTE_THRESHOLD = -2.5
# Days unused before a note fades: by the tasks it helped (0, 1-2, 3+).
NOTE_FADE_DAYS = (90, 180, 365)
NOTE_TENTATIVE_DAYS = 60
NOTE_SOURCES = ("seen", "user", "read", "inferred")
ARCHIVE_MAX = 200


def memory_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "desktop-memory.json")


def empty_memory():
    return {"version": 4, "notes": [], "aliases": {}, "usage": {"apps": {}, "layouts": {}, "tools": {}},
            "targets": {}, "triggers": [], "archive": [], "routines": []}


class Memory:
    """The memory file, read and written under an exclusive lock (several
    agents' servers and the shell may write at once)."""

    path = staticmethod(memory_path)
    empty = staticmethod(empty_memory)

    def __enter__(self):
        path = self.path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.lockfd = os.open(path + ".lock", os.O_WRONLY | os.O_CREAT, 0o600)
        fcntl.flock(self.lockfd, fcntl.LOCK_EX)
        try:
            with open(path, encoding="utf-8") as f:
                self.data = json.load(f)
            if not isinstance(self.data, dict):
                raise ValueError
        except (OSError, ValueError):
            self.data = self.empty()
        for k, v in self.empty().items():
            self.data.setdefault(k, v)
        self.changed = False
        self.migrate()
        return self

    def migrate(self):
        for k, v in empty_memory()["usage"].items():
            self.data["usage"].setdefault(k, v)
        if self.data.get("version", 1) < 2:
            # Version 1 linked notes to any app sharing a word with their
            # topic ("search" -> Web Search Keywords): link them again.
            for n in self.data["notes"]:
                n["apps"] = note_apps(n.get("topic", ""), self.data["aliases"], self.data["usage"]["apps"])
            self.data["version"] = 2
            self.changed = True
        if self.data["version"] < 3:
            # Version 2 counted a note's uses each time it was shown: that is
            # `shown` now; its strength starts from its last update. Recipes
            # were their steps' JSON in the text: steps of their own.
            for n in self.data["notes"]:
                n["shown"] = n.pop("uses", 0)
                # Given often, so about the tasks agents do: held a while
                # longer, until its own outcomes say.
                n.setdefault("ok", 1 if n["shown"] >= 20 else 0)
                n.setdefault("hist", [n.get("updated") or n.get("created") or int(time.time())])
                n.setdefault("source", "seen")
                if n.get("kind") == "recipe" and "steps" not in n:
                    try:
                        steps = json.loads(n["text"].split(":", 1)[1])
                    except (ValueError, IndexError):
                        steps = None
                    if isinstance(steps, list) and steps:
                        n["steps"], n["vars"] = steps, recipe_vars(steps)
                        n["text"] = recipe_gist(steps)
            self.data["version"] = 3
            self.changed = True
        if self.data["version"] < 4:
            # Before music_repeating, "when a song repeats too long" could
            # only be a track_changed routine whose Claude run guessed the
            # repeat at each new track (and never saw a loop): the cue now.
            for r in self.data.get("routines") or []:
                when = r.get("when") if isinstance(r, dict) else None
                if (isinstance(when, dict) and when.get("event") == "track_changed"
                        and not any(when.get(k) for k in ("app", "words"))
                        and ROUTINE_REPEAT_WORDS.search(str(r.get("text") or ""))):
                    when["event"] = "music_repeating"
            self.data["version"] = 4
            self.changed = True

    def save(self):
        self.changed = True

    def __exit__(self, exc_type, *rest):
        try:
            if self.changed and exc_type is None:
                path = self.path()
                fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(self.data, f, indent=1, ensure_ascii=False)
                os.replace(path + ".tmp", path)
        finally:
            fcntl.flock(self.lockfd, fcntl.LOCK_UN)
            os.close(self.lockfd)


def read_memory():
    try:
        with Memory() as m:
            return m.data
    except OSError:
        return empty_memory()


def count_use(kind, key, **extra):
    """Usage, best effort: a failure to record never fails the tool."""
    try:
        with Memory() as m:
            entry = m.data["usage"][kind].setdefault(key, {"count": 0})
            entry["count"] += 1
            entry["last"] = int(time.time())
            entry.update(extra)
            m.save()
    except (OSError, ValueError, KeyError, TypeError):
        pass


def count_note_shown(ids, ctx=None):
    """Notes given to an agent (recalled, or sent because they are about its
    task or the app it reached): counted, and part of the agent's episode,
    whose outcome tells whether they helped (finish_episode)."""
    if not ids:
        return
    if ctx is not None:
        ctx.episode["notes"].update(ids)
    try:
        with Memory() as m:
            for n in m.data["notes"]:
                if n["id"] in ids:
                    n["shown"] = n.get("shown", 0) + 1
            m.save()
    except (OSError, ValueError, KeyError, TypeError):
        pass


def activation(n, now=None):
    """How likely a note is needed now (ACT-R's base-level learning): the
    times it helped, the recent ones weighing most, plus what it proved:
    the tasks it helped, less those it failed since it was last fixed."""
    now = now or time.time()
    times = n.get("hist") or [n.get("updated") or n.get("created") or now]
    base = math.log(sum(max((now - t) / 3600, 1) ** -NOTE_DECAY for t in times))
    return base + 0.5 * math.log1p(n.get("ok", 0)) - 0.7 * n.get("fail", 0)
