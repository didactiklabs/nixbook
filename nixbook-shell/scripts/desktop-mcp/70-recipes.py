# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Recipes (the procedural memory) and run_steps.

# Besides the window and input tools, a step may open a page in Zen (a
# recipe often starts with one), never act in it.
RUN_STEPS_EXTRA = {"page_go"}
RUN_STEPS_PAGE_ACTIONS = ("open", "navigate", "activate", "search")


# Recipes, the procedural memory: steps that worked, saved by run_steps'
# remember_as with {name} placeholders for what changes, run again in one
# call by run_recipe, so the steps never pass through the model again. One
# that worked on RECIPE_MACRO_DAYS days is a macro: proven, offered in one
# line. A step that fails demotes it, and the agent fixes that step.

RECIPE_MACRO_DAYS = 3
RECIPE_VAR = r"\{([a-z][a-z0-9_]{0,20})\}"


def walk_strings(value, fn):
    if isinstance(value, str):
        return fn(value)
    if isinstance(value, list):
        return [walk_strings(v, fn) for v in value]
    if isinstance(value, dict):
        return {k: walk_strings(v, fn) for k, v in value.items()}
    return value


def recipe_vars(steps):
    found = []
    walk_strings(steps, lambda v: found.extend(re.findall(RECIPE_VAR, v)))
    return list(dict.fromkeys(found))


def recipe_values(value):
    if value is None:
        return {}
    if not isinstance(value, dict) or len(value) > 10:
        raise ToolError("vars: an object of at most 10 {name: text}")
    out = {}
    for k, v in value.items():
        if not re.fullmatch(RECIPE_VAR[2:-2], str(k)) or not isinstance(v, str) or len(v) > 4000:
            raise ToolError("vars: names are lowercase words (name, file_2), values text")
        out[k] = v
    return out


def substitute(steps, values):
    if not values:
        return steps
    return walk_strings(steps, lambda v: re.sub(RECIPE_VAR, lambda m: values.get(m[1], m[0]), v))


def parametrize(steps, values):
    """The steps with each value given back as its {name}: the recipe."""
    def back(v):
        for k, val in sorted(values.items(), key=lambda kv: -len(kv[1])):
            if len(val) >= 2:
                v = v.replace(val, "{" + k + "}")
        return v
    return walk_strings(steps, back)


def recipe_gist(steps):
    """A recipe's steps in a line: \"3 steps: ctrl+k → type {name} → Return\"."""
    def one(step):
        if not isinstance(step, dict):
            return "?"
        name, a = step.get("tool"), step.get("args") or {}
        if name == "press_keys":
            return " ".join(a.get("keys") or []) if isinstance(a.get("keys"), list) else "keys"
        if name == "type_text":
            return "type " + short(str(a.get("text", "")), 30)
        if name == "ui_act":
            return f"ui_act {short(str(a.get('target', '')), 30)}"
        if name == "launch_app":
            return f"launch {a.get('app', '')}"
        if name == "focus_app":
            return f"focus {a.get('app', '')}"
        if name == "page_go":
            return f"open {short(str(a.get('url') or a.get('query') or ''), 40)}"
        if name == "restore_layout":
            return f"layout {a.get('name', '')}"
        return name or "?"
    return short(f"{len(steps)} steps: " + " → ".join(one(s) for s in steps), NOTE_TEXT_MAX)


def is_macro(n):
    return len(set(n.get("runs") or [])) >= RECIPE_MACRO_DAYS and not n.get("failStep")


def record_recipe(note_id, ok, error=""):
    """A recipe ran: what it proved (a day it worked; a step that failed)."""
    now = int(time.time())
    try:
        with Memory() as m:
            n = next((n for n in m.data["notes"] if n["id"] == note_id), None)
            if not n:
                return
            if ok:
                n["ok"] = n.get("ok", 0) + 1
                add_trace(n, now)
                today = datetime.date.today().isoformat()
                runs = [d for d in n.get("runs") or [] if d != today]
                n["runs"] = runs[-4:] + [today]
                n.pop("failStep", None)
                n.pop("tentative", None)
            else:
                n["fail"] = n.get("fail", 0) + 1
                n["runs"] = []
                failed = re.search(r"^(\d+)\. \S+ failed: (.*)$", error, re.M)
                n["failStep"] = {"step": int(failed[1]) if failed else 0,
                                 "error": short(failed[2] if failed else error, 200), "time": now}
            m.save()
    except (OSError, ValueError, KeyError, TypeError):
        pass


@tool(
    "run_recipe",
    "input",
    "Run a recipe from the memory (its id; the notes show them as "
    "run_recipe {id, vars}) in one call, giving its {name} placeholders' "
    "values in `vars`. Stops at the first step that fails, like run_steps.",
    obj(
        {
            "id": {"type": "string", "description": "The recipe's id (or its topic)"},
            "vars": {"type": "object", "description": "Values for its placeholders, e.g. {\"name\": \"Lan\"}"},
        },
        ["id"],
    ),
)
def t_run_recipe(ctx, args):
    want = as_str(args, "id", max_len=NOTE_TOPIC_MAX)
    notes = [n for n in read_memory()["notes"] if n.get("kind") == "recipe" and n.get("steps")]
    n = next((n for n in notes if n["id"] == want), None) or next(
        (n for n in notes if n["topic"].lower() == want.lower()), None)
    if not n:
        raise ToolError(f"no recipe {want!r}: recall lists the notes, recipes among them")
    values = recipe_values(args.get("vars"))
    missing = [v for v in n.get("vars") or [] if v not in values]
    if missing:
        raise ToolError(f"vars: give {', '.join(missing)} (recipe {n['id']}: {n['text']})")
    ctx.notes_shown.add(n["id"])
    ctx.episode["judged"].add(n["id"])
    try:
        out = t_run_steps(ctx, {"steps": substitute(n["steps"], values)})
    except ToolError as e:
        record_recipe(n["id"], False, str(e))
        raise ToolError(f"{e}\nRecipe {n['id']} ({n['topic']}) failed there: do that step another way, "
                        f"then save the steps that work (run_steps with remember_as {n['topic']!r} replaces it).")
    record_recipe(n["id"], True)
    return out


# -- the shell ---------------------------------------------------------------

IPC_NAME = r"[A-Za-z][A-Za-z0-9_]{0,63}"


def qs_ipc(*args):
    """The user's shell (its IPC)."""
    qs = os.environ.get("NIXBOOK_DESKTOP_MCP_QS")
    conf = os.environ.get("NIXBOOK_DESKTOP_MCP_QS_CONFIG")
    if qs and conf:
        return run([qs, "-c", conf, "ipc", *args])
    return run(["nixbook-shell", "ipc", *args])


@tool(
    "shell_ipc_list",
    "shell",
    "List what the desktop shell (bar, sidebars, launcher, lock screen, …) "
    "can be asked to do: its IPC targets and their functions.",
    read_only=True,
)
def t_shell_ipc_list(ctx, args):
    out = qs_ipc("show").stdout
    deny = set(ctx.cfg.get("shellIpcDenyTargets", []))
    blocks, keep = [], True
    for line in out.splitlines():
        m = re.match(r"\s*target\s+(\S+)", line)
        if m:
            keep = m.group(1) not in deny
        if keep:
            blocks.append(line)
    return [text("\n".join(blocks) or out)]


@tool(
    "shell_ipc",
    "shell",
    "Call a desktop shell IPC function (see shell_ipc_list), e.g. target "
    "sidebarRight, function toggle.",
    obj(
        {
            "target": {"type": "string"},
            "function": {"type": "string"},
            "args": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
        },
        ["target", "function"],
    ),
)
def t_shell_ipc(ctx, args):
    target = as_str(args, "target", max_len=64, pattern=IPC_NAME)
    fn = as_str(args, "function", max_len=64, pattern=IPC_NAME)
    if target in ctx.cfg.get("shellIpcDenyTargets", []):
        raise ToolError(f"refused: the {target!r} target is off limits")
    if target == "notes" and fn in NOTES_FILE_FUNCTIONS:
        raise ToolError("refused: use the widget tool for notes")
    extra = args.get("args") or []
    if not isinstance(extra, list) or len(extra) > 8 or not all(isinstance(a, str) and len(a) <= 256 for a in extra):
        raise ToolError("`args` must be up to 8 strings of at most 256 characters")
    instead = IPC_IMAGE_PATH_FUNCTIONS.get((target, fn))
    if instead and (fn != "set" or (len(extra) > 1 and extra[1] == "path")):
        raise ToolError(f"refused: use the {instead} tool for a picture (it must be in a folder the user shares with agents)")
    ctx.guard.check_rate()
    out = qs_ipc("call", "--", target, fn, *extra).stdout.strip()
    return [text(out or f"called {target}.{fn}")]


def theme_registry():
    out = qs_ipc("call", "--", "theme", "list").stdout.strip()
    try:
        reg = json.loads(out)
        if isinstance(reg, dict) and isinstance(reg.get("themes"), list):
            return reg
    except ValueError:
        pass
    raise ToolError("the desktop shell didn't list its themes (is nixbook-shell running?)")


def _named(items, want):
    """The item whose id or name is `want` (accents and case ignored), else
    the only one whose name contains it."""
    w = fold(want).strip()
    exact = [i for i in items if fold(i["id"]) == w or fold(i.get("name", "")) == w]
    if exact:
        return exact[0]
    partial = [i for i in items if w and (w in fold(i.get("name", "")) or w in fold(i["id"]))]
    return partial[0] if len(partial) == 1 else None


@tool(
    "list_themes",
    "shell",
    "The desktop shell's themes (its whole look: colours, shapes, fonts, "
    "sounds, wallpapers) and each one's variants, the current ones, and "
    "which are locked by the Nix configuration.",
    read_only=True,
)
def t_list_themes(ctx, args):
    return [text(theme_registry())]


@tool(
    "set_theme",
    "shell",
    "Switch the desktop shell's theme and/or variant, by id or name: e.g. "
    "theme \"persona\" with variant \"Persona 3 Reload\" (or \"p3r\"), or a "
    "variant alone (\"momonga\") to switch to it within its theme. The "
    "palette and wallpapers follow. See list_themes.",
    obj({
        "theme": {"type": "string", "description": "A theme id or name (Material, Persona, Chiikawa…)"},
        "variant": {"type": "string", "description": "A variant id or name of that theme"},
    }),
)
def t_set_theme(ctx, args):
    want_theme = as_str(args, "theme", required=False, max_len=64)
    want_variant = as_str(args, "variant", required=False, max_len=64)
    if not want_theme and not want_variant:
        raise ToolError("give a `theme`, a `variant`, or both (see list_themes)")
    reg = theme_registry()
    themes = reg["themes"]
    if want_theme:
        theme = _named(themes, want_theme)
        if not theme:
            raise ToolError(f"no theme {want_theme!r}: {', '.join(t['id'] for t in themes)}")
    else:
        # A variant alone: in the current theme first, else the theme that has it.
        current = next(t for t in themes if t["id"] == reg["current"])
        found = [t for t in [current] + [t for t in themes if t is not current]
                 if _named(t.get("variants", []), want_variant)]
        if not found:
            raise ToolError(f"no variant {want_variant!r} in any theme (see list_themes)")
        theme = found[0]
    variant = ""
    if want_variant:
        v = _named(theme.get("variants", []), want_variant)
        if not v:
            names = ", ".join(x["id"] for x in theme.get("variants", [])) or "none"
            raise ToolError(f"{theme['name']} has no variant {want_variant!r} (variants: {names})")
        variant = v["id"]
    ctx.guard.check_rate()
    out = qs_ipc("call", "--", "theme", "set", theme["id"], variant).stdout.strip()
    if not out.startswith("ok"):
        raise ToolError(out or "the shell didn't answer")
    return [text(f"theme set: {out[3:].strip()}")]


@tool(
    "report_problem",
    "shell",
    "File something broken or rough in nixbook itself (this desktop shell, its "
    "widgets and settings, these desktop tools, its configuration) for its fixer "
    "(nixbook-improve), which makes small fixes as pull requests the user merges. "
    "Use it when the user says something of nixbook doesn't work, looks wrong or "
    "is annoying (\"report this\", \"that's broken\"), or a desktop tool failed in a "
    "way that looks like a bug rather than a refusal. Only for a fix (at most a few "
    "files): something nixbook should do and doesn't, a new widget, setting or "
    "behaviour, or a change of how a thing works is a feature, filed with "
    "request_feature instead; the fixer moves one it finds too big to the feature "
    "requests itself. Not for other apps' bugs. Say what happens and what was "
    "expected, plainly; it stays on this computer. Only while the user has turned "
    "it on (Settings > Desktop agents > Fixes it makes itself). fix_now starts "
    "fixing it at once, as Settings' Fix now (in line after the one being made, if "
    "any): only when the user asked for that in "
    "this conversation (\"fix it now\"), never on your own.",
    obj({
        "what": {"type": "string", "description": "What is wrong: what happens, what was expected"},
        "where": {"type": "string", "description": "The widget, setting, tool or file, when known"},
        "fix_now": {"type": "boolean", "description": "Start fixing it at once (the user asked; default false)"},
    }, ["what"]),
)
def t_report_problem(ctx, args):
    what = as_str(args, "what", max_len=1000)
    where = as_str(args, "where", required=False, max_len=200) or ""
    if not shell_setting("ai.improve.enable", False):
        raise ToolError("the fixer is off: the user turns it on in Settings > Desktop agents > "
                        "Fixes it makes itself. Tell them, don't retry.")
    ctx.guard.check_rate()
    out = improve_file("note", what, where)
    again = f" (reported {out['count']} times now)" if out.get("count", 1) > 1 else ""
    now = f" {improve_now(ctx, out)}" if args.get("fix_now") is True else ""
    return [text(f"filed for the fixer{again}: it makes a fix as a pull request when it can, and the "
                 "user gets Merge, Look, Drop once its checks pass. One too big for a fix becomes a "
                 f"feature request.{now}")]


@tool(
    "request_feature",
    "shell",
    "Ask for a feature in nixbook itself (this desktop shell, its widgets and "
    "settings, these desktop tools, its configuration): something it doesn't do "
    "yet, a new widget, setting, shortcut or behaviour. Its builder "
    "(nixbook-improve) makes it as a pull request the user reviews and merges "
    "(never merged on its own). Use it when the user wants nixbook to do "
    "something new (\"I wish the bar showed…\", \"add a way to…\"), or asks for a "
    "change too big for a fix. A bug or a rough edge is report_problem's. Say "
    "what it should do, for whom and where it fits, plainly; it stays on this "
    "computer. Only while the user has turned it on (Settings > Desktop agents > "
    "Features it builds). build_now starts building it at once, as Settings' Build "
    "now (in line after the one being made, if any): only when the user asked for that in this conversation (\"build it now\"), "
    "never on your own.",
    obj({
        "what": {"type": "string", "description": "The feature: what it should do, how one would use it"},
        "where": {"type": "string", "description": "The widget, setting, tool or file it belongs to, when known"},
        "build_now": {"type": "boolean", "description": "Start building it at once (the user asked; default false)"},
    }, ["what"]),
)
def t_request_feature(ctx, args):
    what = as_str(args, "what", max_len=1500)
    where = as_str(args, "where", required=False, max_len=200) or ""
    if not shell_setting("ai.improve.features.enable", False):
        raise ToolError("building features is off: the user turns it on in Settings > Desktop agents > "
                        "Features it builds. Tell them, don't retry.")
    ctx.guard.check_rate()
    out = improve_file("request", what, where)
    again = f" (asked {out['count']} times now)" if out.get("count", 1) > 1 else ""
    now = f" {improve_now(ctx, out)}" if args.get("build_now") is True else ""
    return [text(f"filed as a feature request{again}: it is built as a pull request when it can (one a day "
                 "on its own, or at once from Settings), and the user gets Merge, Look, Drop once its checks "
                 f"pass; it is never merged on its own.{now}")]
