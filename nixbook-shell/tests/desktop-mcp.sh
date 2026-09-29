#!/usr/bin/env bash
# Tests for scripts/desktop-mcp.py (nixbook-desktop-mcp), against stub niri,
# wtype, ydotool, grim, wl-copy, notify-send and qs that log their arguments:
#   - the MCP protocol over stdio (initialize, tools/list, tools/call, errors);
#   - each tool's niri/wtype/ydotool command line;
#   - the guardrails: denied windows, Super/VT combos, text cap, rate limit,
#     pause, disabled groups, denied IPC targets, no arbitrary commands;
#   - the pointer: the exact Wayland requests sent to a fake compositor
#     (tests/fake-wayland.py), screenshot mappings, the ydotool fallback;
#   - HTTP: loopback only, bearer token, Host/Origin checks.
# Needs bash, python3, jq and curl. Run: bash tests/desktop-mcp.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mcp="$root/scripts/desktop-mcp.py"
tmp="$(mktemp -d)"
http_pid=""
wl_pid=""
cleanup() {
  [ -z "$http_pid" ] || kill "$http_pid" 2>/dev/null || true
  [ -z "$wl_pid" ] || kill "$wl_pid" 2>/dev/null || true
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

# -- stubs -------------------------------------------------------------------

bin="$tmp/bin"
mkdir -p "$bin" "$tmp/runtime" "$tmp/state" "$tmp/config/nixbook-shell" "$tmp/data/applications"
calls="$tmp/calls"
: >"$calls"
export STUB_CALLS="$calls" STUB_FOCUS="$tmp/focus" STUB_CLIP="$tmp/clip"
echo firefox >"$STUB_FOCUS"

cat >"$bin/niri" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "msg --json" ]; then
  focus=$(cat "$STUB_FOCUS")
  case "$3" in
    windows)
      # A launched app's window (spawn below) appears after the others.
      # Hidden: ids listed in $STUB_CALLS.hidden (closed windows).
      hidden="$(cat "$STUB_CALLS.hidden" 2>/dev/null || echo '[]')"
      launched_app="$(cat "$STUB_CALLS.launched" 2>/dev/null || true)"
      jq -nc --arg f "$focus" --argjson launched "$([ -e "$STUB_CALLS.launched" ] && echo true || echo false)" \
        --arg launched_app "${launched_app:-firefox}" --argjson hidden "$hidden" '[
        {id: 1, app_id: "firefox", title: "Mozilla Firefox", workspace_id: 10, is_focused: ($f == "firefox"), is_floating: false},
        {id: 2, app_id: "kitty", title: "~", workspace_id: 10, is_focused: ($f == "kitty"), is_floating: false},
        {id: 3, app_id: "org.gnome.Nautilus", title: "Enter password", workspace_id: 11, is_focused: ($f == "prompt"), is_floating: true,
         layout: {window_size: [800, 600], tile_pos_in_workspace_view: [100.4, 50], pos_in_scrolling_layout: null}},
        {id: 4, app_id: "org.gnome.TextEditor", title: "notes", workspace_id: 10, is_focused: false, is_floating: false,
         layout: {window_size: [1000, 1900], tile_pos_in_workspace_view: null, pos_in_scrolling_layout: [2, 1]}},
        {id: 5, app_id: "org.gnome.Calculator", title: "Calculator", workspace_id: 10, is_focused: false, is_floating: true,
         layout: {window_size: [400, 300], tile_pos_in_workspace_view: [10, 20], window_offset_in_tile: [2, 3]}}
      ] + (if $launched then [{id: 6, app_id: $launched_app, title: "New Tab", workspace_id: 10, is_focused: false, is_floating: false}] else [] end)
      | map(select(.id as $i | $hidden | index($i) | not))' ;;
    workspaces)
      echo '[{"id":10,"idx":1,"name":null,"output":"eDP-1","is_active":true,"is_focused":true,"active_window_id":1},
             {"id":11,"idx":2,"name":"chat","output":"eDP-1","is_active":false,"is_focused":false,"active_window_id":3}]' ;;
    outputs)
      echo '{"eDP-1":{"name":"eDP-1","logical":{"x":0,"y":0,"width":3136,"height":1960,"scale":1.0}},
             "HDMI-A-1":{"name":"HDMI-A-1","logical":{"x":3136,"y":200,"width":1920,"height":1080,"scale":2.0}},
             "DP-2":{"name":"DP-2","logical":null}}' ;;
    focused-output)
      echo '{"name":"eDP-1"}' ;;
  esac
  exit 0
fi
echo "niri $*" >>"$STUB_CALLS"
# The launched window's app_id: the command's name (what the stub .desktop files start).
[ "$3" != "spawn" ] || basename "$5" >"$STUB_CALLS.launched"
if [ "$3" = "screenshot-window" ]; then
  # Like niri: the capture goes to --path and to the clipboard.
  printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\x03\xe8\0\0\x07\x6c window' >"${*: -1}"
  cp "${*: -1}" "$STUB_CLIP"
  echo image/png >"$STUB_CLIP.type"
fi
EOF
for tool in wtype ydotool notify-send; do
  cat >"$bin/$tool" <<EOF
#!/usr/bin/env bash
if [ "\${*: -1}" = "-" ] || [ "\${*: -1}" = "--file" ]; then echo "$tool \$* <<\$(cat)" >>"\$STUB_CALLS"; else echo "$tool \$*" >>"\$STUB_CALLS"; fi
EOF
done
cat >"$bin/grim" <<'EOF'
#!/usr/bin/env bash
echo "grim $*" >>"$STUB_CALLS"
printf '\x89PNG fake' >"${*: -1}"
EOF
# A clipboard: $STUB_CLIP (content) and $STUB_CLIP.type (its type).
cat >"$bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--clear" ]; then
  rm -f "$STUB_CLIP" "$STUB_CLIP.type"
  echo "wl-copy --clear" >>"$STUB_CALLS"
  exit 0
fi
type=text/plain
[ "${1:-}" != "--type" ] || type=$2
cat >"$STUB_CLIP"
echo "$type" >"$STUB_CLIP.type"
echo "wl-copy <<$(cat "$STUB_CLIP")" >>"$STUB_CALLS"
EOF
cat >"$bin/wl-paste" <<'EOF'
#!/usr/bin/env bash
[ -f "$STUB_CLIP.type" ] || exit 1
if [ "${1:-}" = "--list-types" ]; then cat "$STUB_CLIP.type"; else cat "$STUB_CLIP"; fi
EOF
# magick: copies its input to its output (the last argument).
cat >"$bin/magick" <<'EOF'
#!/usr/bin/env bash
echo "magick $*" >>"$STUB_CALLS"
cp "$1" "${*: -1}"
EOF
cat >"$bin/qs" <<'EOF'
#!/usr/bin/env bash
echo "qs $*" >>"$STUB_CALLS"
if [ "${*: -1}" = "show" ]; then
  printf 'target sidebarLeft\n  function toggle(): void\ntarget session\n  function open(): void\n'
fi
EOF
chmod +x "$bin"/*

cat >"$tmp/data/applications/org.mozilla.firefox.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Firefox
Exec=firefox --name firefox %u
[Desktop Action new]
Exec=firefox --new-window
EOF
cat >"$tmp/data/applications/org.gnome.Calculator.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Calculator
Exec=org.gnome.Calculator
EOF
cat >"$tmp/data/applications/htop.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Htop
Exec=htop
Terminal=true
EOF

export PATH="$bin:$PATH"
export XDG_RUNTIME_DIR="$tmp/runtime" XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
export XDG_DATA_HOME="$tmp/data" XDG_DATA_DIRS="$tmp/none"
export NIXBOOK_DESKTOP_MCP_QS="$bin/qs" NIXBOOK_DESKTOP_MCP_QS_CONFIG=nixbook-shell
export NIRI_SOCKET=/dev/null
# No compositor yet: the pointer tools fall back to ydotool until the fake
# one starts (the pointer section below).
export WAYLAND_DISPLAY=wayland-test

call() { python3 "$mcp" call "$@" 2>&1 || true; }
last_call() { tail -n 1 "$calls"; }
reset_calls() { : >"$calls"; }

# -- MCP over stdio ------------------------------------------------------------

out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test-client"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nope","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"bogus"}' \
  'not json' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"screenshot","arguments":{}}}' |
  python3 "$mcp")
expect_eq "stdio: one reply per request, none for notifications" 7 "$(wc -l <<<"$out" | tr -d ' ')"
expect_eq "initialize: protocol version echoed" 2025-06-18 "$(jq -r 'select(.id==1).result.protocolVersion' <<<"$out")"
expect_eq "initialize: tools capability" '{"listChanged":false}' "$(jq -c 'select(.id==1).result.capabilities.tools' <<<"$out")"
expect_eq "tools/list: 29 tools" 29 "$(jq 'select(.id==2).result.tools | length' <<<"$out")"
expect_eq "tools/list: read-only annotation" true "$(jq 'select(.id==2).result.tools[] | select(.name=="list_windows").annotations.readOnlyHint' <<<"$out")"
expect_eq "tools/list: destructive annotation" true "$(jq 'select(.id==2).result.tools[] | select(.name=="close_window").annotations.destructiveHint' <<<"$out")"
expect_eq "tools/call: focus_window succeeds" false "$(jq 'select(.id==3).result.isError' <<<"$out")"
expect_eq "unknown tool: -32602" -32602 "$(jq 'select(.id==4).error.code' <<<"$out")"
expect_eq "unknown method: -32601" -32601 "$(jq 'select(.id==5).error.code' <<<"$out")"
expect_eq "bad JSON: -32700" -32700 "$(jq 'select(.id==null).error.code' <<<"$out")"
expect_eq "screenshot: image content (JPEG)" "image/jpeg" "$(jq -r 'select(.id==6).result.content[1].mimeType' <<<"$out")"
expect_eq "screenshot: scaled to 1568px" "grim -o eDP-1 -s 0.5000 -t jpeg" "$(grep '^grim' "$calls" | cut -d' ' -f1-7)"
expect_eq "screenshot: file removed after sending" 0 "$(find "$XDG_RUNTIME_DIR" -name 'screenshot-*' | wc -l | tr -d ' ')"
expect_eq "audit: client name from initialize" test-client "$(jq -r 'select(.tool=="focus_window").client' "$XDG_STATE_HOME/nixbook-shell/desktop-mcp.log" | head -1)"
expect_eq "audit log is private" 600 "$(stat -c %a "$XDG_STATE_HOME/nixbook-shell/desktop-mcp.log")"
expect_eq "runtime dir is private" 700 "$(stat -c %a "$XDG_RUNTIME_DIR/nixbook-desktop-mcp")"

# -- tools -----------------------------------------------------------------------

out=$(call list_windows)
expect_eq "list_windows: workspace joined" chat "$(jq -r '.[] | select(.id==3).workspace.name' <<<"$out")"
expect_eq "list_windows: floating position and size" '[100,50] [800,600]' "$(jq -c '.[] | select(.id==3) | .position, .size' <<<"$out" | paste -sd' ')"
expect_eq "list_windows: tiled column, no position" '2 1 null' "$(jq -r '.[] | select(.id==4) | "\(.column) \(.tile) \(.position)"' <<<"$out")"

# Window screenshots: silent (grim) for windows on screen.
printf 'user text' | wl-copy
reset_calls
out=$(call screenshot '{"window_id":5}')
expect_eq "window screenshot: a floating window cropped exactly, silently" "grim -g 12,23 400x300 -s 1.0000 -t jpeg" "$(grep '^grim' "$calls" | cut -d' ' -f1-8)"
expect_contains "window screenshot: floating window mapping" "$out" 'mapping: {"x": 12, "y": 23, "scale": 1.0}'
reset_calls
out=$(call screenshot '{"window_id":4}')
expect_contains "window screenshot: a tiled window comes with its monitor" "$out" "is tiled on eDP-1"
expect_eq "window screenshot: niri's capture not used" "" "$(grep screenshot-window "$calls" || true)"
out=$(call screenshot '{"window_id":3}')
expect_contains "window screenshot: off screen refused by default" "$out" "isn't on screen"
# Off screen, asked for: niri's capture (to a file, and the clipboard, which comes back).
reset_calls
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"screenshot","arguments":{"window_id":3,"offscreen":true}}}' | python3 "$mcp")
expect_eq "offscreen window screenshot: JPEG" image/jpeg "$(jq -r '.result.content[1].mimeType' <<<"$out")"
expect_contains "offscreen window screenshot: size read" "$(jq -r '.result.content[0].text' <<<"$out")" "1000x1900 pixels"
expect_contains "offscreen window screenshot: niri writes it to a file" "$(cat "$calls")" "niri msg action screenshot-window --id 3 --path $XDG_RUNTIME_DIR/nixbook-desktop-mcp/screenshot-"
sleep 0.2
expect_eq "offscreen window screenshot: clipboard restored" "user text" "$(wl-paste)"
out=$(call screenshot '{"window_id":99}')
expect_contains "window screenshot: unknown id" "$out" "no window with id 99"

reset_calls
call move_window_to_workspace '{"id":1,"workspace":2}' >/dev/null
expect_eq "move_window_to_workspace" "niri msg action move-window-to-workspace --window-id 1 --focus false 2" "$(last_call)"
call focus_workspace '{"workspace":"chat"}' >/dev/null
expect_eq "focus_workspace by name" "niri msg action focus-workspace chat" "$(last_call)"
out=$(call focus_workspace '{"workspace":"--help"}')
expect_contains "focus_workspace: option-like name refused" "$out" "must be a workspace index"
out=$(call focus_window '{"id":99}')
expect_contains "focus_window: unknown id" "$out" "no window with id 99"
call window_action '{"id":1,"action":"wider"}' >/dev/null
expect_eq "window_action wider" "niri msg action set-column-width +10%" "$(last_call)"

reset_calls
rm -f "$calls.launched"
out=$(call launch_app '{"app":"firefox"}')
expect_eq "launch_app: by name, field codes dropped" "niri msg action spawn -- firefox --name firefox" "$(last_call)"
expect_contains "launch_app: waits for the new window and names it" "$out" '"title": "New Tab"'
out=$(call launch_app '{"app":"htop"}')
expect_contains "launch_app: terminal apps refused" "$out" "terminal applications"
out=$(call launch_app '{"app":"rm -rf ~"}')
expect_contains "launch_app: no arbitrary command" "$out" "no application matches"

reset_calls
call type_text '{"text":"hello world"}' >/dev/null
expect_eq "type_text via wtype stdin" "wtype - <<hello world" "$(last_call)"
call press_keys '{"keys":["ctrl+l","Return"]}' >/dev/null
expect_eq "press_keys" "wtype -M ctrl -k l -m ctrl -k Return" "$(last_call)"
out=$(call press_keys '{"keys":["super+shift+e"]}')
expect_contains "press_keys: Super refused" "$out" "Super combinations"
out=$(call press_keys '{"keys":["ctrl+alt+F2"]}')
expect_contains "press_keys: VT switch refused" "$out" "VT switching"
# shellcheck disable=SC2016 # a literal $(id), as an agent could send it
out=$(call press_keys '{"keys":["ctrl+$(id)"]}')
expect_contains "press_keys: bad key name" "$out" "invalid key"
out=$(call click '{"x":100,"y":200,"button":"right"}')
expect_eq "fallback click: moves then clicks" "ydotool click 0xC1" "$(last_call)"
expect_eq "fallback click: absolute move" "ydotool mousemove --absolute -x 100 -y 200" "$(tail -n 2 "$calls" | head -1)"
expect_contains "fallback click: says it's approximate" "$out" "ydotool fallback: approximate"
call scroll '{"dy":3}' >/dev/null
expect_eq "fallback scroll down" "ydotool mousemove --wheel -x 0 -y -3" "$(last_call)"
call drag '{"x":10,"y":10,"to_x":20,"to_y":20}' >/dev/null
expect_eq "fallback drag: press, moves, release" "ydotool click 0x40|ydotool click 0x80" \
  "$(grep '^ydotool click' "$calls" | tail -n 2 | paste -sd'|')"
call clipboard_set '{"text":"abc"}' >/dev/null
sleep 0.2
expect_contains "clipboard_set" "$(cat "$calls")" "wl-copy <<abc"

echo kitty >"$STUB_FOCUS"
reset_calls
out=$(call type_text '{"text":"rm -rf ~"}')
expect_contains "type_text into a terminal refused" "$out" "refused: input into 'kitty'"
out=$(call click '{"x":1,"y":1}')
expect_contains "click into a terminal refused" "$out" "refused"
echo prompt >"$STUB_FOCUS"
out=$(call press_keys '{"keys":["Return"]}')
expect_contains "input into a password prompt refused" "$out" "password or authentication prompt"
expect_eq "nothing ran while refused" "" "$(cat "$calls")"
echo firefox >"$STUB_FOCUS"

out=$(call type_text "$(jq -nc '{text: ("x" * 5000)}')")
expect_contains "type_text: length cap" "$out" "longer than 4000"
if grep -q '"text": "<5000 chars>"' "$XDG_STATE_HOME/nixbook-shell/desktop-mcp.log"; then
  pass "audit: typed text not logged"
else
  fail "audit: typed text not logged"
fi

out=$(call shell_ipc_list)
expect_not_contains "shell_ipc_list hides denied targets" "$out" "target session"
call shell_ipc '{"target":"sidebarLeft","function":"toggle"}' >/dev/null
expect_eq "shell_ipc" "qs -c nixbook-shell ipc call -- sidebarLeft toggle" "$(last_call)"
out=$(call shell_ipc '{"target":"session","function":"open"}')
expect_contains "shell_ipc: denied target" "$out" "off limits"

# -- the pointer through the virtual pointer protocol ------------------------------------

# Screenshot mappings: a region at full resolution, the monitor as before.
reset_calls
out=$(call screenshot '{"region":{"x":3140,"y":210,"width":100,"height":50}}')
expect_eq "region screenshot: sharpest scale of the monitor it covers" "grim -g 3140,210 100x50 -s 2.0000 -t jpeg" "$(grep '^grim' "$calls" | cut -d' ' -f1-8)"
expect_contains "region screenshot: mapping" "$out" 'mapping: {"x": 3140, "y": 210, "scale": 2.0}'
out=$(call screenshot '{"region":{"x":9000,"y":0,"width":100,"height":100}}')
expect_contains "region screenshot: outside the desktop" "$out" "outside the desktop"
out=$(call screenshot '{}')
expect_contains "monitor screenshot: mapping" "$out" 'mapping: {"x": 0, "y": 0, "scale": 0.5}'

wl_log="$tmp/wayland.log"
start_compositor() {
  [ -z "${wl_pid:-}" ] || kill "$wl_pid" 2>/dev/null || true
  : >"$wl_log"
  python3 "$root/tests/fake-wayland.py" "$XDG_RUNTIME_DIR/wayland-test" "$wl_log" "$@" &
  wl_pid=$!
  for _ in $(seq 50); do
    [ -S "$XDG_RUNTIME_DIR/wayland-test" ] && break
    sleep 0.05
  done
}
# The requests the fake compositor got, one per line: name and arguments.
requests() { jq -rc 'select(.request != "frame") | [.request, (.args // .interface // .seat)] | map(tostring) | join(" ")' "$wl_log"; }
start_compositor

out=$(call get_status)
expect_eq "get_status: exact pointer" "virtual pointer (exact)" "$(jq -r .pointer <<<"$out")"

: >"$wl_log"
reset_calls
out=$(call click '{"x":3200.5,"y":300}')
expect_eq "click: no ydotool" "" "$(grep ydotool "$calls" || true)"
expect_eq "click: the exact protocol exchange" "bind wl_seat
bind zwlr_virtual_pointer_manager_v1
create_virtual_pointer wl_seat
motion_absolute [25604,2400,40448,15680]
button [272,1]
button [272,0]
destroy []
manager_destroy null" "$(requests)"
expect_eq "click: seat and manager bound at version 1" "1 1" "$(jq -r 'select(.request=="bind").version' "$wl_log" | paste -sd' ')"
expect_eq "click: every event in a frame" 3 "$(jq -r .request "$wl_log" | grep -c '^frame$')"
expect_eq "click: reply" "left click at (3200.5,300)" "$(head -n 1 <<<"$out")"
expect_eq "click: reply names the focused window" "Focused: firefox — 'Mozilla Firefox' (id 1)" "$(tail -n 1 <<<"$out")"

: >"$wl_log"
call click '{"x":100,"y":50,"screenshot":{"x":3136,"y":200,"scale":2},"button":"right","double":true}' >/dev/null
expect_eq "click: screenshot pixels mapped to the desktop" "motion_absolute [25488,1800,40448,15680]" "$(requests | grep motion)"
expect_eq "double right click" "button [273,1]|button [273,0]|button [273,1]|button [273,0]" "$(requests | grep button | paste -sd'|')"

: >"$wl_log"
out=$(call click '{"x":6000,"y":10}')
expect_contains "click: outside the desktop refused" "$out" "outside the desktop"
expect_eq "click: nothing pressed outside the desktop" "" "$(requests | grep button || true)"
out=$(call click '{"x":1,"y":1,"screenshot":{"x":0,"y":0,"scale":0}}')
expect_contains "click: bad mapping refused" "$out" "must be a screenshot's mapping"

: >"$wl_log"
call drag '{"x":100,"y":100,"to_x":220,"to_y":340}' >/dev/null
expect_eq "drag: press, 13 moves, release" "13 button [272,1]|button [272,0]" \
  "$(requests | grep -c motion_absolute) $(requests | grep button | paste -sd'|')"
expect_eq "drag: ends on the target" "motion_absolute [1760,2720,40448,15680]" "$(requests | grep motion_absolute | tail -n 1)"
expect_eq "drag: pressed after the first move, released after the last" "motion_absolute button motion_absolute button" \
  "$(requests | awk '{print $1}' | grep -E 'motion_absolute|button' | uniq | sed -n '1p;2p;3p;$p' | paste -sd' ')"

: >"$wl_log"
call scroll '{"dy":3,"dx":-1,"x":50,"y":60}' >/dev/null
expect_eq "scroll: at a point, wheel notches" "motion_absolute [400,480,40448,15680]|axis_source [0]|axis_discrete [0,45.0,3]|axis_discrete [1,-15.0,-1]" \
  "$(requests | grep -E 'motion|axis' | paste -sd'|')"

echo kitty >"$STUB_FOCUS"
: >"$wl_log"
out=$(call click '{"x":10,"y":10}')
expect_contains "click into a terminal refused before connecting" "$out" "refused"
expect_eq "no Wayland request while refused" "" "$(cat "$wl_log")"
echo firefox >"$STUB_FOCUS"

start_compositor --no-virtual-pointer
reset_calls
out=$(call click '{"x":10,"y":20}')
expect_eq "no virtual pointer: ydotool fallback" "ydotool mousemove --absolute -x 10 -y 20|ydotool click 0xC0" "$(paste -sd'|' "$calls")"
out=$(call get_status)
expect_contains "get_status: fallback reported" "$(jq -r .pointer <<<"$out")" "ydotool (approximate)"
kill "$wl_pid" 2>/dev/null || true
wl_pid=""

# -- fewer round trips: screenshot_after, run_steps ---------------------------------------

reset_calls
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1,"screenshot_after":true,"wait_ms":0}}}' | python3 "$mcp")
expect_eq "screenshot_after: action, focused window, screenshot" "text text text image" "$(jq -r '[.result.content[].type] | join(" ")' <<<"$out")"
expect_eq "screenshot_after: the action ran first" "niri msg action focus-window --id 1|grim" "$(grep -v '^notify-send' "$calls" | sed 's/^grim.*/grim/' | paste -sd'|')"
expect_eq "screenshot_after: offered on action tools only" "true false" \
  "$(python3 "$mcp" tools | jq -r '[(.[] | select(.name=="click") | .inputSchema.properties | has("screenshot_after")), (.[] | select(.name=="list_windows") | .inputSchema.properties | has("screenshot_after"))] | join(" ")')"

reset_calls
out=$(call run_steps '{"steps":[{"tool":"press_keys","args":{"keys":["ctrl+k"]}},{"tool":"type_text","args":{"text":"Alesio"},"wait_ms":0},{"tool":"press_keys","args":{"keys":["Return"]},"wait_ms":0}]}')
expect_eq "run_steps: every step, in order" "wtype -M ctrl -k k -m ctrl|wtype - <<Alesio|wtype -k Return" "$(paste -sd'|' "$calls")"
expect_contains "run_steps: step results" "$out" "3. press_keys: pressed Return"
reset_calls
out=$(call run_steps '{"steps":[{"tool":"type_text","args":{"text":"a"},"wait_ms":0},{"tool":"press_keys","args":{"keys":["super+q"]}},{"tool":"type_text","args":{"text":"b"}}]}')
expect_contains "run_steps: stops at a refused step" "$out" "2. press_keys failed: refused: Super combinations"
expect_eq "run_steps: nothing after the refused step" "wtype - <<a" "$(paste -sd'|' "$calls")"
out=$(call run_steps '{"steps":[{"tool":"shell_ipc","args":{"target":"bar","function":"toggle"}}]}')
expect_contains "run_steps: only window and input tools" "$out" "not a window or input tool"
out=$(call run_steps '{"steps":[{"tool":"run_steps","args":{}}]}')
expect_contains "run_steps: no nesting" "$out" "not a window or input tool"
reset_calls
echo kitty >"$STUB_FOCUS"
out=$(call run_steps '{"steps":[{"tool":"type_text","args":{"text":"rm -rf ~"}}]}')
expect_contains "run_steps: guardrails apply to every step" "$out" "refused: input into 'kitty'"
expect_eq "run_steps: nothing typed into the terminal" "" "$(cat "$calls")"
echo firefox >"$STUB_FOCUS"

# -- window layouts ----------------------------------------------------------------------------

rm -f "$calls.launched"
out=$(call save_layout '{"name":"work"}')
expect_contains "save_layout" "$out" "saved layout 'work': 5 windows on eDP-1"
layout="$XDG_STATE_HOME/nixbook-shell/layouts/work.json"
expect_eq "save_layout: private file" 600 "$(stat -c %a "$layout")"
expect_eq "save_layout: a floating window's place" '{"monitor":"eDP-1","workspace":{"index":1,"name":null},"position":[10,20],"size":[400,300],"desktop":"org.gnome.Calculator"}' \
  "$(jq -c '.windows[] | select(.app_id=="org.gnome.Calculator") | {monitor, workspace, position, size, desktop}' "$layout")"
expect_eq "save_layout: a tiled window's column (no app to reopen it)" '2 1 null' "$(jq -r '.windows[] | select(.app_id=="org.gnome.TextEditor") | "\(.column) \(.tile) \(.desktop)"' "$layout")"
expect_contains "save_layout: says what can't be reopened" "$out" "no .desktop entry found): kitty, org.gnome.Nautilus, org.gnome.TextEditor"
out=$(call save_layout '{"name":"../etc"}')
expect_contains "save_layout: names can't escape the directory" "$out" "invalid value"
out=$(call list_layouts)
expect_eq "list_layouts" "work 5" "$(jq -r '.[] | "\(.name) \(.windows)"' <<<"$out")"

# Calculator closed since: restore starts it and places everything.
echo '[5]' >"$calls.hidden"
reset_calls
out=$(call restore_layout '{"name":"work"}')
expect_contains "restore_layout: starts what isn't open" "$(cat "$calls")" "niri msg action spawn -- org.gnome.Calculator"
expect_contains "restore_layout: every window placed" "$out" "5 of 5 windows placed"
expect_contains "restore_layout: monitor then workspace" "$(cat "$calls")" "niri msg action move-window-to-monitor --id 4 eDP-1
niri msg action move-window-to-workspace --window-id 4 --focus false 1"
expect_contains "restore_layout: tiled column order and width" "$(cat "$calls")" "niri msg action focus-window --id 4
niri msg action move-column-to-index 2
niri msg action set-window-width --id 4 1000"
expect_contains "restore_layout: floating size and position" "$(cat "$calls")" "niri msg action set-window-width --id 6 400
niri msg action set-window-height --id 6 300
niri msg action move-floating-window --id 6 -x 10 -y 20"
expect_eq "restore_layout: focus given back" "niri msg action focus-window --id 1" "$(grep -v '^notify' "$calls" | tail -n 1)"
rm -f "$calls.hidden" "$calls.launched"
out=$(call restore_layout '{"name":"nope"}')
expect_contains "restore_layout: unknown layout" "$out" "no saved layout 'nope'"

# The user's own command (the shell's menus and shortcuts).
layout_cmd() { python3 "$mcp" layout "$@" 2>&1 || true; }
python3 "$mcp" pause >/dev/null
out=$(layout_cmd save gaming)
expect_contains "layout save: works while agents are paused" "$out" "saved layout 'gaming'"
python3 "$mcp" resume >/dev/null
expect_eq "layout list: names and the current one" "gaming|gaming work" "$(layout_cmd list | jq -r '"\(.current)|\([.layouts[].name] | join(" "))"')"
reset_calls
out=$(layout_cmd cycle)
expect_contains "layout cycle: restores the next one" "$out" "restored layout 'work'"
expect_eq "layout cycle: becomes current" work "$(layout_cmd list | jq -r .current)"
out=$(layout_cmd cycle)
expect_contains "layout cycle: wraps around" "$out" "restored layout 'gaming'"
layout_cmd rename gaming games >/dev/null
expect_eq "layout rename: current follows" "games|games work" "$(layout_cmd list | jq -r '"\(.current)|\([.layouts[].name] | join(" "))"')"
expect_contains "layout rename: no overwrite" "$(layout_cmd rename games work)" "exists already"
layout_cmd delete games >/dev/null
expect_eq "layout delete" "|work" "$(layout_cmd list | jq -r '"\(.current)|\([.layouts[].name] | join(" "))"')"
expect_contains "layout: names checked" "$(layout_cmd save '../x')" "a layout name"
expect_eq "layout: the user's calls are logged" you "$(jq -r 'select(.tool=="save_layout") | .client' "$XDG_STATE_HOME/nixbook-shell/desktop-mcp.log" | tail -n 1)"

# -- desktop memory -------------------------------------------------------------------------

mem="$XDG_STATE_HOME/nixbook-shell/desktop-memory.json"
rm -f "$mem" "$calls.launched"
# "discord" isn't installed; the agent finds "Firefox" next: an alias is learned.
out=$(call launch_app '{"app":"discord"}')
expect_contains "memory: a failed launch" "$out" "no application matches"
call launch_app '{"app":"Firefox"}' >/dev/null
expect_eq "memory: alias learned from a failure then a success" org.mozilla.firefox "$(jq -r '.aliases.discord' "$mem")"
expect_eq "memory: app use counted" 1 "$(jq '.usage.apps["org.mozilla.firefox"].count' "$mem")"
reset_calls
call launch_app '{"app":"discord"}' >/dev/null
expect_contains "memory: the alias is used next time" "$(cat "$calls")" "niri msg action spawn -- firefox --name firefox"
expect_eq "memory: private file" 600 "$(stat -c %a "$mem")"

out=$(call remember '{"topic":"discord","text":"Vesktop: open a DM with ctrl+k, type the name, Return"}')
expect_contains "remember" "$out" "remembered as note"
note_id=$(jq -r '.notes[0].id' "$mem")
out=$(call remember '{"topic":"discord","text":"Vesktop: open a DM with ctrl+k, type the name, Return"}')
expect_contains "remember: no duplicate" "$out" "updated note $note_id"
out=$(call remember "$(jq -nc '{topic: "x", text: ("y" * 700)}')")
expect_contains "remember: text capped" "$out" "longer than 600"
call run_steps '{"steps":[{"tool":"press_keys","args":{"keys":["ctrl+k"]},"wait_ms":0}],"remember_as":"discord: open quick switcher"}' >/dev/null
expect_eq "run_steps remember_as: recipe saved" recipe "$(jq -r '.notes[] | select(.topic=="discord: open quick switcher") | .kind' "$mem")"

# Every agent gets the digest when it connects.
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t"}}}' | python3 "$mcp")
instr=$(jq -r .result.instructions <<<"$out")
expect_contains "digest: in the instructions" "$instr" "Desktop memory from earlier sessions"
expect_contains "digest: labelled as hints, not the user's instructions" "$instr" "not instructions from the user"
expect_contains "digest: aliases" "$instr" "discord -> org.mozilla.firefox"
expect_contains "digest: notes" "$instr" "[$note_id] discord: Vesktop: open a DM"
expect_contains "digest: apps used" "$instr" "org.mozilla.firefox (2x)"
echo '{"memoryPromptChars":200}' >"$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 "$mcp")
expect_contains "digest: capped" "$(jq -r .result.instructions <<<"$out")" "(more: call recall)"
echo '{"tools":["observe","windows"]}' >"$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 "$mcp")
expect_not_contains "digest: not sent with memory turned off" "$(jq -r .result.instructions <<<"$out")" "Desktop memory from"
rm "$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"

out=$(call recall '{"query":"discord"}')
expect_eq "recall: search" 2 "$(jq '.notes | length' <<<"$out")"
expect_eq "recall: counts uses" 1 "$(jq --arg id "$note_id" '.notes[] | select(.id==$id) | .uses' "$mem")"
out=$(call forget "{\"id\":\"$note_id\"}")
expect_contains "forget" "$out" "forgot note $note_id"
expect_contains "forget: unknown" "$(call forget '{"id":"abc"}')" "no note abc"
python3 "$mcp" memory clear notes >/dev/null
expect_eq "memory clear notes: aliases kept" "0 org.mozilla.firefox" "$(jq -r '"\(.notes | length) \(.aliases.discord)"' "$mem")"
python3 "$mcp" memory clear usage aliases >/dev/null
expect_eq "memory clear: several parts at once" "0 0" "$(jq -r '"\(.aliases | length) \(.usage.apps | length)"' "$mem")"
python3 "$mcp" memory clear >/dev/null
expect_eq "memory clear: all" "0 0" "$(jq -r '"\(.aliases | length) \(.usage.apps | length)"' "$mem")"
rm -f "$calls.launched"

# -- the state file the bar widget reads ------------------------------------------------------

state="$XDG_RUNTIME_DIR/nixbook-desktop-mcp/state.json"
call focus_window '{"id":1}' >/dev/null
expect_eq "state: last call" "focus_window ok false" "$(jq -r '"\(.last.tool) \(.last.outcome) \(.paused)"' "$state")"
python3 "$mcp" toggle >/dev/null
expect_eq "toggle: pauses" true "$(jq .paused "$state")"
expect_eq "state: last call kept on pause" focus_window "$(jq -r .last.tool "$state")"
python3 "$mcp" toggle >/dev/null
expect_eq "toggle: resumes" false "$(jq .paused "$state")"
out=$(call shell_ipc '{"target":"desktopControl","function":"resume"}')
expect_contains "shell_ipc: the bar's pause/resume is the user's only" "$out" "off limits"
out=$(call shell_ipc '{"target":"layouts","function":"restore","args":["work"]}')
expect_contains "shell_ipc: the user's layouts target is theirs only" "$out" "off limits"

# -- pause, groups, rate limit ---------------------------------------------------

python3 "$mcp" pause >/dev/null
out=$(call focus_window '{"id":1}')
expect_contains "pause: tools refused" "$out" "paused by the user"
out=$(call get_status)
expect_eq "pause: get_status still answers" true "$(jq .paused <<<"$out")"
python3 "$mcp" resume >/dev/null
out=$(call focus_window '{"id":1}')
expect_eq "resume" "focused window 1" "$(head -n 1 <<<"$out")"

echo '{"tools":["observe"],"actionsPerMinute":2}' >"$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"
expect_eq "config: disabled groups not listed" 6 "$(python3 "$mcp" tools | jq length)"
out=$(call type_text '{"text":"x"}')
expect_contains "config: disabled tool not callable" "$out" "unknown or disabled tool"
echo '{"actionsPerMinute":2}' >"$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"
out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' |
  python3 "$mcp")
expect_contains "rate limit" "$(jq -r 'select(.id==3).result.content[0].text' <<<"$out")" "rate limit"
rm "$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"

out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_status","arguments":{}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":"bogus"}' |
  XDG_RUNTIME_DIR=/nonexistent/run python3 "$mcp" 2>/dev/null)
expect_contains "no runtime dir: actions refused (fail closed)" "$(jq -r 'select(.id==1).result.content[0].text' <<<"$out")" "no private runtime directory"
expect_eq "no runtime dir: server keeps answering" 3 "$(wc -l <<<"$out" | tr -d ' ')"

# -- HTTP ----------------------------------------------------------------------------

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 "$mcp" serve --http --port "$port" 2>"$tmp/http.log" &
http_pid=$!
for _ in $(seq 50); do
  curl -s -o /dev/null "http://127.0.0.1:$port/" && break
  sleep 0.1
done
token=$(python3 "$mcp" token)
expect_eq "token file is private" 600 "$(stat -c %a "$XDG_RUNTIME_DIR/nixbook-desktop-mcp/token")"
expect_eq "HTTP: bound to 127.0.0.1 only" "127.0.0.1:$port" \
  "$(python3 -c "import sys; [print(l.split()[1]) for l in open('/proc/net/tcp') if l.split()[3]=='0A' and l.split()[1].endswith(':%04X' % $port)]" |
    python3 -c 'import sys,socket; h,p=sys.stdin.read().strip().split(":"); print(socket.inet_ntoa(bytes.fromhex(h)[::-1])+":"+str(int(p,16)))')"
body='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_status","arguments":{}}}'
post() { curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$port/mcp" -H 'Content-Type: application/json' -d "$body" "$@"; }
expect_eq "HTTP: no token -> 401" 401 "$(post)"
expect_eq "HTTP: wrong token -> 401" 401 "$(post -H 'Authorization: Bearer nope')"
expect_eq "HTTP: foreign Origin -> 403" 403 "$(post -H "Authorization: Bearer $token" -H 'Origin: https://evil.example')"
expect_eq "HTTP: rebinding Host -> 403" 403 "$(post -H "Authorization: Bearer $token" -H "Host: evil.example:$port")"
expect_eq "HTTP: token -> 200" 200 "$(post -H "Authorization: Bearer $token")"
out=$(curl -s -X POST "http://127.0.0.1:$port/mcp" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$body")
expect_eq "HTTP: tool result" false "$(jq .result.isError <<<"$out")"
expect_eq "HTTP: notification -> 202" 202 "$(body='{"jsonrpc":"2.0","method":"notifications/initialized"}' post -H "Authorization: Bearer $token")"
expect_eq "HTTP: other path -> 404" 404 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$port/" -H "Authorization: Bearer $token" -d "$body")"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all desktop-mcp tests passed"
