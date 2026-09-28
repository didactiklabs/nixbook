#!/usr/bin/env bash
# nixbook-shell performance test: the shell in a headless compositor, once per
# theme, measured the same way every time.
#
#   bash nixbook-shell/tests/perf.sh [--package PATH] [--idle SECONDS] [--json FILE]
#   (tests/run.sh shell-perf)
#
# Per theme (Material, Persona 5 Royal, Chiikawa):
#   startup  ms from launch until the QML is loaded ("Configuration Loaded")
#   cpu      idle CPU (% of one core) over --idle seconds, after 20 s to settle
#   rss      resident memory (MB) at the end
# score = 1000 / mean(startup_s + cpu_% + rss_MB / 100), higher is better.
#
# Everything runs from Nix (sway, dbus, fonts: the pinned nixpkgs), in a
# throwaway home and a short-lived Wayland socket, with Qt's software renderer
# (no GPU needed): compare scores taken on the same machine only. Needs nix
# and ~3 minutes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package=""
idle=30
json=""
while [ $# -gt 0 ]; do
  case "$1" in
  --package)
    package="$2"
    shift 2
    ;;
  --idle)
    idle="$2"
    shift 2
    ;;
  --json)
    json="$2"
    shift 2
    ;;
  *)
    echo "perf.sh: unknown argument $1" >&2
    exit 2
    ;;
  esac
done

nixpkgs=$(nix-instantiate --eval -E "(import $here/npins).nixpkgs.outPath" | tr -d '"')
build() { nix-build --no-out-link -E "$1" 2>/dev/null | tail -1; }
[ -n "$package" ] || package=$(build "(import $here/. {}).package")
tools=$(build "let p = import $nixpkgs {}; in p.symlinkJoin { name = \"nixbook-shell-perf-tools\"; paths = [ p.sway p.dbus p.coreutils p.procps p.jq ]; }")
fonts=$(build "let p = import $nixpkgs {}; in p.makeFontsConf { fontDirectories = [ p.roboto p.oswald p.nunito p.dejavu_fonts ]; }")
export PATH="$tools/bin:$PATH"

work=$(mktemp -d)
run=$(mktemp -d /tmp/nbperf.XXXXXX) # short: the sway IPC socket path is limited
chmod 700 "$run"
cleanup() {
  [ -n "${shell_pid:-}" ] && kill "$shell_pid" 2>/dev/null || true
  [ -n "${sway_pid:-}" ] && kill "$sway_pid" 2>/dev/null || true
  sleep 1
  chmod -R u+w "$work" "$run" 2>/dev/null || true
  rm -rf "$work" "$run"
}
trap cleanup EXIT

home="$work/home"
mkdir -p "$home/.config/sway" "$home/.config/nixbook-shell" "$home/.local/state/quickshell/user"
echo "output HEADLESS-1 resolution 1920x1080" >"$home/.config/sway/config"
# The QML tree, where Home Manager links it (`qs -c nixbook-shell`).
mkdir -p "$home/.config/quickshell"
ln -s "$(grep -o '/nix/store/[^ ]*-nixbook-shell-vendored-[^/ ]*' "$package/bin/nixbook-shell" | head -1)" \
  "$home/.config/quickshell/nixbook-shell"
# No first-run welcome window.
echo x >"$home/.local/state/quickshell/user/first_run.txt"

export HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
  XDG_CACHE_HOME="$home/.cache" XDG_DATA_HOME="$home/.local/share" XDG_RUNTIME_DIR="$run" \
  FONTCONFIG_FILE="$fonts" LANG=C.UTF-8
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK

# The compositor, in its own D-Bus session (notifications, portals).
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  setsid dbus-run-session --config-file "$tools/share/dbus-1/session.conf" -- sway -c "$home/.config/sway/config" >"$work/sway.log" 2>&1 &
sway_pid=$!
for _ in $(seq 50); do
  [ -S "$run/wayland-1" ] && break
  sleep 0.2
done
[ -S "$run/wayland-1" ] || {
  echo "perf.sh: sway did not start" >&2
  cat "$work/sway.log" >&2
  exit 1
}
sway_main=$(pgrep -n -f "sway -c $home/.config/sway/config" || true)
dbus_addr=$(tr '\0' '\n' <"/proc/$sway_main/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
export WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software \
  DBUS_SESSION_BUS_ADDRESS="$dbus_addr"

ticks() { awk '{print $14 + $15 + $16 + $17}' "/proc/$1/stat"; }
hz=$(getconf CLK_TCK)

results="[]"
measure() {
  local name="$1" config="$2"
  printf '%s\n' "$config" >"$home/.config/nixbook-shell/config.json"
  local log="$work/$name.log" start end pid t0 t1 rss
  start=$(date +%s%N)
  setsid "$package/bin/nixbook-shell" >"$log" 2>&1 &
  shell_pid=$!
  end=""
  for _ in $(seq 600); do
    if grep -q "Configuration Loaded" "$log" 2>/dev/null; then
      end=$(date +%s%N)
      break
    fi
    sleep 0.05
  done
  [ -n "$end" ] || {
    echo "perf.sh: $name did not load" >&2
    tail -20 "$log" >&2
    exit 1
  }
  pid=$(pgrep -n -f "quickshell -c nixbook-shell" || pgrep -n -f "qs -c nixbook-shell")
  sleep 20
  t0=$(ticks "$pid")
  sleep "$idle"
  t1=$(ticks "$pid")
  rss=$(awk '/VmRSS/ {print $2}' "/proc/$pid/status")
  kill "$shell_pid" "$pid" 2>/dev/null || true
  wait "$shell_pid" 2>/dev/null || true
  shell_pid=""
  sleep 2
  results=$(jq -c --arg name "$name" \
    --argjson startup "$(((end - start) / 1000000))" \
    --argjson cpu "$(awk -v d="$((t1 - t0))" -v hz="$hz" -v s="$idle" 'BEGIN { printf "%.2f", 100 * d / hz / s }')" \
    --argjson rss "$((rss / 1024))" \
    '. + [{theme: $name, startup_ms: $startup, idle_cpu_percent: $cpu, rss_mb: $rss}]' <<<"$results")
}

measure material '{"appearance":{"theme":"material"}}'
measure persona '{"appearance":{"theme":"persona","persona":{"variant":"p5"}}}'
measure chiikawa '{"appearance":{"theme":"chiikawa","chiikawa":{"variant":"chiikawa"}}}'

report=$(jq -c '{
    themes: .,
    score: (1000 / ((map(.startup_ms / 1000 + .idle_cpu_percent + .rss_mb / 100) | add) / length) | . * 10 | round / 10)
  }' <<<"$results")
[ -z "$json" ] || printf '%s\n' "$report" >"$json"

printf '%-10s %10s %10s %8s\n' theme startup_ms idle_cpu_% rss_MB
jq -r '.themes[] | [.theme, .startup_ms, .idle_cpu_percent, .rss_mb] | @tsv' <<<"$report" |
  while IFS=$'\t' read -r t s c r; do printf '%-10s %10s %10s %8s\n' "$t" "$s" "$c" "$r"; done
echo "score: $(jq .score <<<"$report") (higher is better)"
