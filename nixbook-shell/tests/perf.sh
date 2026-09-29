#!/usr/bin/env bash
# nixbook-shell performance and smoothness test: the shell in a headless
# compositor, in each theme, driven like a person would drive it.
#
#   bash nixbook-shell/tests/perf.sh [--quick] [--rounds N] [--themes a,b] [--json FILE]
#   bash nixbook-shell/tests/perf.sh --compare [REF] [--quick] [--rounds N] ...
#   (run-tests shell-perf)
#
# Two uses:
#   - the score (default, ~5 min): this tree's shell, every metric converted
#     to the reference machine (see calibration) and compared with the
#     baseline below: 100 = the shell before the smoothness work (2026-09-29),
#     higher is better. For the AGENTS.md table.
#   - --compare REF (default origin/main, ~15 min): builds REF (A) and this
#     tree (B) and runs them alternately (A B, then B A) on the same machine,
#     at the same time: machine speed and load cancel out. The way to tell
#     whether a change helps: % per metric and per interaction, each with its
#     99% interval and verdict — better / worse when the change is
#     significant (a t-test over the rounds: each round, both shells in every
#     theme, is one independent sample; 3 by default) and over 3%, else
#     "noise". Validated: identical code gets no verdict; the smoothness
#     work gets UI time −68% "better". Three rounds only resolve big changes
#     (the interval is wide); --rounds 5 or more for a closer look.
# --quick: Material only, one round (~1.5 min; with --compare ~3 min and no
# verdicts: one sample).
#
# Per theme, the median over --rounds rounds (default 2; 3 with --compare):
#   startup_ms   launch until the QML is loaded (two launches per theme)
#   idle_cpu     CPU ms per idle minute: 10 s of quiet idle (once the startup
#                work is over) scaled to a minute, plus the clock's minute
#                change (`tick_ms`, measured on its own)
#   wakeups_s    context switches per idle second
#   spawns_min   processes started per idle minute (polling commands)
#   rss_mb       resident memory at the end of the round
# and, over scripted interactions (keys typed 120 ms apart: the launcher —
# type, erase, retype, move through the results —, the AI chat input, the
# right sidebar, a wallpaper change and back, the settings window):
#   ui_ms        UI-thread CPU: JS, bindings, layout — what makes typing lag
#   render_ms    time drawing frames: masks, layers, effects, buffer sizes
#   jank         heavy frames: drawn in more than 1.5 plain full-screen
#                frames of the calibration (relative to the machine's drawing
#                speed), or prepared on the UI thread in more than a 60 Hz
#                frame (16.7 ms on the reference machine): visible stutter
#   (cpu_ms — all threads —, frames, and — where the CPU's counters can be
#   read, see below — ui_minstr / all_minstr, millions of instructions, are
#   reported and compared, not scored)
# Each interaction's ui / render / jank is reported too.
#
# score = 100 × geometric mean over the 8 metrics of baseline / value (counts
# +1, so 0 stays finite): every metric weighs the same; 110 ≈ 10% better on
# average.
#
# How a round goes: one shell, started in the first theme; each theme is
# switched to live (config.json, as the Settings menu does), then measured
# (idle, interactions). The clock redraws the bar once a minute: no window is
# allowed to straddle a minute change — the test waits for it instead, and
# measures that change (`tick_ms`) while waiting.
#
# Reliability:
#   - real OpenGL on Mesa's llvmpipe (CPU, no GPU needed), so shader effects,
#     masks and layers cost what they cost (Qt's software renderer skipped
#     them), llvmpipe pinned to 2 threads and 128-bit vectors: the same code
#     runs whatever the CPU;
#   - animations advance a fixed step per frame (QSG_FIXED_ANIMATION_STEP):
#     every animation renders the same frames on any machine;
#   - with 6 physical cores or more, the shell gets 4 of them to itself (one
#     logical CPU each), the compositor and this script another: nothing
#     competes with it or moves it between cores;
#   - calibration: a minimal Quickshell config (a bar, a full-screen animated
#     scene) started the same way; its frame time (steady to ~1%) converts
#     every timing to the reference machine (REF_CAL_FRAME_MS below);
#   - CPU from the scheduler (ns); instructions too when the kernel allows
#     reading the CPU's counters (perf; not in most containers) — they barely
#     move with clock speed, heat or load;
#   - frames from Qt's scene graph log (qt.scenegraph.time.renderloop), a
#     fixed 1920×1080 output, fonts, applications and wallpapers.
# Absolute numbers still move a little between machines and runs (caches,
# memory, heat): compare scores from one machine, and judge a change with
# --compare.
#
# Everything runs from Nix (sway, dbus, fonts, strace, wtype, Mesa, perf,
# util-linux: the pinned nixpkgs), in a throwaway home and a short-lived
# Wayland socket.
set -euo pipefail

# The reference machine (AMD Ryzen 7 6800U) and the baseline measured on it.
# (its calibration: 17.541 ms/frame; 98 ms startup and 1520 ms CPU, for
# information)
REF_CAL_FRAME_MS=17.541
# Per theme (another theme is compared with Material's): the shell before
# the smoothness work (e8d671d5), median of 3 rounds, on the reference machine.
BASE='{
  "chiikawa": {"startup_ms":1912,"idle_cpu":1157,"wakeups_s":73.4,"spawns_min":0,"rss_mb":1471,"ui_ms":3789,"render_ms":17570,"jank":380},
  "material": {"startup_ms":2254,"idle_cpu":1200,"wakeups_s":96.8,"spawns_min":0,"rss_mb":1471,"ui_ms":3968,"render_ms":19529,"jank":406},
  "persona": {"startup_ms":2230,"idle_cpu":1208,"wakeups_s":98.9,"spawns_min":0,"rss_mb":1471,"ui_ms":3566,"render_ms":16441,"jank":346}
}'

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package=""
compare=""
rounds=""
themes="material,persona,chiikawa"
idle=10
json=""
while [ $# -gt 0 ]; do
  case "$1" in
  --package)
    package="$2"
    shift 2
    ;;
  --compare)
    compare="origin/main"
    if [ $# -gt 1 ] && [ "${2#--}" = "$2" ]; then
      compare="$2"
      shift
    fi
    shift
    ;;
  --quick)
    rounds=1
    themes="material"
    shift
    ;;
  --rounds | --runs)
    rounds="$2"
    shift 2
    ;;
  --themes)
    themes="$2"
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
IFS=, read -ra theme_list <<<"$themes"
# Rounds are the independent samples: --compare needs 3 for its t-test.
[ -n "$rounds" ] || rounds=$([ -n "$compare" ] && echo 3 || echo 2)

nixpkgs=$(nix-instantiate --eval -E "(import $here/npins).nixpkgs.outPath" | tr -d '"')
build() { nix-build --no-out-link -E "$1" 2>/dev/null | tail -1; }
work=$(mktemp -d)
run=$(mktemp -d /tmp/nbperf.XXXXXX) # short: the sway IPC socket path is limited
chmod 700 "$run"

[ -n "$package" ] || package=$(build "(import $here/. {}).package")
refpackage=""
if [ -n "$compare" ]; then
  # REF's nixbook-shell/, built the same way (it is self-contained).
  mkdir -p "$work/ref"
  git -C "$(git -C "$here" rev-parse --show-toplevel)" archive "$compare" nixbook-shell | tar -x -C "$work/ref"
  refpackage=$(build "(import $work/ref/nixbook-shell {}).package")
  [ -n "$refpackage" ] || {
    echo "perf.sh: cannot build $compare" >&2
    exit 1
  }
fi
tools=$(build "let p = import $nixpkgs {}; in p.symlinkJoin { name = \"nixbook-shell-perf-tools\"; paths = [ p.sway p.dbus p.coreutils p.procps p.jq p.strace p.gawk p.wtype p.util-linux p.perf ]; }")
fonts=$(build "let p = import $nixpkgs {}; in p.makeFontsConf { fontDirectories = [ p.roboto p.oswald p.nunito p.dejavu_fonts ]; }")
mesa=$(build "(import $nixpkgs {}).mesa")
export PATH="$tools/bin:$PATH"
qs=$(grep -o '/nix/store/[^ ]*/bin/qs' "$package/bin/nixbook-shell" | head -1)

# Whole process groups (setsid): the shell's own children, dbus-daemon…
cleanup() {
  [ -n "${shell_pid:-}" ] && kill -- -"$shell_pid" 2>/dev/null || true
  [ -n "${sway_pid:-}" ] && kill -- -"$sway_pid" 2>/dev/null || true
  sleep 1
  chmod -R u+w "$work" "$run" 2>/dev/null || true
  rm -rf "$work" "$run"
}
trap cleanup EXIT

# ------------------------------------------------------------------- CPUs
# One logical CPU per physical core; the shell gets cores 2–5, this script
# and the compositor core 0 (all its logical CPUs).
shell_cpus=""
mapfile -t core_cpus < <(lscpu -p=CPU,CORE | grep -v '^#' | awk -F, '!seen[$2]++ {print $1}')
if [ "${#core_cpus[@]}" -ge 6 ]; then
  shell_cpus="${core_cpus[2]},${core_cpus[3]},${core_cpus[4]},${core_cpus[5]}"
  harness_cpus=$(lscpu -p=CPU,CORE | grep -v '^#' | awk -F, -v c="$(lscpu -p=CPU,CORE | grep -v '^#' | head -1 | cut -d, -f2)" '$2 == c {print $1}' | paste -sd,)
  taskset -pc "$harness_cpus" $$ >/dev/null
fi
# Prefix of every shell's command line (setsid runs it: no function).
pin=()
[ -z "$shell_cpus" ] || pin=(taskset -c "$shell_cpus")
# The CPU's instruction counters, when the kernel lets us read them.
counters=0
perf stat -x, -e instructions:u -- true >/dev/null 2>&1 && counters=1

home="$work/home"
mkdir -p "$home/.config/sway" "$home/.config/nixbook-shell" "$home/.config/quickshell" \
  "$home/.local/state/quickshell/user" "$home/.local/share/applications" "$work/calibration"
echo "output HEADLESS-1 resolution 1920x1080 scale 1" >"$home/.config/sway/config"
# No first-run welcome window.
echo x >"$home/.local/state/quickshell/user/first_run.txt"
# A realistic launcher: 300 applications to search.
i=0
for a in Fire Thunder Libre Gnome Kde Visual Blue Open Steam Signal Tele Pavu Net Disk Image Video Audio Text Code Mail; do
  for b in fox bird office terminal manager studio editor viewer player writer calc monitor tweaks settings browser; do
    i=$((i + 1))
    printf '[Desktop Entry]\nType=Application\nName=%s%s\nGenericName=%s %s\nComment=The %s %s application\nExec=true %s\nIcon=application-x-executable\nKeywords=%s;%s;\n' \
      "$a" "$b" "$a" "$b" "$a" "$b" "$i" "$a" "$b" >"$home/.local/share/applications/perf-$i.desktop"
  done
done
cat >"$work/calibration/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
    PanelWindow {
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        color: "#202020"
        Text { anchors.centerIn: parent; text: "calibration"; color: "white" }
    }
    // A full-screen animated scene: the machine's drawing speed.
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#303050" }
                GradientStop { position: 1; color: "#503030" }
            }
            Repeater {
                model: 24
                Rectangle {
                    required property int index
                    x: (index % 6) * 300 + 60; y: Math.floor(index / 6) * 250 + 60
                    width: 180; height: 180; radius: 40; opacity: 0.8
                    color: Qt.hsla(index / 24, 0.6, 0.5, 1)
                    RotationAnimation on rotation { from: 0; to: 360; duration: 2000; loops: Animation.Infinite }
                }
            }
        }
    }
}
QML

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
# Real OpenGL on the CPU (Mesa llvmpipe, pinned: same code on any CPU),
# fixed-step animations, and the scene graph's frame timings.
export WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
  LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=2 LP_NATIVE_VECTOR_WIDTH=128 \
  LIBGL_DRIVERS_PATH="$mesa/lib/dri" __EGL_VENDOR_LIBRARY_FILENAMES="$mesa/share/glvnd/egl_vendor.d/50_mesa.json" \
  QSG_FIXED_ANIMATION_STEP=1 QT_LOGGING_RULES="qt.scenegraph.time.renderloop.debug=true"

hz=$(getconf CLK_TCK)
# CPU ms of a process and its reaped children (all threads, ever).
cpums() { awk -v hz="$hz" '{printf "%d", 1000 * ($14 + $15 + $16 + $17) / hz}' "/proc/$1/stat"; }
# CPU ms of all its current threads, from the scheduler (ns): precise, for
# windows where no thread starts or ends (idle).
allms() { cat /proc/"$1"/task/*/schedstat 2>/dev/null | awk '{s += $1} END {printf "%.1f", s / 1e6}'; }
# CPU ms of the UI (main) thread, from the scheduler (ns).
uims() { awk '{printf "%.1f", $1 / 1e6}' "/proc/$1/task/$1/schedstat"; }
# Context switches of all its current threads.
ctxsw() { cat /proc/"$1"/task/*/status 2>/dev/null | awk '/_ctxt_switches/ {s += $2} END {print s + 0}'; }
execs() { grep -c 'execve("' "$1" 2>/dev/null || true; }
lines() { wc -l <"$1"; }
median() { sort -n | awk '{a[NR] = $1} END {if (NR) print (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2; else print 0}'; }
now() { date +%s%N; }
# b - a, never below 0 (a thread that ended takes its counts with it).
delta() { awk -v a="$1" -v b="$2" -v k="${3:-1}" 'BEGIN {d = b - a; print (d > 0 ? d : 0) * k}'; }
# Frame times (ms) drawn in log lines ($2, $3], one per line.
frametimes() {
  sed -n "$(($2 + 1)),$3p" "$1" | sed 's/\x1b\[[0-9;]*m//g' |
    sed -n 's/.*syncAndRender: frame rendered in \([0-9]*\)ms.*/\1/p'
}
# Frame stats of log lines ($2, $3]: drawn frames and their ms (scaled by
# $4, to the reference machine); jank = frames drawn in more than 1.5 of the
# calibration's plain full-screen frames ($5 ms: relative to this machine's
# drawing speed), or prepared on the UI thread (polish + animations, scaled
# by $6) in more than a 60 Hz frame (16.7 ms).
frames() {
  sed -n "$(($2 + 1)),$3p" "$1" | sed 's/\x1b\[[0-9;]*m//g' | awk -v k="$4" -v cal="$5" -v ku="$6" '
    /syncAndRender: frame rendered in/ {
      match($0, /rendered in [0-9]+ms/); t = substr($0, RSTART + 12, RLENGTH - 14)
      n++; ms += k * t; if (t > 1.5 * cal) jank++
    }
    /Frame prepared, polish=/ {
      match($0, /polish=[0-9]+/); p = substr($0, RSTART + 7, RLENGTH - 7)
      match($0, /animations=[0-9]+/); a = substr($0, RSTART + 11, RLENGTH - 11)
      if (ku * (p + a) > 16.7) jank++
    }
    END { printf "{\"frames\":%d,\"render_ms\":%.1f,\"jank\":%d}", n, ms, jank }'
}
# Instructions (user space, millions) of the shell's threads, UI thread and
# all, while `$@` runs; {} without counters.
counting() {
  if [ "$counters" != 1 ]; then
    "$@"
    echo '{}' >"$work/instr.json"
    return
  fi
  perf stat -x, --per-thread -e instructions:u -p "$main_pid" -o "$work/perf.csv" &
  local pp=$!
  sleep 0.1
  "$@"
  kill -INT "$pp" 2>/dev/null || true
  wait "$pp" 2>/dev/null || true
  awk -F, -v pid="$main_pid" '
    $4 ~ /instructions/ && $2 ~ /^[0-9]+$/ {
      tid = $1; sub(/.*-/, "", tid); all += $2; if (tid == pid) ui += $2
    }
    END { printf "{\"ui_minstr\":%.2f,\"all_minstr\":%.2f}", ui / 1e6, all / 1e6 }' "$work/perf.csv" >"$work/instr.json"
}

# Starts `$@`, waits for its log to say the config is loaded; sets started_ms,
# main_pid.
start_and_wait() {
  local log="$1" pattern="$2"
  shift 2
  local start end=""
  start=$(now)
  setsid "$@" >"$log" 2>&1 &
  shell_pid=$!
  for _ in $(seq 800); do
    if grep -q "Configuration Loaded" "$log" 2>/dev/null; then
      end=$(now)
      break
    fi
    sleep 0.025
  done
  [ -n "$end" ] || {
    echo "perf.sh: $log: did not load" >&2
    tail -20 "$log" >&2
    exit 1
  }
  started_ms=$(((end - start) / 1000000))
  main_pid=$(pgrep -n -f "$pattern")
}
# Waits (up to 40 s) until the shell is quiet: under 2% of a core and 200
# context switches over 1 s, twice in a row (startup or theme-switch work
# done, and no animation still running: a cheap one passes the CPU test).
settle() {
  local a b wa wb quiet=0 t=0
  a=$(cpums "$main_pid")
  wa=$(ctxsw "$main_pid")
  while [ "$t" -lt 40 ] && [ "$quiet" -lt 2 ]; do
    sleep 1
    t=$((t + 1))
    b=$(cpums "$main_pid")
    wb=$(ctxsw "$main_pid")
    if [ $((b - a)) -lt 20 ] && [ $((wb - wa)) -lt 200 ]; then quiet=$((quiet + 1)); else quiet=0; fi
    a=$b
    wa=$wb
  done
}
# Before a window of $1 s: when the next minute change would fall in it,
# waits for it, measuring it (CPU from 1 s before to 4 s after) into ticks.
ticks=()
guard() {
  local left t0 t1
  left=$(awk -v now="$(date +%s.%N)" 'BEGIN {printf "%.3f", 60 - (now - int(now / 60) * 60)}')
  if awk -v l="$left" -v n="$1" 'BEGIN {exit !(l < n + 1)}'; then
    sleep "$(awk -v l="$left" 'BEGIN {print (l > 1 ? l - 1 : 0)}')"
    t0=$(cpums "$main_pid")
    sleep 5
    t1=$(cpums "$main_pid")
    ticks+=("$((t1 - t0))")
  fi
}
stop() {
  kill -- -"$shell_pid" 2>/dev/null || true
  kill "$main_pid" 2>/dev/null || true
  wait "$shell_pid" 2>/dev/null || true
  shell_pid=""
  sleep 1
}

# ------------------------------------------------------------- calibration
cal_ms_runs=()
cal_cpu_runs=()
cal_frame_runs=()
for i in 1 2 3; do
  log="$work/cal.$i.log"
  start_and_wait "$log" "\-p $work/calibration/shell.qml" "${pin[@]}" "$qs" -p "$work/calibration/shell.qml"
  cal_ms_runs+=("$started_ms")
  sleep 1
  cal_cpu_runs+=("$(cpums "$main_pid")")
  l0=$(lines "$log")
  sleep 2
  # Mean, not median: frame times are whole ms, the mean over ~120 frames isn't.
  cal_frame_runs+=("$(frametimes "$log" "$l0" "$(lines "$log")" | awk '{s += $1} END {printf "%.3f", NR ? s / NR : 0}')")
  stop
done
cal_ms=$(printf '%s\n' "${cal_ms_runs[@]}" | median)
cal_cpu=$(printf '%s\n' "${cal_cpu_runs[@]}" | median)
cal_frame=$(printf '%s\n' "${cal_frame_runs[@]}" | median)
# To the reference machine (1 when unset: while measuring the reference).
# One factor for every timing, from the frame time: it varies by ~1% from
# run to run, where the calibration's ~100 ms startup varied by ~50% and its
# CPU by ~8% (startup and CPU are reported, for information).
k_frame=$(awk -v r="$REF_CAL_FRAME_MS" -v c="$cal_frame" 'BEGIN {print (r > 0 && c > 0) ? r / c : 1}')
k_start=$k_frame
k_cpu=$k_frame

# ----------------------------------------------------------- interactions
ipc() { timeout 10 "$pkg/bin/nixbook-shell" ipc call "$@" >/dev/null 2>&1 || true; }
# Typed like a person: 120 ms between keys (-s: the first key waits for the
# keymap, else wtype loses it).
typing() { wtype -s 300 -d 120 "$@"; }
keys() {
  local k=$1 n=$2 args=()
  for _ in $(seq "$n"); do args+=(-k "$k"); done
  wtype -s 300 -d 120 "${args[@]}"
}
# One interaction ($1, at most $2 s), measured on its own: its frames (from
# the log), UI-thread and total CPU, instructions; appends to $steps.
step() {
  local name="$1" est="$2" l0 l1 u0 u1 c0 c1
  shift 2
  guard "$est"
  sleep 0.2
  l0=$(lines "$log")
  u0=$(uims "$main_pid")
  c0=$(cpums "$main_pid")
  counting "$@"
  sleep 0.5
  l1=$(lines "$log")
  u1=$(uims "$main_pid")
  c1=$(cpums "$main_pid")
  steps+=$(frames "$log" "$l0" "$l1" "$k_frame" "$cal_frame" "$k_cpu" | jq -c --arg name "$name" \
    --argjson u "$(delta "$u0" "$u1" "$k_cpu")" --argjson c "$(delta "$c0" "$c1" "$k_cpu")" \
    --slurpfile instr "$work/instr.json" '. + {name: $name, ui_ms: $u, cpu_ms: $c} + $instr[0]')$'\n'
}
launcher() {
  ipc search open
  sleep 0.3
  typing "firefox"
  keys BackSpace 4
  typing "term"
  keys Down 5
  ipc search close
}
aichat() {
  ipc sidebarLeft open
  sleep 0.3
  typing "change the wallpaper"
  ipc sidebarLeft close
}
quicksettings() {
  ipc sidebarRight open
  sleep 1
  ipc sidebarRight close
}
wallpaper() {
  ipc wallpapers apply "$wallB"
  sleep 2
  ipc wallpapers apply "$wallA"
  sleep 2
}
settingswindow() {
  ipc settings open
  sleep 1.5
  ipc settings close
}

config_for() {
  case "$1" in
  persona) echo '{"appearance":{"theme":"persona","persona":{"variant":"p5"}}}' ;;
  chiikawa) echo '{"appearance":{"theme":"chiikawa","chiikawa":{"variant":"chiikawa"}}}' ;;
  *) echo '{"appearance":{"theme":"material"}}' ;;
  esac | jq -c --arg w "$wallA" '. * {background: {wallpaperPath: $w}}'
}
# use PACKAGE: the shell to run (the QML tree where Home Manager links it).
use() {
  pkg="$1"
  vendored=$(grep -o '/nix/store/[^ ]*-nixbook-shell-vendored-[^/ ]*' "$pkg/bin/nixbook-shell" | head -1)
  wallA="$vendored/assets/images/default_wallpaper.png"
  wallB="$vendored/assets/persona/p5-wide.png"
  ln -sfn "$vendored" "$home/.config/quickshell/nixbook-shell"
  rm -rf "$home/.cache" "$home/.local/state/quickshell/user/generated"
}

# startups LABEL PACKAGE: two launches per theme, appended to $starts.
starts=""
startups() {
  local label="$1" theme k
  use "$2"
  for theme in "${theme_list[@]}"; do
    for k in 1 2; do
      config_for "$theme" >"$home/.config/nixbook-shell/config.json"
      start_and_wait "$work/start.log" "quickshell -c nixbook-shell" "${pin[@]}" "$pkg/bin/nixbook-shell"
      starts+=$(jq -nc --arg label "$label" --arg theme "$theme" --argjson k "$k" \
        --argjson ms "$(awk -v a="$started_ms" -v k="$k_start" 'BEGIN {print a * k}')" \
        '{label: $label, theme: $theme, k: $k, startup_ms: $ms}')$'\n'
      stop
    done
  done
}

# round LABEL PACKAGE ROUND: one shell, every theme in turn, appended to $rows.
rows=""
round() {
  local label="$1" r="$3" theme first=1 trace c0 w0 e0 c1 w1 e1 rss tick part=""
  use "$2"
  log="$work/$label.$r.log"
  trace="$work/$label.$r.exec"
  ticks=()
  config_for "${theme_list[0]}" >"$home/.config/nixbook-shell/config.json"
  start_and_wait "$log" "quickshell -c nixbook-shell" \
    "${pin[@]}" strace -f -qq --seccomp-bpf -e trace=execve -o "$trace" "$pkg/bin/nixbook-shell"
  sleep 2
  settle
  for theme in "${theme_list[@]}"; do
    if [ "$first" = 0 ]; then
      config_for "$theme" >"$home/.config/nixbook-shell/config.json"
      sleep 1
      settle
    fi
    first=0
    guard "$idle"
    c0=$(allms "$main_pid")
    w0=$(ctxsw "$main_pid")
    e0=$(execs "$trace")
    sleep "$idle"
    c1=$(allms "$main_pid")
    w1=$(ctxsw "$main_pid")
    e1=$(execs "$trace")
    steps=""
    step launcher 9 launcher
    step aichat 7 aichat
    step quicksettings 4 quicksettings
    step wallpaper 8 wallpaper
    step settings 5 settingswindow
    part+=$(jq -nc --arg label "$label" --arg theme "$theme" --argjson r "$r" \
      --argjson idle_ms "$(delta "$c0" "$c1" "$k_cpu")" --argjson w "$(delta "$w0" "$w1")" \
      --argjson e "$(delta "$e0" "$e1")" --argjson idle "$idle" --argjson steps "$(jq -sc . <<<"$steps")" '{
        label: $label, theme: $theme, round: $r,
        idle_quiet: ($idle_ms * 60 / $idle),
        wakeups_s: ($w / $idle),
        spawns_min: ($e * 60 / $idle),
        ui_ms: ($steps | map(.ui_ms) | add),
        render_ms: ($steps | map(.render_ms) | add),
        jank: ($steps | map(.jank) | add),
        cpu_ms: ($steps | map(.cpu_ms) | add),
        frames: ($steps | map(.frames) | add),
        steps: ($steps | map({key: .name, value: (del(.name))}) | from_entries)
      } + (if ($steps[0] | has("ui_minstr")) then {
        ui_minstr: ($steps | map(.ui_minstr) | add), all_minstr: ($steps | map(.all_minstr) | add)
      } else {} end)')$'\n'
  done
  # At least one minute change per round (else wait for the next one).
  [ "${#ticks[@]}" -gt 0 ] || guard 70
  tick=$(printf '%s\n' "${ticks[@]}" | median)
  rss=$(awk '/VmRSS/ {print $2}' "/proc/$main_pid/status")
  stop
  rows+=$(jq -c --argjson tick "$(awk -v t="$tick" -v k="$k_cpu" 'BEGIN {print t * k}')" --argjson rss "$rss" \
    '. + {tick_ms: $tick, idle_cpu: (.idle_quiet + $tick), rss_mb: ($rss / 1024)}' <<<"$part")$'\n'
}

started=$(now)
if [ -n "$compare" ]; then
  startups A "$refpackage"
  startups B "$package"
else
  startups B "$package"
fi
for r in $(seq "$rounds"); do
  if [ -z "$compare" ]; then
    round B "$package" "$r"
  elif [ $((r % 2)) -eq 1 ]; then
    # Alternate the order, so a slow drift of the machine favours neither.
    round A "$refpackage" "$r"
    round B "$package" "$r"
  else
    round B "$package" "$r"
    round A "$refpackage" "$r"
  fi
done
elapsed=$((($(now) - started) / 1000000000))

# ----------------------------------------------------------------- report
report=$(jq -sc --argjson base "$BASE" --argjson rounds "$rounds" --argjson counters "$counters" \
  --arg pinned "${shell_cpus:-no}" --argjson starts "$(jq -sc . <<<"$starts")" \
  --argjson cal "{\"startup_ms\":$cal_ms,\"cpu_ms\":$cal_cpu,\"frame_ms\":$cal_frame}" \
  --argjson k "{\"startup\":$k_start,\"cpu\":$k_cpu,\"frame\":$k_frame}" '
  def med: if . == null then null else sort end | if . == null or length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  def r(n): if . == null then null else . * pow(10; n) | round / pow(10; n) end;
  def scored: ["startup_ms", "idle_cpu", "wakeups_s", "spawns_min", "rss_mb", "ui_ms", "render_ms", "jank"];
  def reported: ["tick_ms", "cpu_ms", "frames", "ui_minstr", "all_minstr"];
  def counts: ["wakeups_s", "spawns_min", "jank"];
  # a / b (counts +1, so 0 stays finite).
  def ratio($a; $b; $m): if (counts | index($m)) then ($a + 1) / ($b + 1) elif $b > 0 then $a / $b else 1 end;
  def geomean: if length == 0 then null else (map(log) | add / length) | exp end;
  def pct: if . == null then null else 100 * (. - 1) | r(1) end;
  # Change of B over A from per-round ratios (a round: both shells, every
  # theme; rounds are the independent samples): the geometric mean, a 99%
  # interval (t distribution, on log ratios: asymmetric in %) and a verdict
  # — better / worse when the interval excludes no change and the change is
  # over 3%, else noise ("few rounds" under 2). 99%, not 95%: ~26 metrics
  # are judged at once, and at 95% one or two would come out "significant"
  # by chance (measured: identical code gave three).
  def tcrit: [0, 63.66, 9.92, 5.84, 4.60, 4.03, 3.71, 3.50, 3.36, 3.25][.] // 3.0;
  def verdict: (map(select(. != null and . > 0) | log)) as $l | ($l | length) as $n
    | if $n == 0 then {change: null, low: null, high: null, verdict: "n/a"} else
      ($l | add / $n) as $mean
      | (if $n > 1 then (($l | map(. - $mean | . * .) | add) / ($n - 1) | sqrt) else null end) as $sd
      | (if $sd == null then null else ($n - 1 | tcrit) * $sd / ($n | sqrt) end) as $half
      | {change: (($mean | exp) - 1 | . * 100 | r(1)),
         low: (if $half == null then null else (($mean - $half | exp) - 1) * 100 | r(1) end),
         high: (if $half == null then null else (($mean + $half | exp) - 1) * 100 | r(1) end),
         ratios: (map(exp | r(4))),
         verdict: (if $n < 2 then "few rounds"
           elif (($mean | exp) - 1 | fabs) < 0.03 then "noise"
           elif $mean + $half < 0 then "better"
           elif $mean - $half > 0 then "worse"
           else "noise" end)} end;
  . as $rows
  | ($starts | group_by(.label + "/" + .theme) | map({key: (.[0].label + "/" + .[0].theme), value: map(.startup_ms)}) | from_entries) as $st
  | ($rows | map(. + {startup_ms: ($st[.label + "/" + .theme] | med)})) as $rows
  | ($rows | map(.round) | unique) as $rounds_list
  | ($rows | map(.theme) | unique) as $themes_list
  # Per round, B/A over the themes (geometric mean).
  | def per_round(f): [$rounds_list[] as $rd
    | [$themes_list[] as $t | ([$rows[] | select(.label == "B" and .round == $rd and .theme == $t)][0]) as $rb
        | ([$rows[] | select(.label == "A" and .round == $rd and .theme == $t)][0]) as $ra
        | if $rb == null or $ra == null then empty else ([$rb, $ra] | f) end]
    | if length == 0 then null else geomean end];
  # Median per label and theme, steps included.
  ($rows | group_by(.label + "/" + .theme) | map(. as $g |
      (reduce ($g[0] | keys_unsorted[] | select(IN("label", "theme", "round", "steps") | not)) as $m
        ({label: $g[0].label, theme: $g[0].theme}; .[$m] = ([$g[][$m]] | med)))
      + {steps: ($g[0].steps | keys_unsorted | map(. as $s | {key: $s, value:
          ($g[0].steps[$s] | keys_unsorted | map(. as $f | {key: $f, value: ([$g[].steps[$s][$f]] | med)}) | from_entries)})
        | from_entries)})) as $sum
  | ($sum | map(select(.label == "B"))) as $b
  | ($sum | map(select(.label == "A"))) as $a
  # Pairs of rows: same theme and round, A and B.
  | ([$rows[] | select(.label == "B")] | map(. as $rb | {b: $rb, a: ([$rows[] | select(.label == "A" and .theme == $rb.theme and .round == $rb.round)][0])})
      | map(select(.a != null))) as $pairs
  | ($starts | map(select(.label == "B")) | map(. as $sb | {b: $sb, a: ([$starts[] | select(.label == "A" and .theme == $sb.theme and .k == $sb.k)][0])})
      | map(select(.a != null))) as $spairs
  | {
      calibration: $cal, to_reference: $k, rounds: $rounds, pinned_cpus: $pinned, instructions: ($counters == 1),
      themes: ($b | map(del(.label) | (($base[.theme] // $base.material) // {}) as $bt
        | . + {score: (if $bt == {} then null else 100 * ([scored[] as $m | ratio($bt[$m]; .[$m]; $m)] | geomean) | r(1) end)})),
      score: (if $base == {} then null else
        100 * ([$b[] | ($base[.theme] // $base.material) as $bt | . as $t | scored[] as $m | ratio($bt[$m]; $t[$m]; $m)] | geomean) | r(1) end)
    }
  + (if ($pairs | length) == 0 then {} else {
      reference: ($a | map(del(.label))),
      # B vs A per metric: change % (negative = less = better), ± and verdict.
      change: ([scored[], reported[]] | map(. as $m | {key: $m, value:
        (if $m == "startup_ms" then
           # Launches: the k-th of each theme, as rounds.
           [1, 2] | map(. as $k | [$spairs[] | select(.b.k == $k) | ratio(.b.startup_ms; .a.startup_ms; $m)] | if length == 0 then null else geomean end)
         else per_round(if (.[0] | has($m)) and (.[1] | has($m)) then ratio(.[0][$m]; .[1][$m]; $m) else empty end) end
         | verdict)}) | from_entries),
      step_change: ($pairs[0].b.steps | keys_unsorted | map(. as $s | {key: $s, value:
        (["ui_ms", "render_ms", "jank"] + (if ($pairs[0].b.steps[$s] | has("ui_minstr")) then ["ui_minstr"] else [] end)
          | map(. as $f | {key: $f, value: (per_round(ratio(.[0].steps[$s][$f]; .[1].steps[$s][$f]; $f)) | verdict)})
          | from_entries)}) | from_entries),
      # Overall: how much better B is (geometric mean of A/B over the scored
      # metrics and rounds).
      improvement: ([scored[] | select(. != "startup_ms") as $m | per_round(ratio(.[1][$m]; .[0][$m]; $m))[]]
        + [$spairs[] | ratio(.a.startup_ms; .b.startup_ms; "startup_ms")] | geomean | if . == null then null else 100 * (. - 1) | r(1) end)
    } end)' <<<"$rows")
[ -z "$json" ] || printf '%s\n' "$report" >"$json"

echo "calibration: $cal_frame ms/frame, so ×$k_frame to the reference machine ($cal_ms ms startup, $cal_cpu ms CPU)"
echo "shell CPUs: ${shell_cpus:-not pinned (fewer than 6 cores)}; instruction counters: $([ "$counters" = 1 ] && echo yes || echo "no (perf not allowed here)"); took ${elapsed}s"
printf '%-9s %8s %8s %7s %9s %8s %7s %8s %9s %6s %6s\n' \
  theme startup idle_cpu tick_ms wakeups/s spawns/m rss_MB ui_ms render_ms jank score
jq -r '.themes[] | [.theme, (.startup_ms | round), (.idle_cpu | round), (.tick_ms | round), (.wakeups_s | round),
  .spawns_min, (.rss_mb | round), (.ui_ms | round), (.render_ms | round), .jank, (.score // "-")] | @tsv' <<<"$report" |
  while IFS=$'\t' read -r a b c d e f g h i j k; do
    printf '%-9s %8s %8s %7s %9s %8s %7s %8s %9s %6s %6s\n' "$a" "$b" "$c" "$d" "$e" "$f" "$g" "$h" "$i" "$j" "$k"
  done
echo "per interaction (ui ms / render ms / jank):"
jq -r '.themes[] | "  \(.theme): " + (.steps | to_entries
  | map("\(.key) \(.value.ui_ms | round)/\(.value.render_ms | round)/\(.value.jank)") | join(", "))' <<<"$report"
echo "score: $(jq -r '.score // "- (no baseline yet)"' <<<"$report") (100 = before the smoothness work; higher is better; median of $rounds rounds)"
if [ -n "$compare" ]; then
  echo
  echo "$compare (A) → this tree (B), negative = less = better, [99% interval] over $rounds rounds;"
  echo "better/worse: the interval excludes no change, and over 3%"
  jq -r 'def fmt: "\(if .change > 0 then "+" else "" end)\(.change)%\(if .low != null then " [\(.low)%, \(.high)%]" else "" end) \(.verdict)";
    .change | to_entries | map(select(.value.change != null)) | map("  \(.key): \(.value | fmt)") | .[]' <<<"$report"
  echo "per interaction:"
  jq -r 'def fmt: "\(if .change > 0 then "+" else "" end)\(.change)%\(if .low != null then " [\(.low)%, \(.high)%]" else "" end) \(.verdict)";
    .step_change | to_entries | map("  \(.key): " + (.value | to_entries | map("\(.key) \(.value | fmt)") | join(", "))) | .[]' <<<"$report"
  echo "overall: this tree is $(jq .improvement <<<"$report")% better than $compare (geometric mean over the scored metrics)"
fi
