#!/usr/bin/env bash
# Tests for the Kiroshi scan (desktop-mcp.py's `kiroshi scan`), against a
# stub Claude Code that answers each pass from what it is asked: the waves
# (brief, labels, one detail per item, the order), the boxes checked, the
# offers filtered (unknown tools, one-click work, a notification that isn't
# there, one dismissed alone), a reply waiting for Send, the offers taken
# read back, the image sent first, and no scan with AI off.
# Needs bash, python3 and jq. Run: bash tests/kiroshi.sh
set -euo pipefail
export NIXBOOK_PRIVACY_PSEUDONYMS=0
export -n out 2>/dev/null || true

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mcp="$root/scripts/desktop-mcp.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

bin="$tmp/bin"
mkdir -p "$bin" "$tmp/runtime" "$tmp/state" "$tmp/config/nixbook-shell" "$tmp/data"
export XDG_RUNTIME_DIR="$tmp/runtime" XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/config"
export XDG_DATA_HOME="$tmp/data" XDG_DATA_DIRS="$tmp/none" STUB_LOG="$tmp/claude"
mkdir -p "$STUB_LOG"

# Claude Code: each pass told apart by its task, its input kept.
cat >"$bin/claude" <<'EOF'
#!/usr/bin/env python3
import json, os, sys, time
msg = json.loads(sys.stdin.readline())
content = msg["message"]["content"]
task = content[-1]["text"]
log = os.environ["STUB_LOG"]
kind = ("brief" if "doing = one line" in task else "labels" if "Label the 3 to 8" in task
        else "item" + task.split("Now only item ")[1].split(" ")[0] if "Now only item " in task else "other")
with open(os.path.join(log, kind), "w") as f:
    json.dump({"argv": sys.argv[1:], "content": content}, f)
answers = {
    "brief": {"doing": "Planning the release with Anna", "focus": "Anna asks for the date"},
    "labels": {"items": [
        {"label": "Anna's message", "kind": "message", "box": [100, 50, 300, 80], "urgency": "now", "gist": "When is the release?"},
        {"label": "Build failed", "kind": "error", "box": [500, 400, 700, 600], "urgency": "soon", "gist": "nix build fails"},
        {"label": "Ad", "kind": "notification", "box": [9999, 10, 50, 50], "urgency": "noise", "gist": "A sale"},
        {"label": "no box", "kind": "text", "box": [1, 2], "urgency": "now", "gist": "dropped"}],
        "routine": [2, 7]},
    "item0": {"facts": ["Anna asks when the release is"], "why": "She waits", "next": "Answer her", "options": [
        {"title": "Reply with the date", "saves": "~1 min", "value": 3, "kind": "quick", "tool": "notification_action",
         "args": {"id": 7, "reply": "Friday the 31st"}},
        {"title": "Reply to an old one", "value": 3, "kind": "quick", "tool": "notification_action",
         "args": {"id": 99, "reply": "x"}},
        {"title": "Add a task", "saves": "~1 min · 5 clicks", "value": 2, "kind": "quick", "tool": "tasks",
         "args": {"title": "Ship the release", "due": "2026-10-31"}},
        {"title": "Run a command", "value": 3, "kind": "quick", "tool": "type_text", "args": {"text": "rm -rf ~"}}]},
    "item1": {"facts": ["nix build fails on hash mismatch"], "why": "", "next": "Update the hash", "options": [
        {"title": "Open the log", "value": 2, "kind": "agent", "plan": ["open it"], "instruction": "Open the log"},
        {"title": "Fix the hash", "saves": "~5 min", "value": 3, "kind": "agent",
         "plan": ["Read the error", "Put the new hash in the .nix file"], "draft": "",
         "instruction": "Update the vendorHash in nixbook-shell/accounts.nix to the one nix printed"},
        {"title": "A task due someday", "value": 2, "kind": "quick", "tool": "tasks", "args": {"title": "x", "due": "someday"}}]},
    "item2": {"facts": ["A sale"], "options": [
        {"title": "Clear it", "value": 2, "kind": "quick", "tool": "dismiss_notifications", "args": {"ids": [8]}},
        {"title": "Clear the ads", "value": 2, "kind": "quick", "tool": "dismiss_notifications", "args": {"ids": [7, 8]}}]},
}
if os.environ.get("STUB_FAIL_LABELS") and kind == "labels":
    print(json.dumps({"type": "result", "is_error": True, "result": "overloaded"}))
    sys.exit(1)
time.sleep(0.05)
print(json.dumps({"type": "system", "subtype": "init"}))
print(json.dumps({"type": "result", "is_error": False, "result": "```json\n" + json.dumps(answers.get(kind, {})) + "\n```"}))
EOF
chmod +x "$bin/claude"

# A 1280x800 PNG (only its header is read for the size).
python3 - "$tmp/shot.png" <<'EOF'
import struct, sys, zlib
w, h = 1280, 800
raw = b"".join(b"\x00" + b"\x00" * (w * 3) for _ in range(h))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
EOF

req() {
  jq -n --arg img "$tmp/shot.png" --arg claude "$bin/claude" '{mode: "scan", lang: "en", claude: $claude, image: $img,
    context: {app: "vesktop", title: "Anna — Discord"},
    windows: [{app: "vesktop", title: "Anna — Discord"}, {app: "kitty", title: "nix build"}],
    notifications: [{id: 7, time: "10:02", app: "Vesktop", summary: "Anna", body: "When is the release?", actions: [], canReply: true},
                    {id: 8, time: "09:40", app: "Shop", summary: "Sale", body: "50% off", actions: ["Open"], canReply: false}],
    events: [{when: "Friday 10:00", summary: "Release", location: "", meeting: true}], recent: []}' >"$tmp/req.json"
}
req
python3 "$mcp" kiroshi taken '{"title": "Add a task", "on": "a request in Slack", "app": "slack"}'
out=$(python3 "$mcp" kiroshi scan "$tmp/req.json")
ev() { jq -c --arg t "$1" 'select(.type == $t)' <<<"$out"; }

# The brief and the labels come in parallel; the items after the labels,
# then their order, then done.
types=$(jq -r '.type' <<<"$out" | grep -v '^brief$' | tr '\n' ' ' | sed 's/ $//')
expect_eq "waves: labels, each item, the order" "start scan item item item ranked done" "$types"
expect_eq "brief" "Planning the release with Anna|Anna asks for the date" "$(ev brief | jq -r '.doing + "|" + .focus')"
scan=$(ev scan)
expect_eq "scan: the image's size" "1280x800" "$(jq -r '"\(.width)x\(.height)"' <<<"$scan")"
expect_eq "scan: an item without a box dropped" "3" "$(jq '.items | length' <<<"$scan")"
expect_eq "scan: [x1, y1, x2, y2] read as a box" "[500,400,200,200]" "$(jq -c '.items[1].box' <<<"$scan")"
expect_eq "scan: a box kept on the image" "1279" "$(jq '.items[2].box[0]' <<<"$scan")"
expect_eq "scan: routine indexes that exist" "[2]" "$(jq -c '.routine' <<<"$scan")"
item() { ev item | jq -c --argjson i "$1" 'select(.index == $i)'; }
i0=$(item 0)
expect_eq "options: unknown tools and absent notifications dropped" "Reply with the date|Add a task" \
  "$(jq -r '[.options[].title] | join("|")' <<<"$i0")"
expect_eq "options: a reply waits for Send, its draft editable" "true|Friday the 31st|reply" \
  "$(jq -r '.options[0] | "\(.confirm)|\(.draft)|\(.draftKey)"' <<<"$i0")"
expect_eq "options: a fixed argument filled in" "create" "$(jq -r '.options[1].args.action' <<<"$i0")"
i1=$(item 1)
expect_eq "options: one-click work and bad dates dropped" "Fix the hash" "$(jq -r '[.options[].title] | join("|")' <<<"$i1")"
expect_contains "options: the best agent one is its handle" "$(jq -r '.handle.instruction' <<<"$i1")" "vendorHash"
expect_eq "options: never one notification cleared alone" "Clear the ads" "$(item 2 | jq -r '[.options[].title] | join("|")')"
expect_eq "ranked: value × urgency, best first" "[0,1,2]" "$(ev ranked | jq -c '.order')"
expect_eq "ranked: routine ones with an option worth it" "[2]" "$(ev ranked | jq -c '.routine')"

labels="$STUB_LOG/labels"
expect_eq "the image first" "image|image/png" "$(jq -r '.content[0] | "\(.type)|\(.source.media_type)"' "$labels")"
expect_contains "the context: the windows" "$(jq -r '.content[1].text' "$labels")" "kitty — nix build"
expect_contains "the context: a notification with its id" "$(jq -r '.content[1].text' "$labels")" "#7 [10:02] Vesktop · Anna: When is the release? (can reply)"
expect_contains "the context: the next event" "$(jq -r '.content[1].text' "$labels")" "Friday 10:00: Release (video call)"
expect_contains "Claude Code without tools or servers" "$(jq -r '.argv | join(" ")' "$labels")" "--tools  --model sonnet"
expect_contains "the offers taken, read back" "$(jq -r '.content[2].text' "$STUB_LOG/item0")" "- Add a task (for: a request in Slack)"
expect_contains "only the tools there are offered" "$(jq -r '.content[2].text' "$STUB_LOG/item0")" "  - notification_action"
expect_eq "taken: listed" "- Add a task (for: a request in Slack)" "$(python3 "$mcp" kiroshi taken)"

out=$(STUB_FAIL_LABELS=1 python3 "$mcp" kiroshi scan "$tmp/req.json" || true)
expect_contains "a failed pass: said" "$(ev error | jq -r .error)" "overloaded"
expect_eq "a failed pass: done" "1" "$(ev "done" | wc -l | tr -d ' ')"
echo '{"policies": {"ai": 0}}' >"$XDG_CONFIG_HOME/nixbook-shell/config.json"
out=$(python3 "$mcp" kiroshi scan "$tmp/req.json" || true)
expect_eq "AI off: no scan" "no Claude Code (or AI is off)" "$(ev error | jq -r .error)"
rm "$XDG_CONFIG_HOME/nixbook-shell/config.json"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all kiroshi tests passed"
