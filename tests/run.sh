#!/usr/bin/env bash
# Cheap regression checks: everything here evaluates, only tiny derivations
# are built. See the "Tests" section of README.md.
#
#   tests/run.sh repo                  repository consistency, custom packages, lib unit tests
#   tests/run.sh shell                 nixbook-shell script tests
#   tests/run.sh iso                   the installer ISO evaluates
#   tests/run.sh docs                  docs/MODULES.md lists the modules' current options
#   tests/run.sh hosts                 print the hive's node names (JSON)
#   tests/run.sh host NAME [--all-modules]
#                                      evaluate a machine + check its invariants
#   tests/run.sh all                   everything above, every host
#
# Needs: nix, jq, yq (mikefarah), python3; `host` also needs colmena and an
# /etc/nixos/hardware-configuration.nix (on a non-NixOS machine or a CI
# runner, install tests/hardware-configuration.nix there).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
export NIXPKGS_ALLOW_UNFREE=1

need() {
  local missing=()
  for tool in "$@"; do command -v "$tool" >/dev/null || missing+=("$tool"); done
  if [ ${#missing[@]} -ne 0 ]; then
    echo "tests/run.sh: missing tools: ${missing[*]} (run inside \`devenv shell\`)" >&2
    exit 2
  fi
}

# Evaluation warnings become GitHub annotations in CI (stderr is passed on).
annotate() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    sed -E 's/^evaluation warning: (.*)$/::warning title=Evaluation warning::\1/'
  else
    cat
  fi
}

section() {
  echo
  echo "== $*"
}

cmd_repo() {
  need nix-instantiate jq yq
  local failed=0 check

  section "repo: consistency and nixbook-shell lib.nix unit tests"
  for check in machines orphans shellLib; do
    if nix-instantiate --eval --strict --json tests/repo.nix -A "$check" >/dev/null 2> >(annotate >&2); then
      echo "ok   - $check"
    else
      echo "FAIL - $check" >&2
      failed=1
    fi
  done

  section "repo: every custom package instantiates"
  local pkg
  for pkg in $(nix-instantiate --eval --strict --json -E 'builtins.attrNames (import ./tests/repo.nix).packages' | jq -r '.[]'); do
    if nix-instantiate --eval --strict tests/repo.nix -A "packages.$pkg" >/dev/null 2>"$tmpdir/pkg.err"; then
      echo "ok   - customPkgs/$pkg"
    else
      echo "FAIL - customPkgs/$pkg" >&2
      grep -E '^\s*error:' "$tmpdir/pkg.err" | sed 's/^/       /' >&2
      failed=1
    fi
  done

  section "repo: CI and devenv agree with the hive and npins"
  local nodes matrix job
  nodes=$(nix-instantiate --eval --strict --json tests/repo.nix -A hiveNodes | jq -c 'sort')
  for job in build push-cache; do
    matrix=$(yq -o=json ".jobs.\"$job\".strategy.matrix.profile" .github/workflows/build.yaml | jq -c 'sort')
    if [ "$matrix" = "$nodes" ]; then
      echo "ok   - build.yaml $job matrix builds every hive node"
    else
      echo "FAIL - build.yaml $job matrix $matrix != hive nodes $nodes" >&2
      failed=1
    fi
  done
  local npins_rev devenv_rev
  npins_rev=$(jq -r .pins.nixpkgs.revision npins/sources.json)
  devenv_rev=$(yq -r '.inputs.nixpkgs.url' devenv.yaml | sed 's|.*/||')
  if [ "$npins_rev" = "$devenv_rev" ]; then
    echo "ok   - devenv.yaml nixpkgs is the npins nixpkgs ($npins_rev)"
  else
    echo "FAIL - devenv.yaml nixpkgs $devenv_rev != npins nixpkgs $npins_rev" >&2
    failed=1
  fi
  return "$failed"
}

cmd_shell() {
  need nix-instantiate jq python3
  section "nixbook-shell scripts"
  bash tests/nixbook-shell.sh
}

cmd_iso() {
  need nix-instantiate
  section "installer ISO evaluates"
  nix-instantiate default.nix -A buildIso --add-root "$tmpdir/iso.drv" --indirect 2> >(annotate >&2)
}

cmd_docs() {
  need nix-build
  section "docs/MODULES.md is up to date"
  nix-build docs/generate-docs.nix -o "$tmpdir/docs" >/dev/null 2> >(annotate >&2)
  # Compare the structure (modules, options, types, defaults), not the prose,
  # and ignore whitespace and escapes: the committed file went through
  # prettier, whose output changes with its version.
  structure() { grep -E '^(#|- \*\*(Type|Default):)' "$1" | sed 's/[[:blank:]\\]//g'; }
  if diff -u <(structure docs/MODULES.md) <(structure "$tmpdir/docs/MODULES.md") >&2; then
    echo "ok   - every option is documented as currently defined"
  else
    # shellcheck disable=SC2016 # backticks are Markdown, not a substitution
    echo 'FAIL - docs/MODULES.md is stale: run `generate-docs` in `devenv shell` and commit the result' >&2
    return 1
  fi
}

cmd_hosts() {
  need nix-instantiate
  nix-instantiate --eval --strict --json tests/repo.nix -A hiveNodes
}

cmd_host() {
  local host="${1:?usage: tests/run.sh host NAME [--all-modules]}" all=false
  [ "${2:-}" = "--all-modules" ] && all=true
  need colmena nix-store jq
  if [ ! -e /etc/nixos/hardware-configuration.nix ]; then
    echo "tests/run.sh: /etc/nixos/hardware-configuration.nix is missing; for an evaluation-only machine:" >&2
    echo "  sudo install -D -m 644 tests/hardware-configuration.nix /etc/nixos/hardware-configuration.nix" >&2
    exit 2
  fi

  section "host $host$([ "$all" = true ] && echo " (all optional modules on)"): evaluate + invariants"
  local result
  result=$(colmena eval -E "import $repo/tests/hosts.nix { host = \"$host\"; allModules = $all; }" \
    2> >(annotate >&2) | tail -n 1)
  jq -r '"toplevel: \(.toplevel)", (.warnings[] | "NixOS warning: \(.)")' <<<"$result"
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    jq -r '.warnings[] | "::warning title=NixOS warning ('"$host"')::\(.)"' <<<"$result"
  fi

  section "host $host: build generated files"
  local drvs
  mapfile -t drvs < <(jq -r '.cheapBuilds[]' <<<"$result")
  nix-store --realise "${drvs[@]}" --add-root "$tmpdir/cheap" --indirect >/dev/null
  local drv out
  for drv in "${drvs[@]}"; do
    out=$(nix-store --query --outputs "$drv")
    case "$drv" in
    *projectGit.json.drv)
      # /etc/nixos/version: osupdate reads `.rev` from it.
      jq -e '.rev | type == "string" and length > 0' "$out" >/dev/null ||
        {
          echo "FAIL - /etc/nixos/version has no rev: $(cat "$out")" >&2
          return 1
        }
      ;;
    *.json.drv) jq -e . "$out" >/dev/null || {
      echo "FAIL - $out is not valid JSON" >&2
      return 1
    } ;;
    esac
    echo "ok   - ${out#/nix/store/*-}"
  done
}

cmd_all() {
  local failed=0 host
  cmd_repo || failed=1
  cmd_shell || failed=1
  cmd_iso || failed=1
  cmd_docs || failed=1
  for host in $(cmd_hosts | jq -r '.[]'); do
    cmd_host "$host" || failed=1
  done
  cmd_host "$(cmd_hosts | jq -r '.[0]')" --all-modules || failed=1
  return "$failed"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

case "${1:-}" in
repo | shell | iso | docs | hosts | all) "cmd_$1" ;;
host)
  shift
  cmd_host "$@"
  ;;
*)
  # Usage: the header comment.
  awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" >&2
  exit 2
  ;;
esac
