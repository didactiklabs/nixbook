#!/usr/bin/env bash
# Prints songrec's first match (one line of Shazam JSON) heard on the default
# output (-s monitor) or input (-s input) within -t seconds, asking Shazam
# every -i seconds; nothing when there is none. Exits 1 when songrec or an
# audio source is missing.

INTERVAL=4
TOTAL_DURATION=16
SOURCE_TYPE="monitor" # monitor | input
FIFO=$(mktemp -u "${TMPDIR:-/tmp}/songrec_out_XXXXXX")

while getopts "i:t:s:" opt; do
  case $opt in
  i) INTERVAL=$OPTARG ;;
  t) TOTAL_DURATION=$OPTARG ;;
  s) SOURCE_TYPE=$OPTARG ;;
  *) exit 1 ;;
  esac
done

if ! command -v songrec >/dev/null 2>&1; then
  exit 1
fi

# get-default-*, not `pactl info`: its "Default Sink:" line is translated
# (e.g. "Destination par défaut" in French), so it wasn't found there.
if [ "$SOURCE_TYPE" = "monitor" ]; then
  AUDIO_DEVICE=$(pactl get-default-sink 2>/dev/null)
  [ -z "$AUDIO_DEVICE" ] || AUDIO_DEVICE="$AUDIO_DEVICE.monitor"
elif [ "$SOURCE_TYPE" = "input" ]; then
  AUDIO_DEVICE=$(pactl get-default-source 2>/dev/null)
else
  echo "Invalid source type" >&2
  exit 1
fi

sources=$(pactl list short sources 2>/dev/null | awk '{print $2}')
if [ -z "$AUDIO_DEVICE" ] || ! grep -Fxq -- "$AUDIO_DEVICE" <<<"$sources"; then
  # No default: the first monitor (or input) there is, else any source.
  if [ "$SOURCE_TYPE" = "monitor" ]; then
    AUDIO_DEVICE=$(grep -m1 '\.monitor$' <<<"$sources")
  else
    AUDIO_DEVICE=$(grep -m1 -v '\.monitor$' <<<"$sources")
  fi
  [ -n "$AUDIO_DEVICE" ] || AUDIO_DEVICE=$(head -n 1 <<<"$sources")
  if [ -z "$AUDIO_DEVICE" ]; then
    exit 1
  fi
fi

mkfifo "$FIFO"

cleanup() {
  kill "$SONGREC_PID" 2>/dev/null || true
  wait "$SONGREC_PID" 2>/dev/null
  rm -f "$FIFO"
}
trap cleanup EXIT

# `timeout` ends it after the time limit (and the loop below with it). A
# background `sleep && kill` used to hold our stdout open, so a match only
# reached the shell once the whole time limit was over.
timeout "$TOTAL_DURATION" songrec listen --audio-device "$AUDIO_DEVICE" \
  --request-interval "$INTERVAL" --json --disable-mpris >"$FIFO" 2>/dev/null &
SONGREC_PID=$!

while IFS= read -r line; do
  if grep -q '"matches" *: *\[' <<<"$line"; then
    if grep -q '"matches" *: *\[\]' <<<"$line"; then
      continue
    fi
    echo "$line"
    exit 0
  fi
done <"$FIFO"

exit 0
