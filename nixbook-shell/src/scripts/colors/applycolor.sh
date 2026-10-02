#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="nixbook-shell"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The open terminals' devices (overridable for the tests).
PTS_DIR="${NIXBOOK_SHELL_PTS_DIR:-/dev/pts}"
GENERATED_TERMINAL="$STATE_DIR/user/generated/terminal"

# kitty reads the generated theme through the Home Manager module's
# `include` (hm-module.nix): SIGUSR1 makes every kitty reload it.
reload_kitty() {
  local pids
  pids=$(pidof kitty) || return 0
  # shellcheck disable=SC2086 # one pid per word
  kill -SIGUSR1 $pids 2>/dev/null || true
}

# --reset-terminal: terminal theming was turned off; give every open
# terminal its own colours back (OSC 104 palette, 110/111/112 foreground,
# background, cursor, 117/119 selection), and drop the generated files so
# kitty and new shells don't pick them up again.
if [[ ${1:-} == "--reset-terminal" ]]; then
  rm -f "$GENERATED_TERMINAL/kitty-theme.conf" "$GENERATED_TERMINAL/sequences.txt"
  reload_kitty
  for file in "$PTS_DIR"/*; do
    if [[ $file =~ /[0-9]+$ ]]; then
      { printf '\e]104\e\\\e]110\e\\\e]111\e\\\e]112\e\\\e]117\e\\\e]119\e\\' >"$file"; } 2>/dev/null &
      disown || true
    fi
  done
  exit 0
fi
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_kitty() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Writable copy: the template is in the read-only Nix store, and a
  # read-only copy makes every later cp fail (colours never updated again).
  rm -f "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  cp --no-preserve=mode "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  done

  reload_kitty
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Writable copy: the template is in the read-only Nix store, and a
  # read-only copy makes every later cp fail (colours never updated again).
  rm -f "$STATE_DIR"/user/generated/terminal/sequences.txt
  cp --no-preserve=mode "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  for file in "$PTS_DIR"/*; do
    if [[ $file =~ /[0-9]+$ ]]; then
      {
        cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } &
      disown || true
    fi
  done
}

apply_term() {
  apply_kitty
  apply_anyterm
}

apply_qt() {
  sh "$CONFIG_DIR/scripts/kvantum/materialQT.sh"          # generate kvantum theme
  python "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" # apply config colors
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/nixbook-shell/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

# apply_qt & # Qt theming is already handled by kde-material-colors
