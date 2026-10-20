#!/usr/bin/env bash
# (The Nix build gives the script an interpreter with its modules: no
# virtualenv to activate.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/find_regions.py" "$@"
