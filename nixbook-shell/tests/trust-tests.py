"""The trust ladder's gate (scripts/desktop-mcp.py: trust_gate, the
helper's /trust hook) against a real helper: Claude Code's PreToolUse
events posted as it does, the shell's answers on the helper's stdin."""
import json, os, shutil, subprocess, sys, threading, urllib.request, queue, tempfile
dm = sys.argv[1]
home = tempfile.mkdtemp()
failed = []
env = dict(os.environ, XDG_STATE_HOME=home + "/state", XDG_CONFIG_HOME=home + "/cfg", XDG_RUNTIME_DIR=home + "/run", HOME=home)
os.makedirs(home + "/run", mode=0o700)
[env.pop(k, None) for k in list(env) if k.startswith("CLAUDE")]
p = subprocess.Popen([sys.executable, dm, "helper"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(json.loads(l)) for l in p.stdout], daemon=True).start()
hello = lines.get(timeout=10)
url, token = hello["hook"].replace("/hook", "/trust"), hello["token"]
def post(name, inp, results):
    ev = {"hook_event_name": "PreToolUse", "tool_name": name, "tool_input": inp, "session_id": "S1"}
    req = urllib.request.Request(url, data=json.dumps(ev).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    results.append(json.loads(urllib.request.urlopen(req, timeout=200).read() or b"{}"))
def call(name, inp):
    r = []; post(name, inp, r); return r[0]
def send(o):
    p.stdin.write(json.dumps(o) + "\n"); p.stdin.flush()
def check(label, got, want):
    print(("ok  " if got == want else "FAIL") + f" {label}: {got!r}" + ("" if got == want else f" (want {want!r})"))
    if got != want:
        failed.append(label)
dec = lambda a: (a.get("hookSpecificOutput") or {}).get("permissionDecision")
# 1. reads: silent, nothing sent
check("read tool passes", call("mcp__jellyfin__search", {"query": "x"}), {})
# 2. acting desktop step: tell -> told line
check("acting step passes", call("mcp__desktop__close_window", {"id": 3}), {})
check("told line", list(lines.get(timeout=5).keys()), ["told"])
# 3. risky other-server step: asked; answer allow
r = []; t = threading.Thread(target=post, args=("mcp__seerr__cancel_request", {"id": 4}, r)); t.start()
a = lines.get(timeout=5); check("approval asked", list(a.keys()), ["approval"]); check("its class", a["approval"]["class"], "seerr__cancel_request")
send({"approvalAnswer": a["approval"]["id"], "allow": True}); t.join(10)
check("allowed", dec(r[0]), "allow")
# 4. same, answered no
r = []; t = threading.Thread(target=post, args=("mcp__seerr__cancel_request", {"id": 5}, r)); t.start()
a = lines.get(timeout=5); send({"approvalAnswer": a["approval"]["id"], "allow": False}); t.join(10)
check("denied", dec(r[0]), "deny")
# 5. desktop risky (discord send): the server asks itself: the gate stays out
check("desktop send left to the server", call("mcp__desktop__discord", {"action": "send", "channel": "c", "content": "hi"}), {})
# 6. Always: the shell sets tell, then the next one isn't asked
send({"id": 9, "argv": ["trust", "set", "seerr__cancel_request", "tell"], "stdin": ""})
check("set via helper", json.loads(lines.get(timeout=5)["stdout"]), {"class": "seerr__cancel_request", "level": "tell"})
check("no longer asked", call("mcp__seerr__cancel_request", {"id": 6}), {})
check("told instead", list(lines.get(timeout=5).keys()), ["told"])
# 7. discord send raised by the user: told, and ask_user_yes skips
send({"id": 10, "argv": ["trust", "set", "discord:send", "tell"], "stdin": ""}); lines.get(timeout=5)
check("discord send told", call("mcp__desktop__discord", {"action": "send", "channel": "c", "content": "hi"}), {})
check("told line", list(lines.get(timeout=5).keys()), ["told"])
send({"id": 11, "argv": ["trust", "set", "discord:send", "silent"], "stdin": ""})
check("silent refused for a send", "error" in json.loads(lines.get(timeout=5)["stdout"]), True)
# 8. an agent can't set a level
out = subprocess.run([sys.executable, dm, "trust", "set", "close_window", "silent"], capture_output=True, text=True, env=dict(env, CLAUDECODE="1"))
check("agent refused", "error" in out.stdout, True)
# 9. streak: 3 yeses -> trustSuggest
for i in range(3):
    r = []; t = threading.Thread(target=post, args=("mcp__seerr__decline_request", {"id": i}, r)); t.start()
    a = lines.get(timeout=5); send({"approvalAnswer": a["approval"]["id"], "allow": True}); t.join(10)
check("suggest after 3", list(lines.get(timeout=5).keys()), ["trustSuggest"])
p.kill()
shutil.rmtree(home, ignore_errors=True)
sys.exit(1 if failed else 0)
