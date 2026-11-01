#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="nixbook-shell"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
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

# The ttys kitty's windows run on ("pts/N", one per line): the programs it
# started are its children. Those never get raw escape sequences: the reload
# above recolours them (and drops colours an escape code had set), while a
# sequence written from outside lands in the middle of whatever the program
# is drawing. A TUI writing without blocking (node's, so Claude Code,
# opencode…) has its frame split across write() calls, and our bytes cut one
# of its escape sequences in two: the rest shows up as text
# ("29;203;121m###"). NIXBOOK_SHELL_KITTY_TTYS stands in for the tests.
kitty_ttys() {
  if [[ -n ${NIXBOOK_SHELL_KITTY_TTYS+set} ]]; then
    tr ' ' '\n' <<<"$NIXBOOK_SHELL_KITTY_TTYS"
    return 0
  fi
  local pids
  pids=$(pidof kitty) || return 0
  ps -o tty= --ppid "${pids// /,}" 2>/dev/null | tr -d ' '
}

# The open terminals' devices, kitty's left out (see kitty_ttys).
other_ptys() {
  local skip file
  skip=$'\n'$(kitty_ttys)$'\n'
  for file in "$PTS_DIR"/*; do
    [[ $file =~ /([0-9]+)$ ]] || continue
    [[ $skip == *$'\n'"pts/${BASH_REMATCH[1]}"$'\n'* ]] && continue
    printf '%s\n' "$file"
  done
}

# --reset-terminal: terminal theming was turned off; give every open
# terminal its own colours back (OSC 104 palette, 110/111/112 foreground,
# background, cursor, 117/119 selection; kitty by reloading without the
# theme), and drop the generated files so kitty and new shells don't pick
# them up again.
if [[ ${1:-} == "--reset-terminal" ]]; then
  rm -f "$GENERATED_TERMINAL/kitty-theme.conf" "$GENERATED_TERMINAL/sequences.txt"
  reload_kitty
  while IFS= read -r file; do
    { printf '\e]104\e\\\e]110\e\\\e]111\e\\\e]112\e\\\e]117\e\\\e]119\e\\' >"$file"; } 2>/dev/null &
    disown || true
  done < <(other_ptys)
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

colornames=$(cut -d: -f1 "$STATE_DIR"/user/generated/material_colors.scss)
colorstrings=$(cut -d: -f2 "$STATE_DIR"/user/generated/material_colors.scss | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
# shellcheck disable=SC2206 # one colour per line (IFS), no glob characters
colorlist=($colornames) # Array of color names
# shellcheck disable=SC2206
colorvalues=($colorstrings) # Array of color values

# Every placeholder ("$name #") replaced by its colour, in one sed run per
# file (it used to be one run per colour: ~130 processes per switch).
colorsed=''
for i in "${!colorlist[@]}"; do
  colorsed+="s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g"$'\n'
done

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
  sed -i "$colorsed" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf

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
  sed -i "$colorsed" "$STATE_DIR"/user/generated/terminal/sequences.txt

  # Terminals other than kitty (which reloads its theme): written to the open
  # ones, replayed by each new interactive shell (hm-module.nix).
  while IFS= read -r file; do
    {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
    } 2>/dev/null &
    disown || true
  done < <(other_ptys)
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
