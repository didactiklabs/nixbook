#!/usr/bin/env bash
# Video ("live") wallpapers: one mpvpaper per output.
#
#   live-wallpaper.sh play <video>    show this video: switched inside the
#                                     running players (no new surface: instant),
#                                     else new players. Paused on its first
#                                     frame: the shell resumes it once the
#                                     transition to that frame is over.
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
#   live-wallpaper.sh prepare-start <current video|-> <folder>...
#                                     prepare the library in the background
#                                     (`prepare`, in a systemd unit)
#   live-wallpaper.sh stop            stop playback
#
# The shell (services/Wallpapers.qml) owns playback: it starts the video as
# soon as it is chosen (paused on its first frame, under the transition to
# that frame), resumes it once the transition is over, stops it once an image
# covers it, and pauses an output's video while nothing of it can be seen
# (windows over the whole desktop, locked, screens off). switchwall.sh only
# records the wallpaper and its still frame.
#
# Quality, 60 fps and power — measured on a 1080p60 video on a 2880×1800
# output (Radeon 680M):
# - The library is prepared ahead of time (`prepare`, never while switching):
#   every video of the wallpaper folders gets its still frame and, on AC
#   power, one copy per output size at exactly that size (cropped to cover
#   it, scaled with lanczos) and at 60 fps (a video under ~47 fps is
#   motion-interpolated to 60 — anime wallpapers are often 24 or 30 —, one
#   over 60 brought down to 60), encoded with VA-API (HEVC), into
#   $XDG_CACHE_HOME/nixbook-shell/live-wallpapers. A video not prepared yet
#   plays as it is.
# - With nothing left to scale, mpv draws it the simplest way
#   (gpu-dumb-mode): mpvpaper's GPU time 55% → 13% at 60 fps, no dropped
#   frame. Scaling the 1080p video sharply at play time instead (spline36)
#   doubled it and dropped ~7 frames a second; bilinear looked soft.
# - Paused while the desktop can't be seen: mpvpaper ~0, niri's GPU time
#   33% → 11%. `-p` still pauses it while its surface isn't drawn (screen
#   locked, outputs off).
# - Preparing runs one video at a time in a systemd unit of its own (idle
#   CPU and IO, 4 GB of memory at most), out of the shell's service: an
#   earlier version interpolated eight full-size slices inside it, at play
#   time, and the OOM killer took the shell.
# - The video goes on the *Bottom* layer. niri's xray blur (tiled
#   windows) only samples Background-layer surfaces, where the shell keeps a
#   still frame (NiriBackdrop, the video's thumbnail): windows blur that still
#   frame once instead of re-blurring every output on every video frame, while
#   gaps and the uncovered desktop show the live video. Measured: niri GPU
#   123% → 67%, CPU 88% → 68%. The shell re-maps its own Bottom-layer surface
#   (desktop widgets) once new players are up, so the widgets stay above them.

set -u
cmd="${1:-}"
video="${2:-}"
video="${video#file://}"
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/nixbook-shell"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nixbook-shell/live-wallpapers"
FPS=60
VIDEO_RE='.*\.(mp4|webm|mkv|avi|mov|MP4|WEBM|MKV|AVI|MOV)'

# The output's player: mpv's IPC socket (one per output).
sock() { echo "$RUNDIR/live-wallpaper-$1.sock"; }
# Sends one mpv IPC command (JSON) to an output's player; prints its reply.
mpv_cmd() {
  local s
  s=$(sock "$1")
  [ -S "$s" ] || return 1
  printf '%s\n' "$2" | socat -t 2 - "UNIX-CONNECT:$s" 2>/dev/null | jq -c 'select(has("error"))' | head -n 1
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

# "name width height" per enabled output: the pixels it draws (logical size
# × scale, so a rotated output counts as it is shown).
outputs() {
  niri msg --json outputs | jq -r 'to_entries[] | .value | select(.current_mode != null and .logical != null)
    | "\(.name) \(.logical.width * .logical.scale | round) \(.logical.height * .logical.scale | round)"'
}

# A video's copies start with this (its path, size and time).
key() { stat -c '%n %s %Y' "$(realpath "$1")" | sha1sum | cut -c1-16; }
copy_path() { echo "$CACHE/$(key "$1")-$2x$3.live.mp4"; } # <video> <w> <h>
# What an output plays: the video's prepared copy for its size, else the video.
best_file() { # <video> <w> <h>
  local c
  c=$(copy_path "$@")
  if [ -f "$c" ]; then echo "$c"; else echo "$1"; fi
}

case "$cmd" in
stop)
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
prepare-start)
  # In a systemd unit of its own (the shell's PATH — ffmpeg, socat, jq — and
  # niri's socket passed along): out of the shell's service, capped in
  # memory, idle CPU and IO. One at a time: systemd refuses a second unit of
  # that name while it runs. Without a user manager (or
  # LIVE_WALLPAPER_NO_UNIT), in the background as it is.
  shift
  # The previous version's play-time copy jobs, if one still runs.
  [ -n "${LIVE_WALLPAPER_NO_UNIT:-}" ] || systemctl --user stop 'nixbook-live-wallpaper-copies-*' 2>/dev/null
  # One started by another version of this script (a deploy doesn't stop it:
  # it isn't in the shell's service) gives way, or it would go on for hours
  # making copies the old way while refusing this one.
  self=$(realpath "$0")
  if [ -z "${LIVE_WALLPAPER_NO_UNIT:-}" ] && systemctl --user is-active --quiet nixbook-live-wallpapers-prepare &&
    ! systemctl --user show -p Environment --value nixbook-live-wallpapers-prepare |
    tr ' ' '\n' | grep -qxF "LIVE_WALLPAPER_SCRIPT=$self"; then
    # Killed: ffmpeg finishes the frame it is on first (seconds at full size,
    # systemd waited 90 s), and what it was making is thrown away anyway.
    systemctl --user kill -s KILL nixbook-live-wallpapers-prepare 2>/dev/null
    systemctl --user stop nixbook-live-wallpapers-prepare 2>/dev/null
    # Its name is free once systemd has let go of the stopped unit.
    for _ in $(seq 50); do
      [ "$(systemctl --user show -p LoadState --value nixbook-live-wallpapers-prepare)" = not-found ] && break
      sleep 0.1
    done
  fi
  if [ -z "${LIVE_WALLPAPER_NO_UNIT:-}" ] && systemd-run --user --quiet --collect \
    --unit=nixbook-live-wallpapers-prepare --description="Prepare the live wallpapers" \
    -p MemoryHigh=3G -p MemoryMax=4G -p CPUWeight=idle -p IOWeight=10 -p Nice=19 \
    -E PATH -E NIRI_SOCKET -E WAYLAND_DISPLAY -E XDG_RUNTIME_DIR -E XDG_CACHE_HOME -E XDG_STATE_HOME \
    -E "LIVE_WALLPAPER_SCRIPT=$self" bash "$self" prepare "$@" >/dev/null 2>&1 </dev/null; then
    exit 0
  fi
  [ -n "${LIVE_WALLPAPER_NO_UNIT:-}" ] || ! systemctl --user is-active --quiet nixbook-live-wallpapers-prepare || exit 0
  setsid bash "$0" prepare "$@" >/dev/null 2>&1 </dev/null &
  exit 0
  ;;
esac

OPTS="no-audio loop pause=yes quiet=yes hwdec=auto-safe gpu-dumb-mode=yes video-sync=display-resample interpolation=no panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

# A video's "width height fps".
probe() {
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate \
    -of csv=s=,:p=0 "$1" | awk -F, '{ split($3, r, "/"); f = (r[2] > 0) ? r[1] / r[2] : r[1]; print $1, $2, f }'
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

# The copy of <video> for an output <w>×<h>: scaled (and brought down to 60
# fps) for a video of 47 fps or more, motion-interpolated to 60 for a slower
# one. Nothing to do for a video already that size at 47-61 fps.
make_copy() { # <video> <out> <w> <h>
  local src="$1" out="$2" w=$3 h=$4 srcw srch srcf rate=""
  read -r srcw srch srcf < <(probe "$src")
  [ "${srcw:-0}" -gt 0 ] || return 1
  if awk -v f="$srcf" 'BEGIN { exit !(f < 47) }'; then
    make_smooth "$@"
    return
  fi
  if [ "$srcw" = "$w" ] && [ "$srch" = "$h" ] && awk -v f="$srcf" 'BEGIN { exit !(f <= 61) }'; then
    return 0
  fi
  awk -v f="$srcf" -v t="$FPS" 'BEGIN { exit !(f > t + 1) }' && rate="fps=$FPS,"
  encode "$rate$(scale_crop "$w" "$h")" "$out.part" -i "$src" && mv "$out.part" "$out"
}

# Interpolated at the output's size (a 4K video is scaled down first, so its
# detail is kept), or at the video's own when it is smaller (then scaled up:
# the same picture for less work). In slices (one takes ~0.9 GB at 1080p,
# ~1.9 GB at 2880×1800, and eight full-size ones made the laptop swap until
# the kernel killed the shell: two at most up to 1080p, else one): each slice
# gets one input frame past its end (so the frames between it and the next
# slice are made too) and is cut to its exact number of output frames, so the
# joins don't skip. The cost grows with the pixels (~18 s of CPU per second
# of video at 1080p, ~50 at 2880×1800). Copies carry SMOOTH_TAG: one without
# it was interpolated at 1080p at most by an earlier version (`stale`).
SMOOTH_TAG=nixbook-live-wallpaper:full-size
make_smooth() { # <video> <out> <w> <h>
  local src="$1" out="$2" w=$3 h=$4 srcw srch srcf dur n frames per i start tmp vf
  read -r srcw srch srcf < <(probe "$src")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")
  frames=$(awk -v d="$dur" -v t="$FPS" 'BEGIN { printf "%d", d * t }')
  [ "${frames:-0}" -gt 0 ] || return 1
  n=$(($(nproc) / 4))
  [ "$n" -ge 1 ] || n=1
  [ "$n" -le 2 ] || n=2
  # One above 1080p, or when memory is short (under 6 GB available): same
  # result, half the memory, twice the time.
  [ $((w * h)) -le $((1920 * 1080)) ] || [ $((srcw * srch)) -le $((1920 * 1080)) ] || n=1
  [ "$(awk '/^MemAvailable:/ { print int($2 / 1048576) }' /proc/meminfo)" -ge 6 ] || n=1
  # Whole seconds: every slice starts on a frame of the video, whatever its
  # frame rate.
  per=$((((frames + n - 1) / n + FPS - 1) / FPS * FPS))
  local mi="minterpolate=fps=$FPS:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
  if [ $((srcw * srch)) -le $((w * h)) ]; then
    vf="$mi,$(scale_crop "$w" "$h")"
  else
    vf="$(scale_crop "$w" "$h"),$mi"
  fi
  tmp=$(mktemp -d "$CACHE/.smooth.XXXXXX")
  local -a pids=()
  for ((i = 0; i < n; i++)); do
    start=$(awk -v i="$i" -v p="$per" -v t="$FPS" 'BEGIN { printf "%.6f", i * p / t }')
    awk -v s="$start" -v d="$dur" 'BEGIN { exit !(s < d) }' || break
    encode "$vf" "$tmp/$i.mp4" -ss "$start" -t "$(awk -v p="$per" -v t="$FPS" -v f="$srcf" 'BEGIN { printf "%.6f", p / t + 1.5 / f }')" \
      -i "$src" -frames:v "$per" &
    pids+=($!)
  done
  local ok=1 p
  for p in "${pids[@]}"; do wait "$p" || ok=0; done
  if [ "$ok" = 1 ]; then
    for ((i = 0; i < ${#pids[@]}; i++)); do echo "file '$i.mp4'"; done >"$tmp/list"
    ffmpeg -v error -y -f concat -safe 0 -i "$tmp/list" -c copy -metadata comment="$SMOOTH_TAG" -f mp4 "$out.part" </dev/null &&
      mv "$out.part" "$out" || ok=0
  fi
  rm -rf "$tmp" "$out.part"
  [ "$ok" = 1 ]
}

# A copy made by an earlier version that interpolated at 1080p at most: a
# video under 47 fps it scaled down for that (taller than 1080 and wider than
# the output's 1080-high size), its copy without SMOOTH_TAG. Remade (it plays
# meanwhile).
stale() { # <video> <copy> <w> <h>
  local srcw srch srcf
  read -r srcw srch srcf < <(probe "$1")
  awk -v f="$srcf" 'BEGIN { exit !(f < 47) }' || return 1
  [ "$4" -gt 1080 ] && [ "$srch" -gt 1080 ] && [ $((srcw * $4)) -gt $(($3 * 1080)) ] || return 1
  [ "$(ffprobe -v error -show_entries format_tags=comment -of csv=p=0 "$2")" != "$SMOOTH_TAG" ]
}

# A copy just made for <video>: the outputs of its size playing that video
# (as it is, or a copy — a remade one has the same name, the player still
# holds the old file) take it at once, from the same moment, paused or not
# as they were: it only gets sharper.
swap_in() { # <video> <copy> <w> <h>
  local name w h path t
  [ -f "$2" ] || return 0
  while read -r name w h; do
    [ "$w" = "$3" ] && [ "$h" = "$4" ] || continue
    path=$(mpv_cmd "$name" '{"command":["get_property","path"]}' | jq -r '.data // empty')
    [ "$path" = "$1" ] || [[ "$path" == "$CACHE/$(key "$1")-"* ]] || continue
    t=$(mpv_cmd "$name" '{"command":["get_property","time-pos"]}' | jq -r '.data // 0')
    mpv_cmd "$name" "$(jq -nc --arg f "$2" --arg t "$t" \
      '{command: {name: "loadfile", url: $f, flags: "replace", options: "start=\($t)"}}')" >/dev/null
  done < <(outputs)
}

on_ac() { # no battery (a desktop) counts as AC
  local d
  for d in /sys/class/power_supply/*; do
    [ "$(cat "$d/type" 2>/dev/null)" = Mains ] && [ "$(cat "$d/online" 2>/dev/null)" = 1 ] && return 0
  done
  ! grep -qx Battery /sys/class/power_supply/*/type 2>/dev/null
}

# One file per video (a hash of its path), remade when the video is newer.
poster() { # <video>
  local dir out
  dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/wallpaper/video-thumbnails"
  out="$dir/$(printf '%s' "$1" | md5sum | cut -c1-32).jpg"
  if [ ! -s "$out" ] || [ "$1" -nt "$out" ]; then
    mkdir -p "$dir"
    if ! ffmpeg -v error -y -i "$1" -frames:v 1 -q:v 2 -f image2 "$out.$$.jpg" </dev/null; then
      rm -f "$out.$$.jpg"
      return 1
    fi
    mv -f "$out.$$.jpg" "$out"
  fi
  echo "$out"
}

# Prepares the library: every video of the folders (4 levels deep), the
# current wallpaper first, then the newest: its still frame, then (on AC
# power only) its copy for every output size. Copies of videos no longer
# there go, and leftovers of a stopped run.
prepare() { # <current video|-> <folder>...
  mkdir -p "$CACHE"
  exec 9>"$CACHE/.prepare.lock"
  # A run being replaced lets go of it a moment after its unit is killed
  # (its ffmpeg holds it too): wait for that, not for a whole other run.
  flock -w 15 9 || return 0
  local current="${1:--}"
  shift
  local -a videos=() outs=()
  local f w h c o
  [ "$current" != - ] && [ -f "$current" ] && videos+=("$current")
  while IFS= read -r -d '' f; do
    [ "$f" != "$current" ] && videos+=("$f")
  done < <(find "$@" -maxdepth 4 -type f -regextype posix-extended -regex "$VIDEO_RE" -printf '%T@ %p\0' 2>/dev/null |
    sort -z -rn | cut -z -d' ' -f2-)
  while read -r _ w h; do outs+=("$w $h"); done < <(outputs | sort -u -k2,3)
  find "$CACHE" -maxdepth 1 \( -name '.smooth.*' -o -name '*.part' \) -exec rm -rf {} +
  # Copies of earlier versions (made at play time, other names).
  find "$CACHE" -maxdepth 1 -name '*.mp4' ! -name '*.live.mp4' -delete
  local -A keep=()
  for f in "${videos[@]}"; do
    poster "$f" >/dev/null
    keep[$(key "$f")]=1
  done
  for f in "$CACHE"/*.live.mp4; do
    [ -e "$f" ] || continue
    c=$(basename "$f")
    [ -n "${keep[${c%%-*}]:-}" ] || rm -f "$f"
  done
  for f in "${videos[@]}"; do
    for o in "${outs[@]}"; do
      read -r w h <<<"$o"
      c=$(copy_path "$f" "$w" "$h")
      [ -f "$c" ] && ! stale "$f" "$c" "$w" "$h" && continue
      on_ac || return 0
      make_copy "$f" "$c" "$w" "$h" && swap_in "$f" "$c" "$w" "$h"
    done
  done
}

# This video (or its copy) playing on every output, on the Bottom layer (one
# left on the Background layer by an older version would sit under the still
# frame and look frozen), each answering on its socket (one started by an
# older version has none). `[m]` keeps the pattern from matching this
# script's own command line (the process itself is named `.mpvpaper-wrapp`,
# Nix wrapper).
running() {
  local procs want have name
  procs=$(pgrep -af "/bin/[m]pvpaper ") || return 1
  grep -qF -- " $video" <<<"$procs" || grep -qF -- "$CACHE/$(key "$video")-" <<<"$procs" || return 1
  while read -r name _; do
    [ -S "$(sock "$name")" ] || return 1
  done < <(outputs)
  want=$(outputs | wc -l)
  have=$(niri msg --json layers | jq '[.[] | select(.namespace == "mpvpaper" and .layer == "Bottom") | .output] | unique | length')
  [ "$have" -ge "$want" ]
}

# Switches the running players to this video, paused on its first frame
# (the shell resumes it): no new surface, nothing to restack. Fails when an
# output has no player answering (then `start` makes new ones).
switch() {
  local name w h f o
  local -a outs=()
  while read -r name w h; do outs+=("$name $w $h"); done < <(outputs)
  [ "${#outs[@]}" -gt 0 ] || return 1
  for o in "${outs[@]}"; do
    read -r name _ <<<"$o"
    mpv_cmd "$name" '{"command":["get_property","pid"]}' | grep -q '"success"' || return 1
  done
  for o in "${outs[@]}"; do
    read -r name w h <<<"$o"
    f=$(best_file "$video" "$w" "$h")
    mpv_cmd "$name" '{"command":["set_property","pause",true]}' >/dev/null
    mpv_cmd "$name" "$(jq -nc --arg f "$f" '{command: ["loadfile", $f, "replace"]}')" >/dev/null
  done
}

# New players (paused: the shell resumes them), once the old ones are gone;
# returns once every output shows its player and answers on its socket
# (then the shell lifts its widgets above them).
start() {
  stop_players
  mkdir -p "$RUNDIR"
  local name w h n=0 s ready
  local -a socks=()
  while read -r name w h; do
    socks+=("$(sock "$name")")
    rm -f "$(sock "$name")"
    # Its messages kept (small, in the runtime dir): why one ended, if it does.
    mpvpaper -p -l bottom -o "$OPTS input-ipc-server=$(sock "$name")" "$name" "$(best_file "$video" "$w" "$h")" \
      >"$RUNDIR/live-wallpaper-$name.log" 2>&1 </dev/null &
    n=$((n + 1))
  done < <(outputs)
  for _ in $(seq 150); do
    ready=1
    for s in "${socks[@]}"; do [ -S "$s" ] || ready=0; done
    [ "$ready" = 1 ] && [ "$(mpv_layers)" -ge "$n" ] && return 0
    sleep 0.1
  done
  return 1
}

if [ -z "$cmd" ] || { [ "$cmd" != prepare ] && [ ! -f "$video" ]; }; then
  echo "usage: $0 play|ensure|poster <video> | pause <output> yes|no | prepare-start <video|-> <folder>... | stop" >&2
  exit 1
fi

# Exit status, for the shell: 0 new players started and shown (lift the
# widgets), 11 switched inside the running players, 10 (ensure) this video
# already playing, 1 the players didn't show up.
case "$cmd" in
play)
  switch && exit 11
  start || exit 1
  ;;
ensure)
  running && exit 10
  start || exit 1
  ;;
poster) poster "$video" || exit 1 ;;
prepare)
  shift
  prepare "$@"
  ;;
*)
  echo "unknown command: $cmd" >&2
  exit 1
  ;;
esac
