#!/usr/bin/env bash
# Tests for nixbook-accounts (accounts/, the shell's accounts backend), with
# its Google provider against fake Google APIs (tests/fake-google.py):
#   - setup (file, --find, --id/--secret) and the login flow (PKCE, state,
#     loopback redirect, the account's email);
#   - sync: full, paged, incremental (changes and deletions), expired sync
#     token, a revoked token;
#   - changes: create, update (only the fields given, Google's copy kept),
#     star, labels (made from a name), delete, batches, refusals;
#   - list: search (accents, phone digits), label and starred filters;
#   - tasks: full and incremental sync (paged, deletions, a new list),
#     create, update (a due date cleared), done/undone, move, subtasks
#     deleted with their parent, lists made, renamed and deleted.
#   - calendar: every calendar subscribed to (one hidden in Google off, its
#     events not fetched, turned on and off in the shell), a read-only
#     one), events created (single, a series, all-day), a series expanded,
#     one occurrence moved or deleted (Google's instance ids), sync tokens
#     (an expired one: everything again), moving, deleting;
#   - mail (Gmail, live): unread counts, search, a thread read (HTML made
#     plain, a charset, quoted replies cut), an attachment saved, archive,
#     read, labels (made from a name), sending (new, a reply to all, an
#     attachment through the upload endpoint), drafts, filters (made,
#     applied to the mail there, replaced, deleted; forwarding refused), an
#     account signed in before mail was asked for;
#   - several accounts: merged copies, a new contact or list in the account
#     asked for, names in two accounts, removing one account.
# Needs bash, python3, jq, curl, and go unless $NIXBOOK_ACCOUNTS names a built
# binary. Run: bash tests/accounts.sh
set -euo pipefail
export -n out 2>/dev/null || true

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
server_pid=""
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
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
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi
}
expect_contains() {
  if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "missing: $3"$'\n'"in:"$'\n'"$2"; fi
}

log="$tmp/requests"
: >"$log"
python3 "$root/tests/fake-google.py" 0 "$log" >"$tmp/port" &
server_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/port" ] && break
  sleep 0.1
done
port=$(cat "$tmp/port")
api="http://127.0.0.1:$port"

mkdir -p "$tmp/secrets" "$tmp/state" "$tmp/Downloads"
export NIXBOOK_ACCOUNTS_GOOGLE_PEOPLE_API="$api" NIXBOOK_ACCOUNTS_GOOGLE_TASKS_API="$api/tasksapi" NIXBOOK_ACCOUNTS_GOOGLE_CALENDAR_API="$api/calendarapi" \
  NIXBOOK_ACCOUNTS_GOOGLE_GMAIL_API="$api/gmailapi" NIXBOOK_ACCOUNTS_GOOGLE_GMAIL_UPLOAD="$api/gmailupload" TZ=Europe/Paris NIXBOOK_ACCOUNTS_GOOGLE_TOKEN_URL="$api/token" NIXBOOK_ACCOUNTS_GOOGLE_REVOKE_URL="$api/revoke" \
  NIXBOOK_ACCOUNTS_GOOGLE_AUTH_URL="$api/auth" NIXBOOK_ACCOUNTS_SECRETS_DIR="$tmp/secrets" XDG_STATE_HOME="$tmp/state" \
  XDG_DOWNLOAD_DIR="$tmp/Downloads" XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/config"
bin="${NIXBOOK_ACCOUNTS:-}"
if [ -z "$bin" ]; then
  bin="$tmp/nixbook-accounts"
  (cd "$root/accounts" && CGO_ENABLED=0 go build -o "$bin" .)
  if (cd "$root/accounts" && CGO_ENABLED=0 go test ./...) >/dev/null; then pass "go test"; else fail "go test"; fi
fi
nc() { "$bin" "$@"; }
cache="$tmp/state/nixbook-accounts/contacts.json"

# -- setup and login -----------------------------------------------------------

out=$(nc status)
expect_eq "status: only the local account" "false local true" "$(jq -r '"\(.providers.google.configured) \([.accounts[].id] | join(",")) \(.accounts[0].connected)"' <<<"$out")"
out=$(nc contacts sync || true)
expect_eq "sync: the local account alone" "local" "$(jq -r '[.accounts[].account] | join(",")' <<<"$out")"
# A client the system provides (nixbook ships one): configured with no
# setup, used by the sign-in; one set up here comes first.
mkdir -p "$tmp/config/nixbook-accounts"
printf '{"installed":{"client_id":"shipped.apps.googleusercontent.com","client_secret":"s"}}' >"$tmp/config/nixbook-accounts/google-client.json"
expect_eq "a provided client: configured, no setup needed" "true true" "$(nc status | jq -r '"\(.providers.google.configured) \(.providers.google.provided)"')"
nc add google --no-browser >"$tmp/plogin" &
plogin_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/plogin" ] && break
  sleep 0.1
done
kill "$plogin_pid" 2>/dev/null || true
wait "$plogin_pid" 2>/dev/null || true
expect_contains "a provided client: the sign-in uses it" "$(head -1 "$tmp/plogin")" "client_id=shipped.apps.googleusercontent.com"
rm "$tmp/config/nixbook-accounts/google-client.json"
expect_contains "setup: which provider" "$(nc setup || true)" "setup google"
expect_contains "setup: needs something" "$(nc setup google || true)" "setup google FILE, --find"
expect_contains "setup --find: nothing downloaded" "$(nc setup google --find || true)" "no client_secret*.json"
echo '{"installed":{"client_id":"old.apps.googleusercontent.com","client_secret":"s0"}}' >"$tmp/Downloads/client_secret_1.json"
touch -d '1 hour ago' "$tmp/Downloads/client_secret_1.json"
echo '{"installed":{"client_id":"new.apps.googleusercontent.com","client_secret":"s1"}}' >"$tmp/Downloads/client_secret_2.json"
nc setup google --find >/dev/null
expect_eq "setup --find: the newest download" "new.apps.googleusercontent.com" "$(jq -r .client_id "$tmp/secrets/client-google")"
echo '{"web":{"client_id":"x"}}' >"$tmp/bad.json"
expect_contains "setup: not a client" "$(nc setup google "$tmp/bad.json" || true)" "not a Google OAuth client"
nc setup google --id id.apps.googleusercontent.com --secret sec >/dev/null
expect_eq "setup --id --secret" "id.apps.googleusercontent.com sec" "$(jq -r '"\(.client_id) \(.client_secret)"' "$tmp/secrets/client-google")"
expect_eq "secrets: private files" "600" "$(stat -c %a "$tmp/secrets/client-google")"

nc add google --no-browser >"$tmp/login" &
login_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/login" ] && break
  sleep 0.1
done
auth_url=$(head -1 "$tmp/login" | jq -r .authUrl)
query=$(python3 -c 'import sys,urllib.parse as u; q=u.parse_qs(u.urlparse(sys.argv[1]).query); print(q["redirect_uri"][0], q["state"][0], q["code_challenge_method"][0], q["scope"][0].replace(" ", ","), q["access_type"][0])' "$auth_url")
read -r redirect state method scope access <<<"$query"
expect_eq "login: PKCE, offline, one consent for every service" "S256 offline https://www.googleapis.com/auth/contacts,https://www.googleapis.com/auth/tasks,https://www.googleapis.com/auth/calendar,https://www.googleapis.com/auth/gmail.modify,https://www.googleapis.com/auth/gmail.settings.basic,openid,email" "$method $access $scope"
expect_contains "login: loopback redirect" "$redirect" "http://127.0.0.1:"
code=$(curl -s -o /dev/null -w '%{http_code}' "$redirect/?state=wrong&code=the-code")
expect_eq "login: a wrong state is refused" "400" "$code"
page=$(curl -s "$redirect/?state=$state&code=the-code")
expect_contains "login: the browser's page" "$page" "Google account connected"
wait "$login_pid"
out=$(tail -1 "$tmp/login")
expect_eq "login: the account" "google-1 me@example.com" "$(jq -r '"\(.account.id) \(.account.email)"' <<<"$out")"
expect_eq "login: first sync" "true 0" "$(jq -r '"\(.contacts.accounts[0].full) \(.contacts.count)"' <<<"$out")"
expect_eq "login: tasks synced too (with the local list)" "true 2 0" "$(jq -r '"\(.tasks.accounts[0].full) \(.tasks.lists) \(.tasks.count)"' <<<"$out")"
expect_eq "login: refresh token kept, per account" "rt-me@example.com" "$(jq -r .refresh_token "$tmp/secrets/account-google-1")"
expect_contains "login: code exchanged with the verifier" "$(grep 'POST /token' "$log")" "code_verifier="
out=$(nc status)
expect_eq "status: connected" "true true me@example.com" "$(jq -r '"\(.providers.google.configured) \(.accounts[0].connected) \(.accounts[0].email)"' <<<"$out")"

# -- changes -------------------------------------------------------------------

apply() { nc contacts apply "$1"; }
out=$(apply '{"op":"create","name":"Élodie Martin","emails":["elodie@example.com",{"value":"e.martin@work.example","type":"work"}],"phones":["+33 6 12 34 56 78"],"organization":"Acme","title":"CTO","birthday":"1990-04-02","labels":["Family"],"starred":true}')
expect_eq "create: ok" "true" "$(jq -r '.[0].ok' <<<"$out")"
id1=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "create: the contact back" "Élodie Martin|elodie@example.com,e.martin@work.example|work|1990-04-02|true|Acme|CTO" \
  "$(jq -r '.[0].result | "\(.name)|\([.emails[].value] | join(","))|\(.emails[1].type)|\(.birthday)|\(.starred)|\(.organization)|\(.title)"' <<<"$out")"
body=$(grep 'POST /people:createContact' "$log" | tail -1 | cut -d' ' -f3-)
family=$(jq -r '.labels[] | select(.name == "Family") | .id' "$cache")
expect_eq "create: the request" "$(jq -cS . <<<'{"names":[{"unstructuredName":"Élodie Martin"}],"emailAddresses":[{"value":"elodie@example.com"},{"value":"e.martin@work.example","type":"work"}],"phoneNumbers":[{"value":"+33 6 12 34 56 78"}],"organizations":[{"name":"Acme","title":"CTO"}],"birthdays":[{"date":{"month":4,"day":2,"year":1990}}],"memberships":[{"contactGroupMembership":{"contactGroupResourceName":"contactGroups/myContacts"}},{"contactGroupMembership":{"contactGroupResourceName":"contactGroups/starred"}},{"contactGroupMembership":{"contactGroupResourceName":"contactGroups/'"${family#google-1:}"'"}}]}')" "$(jq -cS . <<<"$body")"
expect_contains "create: an unknown label is made" "$(grep 'POST /contactGroups' "$log")" '"name":"Family"'
expect_eq "create: in the local copy, labels by id" "[\"$family\"]" "$(jq -c --arg id "$id1" '.contacts[] | select(.id == $id) | .labels' "$cache")"
expect_eq "local copy: private" "600" "$(stat -c %a "$cache")"

apply '{"ops":[{"op":"create","givenName":"Bob","familyName":"Stone","phones":["06 99 88 77 66"],"addresses":[{"street":"1 Main St","city":"Springfield","type":"home"}]},{"op":"create","organization":"Plumbing Ltd","notes":"call before 9"},{"op":"create","notes":"no name"}]}' >"$tmp/batch"
expect_eq "batch: each reported" "true,true,false" "$(jq -r '[.[].ok] | join(",")' "$tmp/batch")"
expect_contains "create: refused without a name, email, phone or company" "$(jq -r '.[2].error' "$tmp/batch")" "needs a name"
id2=$(jq -r '.[0].result.id' "$tmp/batch")
id3=$(jq -r '.[1].result.id' "$tmp/batch")
expect_eq "create: structured address" "1 Main St
Springfield|home" "$(jq -r '.[0].result.addresses[0] | "\(.value)|\(.type)"' "$tmp/batch")"

out=$(apply "{\"op\":\"update\",\"id\":\"$id2\",\"emails\":[\"bob@example.com\"],\"title\":\"Mayor\"}")
expect_eq "update: changed fields" "bob@example.com Mayor Bob Stone" "$(jq -r '.[0].result | "\(.emails[0].value) \(.title) \(.name)"' <<<"$out")"
patch=$(grep "PATCH /people/${id2#google-1:}:updateContact" "$log" | tail -1)
expect_contains "update: only the fields given" "$patch" "updatePersonFields=emailAddresses%2Corganizations"
expect_contains "update: with Google's etag" "$patch" '"etag":"e'
expect_eq "update: the rest kept" "06 99 88 77 66" "$(jq -r '.[0].result.phones[0].value' <<<"$out")"

out=$(apply "{\"op\":\"update\",\"id\":\"$id2\",\"phones\":[{\"value\":\"06 99 88 77 66\",\"type\":\"mobile\"},\"0123\"]}")
expect_eq "update: an unchanged entry keeps Google's copy, new type" "mobile,0123" "$(jq -r '[.[0].result.phones[] | if .type != "" then .type else .value end] | join(",")' <<<"$out")"

out=$(apply "{\"op\":\"star\",\"id\":\"$id2\"}")
expect_eq "star" "true" "$(jq -r '.[0].result.starred' <<<"$out")"
out=$(apply "{\"op\":\"unstar\",\"id\":\"$id1\"}")
expect_eq "unstar, labels kept" "false [\"$family\"]" "$(jq -r '.[0].result | "\(.starred) \(.labels | tojson)"' <<<"$out")"
out=$(apply "{\"op\":\"update\",\"id\":\"$id1\",\"birthday\":\"\",\"labels\":[\"family\",\"Work\"]}")
work=$(jq -r '.labels[] | select(.name == "Work") | .id' "$cache")
expect_eq "update: birthday cleared, labels by name (any case), a new one" "|$family,$work" "$(jq -r '.[0].result | "\(.birthday)|\(.labels | join(","))"' <<<"$out")"
expect_contains "update: a bad birthday" "$(apply "{\"op\":\"update\",\"id\":\"$id1\",\"birthday\":\"April\"}")" "YYYY-MM-DD or MM-DD"
expect_contains "update: nothing to change" "$(apply "{\"op\":\"update\",\"id\":\"$id1\"}")" "nothing to change"
expect_contains "update: unknown contact" "$(apply '{"op":"update","id":"nope","name":"x"}')" "no contact 'nope'"
expect_contains "unknown op" "$(apply '{"op":"merge"}')" "unknown op 'merge'"

# -- photos ----------------------------------------------------------------------

img() { python3 "$root/tests/test-image.py" "$@"; }
img png "$tmp/photo.png"
echo "not an image" >"$tmp/photo.txt"
out=$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"$tmp/photo.png\"}")
expect_contains "set_photo: Google's photo URL back" "$(jq -r '.[0].result.photo' <<<"$out")" "https://lh3.googleusercontent.com/fake/${id1#google-1:}-"
grep "PATCH /people/${id1#google-1:}:updateContactPhoto" "$log" | tail -1 | cut -d' ' -f3- | jq -r .photoBytes | base64 -d >"$tmp/sent.jpg"
expect_eq "set_photo: a JPEG, fit in 720 pixels" "720x360" "$(img size "$tmp/sent.jpg")"
expect_eq "set_photo: in the local copy" "$(jq -r '.[0].result.photo' <<<"$out")" "$(nc contacts get "$id1" | jq -r .photo)"
out=$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"\"}")
expect_eq "set_photo: \"\" removes it (Google's silhouette left out)" "" "$(jq -r '.[0].result.photo' <<<"$out")"
expect_contains "set_photo: removed at Google" "$(grep -c "DELETE /people/${id1#google-1:}:deleteContactPhoto" "$log")" "1"
expect_contains "set_photo: only an image" "$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"$tmp/photo.txt\"}")" "isn't a PNG, JPEG or GIF image"
expect_contains "set_photo: an absolute path" "$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"photo.png\"}")" "absolute path"
expect_contains "set_photo: a missing file" "$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"$tmp/nope.png\"}")" "no file"
expect_contains "apply: not JSON" "$(nc contacts apply '{' || true)" "isn't JSON"
expect_contains "apply: too many" "$(nc contacts apply "{\"ops\":[$(printf '{"op":"star"},%.0s' $(seq 50)){\"op\":\"star\"}]}" || true)" "1 to 50"

# -- labels --------------------------------------------------------------------

expect_contains "create_label: a duplicate" "$(apply '{"op":"create_label","name":"work"}')" "already a label"
out=$(apply '{"op":"rename_label","label":"Work","name":"Job"}')
expect_eq "rename_label" "Job" "$(jq -r '.[0].result.name' <<<"$out")"
expect_contains "rename_label: with the group's etag" "$(grep "PUT /contactGroups/${work#google-1:}" "$log")" '"updateGroupFields":"name"'

# -- sync ----------------------------------------------------------------------

out=$(nc contacts sync)
expect_eq "sync: incremental" "false" "$(jq -r .accounts[0].full <<<"$out")"
expect_eq "sync: 3 contacts" "3" "$(jq -r .count <<<"$out")"
expect_eq "sync: labels with counts" "Family:1,Job:1" "$(jq -r '[.labels[] | "\(.name):\(.count)"] | join(",")' "$cache")"
if grep -q "syncToken=" "$log"; then pass "sync: with the sync token"; else fail "sync: with the sync token"; fi

out=$(apply "{\"op\":\"delete\",\"id\":\"$id3\"}")
expect_eq "delete" "$id3" "$(jq -r '.[0].result.deleted' <<<"$out")"
expect_eq "delete: gone from the local copy" "2" "$(jq '.contacts | length' "$cache")"
# Someone deletes Bob in Google Contacts: the next sync drops him.
curl -s -X DELETE -H 'Authorization: Bearer x' "$api/people/${id2#google-1:}:deleteContact" >/dev/null
out=$(nc contacts sync)
expect_eq "sync: a deletion elsewhere" "1 1" "$(jq -r '"\(.accounts[0].changed) \(.count)"' <<<"$out")"

jq '.accounts["google-1"].syncToken = "expired"' "$cache" >"$tmp/c" && mv "$tmp/c" "$cache"
out=$(nc contacts sync)
expect_eq "sync: expired token, all again" "true 1" "$(jq -r '"\(.accounts[0].full) \(.count)"' <<<"$out")"
out=$(nc contacts sync --full)
expect_eq "sync --full" "true" "$(jq -r .accounts[0].full <<<"$out")"

# -- list ----------------------------------------------------------------------

apply '{"ops":[{"op":"create","name":"Zoé Durand","phones":["+33 7 00 11 22 33"],"starred":true},{"op":"create","name":"Adam Smith","emails":["adam@acme.example"],"labels":["Family"]}]}' >/dev/null
expect_eq "list: sorted by name" "Adam Smith,Élodie Martin,Zoé Durand" "$(nc contacts list | jq -r '[.contacts[].name] | join(",")')"
expect_eq "list: accents ignored" "Élodie Martin" "$(nc contacts list --query elodie | jq -r '[.contacts[].name] | join(",")')"
expect_eq "list: every word" "Élodie Martin" "$(nc contacts list --query 'acme cto' | jq -r '[.contacts[].name] | join(",")')"
expect_eq "list: phone digits" "Zoé Durand" "$(nc contacts list --query '700 112 233' | jq -r '[.contacts[].name] | join(",")')"
expect_eq "list: label" "Adam Smith,Élodie Martin" "$(nc contacts list --label family | jq -r '[.contacts[].name] | join(",")')"
expect_eq "list: label names, not ids" '["Family","Job"]' "$(nc contacts list --query elodie | jq -c '.contacts[0].labels')"
expect_eq "list: starred" "Zoé Durand" "$(nc contacts list --starred | jq -r '[.contacts[].name] | join(",")')"
expect_eq "list: limit, total" "1 3" "$(nc contacts list --limit 1 | jq -r '"\(.contacts | length) \(.total)"')"
expect_contains "list: unknown label" "$(nc contacts list --label Golf || true)" "no label 'Golf'"
expect_eq "get" "Zoé Durand" "$(nc contacts get "$(nc contacts list --starred | jq -r '.contacts[0].id')" | jq -r .name)"

out=$(apply '{"op":"delete_label","label":"Family"}')
expect_eq "delete_label: the contacts stay" "3 0" "$(jq -r --arg f "$family" '"\(.contacts | length) \([.contacts[].labels[] | select(. == $f)] | length)"' "$cache")"

# -- tasks ---------------------------------------------------------------------

tasks_cache="$tmp/state/nixbook-accounts/tasks.json"
tapply() { nc tasks apply "$1"; }
out=$(tapply '{"ops":[{"op":"create","title":"call mum","due":"2026-10-20","notes":"about Sunday"},{"op":"create","title":"buy milk"},{"op":"create","title":"pay rent","list":"Nope"},{"op":"create","title":""},{"op":"create","title":"x","due":"tomorrow"}]}')
expect_eq "tasks create: each reported" "true,true,false,false,false" "$(jq -r '[.[].ok] | join(",")' <<<"$out")"
expect_eq "tasks create: unknown list" "no list 'Nope': My Tasks, Tasks" "$(jq -r '.[2].error' <<<"$out")"
expect_contains "tasks create: a title needed" "$(jq -r '.[3].error' <<<"$out")" "needs a title"
expect_contains "tasks create: due checked" "$(jq -r '.[4].error' <<<"$out")" "YYYY-MM-DD"
t1=$(jq -r '.[0].result.id' <<<"$out")
t2=$(jq -r '.[1].result.id' <<<"$out")
expect_eq "tasks create: the task back" "call mum|2026-10-20|about Sunday|google-1:L1|false" "$(jq -r '.[0].result | "\(.title)|\(.due)|\(.notes)|\(.listId)|\(.done)"' <<<"$out")"
expect_contains "tasks create: Google's due time" "$(grep "POST /tasksapi/lists/L1/tasks" "$log" | head -1)" '"due":"2026-10-20T00:00:00.000Z"'
expect_eq "tasks create: in the copy" "2" "$(jq '.tasks | length' "$tasks_cache")"

out=$(tapply "{\"op\":\"create\",\"title\":\"milk brand\",\"parent\":\"$t2\"}")
expect_eq "tasks create: a subtask" "$t2" "$(jq -r '.[0].result.parent' <<<"$out")"

out=$(tapply "{\"op\":\"update\",\"id\":\"$t1\",\"due\":\"\",\"title\":\"call mum back\"}")
expect_eq "tasks update: due cleared, title" "|call mum back|about Sunday" "$(jq -r '.[0].result | "\(.due)|\(.title)|\(.notes)"' <<<"$out")"
expect_contains "tasks update: the whole task put back" "$(grep "PUT /tasksapi/lists/L1/tasks/${t1#google-1:}" "$log" | tail -1)" '"notes":"about Sunday"'
expect_contains "tasks update: nothing to change" "$(tapply "{\"op\":\"update\",\"id\":\"$t1\"}")" "nothing to change"
expect_contains "tasks update: unknown task" "$(tapply '{"op":"update","id":"nope","title":"x"}')" "no task 'nope'"
out=$(tapply "{\"op\":\"done\",\"id\":\"$t1\"}")
expect_eq "tasks done" "true" "$(jq -r '.[0].result | .done and (.completed != "")' <<<"$out")"
out=$(tapply "{\"op\":\"undone\",\"task\":\"$t1\"}")
expect_eq "tasks undone (task works as id)" "false|" "$(jq -r '.[0].result | "\(.done)|\(.completed)"' <<<"$out")"

out=$(tapply '{"op":"create_list","name":"Work"}')
work=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "tasks create_list" "Work" "$(jq -r '.[0].result.name' <<<"$out")"
expect_contains "tasks create_list: a duplicate" "$(tapply '{"op":"create_list","name":"work"}')" "already a list"
out=$(tapply "{\"op\":\"move\",\"id\":\"$t1\",\"list\":\"work\"}")
expect_eq "tasks move: by list name, same id" "$t1 $work" "$(jq -r '.[0].result | "\(.id) \(.listId)"' <<<"$out")"
expect_contains "tasks move: Google's move" "$(grep "/move?" "$log" | tail -1)" "destinationTasklist=${work#google-1:}"
out=$(tapply '{"op":"rename_list","list":"Work","name":"Job"}')
expect_eq "tasks rename_list" "Job" "$(jq -r '.lists[] | select(.id == "'"$work"'") | .name' "$tasks_cache")"

out=$(nc tasks sync)
expect_eq "tasks sync: incremental" "false 3 3" "$(jq -r '"\(.accounts[0].full) \(.lists) \(.count)"' <<<"$out")"
if grep -q "updatedMin=" "$log"; then pass "tasks sync: changes since the last sync"; else fail "tasks sync: changes since the last sync"; fi
# Changes made in Google Tasks elsewhere: a new task in a new list, one deleted.
curl -s -X DELETE -H 'Authorization: Bearer x' "$api/tasksapi/lists/L1/tasks/${t2#google-1:}" >/dev/null
home=$(curl -s -X POST -H 'Authorization: Bearer x' -H 'Content-Type: application/json' -d '{"title":"Home"}' "$api/tasksapi/users/@me/lists" | jq -r .id)
for i in 1 2 3; do
  curl -s -X POST -H 'Authorization: Bearer x' -H 'Content-Type: application/json' -d "{\"title\":\"chore $i\"}" "$api/tasksapi/lists/$home/tasks" >/dev/null
done
out=$(nc tasks sync)
expect_eq "tasks sync: a deletion elsewhere (its subtask too), a new list (paged)" "4 4" "$(jq -r '"\(.lists) \(.count)"' <<<"$out")"
expect_eq "tasks sync: the copy" "call mum back,chore 1,chore 2,chore 3" "$(jq -r '[.tasks[].title] | sort | join(",")' "$tasks_cache")"
expect_eq "tasks list: one list" "chore 1,chore 2,chore 3" "$(nc tasks list --list home | jq -r '[.tasks[].title] | join(",")')"
tapply "{\"op\":\"done\",\"id\":\"$t1\"}" >/dev/null
expect_eq "tasks list: open ones by default" "0 1" "$(nc tasks list --list Job | jq -r '.tasks | length') $(nc tasks list --list Job --done | jq -r '.tasks | length')"
expect_eq "tasks sync --full" "true 4" "$(nc tasks sync --full | jq -r '"\(.accounts[0].full) \(.count)"')"
# A copy that lost its open tasks (as an older version left it): only
# "changed since" can't bring them back, a full sync does. (Synced after
# they last changed: the test's tasks are seconds old.)
jq --argjson later "$((($(date +%s) + 3600) * 1000))" \
  '.tasks |= map(select(.done)) | .accounts[] |= (.syncedAt = $later)' "$tasks_cache" >"$tmp/broken.json" && mv "$tmp/broken.json" "$tasks_cache"
nc tasks sync >/dev/null
expect_eq "tasks sync: a broken copy stays broken" "1" "$(jq -r '.tasks | length' "$tasks_cache")"
nc tasks sync --full >/dev/null
expect_eq "tasks sync --full: the open tasks back" "4" "$(jq -r '.tasks | length' "$tasks_cache")"

expect_contains "tasks delete_list: Google's refusal" "$(tapply '{"op":"delete_list","list":"My Tasks"}')" "default list can't be deleted"
out=$(tapply '{"op":"delete_list","list":"Home"}')
expect_eq "tasks delete_list: with its tasks" "3" "$(jq -r '.[0].result.tasks' <<<"$out")"
out=$(tapply "{\"op\":\"delete\",\"id\":\"$t1\"}")
expect_eq "tasks delete" "call mum back" "$(jq -r '.[0].result.title' <<<"$out")"
expect_eq "tasks: the copy after" "0 3" "$(jq -r '"\(.tasks | length) \(.lists | length)"' "$tasks_cache")"
expect_eq "status: tasks" "3" "$(nc status | jq -r .tasks.lists)"

# -- calendar --------------------------------------------------------------------

events_cache="$tmp/state/nixbook-accounts/events.json"
capply() { nc calendar apply "$1"; }
out=$(nc calendar sync)
expect_eq "calendar sync: every calendar (and the local one)" "4 0" "$(jq -r '"\(.calendars) \(.count)"' <<<"$out")"
out=$(nc calendar calendars)
expect_eq "calendar calendars" "Me true false 10|Holidays false true|Hidden false false|Personal true false 10" "$(jq -r '[.calendars[] | "\(.name) \(.primary) \(.readOnly)\(if .defaultReminders | length > 0 then " \(.defaultReminders | join(","))" else "" end)"] | join("|")' <<<"$out")"
out=$(capply '{"ops":[{"op":"create","summary":"Dentist","start":"2026-11-03T09:00","location":"12 rue X, https://zoom.us/j/123"},{"op":"create","summary":"Standup","start":"2026-10-19T09:30","end":"2026-10-19T09:45","recurrence":"weekdays","reminders":[5]},{"op":"create","summary":"Holidays","start":"2026-12-24","end":"2026-12-26","reminders":null},{"op":"create","summary":"x","calendar":"Holidays","start":"2026-11-03"},{"op":"create","start":"2026-11-03"}]}')
expect_eq "calendar create: each reported" "true,true,true,false,false" "$(jq -r '[.[].ok] | join(",")' <<<"$out")"
expect_contains "calendar create: a read-only calendar" "$(jq -r '.[3].error' <<<"$out")" "read-only"
expect_contains "calendar create: a summary needed" "$(jq -r '.[4].error' <<<"$out")" "summary"
expect_eq "calendar create: in the primary calendar" "google-1:primary-cal" "$(jq -r '.[0].result.calendarId' <<<"$out")"
expect_eq "calendar create: the meeting link found" "https://zoom.us/j/123" "$(jq -r '.[0].result.meetingUrl' <<<"$out")"
body=$(grep "POST /calendarapi/calendars/primary-cal/events" "$log" | sed -n 2p | cut -d' ' -f3-)
expect_eq "calendar create: a series in the local zone" '{"dateTime":"2026-10-19T09:30:00+02:00","timeZone":"Europe/Paris"} ["RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"] [{"method":"popup","minutes":5}]' "$(jq -c '.start' <<<"$body") $(jq -c '.recurrence' <<<"$body") $(jq -c '.reminders.overrides' <<<"$body")"
body=$(grep "POST /calendarapi/calendars/primary-cal/events" "$log" | sed -n 3p | cut -d' ' -f3-)
expect_eq "calendar create: all-day, its last day given" '{"date":"2026-12-24"} {"date":"2026-12-27"} true' "$(jq -c '.start' <<<"$body") $(jq -c '.end' <<<"$body") $(jq -c '.reminders.useDefault' <<<"$body")"
standup=$(jq -r '.[1].result.id' <<<"$out")

out=$(nc calendar events --from 2026-10-26 --to 2026-10-31)
expect_eq "calendar events: a series expanded, across the clock change" "09:30+01:00 x5" "$(jq -r '[.events[] | select(.summary == "Standup") | .start[11:16] + .start[19:]] | unique | .[0]' <<<"$out") x$(jq '[.events[] | select(.summary == "Standup")] | length' <<<"$out")"
expect_eq "calendar events: the event's reminders, else the calendar's" "[5] [10]" "$(jq -c '[.events[] | select(.summary == "Standup")][0].reminders' <<<"$out") $(nc calendar events --from 2026-11-03 --to 2026-11-04 | jq -c '.events[] | select(.summary == "Dentist") | .reminders')"
out=$(capply "{\"ops\":[{\"op\":\"delete\",\"id\":\"$standup\",\"occurrence\":\"2026-10-27T09:30:00+01:00\"},{\"op\":\"update\",\"id\":\"$standup\",\"occurrence\":\"2026-10-28T09:30:00+01:00\",\"start\":\"2026-10-28T11:00\",\"summary\":\"Standup (late)\"}]}")
expect_eq "calendar: one occurrence deleted, one moved" "true,true" "$(jq -r '[.[].ok] | join(",")' <<<"$out")"
expect_contains "calendar: an occurrence by Google's instance id" "$(grep "DELETE /calendarapi" "$log" | tail -1)" "${standup#google-1:}_20261027T083000Z"
out=$(nc calendar events --from 2026-10-26 --to 2026-10-31)
expect_eq "calendar events: the occurrence changes" "Standup 26,Standup (late) 28,Standup 29,Standup 30" "$(jq -r '[.events[] | "\(.summary) \(.start[8:10])"] | join(",")' <<<"$out")"
expect_eq "calendar events: a changed occurrence stands for its series" "$standup" "$(jq -r '.events[] | select(.summary == "Standup (late)") | .id' <<<"$out")"
out=$(capply "{\"op\":\"update\",\"id\":\"$standup\",\"all\":true,\"occurrence\":\"2026-10-29T09:30:00+01:00\",\"start\":\"2026-10-29T10:00\",\"end\":\"2026-10-29T10:20\"}")
expect_eq "calendar update: the series moved as an occurrence was" '{"dateTime":"2026-10-19T10:00:00+02:00","timeZone":"Europe/Paris"} {"dateTime":"2026-10-19T10:20:00+02:00","timeZone":"Europe/Paris"}' "$(grep "PATCH /calendarapi/calendars/primary-cal/events/${standup#google-1:} " "$log" | tail -1 | cut -d' ' -f3- | jq -c '.start, .end' | paste -sd' ')"
expect_eq "calendar events: every occurrence moved" "10:00 10:00" "$(nc calendar events --from 2026-10-29 --to 2026-10-31 | jq -r '[.events[] | select(.summary == "Standup") | .start[11:16]] | join(" ")')"
out=$(capply "{\"op\":\"update\",\"id\":\"$standup\",\"summary\":\"Daily standup\"}")
expect_eq "calendar update: the series" "Daily standup,Standup (late)" "$(nc calendar events --from 2026-10-28 --to 2026-10-30 | jq -r '[.events[].summary] | unique | join(",")')"
expect_contains "calendar update: nothing to change" "$(capply "{\"op\":\"update\",\"id\":\"$standup\"}")" "nothing to change"
expect_contains "calendar update: unknown event" "$(capply '{"op":"update","id":"nope","summary":"x"}')" "no event 'nope'"
expect_contains "calendar events: a range needed" "$(nc calendar events --from 2026-10-01 || true)" "--from TIME --to TIME"

out=$(nc calendar sync)
expect_eq "calendar sync: with the sync tokens" "false" "$(jq -r '.accounts[0].full' <<<"$out")"
if grep -q "syncToken=" "$log"; then pass "calendar sync: a token sent"; else fail "calendar sync: a token sent"; fi
jq '.accounts["google-1"].syncToken = "{\"primary-cal\":\"expired\",\"holidays\":\"expired\"}"' "$events_cache" >"$tmp/e" && mv "$tmp/e" "$events_cache"
out=$(nc calendar sync)
expect_eq "calendar sync: an expired token, everything again" "true" "$(jq -r '.accounts[0].full' <<<"$out")"
expect_eq "calendar sync: the copy as before" "Daily standup,Dentist,Holidays,Standup (late)" "$(nc calendar events --from 2026-10-01 --to 2027-01-01 | jq -r '[.events[].summary] | unique | join(",")')"
dentist=$(nc calendar events --from 2026-11-03 --to 2026-11-04 | jq -r '.events[] | select(.summary == "Dentist") | .id')
expect_contains "calendar update: an unknown calendar to move to" "$(capply "{\"op\":\"update\",\"id\":\"$dentist\",\"calendar\":\"nope\"}")" "no calendar 'nope'"
out=$(capply "{\"op\":\"delete\",\"id\":\"$standup\"}")
expect_eq "calendar delete: the series and its occurrences" "0" "$(nc calendar events --from 2026-10-01 --to 2027-01-01 | jq '[.events[] | select(.summary | test("tandup"))] | length')"
out=$(nc calendar sync)
expect_eq "calendar sync: the deletion seen by Google" "0" "$(nc calendar events --from 2026-10-01 --to 2027-01-01 | jq '[.events[] | select(.summary | test("tandup"))] | length')"
expect_eq "status: calendar" "4" "$(nc status | jq -r .calendar.calendars)"

# Calendars turned on and off: Google's hidden one starts off, its events not fetched.
expect_eq "calendars: hidden in Google, off" "Me false|Holidays false|Hidden true|Personal false" "$(nc calendar calendars | jq -r '[.calendars[] | "\(.name) \(.hidden)"] | join("|")')"
if grep -q "GET /calendarapi/calendars/hidden-cal/events" "$log"; then fail "calendars: an off one's events not fetched"; else pass "calendars: an off one's events not fetched"; fi
curl -s -X POST -H 'Authorization: Bearer x' -H 'Content-Type: application/json' "$api/calendarapi/calendars/hidden-cal/events" \
  --data '{"summary":"Gym","start":{"dateTime":"2026-11-05T18:00:00+01:00"},"end":{"dateTime":"2026-11-05T19:00:00+01:00"}}' >/dev/null
out=$(capply '{"op":"show_calendar","calendar":"Hidden"}')
expect_eq "show_calendar: on" "google-1:hidden-cal false" "$(jq -r '.[0].result | "\(.id) \(.hidden)"' <<<"$out")"
nc calendar sync >/dev/null
expect_eq "show_calendar: its events fetched with the next sync" "Gym" "$(nc calendar events --from 2026-11-05 --to 2026-11-06 | jq -r '[.events[].summary] | join(",")')"
expect_eq "show_calendar: kept over syncs (Google's selection left alone)" "false" "$(nc calendar calendars | jq -r '.calendars[] | select(.name == "Hidden") | .hidden')"
capply '{"op":"hide_calendar","calendar":"google-1:hidden-cal"}' >/dev/null
expect_eq "hide_calendar: its events not listed at once" "" "$(nc calendar events --from 2026-11-05 --to 2026-11-06 | jq -r '[.events[].summary] | join(",")')"
fetches=$(grep -c "GET /calendarapi/calendars/hidden-cal/events" "$log")
nc calendar sync >/dev/null
expect_eq "hide_calendar: not fetched any more" "$fetches" "$(grep -c "GET /calendarapi/calendars/hidden-cal/events" "$log")"
capply '{"op":"hide_calendar","calendar":"Me"}' >/dev/null
out=$(capply '{"op":"create","summary":"Haircut","start":"2026-11-06T10:00"}')
expect_eq "hide_calendar: new events go to a shown calendar" "local:personal" "$(jq -r '.[0].result.calendarId' <<<"$out")"
capply "{\"op\":\"delete\",\"id\":\"$(jq -r '.[0].result.id' <<<"$out")\"}" >/dev/null
capply '{"op":"show_calendar","calendar":"Me"}' >/dev/null
expect_contains "show_calendar: a calendar needed" "$(capply '{"op":"show_calendar"}')" "is required (a calendar's id or name)"

# -- mail ------------------------------------------------------------------------

expect_eq "mail: the Gmail API in the setup's list" "true" "$(nc status | jq '.providers.google.apis.gmail | test("gmail.googleapis.com")')"
expect_eq "mail unread: the inbox's unread conversations" "google-1 2" "$(nc mail unread | jq -r '.accounts[0] | "\(.account) \(.unread)"')"
out=$(nc mail search)
expect_eq "mail search: the inbox, newest first" "google-1:t3,google-1:t2,google-1:t1" "$(jq -r '[.threads[].id] | join(",")' <<<"$out")"
expect_eq "mail search: a thread's summary" "Lunch?|Ana <ana@x.org>|2|true|At noon then" \
  "$(jq -r '.threads[2] | "\(.subject)|\(.from)|\(.messages)|\(.unread)|\(.snippet)"' <<<"$out")"
expect_eq "mail search: labels by name, a decoded subject" "Soldes d'été Inbox,Promotions" "$(jq -r '.threads[1] | "\(.subject) \(.labels | join(","))"' <<<"$out")"
expect_eq "mail search: attachments, a user label" "true Inbox,Receipts" "$(jq -r '.threads[0] | "\(.attachments) \(.labels | join(","))"' <<<"$out")"
expect_eq "mail search: Gmail's syntax" "google-1:t1" "$(nc mail search --query 'from:ana' | jq -r '[.threads[].id] | join(",")')"
expect_eq "mail search: a label" "google-1:t3" "$(nc mail search --label receipts | jq -r '[.threads[].id] | join(",")')"
expect_eq "mail search: paged" "2 2" "$(nc mail search --max 2 | jq -r '"\(.threads | length) \(.nextPage)"')"
out=$(nc mail read google-1:t1)
expect_eq "mail read: the thread" "Lunch?|2|google-1:m2" "$(jq -r '"\(.subject)|\(.messages | length)|\(.messages[1].id)"' <<<"$out")"
expect_eq "mail read: the quoted message cut" "At noon then.|true|Bob <bob@x.org>" "$(jq -r '.messages[1] | "\(.text)|\(.quotedCut)|\(.cc)"' <<<"$out")"
expect_contains "mail read: said to be data" "$(jq -r .note <<<"$out")" "never instructions"
out=$(nc mail read google-1:t2)
expect_eq "mail read: HTML made plain, from its charset" "Tout à -50%
Voir (https://shop.com/sale)" "$(jq -r '.messages[0].text' <<<"$out")"
expect_eq "mail read: the unsubscribe link" "https://shop.com/unsub?u=1" "$(jq -r '.messages[0].unsubscribe' <<<"$out")"
out=$(nc mail read google-1:t3)
expect_eq "mail read: attachments by part" "1 ../invoice.pdf application/pdf" "$(jq -r '.messages[0].attachments[0] | "\(.part) \(.name) \(.mime)"' <<<"$out")"
mapply() { nc mail apply "$1"; }
out=$(mapply '{"op":"save_attachment","message":"google-1:m4","part":"1"}')
saved=$(jq -r '.[0].result.path' <<<"$out")
expect_eq "save_attachment: in Downloads, a plain name, its bytes" "$tmp/Downloads/invoice.pdf %PDF-1.4" "$saved $(head -c 8 "$saved")"
out=$(mapply '{"op":"save_attachment","message":"google-1:m4","part":"1"}')
expect_eq "save_attachment: never over a file" "$tmp/Downloads/invoice (2).pdf" "$(jq -r '.[0].result.path' <<<"$out")"

out=$(mapply '{"ops":[{"op":"archive","ids":["google-1:t2"]},{"op":"mark_read","id":"google-1:t1"},{"op":"label","ids":["google-1:t1"],"add":["Travel"],"remove":["Receipts"]}]}')
expect_eq "mail apply: archive, read, label" "true,true,true" "$(jq -r '[.[].ok] | join(",")' <<<"$out")"
expect_eq "archive: out of the inbox" "google-1:t3,google-1:t1" "$(nc mail search | jq -r '[.threads[].id] | join(",")')"
expect_eq "mark_read: no unread left but the archived one" "0" "$(nc mail unread | jq -r '.accounts[0].unread')"
expect_contains "label: a new label made from its name" "$(grep 'POST /gmailapi/users/me/labels' "$log")" '"name":"Travel"'
expect_eq "labels: Gmail's own first, then the user's, with counts" "Inbox Receipts:1 Travel:1" \
  "$(nc mail labels | jq -r '"\(.labels[0].name) \([.labels[] | select(.system | not) | "\(.name):\(.total)"] | join(" "))"')"
expect_contains "label: an unknown label to remove" "$(mapply '{"op":"label","id":"google-1:t1","remove":["Nope"]}')" "no label 'Nope'"
expect_contains "rename_label: not Gmail's own" "$(mapply '{"op":"rename_label","label":"Inbox","name":"x"}')" "Gmail's own labels"
out=$(mapply '{"op":"rename_label","label":"Travel","name":"Trips"}')
expect_eq "rename_label" "Trips" "$(jq -r '.[0].result.label' <<<"$out")"
expect_contains "mail apply: an unknown change" "$(mapply '{"op":"explode"}')" "unknown change 'explode'"
expect_contains "send: needs a recipient" "$(mapply '{"op":"send","subject":"x","body":"y"}')" "needs a recipient"
expect_contains "send: addresses checked" "$(mapply '{"op":"send","to":"not an address","body":"y"}')" "isn't a list of addresses"

sent_raw() { grep "POST /gmailapi/users/me/$1 " "$log" | tail -1 | cut -d' ' -f3- | jq -r "$2" | python3 -c 'import sys,base64; s=sys.stdin.read().strip(); print(base64.urlsafe_b64decode(s+"="*(-len(s)%4)).decode())'; }
out=$(mapply '{"op":"send","to":"Zoé Durand <zoe@x.org>","bcc":"secret@x.org","subject":"Bonjour é","body":"Première ligne\nfin"}')
sent_thread=$(jq -r '.[0].result.thread' <<<"$out")
expect_eq "send: sent, a new thread" "true google-1:s" "$(jq -r '.[0].ok' <<<"$out") ${sent_thread:0:10}"
raw=$(sent_raw messages/send .raw)
expect_contains "send: from the account" "$raw" "From: <me@example.com>"
expect_contains "send: the name encoded" "$raw" "To: =?utf-8?q?Zo=C3=A9_Durand?= <zoe@x.org>"
expect_contains "send: Bcc handed to Gmail" "$raw" "Bcc: <secret@x.org>"
out=$(nc mail read "$sent_thread")
expect_eq "send: read back" "Bonjour é|Première ligne
fin" "$(jq -r '"\(.subject)|\(.messages[0].text)"' <<<"$out")"
out=$(mapply '{"op":"send","replyTo":"google-1:t1","replyAll":true,"body":"Perfect"}')
expect_eq "reply: in its thread, to the sender, the others in copy" 'google-1:t1|"Ana" <ana@x.org>|"Bob" <bob@x.org>|Re: Lunch?' \
  "$(jq -r '.[0].result | "\(.thread)|\(.to)|\(.cc)|\(.subject)"' <<<"$out")"
raw=$(sent_raw messages/send .raw)
expect_contains "reply: In-Reply-To the last message" "$raw" "In-Reply-To: <m2@x.org>"
expect_contains "reply: References the thread" "$raw" "References: <m1@x.org> <m2@x.org>"
expect_eq "reply: its thread id given" "t1" "$(grep 'POST /gmailapi/users/me/messages/send ' "$log" | tail -1 | cut -d' ' -f3- | jq -r .threadId)"
printf 'hello file' >"$tmp/notes.txt"
out=$(NIXBOOK_ACCOUNTS_GMAIL_INLINE_MAX=100 nc mail apply "{\"op\":\"send\",\"to\":\"zoe@x.org\",\"subject\":\"File\",\"body\":\"see attached\",\"attachments\":[\"$tmp/notes.txt\"]}")
expect_eq "send: a big one through the upload endpoint" "true notes.txt 1" "$(jq -r '"\(.[0].ok) \(.[0].result.attachments[0])"' <<<"$out") $(grep -c 'POST /gmailupload/users/me/messages/send?uploadType=multipart' "$log")"
expect_eq "send: the attachment there" "notes.txt" "$(nc mail read "$(jq -r '.[0].result.thread' <<<"$out")" | jq -r '.messages[0].attachments[0].name')"
expect_contains "send: a missing file" "$(mapply '{"op":"send","to":"zoe@x.org","body":"x","attachments":["/nope"]}')" "can't attach /nope"

out=$(mapply '{"op":"draft","to":"zoe@x.org","subject":"Later","body":"draft text"}')
draft=$(jq -r '.[0].result.draft' <<<"$out")
expect_eq "draft: kept" "Later <zoe@x.org>" "$(nc mail drafts | jq -r '.drafts[0] | "\(.subject) \(.to)"')"
out=$(mapply "{\"op\":\"send_draft\",\"id\":\"$draft\"}")
expect_eq "send_draft: sent, no draft left" "true 0" "$(jq -r '.[0].ok' <<<"$out") $(nc mail drafts | jq '.drafts | length')"

out=$(mapply '{"op":"create_filter","criteria":{"from":"news@shop.com"},"action":{"label":"Shopping","archive":true,"markRead":true},"applyExisting":true}')
filter=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "create_filter: in words" "from:(news@shop.com) → label Shopping, skip the inbox, mark read" "$(jq -r '.[0].result.description' <<<"$out")"
expect_eq "create_filter: applied to the mail there" "1" "$(jq -r '.[0].result.appliedTo' <<<"$out")"
expect_eq "create_filter: the existing mail labelled" "google-1:t2" "$(nc mail search --label Shopping | jq -r '[.threads[].id] | join(",")')"
expect_eq "filters: listed" "1 from:(news@shop.com) → label Shopping, skip the inbox, mark read" "$(nc mail filters | jq -r '"\(.filters | length) \(.filters[0].description)"')"
expect_contains "create_filter: no forwarding" "$(mapply '{"op":"create_filter","criteria":{"from":"a@b"},"action":{"forward":"x@evil.example"}}')" "aren't offered here"
expect_contains "create_filter: criteria needed" "$(mapply '{"op":"create_filter","action":{"archive":true}}')" "needs criteria"
expect_contains "create_filter: an action needed" "$(mapply '{"op":"create_filter","criteria":{"from":"a@b"},"action":{}}')" "needs an action"
out=$(mapply "{\"op\":\"replace_filter\",\"id\":\"$filter\",\"action\":{\"star\":true,\"category\":\"promotions\"}}")
expect_eq "replace_filter: the new one, the old one gone" "from:(news@shop.com) → star, categorise as Promotions|1" \
  "$(jq -r '.[0].result.description' <<<"$out")|$(nc mail filters | jq '.filters | length')"
expect_contains "replace_filter: says what it was" "$(jq -r '.[0].result.replaced' <<<"$out")" "label Shopping"
out=$(mapply "{\"op\":\"delete_filter\",\"id\":\"$(nc mail filters | jq -r '.filters[0].id')\"}")
expect_eq "delete_filter" "true 0" "$(jq -r '.[0].ok' <<<"$out") $(nc mail filters | jq '.filters | length')"

out=$(mapply '{"op":"trash","ids":["google-1:t4"]}')
expect_eq "trash: out of search" "true 0" "$(jq -r '.[0].ok' <<<"$out") $(nc mail search --query 'Archived' | jq '.threads | length')"
expect_eq "untrash: back" "1" "$(
  mapply '{"op":"untrash","ids":["google-1:t4"]}' >/dev/null
  nc mail search --query 'Archived' | jq '.threads | length'
)"
expect_contains "mail: an id of no account" "$(nc mail read nope:t1 || true)" "no account 'nope'"
expect_contains "mail: not an id" "$(nc mail read t1 || true)" "isn't an id from list"

cp "$tmp/secrets/account-google-1" "$tmp/token-backup"
jq '.access_token = "at-noscope@example.com" | .expiry = 4102444800' "$tmp/token-backup" >"$tmp/secrets/account-google-1"
set +e
out=$(nc mail unread)
rc=$?
set -e
expect_eq "mail: signed in before mail was asked for: sign in again (exit 2)" "2" "$rc"
expect_contains "mail: says why" "$out" "connected before mail was added"
cp "$tmp/token-backup" "$tmp/secrets/account-google-1"

# -- several accounts -----------------------------------------------------------

nc add google --no-browser >"$tmp/login2" &
login_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/login2" ] && break
  sleep 0.1
done
read -r redirect state < <(python3 -c 'import sys,urllib.parse as u; q=u.parse_qs(u.urlparse(sys.argv[1]).query); print(q["redirect_uri"][0], q["state"][0])' "$(head -1 "$tmp/login2" | jq -r .authUrl)")
curl -s "$redirect/?state=$state&code=work-code" >/dev/null
wait "$login_pid"
out=$(tail -1 "$tmp/login2")
expect_eq "second account" "google-2 work@example.com" "$(jq -r '"\(.account.id) \(.account.email)"' <<<"$out")"
expect_eq "second account: its own data" "0 1 3" "$(jq -r '"\(.contacts.accounts[0].count) \(.tasks.accounts[0].lists) \(.calendar.accounts[0].calendars)"' <<<"$out")"
expect_eq "status: two accounts, then the local one" "google-1,google-2,local" "$(nc status | jq -r '[.accounts[].id] | join(",")')"

out=$(apply '{"op":"create","account":"work@example.com","name":"Carla Boss","labels":["Job"]}')
expect_eq "create: in the account asked for" "google-2" "$(jq -r '.[0].result.account' <<<"$out")"
expect_contains "create: its id says its account" "$(jq -r '.[0].result.id' <<<"$out")" "google-2:"
expect_eq "contacts: merged" "4" "$(nc contacts list | jq -r .total)"
expect_eq "contacts list --account" "Carla Boss" "$(nc contacts list --account google-2 | jq -r '[.contacts[].name] | join(",")')"
expect_contains "a label name in two accounts" "$(apply '{"op":"rename_label","label":"Job","name":"Office"}')" "several accounts: give its id"
w_job=$(jq -r '.labels[] | select(.name == "Job" and .account == "google-2") | .id' "$cache")
expect_eq "rename_label: by id in one account" "Office" "$(apply "{\"op\":\"rename_label\",\"label\":\"$w_job\",\"name\":\"Office\"}" | jq -r '.[0].result.name')"
carla=$(nc contacts list --account google-2 | jq -r '.contacts[0].id')
job=$(jq -r '.labels[] | select(.name == "Job" and .account == "google-1") | .id' "$cache")
expect_contains "labels: another account's id refused" "$(apply "{\"op\":\"update\",\"id\":\"$carla\",\"labels\":[\"$job\"]}")" "in another account"
expect_contains "labels: an unknown label id" "$(apply "{\"op\":\"update\",\"id\":\"$carla\",\"labels\":[\"google-2:nope\"]}")" "no label 'google-2:nope'"

expect_contains "tasks: a list name in two accounts" "$(tapply '{"op":"create","list":"My Tasks","title":"x"}')" "several accounts: give its id"
out=$(tapply '{"op":"create","list":"google-2:L1","title":"quarterly report"}')
w_task=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "tasks create: in the list's account" "google-2:L1" "$(jq -r '.[0].result.listId' <<<"$out")"
expect_eq "tasks: merged lists, accounts in order, the local one last" "google-1,google-1,google-2,local" "$(nc tasks list | jq -r '[.lists[].account] | join(",")')"
expect_contains "tasks move: not between accounts" "$(tapply "{\"op\":\"move\",\"id\":\"$w_task\",\"list\":\"google-1:L1\"}")" "same account"
expect_eq "tasks list --account" "quarterly report" "$(nc tasks list --account work@example.com | jq -r '[.tasks[].title] | join(",")')"
out=$(nc mail search)
expect_eq "mail search: every Google account's merged" "google-1,google-2" "$(jq -r '[.threads[].id | split(":")[0]] | unique | join(",")' <<<"$out")"
expect_contains "mail labels: which account, when several" "$(nc mail labels || true)" "several Google accounts"
expect_eq "mail labels --account" "work@example.com" "$(nc mail labels --account work@example.com | jq -r .account)"
out=$(nc contacts sync)
expect_eq "sync: every account" "google-1,google-2,local" "$(jq -r '[.accounts[].account] | join(",")' <<<"$out")"

out=$(nc remove google-2)
expect_eq "remove one account: its data gone, the others' kept" "true 3 3" "$(jq -r .ok <<<"$out") $(nc contacts list | jq -r .total) $(nc tasks list | jq -r '.lists | length')"
expect_contains "remove: unknown account" "$(nc remove nope || true)" "no account 'nope'"

# -- signed out ----------------------------------------------------------------

jq '.access_token = "" | .refresh_token = "revoked"' "$tmp/secrets/account-google-1" >"$tmp/t" && mv "$tmp/t" "$tmp/secrets/account-google-1"
out=$(nc contacts sync || true)
expect_contains "revoked: says to connect again" "$out" "connect it again"
expect_eq "revoked: token forgotten, the account kept" "false google-1" "$(nc status | jq -r '"\(.accounts[0].connected) \(.accounts[0].id)"')"
expect_contains "revoked: the error kept for the app" "$(jq -r .error "$cache")" "connect it again"
expect_eq "revoked: the contacts kept" "3" "$(jq '.contacts | length' "$cache")"
echo '{"refresh_token":"rt-me@example.com","email":"me@example.com"}' >"$tmp/secrets/account-google-1"
out=$(nc remove me@example.com)
expect_eq "remove: the account and its copies gone, the local one stays" "true 1 0 1 1" "$(jq -r .ok <<<"$out") $(nc status | jq -r '"\(.accounts | length) \(.contacts.count) \(.tasks.lists) \(.calendar.calendars)"')"
expect_eq "remove: its token too" "no" "$([ -e "$tmp/secrets/account-google-1" ] && echo yes || echo no)"
expect_contains "remove: token revoked" "$(grep 'POST /revoke' "$log")" "token=rt-me"

# -- the local account ----------------------------------------------------------

expect_contains "local: can't be removed" "$(nc remove local || true)" "can't be removed"
local_data="$tmp/data/nixbook-accounts/local"
out=$(nc contacts apply '{"ops":[{"op":"create","name":"Zoé Durand","phones":["06 12"],"labels":["Famille"],"starred":true,"birthday":"04-02"},{"op":"create","notes":"nameless"}]}')
expect_eq "local contacts: create (no other account)" "true,false local" "$(jq -r '[.[].ok] | join(",")' <<<"$out") $(jq -r '.[0].result.account' <<<"$out")"
expect_eq "local contacts: in the data directory, not a copy" "Zoé Durand --04-02" "$(jq -r '.contacts[0] | "\(.name) \(.birthday)"' "$local_data/contacts.json")"
zoe=$(jq -r '.[0].result.id' <<<"$out")
out=$(nc contacts apply "{\"ops\":[{\"op\":\"update\",\"id\":\"$zoe\",\"emails\":[\"zoe@example.com\"],\"labels\":[\"Famille\",\"Amis\"]},{\"op\":\"rename_label\",\"label\":\"Famille\",\"name\":\"Family\"},{\"op\":\"unstar\",\"id\":\"$zoe\"}]}")
expect_eq "local contacts: update, labels" "true,true,true Amis,Family false" "$(jq -r '[.[].ok] | join(",")' <<<"$out") $(nc contacts get "$zoe" | jq -r '"\(.labels | sort | join(",")) \(.starred)"')"
out=$(nc contacts apply "{\"op\":\"set_photo\",\"id\":\"$zoe\",\"photo\":\"$tmp/photo.png\"}")
photo=$(jq -r '.[0].result.photo' <<<"$out")
expect_contains "local contacts: the photo a file in the data directory" "$photo" "file://$local_data/photos/${zoe#local:}-"
expect_eq "local contacts: the photo private, a JPEG" "600 720x360" "$(stat -c %a "${photo#file://}") $(img size "${photo#file://}")"
nc contacts apply "{\"op\":\"set_photo\",\"id\":\"$zoe\",\"photo\":\"\"}" >/dev/null
expect_eq "local contacts: the photo removed, its file too" " no" "$(nc contacts get "$zoe" | jq -r .photo) $([ -e "${photo#file://}" ] && echo yes || echo no)"
out=$(nc tasks apply '{"ops":[{"op":"create","title":"Water plants","due":"2026-10-20"},{"op":"create_list","name":"Home"},{"op":"create","list":"Home","title":"Fix the door"}]}')
expect_eq "local tasks: the first list, a new one" "Tasks Home" "$(nc tasks list | jq -r '[.lists[].name] | join(" ")')"
door=$(jq -r '.[2].result.id' <<<"$out")
nc tasks apply "{\"ops\":[{\"op\":\"done\",\"id\":\"$door\"},{\"op\":\"move\",\"id\":\"$door\",\"list\":\"Tasks\"}]}" >/dev/null
expect_eq "local tasks: done and moved" "true local:tasks" "$(nc tasks list --done | jq -r --arg d "$door" '.tasks[] | select(.id == $d) | "\(.done) \(.listId)"')"
expect_contains "local tasks: the last list stays" "$(nc tasks apply '{"op":"delete_list","list":"Tasks"}' | jq -r '.[0].ok')$(nc tasks apply '{"op":"delete_list","list":"Home"}' | jq -r '.[0].ok')" "truefalse"
out=$(nc calendar apply '{"op":"create","summary":"Yoga","start":"2026-10-19T18:00","recurrence":"weekly","reminders":[30]}')
yoga=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "local calendar: in Personal" "local:personal Europe/Paris" "$(jq -r '.[0].result | "\(.calendarId) \(.timeZone)"' <<<"$out")"
nc calendar apply "{\"op\":\"delete\",\"id\":\"$yoga\",\"occurrence\":\"2026-10-26T18:00:00+01:00\"}" >/dev/null
expect_eq "local calendar: a series, one occurrence cancelled" "19 02" "$(nc calendar events --from 2026-10-19 --to 2026-11-03 | jq -r '[.events[] | select(.summary == "Yoga") | .start[8:10]] | join(" ")')"
expect_eq "local calendar: its reminders" "[30]" "$(nc calendar events --from 2026-10-19 --to 2026-10-20 | jq -c '.events[0].reminders')"
# Sync rereads the files (another nixbook-accounts, a restored backup).
rm -rf "$tmp/state/nixbook-accounts/events.json"
expect_eq "local: the data survives its copy" "Yoga" "$(nc calendar events --from 2026-10-19 --to 2026-10-20 | jq -r '.events[0].summary')"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
