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
# click or type into the agent's desktop. Closing it stops the agent:
# desktop-mcp doesn't start it again, only the user does (`desktop agent`,
# Mod+Shift+A). The user takes over (`desktop interact`, Mod+Ctrl+A: clicks
# and keys get through while $XDG_RUNTIME_DIR/nixbook-desktop-mcp/
# agent-desktop-input exists; off again on each start). Nothing is on it but the one app the agent works in, filling
# it edge to edge (desktop-mcp closes the previous app when it starts
# another): no bar, no borders, no layout to look after.
#
# Its apps are the agent's, not the user's:
#   - their own home ($XDG_DATA_HOME/nixbook-shell/agent-home): their own
#     browser profiles, history and logins, with the user's GTK/Qt/font
#     settings linked in so apps look the same;
#   - their own D-Bus session (a private bus): GApplication/Firefox remoting,
#     portals and notifications don't reach the user's session, so a second
#     copy of an app the user has open starts here instead of handing its
#     window to the user's copy.
#
# Never open empty: started by the `nixbook-agent-desktop` user service when
# an agent starts an app (desktop-mcp's launch_app), it quits by itself once
# no window is left (`--watch`, run inside it: 10 s without a window, not in
# its first 15 s while the app that opened it starts), leaving agent-desktop.closing so this doesn't take it for
# the user closing the window. That (niri quitting without the marker) stops
# the agents: ~/.local/state/nixbook-shell/agent-desktop-stopped, until the
# user switches them on again.
#
# Writes WAYLAND_DISPLAY and NIRI_SOCKET of the nested niri to
# $XDG_RUNTIME_DIR/nixbook-desktop-mcp/agent-desktop.env once it's up, and
# removes the file when it exits.
set -euo pipefail

runtime="${XDG_RUNTIME_DIR:?no XDG_RUNTIME_DIR}/nixbook-desktop-mcp"
env_file="$runtime/agent-desktop.env"
input_file="$runtime/agent-desktop-input"
closing_file="$runtime/agent-desktop.closing"

# Inside the agent desktop (niri's first spawned process, so its sockets are
# up): announce it, then close it once it's empty.
if [ "${1:-}" = --watch ]; then
  # The private bus activates services (D-Bus activated apps) here, with the
  # agent's home.
  dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET HOME \
    XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
  umask 077
  printf 'WAYLAND_DISPLAY=%s\nNIRI_SOCKET=%s\n' "$WAYLAND_DISPLAY" "$NIRI_SOCKET" >"$env_file.tmp"
  mv "$env_file.tmp" "$env_file"
  idle=0
  uptime=0
  while sleep 1; do
    uptime=$((uptime + 1))
    if ! windows="$(niri msg --json windows 2>/dev/null)"; then
      # niri gone (closed by the user, or crashed): nothing left to watch.
      [ -S "$NIRI_SOCKET" ] || exit 0
      continue
    fi
    if [ "$windows" = "[]" ]; then
      idle=$((idle + 1))
    else
      idle=0
    fi
    if [ "$idle" -ge 10 ] && [ "$uptime" -ge 15 ]; then
      : >"$closing_file"
      niri msg action quit --skip-confirmation
      exit 0
    fi
  done
fi
stopped_file="${XDG_STATE_HOME:-$HOME/.local/state}/nixbook-shell/agent-desktop-stopped"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
config="$runtime/agent-desktop.kdl"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
agent_home="${NIXBOOK_AGENT_HOME:-$data_home/nixbook-shell/agent-home}"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "nixbook-agent-desktop: no WAYLAND_DISPLAY: it runs as a window on the user's desktop" >&2
  exit 1
fi
mkdir -p "$runtime" "$agent_home"
chmod 700 "$runtime" "$agent_home"
mkdir -p "$agent_home/.config" "$agent_home/.local/share" "$agent_home/.local/state" "$agent_home/.cache"

# The user's look: links, so a theme change reaches the agent's apps too.
# Nothing with accounts or secrets (browsers, mail, keyrings) is linked.
link() {
  local src="$1" dst="$2"
  if [ -e "$src" ] && [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
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
// Every window fills the whole screen, edge to edge (maximized, not
// fullscreen: a fullscreen browser hides its tabs and address bar).
window-rule {
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
spawn-at-startup "bash" $(kdl "$self") "--watch"
EOF

rm -f "$env_file" "$input_file" "$closing_file"
trap 'rm -f "$env_file" "$input_file"' EXIT
trap 'exit 143' TERM INT
# The system's session bus configuration (NixOS: /etc/dbus-1), else dbus's own.
bus_config=()
if [ ! -e /etc/dbus-1/session.conf ]; then
  bus_config=(--config-file "$(dirname "$(command -v dbus-daemon)")/../share/dbus-1/session.conf")
fi
# Not exec: the trap removes the env file when niri exits.
NIRI_WINIT_IGNORE_INPUT=1 NIRI_WINIT_ALLOW_INPUT_FILE="$input_file" \
  NIRI_WINIT_TITLE="Assistant's desktop" NIRI_WINIT_APP_ID=nixbook-agent-desktop \
  dbus-run-session "${bus_config[@]}" -- niri -c "$config"
# Back here only when niri quit by itself (stopping the service ends this in
# the TERM trap, a crash with set -e): emptied by the watcher, or the user
# closed the window, which stops the agents.
if [ -e "$closing_file" ]; then
  rm -f "$closing_file"
else
  mkdir -p "$(dirname "$stopped_file")"
  echo stopped >"$stopped_file"
fi
