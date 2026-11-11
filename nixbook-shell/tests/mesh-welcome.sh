#!/usr/bin/env bash
# The mesh's welcome back in plain code (src/modules/common/functions/
# mesh_welcome.js) under node: mesh-welcome-tests.js.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/mesh-welcome-tests.js"
else
  nix-shell -p nodejs --run "node '$here/mesh-welcome-tests.js'"
fi
