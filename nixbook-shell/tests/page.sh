#!/usr/bin/env bash
# nixbook's page code (zen/page.js): stable references, finding a re-rendered
# element by its name, change reports (page-tests.js, node).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/page-tests.js"
else
  nix-shell -p nodejs --run "node '$here/page-tests.js'"
fi
