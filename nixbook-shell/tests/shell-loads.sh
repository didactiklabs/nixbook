#!/usr/bin/env bash
# Starts nixbook-shell on a headless sway, with an empty home, and keeps what
# it printed: whether a change still loads, and the QML warnings it brought
# (nixbook-improve runs it on the change's base and on the change, then
# compares the two logs).
#
#   shell-loads.sh SHELL_DIR OUT_DIR [SECONDS]
#
# SHELL_DIR: a nixbook-shell/ directory (built with nix-build). OUT_DIR gets
# log.txt (the shell's output, colours stripped) and screen.png (the screen
# at the end). Exit 0: the shell was still running after SECONDS (default
# 25); 1: it didn't build, start or stay up. Needs sway and grim on PATH; no
# GPU (pixman, Qt's software renderer).
set -euo pipefail

shell_dir=$(realpath "$1")
out=$(realpath -m "$2")
seconds=${3:-25}
mkdir -p "$out"

# A short runtime dir: the scratch paths can be too long for a Unix socket.
run=$(mktemp -d /tmp/shell-loads.XXXXXX)
home=$(mktemp -d)
sway_pid=
shell_pid=
cleanup() {
  # The shell's own children (cliphist, its helper scripts) go with it.
  [ -z "$shell_pid" ] || kill -- -"$shell_pid" 2>/dev/null || true
  [ -z "$sway_pid" ] || kill "$sway_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$run" "$home" 2>/dev/null || true
}
trap cleanup EXIT

package=$(nix-build --no-out-link "$shell_dir" -A package 2>"$out/build.txt") || {
  echo "shell-loads: the package didn't build (build.txt)" >&2
  exit 1
}
config=$(nix-build --no-out-link "$shell_dir" -A package.passthru.shell 2>>"$out/build.txt") || exit 1
mkdir -p "$home"/{config/quickshell,state,cache,data}
ln -s "$config" "$home/config/quickshell/nixbook-shell"

printf 'output HEADLESS-1 resolution 1280x800\nxwayland disable\n' >"$home/sway.cfg"
XDG_RUNTIME_DIR=$run WAYLAND_DISPLAY='' WLR_BACKENDS=headless WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 sway -c "$home/sway.cfg" >"$out/sway.txt" 2>&1 &
sway_pid=$!
display=
for _ in $(seq 100); do
  display=$(find "$run" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -printf '%f\n' | head -n 1)
  [ -z "$display" ] || break
  sleep 0.1
done
[ -n "$display" ] || {
  echo "shell-loads: sway didn't start (sway.txt)" >&2
  exit 1
}

setsid env XDG_RUNTIME_DIR="$run" WAYLAND_DISPLAY="$display" QT_QUICK_BACKEND=software LANG=C.UTF-8 \
  XDG_CONFIG_HOME="$home/config" XDG_STATE_HOME="$home/state" XDG_CACHE_HOME="$home/cache" \
  XDG_DATA_HOME="$home/data" "$package/bin/nixbook-shell" >"$out/raw.txt" 2>&1 &
shell_pid=$!
sleep "$seconds"
up=0
if kill -0 "$shell_pid" 2>/dev/null; then
  up=1
  XDG_RUNTIME_DIR=$run WAYLAND_DISPLAY=$display grim "$out/screen.png" 2>/dev/null || true
  kill -- -"$shell_pid" 2>/dev/null || true
fi
wait "$shell_pid" 2>/dev/null || true
shell_pid=
sed 's/\x1b\[[0-9;]*m//g' "$out/raw.txt" >"$out/log.txt"
rm -f "$out/raw.txt"
if [ "$up" != 1 ]; then
  echo "shell-loads: the shell exited within ${seconds}s (log.txt)" >&2
  exit 1
fi
