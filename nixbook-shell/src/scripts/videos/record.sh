#!/usr/bin/env bash
CONFIG_FILE="$HOME/.config/nixbook-shell/config.json"
JSON_PATH=".screenRecord.savePath"
CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)
RECORDING_DIR=""
if [[ -n $CUSTOM_PATH ]]; then
  RECORDING_DIR="$CUSTOM_PATH"
else
  RECORDING_DIR="$HOME/Videos"
fi

set_recording_state() {
  local state=$1
  local STATE_FILE="$HOME/.local/state/quickshell/states.json"
  local tmp=$(mktemp)
  jq ".record.enable = $state" "$STATE_FILE" >"$tmp" && mv "$tmp" "$STATE_FILE"
}

getdate() {
  date '+%Y-%m-%d_%H.%M.%S'
}
# The desktop audio: the monitor of the default output (every sink has one,
# so the first monitor listed is only a fallback).
getaudiooutput() {
  local sink
  sink=$(pactl get-default-sink 2>/dev/null)
  if [[ -n $sink ]]; then
    echo "$sink.monitor"
  else
    pactl list short sources 2>/dev/null | awk '$2 ~ /\.monitor$/ { print $2; exit }'
  fi
}

getactivemonitor() {
  niri msg --json focused-output | jq -r '.name // empty'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# Usage: record.sh [--region "X,Y WxH" | --output NAME | --fullscreen] [--no-sound]
# Starts a recording (of the region, the output, the focused output, else a
# region picked with slurp), with the desktop audio unless --no-sound; stops
# the running one when there is one. --sound is the default, still accepted.
ARGS=("$@")
MANUAL_REGION=""
OUTPUT=""
SOUND_FLAG=1
FULLSCREEN_FLAG=0
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  if [[ ${ARGS[i]} == "--region" ]]; then
    if ((i + 1 < ${#ARGS[@]})); then
      MANUAL_REGION="${ARGS[i + 1]}"
    else
      notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' &
      disown
      exit 1
    fi
  elif [[ ${ARGS[i]} == "--output" ]]; then
    if ((i + 1 < ${#ARGS[@]})); then
      OUTPUT="${ARGS[i + 1]}"
    else
      notify-send "Recording cancelled" "No output specified for --output" -a 'Recorder' &
      disown
      exit 1
    fi
  elif [[ ${ARGS[i]} == "--sound" ]]; then
    SOUND_FLAG=1
  elif [[ ${ARGS[i]} == "--no-sound" ]]; then
    SOUND_FLAG=0
  elif [[ ${ARGS[i]} == "--fullscreen" ]]; then
    FULLSCREEN_FLAG=1
  fi
done

if pgrep wf-recorder >/dev/null; then
  notify-send "Recording Stopped" "Copied to the clipboard" -a 'Recorder' &
  pkill wf-recorder &
  set_recording_state false
else
  if [[ $FULLSCREEN_FLAG -eq 1 && -z $OUTPUT ]]; then
    OUTPUT="$(getactivemonitor)"
  fi
  if [[ -n $OUTPUT ]]; then
    target=(-o "$OUTPUT")
  else
    if [[ -n $MANUAL_REGION ]]; then
      region="$MANUAL_REGION"
    else
      if ! region="$(slurp 2>&1)"; then
        notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' &
        disown
        exit 1
      fi
    fi
    target=(--geometry "$region")
  fi
  audio=()
  if [[ $SOUND_FLAG -eq 1 ]]; then
    audio=(--audio="$(getaudiooutput)")
  fi
  file='./recording_'"$(getdate)"'.mp4'
  notify-send "Starting recording" "${file#./}" -a 'Recorder' &
  disown
  set_recording_state true
  wf-recorder "${target[@]}" --pixel-format yuv420p -f "$file" -t "${audio[@]}"
  set_recording_state false
  # The video in the clipboard as a file (pasted into a file manager or a chat).
  if [[ -s $file ]]; then
    wl-copy --type text/uri-list "file://$PWD/${file#./}"
  fi
fi
