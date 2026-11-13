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
#                    target: `call-rules` below, from audio.calls.apps and
#                    .sites): the same
#                    three, tuned for listening, then the default output.
#
#   run       the canceller (the unit's ExecStart): for the microphone that
#             is the default input now
#   post      once it is up, make it the default input (ExecStartPost)
#   restore   the previous default input again (ExecStopPost)
#   status    {"active": bool, "source": "<node.name of the default input>",
#             "resting": bool}
#   rest on|off   let it rest / wake it (services/EchoCancel.qml, below)
#   call-rules [--restart]   the call apps' stream rule (below), from the
#             settings; {"changed": bool}; --restart: pipewire-pulse
#             restarted when it changed
#
# Call apps (audio.calls.apps: a word of an app's name or program name, any
# case) and calls in a Firefox-family browser (audio.calls.sites: the whole
# tab title, which those browsers give each tab's sound stream; Chromium names
# them all "Playback") play on "Call voices": a PipeWire stream rule giving
# them that target, and node.dont-move so EasyEffects can't take them back,
# in the user's pipewire-pulse.conf.d (PulseAudio clients: Electron apps) and
# client.conf.d (PipeWire's own). Read when the sound server and each app
# start: pipewire-pulse is restarted for a change (services/EchoCancel.qml,
# a few seconds after the last edit). Without "Call voices" they play on the
# default output. Both lists empty: no rule.
#
# Resting. PipeWire runs what is downstream of an output that plays, through
# passive links too: with the reference on the default output, the canceller
# and the microphone ran whenever any sound played, with nobody recording
# (music alone: 18 % of a core, the microphone powered, and the whole audio
# graph at the canceller's 5 ms period instead of 21 ms; measured on totoro).
# So while nothing records the cancelled microphone, the shell points the
# reference stream at $IDLE, a sink of this unit nothing plays on: nothing of
# the canceller runs. Something that starts recording runs the chain by itself
# (its link isn't passive), and the shell puts the reference back on the
# default output at once (WirePlumber links it: a stream without a target).
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
REFERENCE=nixbook-echo-cancel.reference
IDLE=nixbook-echo-cancel.idle
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

# A word in any case, as a POSIX regular expression: "Slack" is
# [sS][lL][aA][cC][kK], "." is [.].
any_case() {
  local word=$1 out="" c i
  for ((i = 0; i < ${#word}; i++)); do
    c=${word:i:1}
    case "$c" in
    [A-Za-z]) out+="[${c,,}${c^^}]" ;;
    .) out+="[.]" ;;
    *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}
DEFAULT_CALL_APPS='["vesktop","discord","webcord","slack","zoom","teams","element","signal","telegram","whatsapp","skype","jitsi","mumble","teamspeak"]'
DEFAULT_CALL_SITES='["Meet( (-|–|—) .*)?","Google Meet.*",".* [|] Jitsi Meet",".* [|] Microsoft Teams"]'
# The rule's text from the settings ("" when it has nothing to match). Words
# with other characters, and sites with a quote or a backslash, are left out.
call_rule() {
  local apps sites word pattern="" site_pattern="" browsers=""
  apps=$(jq -r --argjson d "$DEFAULT_CALL_APPS" '(.audio.calls.apps // $d)[]? | select(type == "string")' "$settings" 2>/dev/null ||
    jq -rn --argjson d "$DEFAULT_CALL_APPS" '$d[]')
  sites=$(jq -r --argjson d "$DEFAULT_CALL_SITES" '(.audio.calls.sites // $d)[]? | select(type == "string")' "$settings" 2>/dev/null ||
    jq -rn --argjson d "$DEFAULT_CALL_SITES" '$d[]')
  while IFS= read -r word; do
    [[ $word =~ ^[A-Za-z0-9\ ._-]+$ ]] || continue
    pattern+="${pattern:+|}$(any_case "$word")"
  done <<<"$apps"
  while IFS= read -r word; do
    [ -n "$word" ] && [[ $word != *[\"\\]* ]] || continue
    site_pattern+="${site_pattern:+|}$word"
  done <<<"$sites"
  for word in twilight zen firefox librewolf floorp waterfox; do
    browsers+="${browsers:+|}$(any_case "$word")"
  done
  [ -n "$pattern$site_pattern" ] || return 0
  printf '%s\n' '# nixbook-shell (audio.calls.apps and .sites, Settings > Sound): call apps' \
    '# and calls in a browser play on "Call voices", or straight on the default' \
    '# output without it. Written by nixbook-echo-cancel call-rules.' \
    'stream.rules = [' '  { matches = ['
  if [ -n "$pattern" ]; then
    printf '      { application.name = "~.*(%s).*" media.class = "Stream/Output/Audio" }\n' "$pattern"
    printf '      { application.process.binary = "~.*(%s).*" media.class = "Stream/Output/Audio" }\n' "$pattern"
  fi
  if [ -n "$site_pattern" ]; then
    printf '      { application.name = "~.*(%s).*" media.name = "~^(%s)$" media.class = "Stream/Output/Audio" }\n' \
      "$browsers" "$site_pattern"
  fi
  printf '%s\n' '    ]' '    actions = { update-props = { node.dont-move = true target.object = "'"$VOICES"'" } }' '  }' ']'
}

case "${1:-}" in
call-rules)
  rule=$(call_rule)
  changed=false
  for sub in pipewire-pulse.conf.d client.conf.d; do
    file="${XDG_CONFIG_HOME:-$HOME/.config}/pipewire/$sub/60-nixbook-call-voices.conf"
    if [ -z "$rule" ]; then
      if [ -e "$file" ] || [ -L "$file" ]; then
        rm -f "$file"
        changed=true
      fi
      continue
    fi
    [ ! -L "$file" ] && [ "$(cat "$file" 2>/dev/null)" = "$rule" ] && continue
    mkdir -p "${file%/*}"
    # A link left by an older Home Manager generation is replaced too.
    rm -f "$file"
    printf '%s\n' "$rule" >"$file.tmp"
    mv -f "$file.tmp" "$file"
    changed=true
  done
  if [ "$changed" = true ] && [ "${2:-}" = --restart ]; then
    systemctl --user try-restart pipewire-pulse.service || true
  fi
  printf '{"changed": %s}\n' "$changed"
  ;;
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
        node.name = "$REFERENCE"
        node.description = "Echo cancellation reference"
        node.passive = true
        # A new unit starts awake: a target set while it rested isn't kept.
        state.restore-target = false
      }
    }
  }
  # Where the reference rests (see "Resting" above): a sink nothing plays on,
  # its output connected to nothing. Neither is of a class mixers know
  # ("Audio/Sink", "Stream/Output/Audio"): none lists them, the shell's
  # included, and the sink is never the default output.
  { name = libpipewire-module-loopback
    flags = [ nofail ]
    args = {
      node.description = "Echo cancellation (resting)"
      audio.position = [ FL FR ]
      capture.props = {
        node.name = "$IDLE"
        media.class = "Audio/Sink/Internal"
      }
      playback.props = {
        node.name = "$IDLE.out"
        media.class = "Stream/Output/Audio/Internal"
        node.autoconnect = false
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
rest)
  # Not running, or a unit without the idle sink (it didn't load): nothing
  # to do, the reference stays where it is.
  reference=$(node_id "$REFERENCE")
  [ -n "$reference" ] || exit 0
  case "${2:-}" in
  on)
    [ -n "$(node_id "$IDLE")" ] || exit 0
    pw-metadata -n default "$reference" target.object "$IDLE" >/dev/null
    ;;
  off)
    pw-metadata -n default -d "$reference" target.object >/dev/null
    ;;
  *)
    echo "usage: nixbook-echo-cancel rest on|off" >&2
    exit 2
    ;;
  esac
  ;;
status)
  active=false
  [ -n "$(node_id "$SOURCE")" ] && active=true
  resting=false
  reference=$(node_id "$REFERENCE")
  if [ -n "$reference" ] && pw-metadata -n default "$reference" target.object 2>/dev/null | grep -qF "value:'$IDLE'"; then
    resting=true
  fi
  jq -cn --argjson active "$active" --argjson resting "$resting" --arg source "$(default_name @DEFAULT_AUDIO_SOURCE@)" \
    '{active: $active, source: $source, resting: $resting}'
  ;;
*)
  echo "usage: nixbook-echo-cancel run|post|restore|status|rest on|off|call-rules [--restart]" >&2
  exit 2
  ;;
esac
