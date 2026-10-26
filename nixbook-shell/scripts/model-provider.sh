# shellcheck shell=bash
# nixbook-model-provider: which model provider Claude Code talks to. Every
# Claude Code the shell starts (the side panel, the memory and initiative
# passes, routines, the equalizer agent, nixbook-improve) is started through
# `nixbook-model-provider run CLAUDE ARGS…`. With the default provider,
# Anthropic, that is Claude Code on the user's own Claude login, unchanged;
# with another one, Claude Code is pointed at its Anthropic-compatible
# Messages API (ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN, never the claude.ai
# login) and Claude's model names are mapped to the provider's.
#
# The setting is the shell's (Settings > Desktop agents > Model provider):
# ai.provider = {kind: anthropic|meta|custom, baseUrl, model, smallModel,
# bigModel} in ~/.config/nixbook-shell/config.json. The API key is in the
# keyring (secret-tool), stored per provider and host: a key saved for one
# server is never sent to another.
#
#   run CLAUDE [ARGS…]  exec Claude Code with the provider's environment
#   status              {kind, label, baseUrl, host, model, smallModel,
#                        bigModel, keySaved, error}
#   key set             the key on stdin → {saved} or {error}
#   key forget          → {saved: false}
#   test                one short request → {ok, model, answer} or {ok: false, error}
set -uo pipefail

config=${NIXBOOK_SHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell/config.json}

# The provider's settings, presets filled in: kind, base URL, main, small
# and big model (one line each).
settings() {
  jq -r '
    def presets: {meta: {baseUrl: "https://api.meta.ai", model: "muse-spark-1.3", smallModel: "muse-spark-1.3", bigModel: "muse-wonder-1.0"}};
    (.ai.provider // {}) as $p
    | (($p.kind // "anthropic") | tostring | ascii_downcase) as $k
    | (presets[$k] // {}) as $preset
    | [ "baseUrl", "model", "smallModel", "bigModel" ]
    | map(($p[.] // "" | tostring) as $v | if $v == "" then ($preset[.] // "") else $v end) as $v
    | $k, ($v[0] | sub("/+$"; "")), $v[1], $v[2], $v[3]
  ' "$config" 2>/dev/null || printf 'anthropic\n\n\n\n\n'
}

{
  read -r kind
  read -r base
  read -r model
  read -r small
  read -r big
} < <(settings)
kind=${kind:-anthropic}
case "$kind" in
anthropic) label="Anthropic" ;;
meta) label="Meta" ;;
custom) label="Custom" ;;
*)
  label=$kind
  ;;
esac

# The URL's error, if any: https, or http on this computer only (a local
# gateway); never a key sent in clear over the network.
url_error() {
  case "$kind" in
  anthropic) return 0 ;;
  meta | custom) ;;
  *)
    echo "unknown provider \"$kind\""
    return 0
    ;;
  esac
  if [ -z "$base" ]; then
    echo "no server URL"
  elif [[ ! $base =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] &&
    [[ ! $base =~ ^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]]; then
    echo "the server URL must be https:// (or http:// on this computer): $base"
  elif [ -z "$model" ]; then
    echo "no model"
  fi
}
host=$(sed -E 's#^[a-z]+://([^/]+).*#\1#' <<<"$base")
attrs=(application nixbook-shell kind model-provider provider "$kind" host "$host")

lookup_key() {
  secret-tool lookup "${attrs[@]}" 2>/dev/null
}

# What a Claude model name becomes on the provider: the aliases and full
# Claude ids by family; the provider's own ids as they are.
map_model() {
  local v=$1 to=""
  case "$v" in
  *haiku*) to=$small ;;
  *opus* | *fable*) to=$big ;;
  sonnet* | claude-* | default) to=$model ;;
  esac
  printf '%s' "${to:-$v}"
}

# A failure the caller can read: Claude Code's own result line when it was
# asked for JSON, otherwise on stderr.
fail_run() {
  local msg="$label: $1"
  if [[ " ${run_args[*]} " =~ \ --output-format[=\ ](stream-)?json\  ]]; then
    jq -cn --arg m "$msg" '{type: "result", subtype: "error_during_execution", is_error: true, result: $m}'
  fi
  echo "nixbook-model-provider: $msg" >&2
  exit 3
}

cmd_run() {
  local claude=${1:-}
  shift || true
  run_args=("$@")
  [ -n "$claude" ] || {
    echo "usage: nixbook-model-provider run CLAUDE [ARGS…]" >&2
    exit 2
  }
  if [ "$kind" = anthropic ]; then
    exec "$claude" "$@"
  fi
  local err key
  err=$(url_error)
  [ -z "$err" ] || fail_run "$err (Settings > Desktop agents > Model provider)"
  key=$(lookup_key)
  [ -n "$key" ] || fail_run "no API key saved (Settings > Desktop agents > Model provider)"
  # Only the provider's key: never the claude.ai login, nor an Anthropic
  # key from the environment (it would be sent to that server).
  unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_SMALL_FAST_MODEL
  export ANTHROPIC_BASE_URL=$base ANTHROPIC_AUTH_TOKEN=$key
  export ANTHROPIC_MODEL=$model ANTHROPIC_DEFAULT_SONNET_MODEL=$model CLAUDE_CODE_SUBAGENT_MODEL=$model
  export ANTHROPIC_DEFAULT_HAIKU_MODEL=${small:-$model} ANTHROPIC_DEFAULT_OPUS_MODEL=${big:-$model}
  # No telemetry or update checks to Anthropic while using someone else.
  export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
  local out=() a next=""
  for a in "$@"; do
    if [ -n "$next" ]; then
      out+=("$(map_model "$a")")
      next=""
      continue
    fi
    case "$a" in
    --model | --fallback-model)
      out+=("$a")
      next=1
      ;;
    --model=* | --fallback-model=*) out+=("${a%%=*}=$(map_model "${a#*=}")") ;;
    *) out+=("$a") ;;
    esac
  done
  exec "$claude" "${out[@]}"
}

cmd_status() {
  local saved=false err
  err=$(url_error)
  [ "$kind" != anthropic ] && [ -z "$err" ] && [ -n "$(lookup_key)" ] && saved=true
  jq -cn --arg kind "$kind" --arg label "$label" --arg base "$base" --arg host "$host" --arg model "$model" \
    --arg small "$small" --arg big "$big" --argjson saved "$saved" --arg err "$err" \
    '{kind: $kind, label: $label, baseUrl: $base, host: $host, model: $model, smallModel: $small,
      bigModel: $big, keySaved: $saved, error: $err}'
}

cmd_key() {
  local err key
  case "${1:-}" in
  set)
    [ "$kind" != anthropic ] || {
      jq -cn '{error: "Anthropic uses your Claude login: no key to save"}'
      return
    }
    err=$(url_error)
    [ -z "$err" ] || {
      jq -cn --arg e "$err" '{error: $e}'
      return
    }
    IFS= read -r key || true
    key=$(tr -d '[:space:]' <<<"$key")
    [[ -n $key && $key =~ ^[[:print:]]+$ ]] || {
      jq -cn '{error: "empty key"}'
      return
    }
    if printf '%s' "$key" | secret-tool store --label="nixbook-shell: $label API key ($host)" "${attrs[@]}" 2>/dev/null; then
      jq -cn '{saved: true}'
    else
      jq -cn '{error: "the keyring refused it (secret-tool store)"}'
    fi
    ;;
  forget)
    secret-tool clear "${attrs[@]}" 2>/dev/null
    jq -cn '{saved: false}'
    ;;
  *)
    echo "usage: nixbook-model-provider key set|forget" >&2
    exit 2
    ;;
  esac
}

cmd_test() {
  local err key reply code
  [ "$kind" != anthropic ] || {
    jq -cn '{ok: true, model: "claude", answer: "Anthropic: Claude Code on your Claude login"}'
    return
  }
  err=$(url_error)
  [ -z "$err" ] || {
    jq -cn --arg e "$err" '{ok: false, error: $e}'
    return
  }
  key=$(lookup_key)
  [ -n "$key" ] || {
    jq -cn '{ok: false, error: "no API key saved"}'
    return
  }
  # The key as a header from a file descriptor, never on a command line.
  reply=$(curl -sS -m 40 -w '\n%{http_code}' "$base/v1/messages" \
    -H @<(printf 'Authorization: Bearer %s\n' "$key") \
    -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
    --data "$(jq -cn --arg m "$model" '{model: $m, max_tokens: 32, messages: [{role: "user", content: "Answer with one word: ready."}]}')" 2>&1)
  code=$(tail -n1 <<<"$reply")
  reply=$(sed '$d' <<<"$reply")
  if [ "$code" = 200 ]; then
    jq -c --arg m "$model" '{ok: true, model: (.model // $m), answer: ([.content[]? | select(.type == "text") | .text] | join("") | .[0:80])}' <<<"$reply" 2>/dev/null ||
      jq -cn '{ok: false, error: "the server answered something that is not a Messages API reply"}'
  else
    jq -cn --arg c "$code" --arg r "$reply" \
      '{ok: false, error: ("HTTP " + $c + ": " + (($r | fromjson? | .error.message // .message // .error // empty | tostring) // $r | .[0:200]))}'
  fi
}

case "${1:-}" in
run)
  shift
  cmd_run "$@"
  ;;
status) cmd_status ;;
key)
  shift
  cmd_key "$@"
  ;;
test) cmd_test ;;
*)
  echo "usage: nixbook-model-provider run CLAUDE [ARGS…] | status | key set|forget | test" >&2
  exit 2
  ;;
esac
