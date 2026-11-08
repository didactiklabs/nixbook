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
#   live-wallpaper.sh pause <output> yes|no
#                                     pause or resume one output's video (the
#                                     shell: its desktop covered or shown)
#   live-wallpaper.sh stop            stop playback
#
# The shell (services/Wallpapers.qml) owns playback: it starts the video once
# the wallpaper transition to its still frame has finished (the first frame,
# so the picture comes alive without a jump), stops it once an image covers
# it, and pauses an output's video while nothing of it can be seen (windows
# over the whole desktop, locked, screens off). switchwall.sh only records the
# wallpaper and its still frame.
#
# Quality, 60 fps and power — measured on a 1080p60 video on a 2880×1800
# output (Radeon 680M):
# - Each output plays its own copy of the video, made once in the background
#   at exactly its size (cropped to cover it, scaled with lanczos) and at 60
#   fps (a video under ~47 fps is motion-interpolated to 60 — anime
#   wallpapers are often 24 or 30 —, one over 60 is brought down to 60),
#   encoded with VA-API (HEVC) when possible, else x264, at idle priority,
#   into $XDG_CACHE_HOME/nixbook-shell/live-wallpapers. It replaces the
#   original as soon as it is there, at the same position, in the running
#   player (mpv's IPC socket: no restart, no flash).
# - With nothing left to scale, mpv draws it the simplest way
#   (gpu-dumb-mode): mpvpaper's GPU time 55% → 13% at 60 fps, no dropped
#   frame. Scaling the 1080p video sharply at play time instead (spline36)
#   doubled it and dropped ~7 frames a second; bilinear looked soft.
# - Paused while the desktop can't be seen: mpvpaper ~0, niri's GPU time
#   33% → 11%. `-p` still pauses it while its surface isn't drawn (screen
#   locked, outputs off).
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
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/nixbook-shell"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nixbook-shell/live-wallpapers"
FPS=60

# The output's player: mpv's IPC socket (one per output).
sock() { echo "$RUNDIR/live-wallpaper-$1.sock"; }
# Sends one mpv IPC command (JSON) to an output's player; prints its reply.
mpv_cmd() {
  local s
  s=$(sock "$1")
  [ -S "$s" ] || return 1
  printf '%s\n' "$2" | socat -t 2 - "UNIX-CONNECT:$s" 2>/dev/null | jq -c 'select(has("error"))' | head -n 1
}

COPIES_PID="$RUNDIR/live-wallpaper-copies.pid"
# Stops the copies being made (every ffmpeg of them: they run in their own
# process group), unless they are this video's (key $1).
cancel_copies() {
  local pid k
  [ -f "$COPIES_PID" ] && read -r pid k <"$COPIES_PID" || return 0
  [ -n "${1:-}" ] && [ "$1" = "$k" ] && return 0
  # Killed outright: ffmpeg finishes up gracefully on SIGTERM (seconds);
  # what it leaves is pruned.
  kill -KILL -- "-$pid" 2>/dev/null
  rm -f "$COPIES_PID"
}
mpv_layers() { niri msg --json layers 2>/dev/null | jq '[.[] | select(.namespace == "mpvpaper")] | length'; }
# Stops the players and waits until they and their surfaces are gone (the
# shell lifts its desktop widgets over the new ones once they are up: an old
# surface still listed made it do that too early).
stop_players() {
  local i
  pkill -f "/bin/[m]pvpaper " || return 0
  for i in $(seq 40); do
    pgrep -f "/bin/[m]pvpaper " >/dev/null || break
    [ "$i" != 20 ] || pkill -9 -f "/bin/[m]pvpaper "
    sleep 0.05
  done
  for _ in $(seq 40); do
    [ "$(mpv_layers)" = 0 ] && break
    sleep 0.05
  done
}

case "$cmd" in
stop)
  cancel_copies
  stop_players
  rm -f "$RUNDIR"/live-wallpaper-*.sock
  exit 0
  ;;
pause)
  case "${3:-}" in yes | no) ;; *)
    echo "usage: $0 pause <output> yes|no" >&2
    exit 1
    ;;
  esac
  mpv_cmd "$2" "{\"command\":[\"set_property\",\"pause\",$([ "$3" = yes ] && echo true || echo false)]}" >/dev/null
  exit 0
  ;;
esac
[ -n "$cmd" ] && [ -f "$video" ] || {
  echo "usage: $0 play|ensure|poster|copies <video> | pause <output> yes|no | stop" >&2
  exit 1
}

OPTS="no-audio loop hwdec=auto-safe gpu-dumb-mode=yes video-sync=display-resample interpolation=no panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

# "name width height" per enabled output: the pixels it draws (logical size
# × scale, so a rotated output counts as it is shown).
outputs() {
  niri msg --json outputs | jq -r 'to_entries[] | .value | select(.current_mode != null and .logical != null)
    | "\(.name) \(.logical.width * .logical.scale | round) \(.logical.height * .logical.scale | round)"'
}

# The video's "width height fps".
probe() {
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate \
    -of csv=s=,:p=0 "$video" | awk -F, '{ split($3, r, "/"); f = (r[2] > 0) ? r[1] / r[2] : r[1]; print $1, $2, f }'
}

# Copies of this video start with this (its path, size and time).
key() { stat -c '%n %s %Y' "$(realpath "$video")" | sha1sum | cut -c1-16; }

# Its copies for an output W×H (see the top), "" when not needed:
#   fast: at exactly W×H, at the video's own frame rate (60 at most); made in
#         seconds. Not needed when the video already is W×H and ≤ 61 fps.
#   smooth: at W×H and 60 fps, motion-interpolated; only for a video under
#         47 fps. Slow (~20-30 s of CPU per second of 1080p), so made in
#         parallel slices, on AC power only.
# Printed as "fast smooth" ("-" for none).
copy_paths() {
  local w=$1 h=$2 srcw srch srcf k fps fast=- smooth=-
  read -r srcw srch srcf < <(probe)
  [ "${srcw:-0}" -gt 0 ] && [ "$w" -gt 0 ] || {
    echo "- -"
    return 0
  }
  k=$(key)
  fps=$(awk -v f="$srcf" -v t="$FPS" 'BEGIN { f = (f > t) ? t : f; printf "%d", f + 0.5 }')
  if [ "$srcw" != "$w" ] || [ "$srch" != "$h" ] || awk -v f="$srcf" 'BEGIN { exit !(f > 61) }'; then
    fast="$CACHE/$k-${w}x${h}-${fps}.mp4"
  fi
  if awk -v f="$srcf" 'BEGIN { exit !(f > 0 && f < 47) }'; then
    smooth="$CACHE/$k-${w}x${h}-${FPS}i.mp4"
  fi
  echo "$fast $smooth"
}

# The best of this output's files that exists: smooth, fast, the video.
best_file() {
  local fast smooth
  read -r fast smooth < <(copy_paths "$1" "$2")
  if [ "$smooth" != - ] && [ -f "$smooth" ]; then
    echo "$smooth"
  elif [ "$fast" != - ] && [ -f "$fast" ]; then
    echo "$fast"
  else
    echo "$video"
  fi
}

encode() { # <filters> <out> [ffmpeg input options...]
  # VA-API decoding and HEVC encoding (the CPU only scales: about 40% less
  # of it for a 4K video), else CPU decoding, else x264.
  local vf="$1" out="$2"
  shift 2
  local -a va=(-init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va)
  nice -n 19 ionice -c 3 ffmpeg -v error -y "${va[@]}" -hwaccel vaapi -hwaccel_device va "$@" -an \
    -vf "$vf,format=nv12,hwupload" -c:v hevc_vaapi -qp 18 -f mp4 "$out" </dev/null ||
    nice -n 19 ionice -c 3 ffmpeg -v error -y "${va[@]}" "$@" -an \
      -vf "$vf,format=nv12,hwupload" -c:v hevc_vaapi -qp 18 -f mp4 "$out" </dev/null ||
    nice -n 19 ionice -c 3 ffmpeg -v error -y "$@" -an -vf "$vf" \
      -c:v libx264 -preset veryfast -crf 16 -threads 2 -pix_fmt yuv420p -f mp4 "$out" </dev/null
}

scale_crop() { echo "scale=$1:$2:force_original_aspect_ratio=increase:flags=lanczos+accurate_rnd+full_chroma_int,crop=$1:$2"; }

make_fast() { # <out> <w> <h>
  local srcf rate=""
  read -r _ _ srcf < <(probe)
  awk -v f="${srcf:-0}" -v t="$FPS" 'BEGIN { exit !(f > t + 1) }' && rate="fps=$FPS,"
  encode "$rate$(scale_crop "$2" "$3")" "$1.part" -i "$video" && mv "$1.part" "$1"
}

# Interpolated in slices (two at most, see below): each slice gets one input frame
# past its end (so the frames between it and the next slice are made too)
# and is cut to its exact number of output frames, so the joins don't skip.
# The interpolation runs at the smaller of the video's and the output's size.
make_smooth() { # <out> <w> <h>
  local out="$1" w=$2 h=$3 srcw srch srcf dur n frames per i start tmp vf
  read -r srcw srch srcf < <(probe)
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video")
  frames=$(awk -v d="$dur" -v t="$FPS" 'BEGIN { printf "%d", d * t }')
  [ "${frames:-0}" -gt 0 ] || return 1
  # Two at most: one takes ~0.9 GB at 1080p (eight at 2880×1800, ~1.9 GB
  # each, made the laptop swap until the kernel killed the shell).
  n=$(($(nproc) / 4))
  [ "$n" -ge 1 ] || n=1
  [ "$n" -le 2 ] || n=2
  # Whole seconds: every slice starts on a frame of the video, whatever its
  # frame rate.
  per=$((((frames + n - 1) / n + FPS - 1) / FPS * FPS))
  local mi="minterpolate=fps=$FPS:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
  # At 1080p at most, then scaled to the output with lanczos: its cost grows
  # with the pixels (on a 2880×1800 output, 2 s of a 4K video took 9 minutes
  # per process with eight at once). A smaller video is interpolated as it is.
  local ww wh
  read -r ww wh < <(awk -v w="$w" -v h="$h" 'BEGIN { f = (h > 1080) ? 1080 / h : 1
    printf "%d %d", int(w * f / 2 + 0.5) * 2, int(h * f / 2 + 0.5) * 2 }')
  if [ $((srcw * srch)) -le $((ww * wh)) ]; then
    vf="$mi,$(scale_crop "$w" "$h")"
  elif [ "$ww" = "$w" ]; then
    vf="$(scale_crop "$w" "$h"),$mi"
  else
    vf="$(scale_crop "$ww" "$wh"),$mi,scale=$w:$h:flags=lanczos+accurate_rnd+full_chroma_int"
  fi
  tmp=$(mktemp -d "$CACHE/.smooth.XXXXXX")
  local -a pids=()
  for ((i = 0; i < n; i++)); do
    start=$(awk -v i="$i" -v p="$per" -v t="$FPS" 'BEGIN { printf "%.6f", i * p / t }')
    awk -v s="$start" -v d="$dur" 'BEGIN { exit !(s < d) }' || break
    encode "$vf" "$tmp/$i.mp4" -ss "$start" -t "$(awk -v p="$per" -v t="$FPS" -v f="$srcf" 'BEGIN { printf "%.6f", p / t + 1.5 / f }')" \
      -i "$video" -frames:v "$per" &
    pids+=($!)
  done
  local ok=1 p
  for p in "${pids[@]}"; do wait "$p" || ok=0; done
  if [ "$ok" = 1 ]; then
    for ((i = 0; i < ${#pids[@]}; i++)); do echo "file '$i.mp4'"; done >"$tmp/list"
    ffmpeg -v error -y -f concat -safe 0 -i "$tmp/list" -c copy -f mp4 "$out.part" </dev/null &&
      mv "$out.part" "$out" || ok=0
  fi
  rm -rf "$tmp" "$out.part"
  [ "$ok" = 1 ]
}

on_ac() { # no battery (a desktop) counts as AC
  local d
  for d in /sys/class/power_supply/*; do
    [ "$(cat "$d/type" 2>/dev/null)" = Mains ] && [ "$(cat "$d/online" 2>/dev/null)" = 1 ] && return 0
  done
  ! grep -qx Battery /sys/class/power_supply/*/type 2>/dev/null
}

# Copies not played for a month, and those of older versions (named
# KEY-WxH.mp4: one size for every output, not at 60 fps), go.
prune() {
  [ -d "$CACHE" ] || return 0
  find "$CACHE" -maxdepth 1 -name '*.mp4' -atime +30 -delete
  find "$CACHE" -maxdepth 1 -regextype posix-extended -regex '.*/[0-9a-f]{16}-[0-9]+x[0-9]+\.mp4' -delete
  # Left by a run that was stopped (the shell restarted mid-way).
  find "$CACHE" -maxdepth 1 \( -name '.smooth.*' -o -name '*.part' \) -mmin +5 -exec rm -rf {} +
}

# A copy, once made, into an output's running player — still this video, at
# the same position (paused or not as it was).
swap_in() {
  local name="$1" copy="$2" playing pos
  playing=$(mpv_cmd "$name" '{"command":["get_property","path"]}' | jq -r '.data // empty')
  [ "$playing" = "$video" ] || [[ $playing == "$CACHE/$(key)-"* ]] || return 0
  [ "$playing" != "$copy" ] || return 0
  pos=$(mpv_cmd "$name" '{"command":["get_property","time-pos"]}' | jq -r '.data // 0')
  mpv_cmd "$name" "$(jq -nc --arg f "$copy" --arg p "start=$pos" '{command: ["loadfile", $f, "replace", -1, $p]}')" >/dev/null
}

# Makes the missing copies, the fast ones first, each swapped in when made
# (two outputs of one size share them). One run at a time.
copies() {
  mkdir -p "$CACHE" "$RUNDIR"
  local k pid pk
  k=$(key)
  # This video's copies already under way.
  if [ -f "$COPIES_PID" ] && read -r pid pk <"$COPIES_PID" && [ "$pk" = "$k" ] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  cancel_copies
  # (The cancelled run's ffmpegs take a moment to let go of the lock.)
  exec 9>"$CACHE/.copies.lock"
  flock -w 10 9 || return 0
  echo "$$ $k" >"$COPIES_PID"
  local -a outs=()
  local name w h fast smooth stage
  while read -r name w h; do outs+=("$name $w $h"); done < <(outputs)
  for stage in fast smooth; do
    # Not for a wallpaper only passed through (browsing them): the smooth
    # copies, heavy, wait a minute (a new wallpaper cancels this run).
    if [ "$stage" = smooth ]; then
      local need=0
      for o in "${outs[@]}"; do
        read -r name w h <<<"$o"
        read -r fast smooth < <(copy_paths "$w" "$h")
        [ "$smooth" = - ] || [ -f "$smooth" ] || need=1
      done
      [ "$need" = 0 ] || sleep "${LIVE_WALLPAPER_SMOOTH_DELAY:-60}"
    fi
    for o in "${outs[@]}"; do
      read -r name w h <<<"$o"
      read -r fast smooth < <(copy_paths "$w" "$h")
      if [ "$stage" = fast ] && [ "$fast" != - ]; then
        [ -f "$fast" ] || make_fast "$fast" "$w" "$h" || continue
        [ "$smooth" != - ] && [ -f "$smooth" ] || swap_in "$name" "$fast"
      elif [ "$stage" = smooth ] && [ "$smooth" != - ]; then
        if [ ! -f "$smooth" ]; then
          on_ac || continue
          make_smooth "$smooth" "$w" "$h" || continue
        fi
        swap_in "$name" "$smooth"
      fi
    done
  done
  prune
}

# This video (or one of its copies) playing on every output, on the Bottom
# layer (one left on the Background layer by an older version would sit under
# the still frame and look frozen). `[m]` keeps the pattern from matching
# this script's own command line (the process itself is named
# `.mpvpaper-wrapp`, Nix wrapper).
running() {
  local procs want have
  procs=$(pgrep -af "/bin/[m]pvpaper ") || return 1
  grep -qF -- " $video" <<<"$procs" || grep -qF -- "$CACHE/$(key)-" <<<"$procs" || return 1
  # Each output's player answers on its socket (one started by an older
  # version has none: no pausing, no copy swapped in).
  local name
  while read -r name _; do
    [ -S "$(sock "$name")" ] || return 1
  done < <(outputs)
  want=$(outputs | wc -l)
  have=$(niri msg --json layers | jq '[.[] | select(.namespace == "mpvpaper" and .layer == "Bottom") | .output] | unique | length')
  [ "$have" -ge "$want" ]
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
  cancel_copies "$(key)"
  stop_players
  mkdir -p "$RUNDIR"
  local name w h n=0
  local -a socks=()
  while read -r name w h; do
    socks+=("$(sock "$name")")
    rm -f "$(sock "$name")"
    mpvpaper -p -l bottom -o "$OPTS input-ipc-server=$(sock "$name")" "$name" "$(best_file "$w" "$h")" >/dev/null 2>&1 </dev/null &
    n=$((n + 1))
  done < <(outputs)
  # Returns once every output shows its player and answers on its socket
  # (what the shell waits for: then it lifts the widgets and pauses it).
  local s ready
  for _ in $(seq 150); do
    ready=1
    for s in "${socks[@]}"; do [ -S "$s" ] || ready=0; done
    [ "$ready" = 1 ] && [ "$(mpv_layers)" -ge "$n" ] && return 0
    sleep 0.1
  done
  return 1
}

# The missing copies, in the background, in a systemd unit of their own (the
# shell's PATH — ffmpeg, socat, jq — and niri's socket passed along):
# out of the shell's service (heavy enough there to get the shell killed by
# the OOM killer), capped in memory, idle CPU and IO; its process group is
# cancelled as a whole by the next wallpaper. Without a user manager (or
# for tests, LIVE_WALLPAPER_NO_UNIT), a process group of their own.
start_copies() {
  if [ -z "${LIVE_WALLPAPER_NO_UNIT:-}" ] && systemd-run --user --quiet --collect \
    --unit="nixbook-live-wallpaper-copies-$(key)" --description="Live wallpaper copies" \
    -p MemoryHigh=2G -p MemoryMax=3G -p CPUWeight=idle -p IOWeight=10 -p Nice=19 \
    -E PATH -E NIRI_SOCKET -E WAYLAND_DISPLAY -E XDG_RUNTIME_DIR -E XDG_CACHE_HOME -E XDG_STATE_HOME \
    bash "$0" copies "$video" >/dev/null 2>&1 </dev/null; then
    return 0
  fi
  setsid bash "$0" copies "$video" >/dev/null 2>&1 </dev/null &
}

# Exit status, for the shell: 0 players started and shown, 1 they didn't
# show up, 10 (ensure) this video already playing.
case "$cmd" in
play)
  play || exit 1
  start_copies
  ;;
ensure)
  # Also on AC power coming back (the shell): the smooth copies waiting for it.
  if running; then
    start_copies
    exit 10
  fi
  play || exit 1
  start_copies
  ;;
copies) copies ;;
poster) poster ;;
*)
  echo "unknown command: $cmd" >&2
  exit 1
  ;;
esac
