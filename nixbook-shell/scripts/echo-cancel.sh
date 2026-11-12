# shellcheck shell=bash
# nixbook-echo-cancel: the computer's own sound kept out of the microphone,
# and voices made clearer in calls (services/EchoCancel.qml, the
# `nixbook-echo-cancel` user unit). No AI: an echo canceller, equalizers, a
# compressor and a limiter.
#
# PipeWire's echo canceller (module-echo-cancel, WebRTC, with noise
# suppression) in its own small PipeWire process, in monitor mode: what the
# default output plays is the reference to remove, so nothing is rerouted;
# it makes an "Echo-cancelled microphone" from the microphone, which becomes
# the default input while it runs (calls following the default move to it),
# and the previous one comes back when it stops.
#
# Two more stages, each a switch of the shell's settings (audio.calls, on
# unless set to false):
#
#   clearMicrophone  your voice, as others hear it: a speech equalizer
#                    (rumble and boxiness down, presence and air up), a
#                    compressor (a quiet or uneven voice brought up and
#                    evened) and a limiter. The canceller's own output is
#                    then $AEC, and this stage's keeps the name apps and the
#                    shell know.
#   clearVoices      the others' voices, as you hear them: a "Call voices"
#                    output ($VOICES) where call apps play instead of the
#                    music equalizer (a PipeWire stream rule gives them that
#                    target: hm-module.nix, echoCancel.callApps): the same
#                    three, tuned for listening, then the default output.
#
#   run       the canceller (the unit's ExecStart): for the microphone that
#             is the default input now
#   post      once it is up, make it the default input (ExecStartPost)
#   restore   the previous default input again (ExecStopPost)
#   status    {"active": bool, "source": "<node.name of the default input>"}
#
# Another microphone while it runs (services/EchoCancel.qml useMic): its
# node.name into $saved, then `systemctl --user restart` the unit — restore
# makes it the default input, run takes the default, post saves it again.
# The capture streams can't be moved (node.dont-move): EasyEffects' "process
# all input streams" moved the canceller's to its own source, which records
# the default input — this one —, a loop with no microphone in it
# (2026-11-11); and with its microphone gone a while (a suspend, unplugged),
# WirePlumber had put it on another one (the EarPods) and left it there. The
# shell restarts the unit when its microphone comes back. "Call voices" plays
# straight on the default output for the same reason: EasyEffects would take
# its playback stream into the music equalizer.
set -euo pipefail

SOURCE=nixbook-echo-cancel.source
AEC=nixbook-echo-cancel.aec
VOICES=nixbook-call-voices
dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixbook-shell"
mkdir -p "$dir"
chmod 700 "$dir"
conf="$dir/echo-cancel.conf"
saved="$dir/echo-cancel-previous-source"
settings="${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell/config.json"

# The node.name of a default device (@DEFAULT_AUDIO_SOURCE@ / _SINK@).
default_name() {
  wpctl inspect "$1" 2>/dev/null | sed -n 's/^[ *]*node\.name = "\(.*\)"$/\1/p' | head -n 1
}
# A node's id from its node.name ("" when it isn't there).
node_id() {
  pw-dump 2>/dev/null | jq -r --arg n "$1" \
    'first(.[] | select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $n) | .id) // empty'
}
# A switch of audio.calls in the shell's settings: on unless it is false
# there (no settings file, an older one without the key: on).
call_setting() {
  local rc=0
  jq -e --arg k "$1" '.audio.calls[$k] != false' "$settings" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 1 ]
}

# The compressor and the limiter (swh's LADSPA plugins) can be loaded.
have_dynamics() {
  local plugin dir found dirs
  IFS=: read -ra dirs <<<"${LADSPA_PATH:-}"
  for plugin in sc4_1882 fast_lookahead_limiter_1913; do
    found=0
    for dir in "${dirs[@]}"; do
      [ -e "$dir/$plugin.so" ] && found=1
    done
    [ "$found" -eq 1 ] || return 1
  done
}
# A filter-chain module for speech: DESCRIPTION, the compressor's MAKEUP gain
# (dB) and RATIO, the equalizer's FILTERS, then the properties of the stream
# it takes sound from and of the one it gives it to. An equalizer, a
# compressor (everything comes up by MAKEUP, what is over -30 dB is held by
# RATIO: quiet voices gain more than loud ones) and a limiter at -2 dB.
# Without the plugins, the equalizer alone, 2 dB down (the shelf at 0 Hz) so
# its boosts don't clip. nofail: a stage that can't load leaves the rest.
speech_stage() {
  local description=$1 makeup=$2 ratio=$3 filters=$4 capture=$5 playback=$6
  local dynamics="" links="" outputs='"eq:Out 1" "eq:Out 2"'
  if have_dynamics; then
    dynamics="
          { type = ladspa name = level plugin = \"sc4_1882\" label = sc4
            control = {
              \"RMS/peak\" = 0
              \"Attack time (ms)\" = 15
              \"Release time (ms)\" = 300
              \"Threshold level (dB)\" = -30
              \"Ratio (1:n)\" = $ratio
              \"Knee radius (dB)\" = 6
              \"Makeup gain (dB)\" = $makeup
            }
          }
          { type = ladspa name = limit plugin = \"fast_lookahead_limiter_1913\" label = fastLookaheadLimiter
            control = { \"Input gain (dB)\" = 0 \"Limit (dB)\" = -2 \"Release time (s)\" = 0.1 }
          }"
    links='
        links = [
          { output = "eq:Out 1" input = "level:Left input" }
          { output = "eq:Out 2" input = "level:Right input" }
          { output = "level:Left output" input = "limit:Input 1" }
          { output = "level:Right output" input = "limit:Input 2" }
        ]'
    outputs='"limit:Output 1" "limit:Output 2"'
  else
    filters="{ type = bq_highshelf freq = 0 gain = -2.0 q = 1.0 }
              $filters"
  fi
  cat <<EOF
  { name = libpipewire-module-filter-chain
    flags = [ nofail ]
    args = {
      node.description = "$description"
      audio.channels = 2
      audio.position = [ FL FR ]
      filter.graph = {
        nodes = [
          { type = builtin name = eq label = param_eq
            config = { filters = [
              $filters
            ] }
          }$dynamics
        ]$links
        inputs = [ "eq:In 1" "eq:In 2" ]
        outputs = [ $outputs ]
      }
      capture.props = {
        $capture
      }
      playback.props = {
        $playback
      }
    }
  }
EOF
}

case "${1:-}" in
run)
  mic=$(default_name @DEFAULT_AUDIO_SOURCE@)
  # Already ours (a canceller that didn't stop cleanly): the one before it.
  if [ "$mic" = "$SOURCE" ] || [ "$mic" = "$AEC" ] || [ -z "$mic" ]; then
    mic=$(cat "$saved" 2>/dev/null || true)
  fi
  target=""
  [ -n "$mic" ] && target="target.object = \"$mic\""

  # Your voice. Without this stage the canceller's output is the microphone
  # apps record; with it, the stage's output is. Speech from a laptop
  # microphone after noise suppression: nothing under 100 Hz, less of the
  # boxy 300 Hz, more of the consonants (3 kHz) and of the air above 8 kHz;
  # then the compressor's 14 dB (a loud voice is held to less).
  aec_name=$SOURCE
  aec_description="Echo-cancelled microphone"
  mic_stage=""
  if call_setting clearMicrophone; then
    aec_name=$AEC
    aec_description="Echo-cancelled microphone (before the voice stage)"
    mic_stage=$(
      speech_stage "Echo-cancelled microphone" 14 4 \
        '{ type = bq_highpass freq = 100 gain = 0 q = 0.7 }
              { type = bq_peaking freq = 300 gain = -3.0 q = 1.0 }
              { type = bq_peaking freq = 3200 gain = 4.0 q = 0.8 }
              { type = bq_highshelf freq = 8000 gain = 3.0 q = 0.7 }' \
        "node.name = \"nixbook-echo-cancel.voice\"
        node.passive = true
        node.dont-move = true
        target.object = \"$AEC\"" \
        "node.name = \"$SOURCE\"
        node.description = \"Echo-cancelled microphone\"
        media.class = \"Audio/Source\""
    )
  fi

  # The others' voices: "Call voices", where the stream rule sends call
  # apps. A quiet speaker comes up about 19 dB and a loud one about 11
  # (measured on speech 21 dB apart: 13 dB apart after), never over -2 dB.
  voices_stage=""
  if call_setting clearVoices; then
    voices_stage=$(
      speech_stage "Call voices" 20 6 \
        '{ type = bq_highpass freq = 90 gain = 0 q = 0.7 }
              { type = bq_peaking freq = 300 gain = -2.0 q = 1.0 }
              { type = bq_peaking freq = 3000 gain = 3.5 q = 0.8 }
              { type = bq_highshelf freq = 7500 gain = 2.0 q = 0.7 }' \
        "node.name = \"$VOICES\"
        node.description = \"Call voices\"
        media.class = \"Audio/Sink\"
        priority.session = 0" \
        "node.name = \"$VOICES.playback\"
        node.passive = true
        node.dont-move = true"
    )
  fi

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
        node.dont-move = true
        $target
      }
      source.props = {
        node.name = "$aec_name"
        node.description = "$aec_description"
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
$mic_stage
$voices_stage
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
  if [ -n "$prev" ] && [ "$prev" != "$SOURCE" ] && [ "$prev" != "$AEC" ]; then
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
