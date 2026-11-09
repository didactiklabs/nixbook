#!/usr/bin/env bash
# nixbook-mesh (scripts/mesh.py) against a real ntfy server: alice (the
# server's admin, who creates the mesh and invites), bob (joins by hand: a
# token set on the server and the mesh code), carol and dave (invited) and an
# outsider (mallory: a valid token, not on the ACL). Joining, invites, the
# server's ACL, everyone / private messages, presence, resuming after a
# restart, removing someone, and what is refused.
#
# Needs: NIXBOOK_MESH_PYTHON (a python3 with cryptography: mesh.nix's
# pythonEnv) and `ntfy` on the PATH (tests/run.sh builds both).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../scripts/mesh.py"
py="${NIXBOOK_MESH_PYTHON:-python3}"
tmp="$(mktemp -d)"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$tmp"
}
trap cleanup EXIT

failures=0
pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /' >&2
  failures=$((failures + 1))
}
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi; }

# -- The server ------------------------------------------------------------------

port=$((20000 + RANDOM % 20000))
server="http://127.0.0.1:$port"
hash=$(printf 'pw\npw\n' | ntfy user hash 2>/dev/null | tail -1)
tok() { echo "tk_$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 29)"; }
declare -A token
for u in alice bob mallory; do token[$u]=$(tok); done
mkdir -p "$tmp/server"
cat >"$tmp/server/server.yml" <<EOF
listen-http: "127.0.0.1:$port"
base-url: "$server"
cache-file: "$tmp/server/cache.db"
auth-file: "$tmp/server/user.db"
auth-default-access: "deny-all"
auth-access:
  - "bob:mesh-*:rw"
EOF
NTFY_AUTH_USERS="alice:$hash:admin,bob:$hash:user,mallory:$hash:user" \
  NTFY_AUTH_TOKENS="alice:${token[alice]}:a,bob:${token[bob]}:b,mallory:${token[mallory]}:m" \
  ntfy serve --config "$tmp/server/server.yml" >"$tmp/server/log" 2>&1 &
pids+=($!)
for _ in $(seq 50); do
  curl -sf "$server/v1/health" >/dev/null && break
  sleep 0.2
done
curl -sf "$server/v1/health" >/dev/null || {
  cat "$tmp/server/log" >&2
  fail "ntfy starts"
  exit 1
}

# mesh USER ARGS... : the helper as USER, its own config and state, secrets in files.
mesh() {
  local u="$1"
  shift
  mkdir -p "$tmp/$u/config" "$tmp/$u/state"
  XDG_CONFIG_HOME="$tmp/$u/config" XDG_STATE_HOME="$tmp/$u/state" NIXBOOK_MESH_STORE=file \
    NIXBOOK_MESH_ME="$u" "$py" -P "$script" "$@"
}
field() { jq -r "$1" <<<"$2"; }

# -- Setting up ------------------------------------------------------------------

r=$(mesh alice token set <<<"not-a-token" || true)
expect "a malformed token is refused" false "$(field .ok "$r")"
for u in alice bob mallory; do mesh "$u" token set <<<"${token[$u]}" >/dev/null; done
r=$(mesh alice status)
expect "the token is kept (in a file, no keyring here)" "file" "$(field .tokenSource "$r")"
mode=$(stat -c %a "$tmp/alice/config/nixbook-shell/mesh/token")
expect "the token file is private" 600 "$mode"

r=$(mesh alice mesh create)
code=$(field .code "$r")
if [[ $code =~ ^[A-Z2-7-]+$ ]]; then pass "creating a mesh gives a code"; else fail "creating a mesh gives a code" "$r"; fi
r=$(mesh alice mesh code)
expect "the code can be shown again" "$code" "$(field .code "$r")"

typo="${code:0:3}$([ "${code:3:1}" = A ] && echo B || echo A)${code:4}"
r=$(mesh bob mesh join <<<"$typo" || true)
expect "a mistyped code is refused" false "$(field .ok "$r")"
# Lower case, spaces instead of dashes: still the code.
r=$(mesh bob mesh join <<<"$(tr 'A-Z-' 'a-z ' <<<"$code")")
expect "a member joins with the code (any case, any separators)" true "$(field .ok "$r")"
mesh mallory mesh join <<<"$code" >/dev/null

r=$(mesh alice test "$server")
expect "test: the token is alice's" alice "$(field .user "$r")"
expect "test: alice is the admin" admin "$(field .role "$r")"
expect "test: the mesh is reachable" true "$(field .joined "$r")"

# -- Invites ---------------------------------------------------------------------

r=$(mesh bob invite "$server" carol || true)
expect "only the admin can invite" false "$(field .ok "$r")"
r=$(mesh alice invite "$server" "Not A Name" || true)
expect "an invalid name is refused" false "$(field .ok "$r")"
r=$(mesh alice invite "$server" carol)
first=$(field .code "$r")
expect "the admin invites carol" true "$(field .ok "$r")"
r=$(mesh alice invite "$server" carol)
invite=$(field .code "$r")
expect "inviting again gives a new code" true "$(field .again "$r")"
r=$(mesh carol accept <<<"$first" || true)
expect "the replaced code no longer works" false "$(field .ok "$r")"
r=$(mesh carol accept <<<"${invite:0:40}" || true)
expect "a cut code is refused" false "$(field .ok "$r")"
r=$(mesh carol accept <<<"$invite")
expect "carol joins with her invite" true "$(field .ok "$r")"
expect "the invite sets the server" "$server" "$(field .server "$r")"
r=$(mesh carol test "$server")
expect "carol's own token works, in the mesh" "carol true" "$(field .user "$r") $(field .joined "$r")"
r=$(mesh dave accept <<<"$invite" || true)
expect "an invite works once" false "$(field .ok "$r")"
mesh dave accept <<<"$(field .code "$(mesh alice invite "$server" dave)")" >/dev/null
r=$(mesh alice members "$server")
expect "the members, as the admin sees them" "alice bob carol dave" "$(jq -r '[.members[].name] | sort | join(" ")' <<<"$r")"
r=$(mesh bob members "$server" || true)
expect "only the admin lists members" false "$(field .ok "$r")"
r=$(mesh mallory test "$server" || true)
expect "test: a token without the ACL is refused" false "$(field .ok "$r")"
if grep -q "403" <<<"$(field .error "$r")"; then pass "test: says it's the ACL (403)"; else fail "test: says it's the ACL (403)" "$r"; fi

# -- Talking ---------------------------------------------------------------------

listen() {
  mesh "$1" listen "$server" >>"$tmp/$1.events" 2>>"$tmp/$1.err" &
  pids+=($!)
}
listen bob
listen carol
for _ in $(seq 50); do
  grep -q '"connected": true' "$tmp/carol.events" 2>/dev/null && grep -q '"connected": true' "$tmp/bob.events" 2>/dev/null && break
  sleep 0.2
done

r=$(mesh alice send "$server" message <<<'{"text": "hello everyone", "name": "Alice"}')
expect "alice sends to everyone" true "$(field .ok "$r")"
mesh alice send "$server" message <<<'{"text": "just for carol", "to": "carol", "name": "Alice"}' >/dev/null
mesh alice send "$server" presence <<<'{"state": "meeting", "name": "Alice"}' >/dev/null
r=$(mesh alice send "$server" message <<<'{"text": "   "}' || true)
expect "an empty message is refused" false "$(field .ok "$r")"
r=$(mesh mallory send "$server" message <<<'{"text": "let me in"}' || true)
expect "the outsider can't post" false "$(field .ok "$r")"

for _ in $(seq 50); do
  [ "$(grep -c '"kind": "' "$tmp/carol.events" 2>/dev/null)" -ge 3 ] && break
  sleep 0.2
done
sleep 0.5
bob=$(grep '"event": "message"' "$tmp/bob.events" || true)
carol=$(grep '"event": "message"' "$tmp/carol.events" || true)
if grep -q '"hello everyone"' <<<"$bob"; then pass "bob gets the message to everyone"; else fail "bob gets the message to everyone" "$bob"; fi
if grep -q 'just for carol' <<<"$bob"; then fail "bob doesn't get carol's private message" "$bob"; else pass "bob doesn't get carol's private message"; fi
if grep -q 'just for carol' <<<"$carol"; then pass "carol gets her private message"; else fail "carol gets her private message" "$carol"; fi
msg=$(grep '"hello everyone"' <<<"$bob" | head -1)
expect "the sender is alice" alice "$(field .from "$msg")"
expect "with her name" Alice "$(field .name "$msg")"
expect "not marked as bob's own" false "$(field .mine "$msg")"
pres=$(grep '"presence"' <<<"$bob" | head -1)
expect "bob sees alice's status" meeting "$(field .data.state "$pres")"

# On the server: ciphertext only.
raw=$(curl -s -H "Authorization: Bearer ${token[alice]}" "$server/$(
  cd "$tmp" && mesh alice status >/dev/null
  "$py" -P -c "
import base64,hashlib
k=base64.b64decode(open('$tmp/alice/config/nixbook-shell/mesh/key').read())
print('mesh-'+hashlib.sha256(b'nixbook-mesh topic\0'+k).hexdigest()[:24])"
)/json?poll=1&since=all")
if grep -q 'hello everyone\|just for carol\|meeting\|alice' <<<"$raw"; then
  fail "the server only sees ciphertext" "$raw"
else
  pass "the server only sees ciphertext"
fi

# Resuming: a restarted listener doesn't get the same messages again.
kill "${pids[-1]}" "${pids[-2]}" 2>/dev/null || true
sleep 0.3
: >"$tmp/bob.events"
listen bob
for _ in $(seq 50); do
  grep -q '"connected": true' "$tmp/bob.events" 2>/dev/null && break
  sleep 0.2
done
mesh carol send "$server" message <<<'{"text": "new after restart"}' >/dev/null
for _ in $(seq 50); do
  grep -q 'new after restart' "$tmp/bob.events" && break
  sleep 0.2
done
again=$(grep -c '"hello everyone"' "$tmp/bob.events" || true)
expect "after a restart, old messages don't come again" 0 "$again"
if grep -q 'new after restart' "$tmp/bob.events"; then pass "after a restart, new ones do"; else fail "after a restart, new ones do" "$(cat "$tmp/bob.events")"; fi

# A desktop with another mesh's key hears nothing of this one.
mesh carol mesh create >/dev/null
r=$(mesh carol mesh code)
if [ "$(field .code "$r")" != "$code" ]; then pass "a new mesh has a new code"; else fail "a new mesh has a new code"; fi

r=$(mesh alice remove "$server" alice || true)
expect "the admin can't remove themself" false "$(field .ok "$r")"
r=$(mesh alice remove "$server" bob || true)
if grep -q "configuration" <<<"$(field .error "$r")"; then pass "someone set on the server isn't removed by invites, and it says so"; else fail "someone set on the server isn't removed by invites, and it says so" "$r"; fi
r=$(mesh alice remove "$server" dave)
expect "the admin removes dave" true "$(field .ok "$r")"
r=$(mesh dave send "$server" message <<<'{"text": "still here?"}' || true)
expect "dave is cut off at once" false "$(field .ok "$r")"

mesh alice mesh leave >/dev/null
r=$(mesh alice send "$server" message <<<'{"text": "x"}' || true)
expect "after leaving, nothing can be sent" false "$(field .ok "$r")"

if [ "$failures" -ne 0 ]; then
  echo "$failures failed" >&2
  exit 1
fi
echo "all passed"
