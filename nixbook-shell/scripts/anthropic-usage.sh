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
# degrade gracefully. Data is cached for 120s. A 429 serves the last good cache
# and waits before asking again: Retry-After when it says longer, else 5 min,
# doubling with each 429 in a row up to an hour (the server answers
# `retry-after: 0` while it keeps refusing, and asking again every 2 min kept
# it refusing). `--force` skips the 120s cache (the widget's click-to-refresh)
# but still honours that wait.
# Two answer shapes are read: the `five_hour`/`seven_day` windows, and the
# newer `limits` list (kind session / weekly_all / weekly_scoped), used when a
# window is missing. A weekly_scoped limit (one model, e.g. Fable) comes out as
# a SCOPED_LIMIT=<name>\t<percent used>\t<reset> line.

set -u

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
CLAUDE_CREDS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/anthropic-usage"
USAGE_CACHE="$CACHE_DIR/usage.json"
# "<unix time to wait until> <429s in a row>" (an older copy holds the time alone).
BACKOFF_FILE="$CACHE_DIR/backoff"
BACKOFF_MIN=300
BACKOFF_MAX=3600
TTL=120
TOKEN_URL="https://claude.ai/v1/oauth/token"
OAUTH_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"

mkdir -p "$CACHE_DIR"

# A usable answer: either shape (see the header).
USABLE='(.five_hour | type == "object") or ((.limits // []) | type == "array" and length > 0)'

# Reads the backoff file into $backoff_until and $backoff_count (whole numbers).
read_backoff() {
  backoff_until=0
  backoff_count=0
  [ -f "$BACKOFF_FILE" ] || return 0
  read -r backoff_until backoff_count <"$BACKOFF_FILE" 2>/dev/null || true
  case "${backoff_until:-}" in '' | *[!0-9]*) backoff_until=0 ;; esac
  case "${backoff_count:-}" in '' | *[!0-9]*) backoff_count=0 ;; esac
}

emit() {
  local status="${1:-error}"
  local data="${2:-}"
  local backoff_until backoff_count
  read_backoff
  echo "STATUS=$status"
  echo "UPDATED_AT=$(jq -r '.cached_at // 0' "$USAGE_CACHE" 2>/dev/null || printf '0')"
  # When the next fetch will be tried (0: whenever asked).
  if [ "$backoff_until" -gt "$(date +%s)" ]; then
    echo "RETRY_AT=$backoff_until"
  else
    echo "RETRY_AT=0"
  fi
  local lines=""
  # One jq for every line (the widget runs this once per bar). `//` keeps a 0
  # (only null and false fall through).
  [ -n "$data" ] && lines=$(printf '%s' "$data" | jq -r "select($USABLE)"' |
    ((.limits // []) | if type == "array" then . else [] end) as $l |
    ($l | map(select(.kind == "session")) | first) as $s |
    ($l | map(select(.kind == "weekly_all")) | first) as $w |
    def name: (.scope.model.display_name
      // (.scope.surface | if type == "object" then .display_name elif type == "string" then . else null end)
      // "Scoped") | tostring | gsub("[\t\n]"; " ");
    "PLAN_TYPE=\(.plan_type // "")",
    "FIVE_HOUR_UTIL=\(.five_hour.utilization // $s.percent // -1)",
    "FIVE_HOUR_RESET=\(.five_hour.resets_at // $s.resets_at // "")",
    "SEVEN_DAY_UTIL=\(.seven_day.utilization // $w.percent // -1)",
    "SEVEN_DAY_RESET=\(.seven_day.resets_at // $w.resets_at // "")",
    ($l[] | select(.kind == "weekly_scoped" and (.percent | type == "number")) |
      "SCOPED_LIMIT=\(name)\t\(.percent)\t\(.resets_at // "")")' 2>/dev/null)
  if [ -n "$lines" ]; then
    printf '%s\n' "$lines"
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
  # The token goes on stdin (`-d @-`), not the command line other users can
  # read in ps.
  resp=$(printf 'grant_type=refresh_token&refresh_token=%s&client_id=%s' "$refresh" "$OAUTH_CLIENT_ID" |
    curl -s --max-time 10 -X POST "$TOKEN_URL" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d @- 2>/dev/null) || resp=""
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

  # A whole number of seconds, or the default: the answer's text never
  # reaches the arithmetic below (bash evaluates a name or `a[$(…)]` there).
  case "$new_expires" in '' | *[!0-9]*) new_expires=3600 ;; esac
  local new_expires_ms=$((now_ms + new_expires * 1000))
  local tmp
  tmp=$(mktemp "$AUTH_FILE.XXXXXX")
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

  # 429 backoff: serve the last good cache until the wait has passed. The file
  # stays once it has (its count makes the next wait longer); only a good
  # answer removes it.
  local backoff_until backoff_count
  read_backoff
  if [ "$now" -lt "$backoff_until" ]; then
    data=$(cached_data)
    if [ -n "$data" ]; then emit stale "$data"; else emit ratelimited; fi
    return 0
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
  hdrs=$(mktemp "$CACHE_DIR/headers.XXXXXX")
  body=$(printf 'Authorization: Bearer %s\n' "$token" | curl -s --max-time 8 -D "$hdrs" \
    -H @- \
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
    if printf '%s' "$body" | jq -e "$USABLE" >/dev/null 2>&1; then
      # Renamed into place: another instance never reads a half-written cache.
      if jq -n --argjson data "$body" --argjson ts "$now" \
        '{cached_at: $ts, data: $data}' >"$USAGE_CACHE.tmp.$$" 2>/dev/null &&
        mv -f "$USAGE_CACHE.tmp.$$" "$USAGE_CACHE"; then
        rm -f "$BACKOFF_FILE"
      else
        rm -f "$USAGE_CACHE.tmp.$$"
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
    '' | *[!0-9]*) retry_after=0 ;;
    esac
    # 5 min, 10, 20, 40, then an hour; Retry-After when it asks for longer.
    local count=$((backoff_count + 1)) delay=$BACKOFF_MIN i
    for ((i = 1; i < count && delay < BACKOFF_MAX; i++)); do delay=$((delay * 2)); done
    [ "$delay" -gt "$BACKOFF_MAX" ] && delay=$BACKOFF_MAX
    [ "$retry_after" -gt "$delay" ] && delay=$retry_after
    printf '%s %s\n' "$((now + delay))" "$count" >"$BACKOFF_FILE"
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

# One at a time: the widget runs one per bar (one per monitor), all at
# startup, and refresh tokens rotate, so two refreshing the same one would
# leave one of them with a revoked token. The ones waiting then find the
# fresh cache. Without flock (or after 20 s) it runs unlocked.
exec 9>"$CACHE_DIR/lock"
flock -w 20 9 2>/dev/null || true
main
exit 0
