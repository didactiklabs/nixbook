# shellcheck shell=bash
# The jq programs below are single-quoted on purpose: `$p`, `$live`, … are jq
# variables, not shell ones.
# shellcheck disable=SC2016
# `nixbook-shell config <command>` — inspect how the live nixbook-shell settings relate to
# the Nix module. Paths are injected by the launcher (customPkgs/nixbook-shell/default.nix):
#   NIXBOOK_SHELL_MERGE_JQ NIXBOOK_SHELL_BUILTIN NIXBOOK_SHELL_LIVE_KEYS
#   NIXBOOK_SHELL_SHELL NIXBOOK_SHELL_QS NIXBOOK_SHELL_QML_PATH (for `builtin`)
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell"
live="$config_dir/config.json"
# Settings set in Nix, as published by the Home Manager module ({} if none).
NIXBOOK_SHELL_PINNED="$config_dir/nix-pinned-values.json"
[ -s "$NIXBOOK_SHELL_PINNED" ] || NIXBOOK_SHELL_PINNED=<(echo '{}')

usage() {
  cat <<'USAGE'
Usage: nixbook-shell config <command>

  diff      Settings changed from the menu: live values that differ from the
            shell's built-in defaults and are not set in Nix, printed as Nix
            lines. Paste them into `nixbookShellConfig.settings` (or the shared
            homeManagerModules/nixbookShellConfig/settings.nix) to set them in Nix —
            they are then locked in the menu.
  pinned    Keys set in Nix (locked in the Settings menu).
  dump      Every live value that differs from the built-in defaults, as a
            Nix attrset (a starting point for settings.nix; `dump --json` for
            JSON).
  builtin   The shell's built-in default config (upstream Config.qml) as
            JSON, minus runtime-owned keys. The `settings` options are
            generated from it: after changing Config.qml, run
              nixbook-shell config builtin > customPkgs/nixbook-shell/builtin-defaults.json
            (needs the graphical session; opens no window).
  path      Print the config and lock-manifest locations.
USAGE
}

builtin_defaults() {
  local pid
  # Global (not local): the EXIT trap runs after this function returns.
  tmp=$(mktemp -d)
  trap 'rm -rf "${tmp:-}"' EXIT
  mkdir -p "$tmp/shell" "$tmp/config" "$tmp/state" "$tmp/cache"
  for e in "$NIXBOOK_SHELL_SHELL"/*; do ln -s "$e" "$tmp/shell/"; done
  rm "$tmp/shell/shell.qml"
  # Only the Config singleton: with no config.json it writes its defaults.
  printf 'import QtQuick\nimport Quickshell\nimport qs.modules.common\nShellRoot {\n    Component.onCompleted: Config.ready\n}\n' >"$tmp/shell/shell.qml"
  XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
    NIXPKGS_QT6_QML_IMPORT_PATH="$NIXBOOK_SHELL_QML_PATH" \
    "$NIXBOOK_SHELL_QS" -p "$tmp/shell" >"$tmp/log" 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do
    [ -s "$tmp/config/nixbook-shell/config.json" ] && break
    sleep 0.2
  done
  sleep 0.3
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  if ! [ -s "$tmp/config/nixbook-shell/config.json" ]; then
    echo "nixbook-shell: the shell wrote no config (needs a graphical session); log:" >&2
    cat "$tmp/log" >&2
    exit 1
  fi
  jq --slurpfile liveKeys "$NIXBOOK_SHELL_LIVE_KEYS" '
    reduce ($liveKeys[0][] | split(".")) as $p (.; delpaths([$p]))' \
    "$tmp/config/nixbook-shell/config.json"
}

if [ "${1:-}" = "builtin" ]; then
  builtin_defaults
  exit
fi

[ -s "$live" ] || {
  echo "nixbook-shell: $live does not exist yet" >&2
  exit 1
}

# Live leaves that differ from the built-in defaults, minus liveKeys.
changed='
  include "config-merge";
  $liveKeys[0] as $skip
  | [ $live[0] | leaves ]
  | map(select((join(".")) as $k | ($skip | any(. as $s | $k == $s or ($k | startswith($s + "."))) | not)))
  | map(select(. as $p | ($builtin[0] | at($p)) != ($live[0] | at($p))))'

jqc() {
  jq -rn -L "$(dirname "$NIXBOOK_SHELL_MERGE_JQ")" \
    --slurpfile live "$live" \
    --slurpfile builtin "$NIXBOOK_SHELL_BUILTIN" \
    --slurpfile pinned "$NIXBOOK_SHELL_PINNED" \
    --slurpfile liveKeys "$NIXBOOK_SHELL_LIVE_KEYS" "$@"
}

cmd="${1:-diff}"
case "$cmd" in
diff)
  jqc "$changed"'
    | map(select(. as $p | ($pinned[0] | at($p)) == null) | . as $p | nixline($p; $live[0] | at($p)))
    | if length == 0 then "# no menu changes outside Nix" else
        ("# " + (length | tostring) + " setting(s) changed from the menu, not set in Nix:"), .[]
      end'
  ;;
pinned)
  jq -r -L "$(dirname "$NIXBOOK_SHELL_MERGE_JQ")" 'include "config-merge"; [leaves | join(".")] | sort[]' "$NIXBOOK_SHELL_PINNED"
  ;;
dump)
  if [ "${2:-}" = "--json" ]; then
    jqc "$changed"' | reduce .[] as $p ({}; setpath($p; $live[0] | getpath($p)))'
  else
    echo "# nixbook-shell settings that differ from the built-in defaults — see homeManagerModules/nixbookShellConfig/settings.nix."
    jqc "$changed"' | reduce .[] as $p ({}; setpath($p; $live[0] | getpath($p))) | nixpp("")'
  fi
  ;;
path)
  echo "config:   $live"
  echo "manifest: $config_dir/nix-managed.json"
  echo "values:   $config_dir/nix-pinned-values.json"
  ;;
-h | --help | help) usage ;;
*)
  usage >&2
  exit 1
  ;;
esac
