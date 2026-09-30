#!/usr/bin/env bash
# The apps coloured like the shell (programs.nixbook-shell.appTheming): render
# their templates from the palette the shell shows (the wallpaper's or a
# theme variant's, passed by services/AppTheming.qml as JSON), then have the
# running apps pick the new colours up where they can.
#   Qt / KDE: the scheme goes to ~/.local/share/color-schemes (KDE apps load it
#     by name) and its colour sections into ~/.config/kdeglobals, then running
#     KDE apps are told the palette changed; qt6ct/qt5ct reread their colour
#     scheme when their config directory changes.
#   Vesktop reloads its themes folder by itself; Zen and YouTube Music read
#   theirs when they start (or reload the page).
#
# Usage: apply-app-colors.sh PALETTE_JSON

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$XDG_STATE_HOME/quickshell/user/generated/apps"
APPS_CONFIG="$XDG_CONFIG_HOME/nixbook-shell/app-theming.toml"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/nixbook-shell/config.json"

# The templates the Home Manager module set up, and the "Apps" switch
# (appearance.wallpaperTheming.enableQtApps).
[ -f "$APPS_CONFIG" ] || exit 0
if [ -f "$SHELL_CONFIG_FILE" ] &&
  [ "$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")" == "false" ]; then
  exit 0
fi
"$SCRIPT_DIR/render-app-colors.py" "$APPS_CONFIG" <<<"${1:?usage: apply-app-colors.sh PALETTE_JSON}" || exit 1

qt_colors="$APPS_DIR/qt-colors.conf"
if [ -f "$qt_colors" ]; then
  mkdir -p "$XDG_DATA_HOME/color-schemes"
  cp --no-preserve=mode "$qt_colors" "$XDG_DATA_HOME/color-schemes/NixbookShell.colors"
  "$SCRIPT_DIR/apply-kde-colors.py" "$qt_colors" "$XDG_CONFIG_HOME/kdeglobals"
  # KGlobalSettings::PaletteChanged (0): running KDE apps reread kdeglobals.
  gdbus emit --session --object-path /KGlobalSettings \
    --signal org.kde.KGlobalSettings.notifyChange 0 0 >/dev/null 2>&1 || true
  for dir in "$XDG_CONFIG_HOME/qt6ct" "$XDG_CONFIG_HOME/qt5ct"; do
    if [ -d "$dir" ]; then
      rm -f "$dir/.nixbook-shell-palette"
      : >"$dir/.nixbook-shell-palette"
    fi
  done
fi

# add_to_list FILE JQ_PATH VALUE: VALUE added to the JSON array at JQ_PATH of
# FILE (the array created as needed), everything else kept. Only once the app
# has written its settings file: one we'd create could stand in for its
# defaults.
add_to_list() {
  local file="$1" path="$2" value="$3" tmp
  [ -f "$file" ] || return 0
  jq -e --arg v "$value" "($path // []) | index(\$v)" "$file" >/dev/null 2>&1 && return 0
  tmp=$(mktemp "$file.XXXXXX") || return 0
  if jq --arg v "$value" "$path = (($path // []) + [\$v])" "$file" >"$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
  fi
}

# Vesktop: the theme is in its themes folder; turn it on.
if [ -f "$XDG_CONFIG_HOME/vesktop/themes/nixbook-shell.css" ]; then
  add_to_list "$XDG_CONFIG_HOME/vesktop/settings/settings.json" .enabledThemes nixbook-shell.css
fi

# YouTube Music (pear-desktop): its CSS themes are file paths.
if [ -f "$APPS_DIR/youtube-music.css" ]; then
  add_to_list "$XDG_CONFIG_HOME/YouTube Music/config.json" .options.themes "$APPS_DIR/youtube-music.css"
fi
