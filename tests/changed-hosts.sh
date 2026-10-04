#!/usr/bin/env bash
# Prints (JSON array) the colmena nodes whose system derivation differs
# between BASE and the working tree, so CI only builds the machines a change
# actually touches (a pin only one machine uses, a profile, docs-only changes).
#
#   tests/changed-hosts.sh [--save FILE] [--base-map FILE] BASE
#
#   BASE              commit to compare against (a PR's base, the previous main)
#   --save FILE       also write the working tree's { node: drv } map to FILE
#   --base-map FILE   BASE's map from an earlier --save, instead of evaluating
#                     BASE again (ignored when FILE does not exist)
#
# A node missing from BASE counts as changed. Evaluation errors exit non-zero:
# the caller then builds every machine, which reports the actual error.
#
# Needs: colmena, git, jq, and /etc/nixos/hardware-configuration.nix (the same
# one for both sides: base.nix imports it, so it is part of every derivation).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NIXPKGS_ALLOW_UNFREE=1

save="" base_map=""
while [ $# -gt 1 ]; do
  case "$1" in
  --save) save="$2" ;;
  --base-map) base_map="$2" ;;
  *) break ;;
  esac
  shift 2
done
base="${1:?usage: tests/changed-hosts.sh [--save FILE] [--base-map FILE] BASE}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# { node: drv } for the hive in $1. Always this checkout's drv-paths.nix, so a
# BASE from before it existed still evaluates.
drv_paths() {
  colmena --config "$1/hive.nix" eval "$repo/tests/drv-paths.nix" | tail -n 1 | jq -ce 'objects'
}

echo "changed-hosts: evaluating the working tree" >&2
head_map=$(drv_paths "$repo")
if [ -n "$save" ]; then printf '%s\n' "$head_map" >"$save"; fi

if [ -n "$base_map" ] && [ -s "$base_map" ]; then
  echo "changed-hosts: $base's derivations from $base_map" >&2
  base_map=$(cat "$base_map")
else
  echo "changed-hosts: evaluating $base" >&2
  git clone --quiet --shared --no-checkout "$repo" "$tmpdir/base"
  git -C "$tmpdir/base" checkout --quiet --detach "$base"
  base_map=$(drv_paths "$tmpdir/base")
fi

jq -cn --argjson head "$head_map" --argjson base "$base_map" '
  $head | to_entries | map(select($base[.key] != .value) | .key)'
