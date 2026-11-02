#!/usr/bin/env bash
# The Actual Budget adapter (electron/actual.js, the `budget` tool's) under
# node against a fake of Actual's page client: summaries, categories by a
# loose name, transactions, balances, and read-only (actual-tests.js).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/actual-tests.js"
else
  nix-shell -p nodejs --run "node '$here/actual-tests.js'"
fi
