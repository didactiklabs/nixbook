"""Project contexts and teach mode (scripts/desktop-mcp.py), against a fake
niri, Zen bridge, shell and model: run by projects.sh, with private
XDG directories in the environment. Prints "ok - …" / "FAIL - …" lines;
exit status 1 when anything failed."""
import contextlib
import importlib.util
import io
import json
import os
import stat
import sys
import time

spec = importlib.util.spec_from_file_location("dm", sys.argv[1])
dm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dm)

failures = 0


def check(name, got, want):
    global failures
    if got == want:
        print(f"ok   - {name}")
    else:
        failures += 1
        print(f"FAIL - {name}\n       expected: {want!r}\n       actual:   {got!r}")


def check_true(name, cond, detail=""):
    check(name + (f" ({detail})" if detail and not cond else ""), bool(cond), True)


HOME = os.environ["HOME"]
PROJ = os.path.join(HOME, "code", "hackathon")
OTHER = os.path.join(HOME, "code", "other")
for d in (PROJ, OTHER, os.path.join(HOME, ".ssh")):
    os.makedirs(d, exist_ok=True)

# -- the fakes -----------------------------------------------------------------
calls = []
state = {
    "windows": [
        {"id": 1, "app_id": "zen", "title": "Devpost - Zen", "workspace_id": 10, "is_focused": True,
         "is_floating": False, "layout": {"window_size": [1500, 1900], "pos_in_scrolling_layout": [1, 1]}},
        {"id": 2, "app_id": "kitty", "title": "~/code/hackathon", "workspace_id": 10, "is_focused": False,
         "is_floating": False, "pid": 500, "layout": {"window_size": [1500, 1900], "pos_in_scrolling_layout": [2, 1]}},
    ],
    "tabs": [
        {"id": 11, "window": 1, "active": True, "title": "Devpost", "url": "https://devpost.com/hack"},
        {"id": 12, "window": 1, "title": "Repo", "url": "https://github.com/me/hack"},
        {"id": 13, "window": 1, "pinned": True, "title": "Mail", "url": "https://mail.example.com"},
        {"id": 14, "window": 1, "private": "a site the agents may not use"},
        {"id": 15, "window": 1, "otherWorkspace": True, "title": "News", "url": "https://news.example.com"},
        {"id": 21, "window": 2, "title": "Other", "url": "https://other.example.com"},
    ],
    "dnd": False,
    "zen_up": True,
}
os.makedirs(os.path.join(PROJ, "web"), exist_ok=True)


def niri_json(*what, env=None):
    w = what[0]
    if w == "windows":
        return json.loads(json.dumps(state["windows"]))
    if w == "workspaces":
        return [{"id": 10, "idx": 1, "name": None, "output": "eDP-1", "is_active": True, "is_focused": True,
                 "active_window_id": 1},
                {"id": 12, "idx": 2, "name": None, "output": "eDP-1", "is_active": False, "active_window_id": None}]
    if w == "outputs":
        return {"eDP-1": {"name": "eDP-1", "logical": {"x": 0, "y": 0, "width": 3136, "height": 1960, "scale": 1}}}
    if w == "focused-output":
        return {"name": "eDP-1"}
    return {}


def niri_action(*args):
    calls.append(("niri", *args))
    if args[0] == "focus-window":
        for w in state["windows"]:
            w["is_focused"] = str(w["id"]) == args[2]


def zen(ctx, cmd, **kw):
    calls.append(("zen", cmd, json.dumps(kw, sort_keys=True)))
    if not state["zen_up"]:
        raise dm.ToolError("Zen isn't running")
    if cmd == "ping":
        return {"ok": True}
    if cmd == "tabs":
        return json.loads(json.dumps(state["tabs"]))
    if cmd == "open":
        tid = 30 + len(state["tabs"])
        state["tabs"].append({"id": tid, "window": 1, "title": "", "url": kw["url"]})
        return {"id": tid, "url": kw["url"]}
    if cmd == "tab" and kw.get("action") == "close":
        state["tabs"] = [t for t in state["tabs"] if t["id"] != kw["tab"]]
        return {"closed": kw["tab"]}
    return {}


class Proc:
    def __init__(self, stdout=""):
        self.stdout, self.stderr, self.returncode = stdout, "", 0


def qs_ipc(*args):
    calls.append(("qs", *args))
    if args[-1] == "status":
        return Proc(json.dumps({"pomodoro": {"running": False}}))
    return Proc("ok")


def shell_dnd(state_):
    calls.append(("dnd", state_))
    if state_ in ("on", "off"):
        state["dnd"] = state_ == "on"
    return state["dnd"]


APPS = {"zen": {"Name": "Zen Browser", "Exec": "zen %u"}, "kitty": {"Name": "kitty", "Exec": "kitty"},
        "org.gnome.Calculator": {"Name": "Calculator", "Exec": "gnome-calculator"}}

dm.niri_json = niri_json
dm.niri_action = niri_action
dm.zen = zen
dm.qs_ipc = qs_ipc
dm.shell_dnd = shell_dnd
dm.applications = lambda: dict(APPS)
dm.widget_call = lambda *a: "ok"
dm.notify = lambda *a, **k: None

cfg = dm.load_config()
ctx = dm.Context(cfg, "cli", "test", notify=False)


def reset():
    calls.clear()


def text_of(out):
    return "\n".join(c["text"] for c in out if c.get("type") == "text")


# -- projects --------------------------------------------------------------------
out = text_of(dm.project_save_now(ctx, "hackathon", {"dnd": True, "focus_minutes": 25, "on_pause": "tabs"}))
check_true("save: says what it kept", "saved project 'hackathon': 2 apps, 2 tabs" in out, out)
path = dm.project_path("hackathon")
check("save: the file is 0600", stat.S_IMODE(os.stat(path).st_mode), 0o600)
doc = dm.read_project("hackathon")
check("save: its own hidden layout", doc["layout"], "_project-hackathon")
check_true("save: the layout file", os.path.exists(os.path.join(dm.layouts_dir(), "_project-hackathon.json")))
check("save: the hidden layout isn't among the user's", [l["name"] for l in dm.layouts_index()], [])
check("save: the tabs of the project's window, not pinned, private or another workspace's",
      [t["url"] for t in doc["tabs"]], ["https://devpost.com/hack", "https://github.com/me/hack"])
check("save: its options", (doc["dnd"], doc["focus"], doc["onPause"]),
      (True, {"kind": "countdown", "minutes": 25}, "tabs"))
check("save: a new project saved from the desktop is the one open", (doc["state"], dm.current_project()),
      ("open", "hackathon"))
check("save: its apps", doc["apps"], ["kitty", "zen"])

try:
    dm.project_settings({"name": "x"}, {"on_pause": "close"})
    check("on_pause: keep or tabs only", "no error", "ToolError")
except dm.ToolError as e:
    check_true("on_pause: keep or tabs only", "keep, tabs" in str(e), str(e))
for bad in ("../x", "_hidden", "", "a" * 49):
    try:
        dm.project_path(bad)
        check(f"name {bad!r} refused", "accepted", "refused")
    except dm.ToolError:
        check(f"name {bad!r} refused", "refused", "refused")
check("a name as said finds the project", dm.project_name_of("Hackathon"), "hackathon")
check("a new name with spaces", dm.project_name_of("side project"), "side-project")

# Pause: saved, its tabs closed (its rule), DND and the timer as they were.
state["dnd"] = False
doc["started"] = {"dnd": False, "focus": "countdown"}
dm.write_project(doc)
reset()
out = text_of(dm.project_pause_now(ctx, "hackathon"))
check_true("pause: its tabs closed", "2 tabs closed" in out, out)
check("pause: the project window's tabs only", sorted(c[2] for c in calls if c[:2] == ("zen", "tab")),
      ['{"action": "close", "tab": 11}', '{"action": "close", "tab": 12}'])
check_true("pause: DND back off", ("dnd", "off") in calls)
check_true("pause: the timer stopped", ("qs", "call", "timers", "countdownReset") in calls)
doc = dm.read_project("hackathon")
check("pause: paused, not current", (doc["state"], dm.current_project(), "started" in doc), ("paused", "", False))
check("pause: the tabs kept in the project", len(doc["tabs"]), 2)

# Open: the layout, the tabs not open, DND, timer.
reset()
out = text_of(dm.project_open_now(ctx, "hackathon"))
check("open: the tabs that aren't open, in the background",
      sorted(json.loads(c[2])["url"] for c in calls if c[:2] == ("zen", "open")),
      ["https://devpost.com/hack", "https://github.com/me/hack"])
check_true("open: never active", all(not json.loads(c[2])["active"] for c in calls if c[:2] == ("zen", "open")))
check_true("open: the layout restored", "restored layout '_project-hackathon'" in out, out)
check_true("open: DND on", ("dnd", "on") in calls and state["dnd"])
check_true("open: its focus timer", ("qs", "call", "timers", "countdownAdd", "25") in calls, calls)
doc = dm.read_project("hackathon")
check("open: open and current, what DND was kept", (doc["state"], dm.current_project(), doc["started"]),
      ("open", "hackathon", {"dnd": False, "focus": "countdown"}))
check("open: the user's current layout isn't the hidden one", dm.current_layout(), "")
reset()
out = text_of(dm.project_open_now(ctx, "hackathon"))
check("open again: nothing opened twice", [c for c in calls if c[:2] == ("zen", "open")], [])

# Zen not running: started, else said.
state["zen_up"] = False
dm.zen_ready = lambda ctx, timeout: state["zen_up"]
reset()
out = text_of(dm.project_open_now(ctx, "hackathon"))
check_true("open: Zen not reachable is said", "Zen isn't reachable" in out, out)
check_true("open: Zen started for its tabs", ("niri", "spawn", "--", "zen") in calls, calls)
state["zen_up"] = True

# The agent desktop isn't the user's.
ctx.desktop = "agent"
for action in ("open", "save", "pause"):
    try:
        dm.t_project(ctx, {"action": action, "name": "hackathon"})
        check(f"{action}: refused on the agent desktop", "ran", "refused")
    except dm.ToolError as e:
        check_true(f"{action}: refused on the agent desktop", "user's desktop" in str(e), str(e))
ctx.desktop = "user"

# The tool: listed, aliases.
check_true("project list lists it",
           '"name":"hackathon"' in text_of(dm.t_project(ctx, {"action": "list"})).replace(" ", ""))
check("context_open is project open", dm.resolve_alias("context_open", {"name": "x"}),
      ("project", {"name": "x", "action": "open"}))
check("context_save with pause is project pause", dm.resolve_alias("context_save", {"name": "x", "pause": True}),
      ("project", {"name": "x", "action": "pause"}))
check("project_list is project list", dm.resolve_alias("project_list", {}), ("project", {"action": "list"}))
check("browser_open still a page tool", dm.resolve_alias("browser_open", {"url": "u"})[0], "page_go")
check("project acts (windows group)", dm.TOOLS["project"]["group"], "windows")
check("on_pause: keep or tabs",
      dm.TOOLS["project"]["spec"]["inputSchema"]["properties"]["on_pause"]["enum"], ["keep", "tabs"])
check("focus_app: callable, not offered", ("focus_app" in dm.TOOLS,
                                          any(t["name"] == "focus_app" for t in dm.offered_tools(cfg))), (True, False))
check_true("project is offered", any(t["name"] == "project" for t in dm.offered_tools(cfg)))

# The command line.
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    code = dm.main(["project", "set", "hackathon", "dnd", "none"])
check("cli set", (code, json.loads(buf.getvalue())["dnd"]), (0, None))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    code = dm.main(["project", "rename", "hackathon", "hack 2026"])
check("cli rename (spaces as dashes, its layout too)",
      (code, os.path.exists(os.path.join(dm.layouts_dir(), "_project-hack-2026.json")),
       dm.read_project("hack-2026")["layout"]), (0, True, "_project-hack-2026"))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    code = dm.main(["project", "list"])
check("cli list", [p["name"] for p in json.loads(buf.getvalue())["projects"]], ["hack-2026"])
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    code = dm.main(["project", "open", "Hack-2026"])
check_true("cli open: keeps the windows before (its Undo)",
           code == 0 and os.path.exists(os.path.join(dm.layouts_dir(), "_before-undo.json")))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    code = dm.main(["project", "delete", "hack-2026"])
check("cli delete (its layout too)", (code, os.path.exists(os.path.join(dm.layouts_dir(), "_project-hack-2026.json"))),
      (0, False))

# -- focus_app and run_steps ---------------------------------------------------
reset()
out = text_of(dm.t_focus_app(ctx, {"app": "kitty"}))
kitty_ids = {str(w["id"]) for w in state["windows"] if w["app_id"] == "kitty"}
focused = [c for c in calls if c[0] == "niri"]
check_true("focus_app: one of its windows to the front",
           len(focused) == 1 and focused[0][:3] == ("niri", "focus-window", "--id") and focused[0][3] in kitty_ids,
           focused)
launched = []
dm.t_launch_app = lambda ctx, args: launched.append(args) or [dm.text("started")]
dm.t_focus_app(ctx, {"app": "org.gnome.Calculator"})
check("focus_app: started when none is open", launched, [{"app": "org.gnome.Calculator"}])
try:
    dm.t_run_steps(ctx, {"steps": [{"tool": "page_go", "args": {"action": "close"}}]})
    check("run_steps: page_go only opens", "ran", "refused")
except dm.ToolError as e:
    check_true("run_steps: page_go only opens", "only opens or moves a page" in str(e), str(e))
dm.is_paused = lambda: False
reset()
out = text_of(dm.t_run_steps(ctx, {"steps": [{"tool": "page_go", "args": {"action": "open", "url": "https://a.example/x"},
                                              "wait_ms": 0}]}))
check_true("run_steps: page_go open runs", ("zen", "open", '{"active": false, "url": "https://a.example/x"}') in calls,
           calls)

# -- teach mode ------------------------------------------------------------------
check("helper: the shell feeds it", dm.helper_allowed(["teach", "event", "{}"]), True)
check("helper: never saves one", dm.helper_allowed(["teach", "save", "{}"]), False)

for value, secret in (("hunter2!pass9", True), ("482913", True), ("4111 1111 1111 1111", True),
                      ("FR76 3000 6000 0112 3456 7890 189", True), ("api_key=abcdef123456", True),
                      ("March 2026", False), ("Lunch with the team", False), ("https://x.example/a?b=1", False)):
    check(f"secret? {value!r}", dm.teach_secret(value), secret)

state["tabs"] = [{"id": 11, "window": 1, "active": True, "title": "Devpost", "url": "https://devpost.com/hack"}]
check("start", dm.teach_start(ctx)["recording"], True)
check("the recording is 0600", stat.S_IMODE(os.stat(dm.teach_path()).st_mode), 0o600)
ev = dm.teach_event
ev(ctx, {"kind": "launch", "app": "Actual Budget", "desktop": "actual", "name": "Actual Budget"})
ev(ctx, {"kind": "focus", "app": "actual", "desktop": "actual", "title": "Budget"})  # same app: no step
ev(ctx, {"kind": "focus", "app": "org.quickshell", "title": "Shell settings"})
check("a password manager isn't recorded",
      ev(ctx, {"kind": "focus", "app": "org.keepassxc.KeePassXC", "title": "Vault"}), {"skipped": "a password manager"})
check("nor what is copied right after", ev(ctx, {"kind": "clipboard", "text": "correct horse"}), {"skipped": "a secret"})
doc = dm.teach_read()
doc["secretUntil"] = 0
dm.teach_write(doc)
# Zen in front: the tab opened meanwhile, and the one in front moved.
state["tabs"] = [{"id": 11, "window": 1, "active": True, "title": "Expenses March",
                  "url": "https://expenses.example/report?month=March"},
                 {"id": 40, "window": 1, "title": "Receipts", "url": "https://drive.example/receipts/March"}]
ev(ctx, {"kind": "focus", "app": "zen", "desktop": "zen", "title": "Expenses"})
ev(ctx, {"kind": "url", "url": "https://drive.example/receipts/March"})  # the shell's own open: an echo
check("a code isn't kept", ev(ctx, {"kind": "text", "text": "839201"}), {"skipped": "a secret"})
check("a password field isn't kept", ev(ctx, {"kind": "text", "text": "fine words", "password": True}),
      {"skipped": "a secret"})
ev(ctx, {"kind": "text", "text": "Report for March"})
ev(ctx, {"kind": "clipboard", "text": "Team lunch 42 EUR"})
check("only web links", ev(ctx, {"kind": "url", "url": "file:///etc/passwd"}), {"skipped": "only web links"})
os.makedirs(os.path.join(os.environ["XDG_RUNTIME_DIR"], "nixbook-shell"), exist_ok=True)
with open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "nixbook-shell", "agent-input"), "w") as f:
    f.write(str(int(time.time() * 1000)))
check("not while an agent acts", ev(ctx, {"kind": "text", "text": "agent typed"}), {"skipped": "an agent was acting"})
os.unlink(os.path.join(os.environ["XDG_RUNTIME_DIR"], "nixbook-shell", "agent-input"))
stopped = dm.teach_stop(ctx)
check("stop: the steps (the tab in front moved, then the one opened; the shell's open of it not twice)",
      stopped["steps"], ["launch actual", "focus zen", "open https://expenses.example/report?month=M…",
                         "open https://drive.example/receipts/March", "type Report for March", "type Team lunch 42 EUR"])

items = dm.teach_steps(dm.teach_read()["events"])
check("the copied text is pending", [it["pending"] for it in items], [False, False, False, False, False, True])

prompts = []


def fake_model(cfg_, hint, system, prompt, schema=None, web=False):
    prompts.append((system, prompt, hint))
    return {"topic": "expenses: monthly report", "summary": "Opens the month's report and receipts.",
            "keep": [1, 3, 4, 5, 99], "vars": {"month": "March", "bogus": "not in a step", "Bad": "March"}}


dm.ask_model = fake_model
dm.model_ready = lambda cfg_, hint=None: True
draft = dm.teach_draft(cfg, ctx)
check("draft: one model call", len(prompts), 1)
check_true("draft: the model reads the recorded steps", "drive.example/receipts/March" in prompts[0][1])
check("draft: only steps recorded, as the model chose them", [s["tool"] for s in draft["steps"]],
      ["launch_app", "page_go", "page_go", "type_text"])
check("draft: only a variable found in the steps", draft["vars"], {"month": "March"})
check("draft: the variable in the steps", [s["args"].get("url") or s["args"].get("text") for s in draft["steps"][1:]],
      ["https://expenses.example/report?month={month}", "https://drive.example/receipts/{month}",
       "Report for {month}"])
check("draft: the navigation is a page_go navigate", draft["steps"][1]["args"]["action"], "navigate")
check("draft: named", (draft["topic"], draft["source"]), ("expenses: monthly report", "model"))

saved = dm.teach_save(ctx, {"topic": "expenses: monthly report", "rename": {"month": "period"}})
check("save: a recipe with its variable renamed", saved["vars"], ["period"])
note = next(n for n in dm.read_memory()["notes"] if n["id"] == saved["id"])
check("save: in the desktop memory, the user's", (note["kind"], note["source"], note["vars"]),
      ("recipe", "user", ["period"]))
check("save: the steps (no copied text unless ticked)", [s["tool"] for s in note["steps"]],
      ["launch_app", "page_go", "page_go", "type_text"])
check_true("save: the recording is gone", not os.path.exists(dm.teach_path()) and not os.path.exists(dm.teach_draft_path()))
try:
    dm.teach_save(ctx, {})
    check("save: twice", "saved", "refused")
except dm.ToolError:
    check("save: twice", "refused", "refused")

# The model choosing nothing usable: every step shown; AI off: no teach mode.
dm.teach_start(ctx)
ev(ctx, {"kind": "launch", "app": "kitty", "desktop": "kitty"})
dm.teach_stop(ctx)
dm.ask_model = lambda *a, **k: {"topic": "x", "keep": []}
draft = dm.teach_draft(cfg, ctx)
check("draft: plain when the model keeps nothing", (draft["source"], len(draft["steps"])), ("plain", 1))
cfg_path = os.path.join(os.environ["XDG_CONFIG_HOME"], "nixbook-shell", "config.json")
with open(cfg_path, "w") as f:
    json.dump({"policies": {"ai": 0}}, f)
try:
    dm.teach_start(ctx)
    check("AI off: no teach mode", "started", "refused")
except dm.ToolError:
    check("AI off: no teach mode", "refused", "refused")
os.unlink(cfg_path)

sys.exit(1 if failures else 0)
