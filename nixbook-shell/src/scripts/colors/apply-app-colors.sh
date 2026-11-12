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
#   youtube-music: CSS its Electron bridge (electron-bridge.py's `style`) puts
#     in the running app's page, and again after each load of it; the app
#     only has a dark look, so it gets the palette's dark version.
#   gmail: the same for Meru (Gmail's app, bridged as "gmail"), in each of
#     its Gmail pages (one per account); light or dark as the palette is.
#   youtube: the same for ZenPlay (YouTube's app, bridged as "youtube"): its
#     own window (toolbar, splash) and the YouTube page, whose design tokens
#     the bridge's styling script maps to the palette
#     (electron/youtube.style.js); YouTube's own light/dark setting follows.
#   zen: the CSS imported by each profile's userChrome.css (zen-theme.py);
#     Zen only reads it at startup, so a running Zen offers a restart.
#   zen-pages: web pages in the palette's colours (Dark Reader's library in
#     nixbook's Zen extension, zen/pages-theme.js): the colours sent to the
#     running Zen through its bridge, live; a Zen started later gets them
#     from the bridge (zen-bridge.py reads the file).
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
ytm_css="$APPS_DIR/youtube-music.css"
ytm_settings="$XDG_CONFIG_HOME/YouTube Music/config.json"
ytm_socket="$XDG_RUNTIME_DIR/nixbook-electron/youtube-music.sock"
gmail_css="$APPS_DIR/gmail.css"
gmail_socket="$XDG_RUNTIME_DIR/nixbook-electron/gmail.sock"
youtube_css="$APPS_DIR/youtube.css"
youtube_socket="$XDG_RUNTIME_DIR/nixbook-electron/youtube.sock"
zen_pages="$APPS_DIR/zen-pages.json"
zen_socket="$XDG_RUNTIME_DIR/nixbook-zen/bridge.sock"

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
on youtube-music && pairs+=("$TEMPLATES/youtube-music.css" "$ytm_css")
on gmail && pairs+=("$TEMPLATES/gmail.css" "$gmail_css")
on youtube && pairs+=("$TEMPLATES/youtube.css" "$youtube_css")
on zen-pages && pairs+=("$TEMPLATES/zen-pages.json" "$zen_pages")
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

# KDE apps that pinned another colour scheme in their own rc (Dolphin's View >
# Color Scheme, DankMaterialShell's DankMatugen) follow kdeglobals again.
if on qt; then
  rcs=()
  for rc in "$XDG_CONFIG_HOME"/*rc; do
    [ -f "$rc" ] && [ "$rc" != "$XDG_CONFIG_HOME/kdeglobals" ] && rcs+=("$rc")
  done
  [ ${#rcs[@]} -gt 0 ] && "$SCRIPT_DIR/apply-kde-colors.py" --unpin "${rcs[@]}" >/dev/null
fi

# YouTube Music (pear-desktop), Gmail (Meru) and YouTube (ZenPlay): their
# bridge puts the file in the running app (none there: the app's own look again); a bridge
# starting later reads it itself. An older nixbook listed YouTube Music's
# file in the app's own CSS themes: no longer (two copies of different ages
# would fight).
restyle() {
  [ -S "$1" ] || return 0
  printf '{"cmd":"style"}\n' | socat -t 5 - "UNIX-CONNECT:$1" >/dev/null 2>&1 || true
}
edit_list "$ytm_settings" .options.themes del "$ytm_css"
# style_app NAME CSS SOCKET
style_app() {
  if on "$1"; then
    was_changed "$2" && restyle "$3"
  elif [ -f "$2" ]; then
    rm -f "$2"
    restyle "$3"
  fi
}
style_app youtube-music "$ytm_css" "$ytm_socket"
style_app gmail "$gmail_css" "$gmail_socket"
style_app youtube "$youtube_css" "$youtube_socket"

# Zen's web pages: the colours to the running Zen (null: pages left as they
# are).
zen_pages_send() {
  [ -S "$zen_socket" ] || return 0
  printf '%s\n' "$1" | socat -t 10 - "UNIX-CONNECT:$zen_socket" >/dev/null 2>&1 || true
}
if on zen-pages; then
  was_changed "$zen_pages" && zen_pages_send "$(jq -c '{cmd: "theme", theme: .}' "$zen_pages")"
elif [ -f "$zen_pages" ]; then
  rm -f "$zen_pages"
  zen_pages_send '{"cmd":"theme","theme":null}'
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
