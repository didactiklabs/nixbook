#!/usr/bin/env bash
# devenv's nixpkgs (devenv.yaml + devenv.lock) must be the npins nixpkgs
# (npins/sources.json): CI evaluates and lints with one, the machines build with
# the other. A nixpkgs bump that skipped devenv (a manual `npins update`) left
# main red for days.
#
#   tests/nixpkgs-sync.sh --check   exit 1 when they differ (tests/run.sh repo,
#                                   the pre-commit hook)
#   tests/nixpkgs-sync.sh           make devenv follow npins (rewrites
#                                   devenv.yaml, relocks devenv.lock; needs devenv)
#
# Needs jq.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

npins_rev=$(jq -r .pins.nixpkgs.revision npins/sources.json)
yaml_rev() { sed -n 's|^ *url: github:NixOS/nixpkgs/||p' devenv.yaml; }
lock_rev() { jq -r .nodes.nixpkgs.locked.rev devenv.lock; }

if [ "${1:-}" = --check ]; then
  failed=0
  for file in devenv.yaml devenv.lock; do
    if [ "$file" = devenv.yaml ]; then rev=$(yaml_rev); else rev=$(lock_rev); fi
    if [ "$rev" = "$npins_rev" ]; then
      echo "ok   - $file nixpkgs is the npins nixpkgs ($npins_rev)"
    else
      echo "FAIL - $file nixpkgs $rev != npins nixpkgs $npins_rev: run tests/nixpkgs-sync.sh" >&2
      failed=1
    fi
  done
  exit "$failed"
fi

if [ "$(yaml_rev)" != "$npins_rev" ]; then
  sed -i "s|url: github:NixOS/nixpkgs/.*|url: github:NixOS/nixpkgs/${npins_rev}|" devenv.yaml
fi
if [ "$(lock_rev)" != "$npins_rev" ]; then
  devenv update nixpkgs
fi
exec "$0" --check
