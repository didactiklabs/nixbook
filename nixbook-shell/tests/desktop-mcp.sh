#!/usr/bin/env bash
# Tests for scripts/desktop-mcp.py (nixbook-desktop-mcp), against stub niri,
# wtype, ydotool, grim, wl-copy, notify-send and qs that log their arguments:
#   - the MCP protocol over stdio (initialize, tools/list, tools/call, errors);
#   - each tool's niri/wtype/ydotool command line;
#   - the guardrails: denied windows, Super/VT combos, text cap, rate limit,
#     pause (off by default, persistent), disabled groups, denied IPC targets, no arbitrary commands;
#   - the pointer: the exact Wayland requests sent to a fake compositor
#     (tests/fake-wayland.py), screenshot mappings, the ydotool fallback;
#   - the agent desktop: switching the tools to it and back, starting it;
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
# Which niri it was asked (the user's or the agent desktop's): its socket.
echo "${NIRI_SOCKET:-}" >"$STUB_CALLS.socket"
# The agent desktop has no windows (a launched app opens on the user's), or
# with $STUB_AGENT_HAS_WINDOW one app, and the launched one beside it.
if [ "$1 $2 $3" = "msg --json windows" ] && [ "${NIRI_SOCKET:-}" = "${STUB_AGENT_SOCKET:-}" ]; then
  if [ -n "${STUB_AGENT_HAS_WINDOW:-}" ]; then
    jq -nc --argjson launched "$([ -e "$STUB_CALLS.launched" ] && echo true || echo false)" '
      [{id: 20, app_id: "org.gnome.TextEditor", title: "notes", pid: 50, workspace_id: 1, is_focused: ($launched | not), is_floating: false}]
      + (if $launched then [{id: 21, app_id: "firefox", title: "New Tab", pid: 60, workspace_id: 1, is_focused: true, is_floating: false},
                            {id: 22, app_id: "firefox", title: "Restore session?", pid: 60, workspace_id: 1, is_focused: false, is_floating: true}] else [] end)'
  else
    echo '[]'
  fi
  exit 0
fi
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
      + (if env.STUB_NESTED_WINDOW then [{id: 9, app_id: "niri", title: "niri", pid: 1, workspace_id: 10, is_focused: false, is_floating: false}] else [] end)
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
# PPM: the next of $STUB_FRAMES/1.ppm, 2.ppm… (then the last one again, or
# with $STUB_FRAMES_CYCLE the first), else a grey 64x36. To a file, or "-": stdout.
out="${*: -1}"
[ "$out" != - ] || out=/dev/stdout
if [ "${*: -2:1}" = ppm ]; then
  if [ -n "${STUB_FRAMES:-}" ]; then
    n=$(($(cat "$STUB_FRAMES/n" 2>/dev/null || echo 0) + 1))
    if [ ! -e "$STUB_FRAMES/$n.ppm" ]; then
      if [ -n "${STUB_FRAMES_CYCLE:-}" ]; then n=1; else n=$((n - 1)); fi
    fi
    echo "$n" >"$STUB_FRAMES/n"
    cat "$STUB_FRAMES/$n.ppm" >"$out"
  else
    { printf 'P6\n64 36\n255\n'; head -c $((64 * 36 * 3)) /dev/zero | tr '\0' '\200'; } >"$out"
  fi
else
  printf '\x89PNG fake' >"${*: -1}"
fi
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
# magick: copies its input (a file, or stdin: ppm:-) to its output (the last
# argument; jpeg:- or pgm:-… stdout).
cat >"$bin/magick" <<'EOF'
#!/usr/bin/env bash
echo "magick $*" >>"$STUB_CALLS"
in="$1"
case "$in" in *:-) in=/dev/stdin ;; esac
case "${*: -1}" in *:-) cat "$in" ;; *) cp "$in" "${*: -1}" ;; esac
EOF
# tesseract: words of a 2x capture (TSV): two lines, a low-confidence word, an icon read as noise.
cat >"$bin/tesseract" <<'EOF'
#!/usr/bin/env bash
echo "tesseract $*" >>"$STUB_CALLS"
cat >/dev/null
printf 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
printf '5\t1\t1\t1\t1\t1\t200\t100\t80\t30\t95\tMark\n'
printf '5\t1\t1\t1\t1\t2\t290\t100\t40\t30\t93\tas\n'
printf '5\t1\t1\t1\t1\t3\t340\t100\t60\t30\t91\tRead\n'
printf '5\t1\t2\t1\t1\t1\t1000\t600\t120\t40\t88\tFriends\n'
printf '5\t1\t2\t1\t1\t2\t1130\t600\t40\t40\t20\tzq\n'
printf '5\t1\t3\t1\t1\t1\t50\t50\t10\t10\t70\t@\n'
EOF
cat >"$bin/qs" <<'EOF'
#!/usr/bin/env bash
echo "qs $*" >>"$STUB_CALLS"
# The display it was started on: the user's, even from the agent desktop.
echo "${WAYLAND_DISPLAY:-}" >"$STUB_CALLS.qs_display"
if [ "${*: -1}" = "show" ]; then
  printf 'target sidebarLeft\n  function toggle(): void\ntarget session\n  function open(): void\n'
fi
# The shell's theme target (Themes.qml): the registry, and set.
case "$*" in
  *"theme list"*)
    echo '{"current":"material","variant":"","themeLocked":false,"themes":[
      {"id":"material","name":"Material","variant":"","variantLocked":false,"variants":[]},
      {"id":"persona","name":"Persona","variant":"p5","variantLocked":false,"variants":[{"id":"p5","name":"Persona 5 Royal"},{"id":"p3r","name":"Persona 3 Reload"},{"id":"p4","name":"Persona 4 Revival"}]},
      {"id":"chiikawa","name":"Chiikawa","variant":"chiikawa","variantLocked":false,"variants":[{"id":"momonga","name":"Momonga"},{"id":"usagi","name":"Usagi"},{"id":"chiikawa","name":"Chiikawa"}]}]}' ;;
  *"theme set"*)
    if [ -n "${STUB_THEME_ERROR:-}" ]; then echo "$STUB_THEME_ERROR"; else echo "ok: ${*: -2:1} / ${*: -1}"; fi ;;
  # The desktop widgets' targets (DesktopWidgets.qml, Notes.qml, Todo.qml, TimerService.qml).
  *"widgets list"*)
    echo '[{"name":"clock","enabled":true,"placement":"leastBusy"},{"name":"notes","enabled":false,"placement":"free"},{"name":"worldClock","enabled":false,"placement":"free"}]' ;;
  *"widgets show"* | *"widgets hide"*) echo "ok: ${*: -1} ${*: -2:1}" ;;
  # Notes travel through transfer files (Notes.qml): the text read from the
  # one given ($STUB_CALLS.note), the list written to it.
  *"notes listToFile"*) echo '[{"id":"17-1","content":"buy milk","createdAt":17}]' >"${*: -1}"; echo ok ;;
  *"notes addFromFile"*) cat "${*: -1}" >"$STUB_CALLS.note"; echo "ok: 18-2" ;;
  *"notes updateFromFile"*) cat "${*: -1}" >"$STUB_CALLS.note"; echo "ok: 17-1" ;;
  *"notes remove"*)
    if [ "${*: -1}" = "nope" ]; then echo 'error: no note "nope"'; else echo "ok: 17-1"; fi ;;
  *"todo list"*) echo '{"synced":false,"tasks":[{"index":0,"content":"call mum","done":false,"due":null}]}' ;;
  *"todo "*) echo "ok: call mum" ;;
  *"timers status"*) echo '{"pomodoro":{"running":false},"stopwatch":{"running":false},"countdown":{"running":false,"secondsLeft":0}}' ;;
  *"timers countdownAdd"*) echo "ok: countdown ${*: -1} min" ;;
  *"timers "*) echo "ok: done" ;;
  *"musicRecognition status"*) echo '{"listening":false,"source":"system sound","last":{"title":"Take Flight","subtitle":"SPYAIR"}}' ;;
  *"musicRecognition "*) echo "ok: ${*: -1}" ;;
  *"calendar next"*)
    if [ -n "${STUB_NO_DCAL:-}" ]; then echo "error: DankCalendar (dcal) isn't running"; else
      echo '{"now":"2026-09-30T10:00","next":{"summary":"Standup","start":"2026-09-30T10:30","when":"in 30 min"}}'; fi ;;
  *"calendar upcoming"*) echo "{\"days\":${*: -1},\"events\":[]}" ;;
  *"calendar day"*) echo "{\"date\":\"${*: -1}\",\"events\":[]}" ;;
esac
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
cat >"$tmp/data/applications/kcm_webshortcuts.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Web Search Keywords
Exec=kcmshell6 kcm_webshortcuts
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

# -- paused until first allowed, kept across reboots --------------------------

allowed="$XDG_STATE_HOME/nixbook-shell/desktop-control-allowed"
out=$(call list_windows)
expect_contains "default: paused on a fresh install" "$out" "paused by the user"
expect_eq "default: status says paused" true "$(python3 "$mcp" status | jq .paused)"
python3 "$mcp" resume >/dev/null
expect_eq "resume: persisted in the state directory" 600 "$(stat -c %a "$allowed")"
rm -rf "$XDG_RUNTIME_DIR"
expect_eq "resume: survives a reboot (runtime dir wiped)" false "$(python3 "$mcp" status | jq .paused)"
python3 "$mcp" pause >/dev/null
rm -rf "$XDG_RUNTIME_DIR"
expect_eq "pause: survives a reboot" true "$(python3 "$mcp" status | jq .paused)"
python3 "$mcp" resume >/dev/null

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
expect_eq "tools/list: 34 tools" 34 "$(jq 'select(.id==2).result.tools | length' <<<"$out")"
expect_eq "tools/list: read-only annotation" true "$(jq 'select(.id==2).result.tools[] | select(.name=="list_windows").annotations.readOnlyHint' <<<"$out")"
expect_eq "tools/list: destructive annotation" true "$(jq 'select(.id==2).result.tools[] | select(.name=="close_window").annotations.destructiveHint' <<<"$out")"
expect_eq "tools/call: focus_window succeeds" false "$(jq 'select(.id==3).result.isError' <<<"$out")"
expect_eq "unknown tool: -32602" -32602 "$(jq 'select(.id==4).error.code' <<<"$out")"
expect_eq "unknown method: -32601" -32601 "$(jq 'select(.id==5).error.code' <<<"$out")"
expect_eq "bad JSON: -32700" -32700 "$(jq 'select(.id==null).error.code' <<<"$out")"
expect_eq "screenshot: image content (JPEG)" "image/jpeg" "$(jq -r 'select(.id==6).result.content[1].mimeType' <<<"$out")"
expect_eq "screenshot: scaled to 1568px" "grim -o eDP-1 -s 0.5000 -t ppm" "$(grep '^grim' "$calls" | cut -d' ' -f1-7)"
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

# The agent desktop's restricted connection: a compositor without
# security-context-v1 is an error (exit 1), never a socket of full rights.
status=0
err=$(WAYLAND_DISPLAY=wayland-test python3 "$root/scripts/wayland-security-context.py" "$tmp/restricted.sock" </dev/null 2>&1) || status=$?
expect_eq "security context: refused without the protocol" 1 "$status"
expect_contains "security context: says why" "$err" "has no wp_security_context_manager_v1"
expect_eq "security context: no socket left" absent "$([ -e "$tmp/restricted.sock" ] && echo present || echo absent)"

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

# read_screen: OCR lines at desktop positions (eDP-1: 3136 wide, so captured at 4096/3136, not 2x).
reset_calls
out=$(call read_screen)
expect_eq "read_screen: grey capture, sparse OCR" "grim -o eDP-1 -s 1.3061 -t ppm -|magick ppm:- -colorspace gray pgm:-|tesseract stdin stdout --psm 11 -l eng tsv" "$(paste -sd'|' "$calls")"
expect_contains "read_screen: a line, its middle in desktop pixels" "$out" "230,88 153x23 Mark as Read"
expect_contains "read_screen: low-confidence words left out" "$out" "812,475 92x31 Friends"
expect_not_contains "read_screen: noise left out" "$out" "@"
out=$(call read_screen '{"find":"mark AS"}')
expect_contains "read_screen find: the matching line" "$out" "Mark as Read"
expect_not_contains "read_screen find: only it" "$out" "Friends"
expect_contains "read_screen find: none, said so" "$(call read_screen '{"find":"Settings"}')" "No line on monitor eDP-1 contains 'Settings'"

# -- fewer round trips: screenshot_after, run_steps ---------------------------------------

reset_calls
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1,"screenshot_after":true,"wait_ms":0}}}' | python3 "$mcp")
expect_eq "screenshot_after: action, focused window, screenshot" "text text text image" "$(jq -r '[.result.content[].type] | join(" ")' <<<"$out")"
expect_eq "screenshot_after: the action ran first" "niri msg action focus-window --id 1|grim|magick" "$(grep -v '^notify-send' "$calls" | sed 's/^\(grim\|magick\) .*/\1/' | paste -sd'|')"
# By default, screenshot_after waits until the screen stops changing (tiny captures).
reset_calls
start=$(date +%s%N)
out=$(call focus_window '{"id":1,"screenshot_after":true}')
took=$((($(date +%s%N) - start) / 1000000))
expect_eq "screenshot_after: settles, then the screenshot" "probe probe probe shot" \
  "$(grep '^grim' "$calls" | sed 's/.*-s 0.125 -t ppm -$/probe/; s/^grim .*/shot/' | head -3 | paste -sd' ') $(grep '^grim' "$calls" | tail -1 | sed 's/.*-s 0.125 .*/probe/; s/^grim .*/shot/')"
if [ "$took" -lt 2000 ]; then pass "screenshot_after: a still screen settles fast (${took} ms)"; else fail "screenshot_after: a still screen settles fast" "took ${took} ms"; fi
expect_not_contains "screenshot_after: settled, nothing said" "$out" "still changing"
reset_calls
call run_steps '{"steps":[{"tool":"press_keys","args":{"keys":["Return"]},"settle":true}]}' >/dev/null
expect_contains "run_steps: settle waits for the screen" "$(cat "$calls")" "-s 0.125 -t ppm -"

expect_eq "screenshot_after: offered on action tools only" "true false" \
  "$(python3 "$mcp" tools | jq -r '[(.[] | select(.name=="click") | .inputSchema.properties | has("screenshot_after")), (.[] | select(.name=="list_windows") | .inputSchema.properties | has("screenshot_after"))] | join(" ")')"

# Monitor screenshots after the first: only what changed (eDP-1: 3200x1800 at 0,0, scale 0.5).
frames="$tmp/frames"
mkdir -p "$frames"
python3 - "$frames" <<'PY'
import sys
d = sys.argv[1]
def frame(n, paint=()):
    w, h = 1600, 900
    px = bytearray(b"\x80" * (w * h * 3))
    for x0, y0, x1, y1 in paint:
        for y in range(y0, y1):
            px[(y * w + x0) * 3:(y * w + x1) * 3] = b"\xff" * ((x1 - x0) * 3)
    open(f"{d}/{n}.ppm", "wb").write(b"P6\n1600 900\n255\n" + px)
frame(1)
frame(2)                                          # unchanged
frame(3, [(100, 200, 140, 210)])                  # a small change
frame(4, [(100, 200, 140, 210), (1500, 10, 1510, 20), (800, 800, 810, 810)])  # two more, far apart
frame(5, [(0, 0, 1600, 600)])                     # most of it
PY
reset_calls
out=$(for a in 1:'{}' 2:'{}' 3:'{}' 4:'{}' 5:'{}' 6:'{"full":true}'; do
  printf '{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"screenshot","arguments":%s}}\n' "${a%%:*}" "${a#*:}"
done | STUB_FRAMES="$frames" python3 "$mcp")
expect_eq "screenshot: the first one whole" "text image" "$(jq -r 'select(.id==1) | [.result.content[].type] | join(" ")' <<<"$out")"
expect_eq "screenshot: unchanged, no image" "text" "$(jq -r 'select(.id==2) | [.result.content[].type] | join(" ")' <<<"$out")"
expect_contains "screenshot: unchanged, said so" "$(jq -r 'select(.id==2).result.content[0].text' <<<"$out")" "Nothing changed since your last screenshot"
expect_eq "screenshot: a small change, cropped" "text text image" "$(jq -r 'select(.id==3) | [.result.content[].type] | join(" ")' <<<"$out")"
expect_contains "screenshot: crop mapping, in desktop pixels" "$(jq -r 'select(.id==3).result.content[1].text' <<<"$out")" \
  'Part 72x42 at image (84,184), mapping: {"x": 168.0, "y": 368.0, "scale": 0.5}'
expect_eq "screenshot: two changes apart, two crops" "text text image text image" "$(jq -r 'select(.id==4) | [.result.content[].type] | join(" ")' <<<"$out")"
expect_eq "screenshot: most of it changed, whole" "text image" "$(jq -r 'select(.id==5) | [.result.content[].type] | join(" ")' <<<"$out")"
expect_eq "screenshot: full: true, whole" "text image" "$(jq -r 'select(.id==6) | [.result.content[].type] | join(" ")' <<<"$out")"
expect_eq "screenshot: crops cut by magick" "magick -crop 72x42+84+184|magick -crop 42x36+1484+0|magick -crop 42x42+784+784" \
  "$(grep -o '^magick .* -crop [^ ]*' "$calls" | sed 's/ [^ ]*ppm//' | paste -sd'|')"
rm -f "$frames/n"
out=$(STUB_FRAMES="$frames" STUB_FRAMES_CYCLE=1 call focus_window '{"id":1,"screenshot_after":true}')
expect_contains "screenshot_after: a screen that keeps changing, said so" "$out" "(the screen was still changing after 2.5 s)"

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
# Saved with DP-2 (disconnected now) and a monitor gone from the list: those
# windows stay where niri parked them; the layout isn't overwritten.
jq -c '.name = "docked" | .windows |= map(if .app_id == "org.gnome.TextEditor" then .monitor = "DP-2"
  elif .app_id == "kitty" then .monitor = "DP-3" | .workspace = {index: 1, name: null} else . end)' \
  "$layout" >"$XDG_STATE_HOME/nixbook-shell/layouts/docked.json"
reset_calls
out=$(layout_cmd restore docked)
expect_contains "layout restore, monitors unplugged: says so" "$out" "restored layout 'docked': 3 of 5 windows placed (DP-2, DP-3 not connected: 2 left where they are)"
expect_contains "layout restore, monitors unplugged: which windows" "$out" "left where they are: kitty, org.gnome.TextEditor"
expect_not_contains "layout restore, monitors unplugged: their windows not moved" "$(cat "$calls")" "--id 4"
expect_not_contains "layout restore, monitors unplugged: nor piled onto a workspace" "$(cat "$calls")" "--window-id 2"
expect_contains "layout restore, monitors unplugged: the others placed" "$(cat "$calls")" "move-window-to-monitor --id 1 eDP-1"
expect_contains "layout save, monitors unplugged: not overwritten" "$(layout_cmd save docked)" "has windows on DP-2, DP-3, not connected now"
expect_eq "layout save, monitors unplugged: file kept" DP-2 "$(jq -r '.windows[] | select(.app_id=="org.gnome.TextEditor") | .monitor' "$XDG_STATE_HOME/nixbook-shell/layouts/docked.json")"
# The setting (--close-others): the windows the layout doesn't have close.
jq -c '.name = "browsing" | .windows |= map(select(.app_id == "firefox" or .app_id == "kitty"))' \
  "$layout" >"$XDG_STATE_HOME/nixbook-shell/layouts/browsing.json"
reset_calls
out=$(layout_cmd restore browsing)
expect_not_contains "layout restore: the other windows stay open by default" "$(cat "$calls")" "close-window"
reset_calls
out=$(layout_cmd restore browsing --close-others)
expect_contains "layout restore --close-others: says so" "$out" "restored layout 'browsing': 2 of 2 windows placed, 3 others closed"
expect_contains "layout restore --close-others: which" "$out" "closed: org.gnome.Calculator, org.gnome.Nautilus, org.gnome.TextEditor"
expect_eq "layout restore --close-others: closes them" "3 4 5" "$(grep -o 'close-window --id [0-9]*' "$calls" | awk '{print $3}' | sort | xargs)"
expect_eq "layout restore --close-others: logged" true "$(jq -r 'select(.tool=="restore_layout") | .args.close_others' "$XDG_STATE_HOME/nixbook-shell/desktop-mcp.log" | tail -n 1)"
# After work (the last one) comes browsing.
layout_cmd restore work >/dev/null
reset_calls
out=$(layout_cmd cycle --close-others)
expect_contains "layout cycle --close-others" "$out" "restored layout 'browsing': 2 of 2 windows placed, 3 others closed"
# A monitor of the layout unplugged: which windows were on it can't be told.
jq -c '.name = "browsing-docked" | .windows |= map(if .app_id == "kitty" then .monitor = "DP-3" else . end)' \
  "$XDG_STATE_HOME/nixbook-shell/layouts/browsing.json" >"$XDG_STATE_HOME/nixbook-shell/layouts/browsing-docked.json"
reset_calls
out=$(layout_cmd restore browsing-docked --close-others)
expect_contains "layout restore --close-others, monitor unplugged: says so" "$out" "other windows not closed: DP-3 not connected"
expect_not_contains "layout restore --close-others, monitor unplugged: nothing closed" "$(cat "$calls")" "close-window"
# Not for agents: their restore_layout never closes windows.
reset_calls
out=$(call restore_layout '{"name":"browsing","close_others":true}')
expect_not_contains "restore_layout: agents can't close the other windows" "$(cat "$calls")" "close-window"
layout_cmd delete browsing-docked >/dev/null
layout_cmd delete browsing >/dev/null
layout_cmd delete docked >/dev/null
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

# Notes are linked to the apps they are about (here through the learned alias).
expect_eq "remember: note linked to its app" '["org.mozilla.firefox"]' "$(jq -c --arg id "$note_id" '.notes[] | select(.id==$id) | .apps' "$mem")"
call remember '{"topic":"zen browser","text":"new tab ctrl+t, address bar ctrl+l"}' >/dev/null
call remember '{"topic":"apartment search","text":"edit the URL filters"}' >/dev/null
expect_eq "remember: not linked to an app sharing one word of its name" '[]' "$(jq -c '.notes[] | select(.topic=="apartment search") | .apps' "$mem")"
out=$(call remember '{"topic":"Discord","text":"Vesktop: the member list is ctrl+u"}')
expect_contains "remember: lists the notes already on the topic" "$out" "Other notes on this topic:
- [$note_id] discord: Vesktop: open a DM"
expect_contains "remember: asks to merge them" "$out" "remember with its id"
call forget "$(jq -c '{id: (.notes[] | select(.text | contains("ctrl+u")) | .id)}' "$mem")" >/dev/null
call remember '{"topic":"wifi","text":"quick settings in the right sidebar, Mod+N"}' >/dev/null
call remember '{"topic":"spotify","text":"play/pause with space when focused"}' >/dev/null

# Every agent gets the digest when it connects.
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t"}}}' | python3 "$mcp")
instr=$(jq -r .result.instructions <<<"$out")
expect_contains "digest: in the instructions" "$instr" "Desktop memory (hints written by agents"
expect_contains "digest: labelled as hints, not the user's instructions" "$instr" "not the user's instructions"
expect_contains "digest: aliases" "$instr" "discord -> org.mozilla.firefox"
expect_contains "digest: apps used" "$instr" "org.mozilla.firefox (2x)"
expect_contains "digest: without a task, the most used notes in full" "$instr" "Most used notes:"
expect_contains "digest: the others by topic only" "$instr" "Other notes, by topic (recall a topic for its text):"

# The shell's AI chat says what the task is: the notes about it come in full, the rest by topic.
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | NIXBOOK_DESKTOP_MCP_QUERY="send Alesio a message on Discord" python3 "$mcp")
instr=$(jq -r .result.instructions <<<"$out")
expect_contains "digest: notes about the task" "$instr" "Notes about this task:
- [$note_id] discord: Vesktop: open a DM"
expect_not_contains "digest: unrelated notes not in full" "$instr" "play/pause with space"
expect_contains "digest: unrelated notes by topic" "$instr" "spotify"
# A client that outlives a message (the shell's AI chat): the task from a
# file, rewritten each message; a new one's notes come with the next reply.
task="$tmp/task.txt"
echo "send Alesio a message on Discord" >"$task"
task_call() { printf '{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"get_status","arguments":{}}}\n' "$1"; }
out=$({
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  task_call 2
  sleep 1
  echo "pause the music on spotify" >"$task"
  task_call 3
  task_call 4
} | NIXBOOK_DESKTOP_MCP_QUERY_FILE="$task" python3 "$mcp")
expect_contains "task file: notes in the instructions" "$(jq -r 'select(.id==1).result.instructions' <<<"$out")" "[$note_id] discord: Vesktop"
expect_not_contains "task file: unchanged, nothing more" "$(jq -c 'select(.id==2).result.content' <<<"$out")" "Memory about this task"
expect_contains "task file: a new task's notes with the next reply" "$(jq -r 'select(.id==3).result.content[0].text' <<<"$out")" "Memory about this task:
- ["
expect_contains "task file: the new task's notes" "$(jq -r 'select(.id==3).result.content[0].text' <<<"$out")" "play/pause with space"
expect_not_contains "task file: once" "$(jq -c 'select(.id==4).result.content' <<<"$out")" "Memory about this task"
out=$(python3 "$mcp" memory prompt "open a new tab in zen")
expect_contains "memory prompt QUERY: ranked by topic" "$(sed -n '/Notes about this task/,+1p' <<<"$out")" "zen browser: new tab ctrl+t"

echo '{"memoryPromptChars":200}' >"$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 "$mcp")
digest=$(jq -r .result.instructions <<<"$out" | sed -n '/^Desktop memory/,$p')
# Characters, not bytes (the locale may be C): the digest has "—" and "…".
chars=$(printf '%s' "$digest" | python3 -c 'import sys; print(len(sys.stdin.read()))')
if [ "$chars" -le 200 ]; then pass "digest: capped ($chars chars)"; else fail "digest: capped" "$chars chars:"$'\n'"$digest"; fi
echo '{"tools":["observe","windows"]}' >"$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 "$mcp")
expect_not_contains "digest: not sent with memory turned off" "$(jq -r .result.instructions <<<"$out")" "Desktop memory ("
rm "$XDG_CONFIG_HOME/nixbook-shell/desktop-mcp.json"

# Just in time: the notes about an app come with the action that reaches it, once a session.
out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"focus_window","arguments":{"id":1}}}' |
  python3 "$mcp")
expect_contains "just in time: notes about the focused app" "$(jq -r 'select(.id==1) | .result.content[].text' <<<"$out")" "Memory about Firefox:
- [$note_id] discord: Vesktop"
expect_not_contains "just in time: not twice in a session" "$(jq -r 'select(.id==2) | .result.content[].text' <<<"$out")" "Memory about"
expect_not_contains "just in time: not in the chat's one-off calls" "$(call focus_window '{"id":1}')" "Memory about"

out=$(call recall '{"query":"discord"}')
expect_eq "recall: best matches" 2 "$(jq '.notes | length' <<<"$out")"
# Given with the task's digests (env, then file), just in time, then recalled.
expect_eq "recall: counts uses" 4 "$(jq --arg id "$note_id" '.notes[] | select(.id==$id) | .uses' "$mem")"
# ...and the notes whose topic what it types (a site, a search) or the window title names.
out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_text","arguments":{"text":"search the web"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"type_text","arguments":{"text":"furnished apartments in tokyo"}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"type_text","arguments":{"text":"apartments"}}}' |
  python3 "$mcp")
expect_not_contains "just in time: not for a generic word of a topic" "$(jq -r 'select(.id==1) | .result.content[].text' <<<"$out")" "apartment search"
expect_contains "just in time: notes about what was typed" "$(jq -r 'select(.id==2) | .result.content[].text' <<<"$out")" "Memory about what this reached:
- [$(jq -r '.notes[] | select(.topic=="apartment search") | .id' "$mem")] apartment search: edit the URL filters"
expect_not_contains "just in time: typed-text notes not twice" "$(jq -r 'select(.id==3) | .result.content[].text' <<<"$out")" "Memory about"
out=$(call recall '{"query":"how do I open a tab in the browser"}')
expect_eq "recall: ranked by words, not substrings" "zen browser" "$(jq -r '.notes[0].topic' <<<"$out")"
out=$(call recall '{}')
expect_eq "recall: without a query, the topics only" "true false" "$(jq -r '"\(has("topics")) \(has("notes"))"' <<<"$out")"
expect_contains "recall: nothing" "$(call recall '{"query":"blender"}')" "no note about 'blender'"
out=$(call forget "{\"id\":\"$note_id\"}")
expect_contains "forget" "$out" "forgot note $note_id"
expect_contains "forget: unknown" "$(call forget '{"id":"abc"}')" "no note abc"
# Version 1 linked notes to any app sharing a word with the topic: linked again on load.
jq '.version = 1 | .notes += [{id: "0a0a0a", topic: "apartment search", text: "t", apps: ["kcm_webshortcuts"], uses: 0},
                             {id: "0b0b0b", topic: "firefox tabs", text: "t", apps: [], uses: 0}]' "$mem" >"$mem.new" && mv "$mem.new" "$mem"
call recall '{}' >/dev/null
expect_eq "memory v1: notes linked again" '2 [] ["org.mozilla.firefox"]' \
  "$(jq -r '"\(.version) \(.notes[] | select(.id=="0a0a0a") | .apps | tojson) \(.notes[] | select(.id=="0b0b0b") | .apps | tojson)"' "$mem")"
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

# -- themes and variants ---------------------------------------------------------------------

out=$(call list_themes)
expect_eq "list_themes: from the shell" "material persona chiikawa" "$(jq -r '[.themes[].id] | join(" ")' <<<"$out")"
reset_calls
out=$(call set_theme '{"theme":"Persona","variant":"Persona 3 Reload"}')
expect_eq "set_theme: names resolved to ids" "qs -c nixbook-shell ipc call -- theme set persona p3r" "$(grep 'theme set' "$calls")"
expect_contains "set_theme: reply" "$out" "theme set: persona / p3r"
reset_calls
call set_theme '{"variant":"momonga"}' >/dev/null
expect_eq "set_theme: a variant alone finds its theme" "qs -c nixbook-shell ipc call -- theme set chiikawa momonga" "$(grep 'theme set' "$calls")"
call set_theme '{"variant":"p4"}' >/dev/null
expect_contains "set_theme: variant by id" "$(cat "$calls")" "theme set persona p4"
out=$(call set_theme '{"theme":"gruvbox"}')
expect_contains "set_theme: unknown theme" "$out" "no theme 'gruvbox': material, persona, chiikawa"
out=$(call set_theme '{"theme":"material","variant":"p3r"}')
expect_contains "set_theme: variant of another theme" "$out" "Material has no variant 'p3r'"
out=$(call set_theme '{}')
expect_contains "set_theme: nothing asked" "$out" "or both (see list_themes)"
out=$(STUB_THEME_ERROR="error: the theme is set in the Nix configuration (locked)" call set_theme '{"theme":"persona"}')
expect_contains "set_theme: Nix locks reported" "$out" "set in the Nix configuration (locked)"

# -- desktop widgets -------------------------------------------------------------------

out=$(call widget '{"action":"list"}')
expect_eq "widget list: every widget" "clock notes worldClock" "$(jq -r '[.[].name] | join(" ")' <<<"$out")"
reset_calls
call widget '{"widget":"world clock","action":"show"}' >/dev/null
expect_eq "widget show: name matched ignoring case and spaces" "qs -c nixbook-shell ipc call -- widgets show worldClock" "$(last_call)"
expect_contains "widget show: unknown widget" "$(call widget '{"widget":"aquarium","action":"show"}')" "no widget 'aquarium': clock, notes, worldClock"
out=$(call widget '{"widget":"notes","action":"list"}')
expect_eq "widget notes list" "buy milk" "$(jq -r '.[0].content' <<<"$out")"
reset_calls
out=$(call widget '{"widget":"note","action":"add","text":"--call the bank\nbefore 5pm"}')
expect_eq "widget notes add: the text through a transfer file" "--call the bank
before 5pm" "$(cat "$calls.note")"
expect_contains "widget notes add: only the file's path over IPC" "$(last_call)" "notes addFromFile $XDG_RUNTIME_DIR/nixbook-desktop-mcp/notes-"
expect_eq "widget notes add: the transfer file removed" 0 "$(find "$XDG_RUNTIME_DIR/nixbook-desktop-mcp" -name 'notes-*' | wc -l | tr -d ' ')"
expect_contains "widget notes add: the new id" "$out" "18-2"
long=$(python3 -c 'print("a" * 90000)')
out=$(call widget "{\"widget\":\"notes\",\"action\":\"add\",\"text\":\"$long\"}")
expect_contains "widget notes add: long notes (90000 characters)" "$out" "18-2"
expect_eq "widget notes add: a long note whole" 90000 "$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$calls.note")"
too_long=$(python3 -c 'print("a" * 100001)')
expect_contains "widget notes add: at most 100000 characters" "$(call widget "{\"widget\":\"notes\",\"action\":\"add\",\"text\":\"$too_long\"}")" "100000"
expect_contains "widget todo add: tasks keep the typing cap" "$(call widget "{\"widget\":\"todo\",\"action\":\"add\",\"text\":\"$too_long\"}")" "4000"
call widget '{"widget":"notes","action":"update","id":"17-1","text":"buy oat milk"}' >/dev/null
expect_contains "widget notes update" "$(last_call)" "notes updateFromFile 17-1 $XDG_RUNTIME_DIR/nixbook-desktop-mcp/notes-"
expect_eq "widget notes update: the text" "buy oat milk" "$(cat "$calls.note")"
expect_contains "shell_ipc: the notes' file functions only through the widget tool" \
  "$(call shell_ipc '{"target":"notes","function":"addFromFile","args":["/home/x/.ssh/id_rsa"]}')" "refused"
expect_contains "widget notes: the shell's errors" "$(call widget '{"widget":"notes","action":"remove","id":"nope"}')" 'no note "nope"'
expect_contains "widget notes update: needs text" "$(call widget '{"widget":"notes","action":"update","id":"17-1"}')" "must be a non-empty string"
expect_contains "widget notes: unknown action" "$(call widget '{"widget":"notes","action":"done"}')" "notes can't 'done': list, add, update, remove"
out=$(call widget '{"widget":"tasks","action":"list"}')
expect_eq "widget todo list" "call mum" "$(jq -r '.tasks[0].content' <<<"$out")"
call widget '{"widget":"todo","action":"done","index":0}' >/dev/null
expect_eq "widget todo done: by index" "qs -c nixbook-shell ipc call -- todo done 0" "$(last_call)"
expect_contains "widget todo: index checked" "$(call widget '{"widget":"todo","action":"remove","index":"x"}')" "must be a whole number"
out=$(call widget '{"widget":"timers","action":"list"}')
expect_eq "widget timers: list is status" "false" "$(jq -r '.pomodoro.running' <<<"$out")"
out=$(call widget '{"widget":"pomodoro","action":"countdown_add","minutes":25}')
expect_eq "widget timers countdown_add" "qs -c nixbook-shell ipc call -- timers countdownAdd 25" "$(last_call)"
expect_contains "widget: which widget" "$(call widget '{"action":"add","text":"x"}')" "notes, todo, timers or music"

# Music recognition and the calendar (SongRec.qml, CalendarEvents.qml).
out=$(call widget '{"widget":"shazam","action":"status"}')
expect_eq "widget music status" "Take Flight" "$(jq -r '.last.title' <<<"$out")"
call widget '{"widget":"music","action":"use_microphone"}' >/dev/null
expect_eq "widget music source" "qs -c nixbook-shell ipc call -- musicRecognition useMicrophone" "$(last_call)"
call widget '{"widget":"music recognition","action":"listen"}' >/dev/null
expect_eq "widget music listen" "qs -c nixbook-shell ipc call -- musicRecognition listen" "$(last_call)"
out=$(call calendar '{"action":"next"}')
expect_eq "calendar next" "Standup in 30 min" "$(jq -r '"\(.next.summary) \(.next.when)"' <<<"$out")"
call calendar '{"action":"upcoming"}' >/dev/null
expect_eq "calendar upcoming: a week by default" "qs -c nixbook-shell ipc call -- calendar upcoming 7" "$(last_call)"
call calendar '{"action":"day","date":"2026-10-02"}' >/dev/null
expect_eq "calendar day" "qs -c nixbook-shell ipc call -- calendar day 2026-10-02" "$(last_call)"
expect_contains "calendar: date checked" "$(call calendar '{"action":"day","date":"tomorrow"}')" "invalid value"
expect_contains "calendar: days checked" "$(call calendar '{"action":"upcoming","days":400}')" "from 1 to 60"
expect_contains "calendar: no dcal reported" "$(STUB_NO_DCAL=1 call calendar '{"action":"next"}')" "isn't running"

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

# -- the agent desktop ---------------------------------------------------------------------

# systemctl: starting the agent desktop service does what the launcher does
# (scripts/agent-desktop.sh): sockets up, then the env file.
export STUB_AGENT_SOCKET="$tmp/runtime/niri.wayland-9.1.sock"
cat >"$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$STUB_CALLS"
[ -z "${STUB_SYSTEMCTL_FAIL:-}" ] || { echo "Unit nixbook-agent-desktop.service not found." >&2; exit 5; }
if [ "$2" = start ]; then
  python3 -c 'import os, socket, sys
for p in sys.argv[1:]:
    if os.path.exists(p): os.unlink(p)
    socket.socket(socket.AF_UNIX).bind(p)' "$XDG_RUNTIME_DIR/wayland-9" "$STUB_AGENT_SOCKET"
  mkdir -p "$XDG_RUNTIME_DIR/nixbook-agent-desktop"
  printf 'WAYLAND_DISPLAY=wayland-9\nNIRI_SOCKET=%s\n' "$STUB_AGENT_SOCKET" >"$XDG_RUNTIME_DIR/nixbook-agent-desktop/agent-desktop.env"
fi
EOF
chmod +x "$bin/systemctl"
agent_env="$XDG_RUNTIME_DIR/nixbook-agent-desktop/agent-desktop.env"

expect_eq "desktop: the user's by default" user "$(python3 "$mcp" desktop status | jq -r .desktop)"
reset_calls
python3 "$mcp" desktop agent >/dev/null
expect_eq "desktop agent: persisted" agent "$(python3 "$mcp" desktop status | jq -r .desktop)"
expect_eq "desktop agent: no empty window opened" "" "$(grep systemctl "$calls" || true)"
# Closed while no app is on it: the window tools wait for one, the shell
# tools (the user's notes…) work.
expect_contains "agent desktop closed: window tools wait for an app" "$(call list_windows)" "start the app you need with launch_app"
reset_calls
out=$(call widget '{"widget":"notes","action":"add","text":"flat: 3 rooms, 1200 EUR"}')
expect_eq "agent desktop: notes go to the user's shell" "flat: 3 rooms, 1200 EUR" "$(cat "$calls.note")"
expect_eq "agent desktop: the shell is reached on the user's display" wayland-test "$(cat "$calls.qs_display")"
expect_eq "agent desktop closed: the shell tools don't open it" "" "$(grep systemctl "$calls" || true)"
# launch_app opens it.
out=$(STUB_SYSTEMCTL_FAIL=1 call launch_app '{"app": "firefox"}')
expect_contains "launch_app: says when the agent desktop can't start" "$out" "systemctl --user start"
rm -f "$calls.launched"
reset_calls
out=$(call launch_app '{"app": "firefox"}')
expect_eq "launch_app: opens the agent desktop" "systemctl --user start nixbook-agent-desktop.service" "$(grep systemctl "$calls")"
expect_contains "agent desktop: an app opening on the user's desktop is reported" "$out" "opened its window on the user's desktop"
rm -f "$calls.launched"
call focus_window '{"id": 1}' >/dev/null
expect_eq "agent desktop: tools reach its niri" "$STUB_AGENT_SOCKET" "$(cat "$calls.socket")"
expect_eq "agent desktop: status says so" agent "$(call get_status | jq -r .desktop)"
# Its niri has no virtual pointer here: refused, never ydotool (uinput: the user's desktop).
reset_calls
expect_contains "agent desktop: no ydotool fallback for the pointer" "$(call click '{"x": 10, "y": 10}')" "ydotool would click on the user's desktop"
expect_eq "agent desktop: ydotool never run" "" "$(grep ydotool "$calls" || true)"
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 "$mcp")
expect_contains "agent desktop: agents are told" "$(jq -r .result.instructions <<<"$out")" "You work on a desktop of your own"
expect_contains "agent desktop: no shell panels on the user's screen" \
  "$(call shell_ipc '{"target":"sidebarLeft","function":"toggle"}')" "refused: you work on your own desktop"
# Switching to it while it's open: its window (niri.wayland-9.1.sock: pid 1)
# is focused on the user's niri, so it scrolls into view.
python3 "$mcp" desktop user >/dev/null
reset_calls
STUB_NESTED_WINDOW=1 python3 "$mcp" desktop agent >/dev/null
expect_eq "desktop agent: an open agent desktop is focused" "niri msg action focus-window --id 9" "$(grep focus-window "$calls")"
expect_eq "desktop agent: focused through the user's niri" /dev/null "$(cat "$calls.socket")"
rm -f "$calls.launched"
# One app at a time: the one before closes, the new app's own windows stay.
reset_calls
out=$(STUB_AGENT_HAS_WINDOW=1 call launch_app '{"app": "firefox"}')
expect_contains "agent desktop: launch_app starts the app" "$out" '"started"'
expect_eq "agent desktop: one app at a time, the one before closed" "niri msg action close-window --id 20" "$(grep close-window "$calls")"
expect_eq "agent desktop: an app that won't close (save prompt) is reported" 20 "$(jq '.still_open[0].id' <<<"$out")"
rm -f "$calls.launched"
# The user takes over (to log in somewhere): the agent's input waits.
python3 "$mcp" desktop interact on >/dev/null
expect_eq "desktop interact on: the flag" true "$(python3 "$mcp" desktop status | jq .user_has_control)"
expect_contains "user has control: the agent's input refused" "$(call type_text '{"text": "x"}')" "the user took over your desktop"
expect_contains "user has control: launching refused too" "$(call launch_app '{"app": "firefox"}')" "the user took over your desktop"
expect_contains "user has control: the agent can still look" "$(call screenshot)" "mapping"
expect_eq "user has control: get_status says so" true "$(call get_status | jq .user_has_control)"
python3 "$mcp" desktop interact toggle >/dev/null
expect_eq "desktop interact toggle: given back" false "$(python3 "$mcp" desktop status | jq .user_has_control)"
expect_not_contains "given back: the agent types again" "$(call type_text '{"text": "x"}')" "took over"
# Emptied (its watcher closed it): opened again by the next app.
rm -f "$STUB_AGENT_SOCKET"
reset_calls
expect_contains "agent desktop emptied: window tools wait for an app" "$(call list_windows)" "start the app you need"
call launch_app '{"app": "firefox"}' >/dev/null
expect_eq "agent desktop emptied: the next app opens it again" "systemctl --user start nixbook-agent-desktop.service" "$(grep systemctl "$calls")"
rm -f "$calls.launched"
# Closed by the user (the launcher marks it stopped): every tool refused, not
# opened again by an agent, until the user switches them on again.
echo stopped >"$XDG_STATE_HOME/nixbook-shell/agent-desktop-stopped"
rm -f "$STUB_AGENT_SOCKET"
reset_calls
expect_contains "closed by the user: the agents are stopped" "$(call launch_app '{"app": "firefox"}')" "the user closed your desktop"
expect_contains "closed by the user: the shell tools too" "$(call widget '{"widget":"notes","action":"list"}')" "the user closed your desktop"
expect_eq "closed by the user: not opened again by an agent" "" "$(grep systemctl "$calls" || true)"
expect_eq "closed by the user: status says so" true "$(python3 "$mcp" desktop status | jq .stopped_by_user)"
python3 "$mcp" desktop toggle >/dev/null
expect_eq "closed by the user: the toggle switches them on again" false "$(python3 "$mcp" desktop status | jq .stopped_by_user)"
expect_eq "closed by the user: the toggle stays on their desktop" agent "$(python3 "$mcp" desktop status | jq -r .desktop)"
expect_eq "closed by the user: switching on opens no empty window" "" "$(grep systemctl "$calls" || true)"
reset_calls
python3 "$mcp" desktop stop >/dev/null
expect_eq "desktop stop: stops the service" "systemctl --user stop nixbook-agent-desktop.service" "$(grep systemctl "$calls")"
expect_eq "desktop stop: the agents are stopped" true "$(python3 "$mcp" desktop status | jq .stopped_by_user)"
python3 "$mcp" desktop user >/dev/null
call focus_window '{"id": 1}' >/dev/null
expect_eq "desktop user: tools reach the user's niri again" /dev/null "$(cat "$calls.socket")"
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | python3 "$mcp")
expect_not_contains "desktop user: no agent desktop instructions" "$(jq -r .result.instructions <<<"$out")" "desktop of your own"
# A session that outlives a switch is told on its next reply, once.
mkfifo "$tmp/mcp.in" "$tmp/mcp.out"
python3 "$mcp" <"$tmp/mcp.in" >"$tmp/mcp.out" &
mcp_pid=$!
exec 7>"$tmp/mcp.in" 8<"$tmp/mcp.out"
mcp_send() { printf '%s\n' "$1" >&7 && IFS= read -r line <&8 && printf '%s' "$line"; }
status_call() { mcp_send "{\"jsonrpc\":\"2.0\",\"id\":$1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_status\",\"arguments\":{}}}" | jq -r '.result.content[0].text'; }
mcp_send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' >/dev/null
expect_not_contains "switch: nothing to say while unchanged" "$(status_call 2)" "Desktop switched"
python3 "$mcp" desktop agent >/dev/null
expect_contains "switch to the agent's desktop: the session is told" "$(status_call 3)" "Desktop switched by the user: You work on a desktop of your own"
expect_not_contains "switch to the agent's desktop: told once" "$(status_call 4)" "Desktop switched"
python3 "$mcp" desktop user >/dev/null
expect_contains "switch back to the user's desktop: the session is told" "$(status_call 5)" "Desktop switched by the user: You now work on the user's own desktop"
exec 7>&- 8<&-
wait "$mcp_pid" || true
rm -f "$agent_env" "$STUB_AGENT_SOCKET" "$XDG_RUNTIME_DIR/wayland-9"

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
