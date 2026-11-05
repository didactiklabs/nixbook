#!/usr/bin/env bash
# The config assistant's answers: a long how-to doesn't win on scattered
# words, a request to do something isn't answered with a how-to
# (config-assistant-tests.js, node).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/config-assistant-tests.js"
else
  nix-shell -p nodejs --run "node '$here/config-assistant-tests.js'"
fi
