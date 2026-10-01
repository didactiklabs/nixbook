#!/usr/bin/env bash
# nixbook-agent-desktop: a desktop of its own for AI agents, so they can work
# while the user works. A nested niri (a window on the user's desktop) that
# `nixbook-desktop-mcp desktop agent` points the agents' window, screen and
# input tools at: its own pointer, keyboard focus, clipboard and windows;
# nothing it does moves the user's windows or takes their focus. (Their shell
# tools, the notes widget, to-do list, calendar, still reach the user's
# shell: desktop-mcp talks to it over its IPC, not through a display.)
#
# The window is a view, "Assistant's desktop" (app id nixbook-agent-desktop):
# its niri (patched, niri-winit-agent-window.patch) drops the input it gets
# from the user, so the user can move, resize and close the window but not
# click or type into the agent's desktop; except while the user takes it over
# (`desktop interact`, Mod+Ctrl+A: while agent-desktop-input exists). Nothing
# is on it but the one app the agent works in, fullscreen (its niri keeps it
# so, whatever the app asks; desktop-mcp closes the previous app when it
# starts another).
#
# Sandboxed (bubblewrap): its niri and every app on it see none of the
# user's files. Their home is $XDG_DATA_HOME/nixbook-shell/agent-home (their
# own browser profiles and logins); the user's GTK/Qt/font settings are
# visible read-only so apps look the same; the folders the user allows
# (shell setting ai.allowedFolders) read-only; the rest of the home, /mnt,
# /media, the other users' homes, /var/log, /var/lib and /etc/nixos are
# empty. Their own D-Bus session (a private bus: no keyring, portals or
# notifications of the user's), no system bus, none of the user's runtime
# sockets (session bus, audio, X11), their own process namespace (nothing
# of the user's to see or attach to). Shell settings ai.agentDesktop, both
# on unless switched off in Settings > Desktop agents:
#   - hideSystemSockets: /run is empty but for what apps need (the system's
#     programs, graphics drivers, name lookups): no daemon's socket
#     (ydotoold, which types into the user's desktop, is hidden either way);
#   - privateNetwork: their own network (pasta): the internet and the LAN,
#     not this computer's local services (127.0.0.1) nor its abstract
#     sockets (X11).
# Its niri reaches the user's desktop through a restricted socket
# (nixbook-wayland-security-context: security-context-v1), so neither it
# nor anything in the sandbox can capture the user's screen, type or click
# into it, read its clipboard or list its windows.
#
# Never open empty: started by the `nixbook-agent-desktop` user service when
# an agent starts an app (desktop-mcp's launch_app), it quits once no window
# is left (10 s without one, not in its first 15 s while the app that opened
# it starts). This script watches from outside the sandbox, where the apps
# can't reach: when niri quits otherwise, the user closed the window, which
# stops the agents (~/.local/state/nixbook-shell/agent-desktop-stopped, until
# the user switches them on again).
#
# $XDG_RUNTIME_DIR/nixbook-agent-desktop: written here only (read-only in the
# sandbox): agent-desktop.env (the nested niri's WAYLAND_DISPLAY and
# NIRI_SOCKET, once it's up), agent-desktop-input, the niri config; run/,
# writable in the sandbox, is the nested session's runtime directory.
set -euo pipefail

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "nixbook-agent-desktop: no WAYLAND_DISPLAY: it runs as a window on the user's desktop" >&2
  exit 1
fi
user_runtime="${XDG_RUNTIME_DIR:?no XDG_RUNTIME_DIR}"
control="$user_runtime/nixbook-agent-desktop"
session_runtime="$control/run"
env_file="$control/agent-desktop.env"
input_file="$control/agent-desktop-input"
config="$control/agent-desktop.kdl"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
stopped_file="${XDG_STATE_HOME:-$HOME/.local/state}/nixbook-shell/agent-desktop-stopped"
shell_config="$config_home/nixbook-shell/config.json"
agent_home="${NIXBOOK_AGENT_HOME:-$data_home/nixbook-shell/agent-home}"

rm -rf "$control"
mkdir -p "$session_runtime" "$agent_home"
chmod 700 "$control" "$session_runtime" "$agent_home"
mkdir -p "$agent_home/.config" "$agent_home/.local/share" "$agent_home/.local/state" "$agent_home/.cache"

# The user's look: links, so a theme change reaches the agent's apps too (the
# sandbox shows their targets read-only, see `look` below). Nothing with
# accounts or secrets (browsers, mail, keyrings).
look=()
link() {
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  look+=("$src")
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
  fi
}
for name in gtk-3.0 gtk-4.0 fontconfig kdeglobals qt5ct qt6ct Kvantum mimeapps.list; do
  link "$config_home/$name" "$agent_home/.config/$name"
done
for name in fonts icons themes; do
  link "$data_home/$name" "$agent_home/.local/share/$name"
done
link "$HOME/.icons" "$agent_home/.icons"
# dconf (GTK theme, fonts) is copied once: it can't be shared read-only and
# the agent's apps must not rewrite the user's settings.
if [ -e "$config_home/dconf/user" ] && [ ! -e "$agent_home/.config/dconf/user" ]; then
  mkdir -p "$agent_home/.config/dconf"
  cp "$config_home/dconf/user" "$agent_home/.config/dconf/user"
fi

kdl() { # a KDL string
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

cat >"$config" <<EOF
// Generated by nixbook-agent-desktop on each start: edits are lost.
hotkey-overlay {
    skip-at-startup
}
prefer-no-csd
// Screenshots right after an action show its result, not an animation.
animations {
    off
}
screenshot-path null
// Nothing but the app: no focus ring, border or shadow, no hot corner (the
// agent's pointer would open the overview).
layout {
    focus-ring {
        off
    }
    border {
        off
    }
    shadow {
        off
    }
}
gestures {
    hot-corners {
        off
    }
}
// Every window opens fullscreen (a browser may hide its tabs and address bar
// then: the agents are told to use its shortcuts) and stays so: its niri
// ignores the app's own requests to leave it (NIRI_KEEP_FULLSCREEN; Zen and
// Firefox restore their window size on start), maximized to the edges under it.
window-rule {
    open-fullscreen true
    open-maximized-to-edges true
}
environment {
    HOME $(kdl "$agent_home")
    XDG_CONFIG_HOME $(kdl "$agent_home/.config")
    XDG_DATA_HOME $(kdl "$agent_home/.local/share")
    XDG_STATE_HOME $(kdl "$agent_home/.local/state")
    XDG_CACHE_HOME $(kdl "$agent_home/.cache")
    NIXOS_OZONE_WL "1"
    // GTK's own file chooser: the portal's would open on the user's desktop.
    GDK_DEBUG "no-portals"
    GTK_USE_PORTAL "0"
}
// The private bus activates services (D-Bus activated apps) here, with the
// agent's home.
spawn-at-startup "dbus-update-activation-environment" "WAYLAND_DISPLAY" "DISPLAY" "NIRI_SOCKET" "HOME" "XDG_CONFIG_HOME" "XDG_DATA_HOME" "XDG_STATE_HOME" "XDG_CACHE_HOME" "XDG_RUNTIME_DIR"
EOF

# The shell's switches (Settings > Desktop agents): on unless set to false.
setting_on() {
  [ "$(jq -r "if $1 == false then \"off\" else \"on\" end" "$shell_config" 2>/dev/null || echo on)" != off ]
}
hide_system_sockets=true
setting_on .ai.agentDesktop.hideSystemSockets || hide_system_sockets=false
private_network=true
setting_on .ai.agentDesktop.privateNetwork || private_network=false

fail() {
  echo "nixbook-agent-desktop: $1" >&2
  notify-send -a "Desktop agent" -u critical "The assistant's desktop didn't start" "$1" 2>/dev/null || true
  exit 1
}

niri_pid=""
cleanup() {
  [ -z "$niri_pid" ] || kill "$niri_pid" 2>/dev/null || true
  rm -rf "$control"
}
trap cleanup EXIT
trap 'exit 143' TERM INT

# The user's desktop, through a restricted socket: served until this script
# exits (the helper reads its standard input, this holds the other end).
restricted_display="$control/wayland-restricted"
exec {restricted_fd}> >(exec nixbook-wayland-security-context "$restricted_display")
for _ in $(seq 50); do
  [ -S "$restricted_display" ] && break
  sleep 0.1
done
[ -S "$restricted_display" ] || fail "your compositor didn't give it a restricted connection (security-context-v1)"

# -- the sandbox ---------------------------------------------------------------

sandbox=(
  --ro-bind / /
  --dev /dev
  --dev-bind-try /dev/dri /dev/dri
  --proc /proc
  --tmpfs /tmp
  --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup-try
  --die-with-parent --new-session
)
# /run: only what apps need, the system's programs, graphics drivers and
# name lookups; no daemon's socket.
if $hide_system_sockets; then
  sandbox+=(--tmpfs /run)
  for path in /run/current-system /run/booted-system /run/opengl-driver /run/opengl-driver-32 \
    /run/wrappers /run/nscd /run/udev; do
    if [ -L "$path" ]; then
      sandbox+=(--symlink "$(readlink "$path")" "$path")
    elif [ -e "$path" ]; then
      sandbox+=(--ro-bind "$path" "$path")
    fi
  done
  # resolv.conf, when it points into /run (systemd-resolved, NetworkManager).
  resolv="$(readlink -f /etc/resolv.conf || true)"
  case "$resolv" in /run/*) $private_network || sandbox+=(--ro-bind "${resolv%/*}" "${resolv%/*}") ;; esac
fi
# Nobody's files: the homes, removable media, the system bus, the system's
# logs and state, its configuration's sources; ydotoold's socket (it types
# into the user's desktop), whatever the switch above.
for dir in /home /root /mnt /media /run/media /srv /run/dbus /run/ydotoold /var/log /var/lib /etc/nixos; do
  [ -d "$dir" ] && sandbox+=(--tmpfs "$dir")
done
case "$HOME" in /home/*) ;; *) sandbox+=(--tmpfs "$HOME") ;; esac
# None of the user's runtime sockets: the user's desktop only through the
# restricted socket, in $control.
sandbox+=(
  --tmpfs "$user_runtime"
  --ro-bind "$control" "$control"
  --bind "$session_runtime" "$session_runtime"
  --bind "$agent_home" "$agent_home"
)
# The programs the user's .desktop entries start (Home Manager profiles).
for path in "$HOME/.nix-profile" "$HOME/.local/state/nix" "$HOME/.local/state/home-manager" "$data_home/applications"; do
  [ -e "$path" ] && sandbox+=(--ro-bind "$path" "$path")
done
for path in ${look[@]+"${look[@]}"}; do
  sandbox+=(--ro-bind "$path" "$path")
done
# The folders the user lets AI agents read.
if [ -r "$shell_config" ]; then
  while IFS= read -r folder; do
    [ -n "$folder" ] || continue
    # shellcheck disable=SC2088 # a literal ~ from the setting, expanded here
    case "$folder" in "~") folder="$HOME" ;; "~/"*) folder="$HOME/${folder#"~/"}" ;; esac
    case "$folder" in
    /*) [ -d "$folder" ] && sandbox+=(--ro-bind "$folder" "$folder") ;;
    *) echo "nixbook-agent-desktop: ignoring $folder (not an absolute path)" >&2 ;;
    esac
  done < <(jq -r '.ai.allowedFolders // [] | .[] | strings' "$shell_config" 2>/dev/null || true)
fi

# Their own network: pasta gives it the internet and the LAN through this
# computer's connection, without its loopback (-T/-U none, --no-map-gw: the
# defaults would forward to it) and without forwarding anything in; DNS
# through pasta's forwarder (the host's resolver may be on its loopback).
network=()
if $private_network; then
  dns=169.254.1.53
  printf 'nameserver %s\n' "$dns" >"$control/resolv.conf"
  sandbox+=(--ro-bind "$control/resolv.conf" "$(readlink -f /etc/resolv.conf || echo /etc/resolv.conf)")
  network=(pasta --config-net --quiet -t none -u none -T none -U none --no-map-gw --dns-forward "$dns" --)
fi

# The system's session bus configuration (NixOS: /etc/dbus-1), else dbus's own.
bus_config=()
if [ ! -e /etc/dbus-1/session.conf ]; then
  bus_config=(--config-file "$(dirname "$(command -v dbus-daemon)")/../share/dbus-1/session.conf")
fi

${network[@]+"${network[@]}"} bwrap "${sandbox[@]}" \
  --setenv XDG_RUNTIME_DIR "$session_runtime" \
  --setenv WAYLAND_DISPLAY "$restricted_display" \
  --setenv NIRI_WINIT_IGNORE_INPUT 1 \
  --setenv NIRI_WINIT_ALLOW_INPUT_FILE "$input_file" \
  --setenv NIRI_WINIT_TITLE "Assistant's desktop" \
  --setenv NIRI_WINIT_APP_ID nixbook-agent-desktop \
  --setenv NIRI_KEEP_FULLSCREEN 1 \
  --unsetenv DBUS_SESSION_BUS_ADDRESS --unsetenv DISPLAY --unsetenv NIRI_SOCKET \
  -- dbus-run-session "${bus_config[@]}" -- niri -c "$config" {restricted_fd}>&- &
niri_pid=$!

# -- watching it, from outside the sandbox ----------------------------------------

# Its sockets, found before any app runs (an app could make others later).
niri_socket=""
for _ in $(seq 150); do
  niri_socket="$(find "$session_runtime" -maxdepth 1 -name 'niri.wayland-*.sock' -type s -print -quit)"
  [ -n "$niri_socket" ] && break
  kill -0 "$niri_pid" 2>/dev/null || break
  sleep 0.1
done
if [ -z "$niri_socket" ]; then
  $private_network && fail "niri didn't start; its private network (pasta) may be the cause: the journal says (journalctl --user -u nixbook-agent-desktop), Settings > Desktop agents can turn it off"
  fail "niri didn't start (journalctl --user -u nixbook-agent-desktop)"
fi
display="${niri_socket##*/niri.}"
display="${display%.*.sock}"
umask 077
printf 'WAYLAND_DISPLAY=%s\nNIRI_SOCKET=%s\n' "$session_runtime/$display" "$niri_socket" >"$env_file.tmp"
mv "$env_file.tmp" "$env_file"

closing=false
idle=0
uptime=0
while kill -0 "$niri_pid" 2>/dev/null; do
  sleep 1
  uptime=$((uptime + 1))
  windows="$(NIRI_SOCKET="$niri_socket" niri msg --json windows 2>/dev/null)" || continue
  if [ "$windows" = "[]" ]; then
    idle=$((idle + 1))
  else
    idle=0
  fi
  if [ "$idle" -ge 10 ] && [ "$uptime" -ge 15 ]; then
    closing=true
    NIRI_SOCKET="$niri_socket" niri msg action quit --skip-confirmation || true
    break
  fi
done
wait "$niri_pid" || true
niri_pid=""
# Not emptied, not stopped as a service (that ends this in the TERM trap): the
# user closed the window, which stops the agents.
if ! $closing; then
  mkdir -p "$(dirname "$stopped_file")"
  echo stopped >"$stopped_file"
fi
