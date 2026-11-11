#!/usr/bin/env bash
# Web pages in the shell's colours, in Zen (Settings > Appearance > Color
# generation > Apps > Websites (Zen)):
#   - zen/pages-theme.js under node, with a fake Dark Reader and a fake
#     extension storage: the theme a dark and a light palette give, the
#     accent CSS, turned off, a new palette applied at once;
#   - scripts/zen-bridge.py: its first message to the extension when Zen
#     starts it is the palette apply-app-colors.sh rendered (null without).
# Needs node and python3. Run: bash tests/zen-pages.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /' >&2
  failures=$((failures + 1))
}
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi; }

node_run() {
  if command -v node >/dev/null; then node "$@"; else nix-shell -p nodejs --run "node $(printf '%q ' "$@")"; fi
}

# -- pages-theme.js -------------------------------------------------------------
cat >"$tmp/run.js" <<'EOF'
const fs = require("fs");
const calls = [];
let listener = null;
let stored = JSON.parse(process.argv[3]);
globalThis.DarkReader = {
  on: false,
  enable(theme, fixes) { this.on = true; calls.push({ enable: theme, css: fixes.css }); },
  disable() { this.on = false; calls.push({ disable: true }); },
  isEnabled() { return this.on; },
  setFetchMethod() { calls.push({ fetchMethod: true }); },
};
globalThis.browser = {
  storage: {
    local: { get: async () => ({ pageTheme: stored }) },
    onChanged: { addListener: (f) => { listener = f; } },
  },
  runtime: { sendMessage: async () => ({}) },
};
eval(fs.readFileSync(process.argv[2], "utf8"));
setTimeout(() => {
  const next = JSON.parse(process.argv[4]);
  listener({ pageTheme: { newValue: next } }, "local");
  console.log(JSON.stringify(calls));
}, 20);
EOF
dark='{"enabled":true,"mode":"dark","background":"#040707","text":"#dffcfc","selection":"#00585a","scrollbar":"#1f2b2b","accent":"#31f0f1"}'
light='{"enabled":true,"mode":"light","background":"#fcf9ff","text":"#2d2540","selection":"#e9ddff","scrollbar":"#e6e0e9","accent":"#7d5ad7"}'
out=$(node_run "$tmp/run.js" "$root/zen/pages-theme.js" "$dark" "$light")
expect "pages: a dark palette, Dark Reader's dark mode on its colours" \
  '{"fetchMethod":true}|{"brightness":100,"contrast":100,"sepia":0,"grayscale":0,"selectionColor":"#00585a","scrollbarColor":"#1f2b2b","mode":1,"darkSchemeBackgroundColor":"#040707","darkSchemeTextColor":"#dffcfc"}' \
  "$(python3 -c 'import json,sys; c=json.loads(sys.argv[1]); print(json.dumps(c[0],separators=(",",":"))+"|"+json.dumps(c[1]["enable"],separators=(",",":")))' "$out")"
expect "pages: links and focus rings in the accent" "true" \
  "$(python3 -c 'import json,sys; c=json.loads(sys.argv[1]); print(str("a:link, a:visited { color: #31f0f1 !important; }" in c[1]["css"]).lower())' "$out")"
expect "pages: a new palette (light) applied at once, on its light colours" '0 #fcf9ff #2d2540' \
  "$(python3 -c 'import json,sys; t=json.loads(sys.argv[1])[2]["enable"]; print(t["mode"], t["lightSchemeBackgroundColor"], t["lightSchemeTextColor"])' "$out")"
out=$(node_run "$tmp/run.js" "$root/zen/pages-theme.js" "$dark" '{"enabled":false}')
expect "pages: turned off, Dark Reader off" '{"disable":true}' \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])[-1],separators=(",",":")))' "$out")"
out=$(node_run "$tmp/run.js" "$root/zen/pages-theme.js" 'null' 'null')
expect "pages: nothing stored, nothing done" '[]' "$out"

# -- zen-bridge.py: the palette handed over when Zen starts it ----------------------
first_message() {
  XDG_RUNTIME_DIR="$tmp/run" XDG_STATE_HOME="$tmp/state" python3 - "$root/scripts/zen-bridge.py" <<'EOF'
import json, os, struct, subprocess, sys
os.makedirs(os.environ["XDG_RUNTIME_DIR"], mode=0o700, exist_ok=True)
p = subprocess.Popen([sys.executable, "-I", sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
size = struct.unpack("=I", p.stdout.read(4))[0]
msg = json.loads(p.stdout.read(size))
p.stdin.close()
p.wait(timeout=10)
msg.pop("id", None)
print(json.dumps(msg, separators=(",", ":")))
EOF
}
expect "bridge: no palette rendered, pages left alone" '{"cmd":"theme","theme":null}' "$(first_message)"
mkdir -p "$tmp/state/quickshell/user/generated/apps"
printf '{"mode":"dark","background":"#040707"}' >"$tmp/state/quickshell/user/generated/apps/zen-pages.json"
expect "bridge: the palette rendered last, when Zen starts it" '{"cmd":"theme","theme":{"mode":"dark","background":"#040707"}}' "$(first_message)"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all zen-pages tests passed"
