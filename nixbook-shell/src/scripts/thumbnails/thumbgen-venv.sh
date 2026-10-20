#!/usr/bin/env bash
# (The Nix build gives the script an interpreter with its modules: no
# virtualenv to activate.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GIO_USE_VFS=local exec "$SCRIPT_DIR/thumbgen.py" "$@"
