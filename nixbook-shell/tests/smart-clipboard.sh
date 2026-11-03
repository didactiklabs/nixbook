#!/usr/bin/env bash
# The smart clipboard's classifier (src/modules/common/functions/
# clipboard_kinds.js, QML's `.pragma library` JavaScript) under node: the
# kinds in the four languages, the negatives, secrets never offered, and
# its speed. A fixed time zone: the dates are checked to the minute.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  TZ=Europe/Paris node "$here/smart-clipboard-tests.js"
else
  TZ=Europe/Paris nix-shell -p nodejs --run "node '$here/smart-clipboard-tests.js'"
fi
