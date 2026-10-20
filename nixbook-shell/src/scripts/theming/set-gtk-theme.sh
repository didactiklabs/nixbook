#!/usr/bin/env bash
# Apply GTK widget theme. Usage: set-gtk-theme.sh <theme>
set -u

theme="${1:-}"
[[ -z $theme ]] && {
  echo "usage: $0 <gtk-theme>" >&2
  exit 1
}

# Files Home Manager links from the Nix store are left alone: `sed -i` would
# turn the link into a plain file (which the next switch replaces, losing the
# change) and writing through it fails. gsettings carries the choice there.
nix_managed() { [[ -L $1 && $(readlink -f -- "$1") == /nix/store/* ]]; }

# The theme name as a sed replacement: `|`, `&` and `\` taken literally
# (a name with a `|` ended the s command, and what followed became its flags).
sed_repl() {
  local s=${1//\\/\\\\}
  s=${s//&/\\&}
  printf '%s' "${s//|/\\|}"
}

set_ini_key() { # file key value
  local file="$1" key="$2" value="$3"
  nix_managed "$file" && return 0
  mkdir -p "$(dirname "$file")"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=$(sed_repl "$value")|" "$file"
  else
    [[ -f $file ]] || echo "[Settings]" >"$file"
    echo "${key}=${value}" >>"$file"
  fi
}

gsettings set org.gnome.desktop.interface gtk-theme "$theme" 2>/dev/null

set_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-theme-name "$theme"
set_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-theme-name "$theme"

# GTK 2
GTK2_CONFIG="$HOME/.gtkrc-2.0"
if nix_managed "$GTK2_CONFIG"; then
  :
elif grep -q "^gtk-theme-name=" "$GTK2_CONFIG" 2>/dev/null; then
  sed -i "s|^gtk-theme-name=.*|gtk-theme-name=\"$(sed_repl "$theme")\"|" "$GTK2_CONFIG"
else
  echo "gtk-theme-name=\"$theme\"" >>"$GTK2_CONFIG"
fi

exit 0
