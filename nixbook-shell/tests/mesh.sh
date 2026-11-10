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
attachment-cache-dir: "$tmp/server/attachments"
attachment-file-size-limit: "1M"
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
  XDG_CONFIG_HOME="$tmp/$u/config" XDG_STATE_HOME="$tmp/$u/state" XDG_DATA_HOME="$tmp/$u/data" HOME="$tmp/$u" \
    NIXBOOK_MESH_STORE=file NIXBOOK_MESH_ME="$u" "$py" -P "$script" "$@"
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

declare -A listener
listen() {
  mesh "$1" listen "$server" >>"$tmp/$1.events" 2>>"$tmp/$1.err" &
  pids+=($!)
  listener[$1]=$!
}
# mesh_as DIR ME ARGS... : with DIR's files and keys, claiming to be ME.
mesh_as() {
  local d="$1" who="$2"
  shift 2
  XDG_CONFIG_HOME="$tmp/$d/config" XDG_STATE_HOME="$tmp/$d/state" XDG_DATA_HOME="$tmp/$d/data" HOME="$tmp/$d" \
    NIXBOOK_MESH_STORE=file NIXBOOK_MESH_ME="$who" "$py" -P "$script" "$@"
}
listen bob
listen carol
for _ in $(seq 50); do
  grep -q '"connected": true' "$tmp/carol.events" 2>/dev/null && grep -q '"connected": true' "$tmp/bob.events" 2>/dev/null && break
  sleep 0.2
done

r=$(mesh alice send "$server" message <<<'{"text": "privately, before knowing carol", "to": "carol"}' || true)
if grep -q "hasn't been seen" <<<"$(field .error "$r")"; then pass "no private message before the recipient's key is known"; else fail "no private message before the recipient's key is known" "$r"; fi
# Alice's desktop listens (and so learns keys); carol comes online.
listen alice
for _ in $(seq 50); do
  grep -q '"connected": true' "$tmp/alice.events" 2>/dev/null && break
  sleep 0.2
done
mesh carol send "$server" presence <<<'{"state": "free", "name": "Carol"}' >/dev/null
for _ in $(seq 50); do
  [ "$(mesh alice keys | jq -r '.members.carol.fingerprint // empty')" != "" ] && break
  sleep 0.2
done

r=$(mesh alice send "$server" message <<<'{"text": "hello everyone", "name": "Alice"}')
expect "alice sends to everyone" true "$(field .ok "$r")"
r=$(mesh alice send "$server" message <<<'{"text": "just for carol", "to": "carol", "name": "Alice"}')
expect "alice writes privately to carol, once her key is known" true "$(field .ok "$r")"
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
expect "carol's private message is marked private" true "$(field .private "$(grep 'just for carol' <<<"$carol" | head -1)")"
for _ in $(seq 50); do
  grep -q 'just for carol' "$tmp/alice.events" && break
  sleep 0.2
done
if grep -q 'just for carol' "$tmp/alice.events"; then pass "alice reads her own copy"; else fail "alice reads her own copy" "$(cat "$tmp/alice.events")"; fi

# Bob holds the mesh key: he opens the mesh's layer, and finds sealed
# envelopes that say nothing (no names, no text) and that he can't open.
bob_try=$(
  "$py" -P - "$script" "$tmp/bob" "$server" "${token[bob]}" <<'PY'
import importlib.machinery, json, os, sys, urllib.request
os.environ.update(XDG_CONFIG_HOME=f"{sys.argv[2]}/config", XDG_STATE_HOME=f"{sys.argv[2]}/state", NIXBOOK_MESH_STORE="file")
mesh = importlib.machinery.SourceFileLoader("mesh", sys.argv[1]).load_module()
key, _ = mesh.load_key()
topic = mesh.topic_of(key)
req = urllib.request.Request(f"{sys.argv[3]}/{topic}/json?poll=1&since=all", headers={"Authorization": f"Bearer {sys.argv[4]}"})
sk, pk = mesh.load_identity()
sealed, telling, opened = 0, 0, 0
for line in urllib.request.urlopen(req).read().decode().splitlines():
    p = mesh.unseal(key, topic, json.loads(line).get("message") or "")
    if not p or p.get("kind") != "sealed":
        continue
    sealed += 1
    outer = json.dumps(p)
    telling += any(w in outer for w in ("alice", "carol", "just for carol", '"to"', '"from"', '"mid"', '"time"'))
    opened += mesh.open_private(sk, pk, p, topic)[0] is not None
print(json.dumps({"sealed": sealed, "telling": telling, "opened": opened}))
PY
)
if [ "$(field .sealed "$bob_try")" -ge 1 ]; then pass "private messages travel sealed"; else fail "private messages travel sealed" "$bob_try"; fi
expect "a sealed envelope shows no names, text, ids or times" 0 "$(field .telling "$bob_try")"
expect "bob, with the mesh key, opens none of them" 0 "$(field .opened "$bob_try")"

# A read receipt is sealed too: alice gets it, bob sees nothing.
r=$(mesh carol send "$server" read <<<'{"to": "alice", "upTo": 1234}')
expect "carol sends alice a read receipt" true "$(field .ok "$r")"
for _ in $(seq 50); do
  grep -q '"kind": "read"' "$tmp/alice.events" && break
  sleep 0.2
done
receipt=$(grep '"kind": "read"' "$tmp/alice.events" | head -1)
expect "alice gets it, from carol" "carol 1234" "$(field .from "$receipt") $(field .data.upTo "$receipt")"
if grep -q '"kind": "read"' "$tmp/bob.events"; then fail "bob doesn't see it" "$(cat "$tmp/bob.events")"; else pass "bob doesn't see it"; fi

msg=$(grep '"hello everyone"' <<<"$bob" | head -1)
expect "the sender is alice" alice "$(field .from "$msg")"
expect "with her name" Alice "$(field .name "$msg")"
expect "not marked as bob's own" false "$(field .mine "$msg")"
pres=$(grep '"presence"' <<<"$bob" | grep '"from": "alice"' | head -1)
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

# -- Files -----------------------------------------------------------------------

# A GIF (100x50, the header is all sniff reads) and a document.
printf 'GIF89a\x64\x00\x32\x00' >"$tmp/cat.gif"
head -c 300000 /dev/urandom >>"$tmp/cat.gif"
printf 'a report\n' >"$tmp/report.txt"
r=$(mesh alice limits "$server")
expect "the server's file limit, less the tag" $((1024 * 1024 - 16)) "$(field .maxFile "$r")"
r=$(mesh alice sendfile "$server" <<<"{\"path\": \"$tmp/cat.gif\", \"to\": \"carol\", \"text\": \"look\", \"mid\": \"filemid1\", \"name\": \"Alice\"}" | tail -1)
expect "alice sends carol a GIF privately" true "$(field .ok "$r")"
expect "it is seen as an animated image, its size read" "image/gif true 100x50" "$(field .file.mime "$r") $(field .file.animated "$r") $(field .file.w "$r")x$(field .file.h "$r")"
if cmp -s "$tmp/cat.gif" "$(field .file.path "$r")"; then pass "the sender keeps a copy"; else fail "the sender keeps a copy" "$r"; fi
progress=$(mesh alice sendfile "$server" <<<"{\"path\": \"$tmp/report.txt\", \"mid\": \"filemid2\"}" | sed -n 1p)
expect "sending reports progress" progress "$(field .event "$progress")"
r=$(NIXBOOK_MESH_COPY_MAX=1000 mesh alice sendfile "$server" <<<"{\"path\": \"$tmp/cat.gif\", \"mid\": \"filemid3\"}" | tail -1)
expect "a big file isn't copied: the sender's message shows the original" "$tmp/cat.gif" "$(field .file.path "$r")"
head -c 1100000 /dev/urandom >"$tmp/big.bin"
r=$(mesh alice sendfile "$server" <<<"{\"path\": \"$tmp/big.bin\"}" | tail -1 || true)
if grep -q "up to 1.0 MB" <<<"$(field .error "$r")"; then pass "a file over the server's limit is refused, before uploading"; else fail "a file over the server's limit is refused, before uploading" "$r"; fi
r=$(mesh alice sendfile "$server" <<<'{"path": "/nonexistent/x.png"}' || true)
expect "a missing file is refused" false "$(field .ok "$r")"
for _ in $(seq 50); do
  grep -q '"filemid2"' "$tmp/bob.events" && grep -q '"filemid1"' "$tmp/carol.events" && break
  sleep 0.2
done
gif=$(grep '"filemid1"' "$tmp/carol.events" | head -1)
expect "carol's message carries the file and the text" "look cat.gif" "$(field .data.text "$gif") $(field .data.file.name "$gif")"
if grep -q '"filemid1"' "$tmp/bob.events"; then fail "bob doesn't get the private file's message" "$(grep filemid1 "$tmp/bob.events")"; else pass "bob doesn't get the private file's message"; fi
r=$(mesh carol fetch "$server" <<<"{\"file\": $(jq -c .data.file <<<"$gif")}" | tail -1)
expect "carol downloads and decrypts it" true "$(field .ok "$r")"
if cmp -s "$tmp/cat.gif" "$(field .file.path "$r")"; then pass "the file is the one sent"; else fail "the file is the one sent" "$r"; fi
expect "kept privately" 600 "$(stat -c %a "$(field .file.path "$r")")"
again=$(mesh carol fetch "$server" <<<"{\"file\": $(jq -c .data.file <<<"$gif")}" | tail -1)
expect "fetching again uses the copy there" "$(field .file.path "$r")" "$(field .file.path "$again")"
if [ "$(curl -s "$server$(field .data.file.u "$gif")" | head -c 6 | tr -d '\0')" = "GIF89a" ]; then fail "the server holds ciphertext only"; else pass "the server holds ciphertext only"; fi
doc=$(grep '"filemid2"' "$tmp/bob.events" | head -1)
r=$(mesh bob fetch "$server" <<<"{\"file\": $(jq -c .data.file <<<"$doc")}" | tail -1)
if cmp -s "$tmp/report.txt" "$(field .file.path "$r")"; then pass "a file to everyone: bob gets it"; else fail "a file to everyone: bob gets it" "$r"; fi
expect "not an image" "false" "$(field .file.image "$r")"
wrong=$(jq -c '.data.file | .sha = ("0" * 64)' <<<"$doc")
r=$(mesh bob fetch "$server" <<<"{\"file\": $wrong}" || true)
expect "a file that isn't the one described is refused" false "$(field .ok "$(tail -1 <<<"$r")")"
# (Its verified copy, kept by hash, would be used as is.)
rm -rf "$tmp/bob/data/nixbook-shell/mesh/files"
wrong=$(jq -c '.data.file | .k = "'"$(head -c 32 /dev/urandom | base64)"'"' <<<"$doc")
r=$(mesh bob fetch "$server" <<<"{\"file\": $wrong}" | tail -1 || true)
if grep -q "decrypted" <<<"$(field .error "$r")"; then pass "a wrong key is caught"; else fail "a wrong key is caught" "$r"; fi
for u in "http://evil.example/file/a.bin" "/v1/account" "/file/../v1/account"; do
  wrong=$(jq -c --arg u "$u" '.data.file | .u = $u' <<<"$doc")
  r=$(mesh bob fetch "$server" <<<"{\"file\": $wrong}" || true)
  expect "nothing is fetched from elsewhere ($u)" false "$(field .ok "$r")"
done
wrong=$(jq -c '.data.file | .u = "/file/AAAAAAAAAAAA.bin" | .sha = ("1" * 64)' <<<"$doc")
r=$(mesh bob fetch "$server" <<<"{\"file\": $wrong}" || true)
expect "a file gone from the server says so" true "$(field .expired "$r")"
wrong=$(jq -c '.data.file | .name = "../../.bashrc" | .sha = ("2" * 64)' <<<"$doc")
mesh bob fetch "$server" <<<"{\"file\": $wrong}" >/dev/null 2>&1 || true
if [ -e "$tmp/bob/.bashrc" ] || [ -e "$tmp/bob/data/nixbook-shell/.bashrc" ]; then fail "a file's name can't leave the files folder"; else pass "a file's name can't leave the files folder"; fi
p=$(field .file.path "$(mesh bob fetch "$server" <<<"{\"file\": $(jq -c .data.file <<<"$doc")}" | tail -1)")
r=$(mesh bob save <<<"{\"path\": \"$p\"}")
expect "save: a copy in Downloads" "$tmp/bob/Downloads/report.txt" "$(field .path "$r")"
r=$(mesh bob save <<<"{\"path\": \"$p\"}")
expect "save again: a free name" "$tmp/bob/Downloads/report (2).txt" "$(field .path "$r")"
r=$(mesh bob save <<<"{\"path\": \"$tmp/bob/config/nixbook-shell/mesh/token\"}" || true)
expect "save only copies the mesh's files" false "$(field .ok "$r")"
r=$(mesh carol prune <<<'{"keep": []}')
expect "prune: the files of messages gone are deleted" "1 0" "$(field .removed "$r") $(find "$tmp/carol/data/nixbook-shell/mesh/files" -type f | wc -l)"

# -- Deleting --------------------------------------------------------------------

# A message carries `dh`, the hash of a proof only its sender can make; the
# deletion shows the proof, the listener gives its hash.
r=$(mesh alice send "$server" message <<<'{"text": "oops, wrong chat", "mid": "delmid1", "name": "Alice"}')
dh=$(field .dh "$r")
if [[ $dh =~ ^[0-9a-f]{64}$ ]]; then pass "a message's sender gets its deletion commitment"; else fail "a message's sender gets its deletion commitment" "$r"; fi
r=$(mesh alice send "$server" delete <<<'{"target": "delmid1", "name": "Alice"}')
expect "alice deletes it for everyone" true "$(field .ok "$r")"
# Bob poses as alice to delete it (no key of his in it, so nobody's pin of
# alice changes): he can't make her proof.
"$py" -P - "$script" "$tmp/bob/config/nixbook-shell/mesh/key" "$server" "${token[bob]}" <<'PY2'
import base64, importlib.machinery, secrets, sys, time, urllib.request
mesh = importlib.machinery.SourceFileLoader("mesh", sys.argv[1]).load_module()
key = base64.b64decode(open(sys.argv[2]).read())
topic = mesh.topic_of(key)
body = mesh.seal(key, topic, {"kind": "delete", "from": "alice", "name": "Alice", "to": "", "time": int(time.time()),
                              "mid": "forged-delete", "data": {"target": "delmid1", "proof": secrets.token_hex(32)}})
urllib.request.urlopen(urllib.request.Request(f"{sys.argv[3]}/{topic}", data=body.encode(), method="POST",
                       headers={"Authorization": f"Bearer {sys.argv[4]}"})).read()
PY2
r=$(mesh alice send "$server" delete <<<'{"target": "../x"}' || true)
expect "a deletion names a message" false "$(field .ok "$r")"
r=$(mesh alice send "$server" message <<<'{"text": "only carol may see this", "mid": "delmid2", "to": "carol"}')
expect "alice writes carol privately" true "$(field .ok "$r")"
r=$(mesh alice send "$server" delete <<<'{"target": "delmid2", "to": "carol"}')
expect "and deletes it in their conversation" true "$(field .ok "$r")"
for _ in $(seq 50); do
  [ "$(grep -c '"kind": "delete"' "$tmp/bob.events" 2>/dev/null)" -ge 2 ] && grep -q '"delmid2"' "$tmp/carol.events" &&
    [ "$(grep -c '"kind": "delete"' "$tmp/carol.events" 2>/dev/null)" -ge 3 ] && break
  sleep 0.2
done
got=$(grep '"delmid1"' "$tmp/bob.events" | grep '"kind": "message"' | head -1)
expect "bob gets the message with its commitment" "$dh" "$(field .data.dh "$got")"
dels=$(grep '"kind": "delete"' "$tmp/bob.events" || true)
expect "bob gets both deletions of it" 2 "$(grep -c '"delmid1"' <<<"$dels" || true)"
expect "the real one proves it: its hash is the commitment" 1 "$(jq -r --arg dh "$dh" 'select(.data.proofHash == $dh) | .from' <<<"$dels" | grep -c alice || true)"
expect "the one bob forged doesn't" 1 "$(jq -r --arg dh "$dh" 'select(.data.proofHash != $dh) | .from' <<<"$dels" | grep -c alice || true)"
if grep -q '"proof"' "$tmp/bob.events" "$tmp/carol.events"; then fail "the shell never gets the proof itself"; else pass "the shell never gets the proof itself"; fi
priv=$(grep '"kind": "delete"' "$tmp/carol.events" | grep '"delmid2"' | head -1)
expect "carol's private deletion comes sealed, from alice" "alice carol true" "$(field .from "$priv") $(field .to "$priv") $(field .private "$priv")"
if grep -q '"delmid2"' "$tmp/bob.events"; then fail "bob doesn't see the private deletion" "$(grep delmid2 "$tmp/bob.events")"; else pass "bob doesn't see the private deletion"; fi

# -- Reactions and profile pictures ---------------------------------------------

r=$(mesh alice send "$server" message <<<'{"text": "react to this", "mid": "reactmid1"}')
expect "alice writes to everyone" true "$(field .ok "$r")"
r=$(mesh bob send "$server" react <<<'{"target": "reactmid1", "emoji": "👍", "name": "Bob"}')
expect "bob reacts with an emoji" true "$(field .ok "$r")"
r=$(mesh bob send "$server" react <<<'{"target": "reactmid1", "emoji": "lol <b>"}' || true)
expect "a reaction is an emoji, not text" false "$(field .ok "$r")"
r=$(mesh carol send "$server" react <<<'{"target": "delmid2", "emoji": "❤️", "to": "alice", "on": false}')
expect "carol takes back a reaction in her private conversation with alice" true "$(field .ok "$r")"
# A profile picture: a small PNG (as it is without ImageMagick, else made a JPEG).
"$py" -P -c '
import struct, sys, zlib
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
raw = b"".join(b"\0" + b"\xff\x80\x00" * 8 for _ in range(8))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
                             + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))' "$tmp/face.png"
r=$(mesh alice profile "$server" <<<"{\"path\": \"$tmp/face.png\", \"name\": \"Alice\"}")
expect "alice shares her picture" "true null" "$(field .ok "$r") $(field .skipped "$r")"
r=$(mesh alice profile "$server" <<<"{\"path\": \"$tmp/face.png\"}")
expect "the same picture isn't sent again" true "$(field .skipped "$r")"
r=$(mesh mallory profile "$server" <<<"{\"path\": \"$tmp/face.png\"}" || true)
expect "the outsider can't share one" false "$(field .ok "$r")"
for _ in $(seq 50); do
  grep -q '"kind": "profile"' "$tmp/bob.events" && grep -q '"reactmid1"' "$tmp/carol.events" &&
    grep '"kind": "react"' "$tmp/alice.events" | grep -q delmid2 && break
  sleep 0.2
done
react=$(grep '"kind": "react"' "$tmp/carol.events" | grep reactmid1 | head -1)
expect "carol sees bob's reaction" "bob 👍 true" "$(field .from "$react") $(field .data.emoji "$react") $(field .data.on "$react")"
priv=$(grep '"kind": "react"' "$tmp/alice.events" | grep delmid2 | head -1)
expect "alice gets carol's private one, sealed, taken back" "carol true false" "$(field .from "$priv") $(field .private "$priv") $(field .data.on "$priv")"
if grep '"kind": "react"' "$tmp/bob.events" | grep -q delmid2; then fail "bob doesn't see it"; else pass "bob doesn't see it"; fi
prof=$(grep '"kind": "profile"' "$tmp/bob.events" | head -1)
expect "bob gets alice's picture" "alice image/" "$(field .from "$prof") $(field .data.avatar.mime "$prof" | cut -c1-6)"
r=$(mesh bob fetch "$server" <<<"{\"file\": $(jq -c .data.avatar <<<"$prof")}" | tail -1)
expect "and downloads it, an image" "true true" "$(field .ok "$r") $(field .file.image "$r")"
r=$(mesh alice profile "$server" <<<'{"path": ""}')
expect "alice takes it back" true "$(field .ok "$r")"
for _ in $(seq 50); do
  [ "$(grep -c '"kind": "profile"' "$tmp/bob.events")" -ge 2 ] && break
  sleep 0.2
done
expect "bob sees it gone" null "$(grep '"kind": "profile"' "$tmp/bob.events" | tail -1 | jq -c .data.avatar)"

# -- Nudges ----------------------------------------------------------------------

r=$(mesh alice send "$server" message <<<'{"text": "🤗 Sending you a hug", "quick": "hug", "mid": "nudge1"}')
expect "alice sends a nudge" true "$(field .ok "$r")"
mesh alice send "$server" message <<<'{"text": "x", "quick": "Not An Id!", "mid": "nudge2"}' >/dev/null
for _ in $(seq 50); do
  grep -q '"nudge2"' "$tmp/bob.events" && break
  sleep 0.2
done
expect "bob gets its id" hug "$(field .data.quick "$(grep '"nudge1"' "$tmp/bob.events" | head -1)")"
expect "a malformed id is dropped" null "$(field .data.quick "$(grep '"nudge2"' "$tmp/bob.events" | head -1)")"

# A read receipt for everyone's conversation: open, to "".
r=$(mesh bob send "$server" read <<<'{"upTo": 4321}')
expect "bob says he read everyone's conversation" true "$(field .ok "$r")"
for _ in $(seq 50); do
  grep '"kind": "read"' "$tmp/alice.events" | grep -q 4321 && break
  sleep 0.2
done
everyone=$(grep '"kind": "read"' "$tmp/alice.events" | grep 4321 | head -1)
expect "alice gets it, to everyone" "bob  4321" "$(field .from "$everyone") $(field .to "$everyone") $(field .data.upTo "$everyone")"

# -- Listening together ---------------------------------------------------------

state='{"op": "state", "sid": "0123456789abcdef", "service": "spotify", "track": {"id": "4uLU6hMCjMI75M1A2tKUQC", "title": "Song", "artist": "Band", "length": 200, "art": "http://plain/x.jpg"}, "position": 12.5, "playing": true, "name": "Alice"}'
r=$(mesh alice send "$server" listen <<<"$state")
expect "alice shares her music with everyone" true "$(field .ok "$r")"
r=$(mesh alice send "$server" listen <<<"$(jq -c '.to = "carol" | .sid = "fedcba9876543210" | .track.id = "privatetrack1"' <<<"$state")")
expect "and privately with carol" true "$(field .ok "$r")"
r=$(mesh alice send "$server" listen <<<"$(jq -c '.service = "jellyfin" | .sid = "aaaabbbbccccdddd" | .track.id = "0f3c9a2b7e"
  | .jf = {serverId: "srv-1", id: "0f3c9a2b7e", type: "Episode", seriesName: "Edgerunners", season: 1, episode: 3,
           providers: {imdb: "tt123", evil: "x"}, seriesProviders: {tvdb: "416359"}, token: "secret"}' <<<"$state")")
expect "a Jellyfin episode can be shared too" true "$(field .ok "$r")"
r=$(mesh alice send "$server" listen <<<"$(jq -c '.service = "deezer"' <<<"$state")" || true)
expect "only YouTube Music and Spotify are shared" false "$(field .ok "$r")"
r=$(mesh alice send "$server" listen <<<"$(jq -c '.op = "steal"' <<<"$state")" || true)
expect "an unknown listening event is refused" false "$(field .ok "$r")"
r=$(mesh carol send "$server" listen <<<'{"op": "join", "sid": "fedcba9876543210", "to": "alice"}')
expect "carol joins privately" true "$(field .ok "$r")"
for _ in $(seq 50); do
  grep -q '"privatetrack1"' "$tmp/carol.events" && grep -q '"kind": "listen"' "$tmp/bob.events" && grep -q '"op": "join"' "$tmp/alice.events" && break
  sleep 0.2
done
shared=$(grep '"kind": "listen"' "$tmp/bob.events" | head -1)
expect "bob gets the shared song, its position" "4uLU6hMCjMI75M1A2tKUQC 12.5 true" "$(field .data.track.id "$shared") $(field .data.position "$shared") $(field .data.playing "$shared")"
expect "a cover that isn't https is dropped" "" "$(field .data.track.art "$shared")"
for _ in $(seq 50); do
  grep -q '"aaaabbbbccccdddd"' "$tmp/bob.events" && break
  sleep 0.2
done
jfs=$(grep '"aaaabbbbccccdddd"' "$tmp/bob.events" | head -1)
expect "a Jellyfin item travels with what finds it elsewhere, nothing else" '{"episode":3,"id":"0f3c9a2b7e","name":"","providers":{"imdb":"tt123"},"season":1,"seriesName":"Edgerunners","seriesProviders":{"tvdb":"416359"},"serverId":"srv-1","type":"Episode","year":null}' "$(jq -cS .data.jf <<<"$jfs")"
if grep -q '"privatetrack1"' "$tmp/bob.events"; then fail "bob doesn't see carol's private session" "$(cat "$tmp/bob.events")"; else pass "bob doesn't see carol's private session"; fi
if grep -q '"privatetrack1"' "$tmp/carol.events"; then pass "carol gets her private session"; else fail "carol gets her private session" "$(cat "$tmp/carol.events")"; fi
if grep -q '"op": "join"' "$tmp/alice.events"; then pass "alice hears carol joined"; else fail "alice hears carol joined" "$(cat "$tmp/alice.events")"; fi
# A session's state from before an absence says nothing now: skipped.
"$py" -P - "$script" "$tmp/alice/config/nixbook-shell/mesh/key" "$server" "${token[alice]}" <<'PY2'
import base64, importlib.machinery, sys, time, urllib.request
mesh = importlib.machinery.SourceFileLoader("mesh", sys.argv[1]).load_module()
key = base64.b64decode(open(sys.argv[2]).read())
topic = mesh.topic_of(key)
body = mesh.seal(key, topic, {"kind": "listen", "from": "alice", "name": "Alice", "to": "", "time": int(time.time()) - 600,
                              "mid": "old-listen", "data": {"op": "state", "sid": "aaaaaaaaaaaaaaaa"}})
urllib.request.urlopen(urllib.request.Request(f"{sys.argv[3]}/{topic}", data=body.encode(), method="POST",
                       headers={"Authorization": f"Bearer {sys.argv[4]}"})).read()
PY2
mesh alice send "$server" message <<<'{"text": "after the old session"}' >/dev/null
for _ in $(seq 50); do
  grep -q 'after the old session' "$tmp/bob.events" && break
  sleep 0.2
done
if grep -q '"old-listen"' "$tmp/bob.events"; then fail "an old session state is skipped" "$(grep old-listen "$tmp/bob.events")"; else pass "an old session state is skipped"; fi
# Finding a Spotify song on YouTube Music: the closest title, artist, length.
best=$(
  "$py" -P - "$script" <<'PY2'
import importlib.machinery, sys
mesh = importlib.machinery.SourceFileLoader("mesh", sys.argv[1]).load_module()
results = [
    {"videoId": "radio000000", "title": "Get Lucky (Radio Edit - feat. Pharrell Williams)", "line": "Daft Punk • Get Lucky • 4:09", "length": 249},
    {"videoId": "album000000", "title": "Get Lucky (feat. Pharrell Williams and Nile Rodgers)", "line": "Daft Punk • Random Access Memories • 6:10", "length": 370},
    {"videoId": "cover000000", "title": "Get Lucky", "line": "Funk Punk • Get Lucky • 6:09", "length": 369},
    {"videoId": "other000000", "title": "One More Time", "line": "Daft Punk • Discovery • 5:20", "length": 320},
]
a, _ = mesh.best_match({"title": "Get Lucky (feat. Pharrell Williams and Nile Rodgers)", "artist": "Daft Punk", "length": 369}, results)
b, _ = mesh.best_match({"title": "Get Lucky - Radio Edit", "artist": "Daft Punk", "length": 248}, results)
c, _ = mesh.best_match({"title": "Harder Better Faster Stronger", "artist": "Daft Punk", "length": 224}, results)
print(a["videoId"], b["videoId"], c)
PY2
)
expect "a Spotify song is matched on YouTube Music by title, artist and length" "album000000 radio000000 None" "$best"
# Another version, for a listener whose YouTube Music can't play the host's:
# by the same artist, never someone else's cover.
alt=$(
  "$py" -P - "$script" <<'PY2'
import importlib.machinery, sys
mesh = importlib.machinery.SourceFileLoader("mesh", sys.argv[1]).load_module()
results = [
    {"videoId": "cover000000", "title": "Người lạ ơi (Rock version)", "line": "Jason Doan • Người lạ ơi • 3:43", "length": 223},
    {"videoId": "other000000", "title": "Người Lạ Ơi (Liên Quân Version)", "line": "Karik, Orange • Người Lạ Ơi • 3:26", "length": 206},
]
want = {"title": "Người Lạ Ơi", "artist": "Orange & Superbrothers", "length": 224}
a, _ = mesh.best_match(want, results, same_artist=True)
b, _ = mesh.best_match(want, results[:1], same_artist=True)
print(a["videoId"], b)
PY2
)
expect "another version is by the same artist, never a cover" "other000000 None" "$alt"

# Resuming: a restarted listener doesn't get the same messages again.
kill "${listener[bob]}" 2>/dev/null || true
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

# An hour-old status (as if caught up after an absence) is skipped, a
# message next to it isn't.
"$py" -P - "$script" "$tmp/alice/config/nixbook-shell/mesh/key" "$server" "${token[alice]}" <<'PY'
import base64, importlib.machinery, sys, time, urllib.request
mesh = importlib.machinery.SourceFileLoader("mesh", sys.argv[1]).load_module()
key = base64.b64decode(open(sys.argv[2]).read())
topic = mesh.topic_of(key)
body = mesh.seal(key, topic, {"kind": "presence", "from": "alice", "name": "Alice", "to": "",
                              "time": int(time.time()) - 3600, "mid": "old-presence", "data": {"state": "away"}})
req = urllib.request.Request(f"{sys.argv[3]}/{topic}", data=body.encode(), method="POST",
                             headers={"Authorization": f"Bearer {sys.argv[4]}"})
urllib.request.urlopen(req).read()
PY
mesh alice send "$server" message <<<'{"text": "after the old status"}' >/dev/null
for _ in $(seq 50); do
  grep -q 'after the old status' "$tmp/bob.events" && break
  sleep 0.2
done
if grep -q '"old-presence"' "$tmp/bob.events"; then fail "an old status is skipped" "$(cat "$tmp/bob.events")"; else pass "an old status is skipped"; fi
if grep -q 'after the old status' "$tmp/bob.events"; then pass "the message next to it arrives"; else fail "the message next to it arrives"; fi

# Joining late: the conversation so far comes too (the server keeps it).
mesh erin accept <<<"$(field .code "$(mesh alice invite "$server" erin)")" >/dev/null
listen erin
for _ in $(seq 50); do
  grep -q 'after the old status' "$tmp/erin.events" 2>/dev/null && break
  sleep 0.2
done
if grep -q '"hello everyone"' "$tmp/erin.events"; then pass "a desktop joining late gets the conversation so far"; else fail "a desktop joining late gets the conversation so far" "$(cat "$tmp/erin.events")"; fi
if grep -q 'just for carol' "$tmp/erin.events"; then fail "but not others' private messages"; else pass "but not others' private messages"; fi

# A desktop's key is made once, even by processes starting together.
for i in 1 2 3 4 5; do mesh fern keys mine >"$tmp/fern.$i" & done
wait "${!}" 2>/dev/null || true
sleep 1
expect "processes starting together make one key" 1 "$(cat "$tmp"/fern.[1-5] | jq -r .fingerprint | sort -u | wc -l)"

# A new key for a member (erin reinstalls): held back until trusted.
mesh erin send "$server" presence <<<'{"state": "free"}' >/dev/null
for _ in $(seq 50); do
  [ "$(mesh alice keys | jq -r '.members.erin.fingerprint // empty')" != "" ] && break
  sleep 0.2
done
# The reinstall: a new desktop key and no pinned keys, the token and the
# mesh key kept (as if restored), listening again.
kill "${listener[erin]}" 2>/dev/null || true
rm -f "$tmp/erin/config/nixbook-shell/mesh/identity" "$tmp/erin/state/nixbook-shell/mesh/keys.json"
listen erin
mesh erin send "$server" presence <<<'{"state": "free"}' >/dev/null
for _ in $(seq 50); do
  grep -q '"keychange"' "$tmp/alice.events" && break
  sleep 0.2
done
if grep -q '"member": "erin"' <<<"$(grep '"keychange"' "$tmp/alice.events")"; then pass "a member's new key is noticed"; else fail "a member's new key is noticed" "$(cat "$tmp/alice.events")"; fi
r=$(mesh alice send "$server" message <<<'{"text": "for the new erin", "to": "erin"}' || true)
expect "no private message to a changed key before it is trusted" false "$(field .ok "$r")"
r=$(mesh alice keys trust erin)
expect "the new key can be trusted" true "$(field .ok "$r")"
r=$(mesh alice send "$server" message <<<'{"text": "for the new erin", "to": "erin"}')
expect "then the private message goes" true "$(field .ok "$r")"
for _ in $(seq 50); do
  grep -q 'for the new erin' "$tmp/erin.events" && break
  sleep 0.2
done
if grep -q 'for the new erin' "$tmp/erin.events"; then pass "and the new erin reads it"; else fail "and the new erin reads it" "$(cat "$tmp/erin.events")"; fi

# Bob poses as alice (his own key, alice's name) to write to carol privately:
# carol's desktop knows alice's key, so it holds the message back.
r=$(mesh_as bob alice send "$server" message <<<'{"text": "forged, as alice", "to": "carol"}')
expect "(bob's desktop sends the forgery)" true "$(field .ok "$r")"
for _ in $(seq 50); do
  grep -q 'held back' "$tmp/carol.events" && break
  sleep 0.2
done
if grep -q 'forged, as alice' "$tmp/carol.events"; then fail "a forged private message isn't shown" "$(cat "$tmp/carol.events")"; else pass "a forged private message isn't shown"; fi
if grep -q 'held back' "$tmp/carol.events"; then pass "and carol is told it was held back"; else fail "and carol is told it was held back" "$(cat "$tmp/carol.events")"; fi

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
