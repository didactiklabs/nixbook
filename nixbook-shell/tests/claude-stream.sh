#!/usr/bin/env bash
# The side panel's Claude Code stream: no running commentary between steps
# (claude-stream-tests.js, node).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/claude-stream-tests.js"
else
  nix-shell -p nodejs --run "node '$here/claude-stream-tests.js'"
fi
