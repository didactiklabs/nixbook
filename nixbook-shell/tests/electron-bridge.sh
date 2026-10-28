#!/usr/bin/env bash
# Tests for scripts/electron-bridge.py (nixbook-electron-app), the launcher
# that gives the desktop agents an Electron app's pages: started with a
# stand-in for the app (tests/fake-cdp.py) speaking the DevTools protocol on
# the private pipe (fds 3/4), never a real app or account:
#   - what is never bridged (password managers, the switch off), a second
#     start handing over to the running one, an app handing over at once;
#   - the socket: private (0700/0600), one JSON request per line, only the
#     fixed operations (nothing is evaluated from a request);
#   - the page operations (isolated world, typing through Input.insertText,
#     keys through Input.dispatchKeyEvent, focus emulation only meanwhile,
#     password fields refused, screenshots);
#   - Discord's operations (main world, the length cap, the rate limit,
#     tokens and secret keys scrubbed, the audit log: lengths, no text).
# Needs bash, python3 and jq. Run: bash tests/electron-bridge.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge="$root/scripts/electron-bridge.py"
fake="$root/tests/fake-cdp.py"
tmp="$(mktemp -d)"
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

failures=0
pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /' >&2
  failures=$((failures + 1))
}
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi
}
expect_contains() {
  if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "missing: $3"$'\n'"in:"$'\n'"$2"; fi
}
expect_not_contains() {
  if grep -qF -- "$3" <<<"$2"; then fail "$1" "unexpected: $3"$'\n'"in:"$'\n'"$2"; else pass "$1"; fi
}

export XDG_RUNTIME_DIR="$tmp/run" XDG_STATE_HOME="$tmp/state" FAKE_CDP_LOG="$tmp/cdp.log"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"
: >"$FAKE_CDP_LOG"
sock="$XDG_RUNTIME_DIR/nixbook-electron/discord.sock"
audit="$XDG_STATE_HOME/nixbook-shell/electron-bridge.log"

# One request per argument on one connection, one answer line each.
ask() {
  python3 - "$sock" "$@" <<'EOF'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
f = s.makefile("rb")
for req in sys.argv[2:]:
    s.sendall(req.encode() + b"\n")
    print(f.readline().decode().rstrip())
EOF
}
start() {
  python3 "$bridge" --page-js "$root/zen/page.js" --adapters "$root/electron" discord -- python3 "$fake" --app-arg &
  pid=$!
  for _ in $(seq 1 100); do
    [ -S "$sock" ] && return 0
    sleep 0.05
  done
  echo "electron-bridge: no socket" >&2
  return 1
}

# -- never bridged -------------------------------------------------------------
expect_eq "a password manager: started without the bridge" "x --force-renderer-accessibility" \
  "$(python3 "$bridge" bitwarden -- echo x 2>/dev/null)"
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho "$@"\n' >"$tmp/bin/keepassxc"
chmod +x "$tmp/bin/keepassxc"
expect_eq "a password manager by its binary too" "x --force-renderer-accessibility" \
  "$(python3 "$bridge" vault -- "$tmp/bin/keepassxc" x 2>/dev/null)"
expect_eq "switched off: the app alone" "x --force-renderer-accessibility" \
  "$(NIXBOOK_ELECTRON_BRIDGE=0 python3 "$bridge" discord -- echo x)"
expect_eq "--no-a11y: no accessibility flag" "x" "$(NIXBOOK_ELECTRON_BRIDGE=0 python3 "$bridge" --no-a11y discord -- echo x)"
expect_eq "no socket for those" "no" "$([ -e "$sock" ] && echo yes || echo no)"
expect_contains "an app name is checked" "$(python3 "$bridge" '../x' -- echo x 2>&1 || true)" "isn't an app name"
expect_eq "--socket: the path" "$sock" "$(python3 "$bridge" --socket discord)"

# An app that hands over to one already running (without the bridge): no socket.
if FAKE_CDP_HANDOVER=1 python3 "$bridge" --page-js "$root/zen/page.js" discord -- python3 "$fake"; then
  pass "handing over: the launcher ends with the app"
else
  fail "handing over: the launcher ends with the app"
fi
expect_eq "handing over: no socket left" "no" "$([ -e "$sock" ] && echo yes || echo no)"

# -- the bridge ----------------------------------------------------------------
start
expect_eq "the socket: private" "600 700" "$(stat -c %a "$sock") $(stat -c %a "$(dirname "$sock")")"
expect_eq "the app: started with the pipe and its tree" '["--app-arg","--remote-debugging-pipe","--force-renderer-accessibility"]' \
  "$(head -n1 "$FAKE_CDP_LOG" | jq -c .argv)"
out=$(ask '{"cmd":"status"}' '{"cmd":"pages"}')
expect_eq "status" '{"app":"discord","pages":2,"adapter":true}' "$(sed -n 1p <<<"$out" | jq -c '.result | {app, pages, adapter}')"
expect_eq "pages: no DevTools, the web page main" '[["1",false],["2",true]]' \
  "$(sed -n 2p <<<"$out" | jq -c '[.result[] | [.id, .main]]')"
out=$(ask '{"cmd":"evaluate","expression":"document.cookie"}' '{"cmd":"app","op":"eval","args":{}}' 'not json' '{"cmd":"read","page":"9"}')
expect_eq "no evaluate" "unknown command 'evaluate'" "$(sed -n 1p <<<"$out" | jq -r .error)"
expect_eq "no other adapter operation" "no operation 'eval' for discord" "$(sed -n 2p <<<"$out" | jq -r .error)"
expect_contains "one JSON object per line" "$(sed -n 3p <<<"$out")" "one JSON object per line"
expect_contains "an unknown page" "$(sed -n 4p <<<"$out" | jq -r .error)" "no page '9'"

: >"$FAKE_CDP_LOG"
out=$(ask '{"cmd":"read","query":"message"}')
expect_eq "read: the main page's elements" '[1,"text editor","Message #general"]' \
  "$(jq -c '.result.elements[0] | [.ref, .role, .name]' <<<"$out")"
expect_eq "read: the password flag kept" true "$(jq '.result.elements[2].password' <<<"$out")"
expect_eq "read: in an isolated world, on the main page" '["read",true,"S-T1","message"]' \
  "$(grep '"eval"' "$FAKE_CDP_LOG" | tail -n1 | jq -c '[.op, .isolated, .session, .args.query]')"
expect_eq "read: the world made once" 1 "$(grep -c 'Page.createIsolatedWorld' "$FAKE_CDP_LOG")"

: >"$FAKE_CDP_LOG"
out=$(ask '{"cmd":"act","ref":1,"name":"Message #general","action":"type","value":"hello there"}')
expect_eq "type: through Input.insertText" '"hello there"' \
  "$(grep 'Input.insertText' "$FAKE_CDP_LOG" | jq -c .params.text)"
expect_eq "type: the element read back" '"hello there"' "$(jq -c .result.element.value <<<"$out")"
expect_eq "type: focus emulated for the action only" '[true,false]' \
  "$(grep 'setFocusEmulationEnabled' "$FAKE_CDP_LOG" | jq -s -c '[.[].params.enabled]')"
expect_eq "type: the page code asked to leave the typing to the bridge" true \
  "$(grep '"op": "act"' "$FAKE_CDP_LOG" | head -n1 | jq .args.host)"
: >"$FAKE_CDP_LOG"
ask '{"cmd":"act","ref":1,"name":"Message #general","action":"press","value":"Shift+Enter"}' >/dev/null
expect_eq "press: a key event to the page, with its modifier" '[["keyDown","Enter",8,"\r"],["keyUp","Enter",8,null]]' \
  "$(grep 'dispatchKeyEvent' "$FAKE_CDP_LOG" | jq -s -c '[.[].params | [.type, .key, .modifiers, .text]]')"
: >"$FAKE_CDP_LOG"
ask '{"cmd":"act","ref":1,"name":"Message","action":"press","value":"Ctrl+A"}' >/dev/null
expect_eq "press: a shortcut types nothing" '["rawKeyDown",2,null]' \
  "$(grep 'dispatchKeyEvent' "$FAKE_CDP_LOG" | head -n1 | jq -c '.params | [.type, .modifiers, .text]')"
out=$(ask '{"cmd":"act","ref":3,"name":"Password","action":"type","value":"x"}' \
  '{"cmd":"act","ref":1,"name":"Message","action":"press","value":"Hyper+Q"}' \
  '{"cmd":"act","ref":2,"name":"Send a gift","action":"click"}')
expect_contains "a password field: refused" "$(sed -n 1p <<<"$out" | jq -r .error)" "password fields are off limits"
expect_contains "an unknown modifier: refused" "$(sed -n 2p <<<"$out" | jq -r .error)" "unknown modifier"
expect_eq "click: done in the page" '["click","2"]' "$(sed -n 3p <<<"$out" | jq -c '[.result.done, .result.page]')"
out=$(ask '{"cmd":"wait","until":"text","text":"Hello","timeout":500}' '{"cmd":"wait","until":"text","text":"nope","timeout":300}' \
  '{"cmd":"screenshot"}' '{"cmd":"go","action":"back"}' '{"cmd":"go","action":"navigate"}')
expect_eq "wait: there" true "$(sed -n 1p <<<"$out" | jq .result.ok)"
expect_eq "wait: timed out" false "$(sed -n 2p <<<"$out" | jq .result.ok)"
expect_contains "screenshot: a JPEG" "$(sed -n 3p <<<"$out" | jq -r .result.data | cut -c1-30)" "data:image/jpeg;base64,/9j/"
expect_eq "go back: to the entry before" 7 "$(grep 'navigateToHistoryEntry' "$FAKE_CDP_LOG" | jq .params.entryId)"
expect_contains "go: only back, forward, reload" "$(sed -n 5p <<<"$out" | jq -r .error)" "back, forward or reload"

# -- Discord -------------------------------------------------------------------
: >"$FAKE_CDP_LOG"
out=$(ask '{"cmd":"app","op":"status"}' '{"cmd":"app","op":"read","args":{"channel":"general","limit":500}}')
expect_eq "discord: in the main world" '["nixbookApp",false]' \
  "$(grep '"eval"' "$FAKE_CDP_LOG" | head -n1 | jq -c '[.eval, .isolated]')"
expect_eq "discord status: no secret key passed on" '["Me",null]' "$(sed -n 1p <<<"$out" | jq -c '[.result.user, .result.token]')"
expect_eq "discord read: the limit capped" 50 "$(grep '"op": "read"' "$FAKE_CDP_LOG" | jq .args.limit)"
expect_contains "discord read: a token in a message hidden" "$(sed -n 2p <<<"$out" | jq -r '.result.messages[0].content')" "my token is [hidden]"
long=$(python3 -c 'print("a" * 2001)')
out=$(ask '{"cmd":"app","op":"send","args":{"channel":"222222222222222222","content":""}}' \
  "{\"cmd\":\"app\",\"op\":\"send\",\"args\":{\"channel\":\"222222222222222222\",\"content\":\"$long\"}}" \
  '{"cmd":"app","op":"send","args":{"channel":"222222222222222222","content":"see you at noon","reply_to":"555"}}')
expect_contains "send: nothing to send" "$(sed -n 1p <<<"$out" | jq -r .error)" "nothing to send"
expect_contains "send: 2000 characters at most" "$(sed -n 2p <<<"$out" | jq -r .error)" "at most 2000"
expect_eq "send: its id" '"999999999999999999"' "$(sed -n 3p <<<"$out" | jq -c .result.id)"
entry=$(grep '"send"' "$audit" | tail -n1)
expect_eq "send: in the audit log, its length only" '["discord","send",15,true,"ok"]' \
  "$(jq -c '[.app, .op, .chars, .reply, .outcome]' <<<"$entry")"
expect_not_contains "send: the text isn't logged" "$entry" "noon"
reqs=()
for _ in $(seq 1 10); do reqs+=('{"cmd":"app","op":"react","args":{"channel":"222222222222222222","message":"555","emoji":"👍"}}'); done
out=$(ask "${reqs[@]}")
expect_eq "react: the rate limit (10 sends a minute, with the send before)" "9 1" \
  "$(jq -s -r '[(map(select(.ok)) | length), (map(select(.ok | not)) | length)] | join(" ")' <<<"$out")"
expect_contains "react: refused past it" "$(tail -n1 <<<"$out" | jq -r .error)" "sends a minute"

# A second start while this one runs: it hands over, the socket stays.
ino=$(stat -c %i "$sock")
expect_eq "a second start: the app alone (it hands over)" "x --force-renderer-accessibility" \
  "$(python3 "$bridge" discord -- echo x)"
expect_eq "a second start: the socket untouched" "$ino" "$(stat -c %i "$sock")"

# The app quits: the launcher with it, the socket gone.
pkill -f "$fake --app-arg" || true
wait "$pid" 2>/dev/null || true
pid=""
expect_eq "the app gone: no socket" "no" "$([ -e "$sock" ] && echo yes || echo no)"

# -- relaunches and the watcher ------------------------------------------------
edir="$XDG_RUNTIME_DIR/nixbook-electron"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_NOTIFY_LOG"
[ -z "${FAKE_NOTIFY_ACTION:-}" ] || echo "$FAKE_NOTIFY_ACTION"
EOF
cat >"$tmp/bin/pactl" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_PACTL_JSON" 2>/dev/null || echo '[]'
EOF
chmod +x "$tmp/bin/notify-send" "$tmp/bin/pactl"
export NIXBOOK_NOTIFY_SEND="$tmp/bin/notify-send" NIXBOOK_PACTL="$tmp/bin/pactl" FAKE_NOTIFY_LOG="$tmp/notify.log" \
  FAKE_PACTL_JSON="$tmp/pactl.json" NIXBOOK_ELECTRON_SPAWN=plain
: >"$FAKE_NOTIFY_LOG"
# The app as another launcher (an autostart entry) or a relaunch starts it:
# a process naming the app's store path, outside any launcher.
marker="$tmp/store/w-vesktop"
unbridged() {
  python3 -c 'import time; time.sleep(120)' "$marker/opt/app.asar" >/dev/null 2>&1 &
  echo $!
}
expect_gone() {
  for _ in $(seq 1 100); do
    kill -0 "$2" 2>/dev/null || {
      pass "$1"
      return
    }
    sleep 0.1
  done
  fail "$1" "pid $2 still runs"
}
stop_launchers() {
  for l in $(pgrep -f 'electron-bridge[.]py.*watch-test' || true); do kill "$l" 2>/dev/null || true; done
  for _ in $(seq 1 50); do
    pgrep -f 'fake-cdp[.]py --watch-test' >/dev/null || break
    sleep 0.1
  done
  rm -f "$edir/discord.restarted"
}

# The app restarting itself: stopped, started again through the bridge, once.
: >"$FAKE_CDP_LOG"
FAKE_CDP_RELAUNCH="$marker" timeout 60 python3 "$bridge" --page-js "$root/zen/page.js" --adapters "$root/electron" \
  --marker "$marker" discord -- python3 "$fake" --relaunch-test 2>"$tmp/relaunch.err" || true
expect_eq "relaunch: started again through the bridge, once" 2 "$(grep -c '"argv"' "$FAKE_CDP_LOG")"
expect_contains "relaunch: said" "$(cat "$tmp/relaunch.err")" "it restarted itself without the bridge"
expect_contains "relaunch: again at once, given up (no loop)" "$(cat "$tmp/relaunch.err")" "giving up"
expect_contains "relaunch: given up, the user told" "$(cat "$FAKE_NOTIFY_LOG")" "restarted itself twice in a row"
for l in $(pgrep -f "^python3 -c import time; time.sleep[(]120[)] $marker" || true); do kill "$l" 2>/dev/null || true; done
rm -f "$edir/discord.restarted"
# A launcher whose app just quits: no new instance, it ends (no markers: no wait at all).

printf '{"apps":[{"app":"discord","command":["python3","%s","--watch-test"],"markers":["%s"],"a11y":true}]}\n' \
  "$fake" "$marker" >"$tmp/bridge.json"
watch() { python3 "$bridge" --page-js "$root/zen/page.js" --adapters "$root/electron" --config "$tmp/bridge.json" watch --once; }

# Young (an autostart entry, another launcher): restarted through the bridge.
: >"$FAKE_NOTIFY_LOG"
app_pid=$(unbridged)
sleep 0.3
out=$(watch)
expect_eq "watcher: a young unbridged instance restarted" "{}" "$out"
expect_gone "watcher: the unbridged instance stopped" "$app_pid"
for _ in $(seq 1 100); do
  [ -S "$sock" ] && break
  sleep 0.05
done
expect_eq "watcher: the app back, bridged" yes "$([ -S "$sock" ] && echo yes || echo no)"
expect_eq "watcher: nothing said for that" 0 "$(grep -c 'without nixbook' "$FAKE_NOTIFY_LOG" || true)"
stop_launchers

# Old: never stopped, the user asked once.
: >"$FAKE_NOTIFY_LOG"
app_pid=$(unbridged)
sleep 0.3
out=$(NIXBOOK_ELECTRON_YOUNG=0 watch)
expect_eq "watcher: an old instance listed unbridged" "$app_pid false" "$(jq -r '.discord | "\(.pid) \(.inCall)"' <<<"$out")"
expect_eq "watcher: an old instance left running" yes "$(kill -0 "$app_pid" 2>/dev/null && echo yes || echo no)"
expect_contains "watcher: the user asked, with the action" "$(cat "$FAKE_NOTIFY_LOG")" "-a Desktop agent -A restart=Restart with bridge --wait Vesktop runs without nixbook's bridge"
expect_eq "watcher: unbridged.json for desktop-mcp" "$app_pid" "$(jq -r .discord.pid "$edir/unbridged.json")"
# The user clicks "Restart with bridge".
: >"$FAKE_NOTIFY_LOG"
NIXBOOK_ELECTRON_YOUNG=0 FAKE_NOTIFY_ACTION=restart NIXBOOK_ELECTRON_LINGER=4 watch >/dev/null
expect_gone "the action: the instance stopped" "$app_pid"
for _ in $(seq 1 100); do
  [ -S "$sock" ] && break
  sleep 0.05
done
expect_eq "the action: the app back, bridged" yes "$([ -S "$sock" ] && echo yes || echo no)"
stop_launchers

# In a call (a recording stream of its own): only asked, even young.
: >"$FAKE_NOTIFY_LOG"
app_pid=$(unbridged)
printf '[{"index": 3, "properties": {"application.process.id": "%s"}}]\n' "$app_pid" >"$FAKE_PACTL_JSON"
sleep 0.3
out=$(watch)
expect_eq "watcher: in a call, said so" true "$(jq .discord.inCall <<<"$out")"
expect_eq "watcher: in a call, left running" yes "$(kill -0 "$app_pid" 2>/dev/null && echo yes || echo no)"
expect_contains "watcher: in a call, the user asked" "$(cat "$FAKE_NOTIFY_LOG")" "It was in a call"
rm -f "$FAKE_PACTL_JSON"
# Asked only once for that instance; again when an agent asks (discord.ask).
: >"$FAKE_NOTIFY_LOG"
python3 - "$bridge" "$root" "$tmp" <<'EOF'
import importlib.util, sys
s = importlib.util.spec_from_file_location("b", sys.argv[1]); b = importlib.util.module_from_spec(s); s.loader.exec_module(b)
opts = {"page_js": sys.argv[2] + "/zen/page.js", "adapters": sys.argv[2] + "/electron"}
w = b.Watcher(opts, b.read_config(sys.argv[3] + "/bridge.json"))
b.in_call = lambda pid: True
w.poll(); w.poll()
open(b.electron_dir() + "/discord.ask", "w").close()
w.asked.clear(); w.poll()
EOF
expect_eq "watcher: told once per instance, again when an agent asks" 2 "$(grep -c 'without nixbook' "$FAKE_NOTIFY_LOG")"
expect_contains "watcher: an agent's ask said" "$(cat "$FAKE_NOTIFY_LOG")" "An agent tried to use it"
# `restart APP` (the action from the command line).
out=$(python3 "$bridge" --page-js "$root/zen/page.js" --adapters "$root/electron" --config "$tmp/bridge.json" restart discord)
expect_eq "restart: said" "discord: started again through the bridge" "$out"
expect_gone "restart: the instance stopped" "$app_pid"
stop_launchers
expect_contains "restart: only a bridged app" \
  "$(python3 "$bridge" --config "$tmp/bridge.json" restart slack 2>&1 || true)" "one of discord"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all electron-bridge tests passed"
