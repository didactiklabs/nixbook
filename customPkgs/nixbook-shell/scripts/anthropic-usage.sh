# shellcheck shell=bash
# Minimal Anthropic (Claude) usage reader for the nixbook-shell bar widget.
# Auth, in order: Claude Code's own OAuth credentials
# (~/.claude/.credentials.json — Claude Code keeps that token fresh while it
# runs, so a click always gets live numbers), then the copy opencode keeps
# (~/.local/share/opencode/auth.json, refreshed here only when neither CLI is
# running).
# Refresh mirrors the active opencode-claude-auth plugin (dist/credentials.js:
# claude.ai token endpoint + its OAuth client id) and writes rotated tokens
# back. Prints KEY=VALUE lines on stdout; always exits 0 so the widget can
# degrade gracefully. Data is cached for 120s; 429s honour Retry-After and
# serve the last good cache until it expires. `--force` skips the 120s cache
# (the widget's click-to-refresh) but still honours a 429 backoff.

set -u

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
CLAUDE_CREDS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/anthropic-usage"
USAGE_CACHE="$CACHE_DIR/usage.json"
BACKOFF_FILE="$CACHE_DIR/backoff"
TTL=120
TOKEN_URL="https://claude.ai/v1/oauth/token"
OAUTH_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"

mkdir -p "$CACHE_DIR"

emit() {
  local status="${1:-error}"
  local data="${2:-}"
  echo "STATUS=$status"
  echo "UPDATED_AT=$(jq -r '.cached_at // 0' "$USAGE_CACHE" 2>/dev/null || printf '0')"
  if [ -n "$data" ] && printf '%s' "$data" | jq -e '.five_hour' >/dev/null 2>&1; then
    echo "PLAN_TYPE=$(printf '%s' "$data" | jq -r '.plan_type // "pro"')"
    echo "FIVE_HOUR_UTIL=$(printf '%s' "$data" | jq -r '.five_hour.utilization // -1')"
    echo "FIVE_HOUR_RESET=$(printf '%s' "$data" | jq -r '.five_hour.resets_at // ""')"
    echo "SEVEN_DAY_UTIL=$(printf '%s' "$data" | jq -r '.seven_day.utilization // -1')"
    echo "SEVEN_DAY_RESET=$(printf '%s' "$data" | jq -r '.seven_day.resets_at // ""')"
  else
    echo "PLAN_TYPE="
    echo "FIVE_HOUR_UTIL=-1"
    echo "FIVE_HOUR_RESET="
    echo "SEVEN_DAY_UTIL=-1"
    echo "SEVEN_DAY_RESET="
  fi
}

cached_data() {
  if [ -f "$USAGE_CACHE" ]; then
    jq -r '.data // empty' "$USAGE_CACHE" 2>/dev/null || printf ''
  fi
}

# Claude Code's current access token, if it isn't about to expire.
claude_code_token() {
  [ -f "$CLAUDE_CREDS" ] || return 1
  local access expires now_ms
  access=$(jq -r '.claudeAiOauth.accessToken // ""' "$CLAUDE_CREDS" 2>/dev/null || printf '')
  expires=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CLAUDE_CREDS" 2>/dev/null || printf '0')
  now_ms=$(($(date +%s) * 1000))
  if [ -n "$access" ] && [ "${expires:-0}" -gt "$((now_ms + 60000))" ] 2>/dev/null; then
    printf '%s' "$access"
    return 0
  fi
  return 1
}

get_token() {
  claude_code_token && return 0
  [ -f "$AUTH_FILE" ] || return 1

  local access refresh expires now_ms
  access=$(jq -r '.anthropic.access // ""' "$AUTH_FILE" 2>/dev/null || printf '')
  refresh=$(jq -r '.anthropic.refresh // ""' "$AUTH_FILE" 2>/dev/null || printf '')
  expires=$(jq -r '.anthropic.expires // 0' "$AUTH_FILE" 2>/dev/null || printf '0')
  now_ms=$(($(date +%s) * 1000))

  if [ -n "$access" ] && [ "${expires:-0}" -gt "$((now_ms + 60000))" ] 2>/dev/null; then
    printf '%s' "$access"
    return 0
  fi

  # Reuse a stored token only when we cannot prove it is expired (no expiry
  # metadata). Sending a known-expired token just earns a 401/429 and a
  # pointless backoff, so a dead refresh must surface as "no auth" instead.
  if [ -z "$refresh" ]; then
    if [ -n "$access" ] && [ "${expires:-0}" -le 0 ] 2>/dev/null; then
      printf '%s' "$access"
      return 0
    fi
    return 1
  fi

  # Refresh tokens rotate: refreshing here while opencode or the claude CLI is
  # running would invalidate the copy they hold in memory and force the user to
  # re-authenticate. While they are up they refresh (and rewrite $AUTH_FILE)
  # themselves, so back off and serve the cache until they do.
  if pgrep -f '/\.?(opencode|claude)(-wrapped)?( |$)' >/dev/null 2>&1; then
    return 1
  fi

  local resp new_access new_refresh new_expires
  resp=$(curl -s --max-time 10 -X POST "$TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=refresh_token&refresh_token=${refresh}&client_id=${OAUTH_CLIENT_ID}" \
    2>/dev/null) || resp=""
  new_access=$(printf '%s' "$resp" | jq -r '.access_token // empty' 2>/dev/null)
  new_refresh=$(printf '%s' "$resp" | jq -r '.refresh_token // empty' 2>/dev/null)
  new_expires=$(printf '%s' "$resp" | jq -r '.expires_in // empty' 2>/dev/null)

  if [ -z "$new_access" ]; then
    if [ -n "$access" ] && [ "${expires:-0}" -le 0 ] 2>/dev/null; then
      printf '%s' "$access"
      return 0
    fi
    return 1
  fi

  local new_expires_ms=$((now_ms + ${new_expires:-3600} * 1000))
  local tmp
  tmp=$(mktemp)
  if jq --arg a "$new_access" \
    --arg r "${new_refresh:-$refresh}" \
    --argjson e "$new_expires_ms" \
    '.anthropic.access = $a | .anthropic.refresh = $r | .anthropic.expires = $e' \
    "$AUTH_FILE" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$AUTH_FILE"
  else
    rm -f "$tmp"
  fi
  printf '%s' "$new_access"
}

main() {
  if [ ! -f "$AUTH_FILE" ] && [ ! -f "$CLAUDE_CREDS" ]; then
    emit noauth
    return 0
  fi

  local now data
  now=$(date +%s)

  # 429 backoff: serve the last good cache until Retry-After has passed.
  if [ -f "$BACKOFF_FILE" ]; then
    local backoff_until
    backoff_until=$(cat "$BACKOFF_FILE" 2>/dev/null || printf '0')
    if [ "$now" -lt "${backoff_until:-0}" ] 2>/dev/null; then
      data=$(cached_data)
      if [ -n "$data" ]; then emit stale "$data"; else emit ratelimited; fi
      return 0
    fi
    rm -f "$BACKOFF_FILE"
  fi

  # Fresh cache within TTL (unless --force).
  if [ "$FORCE" = 0 ] && [ -f "$USAGE_CACHE" ]; then
    local ts
    ts=$(jq -r '.cached_at // 0' "$USAGE_CACHE" 2>/dev/null || printf '0')
    if [ "${ts:-0}" -gt 0 ] 2>/dev/null && [ "$now" -lt "$((ts + TTL))" ] 2>/dev/null; then
      data=$(cached_data)
      if [ -n "$data" ]; then
        emit ok "$data"
        return 0
      fi
    fi
  fi

  local token
  token=$(get_token 2>/dev/null) || token=""
  if [ -z "$token" ]; then
    data=$(cached_data)
    if [ -n "$data" ]; then emit stale "$data"; else emit noauth; fi
    return 0
  fi

  local hdrs body http
  hdrs=$(mktemp)
  body=$(curl -s --max-time 8 -D "$hdrs" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "User-Agent: opencode/1.0" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -w '\n%{http_code}' \
    "$USAGE_URL" 2>/dev/null) || body=""
  http=$(printf '%s' "$body" | tail -n 1)
  body=$(printf '%s' "$body" | sed '$d')

  case "$http" in
  200)
    if printf '%s' "$body" | jq -e '.five_hour' >/dev/null 2>&1; then
      if jq -n --argjson data "$body" --argjson ts "$now" \
        '{cached_at: $ts, data: $data}' >"$USAGE_CACHE" 2>/dev/null; then
        rm -f "$BACKOFF_FILE"
      fi
      emit ok "$body"
    else
      data=$(cached_data)
      if [ -n "$data" ]; then emit stale "$data"; else emit invalid; fi
    fi
    ;;
  401 | 403)
    data=$(cached_data)
    if [ -n "$data" ]; then emit stale "$data"; else emit noauth; fi
    ;;
  429)
    local retry_after
    retry_after=$(grep -i '^retry-after:' "$hdrs" 2>/dev/null | awk '{print $2}' | tr -d '\r' | head -n 1)
    case "${retry_after:-}" in
    '' | *[!0-9]*) retry_after=60 ;;
    esac
    printf '%s' "$((now + retry_after))" >"$BACKOFF_FILE"
    data=$(cached_data)
    if [ -n "$data" ]; then emit stale "$data"; else emit ratelimited; fi
    ;;
  *)
    data=$(cached_data)
    if [ -n "$data" ]; then emit stale "$data"; else emit error; fi
    ;;
  esac
  rm -f "$hdrs"
  return 0
}

main
exit 0
