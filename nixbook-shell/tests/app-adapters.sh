#!/usr/bin/env bash
# The Discord, Slack, YouTube Music and YouTube adapters (electron/*.js, the
# discord, slack, youtube_music and youtube tools') and YouTube's styling
# script (electron/youtube.style.js), under node against fakes of each app's
# page client (app-adapters-tests.js).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/app-adapters-tests.js"
else
  nix-shell -p nodejs --run "node '$here/app-adapters-tests.js'"
fi
