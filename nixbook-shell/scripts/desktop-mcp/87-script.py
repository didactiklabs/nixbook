# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# run_script: "code mode". Every tool call of an agent is a round trip:
# the model re-reads its whole conversation for each, and every reply stays
# in it for every later step (DAI's transcripts, 2026-11: 77M tokens re-read
# from the cache against 0.9M written; the conversations of 5 calls or more,
# a quarter of them, 91% of it). A script does that work in one step: it
# calls the tools itself, in a loop if need be, and only what it prints
# comes back to the model.
#
# The script is Python, run by bubblewrap with nothing of the machine but
# the Nix store and an empty /tmp: no network, no home, no session bus, no
# Wayland. Its only way out is a pipe to this server: tools.NAME(**args)
# (this server's tools) and servers.NAME.TOOL(**args) (the side panel's
# other MCP servers, assistant-mcp.json), each call going through what the
# model's own calls go through: the tool groups, the pause, the privacy
# mask, the audit log, the rate limit, the tools' own asking (ask_user_yes)
# and, in the shell's sessions, the trust ladder (the helper's /trust, as
# Claude Code's hook would ask it: NIXBOOK_DESKTOP_MCP_TRUST_URL/TOKEN).

import collections

SCRIPT_TIMEOUT = 180
SCRIPT_TIMEOUT_MAX = 900
SCRIPT_CALLS_MAX = 300
SCRIPT_OUTPUT_MAX = 30000
SCRIPT_CODE_MAX = 40000
SCRIPT_MEMORY = 1 << 30
SCRIPT_RESULT_MAX = 2_000_000
# Not from a script: itself, and what only a person at the model's side
# should see (pictures go nowhere from here).
SCRIPT_REFUSED = {"run_script"}

# The script's side: the RPC over its stdin/stdout, print() kept apart.
SCRIPT_BOOT = r'''
import io, json, sys
_rpc_in, _rpc_out = sys.stdin, sys.__stdout__
_printed = io.StringIO()
sys.stdout = _printed
sys.stdin = io.StringIO("")

class ToolError(Exception):
    """A tool refused or failed: its message (a step the user said no to too)."""

def _ask(msg):
    _rpc_out.write(json.dumps(msg) + "\n")
    _rpc_out.flush()
    line = _rpc_in.readline()
    if not line:
        raise SystemExit("the server went away")
    reply = json.loads(line)
    if "error" in reply:
        raise ToolError(reply["error"])
    return reply.get("ok")

class _Tools:
    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        return lambda **args: _ask({"op": "call", "name": name, "args": args})
    def __call__(self, name, **args):
        return _ask({"op": "call", "name": name, "args": args})

class _Server:
    def __init__(self, server):
        self._server = server
    def __getattr__(self, tool):
        if tool.startswith("_"):
            raise AttributeError(tool)
        return lambda **args: _ask({"op": "mcp", "server": self._server, "tool": tool, "args": args})
    def __call__(self, tool, **args):
        return _ask({"op": "mcp", "server": self._server, "tool": tool, "args": args})

class _Servers:
    def __getattr__(self, server):
        if server.startswith("_"):
            raise AttributeError(server)
        return _Server(server)
    def __getitem__(self, server):
        return _Server(server)

tools, servers = _Tools(), _Servers()
_code = json.loads(_rpc_in.readline())["code"]
_error = None
try:
    exec(compile(_code, "<script>", "exec"), {"__name__": "__script__", "tools": tools, "servers": servers,
                                              "ToolError": ToolError})
except SystemExit:
    pass
except BaseException as e:
    import traceback
    tb = traceback.extract_tb(e.__traceback__)
    where = next((f"line {f.lineno}" for f in reversed(tb) if f.filename == "<script>"), "")
    _error = f"{type(e).__name__}: {e}" + (f" ({where})" if where else "")
_rpc_out.write(json.dumps({"op": "done", "printed": _printed.getvalue()[:200000], "error": _error}) + "\n")
_rpc_out.flush()
'''


def script_sandbox():
    """How the script runs: bubblewrap with nothing but the Nix store, or
    (NIXBOOK_DESKTOP_MCP_SCRIPT_UNSANDBOXED=1, the tests: a CI runner may
    have no user namespaces) a plain isolated Python."""
    py = [sys.executable, "-I", "-S", "-c", SCRIPT_BOOT]
    if os.environ.get("NIXBOOK_DESKTOP_MCP_SCRIPT_UNSANDBOXED") == "1":
        return py
    bwrap = shutil.which("bwrap")
    if not bwrap:
        raise ToolError("run_script needs bubblewrap (bwrap), which isn't installed: make the calls one by one")
    return [bwrap, "--unshare-all", "--die-with-parent", "--new-session",
            "--ro-bind", "/nix/store", "/nix/store", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
            "--clearenv", "--setenv", "HOME", "/tmp", "--setenv", "PATH", "/nonexistent", "--setenv", "LANG", "C.UTF-8",
            "--chdir", "/tmp", "--", *py]


def script_limits(seconds):
    def apply():
        import resource
        for what, value in ((resource.RLIMIT_AS, SCRIPT_MEMORY), (resource.RLIMIT_CPU, seconds + 5),
                            (resource.RLIMIT_FSIZE, 64 << 20), (resource.RLIMIT_NOFILE, 64)):
            try:
                resource.setrlimit(what, (value, value))
            except (ValueError, OSError):
                pass
    return apply


def script_value(content):
    """A tool's reply as the script gets it: the JSON of its text, else the
    text; a picture is only said."""
    parts = []
    for c in content or []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "text":
            parts.append(c.get("text") or "")
        elif c.get("type") == "image":
            parts.append("[a picture: scripts get none; take the screenshot as its own call]")
    if len(parts) == 1:
        try:
            return json.loads(parts[0])
        except ValueError:
            return parts[0]
    out = []
    for p in parts:
        try:
            out.append(json.loads(p))
        except ValueError:
            out.append(p)
    return out if out else None


def script_trust(server, tool, args):
    """The trust ladder for one step of a script, in the shell's sessions:
    the helper's /trust answers as it does Claude Code's hook (reads go on,
    `tell` is shown after, `ask` waits for the user's Allow). Not reached
    (no shell, the helper down): the step goes on, as the hook would."""
    url, token = os.environ.get("NIXBOOK_DESKTOP_MCP_TRUST_URL"), os.environ.get("NIXBOOK_DESKTOP_MCP_TRUST_TOKEN")
    if not url or not token or not url.startswith("http://127.0.0.1:"):
        return
    event = {"hook_event_name": "PreToolUse", "tool_name": f"mcp__{server}__{tool}", "tool_input": args,
             "session_id": os.environ.get("NIXBOOK_DESKTOP_MCP_SESSION", "")}
    import urllib.request
    req = urllib.request.Request(url, data=json.dumps(event).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=TRUST_ASK_TIMEOUT + 30) as r:
            answer = json.loads(r.read() or b"{}")
    except (OSError, ValueError) as e:
        log(f"run_script: trust: {e!r}")
        return
    out = (answer or {}).get("hookSpecificOutput") or {}
    if out.get("permissionDecision") == "deny":
        raise ToolError(out.get("permissionDecisionReason") or "Not done: the user said no.")


class ScriptServers:
    """The side panel's other MCP servers a script talks to: each started
    once, kept for the script, stopped at its end."""

    def __init__(self):
        self.procs = {}

    def call(self, name, tool_name, args, timeout=120):
        servers = assistant_servers()
        if name not in servers:
            raise ToolError(f"no MCP server {name!r} here" + (f" (there are: {', '.join(sorted(servers))})"
                                                                  if servers else ""))
        s = self.procs.get(name)
        if s is None or s["proc"].poll() is not None:
            s = self.start(name, servers[name])
        s["id"] += 1
        msg = {"jsonrpc": "2.0", "id": s["id"], "method": "tools/call", "params": {"name": tool_name, "arguments": args}}
        reply = self.exchange(s, msg, timeout)
        if reply.get("error"):
            raise ToolError(f"{name} refused: {short(str(reply['error'].get('message')), 300)}")
        res = reply.get("result") or {}
        return res.get("content") or [], bool(res.get("isError"))

    def start(self, name, server):
        env = dict(os.environ, **{k: str(v) for k, v in (server.get("env") or {}).items()})
        try:
            proc = subprocess.Popen([server["command"], *[str(a) for a in server.get("args") or []]],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                    text=True, env=env)
        except OSError as e:
            raise ToolError(f"the MCP server {name} didn't start: {e}")
        s = {"proc": proc, "id": 1}
        self.procs[name] = s
        self.exchange(s, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                          "params": {"protocolVersion": PROTOCOL_VERSIONS[0], "capabilities": {},
                                     "clientInfo": {"name": "nixbook-run-script", "version": VERSION}}}, 30)
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        proc.stdin.flush()
        return s

    def exchange(self, s, msg, timeout):
        proc, got = s["proc"], {}

        def talk():
            try:
                proc.stdin.write(json.dumps(msg) + "\n")
                proc.stdin.flush()
                for line in proc.stdout:
                    try:
                        reply = json.loads(line)
                    except ValueError:
                        continue
                    if reply.get("id") == msg["id"]:
                        got["reply"] = reply
                        return
            except (OSError, ValueError):
                pass

        worker = threading.Thread(target=talk, daemon=True)
        worker.start()
        worker.join(timeout)
        if "reply" not in got:
            proc.kill()
            raise ToolError("the MCP server gave no answer" + (" in time" if worker.is_alive() else ""))
        return got["reply"]

    def close(self):
        for s in self.procs.values():
            try:
                s["proc"].stdin.close()
                s["proc"].wait(3)
            except (OSError, subprocess.TimeoutExpired):
                s["proc"].kill()


def call_script(ctx, args, session=None):
    """run_script outside call_tool_now's lock (its calls take it, one by
    one): the same checks around it."""
    if not isinstance(args, dict):
        args = {}
    if "run_script" not in enabled_tools(ctx.cfg):
        raise KeyError("run_script")
    if ai_policy() == 0:
        audit(ctx.client, "run_script", {}, "AI off")
        return [text("refused: the user turned AI features off (Settings > Assistant > AI features)")], True
    if args.get("help") is True:
        return [text(guide_text("run_script"))], False
    try:
        paused = is_paused()
    except ToolError as e:
        return [text(f"refused: {e}")], True
    if paused:
        audit(ctx.client, "run_script", {}, "paused")
        return [text("refused: desktop control is paused by the user (`nixbook-desktop-mcp resume` to allow it again)")], True
    ctx.session = session
    logged = {"lines": len(str(args.get("code") or "").splitlines())}
    try:
        content = t_run_script(ctx, args)
    except ToolError as e:
        audit(ctx.client, "run_script", logged, f"error: {e}")
        return [text(mask_text(str(e)) if privacy_on() else str(e))], True
    except Exception as e:  # a bug here must not kill the server
        audit(ctx.client, "run_script", logged, f"crash: {e!r}")
        log(f"run_script: {e!r}")
        return [text(f"internal error: {e}")], True
    audit(ctx.client, "run_script", logged, "ok")
    count_use("tools", "run_script")
    # The script only ever held masked values; masked again all the same,
    # as every reply that reaches the model.
    if privacy_on():
        content = mask_obj(content, privacy_vocab())
    return content, False


def script_step(ctx, msg, others):
    """One call of the script: (value, None) or (None, why)."""
    op = msg.get("op")
    args = msg.get("args") if isinstance(msg.get("args"), dict) else {}
    if op == "call":
        name = str(msg.get("name") or "")
        if name in SCRIPT_REFUSED:
            return None, f"{name} can't be called from a script"
        if name not in TOOLS:
            name, args = resolve_alias(name, args)
        if name not in enabled_tools(ctx.cfg):
            return None, f"no tool {name!r} (or its group is turned off); tools.tool_help(name=...) gives a tool's guide"
        if not trust_reads(name, args, True):
            try:
                script_trust("desktop", name, args)
            except ToolError as e:
                return None, str(e)
        try:
            content, failed = call_tool(ctx, name, args, getattr(ctx, "session", None))
        except KeyError:
            return None, f"no tool {name!r}"
        value = script_value(content)
        if failed:
            return None, value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
        return value, None
    if op == "mcp":
        server, tool_name = str(msg.get("server") or ""), str(msg.get("tool") or "")
        if not re.fullmatch(r"[\w.-]{1,64}", server) or not re.fullmatch(r"[\w.-]{1,128}", tool_name):
            return None, "servers.NAME.TOOL(...): a server's name and one of its tools"
        if ai_policy() == 0:
            return None, "refused: the user turned AI features off"
        if not trust_reads(tool_name, args, False):
            try:
                script_trust(server, tool_name, args)
            except ToolError as e:
                return None, str(e)
        real = unmask_obj(args) if privacy_on() else args
        try:
            content, failed = others.call(server, tool_name, real)
        except ToolError as e:
            audit(ctx.client, f"{server}__{tool_name}", {}, "error")
            # A server's refusal may quote what it was given: the real values.
            return None, mask_text(str(e)) if privacy_on() else str(e)
        audit(ctx.client, f"{server}__{tool_name}", {}, "error" if failed else "ok")
        if privacy_on():
            content = mask_obj(content, privacy_vocab())
        value = script_value(content)
        if failed:
            return None, value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
        return value, None
    return None, "unknown request"


def run_script(ctx, code, seconds):
    """Runs the script; (printed, error, calls by name)."""
    import select
    import tempfile
    calls, others = collections.Counter(), ScriptServers()
    # A file, not a pipe: a script writing to stderr can't fill it and stall.
    errfile = tempfile.TemporaryFile(mode="w+")
    proc = subprocess.Popen(script_sandbox(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errfile,
                            text=True, preexec_fn=script_limits(seconds), close_fds=True)
    deadline = time.monotonic() + seconds
    done = None
    try:
        proc.stdin.write(json.dumps({"code": code}) + "\n")
        proc.stdin.flush()
        buf = ""
        while done is None:
            left = deadline - time.monotonic()
            if left <= 0:
                raise ToolError(f"the script ran out of time ({seconds} s): make it do less, or give it a longer timeout")
            ready, _, _ = select.select([proc.stdout], [], [], min(left, 1.0))
            if not ready:
                if proc.poll() is not None:
                    break
                continue
            line = proc.stdout.readline()
            if not line:
                break
            if len(line) > SCRIPT_RESULT_MAX:
                raise ToolError("the script sent too much at once")
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("op") == "done":
                done = msg
                break
            if sum(calls.values()) >= SCRIPT_CALLS_MAX:
                reply = {"error": f"more than {SCRIPT_CALLS_MAX} calls in one script: split the work"}
            else:
                label = msg.get("name") if msg.get("op") == "call" else f"{msg.get('server')}.{msg.get('tool')}"
                calls[str(label)[:80]] += 1
                value, why = script_step(ctx, msg, others)
                reply = {"error": why} if why is not None else {"ok": value}
            try:
                data = json.dumps(reply, ensure_ascii=False)
            except (TypeError, ValueError):
                data = json.dumps({"ok": str(reply.get("ok"))})
            if len(data) > SCRIPT_RESULT_MAX:
                data = json.dumps({"error": "that reply was too big for a script (more than 2 MB)"})
            proc.stdin.write(data + "\n")
            proc.stdin.flush()
    except (BrokenPipeError, OSError):
        pass
    finally:
        others.close()
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        try:
            errfile.seek(0)
            stderr = errfile.read()[-600:]
        except (OSError, ValueError):
            stderr = ""
        errfile.close()
    if done is None:
        why = (stderr or "").strip().splitlines()[-1:] or ["it ended without a word"]
        raise ToolError(f"the script stopped: {short(why[0], 300)}")
    return done.get("printed") or "", done.get("error"), calls


@tool(
    "run_script",
    "observe",
    "Code mode: run a short Python script that calls the tools itself, for any work of several calls (a loop over "
    "playlists, windows, mails, events, notes…, reading many things to act on a few, a chain of steps). Only what it "
    "print()s comes back to you, so it costs one step instead of one per call: prefer it whenever a task takes 3 "
    "calls or more and you don't need to see each answer to decide the next. In the script: tools.NAME(**args) "
    "calls this server's tool NAME with the same arguments as a direct call (tools.youtube_music_player(action="
    "\"playlists\"), tools.list_windows(), tools.mail(action=\"unread\")…) and returns its answer as Python values "
    "(the JSON parsed, else the text); servers.SERVER.TOOL(**args) calls another MCP server you have (servers."
    "jellyfin.search(query=\"…\")). A refused or failed call raises ToolError (catch it to go on). "
    "tools.tool_help(name=\"…\") returns a tool's guide. Python's standard library, no network, no files, no "
    "pictures (take screenshots as their own call). Each call is checked as yours would be: what sends, pays or "
    "deletes still asks the user. Print a short summary, not raw dumps.",
    obj({
        "code": {"type": "string", "description": "the Python script"},
        "timeout": {"type": "integer", "description": f"seconds it may take (default {SCRIPT_TIMEOUT}, at most {SCRIPT_TIMEOUT_MAX})"},
    }, ["code"]),
)
def t_run_script(ctx, args):
    code = args.get("code")
    if not isinstance(code, str) or not code.strip():
        raise ToolError("`code`: the Python script to run")
    if len(code) > SCRIPT_CODE_MAX:
        raise ToolError(f"`code`: at most {SCRIPT_CODE_MAX} characters")
    seconds = args.get("timeout", SCRIPT_TIMEOUT)
    if not isinstance(seconds, int) or isinstance(seconds, bool) or not 1 <= seconds <= SCRIPT_TIMEOUT_MAX:
        raise ToolError(f"`timeout`: 1 to {SCRIPT_TIMEOUT_MAX} seconds")
    printed, error, calls = run_script(ctx, code, seconds)
    n = sum(calls.values())
    head = f"{n} call{'s' if n != 1 else ''}" + (": " + ", ".join(f"{k}×{v}" if v > 1 else k for k, v in calls.most_common(12))
                                                   if n else "")
    out = printed if len(printed) <= SCRIPT_OUTPUT_MAX else (
        printed[:SCRIPT_OUTPUT_MAX] + f"\n… ({len(printed) - SCRIPT_OUTPUT_MAX} more characters cut: print less)")
    parts = [text(f"({head})"), text(out or "(it printed nothing)")]
    if error:
        parts.append(text(f"The script failed: {error}"))
    return parts
