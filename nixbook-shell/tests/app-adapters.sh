#!/usr/bin/env bash
# The Discord, Slack and YouTube Music adapters (electron/*.js, the
# discord, slack and youtube_music tools') under node against fakes of each
# app's page client (app-adapters-tests.js).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/app-adapters-tests.js"
else
  nix-shell -p nodejs --run "node '$here/app-adapters-tests.js'"
fi
