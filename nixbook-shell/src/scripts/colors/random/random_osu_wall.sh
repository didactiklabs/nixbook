#!/usr/bin/env bash

get_pictures_dir() {
  if command -v xdg-user-dir &>/dev/null; then
    xdg-user-dir PICTURES
    return
  fi

  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
  if [ -f "$config_file" ]; then
    local pictures_path
    pictures_path=$(
      source "$config_file" >/dev/null 2>&1
      echo "$XDG_PICTURES_DIR"
    )
    echo "${pictures_path/#\$HOME/$HOME}"
    return
  fi

  echo "$HOME/Pictures"
}

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PICTURES_DIR=$(get_pictures_dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$PICTURES_DIR/Wallpapers"

response=$(curl "https://osu.ppy.sh/api/v2/seasonal-backgrounds")
images=$(echo "$response" | jq '.backgrounds | length' -r)
[[ $images =~ ^[1-9][0-9]*$ ]] || exit 1
randomIndex=$((RANDOM % images))
link=$(echo "$response" | jq ".backgrounds[$randomIndex].url" -r)
ext=$(echo "$link" | awk -F. '{print $NF}')
ext=${ext%%[?#]*}
# The link and its extension come from the server: only a web URL, and an
# extension that can't reach outside the Wallpapers folder.
if [[ ! $link =~ ^https?:// || ! $ext =~ ^[A-Za-z0-9]+$ ]]; then
  echo "No usable image link in the response" >&2
  exit 1
fi
downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper.$ext"
illogicalImpulseConfigPath="$HOME/.config/nixbook-shell/config.json"
currentWallpaperPath=$(jq -r '.background.wallpaperPath' "$illogicalImpulseConfigPath")
if [ "$downloadPath" == "$currentWallpaperPath" ]; then
  downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper-1.$ext"
fi
curl -f --proto =http,https --proto-redir =http,https "$link" -o "$downloadPath" || exit 1
"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"
