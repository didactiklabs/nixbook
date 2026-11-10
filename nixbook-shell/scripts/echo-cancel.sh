# shellcheck shell=bash
# nixbook-echo-cancel: the computer's own sound kept out of the microphone
# (services/EchoCancel.qml, the `nixbook-echo-cancel` user unit).
#
# PipeWire's echo canceller (module-echo-cancel, WebRTC, with noise
# suppression) in its own small PipeWire process, in monitor mode: what the
# default output plays is the reference to remove, so nothing is rerouted;
# it makes an "Echo-cancelled microphone" from the microphone, which becomes
# the default input while it runs (calls following the default move to it),
# and the previous one comes back when it stops.
#
#   run       the canceller (the unit's ExecStart): for the microphone that
#             is the default input now
#   post      once it is up, make it the default input (ExecStartPost)
#   restore   the previous default input again (ExecStopPost)
#   status    {"active": bool, "source": "<node.name of the default input>"}
set -euo pipefail

SOURCE=nixbook-echo-cancel.source
dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixbook-shell"
mkdir -p "$dir"
chmod 700 "$dir"
conf="$dir/echo-cancel.conf"
saved="$dir/echo-cancel-previous-source"

# The node.name of a default device (@DEFAULT_AUDIO_SOURCE@ / _SINK@).
default_name() {
  wpctl inspect "$1" 2>/dev/null | sed -n 's/^[ *]*node\.name = "\(.*\)"$/\1/p' | head -n 1
}
# A node's id from its node.name ("" when it isn't there).
node_id() {
  pw-dump 2>/dev/null | jq -r --arg n "$1" \
    'first(.[] | select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $n) | .id) // empty'
}

case "${1:-}" in
run)
  mic=$(default_name @DEFAULT_AUDIO_SOURCE@)
  # Already ours (a canceller that didn't stop cleanly): the one before it.
  if [ "$mic" = "$SOURCE" ] || [ -z "$mic" ]; then
    mic=$(cat "$saved" 2>/dev/null || true)
  fi
  target=""
  [ -n "$mic" ] && target="target.object = \"$mic\""
  cat >"$conf" <<EOF
context.properties = { log.level = 2 }
context.spa-libs = {
  audio.convert.* = audioconvert/libspa-audioconvert
  support.*       = support/libspa-support
}
context.modules = [
  { name = libpipewire-module-rt args = { nice.level = -11 } flags = [ ifexists nofail ] }
  { name = libpipewire-module-protocol-native }
  { name = libpipewire-module-client-node }
  { name = libpipewire-module-adapter }
  { name = libpipewire-module-echo-cancel
    args = {
      library.name = aec/libspa-aec-webrtc
      # The reference is what the default output plays (its monitor).
      monitor.mode = true
      aec.args = {
        webrtc.noise_suppression = true
        webrtc.high_pass_filter = true
        webrtc.gain_control = false
      }
      capture.props = {
        node.name = "nixbook-echo-cancel.capture"
        node.passive = true
        $target
      }
      source.props = {
        node.name = "$SOURCE"
        node.description = "Echo-cancelled microphone"
        media.class = "Audio/Source"
      }
      # Monitor mode: the reference stream, from the default output's monitor.
      sink.props = {
        node.name = "nixbook-echo-cancel.reference"
        node.description = "Echo cancellation reference"
        node.passive = true
      }
    }
  }
]
EOF
  exec pipewire -c "$conf"
  ;;
post)
  for _ in $(seq 50); do
    id=$(node_id "$SOURCE")
    [ -n "$id" ] && break
    sleep 0.2
  done
  [ -n "${id:-}" ] || {
    echo "the echo-cancelled microphone didn't appear" >&2
    exit 1
  }
  prev=$(default_name @DEFAULT_AUDIO_SOURCE@)
  if [ -n "$prev" ] && [ "$prev" != "$SOURCE" ]; then
    printf '%s\n' "$prev" >"$saved"
  fi
  wpctl set-default "$id"
  ;;
restore)
  prev=$(cat "$saved" 2>/dev/null || true)
  rm -f "$saved"
  if [ -n "$prev" ]; then
    id=$(node_id "$prev")
    [ -z "$id" ] || wpctl set-default "$id"
  fi
  ;;
status)
  active=false
  [ -n "$(node_id "$SOURCE")" ] && active=true
  jq -cn --argjson active "$active" --arg source "$(default_name @DEFAULT_AUDIO_SOURCE@)" \
    '{active: $active, source: $source}'
  ;;
*)
  echo "usage: nixbook-echo-cancel run|post|restore|status" >&2
  exit 2
  ;;
esac
