# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# nixbook-improve: the fixes and the features asked for.

# An inbox item's status (inbox.go) and its run's CI, in words.
IMPROVE_STATUS = {"new": "queued", "working": "being made", "pr": "pull request open", "merged": "merged",
                  "skipped": "skipped", "too_big": "too big", "feature": "moved to the feature requests",
                  "failed": "failed"}
IMPROVE_CI = {"pending": "CI running", "pass": "CI passed", "fail": "CI failed"}


@tool(
    "list_improvements",
    "shell",
    "What nixbook's fixer (nixbook-improve) has to do or did lately: the fixes "
    "filed with report_problem and the features with request_feature, newest "
    "first, each with its id, kind (fix or feature), what was asked and where it "
    "stands: queued (with its place in the line of those asked to start, "
    "`queued`: 1 starts next), being made (and what it does now), pull request open (its "
    "number and whether CI is running, passed or failed), merged, or skipped, too "
    "big or failed and why. Use it to tell the user how one goes, or to find the "
    "id start_improvement takes.",
    obj({}),
    read_only=True,
)
def t_list_improvements(ctx, args):
    st = improve_cmd(["status"])
    runs = st.get("runs") or []
    queue = improve_queue(st.get("inbox"))
    items = []
    for it in st.get("inbox") or []:
        s = it.get("status")
        if s not in IMPROVE_STATUS:
            continue
        r = next((r for r in runs if r.get("item") == it.get("id")), {})
        e = {"id": it.get("id"), "kind": "feature" if it.get("kind") == "feature" else "fix",
             "text": it.get("text"), "status": IMPROVE_STATUS[s]}
        if it.get("where"):
            e["where"] = it["where"]
        if s == "working":
            e["doing"] = r.get("doing") or r.get("stage")
        if queue.get(it.get("id")):
            e["queued"] = queue[it.get("id")]
        if s == "pr":
            e["pr"] = it.get("pr") or r.get("pr")
            e["ci"] = IMPROVE_CI.get(r.get("ci"), r.get("ci"))
        if s in ("skipped", "too_big", "failed") and it.get("note"):
            e["why"] = it["note"]
        items.append(e)
    return [text({"items": items[:30], "busy": improve_running(st) is not None})]


@tool(
    "start_improvement",
    "shell",
    "Start making a queued fix or building a queued feature of nixbook at once (its "
    "id from list_improvements), as Settings' Fix now and Build now: past the day's "
    "limit, one at a time; while another is being made it waits in line and starts "
    "on its own once that one is done. Only when the user asked for that in this conversation "
    "(\"build that feature now\"), never on your own; only while its kind is on "
    "(Settings > Self-improvement > Fixes it makes itself, Features it builds). It "
    "becomes a pull request the user reviews; list_improvements says how it goes.",
    obj({"id": {"type": "string", "description": "The item's id (list_improvements)"}}, ["id"]),
)
def t_start_improvement(ctx, args):
    iid = as_str(args, "id", max_len=40)
    st = improve_cmd(["status"])
    it = next((i for i in st.get("inbox") or [] if i.get("id") == iid), None)
    if not it:
        raise ToolError(f"no item {iid!r}: see list_improvements")
    feature = it.get("kind") == "feature"
    if not shell_setting("ai.improve.features.enable" if feature else "ai.improve.enable", False):
        raise ToolError(("building features is off: Settings > Self-improvement > Features it builds" if feature
                         else "the fixer is off: Settings > Self-improvement > Fixes it makes itself")
                        + ". Tell the user, don't retry.")
    ctx.guard.check_rate()
    return [text(improve_now(ctx, it, st))]


def improve_now(ctx, item, st=None):
    """Fix now / Build now: `nixbook-improve run --item` in a unit of its
    own, at the lowest priority, as SelfImprove.qml starts it (not counted in
    the day's runs). What to tell the user: started, or why not."""
    st = st or improve_cmd(["status"])
    what = "building" if item.get("kind") == "feature" else "fixing"
    if item.get("status") in ("working", "pr"):
        return "It is being made already: list_improvements says how it goes."
    if item.get("status") in ("merged", "feature"):
        return "Not started: it is " + IMPROVE_STATUS[item["status"]] + "."
    if not st.get("token"):
        return ("Not started: the fixer has no GitHub token yet; the user saves it in Settings > "
                "Self-improvement > Fixes it makes itself.")
    busy = improve_running(st)
    if busy:
        # One at a time: it waits in line and starts on its own after.
        try:
            pos = improve_cmd(["queue", item["id"]]).get("queued")
        except ToolError as e:
            return f"Not started: {e}."
        return (f"Queued (#{pos}): “{busy.get('itemText', '')}” is being made (one at a time); it starts "
                "on its own once the ones before it are done. The user can reorder or remove it in "
                "Settings > Self-improvement.")
    env = [f"--setenv=PATH={os.environ.get('PATH', '')}"]
    claude = claude_path(ctx.cfg)
    if claude:
        env.append(f"--setenv=NIXBOOK_IMPROVE_CLAUDE={claude}")
    try:
        proc = run(["systemd-run", "--user", "--collect", "--quiet", f"--unit=nixbook-improve-run-{int(time.time() * 1000)}",
                    "-p", "RuntimeMaxSec=8h", "-p", "Nice=19", "-p", "CPUWeight=idle", "-p", "IOSchedulingClass=idle",
                    *env, "nixbook-improve", "run", "--item", item["id"]], timeout=15, check=False)
    except ToolError as e:
        return f"Not started: {e}."
    if proc.returncode != 0:
        return f"Not started: {(proc.stderr or '').strip()[-200:] or 'systemd-run failed'}."
    return (f"Started {what} it now ({item['id']}); it takes a while, list_improvements says how it goes, "
            "and Settings > Self-improvement shows it too.")


def improve_queue(inbox):
    """The items asked to start while another was made: id -> place in line
    (1 starts next)."""
    q = sorted((i for i in inbox or [] if isinstance(i, dict) and (i.get("queued") or 0) > 0),
               key=lambda i: i["queued"])
    return {i.get("id"): n for n, i in enumerate(q, 1)}


def improve_running(st):
    """The run going on (its process still nixbook-improve's: one a reboot
    stopped has none), or None."""
    for r in st.get("runs") or []:
        if r.get("outcome") or r.get("stage") == "done" or not r.get("pid"):
            continue
        try:
            with open(f"/proc/{int(r['pid'])}/cmdline", "rb") as f:
                if b"nixbook-improve" in f.read():
                    return r
        except (OSError, ValueError):
            pass
    return None


def improve_file(cmd, what, where):
    """`nixbook-improve note|request`: the inbox item, or a ToolError."""
    return improve_cmd([cmd, "--where", where, what])


def improve_cmd(argv):
    """`nixbook-improve ARGV`: its JSON answer, or a ToolError."""
    proc = run(["nixbook-improve", *argv], timeout=10, check=False)
    try:
        out = json.loads(proc.stdout or "null")
    except ValueError:
        out = None
    if proc.returncode != 0 or not isinstance(out, dict):
        msg = out.get("error") if isinstance(out, dict) else (proc.stderr or "").strip()[-300:]
        raise ToolError(msg or f"nixbook-improve failed ({proc.returncode})")
    return out


# An inbox item's status (nixbook-improve's inbox.go), said plainly.
IMPROVE_STATUS = {
    "new": "queued", "working": "building", "pr": "pull request open", "merged": "merged",
    "skipped": "skipped (not a bug, or not enough to go on)", "ignored": "ignored (harmless, can't be fixed)",
    "too_big": "too big: needs a design choice or more than it may change", "feature": "moved to the feature "
    "requests (too big for a fix)", "failed": "failed (its change never passed the checks)",
    "dropped": "dropped by the user", "gone": "gone by itself",
    "unable": "dropped: it couldn't do it (why says what it tried and what would make it doable; "
    "the user can press Retry in Settings > Self-improvement)",
}
IMPROVE_CI = {"pending": "checks running", "pass": "checks passing", "fail": "checks failing"}


@tool(
    "list_requests",
    "shell",
    "What was filed for nixbook's fixer and builder (nixbook-improve) and how it "
    "goes: each fix and feature request, newest first, with when it was filed, who "
    "filed it, its status (queued, building, pull request open with its link and "
    "checks, merged, skipped, too big, failed, dropped) and why. Use it when the "
    "user asks \"did you file it?\" or \"how is my feature going?\", or before "
    "filing one again; it changes nothing. Who filed it is the user (through an "
    "agent, an agent's idea they accepted, or Settings) or the fixer itself (from "
    "the shell's log, a crash, CI…). Only while the user has turned on Fixes it "
    "makes itself or Features it builds.",
    obj({"kind": {"type": "string", "enum": ["fix", "feature"],
                  "description": "Only the fixes or only the feature requests (default both)"}}),
    read_only=True,
)
def t_list_requests(ctx, args):
    kind = as_str(args, "kind", required=False) or ""
    if kind not in ("", "fix", "feature"):
        raise ToolError("kind: fix or feature")
    if not (shell_setting("ai.improve.enable", False) or shell_setting("ai.improve.features.enable", False)):
        raise ToolError("the fixer is off: the user turns it on in Settings > Self-improvement > "
                        "Fixes it makes itself or Features it builds. Tell them, don't retry.")
    proc = run(["nixbook-improve", "status"], timeout=10, check=False)
    try:
        status = json.loads(proc.stdout or "null")
    except ValueError:
        status = None
    if proc.returncode != 0 or not isinstance(status, dict):
        raise ToolError((proc.stderr or "").strip()[-300:] or f"nixbook-improve failed ({proc.returncode})")
    # Each item's last run: its pull request, checks and title.
    runs = {r.get("item"): r for r in status.get("runs") or [] if isinstance(r, dict)}
    queue = improve_queue(status.get("inbox"))
    out = []
    for i in sorted(status.get("inbox") or [], key=lambda i: i.get("first") or 0, reverse=True):
        feature = i.get("kind") == "feature"
        # info: what isn't nixbook's (another app's crash), only listed.
        if i.get("kind") == "info" or (kind and feature != (kind == "feature")):
            continue
        r = runs.get(i.get("id")) or {}
        st = i.get("status") or "new"
        e = {
            "kind": "feature" if feature else "fix",
            "text": short(str(i.get("text") or ""), 300),
            "filed": time.strftime("%Y-%m-%d %H:%M", time.localtime((i.get("first") or 0) / 1000)),
            "by": "the fixer (a fix too big for one)" if i.get("from")
            else "the user" if i.get("kind") in ("user", "feature") else f"the fixer ({i.get('kind')})",
            "status": IMPROVE_STATUS.get(st, st),
        }
        if i.get("where"):
            e["where"] = i["where"]
        if (i.get("count") or 1) > 1:
            e["times"] = i["count"]
        if i.get("note"):
            e["why"] = short(str(i["note"]), 400)
        if r.get("title"):
            e["title"] = r["title"]
        if st == "working" and r.get("doing"):
            e["doing"] = r["doing"]
        if r.get("url") or i.get("pr"):
            e["pr"] = r.get("url") or f"#{i['pr']}"
        if queue.get(i.get("id")):
            e["status"] = f"queued, #{queue[i['id']]} in line to start (asked while another was being made)"
        if st == "pr" and r.get("ci") in IMPROVE_CI:
            e["status"] += ", " + IMPROVE_CI[r["ci"]]
        if st == "merged" and r.get("outcome") == "reverted":
            e["status"] = "merged, then reverted"
        out.append(e)
    return [text(out or f"nothing filed{' of that kind' if kind else ''}")]
