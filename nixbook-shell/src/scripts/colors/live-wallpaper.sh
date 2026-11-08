#!/usr/bin/env bash
# Video ("live") wallpapers: one mpvpaper per output.
#
#   live-wallpaper.sh play <video>    (re)start playback
#   live-wallpaper.sh ensure <video>  start it unless that video is already
#                                     playing (shell start: mpvpaper dies
#                                     with the shell's service on every
#                                     restart)
#   live-wallpaper.sh poster <video>  print the video's still frame (its
#                                     first frame at full size, made once,
#                                     again when the video changes): what the
#                                     shell shows for it like an image — in
#                                     transitions, previews, the blur
#   live-wallpaper.sh stop            stop playback
#
# The shell (services/Wallpapers.qml) owns playback: it starts the video once
# the wallpaper transition to its still frame has finished (the first frame,
# so the picture comes alive without a jump) and stops it once an image
# covers it. switchwall.sh only records the wallpaper and its still frame.
#
# Power, without visible change:
# - `-p`: mpvpaper pauses while its surface isn't drawn (screen locked,
#   outputs off).
# - A video larger than the biggest output is decoded, uploaded and sampled
#   at full size three times over (a 4K video on 1080p/1440p/1800p outputs).
#   An optimized copy at the biggest output's size (same frame rate, encoded
#   on the GPU with VA-API when possible, else x264 at idle priority) is made
#   once in the background into $XDG_CACHE_HOME/nixbook-shell/live-wallpapers
#   and used from the next start on (never swapped mid-playback: that would
#   restart the video). Measured on a 4K60 video over three outputs: ~60
#   points less GPU time (mpvpaper + niri), same CPU.
# - The video goes on the *Bottom* layer. niri's xray blur (tiled
#   windows) only samples Background-layer surfaces, where the shell keeps a
#   still frame (NiriBackdrop, the video's thumbnail): windows blur that still
#   frame once instead of re-blurring every output on every video frame, while
#   gaps and the uncovered desktop show the live video. Measured: niri GPU
#   123% → 67%, CPU 88% → 68%. The shell re-maps its own Bottom-layer surface
#   (desktop widgets) once the video is up, so the widgets stay above it
#   (Wallpapers.restackOverVideo).

set -u
cmd="${1:-}"
video="${2:-}"
video="${video#file://}"
if [ "$cmd" = stop ]; then
  pkill -f "/bin/[m]pvpaper " || true
  exit 0
fi
[ -n "$cmd" ] && [ -f "$video" ] || {
  echo "usage: $0 play|ensure|poster <video> | stop" >&2
  exit 1
}

OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nixbook-shell/live-wallpapers"

# "name width height" per enabled output (physical pixels).
outputs() {
  niri msg --json outputs | jq -r 'to_entries[] | .value | select(.current_mode != null)
    | "\(.name) \(.modes[.current_mode].width) \(.modes[.current_mode].height)"'
}

# Playing as `play` would start it: an mpvpaper surface on the Bottom layer
# for every output (one left on the Background layer by an older version
# would sit under the still frame and look frozen). `[m]` keeps the pattern
# from matching this script's own command line (the process itself is named
# `.mpvpaper-wrapp`, Nix wrapper).
running() {
  # This video (or its optimized copy), not whatever played before.
  local procs opt
  procs=$(pgrep -af "/bin/[m]pvpaper ") || return 1
  opt=$(optimized_path)
  grep -qF -- " $video" <<<"$procs" || { [ -n "$opt" ] && grep -qF -- " $opt" <<<"$procs"; } || return 1
  local want have
  want=$(outputs | wc -l)
  have=$(niri msg --json layers | jq '[.[] | select(.namespace == "mpvpaper" and .layer == "Bottom") | .output] | unique | length')
  [ "$have" -ge "$want" ]
}

# The optimized copy's path for this video at the biggest output's size, or
# "" when the video isn't bigger than that.
optimized_path() {
  local maxw maxh srcw srch
  read -r maxw maxh < <(outputs | awk '$2 > w { w = $2 } $3 > h { h = $3 } END { print w + 0, h + 0 }')
  IFS=x read -r srcw srch < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video")
  [ "${maxw:-0}" -gt 0 ] && [ "${srcw:-0}" -gt 0 ] || return 0
  # Cover every output: scale by the larger of the two ratios.
  local size
  size=$(awk -v mw="$maxw" -v mh="$maxh" -v sw="$srcw" -v sh="$srch" 'BEGIN {
    f = mw / sw; if (mh / sh > f) f = mh / sh
    if (f > 0.9) exit
    printf "%dx%d", int(sw * f / 2 + 0.5) * 2, int(sh * f / 2 + 0.5) * 2 }')
  [ -n "$size" ] || return 0
  local key
  key=$(stat -c '%n %s %Y' "$(realpath "$video")" | sha1sum | cut -c1-16)
  echo "$CACHE/$key-$size.mp4"
}

optimize() {
  local out="$1" size w h
  size="${out##*-}"
  size="${size%.mp4}"
  w="${size%x*}"
  h="${size#*x}"
  mkdir -p "$CACHE"
  exec 9>"$out.lock"
  flock -n 9 || return 0 # already being made
  [ -f "$out" ] && return 0
  if ffmpeg -v error -y -vaapi_device /dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi \
    -i "$video" -an -vf "scale_vaapi=w=$w:h=$h" -c:v hevc_vaapi -qp 20 -f mp4 "$out.part" ||
    nice -n 19 ionice -c 3 ffmpeg -v error -y -i "$video" -an -vf "scale=$w:$h:flags=lanczos" \
      -c:v libx264 -preset veryfast -crf 16 -threads 2 -pix_fmt yuv420p -f mp4 "$out.part"; then
    mv "$out.part" "$out"
  else
    rm -f "$out.part"
  fi
  rm -f "$out.lock"
}

# One file per video (a hash of its path), remade when the video is newer.
poster() {
  local dir out
  dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/wallpaper/video-thumbnails"
  out="$dir/$(printf '%s' "$video" | md5sum | cut -c1-32).jpg"
  if [ ! -s "$out" ] || [ "$video" -nt "$out" ]; then
    mkdir -p "$dir"
    if ! ffmpeg -v error -y -i "$video" -frames:v 1 -q:v 2 -f image2 "$out.$$.jpg" </dev/null; then
      rm -f "$out.$$.jpg"
      exit 1
    fi
    mv -f "$out.$$.jpg" "$out"
  fi
  echo "$out"
}

play() {
  pkill -f "/bin/[m]pvpaper " || true
  local file="$video" opt
  opt=$(optimized_path)
  [ -n "$opt" ] && [ -f "$opt" ] && file="$opt"
  while read -r name _; do
    mpvpaper -p -l bottom -o "$OPTS" "$name" "$file" >/dev/null 2>&1 </dev/null &
    sleep 0.1
  done < <(outputs)
  if [ -n "$opt" ] && [ ! -f "$opt" ]; then
    optimize "$opt" >/dev/null 2>&1 </dev/null &
  fi
}

case "$cmd" in
play) play ;;
ensure) running || play ;;
poster) poster ;;
*)
  echo "unknown command: $cmd" >&2
  exit 1
  ;;
esac
