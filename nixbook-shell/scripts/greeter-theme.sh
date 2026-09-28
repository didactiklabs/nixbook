#!/usr/bin/env bash
# What the login screen (the nixbook-shell greeter, greeter.nix) needs from
# the user's nixbook-shell settings, exported into $NB_OUT, readable by the
# greeter (which can't read the home directory):
#   settings.json  the look: appearance (theme, variants, fonts…), time, lock
#   colors.json    the shell's generated Material palette (colours only)
#   avatar         the account picture (profile.avatarPath)
#   background     the login screen wallpaper (NB_COPY_BACKGROUND=1)
#   bg             the first frame's colour (the theme's background)
#
# Run by greeter.nix twice: at build time from the settings set in Nix (the
# fallback, no files copied), and as the user by the
# nixbook-shell-greeter-theme service whenever the shell's settings or
# wallpaper palette change. Everything taken from the settings is validated:
# this runs as the user and the greeter loads the result.
#
# Env: NB_OUT, NB_PALETTES (the themes and their palettes, JSON, from
# scripts/theme-palettes.py); optional NB_CONFIG (config.json), NB_COLORS (the
# shell's generated Material palette), NB_DEFAULT_BACKGROUND (the NixOS
# option's wallpaper), NB_COPY_BACKGROUND=1.
set -euo pipefail

: "${NB_OUT:?}" "${NB_PALETTES:?}"
config="${NB_CONFIG:-}"
colors="${NB_COLORS:-}"
[ -n "$config" ] && [ -s "$config" ] && jq -e 'type == "object"' "$config" >/dev/null 2>&1 || config=""
[ -n "$colors" ] && [ -s "$colors" ] && jq -e 'type == "object"' "$colors" >/dev/null 2>&1 || colors=""

theme=$(jq -n \
  --slurpfile palettes "$NB_PALETTES" \
  --slurpfile cfgs "${config:-/dev/null}" \
  --slurpfile m3s "${colors:-/dev/null}" '
  def color($v): ($v | type) == "string" and ($v | test("^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$"));

  ($cfgs[0] // {}) as $cfg
  | ($m3s[0] // {}) as $m3
  | ($palettes[0]) as $registry
  | ($cfg.appearance // {}) as $a
  # Themes.current: the legacy Persona switch, else a known theme, else the default.
  | (if ($a.persona // {}).enable == true and $registry.themes.persona != null then "persona"
     elif ($a.theme | type) == "string" and $registry.themes[$a.theme] != null then $a.theme
     else $registry.default end) as $themeId
  | ($registry.themes[$themeId]) as $themeDef
  | ($a[$themeId] // {} | if type == "object" then . else {} end) as $p
  | (if ($themeDef.variants | index($p.variant)) != null then $p.variant
     else ($themeDef.default // "") end) as $variant
  | ($themeDef.palettes[$variant]) as $spec
  | {
      theme: $themeId,
      variant: $variant,
      # The first frame: the theme palette background, else the generated one.
      bg: (if $spec != null and ($p.palette != false) then $spec.background
           elif color($m3.background) then $m3.background
           else "#141313" end),
      # What the greeter styles itself with: only the look (never commands,
      # accounts or paths but the avatar, read below).
      settings: ({
        appearance: ($a | if type == "object" then del(.themeWallpapers, .themeLockWallpapers, .themeLoginWallpapers) else {} end),
        time: ($cfg.time // {} | if type == "object" then . else {} end),
        lock: ($cfg.lock // {} | if type == "object" then {materialShapeChars} else {} end),
        language: ($cfg.language // {} | if type == "object" then {ui} else {} end)
      }),
      colors: ($m3 | with_entries(select(.value | color(.)))),
      avatar: ($cfg.profile.avatarPath // "" | if type == "string" then . else "" end),
      walls: [
        ($cfg.background.greeterWall // ""),
        "@default@",
        ($cfg.background.lockWall // ""),
        ($cfg.background.wallpaperPath // "")
      ]
    }')

get() { jq -r "$1" <<<"$theme"; }

mkdir -p "$NB_OUT"
# Written atomically, readable by the greeter.
put() {
  printf '%s\n' "$2" >"$NB_OUT/.$1.tmp"
  chmod 0644 "$NB_OUT/.$1.tmp"
  mv -f "$NB_OUT/.$1.tmp" "$NB_OUT/$1"
}
put settings.json "$(jq -c '.settings | del(.. | nulls)' <<<"$theme")"
put colors.json "$(jq -c .colors <<<"$theme")"
put bg "$(get .bg)"

# ---------------------------------------------------------------- wallpaper
# The first of: the login screen wallpaper (settings), the NixOS option's,
# the lock screen's, the desktop's. Copied (a video: one frame of it), so the
# greeter never reads the home directory.
if [ "${NB_COPY_BACKGROUND:-0}" = 1 ]; then
  src=""
  while IFS= read -r wall; do
    [ "$wall" = "@default@" ] && wall="${NB_DEFAULT_BACKGROUND:-}"
    wall="${wall#file://}"
    if [ -n "$wall" ] && [ -f "$wall" ] && [ -r "$wall" ]; then
      src="$wall"
      break
    fi
  done < <(get '.walls[]')

  if [ -z "$src" ]; then
    rm -f "$NB_OUT/background" "$NB_OUT/background.src"
  else
    stamp="$src $(stat -c '%s %Y' -- "$src")"
    if [ "$(cat "$NB_OUT/background.src" 2>/dev/null)" != "$stamp" ]; then
      tmp="$NB_OUT/.background.tmp"
      rm -f "$tmp"
      case "${src,,}" in
      *.mp4 | *.webm | *.mkv | *.avi | *.mov | *.gif)
        ffmpeg -loglevel error -y -i "$src" -frames:v 1 -f image2 -c:v png "$tmp" ||
          rm -f "$tmp"
        ;;
      *) cp -- "$src" "$tmp" ;;
      esac
      if [ -s "$tmp" ]; then
        chmod 0644 "$tmp"
        mv -f "$tmp" "$NB_OUT/background"
        printf '%s\n' "$stamp" >"$NB_OUT/background.src"
      fi
    fi
  fi
fi

# ------------------------------------------------------------------ avatar
# The account picture, copied (an image only, like the wallpaper).
if [ "${NB_COPY_BACKGROUND:-0}" = 1 ]; then
  avatar=$(get .avatar)
  avatar="${avatar#file://}"
  if [ -n "$avatar" ] && [ -f "$avatar" ] && [ -r "$avatar" ] &&
    case "${avatar,,}" in *.png | *.jpg | *.jpeg | *.webp | *.svg) true ;; *) false ;; esac then
    cp -- "$avatar" "$NB_OUT/.avatar.tmp" && chmod 0644 "$NB_OUT/.avatar.tmp" && mv -f "$NB_OUT/.avatar.tmp" "$NB_OUT/avatar"
  else
    rm -f "$NB_OUT/avatar"
  fi
fi
