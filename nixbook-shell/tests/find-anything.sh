#!/usr/bin/env bash
# Tests for "Find it" (scripts/desktop-mcp.py: the find_anything tool and
# `nixbook-desktop-mcp find`, what the launcher's find prefix calls), on
# fixtures, no model and no shell:
#   - the time words (en/fr/de/vi) as ranges;
#   - each source: recent files (names, the text of small files and PDFs
#     through a stub pdftotext), Zen's places.sqlite (history, bookmarks),
#     cliphist (a stub), the notification history, the conversations
#     with DAI;
#   - what is never given: hidden folders, the home itself, files named
#     like secrets, codes and keys, blocked sites, links carrying a key;
#   - the ranking (the kind a request names, file types), the tool's reply,
#     policies.ai (nothing at 0, the plain search at 2), the helper.
# Needs bash, python3 and jq. Run: bash tests/find-anything.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to contain: $3"$'\n'"actual: $2" ;; esac
}
expect_not_contains() {
  case "$2" in *"$3"*) fail "$1" "unexpected: $3"$'\n'"in: $2" ;; *) pass "$1" ;; esac
}

home="$tmp/home"
mkdir -p "$home/Downloads/talks" "$home/Documents" "$home/Desktop" "$home/Pictures/Screenshots" "$home/.secret" \
  "$tmp/state/quickshell/user/ai/history" "$tmp/cfg/nixbook-shell" \
  "$tmp/cfg/zen/default" "$tmp/run" "$tmp/bin"
export HOME="$home" XDG_STATE_HOME="$tmp/state" XDG_CONFIG_HOME="$tmp/cfg" XDG_RUNTIME_DIR="$tmp/run"
export XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache" PATH="$tmp/bin:$PATH"
unset NIXBOOK_DESKTOP_MCP_CONFIG
policy() { echo "{\"policies\": {\"ai\": $1}}" >"$tmp/cfg/nixbook-shell/config.json"; }
policy 1
dm() { python3 -I "$root/scripts/desktop-mcp.py" "$@"; }
find_json() { dm find "$@" --json; }
titles() { jq -r '[.results[].title] | join(" | ")'; }

# Dates the fixtures use: the latest Monday (today when it is one), last
# week's Tuesday, two months ago; epoch seconds at 00:30 local time.
read -r monday lastweek old < <(python3 -c '
import datetime as d
t = d.date.today(); mon = t - d.timedelta(days=t.weekday())
at = lambda x: int(d.datetime(x.year, x.month, x.day, 0, 30).timestamp())
print(at(mon), at(mon - d.timedelta(days=6)), at(t - d.timedelta(days=60)))')
stamp() { touch -d "@$1" "$2"; }

# -- time words -----------------------------------------------------------------
when() { python3 -I -c '
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("dm", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r, rest = m.find_when(sys.argv[2], float(sys.argv[3]))
print(json.dumps({"label": r and r["label"], "from": r and r["from"], "rest": " ".join(rest.split())}))' \
  "$root/scripts/desktop-mcp.py" "$1" "${2:-1793793600}"; }
# 1793793600 = Wednesday 2026-11-04 12:00 UTC; the labels don't depend on the zone.
expect_eq "en: yesterday" '"yesterday"' "$(when "what did we decide in yesterday's call" | jq .label)"
expect_eq "en: the time words leave the request" '"what did we decide in s call"' \
  "$(when "what did we decide in yesterday's call" | jq .rest)"
expect_eq "en: Monday, the latest one" '"Monday 2026-11-02"' "$(when "that speech PDF I downloaded Monday" | jq .label)"
expect_eq "en: last Monday, before today" '"Monday 2026-11-02"' "$(when "last monday" | jq .label)"
expect_eq "en: Wednesday said on a Wednesday is today" '"Wednesday 2026-11-04"' "$(when "on wednesday" | jq .label)"
expect_eq "en: last Wednesday on a Wednesday is a week ago" '"Wednesday 2026-10-28"' "$(when "last wednesday" | jq .label)"
expect_eq "fr: hier" '"yesterday"' "$(when "le lien d'hier" | jq .label)"
expect_eq "fr: avant-hier is not hier" '"the day before yesterday"' "$(when "avant-hier" | jq .label)"
expect_eq "fr: lundi dernier" '"Monday 2026-11-02"' "$(when "le PDF de lundi dernier" | jq .label)"
expect_eq "fr: la semaine dernière" '"last week"' "$(when "la semaine dernière" | jq .label)"
expect_eq "fr: aujourd'hui" '"today"' "$(when "aujourd'hui" | jq .label)"
expect_eq "fr: il y a 3 jours" '"2026-11-01"' "$(when "il y a 3 jours" | jq .label)"
expect_eq "de: gestern" '"yesterday"' "$(when "was haben wir gestern besprochen" | jq .label)"
expect_eq "de: letzte Woche" '"last week"' "$(when "letzte Woche" | jq .label)"
expect_eq "de: am Montag" '"Monday 2026-11-02"' "$(when "die PDF vom Montag" | jq .label)"
expect_eq "de: heute Morgen" '"this morning"' "$(when "heute Morgen" | jq .label)"
expect_eq "vi: hôm qua" '"yesterday"' "$(when "cuộc họp hôm qua" | jq .label)"
expect_eq "vi: thứ hai" '"Monday 2026-11-02"' "$(when "tệp pdf thứ hai" | jq .label)"
expect_eq "vi: tuần trước" '"last week"' "$(when "tuần trước" | jq .label)"
expect_eq "vi: hôm nay" '"today"' "$(when "hôm nay" | jq .label)"
expect_eq "an ISO date" '"2026-10-28"' "$(when "the 2026-10-28 invoice" | jq .label)"
expect_eq "no time word: no range" 'null' "$(when "the dinner link" | jq .label)"
expect_eq "last month" '"last month"' "$(when "le mois dernier" | jq .label)"

# -- fixtures ----------------------------------------------------------------------
printf 'Ladies and gentlemen, the speech for the gala starts here.\n' >"$home/Downloads/talks/notes.txt"
stamp "$monday" "$home/Downloads/talks/notes.txt"
printf '%%PDF-1.4 fake\n' >"$home/Downloads/gala-2026.pdf"
stamp "$monday" "$home/Downloads/gala-2026.pdf"
printf '%%PDF-1.4 fake\n' >"$home/Downloads/speech-old.pdf"
stamp "$old" "$home/Downloads/speech-old.pdf"
printf 'speech\n' >"$home/Downloads/speech-draft.docx"
stamp "$monday" "$home/Downloads/speech-draft.docx"
printf 'speech\n' >"$home/.secret/speech.pdf"
printf 'speech\n' >"$home/speech-in-home.pdf"
printf 'k\n' >"$home/Documents/passwords-speech.txt"
printf 'k\n' >"$home/Documents/speech.kdbx"
printf 'api_key = sk-ant-abcdefghijklmnopqrstuvwx\nspeech budget\n' >"$home/Documents/budget.md"
stamp "$lastweek" "$home/Documents/budget.md"
printf 'png\n' >"$home/Pictures/Screenshots/Screenshot-dinner.png"
# The Desktop pointed at the home (a common user-dirs.dirs): never walked.
# shellcheck disable=SC2016 # $HOME as user-dirs.dirs has it, expanded by its reader
printf 'XDG_DESKTOP_DIR="$HOME"\nXDG_DOWNLOAD_DIR="$HOME/Downloads"\n' >"$tmp/cfg/user-dirs.dirs"
cat >"$tmp/bin/pdftotext" <<'EOF'
#!/usr/bin/env bash
# The second to last argument is the PDF.
case "${*: -2:1}" in
*gala-2026.pdf) echo "Gala evening: the speech of the president" ;;
*) echo "nothing here" ;;
esac
EOF
cat >"$tmp/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-preview-width" ] && exit 1
printf '9\tthe dinner menu: https://chezpaul.example/menu\n8\t483920\n7\tHunter2Pass99\n6\tsk-ant-abcdefghijklmnopqrstuvwxyz\n5\t[[ binary data 12 KiB png 10x10 ]]\n4\tFR7630006000011234567890189\n'
EOF
chmod +x "$tmp/bin/pdftotext" "$tmp/bin/cliphist"

python3 - "$tmp/cfg/zen/default/places.sqlite" "$monday" "$lastweek" <<'EOF'
import sqlite3, sys
db, monday, lastweek = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
con = sqlite3.connect(db)
con.executescript("""CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER);
CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, title TEXT, dateAdded INTEGER);""")
places = [(1, "https://chezpaul.example/reservation", "Chez Paul — dinner reservations"),
          (2, "https://www.mybank-banque.example/dinner", "Dinner offers"),
          (3, "https://shop.example/dinner?token=abc123", "Dinner shop"),
          (4, "https://news.example/speech-analysis", "Analysis of the gala speech"),
          (5, "file:///home/x/dinner.html", "Local dinner page")]
con.executemany("INSERT INTO moz_places VALUES (?, ?, ?)", places)
con.executemany("INSERT INTO moz_historyvisits (place_id, visit_date) VALUES (?, ?)",
                [(1, monday * 10**6), (2, monday * 10**6), (3, monday * 10**6), (4, lastweek * 10**6), (5, monday * 10**6)])
con.execute("INSERT INTO moz_bookmarks (type, fk, title, dateAdded) VALUES (1, 4, 'Gala speech analysis', ?)",
            (lastweek * 10**6,))
con.commit()
EOF
printf '[Profile0]\nName=default\nIsRelative=1\nPath=default\nDefault=1\n' >"$tmp/cfg/zen/profiles.ini"

python3 - "$tmp/state/quickshell/user/notification-history.json" "$monday" "$lastweek" <<'EOF'
import json, sys
path, monday, lastweek = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
json.dump([
    {"appName": "Vesktop", "summary": "Alex", "body": "dinner on friday? https://chezpaul.example/menu", "time": monday * 1000},
    {"appName": "Messages", "summary": "Bank", "body": "Your verification code is 483920", "time": monday * 1000},
    {"appName": "Revolut", "summary": "Dinner", "body": "You paid 40 EUR", "time": monday * 1000},
    {"appName": "Vesktop", "summary": "Alex", "body": "<b>lunch</b> instead? https://shop.example/x?token=zz", "time": lastweek * 1000},
], open(path, "w"))
EOF
python3 - "$tmp/state/quickshell/user/ai/history/index.json" "$monday" <<'EOF'
import json, sys
json.dump({"version": 1, "chats": [
    {"id": "c1", "title": "write the gala speech intro", "created": int(sys.argv[2]) * 1000, "updated": int(sys.argv[2]) * 1000},
    {"id": "c2", "title": "my code is 123456", "updated": int(sys.argv[2]) * 1000}]}, open(sys.argv[1], "w"))
EOF

# -- the examples -------------------------------------------------------------
out=$(find_json "that speech PDF I downloaded Monday")
expect_eq "speech PDF Monday: the one whose text says it" "gala-2026.pdf" "$(titles <<<"$out")"
expect_eq "its action opens it" "$home/Downloads/gala-2026.pdf" "$(jq -r '.results[0].action.open' <<<"$out")"
expect_contains "its snippet: the line that says it" "$(jq -r '.results[0].snippet' <<<"$out")" "speech of the president"
expect_eq "the range said" "Monday" "$(jq -r '.range.label | split(" ")[0]' <<<"$out")"

out=$(find_json "the link Alex sent about dinner")
expect_eq "the link Alex sent: the message first" "notification" "$(jq -r '.results[0].kind' <<<"$out")"
expect_eq "its link opened" "https://chezpaul.example/menu" "$(jq -r '.results[0].action.open' <<<"$out")"
expect_contains "the dinner page of the history too" "$(titles <<<"$out")" "Chez Paul — dinner reservations"
expect_not_contains "a bank's site never" "$(titles <<<"$out")" "Dinner offers"
expect_not_contains "a link with a token never" "$(titles <<<"$out")" "Dinner shop"
expect_not_contains "nor a file:// page" "$(titles <<<"$out")" "Local dinner page"
expect_not_contains "a payment app's notification never" "$(jq -c . <<<"$out")" "You paid"

# -- each source, and what is never given -------------------------------------------
out=$(find_json speech)
all=$(jq -c . <<<"$out")
expect_contains "a text file by its text" "$(titles <<<"$out")" "notes.txt"
expect_contains "a file by its name" "$(titles <<<"$out")" "speech-draft.docx"
expect_contains "a bookmark" "$(titles <<<"$out")" "Gala speech analysis"
expect_contains "a page of the history" "$(titles <<<"$out")" "Analysis of the gala speech"
expect_contains "a conversation with DAI" "$(titles <<<"$out")" "write the gala speech intro"
expect_not_contains "never a hidden folder" "$all" "/.secret/"
expect_not_contains "never the home itself (the Desktop pointed there)" "$all" "speech-in-home"
expect_not_contains "never a file named like a password list" "$all" "passwords-speech"
expect_not_contains "never a password store" "$all" "speech.kdbx"
expect_contains "a file with a key: found by its other words" "$(titles <<<"$out")" "budget.md"
expect_not_contains "its key never shown" "$all" "sk-ant-"
expect_eq "the screenshots' folder too" "Screenshot-dinner.png" "$(find_json screenshot dinner | jq -r '.results[0].title')"

out=$(find_json "dinner" --kinds clipboard)
expect_eq "the clipboard history: the text, its id" "9" "$(jq -r '.results[0].action.cliphist' <<<"$out")"
out=$(find_json "" --kinds clipboard --max 30)
expect_eq "a code, a password, a key, an IBAN, an image: never" "1" "$(jq '.results | length' <<<"$out")"
out=$(find_json "code" --kinds notifications,chats)
expect_eq "a code in a notification or a chat title: never" "0" "$(jq '.results | length' <<<"$out")"

expect_eq "a type said: only files of it" "gala-2026.pdf speech-old.pdf" \
  "$(find_json speech pdf | jq -r '[.results[].title] | sort | join(" ")')"
expect_eq "a range: only what is in it" "budget.md" "$(find_json speech last week --kinds files | titles)"
expect_eq "--when apart from the query" "budget.md" "$(find_json speech --when "letzte Woche" --kinds files | titles)"
expect_eq "a type alone: the newest of it" "gala-2026.pdf" "$(find_json "the pdf from monday" | titles)"
expect_eq "nothing: an empty list" "0" "$(find_json zzyzx | jq '.results | length')"
expect_eq "a bad --kinds" "2" "$(
  dm find x --kinds nope >/dev/null 2>&1
  echo $?
)"

# -- the tool --------------------------------------------------------------------------
echo '{"tools": ["observe"]}' >"$tmp/cfg/nixbook-shell/desktop-mcp.json"
dm resume >/dev/null
out=$(dm call find_anything '{"query": "the link Alex sent about dinner"}')
expect_contains "the tool: the best first, with what to do" "$out" "1. [notification] Alex — Vesktop"
expect_contains "the tool: open the link" "$out" "→ open https://chezpaul.example/menu"
out=$(dm call find_anything '{"query": "zzyzx"}')
expect_contains "the tool: nothing found, said" "$out" "Nothing found"
out=$(dm call find_anything '{"query": "speech", "kinds": ["nope"]}' 2>&1 || true)
expect_contains "the tool: kinds checked" "$out" "kinds"
out=$(dm call find_anything '{"query": "speech", "when": "someday"}' 2>&1 || true)
expect_contains "the tool: a when it can't read" "$out" "today, yesterday, Monday"
spec=$(dm tools | jq -c '.[] | select(.name == "find_anything")')
expect_eq "read-only, group observe" '[true,"observe"]' \
  "$(jq -c '[.annotations.readOnlyHint, ._meta["nixbook/group"]]' <<<"$spec")"

# -- policies.ai -----------------------------------------------------------------------
policy 2
expect_eq "local only: the plain search still" "gala-2026.pdf" "$(find_json "that speech PDF I downloaded Monday" | titles)"
policy 0
expect_eq "AI off: nothing" '{"off":true,"results":[]}' "$(find_json speech | jq -c .)"
expect_contains "AI off: the tool refuses" "$(dm call find_anything '{"query": "speech"}' 2>&1 || true)" "refused"
policy 1

# -- the helper ------------------------------------------------------------------------
# On a thread of its own: the helper's stdin kept open until it answered.
out=$({
  printf '%s\n' '{"id": 1, "argv": ["find", "speech", "pdf", "--json"], "stdin": ""}'
  sleep 2
} | dm helper | tail -n 1)
expect_eq "the helper answers it" "0" "$(jq '.code' <<<"$out")"
expect_contains "the helper: its JSON" "$(jq -r '.stdout' <<<"$out")" "gala-2026.pdf"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all find-anything tests passed"
