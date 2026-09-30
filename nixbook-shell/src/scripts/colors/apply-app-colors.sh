#!/usr/bin/env bash
# The apps coloured like the shell (Settings > Appearance > Color generation >
# Apps): render their templates (app-templates/) from the palette the shell
# shows (the wallpaper's or a theme variant's, passed by
# services/AppTheming.qml as JSON), then have the running apps pick the new
# colours up where they can.
#   qt: the scheme goes to ~/.local/share/color-schemes (KDE apps load it by
#     name) and its colour sections into ~/.config/kdeglobals, then running
#     KDE apps are told the palette changed; qt6ct/qt5ct (set up by
#     programs.nixbook-shell.appTheming.qt) reread their colour scheme when
#     their config directory changes.
#   vesktop: the theme in its themes folder, which it reloads by itself.
#   zen: the CSS imported by each profile's userChrome.css (zen-theme.py);
#     Zen only reads it at startup, so a running Zen offers a restart.
# An app switched off gets its setup undone (Qt: its files just stop being
# updated).
#
# Usage: apply-app-colors.sh PALETTE_JSON [APP,APP...]

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/app-templates"
APPS_DIR="$XDG_STATE_HOME/quickshell/user/generated/apps"

palette="${1:?usage: apply-app-colors.sh PALETTE_JSON [APP,APP...]}"
enabled=",${2:-},"
on() { [[ "$enabled" == *",$1,"* ]]; }

vesktop_css="$XDG_CONFIG_HOME/vesktop/themes/nixbook-shell.css"
vesktop_settings="$XDG_CONFIG_HOME/vesktop/settings/settings.json"

# edit_list FILE JQ_PATH add|del VALUE: VALUE added to / removed from the JSON
# array at JQ_PATH of FILE, everything else kept. Only once the app has
# written its settings file: one we'd create could stand in for its defaults.
edit_list() {
  local file="$1" path="$2" op="$3" value="$4" tmp filter
  [ -f "$file" ] || return 0
  if [ "$op" = add ]; then
    jq -e --arg v "$value" "($path // []) | index(\$v)" "$file" >/dev/null 2>&1 && return 0
    filter="$path = (($path // []) + [\$v])"
  else
    jq -e --arg v "$value" "($path // []) | index(\$v)" "$file" >/dev/null 2>&1 || return 0
    filter="$path = (($path // []) - [\$v])"
  fi
  tmp=$(mktemp "$file.XXXXXX") || return 0
  if jq --arg v "$value" "$filter" "$file" >"$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
  fi
}

# The templates of the apps switched on, and where they go.
pairs=()
on qt && pairs+=("$TEMPLATES/qt-colors.conf" "$APPS_DIR/qt-colors.conf")
on vesktop && pairs+=("$TEMPLATES/vesktop.css" "$vesktop_css")
if on zen; then
  while IFS= read -r profile; do
    [ -n "$profile" ] && pairs+=("$TEMPLATES/zen-userChrome.css" "$profile/chrome/nixbook-shell.css")
  done < <("$SCRIPT_DIR/zen-theme.py" profiles)
fi
changed=()
if [ ${#pairs[@]} -gt 0 ]; then
  mapfile -t changed < <("$SCRIPT_DIR/render-app-colors.py" "${pairs[@]}" <<<"$palette")
fi
was_changed() {
  local f
  for f in "${changed[@]}"; do [ "$f" = "$1" ] && return 0; done
  return 1
}

if on qt && was_changed "$APPS_DIR/qt-colors.conf"; then
  mkdir -p "$XDG_DATA_HOME/color-schemes"
  cp --no-preserve=mode "$APPS_DIR/qt-colors.conf" "$XDG_DATA_HOME/color-schemes/NixbookShell.colors"
  "$SCRIPT_DIR/apply-kde-colors.py" "$APPS_DIR/qt-colors.conf" "$XDG_CONFIG_HOME/kdeglobals"
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

# Vesktop: the theme is in its themes folder; turn it on.
if on vesktop; then
  edit_list "$vesktop_settings" .enabledThemes add nixbook-shell.css
else
  edit_list "$vesktop_settings" .enabledThemes del nixbook-shell.css
  rm -f "$vesktop_css"
fi

# Zen: set up where it's closed; a running Zen showing old colours gets a
# "Restart Zen" notification (the previous one replaced, its wait dropped).
zen_notify() {
  local state="$XDG_RUNTIME_DIR/nixbook-shell-zen-restart" id="" pid
  [ -f "$state.id" ] && id=$(<"$state.id")
  if [ -f "$state.pid" ]; then
    pid=$(<"$state.pid")
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
  fi
  (
    notify-send --app-name "Zen Browser" --print-id ${id:+--replace-id "$id"} \
      --action restart="Restart Zen" \
      "Zen Browser" "Restart it to show the new colours. Your tabs are restored." |
      {
        read -r new_id && printf '%s\n' "$new_id" >"$state.id"
        read -r action && [ "$action" = restart ] && "$SCRIPT_DIR/zen-theme.py" restart
      }
    rm -f "$state.pid"
  ) &
  printf '%s\n' "$!" >"$state.pid"
}
if on zen; then
  "$SCRIPT_DIR/zen-theme.py" sync "${changed[@]}"
  [ $? -eq 3 ] && zen_notify
else
  "$SCRIPT_DIR/zen-theme.py" remove
fi
exit 0
