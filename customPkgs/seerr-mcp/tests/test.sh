#!/usr/bin/env bash
# seerr-mcp against a fake Seerr (tests/fake-seerr.py): every tool, where the
# API key comes from, requests going out as the chosen user (X-API-User),
# errors, and the credentials helper. Never a real server or a real keyring:
# secret-tool is a stub, HOME and XDG_* are scratch directories.
#
#   bash customPkgs/seerr-mcp/tests/test.sh            the source
#   SEERR_MCP=/nix/store/…/bin/seerr-mcp bash …        an installed copy
# Needs python3, jq and openssl (to encrypt the fake Chrome cookies).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
fake_pid=""
cleanup() {
  [ -n "$fake_pid" ] && kill "$fake_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

if [ -n "${SEERR_MCP:-}" ]; then
  smcp=("$SEERR_MCP")
else
  smcp=(python3 "$here/../server.py")
fi

fails=0
pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  [ -n "${2:-}" ] && printf '       %s\n' "$2" | head -c 2000 >&2 && echo >&2
  fails=$((fails + 1))
}
expect_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $3 / got: $2"; fi; }
expect_match() { if printf '%s' "$3" | grep -Eq -- "$2"; then pass "$1"; else fail "$1" "no match for /$2/ in: $3"; fi; }
expect_no() { if printf '%s' "$3" | grep -Fq -- "$2"; then fail "$1" "unexpected '$2' in: $3"; else pass "$1"; fi; }

# -- the environment: scratch home, a stub keyring ------------------------
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_RUNTIME_DIR="$tmp/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$tmp/bin"
unset DBUS_SESSION_BUS_ADDRESS SEERR_API_KEY SEERR_API_KEY_FILE SEERR_USER SEERR_URL
export STUB_DIR="$tmp/stub"
mkdir -p "$STUB_DIR"
bash_path=$(command -v bash)
{
  echo "#!$bash_path"
  cat
} >"$tmp/bin/secret-tool" <<'EOF'
echo "$*" >>"$STUB_DIR/secret-tool.log"
# One secret, with the attributes it was stored with (a lookup's must all be
# among them).
case "$1" in
  lookup)
    # A Chromium-family browser's cookie password (application chrome…).
    if [ "${2:-}" = application ]; then
      [ -f "$STUB_DIR/app-$3" ] && cat "$STUB_DIR/app-$3" && exit 0
      exit 1
    fi
    [ -f "$STUB_DIR/keyring" ] || exit 1
    shift
    while [ $# -ge 2 ]; do
      grep -qF " $1 $2 " "$STUB_DIR/keyring.attrs" 2>/dev/null || exit 1
      shift 2
    done
    cat "$STUB_DIR/keyring" ;;
  store)
    shift
    case "$1" in --label=*) shift ;; esac
    echo " $* " >"$STUB_DIR/keyring.attrs"
    cat >"$STUB_DIR/keyring" ;;
  clear) rm -f "$STUB_DIR/keyring" "$STUB_DIR/keyring.attrs" ;;
esac
EOF
chmod +x "$tmp/bin/secret-tool"
export PATH="$tmp/bin:$PATH"

log="$tmp/requests.log"
: >"$log"
python3 "$here/fake-seerr.py" "$tmp/port" "$log" &
fake_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/port" ] && break
  sleep 0.1
done
url="http://127.0.0.1:$(cat "$tmp/port")"
KEY="test-key-123"

rpc() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$1" | "${smcp[@]}" | tail -n 1
}
call() {
  rpc "$(jq -cn --arg n "$1" --argjson a "${2:-{\}}" '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$n,arguments:$a}}')"
}
text_of() { jq -r '.result.content[0].text'; }
err_of() { jq -r '.result.isError'; }
last_req() { grep -F "\"path\": \"/api/v1$1\"" "$log" | tail -n 1; }

export SEERR_URL="$url" SEERR_API_KEY="$KEY"

# -- the protocol -----------------------------------------------------------
init=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' | "${smcp[@]}")
expect_eq "initialize: echoes a known protocol version" "$(jq -r .result.protocolVersion <<<"$init")" "2025-03-26"
expect_eq "initialize: server name" "$(jq -r .result.serverInfo.name <<<"$init")" "seerr-mcp"
list=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
expect_eq "tools/list: the tools" "$(jq -c '[.result.tools[].name]' <<<"$list")" \
  '["search","details","request","requests","cancel_request","approve_request","decline_request","trending","upcoming","whoami"]'
expect_eq "tools/list: reading tools are read-only" "$(jq -c '[.result.tools[] | select(.annotations.readOnlyHint) | .name]' <<<"$list")" \
  '["search","details","requests","trending","upcoming","whoami"]'
expect_eq "tools/list: cancelling and declining are destructive" "$(jq -c '[.result.tools[] | select(.annotations.destructiveHint) | .name]' <<<"$list")" \
  '["cancel_request","decline_request"]'

# -- the key ----------------------------------------------------------------
r=$(SEERR_URL="" call search '{"query":"dune"}')
expect_match "not set up: says where" "Settings > Desktop agents" "$(text_of <<<"$r")"
r=$(SEERR_API_KEY="wrong-key-999" call search '{"query":"dune"}')
expect_match "a wrong key: refused (401)" "refused the API key \(HTTP 401\)" "$(text_of <<<"$r")"
expect_no "a wrong key: never shown" "wrong-key-999" "$r"
printf '%s' "$KEY" >"$STUB_DIR/keyring"
echo " service seerr-mcp " >"$STUB_DIR/keyring.attrs"
r=$(SEERR_API_KEY="" call search '{"query":"dune"}')
expect_match "the key from the keyring (service seerr-mcp)" "438631" "$(text_of <<<"$r")"
expect_match "keyring looked up by its attributes" "lookup service seerr-mcp" "$(cat "$STUB_DIR/secret-tool.log")"
mkdir -p "$HOME/.config/seerr"
printf '%s\n' "$KEY" >"$HOME/.config/seerr/key"
# shellcheck disable=SC2088 # the literal "~/", expanded by seerr-mcp itself
r=$(SEERR_API_KEY="" SEERR_API_KEY_FILE="~/.config/seerr/key" call search '{"query":"dune"}')
expect_match "the key from a file (~/ expanded)" "438631" "$(text_of <<<"$r")"

# -- search, details, discover ---------------------------------------------
r=$(call search '{"query":"dune part two"}' | text_of)
expect_eq "search: a space sent as %20 (Seerr refuses +)" "query=dune%20part%20two&page=1" "$(last_req /search | jq -r .raw_query)"
expect_eq "search: films with their status, no people" '[{"id":693134,"type":"movie","title":"Dune: Part Two","year":2024,"status":"not requested"}]' \
  "$(jq -c '[.results[] | del(.overview)]' <<<"$r")"
r=$(call search '{"query":"dune","type":"movie"}' | text_of)
expect_eq "search: available ones said so" "Dune available" "$(jq -r '.results[] | select(.id == 438631) | .title + " " + .status' <<<"$r")"
r=$(call details '{"type":"series","id":105248}' | text_of)
expect_eq "details: a series' seasons (not the specials), each with its status" \
  '[{"season":1,"episodes":10,"status":"available"},{"season":2,"episodes":10,"status":"not requested"},{"season":3,"episodes":8,"status":"not requested"}]' \
  "$(jq -c .seasons <<<"$r")"
expect_eq "details: a film's runtime and genres" "155 min Science Fiction" "$(call details '{"type":"movie","id":438631}' | text_of | jq -r '.runtime + " " + .genres[0]')"
expect_match "details: an unknown id said" "has no /movie/1 \(HTTP 404\)" "$(call details '{"type":"movie","id":1}' | text_of)"
expect_match "details: a bad type said" "type: movie or series" "$(call details '{"type":"book","id":1}' | text_of)"
expect_eq "trending: films and series" "movie movie series" "$(call trending | text_of | jq -r '[.results[].type] | join(" ")')"
expect_eq "upcoming: series" "series" "$(call upcoming '{"type":"series"}' | text_of | jq -r '[.results[].type] | unique | join(" ")')"

# -- requests, as the user ---------------------------------------------------
export SEERR_USER=khoa
r=$(call request '{"type":"movie","id":693134}' | text_of)
p=$(last_req /request)
expect_eq "request: a film, as the chosen user (X-API-User)" '{"mediaType":"movie","mediaId":693134} 2' "$(jq -c .body <<<"$p") $(jq -r .as <<<"$p")"
expect_eq "request: says what and how far" "true Dune: Part Two waiting for approval Khoa" \
  "$(jq -r '[.requested, .title, .status, .requested_by] | map(tostring) | join(" ")' <<<"$r")"
r=$(call request '{"type":"movie","id":693134}' | text_of)
expect_match "request: already requested, not again" "already requested, waiting for approval" "$(jq -r .why <<<"$r")"
expect_match "request: already available, not again" "already available" "$(call request '{"type":"movie","id":438631}' | text_of | jq -r .why)"
r=$(call request '{"type":"series","id":105248}' | text_of)
expect_eq "request: a series, the missing seasons only (not the specials, not one available)" "[2,3]" "$(last_req /request | jq -c .body.seasons)"
r=$(call request '{"type":"series","id":105248,"seasons":[3]}' | text_of)
expect_match "request: seasons already requested, not again" "already available or requested" "$(jq -r .why <<<"$r")"
expect_match "request: a season that isn't there" "has no season 9 \(it has 3\)" "$(call request '{"type":"series","id":105248,"seasons":[9]}' | text_of)"
r=$(call requests | text_of)
expect_eq "requests: the user's own, newest first, with their titles" "Cyberpunk: Edgerunners Dune: Part Two" "$(jq -r '[.requests[].title] | join(" ")' <<<"$r")"
expect_eq "requests: asked for that user's" "2" "$(last_req /request | jq -r .query.requestedBy)"
expect_eq "requests: a series' seasons" "[2,3]" "$(jq -c '.requests[0].seasons' <<<"$r")"
r=$(call approve_request '{"id":100}')
expect_match "approve: not allowed for a plain user, said" "Seerr said no: You do not have permission" "$(text_of <<<"$r")"
r=$(SEERR_USER="" call approve_request '{"id":100}' | text_of)
expect_eq "approve: as the key's admin" "100 approved" "$(jq -r '[.approved, .status] | map(tostring) | join(" ")' <<<"$r")"
r=$(SEERR_USER="" call decline_request '{"id":101}' | text_of)
expect_eq "decline" "declined" "$(jq -r .status <<<"$r")"
expect_eq "cancel: the user's own" '{"cancelled":100}' "$(call cancel_request '{"id":100}' | text_of)"
r=$(SEERR_USER=nobody call requests)
expect_match "an unknown user: said, with where to set it" "no user 'nobody'" "$(text_of <<<"$r")"
r=$(call whoami | text_of)
expect_eq "whoami: who requests go out as, and the quota left" "Khoa 2 10" \
  "$(jq -r '[.as, .user_id, .quota.movie.limit] | map(tostring) | join(" ")' <<<"$r")"
expect_no "never the key in a result" "$KEY" "$(call whoami)$(call requests)"
expect_no "never the key in what is logged by the fake" "$KEY" "$(cat "$log")"
unset SEERR_USER

# -- the credentials helper ---------------------------------------------------
rm -f "$STUB_DIR/keyring"
r=$(SEERR_API_KEY="" "${smcp[@]}" credentials status)
expect_eq "credentials status: no key" "$(jq -c '{has_key, key_source}' <<<"$r")" '{"has_key":false,"key_source":null}'
r=$(printf '%s\n' "$KEY" | SEERR_API_KEY="" "${smcp[@]}" credentials test "$url/" khoa)
expect_eq "credentials test: checked as that user, nothing saved" "Khoa 2 $([ -f "$STUB_DIR/keyring" ] && echo saved || echo none)" \
  "$(jq -r '.user + " " + (.user_id|tostring)' <<<"$r") none"
r=$(printf '%s\n' "bad-key-777" | SEERR_API_KEY="" "${smcp[@]}" credentials save "$url" || true)
expect_match "credentials save: a bad key refused, not saved" "refused the API key" "$(jq -r .error <<<"$r")$([ -f "$STUB_DIR/keyring" ] && echo saved)"
expect_no "credentials save: the bad key not printed" "bad-key-777" "$r"
r=$(printf '%s\n' "$KEY" | SEERR_API_KEY="" "${smcp[@]}" credentials save "$url")
expect_eq "credentials save: in the keyring" "$(jq -r '.has_key, .key_source' <<<"$r" | paste -sd' ') $(cat "$STUB_DIR/keyring")" "true keyring $KEY"
expect_no "credentials save: the key not printed" "$KEY" "$r"
r=$(SEERR_API_KEY="" "${smcp[@]}" users "$url" </dev/null)
expect_eq "users: to pick who requests go out as" '[{"id":1,"name":"Admin"},{"id":2,"name":"Khoa"}]' "$(jq -c '[.users[] | {id, name}]' <<<"$r")"
r=$(SEERR_API_KEY="" "${smcp[@]}" configured)
expect_eq "configured: server and key" "$(jq -c . <<<"$r")" '{"configured":true}'
r=$(SEERR_API_KEY="" "${smcp[@]}" credentials forget)
expect_eq "credentials forget" "$(jq -r .has_key <<<"$r") $([ -f "$STUB_DIR/keyring" ] && echo kept || echo gone)" "false gone"
r=$(SEERR_API_KEY="" "${smcp[@]}" configured || true)
expect_eq "configured: no key" "$(jq -r .configured <<<"$r")" "false"

# -- your own login: Seerr's session from the browser's cookies -------------
# A Firefox-family cookie file: Seerr's cookie for another host (never
# taken), an ended session used last, the live one, and another cookie.
host=127.0.0.1
db="$tmp/profile/cookies.sqlite"
mkdir -p "$tmp/profile"
python3 - "$db" "$host" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE moz_cookies (id INTEGER PRIMARY KEY, name TEXT, value TEXT, host TEXT, path TEXT, lastAccessed INTEGER)")
rows = [("connect.sid", "s%3Aother-host.sig", "seerr.elsewhere.org", 300),
        ("connect.sid", "s%3Aended-session.sig", sys.argv[2], 200),
        ("connect.sid", "s%3Akhoa-session.sig", sys.argv[2], 100),
        ("theme", "dark", sys.argv[2], 400)]
con.executemany("INSERT INTO moz_cookies (name, value, host, path, lastAccessed) VALUES (?, ?, ?, '/', ?)", rows)
con.commit()
PY
rm -f "$STUB_DIR/keyring" "$STUB_DIR/keyring.attrs"
export SEERR_API_KEY=""
r=$(SEERR_COOKIE_DBS="$tmp/none.sqlite" "${smcp[@]}" login-from-browser "$url" || true)
expect_match "browser login: none there, says what to do" "no Seerr login for $host in your browser: open .* in Zen or Chrome, sign in" "$(jq -r .error <<<"$r")"
: >"$log"
r=$(SEERR_COOKIE_DBS="$db" "${smcp[@]}" login-from-browser "$url/")
expect_eq "browser login: the live session (an ended one skipped), as its user" "session Khoa 2" \
  "$(jq -r '[.kind, .user, .user_id] | map(tostring) | join(" ")' <<<"$r")"
expect_eq "browser login: kept in the keyring, marked a session" "s%3Akhoa-session.sig  service seerr-mcp kind session " \
  "$(cat "$STUB_DIR/keyring") $(cat "$STUB_DIR/keyring.attrs")"
expect_no "browser login: the cookie never printed" "khoa-session" "$r"
expect_no "browser login: another host's never used" "other-host" "$(cat "$log")"
r=$("${smcp[@]}" credentials status)
expect_eq "credentials status: signed in with your own login" '{"has_key":true,"key_source":"keyring","kind":"session","signed_in_as":"Khoa"}' \
  "$(jq -c '{has_key, key_source, kind, signed_in_as}' <<<"$r")"
: >"$log"
r=$(SEERR_USER=Admin call request '{"type":"movie","id":693134}' | text_of)
p=$(last_req /movie/693134)
expect_eq "your login: calls as you (the session; no key, no X-API-User even when one is set)" "true false null" \
  "$(jq -r '[.session, .key, .as] | map(tostring) | join(" ")' <<<"$p")"
expect_match "your login: the tools work as you" "already requested" "$(jq -r '.why' <<<"$r")"
expect_eq "your login: whoami" "Khoa" "$(call whoami | text_of | jq -r .as)"
r=$(call approve_request '{"id":101}')
expect_match "your login: what you may not do, said as Seerr says it" "Seerr said no: You do not have permission" "$(text_of <<<"$r")"
expect_match "your login: the server's users are an admin's (Settings says so)" "Seerr said no" "$("${smcp[@]}" users "$url" </dev/null | jq -r .error)"
r=$(SEERR_SESSION="s%3Aended-session.sig" call requests)
expect_match "an ended login: says to sign in again" "doesn't take your login any more \(HTTP 403\): sign in to Seerr in your browser again" "$(text_of <<<"$r")"
expect_no "an ended login: the cookie never shown" "ended-session" "$r"
r=$("${smcp[@]}" credentials forget)
expect_eq "sign out: forgotten here (the browser stays signed in)" "false gone" \
  "$(jq -r .has_key <<<"$r") $([ -f "$HOME/.local/state/seerr-mcp/login.json" ] && echo kept || echo gone)"
expect_eq "sign out: never logged out on the server (that would sign the browser out)" "0" "$(grep -c '/auth/logout' "$log" || true)"
unset SEERR_API_KEY

# -- your own login from Chrome (and the Chromium family) -------------------
# Chrome encrypts its cookies: v11 with a password from the keyring
# (application chrome), v10 with Chromium's fixed "peanuts"; newer Chromes
# put the SHA-256 of the host before the value. A fake Cookies file of each.
chrome_db() { # FILE ROWS-JSON: [[value, version, password, host, used_s, hash_prefix]]
  python3 - "$@" <<'PY'
import hashlib, json, sqlite3, subprocess, sys, time
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
con.execute("INSERT INTO meta VALUES ('version', '24')")
con.execute("CREATE TABLE cookies (creation_utc INTEGER, host_key TEXT, name TEXT, value TEXT, "
            "encrypted_value BLOB, path TEXT, last_access_utc INTEGER)")
for value, version, password, host, used, prefix in json.loads(sys.argv[2]):
    key = hashlib.pbkdf2_hmac("sha1", password.encode(), b"saltysalt", 1, 16).hex()
    plain = (hashlib.sha256(host.encode()).digest() if prefix else b"") + value.encode()
    ct = subprocess.run(["openssl", "enc", "-aes-128-cbc", "-K", key, "-iv", "20" * 16], input=plain,
                        capture_output=True, check=True).stdout
    used_us = int((time.time() - used) * 1_000_000) + 11644473600 * 1_000_000
    con.execute("INSERT INTO cookies VALUES (0, ?, 'connect.sid', '', ?, '/', ?)", (host, version.encode() + ct, used_us))
con.commit()
PY
}
mkdir -p "$tmp/chrome/Default/Network" "$tmp/chromium/Default" "$tmp/fx2"
cdb="$tmp/chrome/Default/Network/Cookies"
chrome_db "$cdb" '[["s%3Aother-host.sig", "v11", "chrome-pw", "seerr.elsewhere.org", 10, true],
                   ["s%3Akhoa-session.sig", "v11", "chrome-pw", "127.0.0.1", 60, true]]'
printf chrome-pw >"$STUB_DIR/app-chrome"
: >"$log"
r=$(SEERR_COOKIE_DBS="$cdb" "${smcp[@]}" login-from-browser "$url")
expect_eq "Chrome: its encrypted cookie read (v11, the keyring's password, the host hash cut)" "session Khoa Chrome" \
  "$(jq -r '[.kind, .user, .browser] | map(tostring) | join(" ")' <<<"$r")"
expect_eq "Chrome: the session kept in the keyring" "s%3Akhoa-session.sig" "$(cat "$STUB_DIR/keyring")"
expect_no "Chrome: another host's never used" "other-host" "$(cat "$log")"
expect_no "Chrome: the cookie never printed" "khoa-session" "$r"
expect_eq "Chrome: its password asked for as Chrome's" "1" "$(grep -c '^lookup application chrome$' "$STUB_DIR/secret-tool.log" || true)"
rm -f "$STUB_DIR/app-chrome"
r=$(SEERR_COOKIE_DBS="$cdb" "${smcp[@]}" login-from-browser "$url" || true)
expect_match "Chrome: without its password (a wrong key), no login found" "no Seerr login for" "$(jq -r .error <<<"$r")"
xdb="$tmp/chromium/Default/Cookies"
chrome_db "$xdb" '[["s%3Akhoa-session.sig", "v10", "peanuts", ".127.0.0.1", 30, false]]'
r=$(SEERR_COOKIE_DBS="$xdb" "${smcp[@]}" login-from-browser "$url")
expect_eq "Chromium without a keyring (v10, an older file, a .host cookie)" "session Khoa" \
  "$(jq -r '[.kind, .user] | map(tostring) | join(" ")' <<<"$r")"
# The newest login first, across browsers: Firefox's ended one (used a
# moment ago) is tried first and skipped, Chrome's live one taken.
python3 - "$tmp/fx2/cookies.sqlite" <<'PY'
import sqlite3, sys, time
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE moz_cookies (id INTEGER PRIMARY KEY, name TEXT, value TEXT, host TEXT, path TEXT, lastAccessed INTEGER)")
con.execute("INSERT INTO moz_cookies (name, value, host, path, lastAccessed) VALUES ('connect.sid', 's%3Aended-session.sig', '127.0.0.1', '/', ?)",
            (int(time.time() * 1_000_000),))
con.commit()
PY
printf chrome-pw >"$STUB_DIR/app-chrome"
: >"$log"
r=$(SEERR_COOKIE_DBS="$tmp/fx2/cookies.sqlite:$cdb" "${smcp[@]}" login-from-browser "$url")
expect_eq "Firefox and Chrome: the newest login tried first, an ended one skipped" "Khoa Chrome" \
  "$(jq -r '[.user, .browser] | join(" ")' <<<"$r")"
"${smcp[@]}" credentials forget >/dev/null
rm -f "$STUB_DIR/app-chrome"

# -- a server that doesn't answer ---------------------------------------------
r=$(SEERR_API_KEY="$KEY" SEERR_TIMEOUT=1 SEERR_URL="http://127.0.0.1:9" call search '{"query":"x"}')
expect_match "a server that isn't there: said" "couldn't reach Seerr" "$(text_of <<<"$r")"

if [ "$fails" -ne 0 ]; then
  echo "seerr-mcp: $fails check(s) failed" >&2
  exit 1
fi
echo "seerr-mcp: all checks passed"
