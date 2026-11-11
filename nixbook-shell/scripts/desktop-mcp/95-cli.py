# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The command line (main).

# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

USAGE = """usage: nixbook-desktop-mcp [COMMAND]

  (none) | serve          MCP over stdio (what MCP clients start)
  serve --http [--port N] MCP over HTTP on 127.0.0.1 (bearer token: `token`)
  helper                  the shell's: its quick commands on stdin (JSON lines), and
                          the privacy hooks over HTTP on 127.0.0.1
  tools                   the enabled tools, as MCP JSON
  call NAME [JSON]        run one tool; prints its text, exit 1 on refusal
  pause | resume | toggle stop / allow desktop control, for every client
                          (paused until first resumed; kept across reboots)
  status                  paused or not, config and audit log paths
  notify [on | off | toggle]  the "… is driving the desktop" notification
                          (on by default; kept across reboots)
  token                   the HTTP bearer token (created if needed)
  trust [list] | check CLASS [--risky 0|1] | set CLASS ask|tell|silent
                          the trust ladder: how much the shell's Claude may do on its
                          own, per kind of action (`set`: the user's, never an agent's)
  layout list             saved window layouts (JSON), for the user and the shell:
  layout save|restore NAME  not subject to the agents' pause or tool groups
  layout delete NAME | rename OLD NEW | cycle (restore the next one)
  layout restore|cycle --close-others  also close the windows not in the layout
  project list | show NAME  the projects (JSON): whole contexts (layout, Zen tabs,
                          Do Not Disturb, focus timer)
  project open NAME       open it as it was left (the windows before: the hidden
                          layout _before-undo)
  project save NAME [--pause] | pause NAME  save the desktop into it (a new one, or
                          update it); pause: then its rule (keep, tabs)
  project set NAME dnd on|off|none | focus MINUTES|pomodoro|0 | on-pause keep|tabs
  project delete NAME | rename OLD NEW
  find QUERY [--when W] [--kinds a,b] [--max N] [--json]  find_anything's search (recent
                          files, Zen history/bookmarks, clipboard, notifications,
                          chats), for the launcher's find prefix
  memory [show]           the desktop memory (JSON); memory prompt [QUERY]: the digest
  memory forget ID | clear [notes] [usage] [aliases] [targets] [triggers] [archive] [routines]
                          (default: all; notes with their archive)
  memory fire ID          a reminder was shown (the shell): gone, or not before tomorrow
  initiative consider JSON|-  what the agent would say about an event (the shell):
                          {"event": "back"|"focus"|"happened"|"notifications"|"moment", …}
  initiative pending|show|answer ID replied|later|dismissed|never|unmute [KEY…]|clear
  watch check [--busy] | list | cancel ID
                          what agents watch for the user (the shell checks every minute)
  extract PATH            a download extracted next to it (prints where)
  context JSON|-          the shell's recent events ({now, events}), filtered and redacted
  sent [show] | note PURPOSE TEXT | clear
                          what was sent to a model (JSON, newest first)
  privacy mask [--typed] | unmask
                          stdin to stdout: private details as placeholders, or back
                          (--typed: what the user typed, lowercase first names too)
  privacy hook            Claude Code's PreToolUse/PostToolUse hook for the same
  privacy show|clear      the placeholders given so far (JSON), or forget them
  privacy learned | unlearn KEY
                          the strangers' names learned private (JSON), or one not private
  routine list|run ID [EVENT_JSON]|undone ID|on ID|off ID|remove ID|learn suggest|auto
                          the user's routines (the shell runs them on their cue)
  kiroshi scan REQUEST.json
                          the Kiroshi scan (Mod+K): a brief of the screen, as JSON lines
  kiroshi taken [JSON]    the offers the user took from it (with JSON: one more)
  memory learn [--claude PATH] [--model M] [--delete] [EPISODE.json]
                          the memory pass on an agent's task (servers start it
                          in the background), the fading, the weekly tidy-up
                          when due; memory tidy: the tidy-up now
  personal [show]         what agents remember about you (JSON); personal prompt
                          [QUERY]: the part sent when an agent connects
  personal context [--exclude ID,…] MESSAGE  the entries a message is about
                          (JSON: text, ids), for the shell's AI chat
  personal learn [--claude PATH] [--model M] [--delete] [FILE | -]
                          the memory pass: a small model (default haiku) reads a
                          conversation and saves what is worth keeping (JSON:
                          saved, recalled, forgot, faded, tidied, skipped); then
                          forgets what faded and, weekly, tidies the memory up;
                          --delete removes FILE once read
  personal tidy [--claude PATH] [--model M]  the tidy-up now: merges entries on
                          the same subject, drops what no longer holds
  personal forget ID | clear
  habits [status]         usage habits learned on this machine (JSON), when
                          on: app ids and times only
  habits watch            the recorder (the nixbook-habits user service)
  habits now | report [DAYS] | day [YYYY-MM-DD]  what they say, as text
  habits music            the music taste learned from every player (MPRIS)
  habits music-clear      forget the music listened to (the rest stays)
  habits on | off [--forget]  turn them on or off (Settings > Memory;
                          not off when on in Nix): starts / stops nixbook-habits
  habits pause | resume | toggle | clear | show (JSON)
  habits alias WORD DESKTOP_ID  the launcher: a word that led to an app
  config                  the effective configuration
"""


def main(argv):
    cfg = load_config()
    cmd = argv[0] if argv else "serve"
    if cmd in ("-h", "--help", "help"):
        print(USAGE, end="")
        return 0
    if cmd == "serve":
        if "--http" in argv:
            port = int(cfg["http"].get("port", 7823))
            if "--port" in argv:
                port = int(argv[argv.index("--port") + 1])
            serve_http(cfg, port)
        else:
            serve_stdio(cfg)
        return 0
    if cmd == "helper":
        return serve_helper()
    if cmd == "tools":
        print(json.dumps(offered_tools(cfg), indent=1))
        return 0
    if cmd == "call":
        if len(argv) < 2:
            print(USAGE, end="", file=sys.stderr)
            return 2
        try:
            args = json.loads(argv[2]) if len(argv) > 2 else {}
        except ValueError:
            print("the arguments must be a JSON object", file=sys.stderr)
            return 2
        client = os.environ.get("NIXBOOK_DESKTOP_MCP_CLIENT", "command line")
        # The shell's AI chat shows its own approval card: no notification.
        ctx = Context(cfg, "cli", client, notify=False)
        try:
            content, is_error = call_tool(ctx, argv[1], args)
        except KeyError:
            print(f"unknown or disabled tool: {argv[1]}", file=sys.stderr)
            return 2
        print("\n".join(c["text"] for c in content if c.get("type") == "text"))
        return 1 if is_error else 0
    if cmd == "toggle":
        cmd = "resume" if is_paused() else "pause"
    if cmd == "pause":
        try:
            os.unlink(allowed_flag())
        except FileNotFoundError:
            pass
        write_state()
        notify(["-a", "Desktop agent", "--", "Desktop control paused"])
        print("desktop control paused")
        return 0
    if cmd == "resume":
        os.makedirs(os.path.dirname(allowed_flag()), mode=0o700, exist_ok=True)
        fd = os.open(allowed_flag(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write("allowed\n")
        write_state()
        print("desktop control allowed")
        return 0
    if cmd == "status":
        print(json.dumps({"paused": is_paused(), "notify": notify_enabled(), "last": read_state().get("last"), "config": config_path(),
                          "audit_log": audit_path(), "enabled_groups": cfg["tools"]}, indent=1))
        return 0
    if cmd == "notify":
        want = argv[1] if len(argv) > 1 else "status"
        if want == "toggle":
            want = "off" if notify_enabled() else "on"
        if want == "off":
            os.makedirs(os.path.dirname(quiet_flag()), mode=0o700, exist_ok=True)
            with open(quiet_flag(), "w", encoding="utf-8") as f:
                f.write("quiet\n")
        elif want == "on":
            try:
                os.unlink(quiet_flag())
            except FileNotFoundError:
                pass
        elif want != "status":
            print(USAGE, end="", file=sys.stderr)
            return 2
        print("notification " + ("on" if notify_enabled() else "off"))
        return 0
    if cmd == "find":
        return find_command(cfg, argv[1:])
    if cmd == "project":
        return project_command(cfg, argv[1:])
    if cmd == "layout":
        return layout_command(cfg, argv[1:])
    if cmd == "memory":
        return memory_command(cfg, argv[1:])
    if cmd == "trust":
        return trust_command(argv[1:])
    if cmd == "initiative":
        return initiative_command(cfg, argv[1:])
    if cmd == "watch":
        return watch_command(cfg, argv[1:])
    if cmd == "extract" and len(argv) == 2:
        try:
            print(extract_archive(argv[1]))
        except ToolError as e:
            print(e, file=sys.stderr)
            return 1
        return 0
    if cmd == "context":
        # What a question asked in the bubble takes along: the shell's
        # recent events, filtered ({now, events}).
        try:
            data = json.loads(argv[1] if len(argv) > 1 and argv[1] != "-" else sys.stdin.read())
        except ValueError:
            data = None
        if not isinstance(data, dict) or not isinstance(data.get("events"), list):
            print("context: {\"now\": T, \"events\": [...]}", file=sys.stderr)
            return 2
        print(context_text(cfg, data["events"][:60], data.get("now") if isinstance(data.get("now"), (int, float)) else None))
        return 0
    if cmd == "privacy":
        sub = argv[1] if len(argv) > 1 else ""
        if sub == "hook":
            return privacy_hook()
        if sub in ("mask", "unmask"):
            data = sys.stdin.read()
            # --typed: what the user typed (lowercase first names too).
            sys.stdout.write(mask_text(data, typed="--typed" in argv) if sub == "mask" else unmask_text(data))
            return 0
        if sub == "show":
            print(json.dumps(privacy_tokens(), ensure_ascii=False))
            return 0
        if sub == "learned":
            learned = (read_json(privacy_learned_path()) or {}).get("learned") or {}
            print(json.dumps(sorted(({"key": k, **e} for k, e in learned.items()), key=lambda e: -e.get("since", 0)),
                             ensure_ascii=False))
            return 0
        if sub == "unlearn" and len(argv) == 3:
            return 0 if privacy_unlearn(argv[2]) else 1
        if sub == "clear":
            # The numbers go on: a placeholder in an old chat never
            # becomes someone else.
            with PrivacyMap() as m:
                m.data.update(tokens={}, keys={}, people={})
                m.changed = True
            return 0
        print(USAGE, end="", file=sys.stderr)
        return 2
    if cmd == "sent":
        sub = argv[1] if len(argv) > 1 else "show"
        if sub == "show":
            print(json.dumps(list(reversed(sent_read())), ensure_ascii=False))
            return 0
        if sub == "note" and len(argv) == 4:
            sent_note(clean_text(argv[2], 40), "claude (chat)", argv[3])
            return 0
        if sub == "clear":
            with contextlib.suppress(FileNotFoundError):
                os.remove(sent_path())
            return 0
        print(USAGE, end="", file=sys.stderr)
        return 2
    if cmd == "routine":
        return routine_command(cfg, argv[1:])
    if cmd == "kiroshi":
        return kiroshi_command(cfg, argv[1:])
    if cmd == "personal":
        return personal_command(cfg, argv[1:])
    if cmd == "habits":
        return habits_command(cfg, argv[1:])
    if cmd == "token":
        print(ensure_token())
        return 0
    if cmd == "config":
        print(json.dumps(cfg, indent=1))
        return 0
    print(USAGE, end="", file=sys.stderr)
    return 2


def notify(argv, env=None):
    """A notification (notify-send ARGV), if it can be sent: a missing or
    hung notification daemon never blocks or fails the caller."""
    if not shutil.which("notify-send"):
        return
    try:
        subprocess.run(["notify-send", *argv], capture_output=True, timeout=10, env=env)
    except (OSError, subprocess.TimeoutExpired):
        pass


def memory_command(cfg, argv):
    """The desktop memory for the user (Settings > Memory)."""
    sub = argv[0] if argv else "show"
    if sub == "show":
        print(json.dumps(read_memory(), ensure_ascii=False))
        return 0
    if sub == "prompt":
        print(memory_digest(cfg, " ".join(argv[1:])))
        return 0
    if sub == "forget" and len(argv) > 1:
        return 0 if call_forget(argv[1]) else 1
    if sub == "fire" and len(argv) > 1:
        return 0 if fire_trigger(argv[1]) else 1
    if sub in ("learn", "tidy"):
        return memory_learn_command(cfg, sub, argv[1:])
    if sub == "clear":
        parts = argv[1:] or ["all"]
        every = ["notes", "usage", "aliases", "targets", "triggers", "archive", "routines"]
        if not all(p in every + ["all"] for p in parts):
            print(USAGE, end="", file=sys.stderr)
            return 2
        keys = every if "all" in parts else parts
        if "notes" in keys and "archive" not in keys:
            keys.append("archive")
        with Memory() as m:
            fresh = empty_memory()
            for key in keys:
                m.data[key] = fresh[key]
            m.data.pop("lastFailedLaunch", None)
            if "routines" in keys:  # what learning routines knew goes with them
                m.data.pop("routinesDeclined", None)
                m.data.pop("routineLearnDay", None)
            m.save()
        print(f"cleared {', '.join(keys)}")
        return 0
    print(USAGE, end="", file=sys.stderr)
    return 2


def personal_command(cfg, argv):
    """The personal memory for the user (Settings > Memory > About
    you) and the shell's AI chat (`context`)."""
    sub = argv[0] if argv else "show"
    if sub == "show":
        print(json.dumps(read_personal(), ensure_ascii=False))
        return 0
    if sub == "prompt":
        print(personal_digest(cfg, " ".join(argv[1:])))
        return 0
    if sub == "context":
        rest = argv[1:]
        exclude = []
        if len(rest) > 1 and rest[0] == "--exclude":
            exclude = [i for i in rest[1].split(",") if i]
            rest = rest[2:]
        query = " ".join(rest)[:2000]
        found, ids = personal_context(cfg, query, [i for i in exclude if not i.startswith("m:")])
        # And this machine's reference, when it is a question about it.
        machine, mids = machine_context(query, [i for i in exclude if i.startswith("m:")])
        found = "\n\n".join(t for t in (found, machine) if t)
        print(json.dumps({"text": found, "ids": ids + mids}, ensure_ascii=False))
        return 0
    if sub in ("learn", "tidy"):
        rest = argv[1:]
        opts = {"--claude": claude_path(cfg) or "claude", "--model": "haiku"}
        delete = "--delete" in rest
        rest = [a for a in rest if a != "--delete"]
        while len(rest) > 1 and rest[0] in opts:
            opts[rest[0]], rest = rest[1], rest[2:]
        if len(rest) > 1 or (rest and rest[0].startswith("--")):
            print(USAGE, end="", file=sys.stderr)
            return 2
        if sub == "tidy":
            transcript = ""
        elif not rest or rest[0] == "-":
            transcript = sys.stdin.read()
        else:
            with open(rest[0], encoding="utf-8", errors="replace") as f:
                transcript = f.read()
            if delete:
                os.unlink(rest[0])
        if "personal" not in cfg["tools"]:
            print(json.dumps({"saved": [], "forgot": [], "skipped": ["the personal tool group is off"]}))
            return 0
        done = learn_from(cfg, transcript, opts["--claude"], opts["--model"], tidy=True if sub == "tidy" else None)
        print(json.dumps(done, ensure_ascii=False))
        return 0
    if sub == "forget" and len(argv) > 1:
        try:
            t_forget_about_user(Context(cfg, "cli", "you", notify=False), {"id": argv[1]})
        except ToolError as e:
            log(str(e))
            return 1
        print(f"forgot {argv[1]}")
        return 0
    if sub == "clear" and len(argv) == 1:
        with PersonalMemory() as m:
            gone, m.data["entries"] = m.data["entries"], []
            m.save()
        for e in gone:
            unsync_person_contact(cfg, e, [])
        print("cleared")
        return 0
    print(USAGE, end="", file=sys.stderr)
    return 2


def call_forget(note_id):
    try:
        t_forget(Context(load_config(), "cli", "you", notify=False), {"id": note_id})
    except ToolError as e:
        log(str(e))
        return False
    print(f"forgot {note_id}")
    return True


def layout_command(cfg, argv):
    """Window layouts for the user (the shell's menus, key bindings): the
    same code as the agents' tools, without the pause and the tool groups."""
    close_others = "--close-others" in argv
    argv = [a for a in argv if a != "--close-others"]
    sub = argv[0] if argv else "list"
    ctx = Context(cfg, "cli", "you", notify=False)

    def name_arg(i):
        if len(argv) <= i or not re.fullmatch(LAYOUT_NAME, argv[i]):
            raise ToolError("a layout name: letters, digits, '.', '-' and '_', at most 64")
        return argv[i]

    def path_of(name):
        return os.path.join(layouts_dir(), f"{name}.json")

    if sub == "list":
        print(json.dumps({"current": current_layout(), "layouts": layouts_index()}, ensure_ascii=False))
        return 0
    if sub == "cycle":
        names = [l["name"] for l in layouts_index()]
        if not names:
            raise ToolError("no saved layout")
        cur = current_layout()
        sub, argv = "restore", ["restore", names[(names.index(cur) + 1) % len(names)] if cur in names else names[0]]
    if sub in ("save", "restore"):
        name = name_arg(1)
        args = {"name": name}
        try:
            if sub == "save":
                out = t_save_layout(ctx, args)
            else:
                if close_others:
                    args["close_others"] = True
                out = t_restore_layout(ctx, {"name": name}, close_others=close_others)
        except ToolError as e:
            audit("you", f"{sub}_layout", args, f"error: {e}")
            raise
        audit("you", f"{sub}_layout", args, "ok")
        if sub == "restore":
            habit_event(cfg, "layout", name)
        print("\n".join(c["text"] for c in out))
        notify(["-a", "Window layouts", "-i", "view-grid", "--", out[0]["text"].splitlines()[0].capitalize()])
        return 0
    if sub == "delete":
        name = name_arg(1)
        try:
            os.unlink(path_of(name))
        except FileNotFoundError:
            raise ToolError(f"no saved layout {name!r}")
        if current_layout() == name:
            set_current_layout("")
        print(f"deleted layout {name!r}")
        return 0
    if sub == "rename":
        old, new = name_arg(1), name_arg(2)
        if not os.path.exists(path_of(old)):
            raise ToolError(f"no saved layout {old!r}")
        if os.path.exists(path_of(new)):
            raise ToolError(f"a layout {new!r} exists already")
        with open(path_of(old), encoding="utf-8") as f:
            doc = json.load(f)
        doc["name"] = new
        fd = os.open(path_of(new), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=1, ensure_ascii=False)
        os.unlink(path_of(old))
        if current_layout() == old:
            set_current_layout(new)
        print(f"renamed layout {old!r} to {new!r}")
        return 0
    print(USAGE, end="", file=sys.stderr)
    return 2


PROJECT_BEFORE_LAYOUT = "_before-undo"


def project_keep_before(ctx):
    """The windows as they are, saved as the hidden layout _before-undo
    before a project opens (`layout restore _before-undo` puts them back);
    the user's current layout left as it was."""
    current = current_layout()
    t_save_layout(ctx, {"name": PROJECT_BEFORE_LAYOUT})
    if current:
        set_current_layout(current)
    else:
        with contextlib.suppress(OSError):
            os.unlink(current_layout_path())


def project_command(cfg, argv):
    """Projects for the user (the shell's launcher, menus, Settings, the
    bubble's "work on X"): the agents' code, without the pause and the tool
    groups. Opening one first keeps the windows as they were (the hidden
    layout _before-undo: `layout restore _before-undo` is its Undo)."""
    sub = argv[0] if argv else "list"
    ctx = Context(cfg, "cli", "you", notify=False)

    def name_arg(i):
        if len(argv) <= i:
            raise ToolError("a project name")
        name = project_name_of(argv[i])
        project_path(name)
        return name

    def done(out):
        print("\n".join(c["text"] for c in out))
        first = out[0]["text"].split(": ", 1)
        notify(["-a", "Projects", "-i", "folder-open", "--", first[0].capitalize(), first[1] if len(first) > 1 else ""])
        return 0

    if sub == "list":
        print(json.dumps({"current": current_project(), "projects": projects_index()}, ensure_ascii=False))
        return 0
    if sub == "show":
        print(json.dumps(read_project(name_arg(1)), ensure_ascii=False))
        return 0
    if sub == "open":
        name = name_arg(1)
        read_project(name)
        with contextlib.suppress(ToolError, OSError):
            project_keep_before(ctx)
        try:
            out = project_open_now(ctx, name, user=True)
        except ToolError as e:
            audit("you", "project_open", {"name": name}, f"error: {e}")
            raise
        audit("you", "project_open", {"name": name}, "ok")
        habit_event(cfg, "layout", f"project:{name}")
        return done(out)
    if sub in ("save", "pause"):
        name = name_arg(1)
        try:
            out = project_save_now(ctx, name, {}, pause=sub == "pause" or "--pause" in argv, user=True)
        except ToolError as e:
            audit("you", f"project_{sub}", {"name": name}, f"error: {e}")
            raise
        audit("you", f"project_{sub}", {"name": name}, "ok")
        return done(out)
    if sub == "set" and len(argv) == 4:
        name, key, raw = name_arg(1), argv[2], argv[3]
        keys = {"dnd": "dnd", "focus": "focus_minutes", "on-pause": "on_pause", "onPause": "on_pause"}
        if key not in keys:
            raise ToolError("project set NAME dnd on|off|none | focus MINUTES|pomodoro|0 | on-pause keep|tabs")
        value = raw
        if key == "dnd":
            value = {"on": True, "true": True, "off": False, "false": False, "none": None, "null": None}.get(raw, "?")
        elif key == "focus" and raw != "pomodoro":
            value = int(raw) if raw.isdigit() else -1
        doc = project_settings(read_project(name), {keys[key]: value}, user=True)
        write_project(doc)
        print(json.dumps(project_summary(doc), ensure_ascii=False))
        return 0
    if sub == "delete":
        name = name_arg(1)
        try:
            os.unlink(project_path(name))
        except FileNotFoundError:
            raise ToolError(f"no project {name!r}")
        with contextlib.suppress(OSError):
            os.unlink(os.path.join(layouts_dir(), f"{PROJECT_LAYOUT_PREFIX}{name}.json"))
        if current_project() == name:
            set_current_project("")
        print(f"deleted project {name!r}")
        return 0
    if sub == "rename" and len(argv) == 3:
        old, new = name_arg(1), re.sub(r"\s+", "-", argv[2].strip())
        doc = read_project(old)
        if os.path.exists(project_path(new)):
            raise ToolError(f"a project {new!r} exists already")
        if doc.get("layout") == PROJECT_LAYOUT_PREFIX + old:
            src = os.path.join(layouts_dir(), f"{PROJECT_LAYOUT_PREFIX}{old}.json")
            with contextlib.suppress(OSError):
                os.replace(src, os.path.join(layouts_dir(), f"{PROJECT_LAYOUT_PREFIX}{new}.json"))
            doc["layout"] = PROJECT_LAYOUT_PREFIX + new
        doc["name"] = new
        write_project(doc)
        os.unlink(project_path(old))
        if current_project() == old:
            set_current_project(new)
        print(f"renamed project {old!r} to {new!r}")
        return 0
    print(USAGE, end="", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ToolError as e:
        log(str(e))
        sys.exit(1)
