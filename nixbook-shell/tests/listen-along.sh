#!/usr/bin/env bash
# Listening along's plain code (src/modules/common/functions/track_match.js)
# under node: listen-along-tests.js.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/listen-along-tests.js"
else
  nix-shell -p nodejs --run "node '$here/listen-along-tests.js'"
fi
