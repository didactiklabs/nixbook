#!/usr/bin/env bash
# Tests for nixbook-accounts' CalDAV/CardDAV provider (accounts/internal/dav)
# against a real server, Radicale:
#   - adding an account: a refused password, the address books and to-do
#     calendars found (an events-only calendar left out), a first sync;
#   - contacts: create (vCard fields, labels as categories, the star),
#     update (only the fields given, the card's other lines kept), changes
#     made by another client picked up by sync-collection, labels renamed
#     and deleted, delete;
#   - tasks: create with a due date and notes, done/undone, subtasks,
#     lists made, renamed, deleted, a task moved, another client's to-do;
#   - calendar: the calendars that hold events, events created (single, a
#     series with reminders, all-day), one occurrence deleted (EXDATE) or
#     changed (RECURRENCE-ID), the series renamed, another client's event
#     (its alarm, its meeting link), moving, deleting;
#   - an account signed out by its server (a changed password).
# Needs bash, jq, curl, radicale, and go unless $NIXBOOK_ACCOUNTS names a
# built binary. Run: bash tests/dav.sh
set -euo pipefail
export -n out 2>/dev/null || true

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
rad=""
cleanup() {
  [ -z "$rad" ] || kill "$rad" 2>/dev/null || true
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

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
U="http://127.0.0.1:$port"
mkdir -p "$tmp/store" "$tmp/secrets" "$tmp/state"
echo "me:secret" >"$tmp/users"
cat >"$tmp/config" <<EOF
[server]
hosts = 127.0.0.1:$port
[auth]
type = htpasswd
htpasswd_filename = $tmp/users
htpasswd_encryption = plain
[storage]
filesystem_folder = $tmp/store
[logging]
level = warning
EOF
radicale --config "$tmp/config" >"$tmp/radicale.log" 2>&1 &
rad=$!
for _ in $(seq 100); do
  curl -s -o /dev/null "$U/" && break
  sleep 0.1
done

dav() { curl -s -u me:secret "$@"; }
# What a real server has: an address book, a to-do list, an events calendar.
dav -X MKCOL "$U/me/contacts/" -H 'Content-Type: application/xml' -o /dev/null --data '<?xml version="1.0"?><d:mkcol xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav"><d:set><d:prop><d:resourcetype><d:collection/><card:addressbook/></d:resourcetype><d:displayname>Contacts</d:displayname></d:prop></d:set></d:mkcol>'
mkcal() { dav -X MKCALENDAR "$U/me/$1/" -H 'Content-Type: application/xml' -o /dev/null --data "<?xml version=\"1.0\"?><c:mkcalendar xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:set><d:prop><d:displayname>$2</d:displayname><c:supported-calendar-component-set><c:comp name=\"$3\"/></c:supported-calendar-component-set></d:prop></d:set></c:mkcalendar>"; }
mkcal tasks Reminders VTODO
mkcal events Events VEVENT
mkcal work Work VEVENT

bin="${NIXBOOK_ACCOUNTS:-}"
if [ -z "$bin" ]; then
  bin="$tmp/nixbook-accounts"
  (cd "$root/accounts" && CGO_ENABLED=0 go build -o "$bin" .)
fi
export NIXBOOK_ACCOUNTS_SECRETS_DIR="$tmp/secrets" XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data" TZ=Europe/Paris
na() { "$bin" "$@"; }
cache="$tmp/state/nixbook-accounts/contacts.json"
local_id() { echo "${1#dav-1:}"; }

# -- adding the account -------------------------------------------------------

out=$(echo nope | na add dav --preset custom --url "$U" --username me --password-stdin || true)
expect_contains "add: a refused password" "$out" "refused the password"
expect_eq "add: refused, nothing saved (the local account only)" "local" "$(na status | jq -r '[.accounts[].id] | join(",")')"
expect_contains "add: the password not in the arguments" "$(na add dav --preset custom --url "$U" --username me || true)" "--password-stdin"
expect_contains "add: a server kind" "$(echo x | na add dav --preset gmail --url "$U" --username me --password-stdin || true)" "unknown server kind 'gmail'"
expect_contains "add: custom needs the address" "$(echo x | na add dav --preset custom --username me --password-stdin || true)" "needs the server's address"
out=$(echo secret | na add dav --preset custom --url "$U" --username me --name "Home server" --password-stdin)
expect_eq "add: the account" "dav-1 Home server me" "$(jq -r '.account | "\(.id) \(.name) \(.username)"' <<<"$out")"
expect_eq "add: its collections found" "/me/ /me/" "$(jq -r '.account | "\(.contactsHome) \(.calendarHome)"' <<<"$out")"
expect_eq "add: first sync, the to-do list only (and the local one)" "true 0 2" "$(jq -r '"\(.contacts.accounts[0].full) \(.contacts.count) \(.tasks.lists)"' <<<"$out")"
expect_eq "add: the password in the keyring" '{"password":"secret"}' "$(cat "$tmp/secrets/account-dav-1")"
expect_eq "status: connected, both services" "true true true" "$(na status | jq -r '.accounts[0] | "\(.connected) \(.contacts) \(.tasks)"')"
expect_eq "status: the presets" "Fastmail,iCloud" "$(na status | jq -r '[.providers.dav.presets.fastmail.name, .providers.dav.presets.icloud.name] | join(",")')"
out=$(echo secret | na add dav --preset custom --url "$U" --username me --password-stdin)
expect_eq "add: the same server and user again, the same account" "dav-1 2" "$(jq -r .account.id <<<"$out") $(na status | jq '.accounts | length')"

# -- contacts ------------------------------------------------------------------

apply() { na contacts apply "$1"; }
out=$(apply '{"op":"create","name":"Élodie Martin","emails":[{"value":"elodie@example.com","type":"work"}],"phones":["+33 6 12 34 56 78"],"organization":"Acme","birthday":"1990-04-02","labels":["Family"],"starred":true,"addresses":[{"street":"1 rue X","city":"Lyon","postalCode":"69001","type":"home"}],"notes":"Met in Lyon"}')
id1=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "create: the contact back" "Élodie Martin|Élodie|Martin|work|1990-04-02|true|Acme|1 rue X
69001 Lyon" "$(jq -r '.[0].result | "\(.name)|\(.givenName)|\(.familyName)|\(.emails[0].type)|\(.birthday)|\(.starred)|\(.organization)|\(.addresses[0].value)"' <<<"$out")"
expect_eq "create: labels by name, as categories" '["dav-1:Family"]' "$(jq -c '.[0].result.labels' <<<"$out")"
card=$(dav "$U$(local_id "$id1")")
expect_contains "create: a vCard on the server" "$card" "FN:Élodie Martin"
expect_contains "create: the star a category" "$card" "CATEGORIES:Family\,Starred"
expect_contains "create: the address structured" "$card" "ADR;TYPE=home:;;1 rue X;Lyon;;69001;"

# Another client adds a line the app doesn't know: an update keeps it.
dav -X PUT "$U$(local_id "$id1")" -H 'Content-Type: text/vcard' -o /dev/null --data-binary "$(printf '%s\n' "$card" | sed 's/^END:VCARD/X-SOCIAL:@elodie\nEND:VCARD/')"
out=$(apply "{\"op\":\"update\",\"id\":\"$id1\",\"title\":\"CTO\",\"phones\":[{\"value\":\"+33 6 12 34 56 78\",\"type\":\"mobile\"},\"0123\"]}")
expect_eq "update: the fields given" "CTO mobile 0123" "$(jq -r '.[0].result | "\(.title) \(.phones[0].type) \(.phones[1].value)"' <<<"$out")"
card=$(dav "$U$(local_id "$id1")")
expect_contains "update: the other lines kept" "$card" "X-SOCIAL:@elodie"
expect_contains "update: phone types as vCard's" "$card" "TEL;TYPE=cell:+33 6 12 34 56 78"
out=$(apply "{\"op\":\"unstar\",\"id\":\"$id1\"}")
expect_eq "unstar: the labels stay" 'false ["dav-1:Family"]' "$(jq -r '.[0].result | "\(.starred) \(.labels | tojson)"' <<<"$out")"
expect_contains "update: a bad birthday" "$(apply "{\"op\":\"update\",\"id\":\"$id1\",\"birthday\":\"April\"}")" "YYYY-MM-DD or MM-DD"
python3 "$root/tests/test-image.py" png "$tmp/photo.png"
out=$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"$tmp/photo.png\"}")
photo=$(jq -r '.[0].result.photo' <<<"$out")
expect_contains "set_photo: inline in the vCard" "$(dav "$U$(local_id "$id1")")" "PHOTO;ENCODING=b;TYPE=JPEG:/9j/"
expect_contains "set_photo: shown from a file, not the copy" "$photo" "file://$tmp/state/nixbook-accounts/photos/"
expect_eq "set_photo: the file a JPEG" "720x360" "$(python3 "$root/tests/test-image.py" size "${photo#file://}")"
expect_eq "set_photo: the other lines kept" "1" "$(dav "$U$(local_id "$id1")" | grep -c X-SOCIAL)"
out=$(apply "{\"op\":\"set_photo\",\"id\":\"$id1\",\"photo\":\"\"}")
expect_eq "set_photo: removed" "0 " "$(dav "$U$(local_id "$id1")" | grep -c PHOTO) $(jq -r '.[0].result.photo' <<<"$out")"

out=$(na contacts sync)
expect_eq "sync: with the sync token" "false" "$(jq -r '.accounts[0].full' <<<"$out")"
# Another client: a new card, then one deleted.
dav -X PUT "$U/me/contacts/bob.vcf" -H 'Content-Type: text/vcard' -o /dev/null --data-binary $'BEGIN:VCARD\r\nVERSION:3.0\r\nUID:bob\r\nFN:Bob Stone\r\nN:Stone;Bob;;;\r\nTEL;TYPE=home:06 99 88 77 66\r\nBDAY:--0702\r\nCATEGORIES:Family\r\nEND:VCARD\r\n'
out=$(na contacts sync)
expect_eq "sync: another client's card" "1 2" "$(jq -r '"\(.accounts[0].changed) \(.count)"' <<<"$out")"
expect_eq "sync: its fields" "Bob Stone|home|--07-02" "$(na contacts list --query bob | jq -r '.contacts[0] | "\(.name)|\(.phones[0].type)|\(.birthday)"')"
expect_eq "labels: counted" "Family:2" "$(jq -r '[.labels[] | "\(.name):\(.count)"] | join(",")' "$cache")"
out=$(apply '{"op":"rename_label","label":"Family","name":"Famille"}')
expect_eq "rename_label: every contact's category" "Famille 2" "$(jq -r '.[0].result | "\(.name) \(.count)"' <<<"$out")"
expect_contains "rename_label: on the server" "$(dav "$U/me/contacts/bob.vcf")" "CATEGORIES:Famille"
out=$(apply '{"op":"delete_label","label":"Famille"}')
expect_eq "delete_label: the contacts stay" "2 0" "$(jq -r '"\(.contacts | length) \(.labels | length)"' "$cache")"
dav -X DELETE "$U/me/contacts/bob.vcf" -o /dev/null
out=$(na contacts sync)
# Changed: the deletion, and the label renames made since the last sync.
expect_eq "sync: another client's deletion" "2 1" "$(jq -r '"\(.accounts[0].changed) \(.count)"' <<<"$out")"
out=$(apply "{\"op\":\"delete\",\"id\":\"$id1\"}")
expect_eq "delete" "Élodie Martin 404" "$(jq -r '.[0].result.name' <<<"$out") $(curl -s -o /dev/null -w '%{http_code}' -u me:secret "$U$(local_id "$id1")")"

# -- tasks ---------------------------------------------------------------------

tapply() { na tasks apply "$1"; }
out=$(tapply '{"ops":[{"op":"create","title":"Buy milk","due":"2026-10-20","notes":"2 L"},{"op":"create_list","name":"Work"}]}')
t1=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "tasks create: in the first list" "Buy milk|2026-10-20|2 L|dav-1:/me/tasks/" "$(jq -r '.[0].result | "\(.title)|\(.due)|\(.notes)|\(.listId)"' <<<"$out")"
ics=$(dav "$U$(local_id "$t1")")
expect_contains "tasks create: a VTODO, its due a date" "$ics" "DUE;VALUE=DATE:20261020"
work=$(jq -r '.[1].result.id' <<<"$out")
expect_eq "tasks create_list: a to-do calendar" "Work" "$(na tasks list | jq -r --arg w "$work" '.lists[] | select(.id == $w) | .name')"
out=$(tapply "{\"ops\":[{\"op\":\"done\",\"id\":\"$t1\"},{\"op\":\"create\",\"title\":\"milk brand\",\"parent\":\"$t1\"}]}")
expect_eq "tasks done: completed now" "true" "$(jq -r '.[0].result | .done and (.completed != "")' <<<"$out")"
expect_contains "tasks done: on the server" "$(dav "$U$(local_id "$t1")")" "STATUS:COMPLETED"
expect_eq "tasks create: a subtask" "$t1" "$(jq -r '.[1].result.parent' <<<"$out")"
out=$(tapply "{\"op\":\"update\",\"id\":\"$t1\",\"due\":\"\",\"title\":\"Buy oat milk\"}")
expect_eq "tasks update: due cleared" "|Buy oat milk|2 L" "$(jq -r '.[0].result | "\(.due)|\(.title)|\(.notes)"' <<<"$out")"
out=$(tapply "{\"op\":\"undone\",\"id\":\"$t1\"}")
expect_eq "tasks undone" "false|" "$(jq -r '.[0].result | "\(.done)|\(.completed)"' <<<"$out")"
# Another client's to-do.
dav -X PUT "$U/me/tasks/other.ics" -H 'Content-Type: text/calendar' -o /dev/null --data-binary $'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nBEGIN:VTODO\r\nUID:other\r\nDTSTAMP:20261017T100000Z\r\nSUMMARY:Call the plumber\r\nDUE:20261021T090000Z\r\nEND:VTODO\r\nEND:VCALENDAR\r\n'
out=$(na tasks sync)
expect_eq "tasks sync: another client's to-do" "3 3" "$(jq -r '"\(.lists) \(.count)"' <<<"$out")"
expect_eq "tasks sync: a date-time due as its day" "2026-10-21" "$(na tasks list | jq -r '.tasks[] | select(.title == "Call the plumber") | .due')"
expect_eq "tasks sync: the subtask's parent" "$t1" "$(na tasks list | jq -r '.tasks[] | select(.title == "milk brand") | .parent')"
out=$(tapply "{\"op\":\"move\",\"id\":\"$t1\",\"list\":\"Work\"}")
moved=$(jq -r '.[0].result.id' <<<"$out")
expect_eq "tasks move: to the other list" "$work" "$(jq -r '.[0].result.listId' <<<"$out")"
expect_eq "tasks move: on the server" "404 200" "$(curl -s -o /dev/null -w '%{http_code}' -u me:secret "$U$(local_id "$t1")") $(curl -s -o /dev/null -w '%{http_code}' -u me:secret "$U$(local_id "$moved")")"
out=$(tapply "{\"op\":\"rename_list\",\"list\":\"$work\",\"name\":\"Job\"}")
na tasks sync >/dev/null
expect_eq "tasks rename_list: on the server" "Job" "$(na tasks list | jq -r --arg w "$work" '.lists[] | select(.id == $w) | .name')"
out=$(tapply "{\"op\":\"delete\",\"id\":\"$moved\"}")
expect_eq "tasks delete" "Buy oat milk" "$(jq -r '.[0].result.title' <<<"$out")"
expect_eq "tasks delete: its subtask with it" "0" "$(na tasks list | jq '[.tasks[] | select(.title == "milk brand")] | length')"
out=$(tapply '{"op":"delete_list","list":"Job"}')
expect_eq "tasks delete_list" "Job 1 2" "$(jq -r '.[0].result.name' <<<"$out") $(na tasks list | jq '.tasks | length') $(na tasks list | jq '.lists | length')"

# -- calendar --------------------------------------------------------------------

capply() { na calendar apply "$1"; }
expect_eq "calendar: the calendars with events" "Events,Work" "$(na calendar calendars | jq -r '[.calendars[] | select(.account == "dav-1") | .name] | sort | join(",")')"
work_cal=$(na calendar calendars | jq -r '.calendars[] | select(.name == "Work") | .id')
out=$(capply "{\"ops\":[{\"op\":\"create\",\"calendar\":\"Events\",\"summary\":\"Dentist\",\"start\":\"2026-11-03T09:00\",\"location\":\"12 rue X\"},{\"op\":\"create\",\"calendar\":\"$work_cal\",\"summary\":\"Standup\",\"start\":\"2026-10-19T09:30\",\"end\":\"2026-10-19T09:45\",\"recurrence\":\"weekdays\",\"reminders\":[10]},{\"op\":\"create\",\"calendar\":\"Events\",\"summary\":\"Holidays\",\"start\":\"2026-12-24\",\"end\":\"2026-12-26\"}]}")
expect_eq "calendar create: each" "true,true,true" "$(jq -r '[.[].ok] | join(",")' <<<"$out")"
dentist=$(jq -r '.[0].result.id' <<<"$out")
standup=$(jq -r '.[1].result.id' <<<"$out")
ics=$(dav "$U$(local_id "$standup")")
expect_contains "calendar create: a series in the local zone" "$ics" "DTSTART;TZID=Europe/Paris:20261019T093000"
expect_contains "calendar create: its rule" "$ics" "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
expect_contains "calendar create: its reminder an alarm" "$ics" "TRIGGER:-PT10M"
expect_eq "calendar create: all-day, its last day given" "2026-12-24 2026-12-27" "$(jq -r '.[2].result | "\(.start) \(.end)"' <<<"$out")"
out=$(na calendar events --from 2026-10-26 --to 2026-10-31)
expect_eq "calendar events: the series, across the clock change" "26,27,28,29,30 09:30:00+01:00" "$(jq -r '[.events[] | .start[8:10]] | join(",")' <<<"$out") $(jq -r '.events[0].start[11:]' <<<"$out")"
out=$(capply "{\"ops\":[{\"op\":\"delete\",\"id\":\"$standup\",\"occurrence\":\"2026-10-27T09:30:00+01:00\"},{\"op\":\"update\",\"id\":\"$standup\",\"occurrence\":\"2026-10-28T09:30:00+01:00\",\"start\":\"2026-10-28T11:00\",\"summary\":\"Standup (late)\"}]}")
expect_eq "calendar: one occurrence deleted, one changed" "true,true" "$(jq -r '[.[].ok] | join(",")' <<<"$out")"
ics=$(dav "$U$(local_id "$standup")")
expect_contains "calendar: the deleted one an EXDATE" "$ics" "EXDATE;TZID=Europe/Paris:20261027T093000"
expect_contains "calendar: the changed one its own VEVENT" "$ics" "RECURRENCE-ID;TZID=Europe/Paris:20261028T093000"
capply "{\"op\":\"update\",\"id\":\"$standup\",\"summary\":\"Daily standup\"}" >/dev/null
expect_eq "calendar: the series renamed, the changed one kept" "Daily standup 26,Standup (late) 28,Daily standup 29,Daily standup 30" "$(na calendar events --from 2026-10-26 --to 2026-10-31 | jq -r '[.events[] | "\(.summary) \(.start[8:10])"] | join(",")')"
dav -X PUT "$U/me/events/lunch.ics" -H 'Content-Type: text/calendar' -o /dev/null --data-binary $'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\nBEGIN:VEVENT\r\nUID:lunch\r\nDTSTAMP:20261017T100000Z\r\nDTSTART:20261104T120000Z\r\nDURATION:PT30M\r\nSUMMARY:Lunch\r\nDESCRIPTION:Call: https://meet.google.com/abc-defg-hij\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n'
na calendar sync >/dev/null
expect_eq "calendar sync: another client's event" "13:00:00+01:00 13:30:00+01:00 [15] https://meet.google.com/abc-defg-hij" "$(na calendar events --from 2026-11-04 --to 2026-11-05 | jq -r '.events[] | select(.summary == "Lunch") | "\(.start[11:]) \(.end[11:]) \(.reminders | tojson) \(.meetingUrl)"')"
out=$(capply "{\"op\":\"update\",\"id\":\"$dentist\",\"calendar\":\"Work\"}")
expect_eq "calendar update: moved to another calendar" "$work_cal" "$(na calendar events --from 2026-11-03 --to 2026-11-04 | jq -r '.events[] | select(.summary == "Dentist") | .calendarId')"
moved=$(na calendar events --from 2026-11-03 --to 2026-11-04 | jq -r '.events[] | select(.summary == "Dentist") | .id')
expect_eq "calendar update: moved on the server" "404 200" "$(curl -s -o /dev/null -w '%{http_code}' -u me:secret "$U$(local_id "$dentist")") $(curl -s -o /dev/null -w '%{http_code}' -u me:secret "$U$(local_id "$moved")")"
capply "{\"op\":\"delete\",\"id\":\"$standup\"}" >/dev/null
na calendar sync >/dev/null
expect_eq "calendar delete: the series" "Dentist,Holidays,Lunch" "$(na calendar events --from 2026-10-01 --to 2027-01-01 | jq -r '[.events[].summary] | unique | join(",")')"

# -- signed out ----------------------------------------------------------------

echo "me:changed" >"$tmp/users"
sleep 1
out=$(na contacts sync || true)
expect_contains "a changed password: sign in again" "$out" "refused the password"
expect_eq "a changed password: the account says so" "true" "$(na status | jq -r '.accounts[0].contactsError | test("refused")')"
out=$(echo changed | na add dav --preset custom --url "$U" --username me --password-stdin)
expect_eq "signed in again: the same account, synced" "dav-1 0" "$(jq -r .account.id <<<"$out") $(jq -r .contacts.count <<<"$out")"
na remove dav-1 >/dev/null
expect_eq "remove: the account, its copies, its password (the local account stays)" "1 0 1 1 no" "$(na status | jq -r '"\(.accounts | length) \(.contacts.count) \(.tasks.lists) \(.calendar.calendars)"') $([ -e "$tmp/secrets/account-dav-1" ] && echo yes || echo no)"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
