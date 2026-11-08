#!/usr/bin/env bash
# Project contexts (scripts/desktop-mcp.py: the project tool and the
# `project` command), against a fake niri, Zen bridge,
# shell and model (tests/projects-tests.py), plus the bubble's plain-code
# phrases for them (src/modules/common/functions/project_intent.js, node):
#   - a project saved: its hidden layout, the tabs of its Zen window (not
#     pinned, private or another workspace's), its options; 0600;
#   - opened: the layout, the tabs not open (in the background), DND and
#     the focus timer; nothing opened twice; Zen started for its tabs;
#   - paused: saved, then its rule (tabs), DND and the timer back as they
#     were;
# Needs bash, python3 and node. Run: bash tests/projects.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/state" "$tmp/cfg/nixbook-shell" "$tmp/run" "$tmp/home" "$tmp/data/applications"
chmod 700 "$tmp/run"
export XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/cfg" XDG_RUNTIME_DIR="$tmp/run" HOME="$tmp/home"
export XDG_DATA_HOME="$tmp/data" XDG_DATA_DIRS="$tmp/none"
unset NIXBOOK_DESKTOP_MCP_CONFIG
unset NIRI_SOCKET

status=0
python3 -I "$root/tests/projects-tests.py" "$root/scripts/desktop-mcp.py" || status=1
if command -v node >/dev/null; then
  node "$root/tests/project-intent-tests.js" || status=1
else
  nix-shell -p nodejs --run "node '$root/tests/project-intent-tests.js'" || status=1
fi
exit "$status"
