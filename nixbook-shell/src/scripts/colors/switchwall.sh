#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="nixbook-shell"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/nixbook-shell/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

# Apps themed from the shell's palette (programs.nixbook-shell.appTheming:
# Qt/KDE, Vesktop, Zen, YouTube Music): the Home Manager module writes a
# matugen config with their templates; they get the same source colour,
# scheme and mode as the shell. Gated by the "Apps" switch
# (appearance.wallpaperTheming.enableQtApps).
handle_app_colors() {
  local apps_config="$XDG_CONFIG_HOME/nixbook-shell/matugen-apps.toml"
  [ -f "$apps_config" ] || return
  if [ -f "$SHELL_CONFIG_FILE" ] &&
    [ "$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")" == "false" ]; then
    return
  fi
  local source_color
  source_color=$(tr -d '[:space:]' <"$STATE_DIR/user/generated/source-color.txt" 2>/dev/null)
  [[ $source_color =~ ^#[A-Fa-f0-9]{6}$ ]] || return
  matugen --config "$apps_config" color hex "$source_color" --mode "$mode_flag" --type "$type_flag" >/dev/null || return
  "$SCRIPT_DIR/apply-app-colors.sh"
}

pre_process() {
  local mode_flag="$1"
  if [[ $mode_flag == "dark" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
  elif [[ $mode_flag == "light" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
  fi

  if [ ! -d "$CACHE_DIR"/user/generated ]; then
    mkdir -p "$CACHE_DIR"/user/generated
  fi
}

post_process() {
  local wallpaper_path="$1"
  local colors_lock_flag="$2"

  if [[ -n $colors_lock_flag ]]; then
    return
  fi

  handle_app_colors &
  "$SCRIPT_DIR/code/material-code-set-color.sh" &
}

THUMBNAIL_DIR="$STATE_DIR/user/generated/wallpaper/video-thumbnails"

is_video() {
  local extension="${1##*.}"
  [[ $extension == "mp4" || $extension == "webm" || $extension == "mkv" || $extension == "avi" || $extension == "mov" ]] && return 0 || return 1
}

kill_existing_mpvpaper() {
  pkill -f -9 mpvpaper || true
}

set_wallpaper_path() {
  local path="$1"
  if [ -f "$SHELL_CONFIG_FILE" ]; then
    jq --arg path "$path" '.background.wallpaperPath = $path' "$SHELL_CONFIG_FILE" >"$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
  fi
}

set_thumbnail_path() {
  local path="$1"
  if [ -f "$SHELL_CONFIG_FILE" ]; then
    jq --arg path "$path" '.background.thumbnailPath = $path' "$SHELL_CONFIG_FILE" >"$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
  fi
}

switch() {
  imgpath="$1"
  mode_flag="$2"
  type_flag="$3"
  color_flag="$4"
  color="$5"
  colors_only_flag="$6"
  colors_lock_flag="$7"

  matugen_args=(--source-color-index 0)

  if [[ $color_flag == "1" ]]; then
    matugen_args+=(color hex "$color")
    generate_colors_material_args=(--color "$color")
  else
    if [[ -z $imgpath ]]; then
      echo 'Aborted'
      exit 0
    fi

    if [[ -z $colors_only_flag ]]; then
      kill_existing_mpvpaper
    fi

    if is_video "$imgpath"; then
      mkdir -p "$THUMBNAIL_DIR"

      missing_deps=()
      if ! command -v mpvpaper &>/dev/null; then
        missing_deps+=("mpvpaper")
      fi
      if ! command -v ffmpeg &>/dev/null; then
        missing_deps+=("ffmpeg")
      fi
      if [ ${#missing_deps[@]} -gt 0 ]; then
        # mpvpaper/ffmpeg are runtime deps of the nixbookShellConfig Nix module; if they
        # are missing the shell was not started through the `nixbook-shell` wrapper.
        echo "Missing deps: ${missing_deps[*]}"
        notify-send \
          -a "Wallpaper switcher" \
          -c "im.error" \
          "Can't switch to video wallpaper" \
          "Missing dependencies: ${missing_deps[*]} (provided by the nixbookShellConfig Nix module; start the shell with nixbook-shell)"
        exit 0
      fi

      if [[ -z $colors_only_flag ]]; then
        set_wallpaper_path "$imgpath"

        local video_path="$imgpath"
        # One mpvpaper per output, paused while hidden, from an optimized
        # copy when there is one (see live-wallpaper.sh).
        "$SCRIPT_DIR/live-wallpaper.sh" play "$video_path"
      fi

      thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
      ffmpeg -y -i "$imgpath" -vframes 1 "$thumbnail" 2>/dev/null

      if [[ -z $colors_only_flag ]]; then
        set_thumbnail_path "$thumbnail"
      fi

      if [ -f "$thumbnail" ]; then
        matugen_args+=(image "$thumbnail")
        generate_colors_material_args=(--path "$thumbnail")
      else
        echo "Cannot create image to colorgen"
        exit 1
      fi
    else
      matugen_args+=(image "$imgpath")
      generate_colors_material_args=(--path "$imgpath")
      if [[ -z $colors_only_flag ]]; then
        set_wallpaper_path "$imgpath"
      fi
    fi
  fi

  if [[ -z $mode_flag ]]; then
    current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    if [[ $current_mode == "prefer-dark" ]]; then
      mode_flag="dark"
    else
      mode_flag="light"
    fi
  fi

  if [[ -n $mode_flag ]]; then
    matugen_args+=(--mode "$mode_flag")
    if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
      generate_colors_material_args+=(--mode "dark")
    else
      generate_colors_material_args+=(--mode "$mode_flag")
    fi
  fi
  [[ -n $type_flag ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
  generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
  generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

  pre_process "$mode_flag"

  if [ -f "$SHELL_CONFIG_FILE" ]; then
    enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
    if [[ $enable_apps_shell == "false" && $color_flag != "1" ]]; then
      # Not following the wallpaper: regenerate from the current source
      # colour, so the colours stay put but the light/dark switch and the
      # scheme still apply (an accent colour picked by hand still does).
      # (source-color.txt: matugen's source; color.txt, the generator's pick,
      # for a state older than source-color.txt.)
      frozen_color=$(cat "$STATE_DIR/user/generated/source-color.txt" 2>/dev/null ||
        cat "$STATE_DIR/user/generated/color.txt" 2>/dev/null)
      frozen_color=$(tr -d '[:space:]' <<<"$frozen_color")
      if [[ ! $frozen_color =~ ^#[A-Fa-f0-9]{6}$ ]]; then
        echo "App and shell theming disabled and no current colour, skipping color generation"
        return
      fi
      matugen_args=(--source-color-index 0 color hex "$frozen_color" --mode "$mode_flag")
      [[ -n $type_flag ]] && matugen_args+=(--type "$type_flag")
      # Drop --path <image> (always first), keep the rest.
      generate_colors_material_args=(--color "$frozen_color" "${generate_colors_material_args[@]:2}")
    fi
  fi

  if [ -f "$SHELL_CONFIG_FILE" ]; then
    harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
    harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
    term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
    [[ $harmony != "null" && -n $harmony ]] && generate_colors_material_args+=(--harmony "$harmony")
    [[ $harmonize_threshold != "null" && -n $harmonize_threshold ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
    [[ $term_fg_boost != "null" && -n $term_fg_boost ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
  fi

  colors_json_path="$STATE_DIR/user/generated/colors.json"
  colors_lock_json_path="$STATE_DIR/user/generated/colors-lock.json"
  colors_lock_watch_paths=(
    "$colors_json_path"
    "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
    "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
  )
  colors_lock_backups=()
  if [[ -n $colors_lock_flag ]]; then
    for i in "${!colors_lock_watch_paths[@]}"; do
      watch_path="${colors_lock_watch_paths[$i]}"
      if [[ -f $watch_path ]]; then
        backup_path="$(mktemp)"
        cp "$watch_path" "$backup_path"
        colors_lock_backups[$i]="$backup_path"
      fi
    done
  fi

  matugen "${matugen_args[@]}"

  if [[ -n $colors_lock_flag ]]; then
    if [[ -f $colors_json_path ]]; then
      cp "$colors_json_path" "$colors_lock_json_path"
    fi
    for i in "${!colors_lock_watch_paths[@]}"; do
      watch_path="${colors_lock_watch_paths[$i]}"
      backup_path="${colors_lock_backups[$i]:-}"
      if [[ -n $backup_path ]]; then
        mv "$backup_path" "$watch_path"
      fi
    done
  fi

  source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"

  if [[ -n $colors_lock_flag ]]; then
    output_scss="$STATE_DIR/user/generated/material_colors_lock.scss"
  else
    output_scss="$STATE_DIR/user/generated/material_colors.scss"
  fi

  python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
    >"$output_scss"
  deactivate

  if [[ -z $colors_lock_flag ]]; then
    "$SCRIPT_DIR"/applycolor.sh
  fi

  post_process "$imgpath" "$colors_lock_flag"
}

main() {
  imgpath=""
  mode_flag=""
  type_flag=""
  color_flag=""
  color=""
  noswitch_flag=""
  colors_only_flag=""
  colors_lock_flag=""
  explicit_image=""
  start_dir_flag=""

  get_type_from_config() {
    jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
  }
  get_accent_color_from_config() {
    jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
  }
  set_accent_color() {
    local color="$1"
    jq --arg color "$color" '.appearance.palette.accentColor = $color' "$SHELL_CONFIG_FILE" >"$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
  }

  detect_scheme_type_from_image() {
    local img="$1"
    source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
    "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'
    deactivate
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --mode)
      mode_flag="$2"
      shift 2
      ;;
    --type)
      type_flag="$2"
      shift 2
      ;;
    --color)
      if [[ $2 =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        set_accent_color "$2"
        shift 2
      elif [[ $2 == "clear" ]]; then
        set_accent_color ""
        shift 2
      else
        set_accent_color "$(niri msg pick-color | awk '/^Hex:/ {print $2}')"
        shift
      fi
      ;;
    --image)
      imgpath="$2"
      explicit_image="1"
      shift 2
      ;;
    --start-dir)
      start_dir_flag="$2"
      shift 2
      ;;
    --noswitch)
      noswitch_flag="1"
      if [[ -z $imgpath ]]; then
        imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
      fi
      shift
      ;;
    --colors_lock)
      colors_lock_flag="1"
      colors_only_flag="1"
      noswitch_flag="1"
      if [[ -z $imgpath ]]; then
        imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
      fi
      shift
      ;;
    *)
      if [[ -z $imgpath ]]; then
        imgpath="$1"
      fi
      shift
      ;;
    esac
  done

  if [[ -n $noswitch_flag && -n $explicit_image ]]; then
    colors_only_flag="1"
  fi

  config_color="$(get_accent_color_from_config)"
  if [[ $config_color =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
    color_flag="1"
    color="$config_color"
  fi

  if [[ -z $type_flag ]]; then
    type_flag="$(get_type_from_config)"
  fi

  allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
  valid_type=0
  for t in "${allowed_types[@]}"; do
    if [[ $type_flag == "$t" ]]; then
      valid_type=1
      break
    fi
  done
  if [[ $valid_type -eq 0 ]]; then
    echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
    type_flag="auto"
  fi

  # Only prompt for wallpaper if not using --color and not using --noswitch and no imgpath set
  if [[ -z $imgpath && -z $color_flag && -z $noswitch_flag ]]; then
    if [[ -n $start_dir_flag && -d $start_dir_flag ]]; then
      cd "$start_dir_flag" || return 1
    else
      cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || return 1
    fi
    imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
  fi

  if [[ -n $imgpath && -z $noswitch_flag ]]; then
    set_accent_color ""
    color_flag=""
    color=""
  fi

  if [[ $type_flag == "auto" ]]; then
    if [[ -n $imgpath && -f $imgpath ]]; then
      detected_type="$(detect_scheme_type_from_image "$imgpath")"
      valid_detected=0
      for t in "${allowed_types[@]}"; do
        if [[ $detected_type == "$t" && $detected_type != "auto" ]]; then
          valid_detected=1
          break
        fi
      done
      if [[ $valid_detected -eq 1 ]]; then
        type_flag="$detected_type"
      else
        echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
        type_flag="scheme-tonal-spot"
      fi
    else
      echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
      type_flag="scheme-tonal-spot"
    fi
  fi

  if [[ $mode_flag == "dark" || $mode_flag == "light" ]]; then
    local imgdir="$(dirname "$imgpath")"
    local imgbase="$(basename "$imgpath")"
    local imgname="${imgbase%.*}"
    local imgext="${imgbase##*.}"

    local stripped_name="${imgname%-dark}"
    stripped_name="${stripped_name%-light}"

    local new_imgpath="${imgdir}/${stripped_name}-${mode_flag}.${imgext}"
    local new_stripped_imgpath="${imgdir}/${stripped_name}.${imgext}"

    if [[ -f $new_imgpath ]]; then
      imgpath="$new_imgpath"
    elif [[ -f $new_stripped_imgpath ]]; then
      imgpath="$new_stripped_imgpath"
    fi
  fi

  switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" "$colors_only_flag" "$colors_lock_flag"
}

main "$@"
