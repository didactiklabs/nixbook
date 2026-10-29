#!/usr/bin/env bash
# jellyfin-mcp against a fake Jellyfin (tests/fake-jellyfin.py): every tool,
# where the API key comes from, the Play command a player is sent, the
# fallback when no player can be controlled, errors, the credentials helper,
# the player's (jellyfin-mpv-shim's) login, and the fast path (play-query).
# Never a real server, a real keyring or the user's own systemd: secret-tool
# and systemctl are stubs, HOME and XDG_* are scratch directories.
#
#   bash customPkgs/jellyfin-mcp/tests/test.sh            the source
#   JELLYFIN_MCP=/nix/store/…/bin/jellyfin-mcp bash …     an installed copy
# Needs python3 and jq.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
fake_pid=""
cleanup() {
  [ -n "$fake_pid" ] && kill "$fake_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

if [ -n "${JELLYFIN_MCP:-}" ]; then
  jmcp=("$JELLYFIN_MCP")
else
  jmcp=(python3 "$here/../server.py")
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

# -- the environment: scratch home, stubs ---------------------------------
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_RUNTIME_DIR="$tmp/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$tmp/bin"
unset DBUS_SESSION_BUS_ADDRESS JELLYFIN_API_KEY JELLYFIN_API_KEY_FILE JELLYFIN_USER JELLYFIN_URL
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
{
  echo "#!$bash_path"
  cat
} >"$tmp/bin/systemctl" <<'EOF'
[ "$1" = "--user" ] || exit 9
shift
echo "$*" >>"$STUB_DIR/systemctl.log"
case "$1" in
  is-active) state=$(cat "$STUB_DIR/state" 2>/dev/null || echo inactive); echo "$state"; [ "$state" = active ] ;;
  start | restart)
    echo active >"$STUB_DIR/state"
    # The player connecting: its session appears on the server.
    if [ -f "$STUB_DIR/shim-session.json" ]; then
      python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); s.append(json.load(open(sys.argv[2]))); json.dump(s, open(sys.argv[1], "w"))' \
        "$STUB_DIR/sessions.json" "$STUB_DIR/shim-session.json"
    fi ;;
  stop) echo inactive >"$STUB_DIR/state" ;;
esac
EOF
chmod +x "$tmp/bin/secret-tool" "$tmp/bin/systemctl"
export PATH="$tmp/bin:$PATH"

# -- the fake server --------------------------------------------------------
sessions="$STUB_DIR/sessions.json"
log="$tmp/requests.log"
: >"$log"
SHIM_DEVICE="dev-shim-0001"
write_sessions() {
  cat >"$sessions" <<EOF
[
  {"Id": "s-moonfin", "Client": "Moonfin", "DeviceName": "totoro", "DeviceId": "dev-moon", "UserId": "u-admin",
   "UserName": "Khoa", "SupportsRemoteControl": true, "LastActivityDate": "2026-10-28T10:00:00Z",
   "SupportedCommands": ["SetVolume", "Mute", "Unmute", "VolumeUp", "VolumeDown", "ToggleFullscreen"]},
  {"Id": "s-tv", "Client": "Jellyfin Android TV", "DeviceName": "Living room TV", "DeviceId": "dev-tv",
   "UserId": "u-guest", "UserName": "guest", "SupportsRemoteControl": true, "LastActivityDate": "2026-10-28T11:00:00Z",
   "NowPlayingItem": {"Id": "mov-dune21", "Type": "Movie", "Name": "Dune", "RunTimeTicks": 93000000000},
   "PlayState": {"PositionTicks": 6000000000, "IsPaused": false}},
  {"Id": "s-web", "Client": "Jellyfin Web", "DeviceName": "Firefox", "DeviceId": "dev-web", "UserId": "u-admin",
   "UserName": "Khoa", "SupportsRemoteControl": false, "LastActivityDate": "2026-10-28T12:00:00Z"}
  $1
]
EOF
}
SHIM_SESSION='{"Id": "s-shim", "Client": "Jellyfin MPV Shim", "DeviceName": "totoro mpv", "DeviceId": "'"$SHIM_DEVICE"'",
   "UserId": "u-admin", "UserName": "Khoa", "SupportsRemoteControl": true, "LastActivityDate": "2026-10-28T09:00:00Z",
   "SupportedCommands": ["SetVolume", "Mute", "Unmute", "SetAudioStreamIndex", "SetSubtitleStreamIndex"]}'
write_sessions ""
python3 "$here/fake-jellyfin.py" "$tmp/port" "$log" "$sessions" &
fake_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/port" ] && break
  sleep 0.1
done
url="http://127.0.0.1:$(cat "$tmp/port")"
KEY="test-key-123"
PASSWORD="hunter2-secret"

# One MCP session: initialize, then one tools/call; prints the result object.
rpc() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$1" | "${jmcp[@]}" | tail -n 1
}
call() {
  rpc "$(jq -cn --arg n "$1" --argjson a "${2:-{\}}" '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:$n,arguments:$a}}')"
}
# The tool's text answer, and whether it was an error.
text_of() { jq -r '.result.content[0].text'; }
err_of() { jq -r '.result.isError'; }
reqs() { cat "$log"; }
last_req() { grep -F "\"path\": \"$1\"" "$log" | tail -n 1; }

export JELLYFIN_URL="$url" JELLYFIN_API_KEY="$KEY" JELLYFIN_SHIM_WAIT=2 JELLYFIN_CONFIRM_WAIT=0

# -- the protocol -----------------------------------------------------------
init=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' | "${jmcp[@]}")
expect_eq "initialize: echoes a known protocol version" "$(jq -r .result.protocolVersion <<<"$init")" "2025-03-26"
expect_eq "initialize: server name" "$(jq -r .result.serverInfo.name <<<"$init")" "jellyfin-mcp"
list=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
expect_eq "tools/list: the 13 tools" "$(jq -c '[.result.tools[].name]' <<<"$list")" \
  '["search","item","continue_watching","next_up","recently_added","sessions","play","control","track_preferences","mark_played","favorite","playlists","playlist_add"]'
expect_eq "tools/list: reading tools are read-only" \
  "$(jq -c '[.result.tools[] | select(.annotations.readOnlyHint) | .name]' <<<"$list")" \
  '["search","item","continue_watching","next_up","recently_added","sessions","playlists"]'
expect_eq "tools/list: nothing is destructive" "$(jq '[.result.tools[] | select(.annotations.destructiveHint)] | length' <<<"$list")" "0"
expect_eq "unknown method: -32601" "$(rpc '{"jsonrpc":"2.0","id":3,"method":"nope"}' | jq .error.code)" "-32601"
expect_eq "unknown tool: -32602" "$(call nope | jq .error.code)" "-32602"
expect_eq "bad JSON: -32700" "$(printf 'not json\n' | "${jmcp[@]}" | jq .error.code)" "-32700"
expect_eq "a notification gets no reply" "$(printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' | "${jmcp[@]}" | wc -l)" "0"

# -- where the key comes from -----------------------------------------------
r=$(JELLYFIN_URL="" call search '{"query":"dune"}')
expect_eq "not set up: an error" "$(err_of <<<"$r")" "true"
expect_match "not set up: says where to set it" "Settings > Desktop agents" "$(text_of <<<"$r")"
r=$(JELLYFIN_API_KEY="" call search '{"query":"dune"}')
expect_match "no key anywhere: not set up" "isn't set up" "$(text_of <<<"$r")"
r=$(JELLYFIN_API_KEY="wrong-key-999" call search '{"query":"dune"}')
expect_match "a wrong key: refused (401)" "refused V's login \(HTTP 401\)" "$(text_of <<<"$r")"
expect_no "a wrong key: never shown" "wrong-key-999" "$r"
mkdir -p "$HOME/.config/jf"
printf '%s\n' "$KEY" >"$HOME/.config/jf/key"
# shellcheck disable=SC2088 # the literal "~/", expanded by jellyfin-mcp itself
r=$(JELLYFIN_API_KEY="" JELLYFIN_API_KEY_FILE="~/.config/jf/key" call search '{"query":"spirited"}')
expect_match "the key from a file (~/ expanded)" "mov-spirited" "$(text_of <<<"$r")"
printf '%s' "$KEY" >"$STUB_DIR/keyring"
echo " service jellyfin-mcp " >"$STUB_DIR/keyring.attrs"
r=$(JELLYFIN_API_KEY="" call search '{"query":"spirited"}')
expect_match "the key from the keyring (service jellyfin-mcp)" "mov-spirited" "$(text_of <<<"$r")"
expect_match "keyring looked up by its attributes" "lookup service jellyfin-mcp" "$(cat "$STUB_DIR/secret-tool.log")"
expect_eq "the first administrator by default" "$(last_req /Items | jq -r .query.userId)" "u-admin"
r=$(JELLYFIN_USER=guest call search '{"query":"spirited"}')
expect_eq "JELLYFIN_USER picks the user" "$(last_req /Items | jq -r .query.userId)" "u-guest"
r=$(JELLYFIN_USER=nobody call search '{"query":"spirited"}')
expect_match "an unknown user: an error" "no user named 'nobody'" "$(text_of <<<"$r")"

# -- reading the library ----------------------------------------------------
r=$(call search '{"query":"edgerunner"}' | text_of)
expect_eq "search: the series by part of its name" "$(jq -r '.items[0].id + " " + .items[0].type' <<<"$r")" "ser-edge series"
expect_match "search: the overview is short" '"overview":"[^"]{0,210}"' "$r"
r=$(call search '{"query":"dune","types":["movie"]}' | text_of)
expect_eq "search: types narrow it" "$(jq -c '[.items[].year]' <<<"$r")" "[1984,2021]"
expect_eq "search: favourite shown" "$(jq -r '.items[1].favorite' <<<"$r")" "true"
expect_eq "search: IncludeItemTypes sent" "$(last_req /Items | jq -r .query.IncludeItemTypes)" "Movie"
r=$(call search '{"query":"x","types":["podcast"]}')
expect_match "search: an unknown type is an error" "unknown type 'podcast'" "$(text_of <<<"$r")"
r=$(call item '{"id":"ser-edge"}' | text_of)
expect_eq "item: a series' seasons" "$(jq -r '.seasons[0].id' <<<"$r")" "sea-edge-1"
expect_eq "item: its next episode" "$(jq -r '.next_up.id' <<<"$r")" "ep-e2"
expect_eq "item: a web link with the server id" "$(jq -r .web_url <<<"$r")" "$url/web/#/details?id=ser-edge&serverId=srv-1"
r=$(call item '{"id":"sea-edge-1"}' | text_of)
expect_eq "item: a season's episodes" "$(jq '.episodes | length' <<<"$r")" "10"
expect_eq "item: an episode's progress" "$(jq -r '.episodes[1].resume_at + " " + .episodes[1].progress' <<<"$r")" "10:00 40%"
r=$(call item '{"id":"alb-kob"}' | text_of)
expect_eq "item: an album's tracks" "$(jq -r '.count' <<<"$r")" "3"
r=$(call item '{"id":"art-miles"}' | text_of)
expect_eq "item: an artist's albums" "$(jq -r '.albums[0].id' <<<"$r")" "alb-kob"
r=$(call item '{"id":"nope"}')
expect_match "item: unknown id" "no Jellyfin item with id 'nope'" "$(text_of <<<"$r")"
r=$(call continue_watching | text_of)
expect_eq "continue_watching" "$(jq -r '.items[0].id + " " + .items[0].resume_at' <<<"$r")" "ep-e2 10:00"
r=$(call next_up '{"limit":3}' | text_of)
expect_eq "next_up" "$(jq -r '.items[0].series + " S" + (.items[0].season|tostring) + "E" + (.items[0].episode|tostring)' <<<"$r")" "Cyberpunk: Edgerunners S1E2"
r=$(call recently_added '{"type":"movie"}' | text_of)
expect_eq "recently_added: one kind" "$(jq -r '[.items[].type] | unique | join(",")' <<<"$r")" "movie"
r=$(call playlists | text_of)
expect_eq "playlists" "$(jq -r '.playlists[0].name + " " + (.playlists[0].items|tostring)' <<<"$r")" "Road trip 1"

# -- players ----------------------------------------------------------------
r=$(call sessions | text_of)
expect_eq "sessions: newest first" "$(jq -c '[.sessions[].id]' <<<"$r")" '["s-web","s-tv","s-moonfin"]'
expect_eq "sessions: Moonfin flagged" "$(jq -r '.sessions[2].moonfin' <<<"$r")" "true"
expect_eq "sessions: another user's flagged" "$(jq -r '.sessions[1].other_user' <<<"$r")" "true"
expect_eq "sessions: what plays, where" "$(jq -r '.sessions[1].now_playing.position' <<<"$r")" "10:00 / 2:35:00"
expect_match "sessions: this computer's player not set up" "connect it in Settings" "$(jq -r .this_computer <<<"$r")"

: >"$log"
r=$(call play '{"item_id":"mov-spirited"}' | text_of)
expect_eq "play, no player of this computer: Moonfin (the user's own, controllable)" "$(jq -r .on.id <<<"$r")" "s-moonfin"
p=$(last_req /Sessions/s-moonfin/Playing)
expect_eq "play: the PlayNow call" "$(jq -c '.query | {playCommand, itemIds, startIndex}' <<<"$p")" '{"playCommand":"PlayNow","itemIds":"mov-spirited","startIndex":"0"}'
r=$(call play '{"item_id":"ser-edge","session":"living room"}' | text_of)
expect_eq "play on a named player (another user's TV)" "$(jq -r .on.id <<<"$r")" "s-tv"
p=$(last_req /Sessions/s-tv/Playing)
expect_eq "play a series: from its next episode, where it stopped" \
  "$(jq -r '.query.itemIds | split(",") | .[0] + " " + (length|tostring)' <<<"$p") $(jq -r .query.startPositionTicks <<<"$p")" "ep-e2 9 6000000000"
r=$(call play '{"item_id":"alb-kob","session":"moonfin","mode":"last"}' | text_of)
p=$(last_req /Sessions/s-moonfin/Playing)
expect_eq "play an album, queued last: its tracks in order" "$(jq -r '.query.playCommand + " " + .query.itemIds' <<<"$p")" "PlayLast aud-1,aud-2,aud-3"
r=$(call play '{"item_id":"mov-spirited","session":"firefox"}')
expect_match "a player that can't be controlled: said" "doesn't accept remote control" "$(text_of <<<"$r")"
r=$(call play '{"item_id":"mov-spirited","session":"kitchen"}')
expect_match "an unknown player: the connected ones listed" "no connected player matches 'kitchen' \(connected: " "$(text_of <<<"$r")"

# No player of the user's: the link to open instead.
cat >"$sessions" <<'EOF'
[{"Id": "s-web", "Client": "Jellyfin Web", "DeviceName": "Firefox", "UserId": "u-admin", "SupportsRemoteControl": false}]
EOF
r=$(call play '{"item_id":"mov-spirited"}')
expect_eq "no controllable player: not an error" "$(err_of <<<"$r")" "false"
expect_eq "no controllable player: played false + the web link" \
  "$(text_of <<<"$r" | jq -r '(.played|tostring) + " " + .web_url')" "false $url/web/#/details?id=mov-spirited&serverId=srv-1"
expect_match "no controllable player: says how to connect one" "connect it in Settings > Desktop agents > Jellyfin" "$(text_of <<<"$r")"

# -- the player of this computer: jellyfin-mpv-shim ------------------------
write_sessions ""
shimdir="$XDG_CONFIG_HOME/jellyfin-mpv-shim"
mkdir -p "$shimdir"
echo '{"player_name": "totoro mpv", "client_uuid": "'"$SHIM_DEVICE"'", "fullscreen": true}' >"$shimdir/conf.json"
r=$(printf '%s\n' "wrong" | "${jmcp[@]}" shim-login "$url" Khoa || true)
expect_match "shim-login: a wrong password" "refused this username or password" "$r"
expect_no "shim-login: the password never printed" "wrong" "$(jq -r .error <<<"$r" | sed 's/refused this username or password//')"
: >"$STUB_DIR/systemctl.log"
r=$(printf '%s\n' "$PASSWORD" | "${jmcp[@]}" shim-login "$url/" Khoa)
expect_eq "shim-login: ok" "$(jq -r '.ok, .user, .device' <<<"$r" | paste -sd' ')" "true Khoa totoro mpv"
a=$(last_req /Users/AuthenticateByName)
expect_eq "shim-login: signs in as the shim (its client, device name and id)" \
  "$(jq -c '.client | {Client, Device, DeviceId}' <<<"$a")" '{"Client":"Jellyfin MPV Shim","Device":"totoro mpv","DeviceId":"'"$SHIM_DEVICE"'"}'
expect_eq "shim-login: users.json is 0600" "$(stat -c %a "$shimdir/users.json")" "600"
u=$(cat "$shimdir/users.json")
expect_eq "shim-login: the profile keeps the shim's device id" "$(jq -r '.users[0].device_id + " " + (.users[0].default|tostring) + " " + (.active == .users[0].id | tostring)' <<<"$u")" "$SHIM_DEVICE true true"
expect_eq "shim-login: the credential's shape" \
  "$(jq -c '.users[0].credentials[0] | {address, Name, Id, UserId, AccessToken, username, Users, has_uuid: (.uuid|length > 0)}' <<<"$u")" \
  '{"address":"'"$url"'","Name":"Fake Jellyfin","Id":"srv-1","UserId":"u-admin","AccessToken":"user-token-abc","username":"Khoa","Users":[{"Id":"u-admin","IsSignedInOffline":true}],"has_uuid":true}'
expect_no "shim-login: the password is not stored" "$PASSWORD" "$u$(cat "$shimdir/users.json.bak")"
expect_no "shim-login: the token not printed" "user-token-abc" "$r"
expect_eq "shim-login: the service stopped, then started" "$(paste -sd, "$STUB_DIR/systemctl.log")" "stop jellyfin-mpv-shim.service,start jellyfin-mpv-shim.service"
first_uuid=$(jq -r '.users[0].credentials[0].uuid' <<<"$u")
jq '.users[0].credentials += [{"address": "https://other.example", "Id": "srv-2", "AccessToken": "t2", "uuid": "keep-me"}]' "$shimdir/users.json" >"$tmp/u.json"
cp "$tmp/u.json" "$shimdir/users.json"
printf '%s\n' "$PASSWORD" | "${jmcp[@]}" shim-login "$url" Khoa >/dev/null
u=$(cat "$shimdir/users.json")
expect_eq "shim-login again: replaces its login (same uuid), keeps the others" \
  "$(jq -c '[.users[0].credentials[] | .uuid]' <<<"$u")" '["keep-me","'"$first_uuid"'"]'
r=$("${jmcp[@]}" shim-status)
expect_eq "shim-status" "$(jq -c '{signed_in, user, device}' <<<"$r")" '{"signed_in":true,"user":"Khoa","device":"totoro mpv"}'

echo inactive >"$STUB_DIR/state"
printf '%s' "$SHIM_SESSION" >"$STUB_DIR/shim-session.json"
: >"$STUB_DIR/systemctl.log"
r=$(call play '{"item_id":"mov-spirited"}' | text_of)
expect_eq "play: the player signed in but not running: started, then used" "$(jq -r '.on.id + " " + (.on.this_computer|tostring)' <<<"$r")" "s-shim true"
expect_match "play: its service was started" "^start jellyfin-mpv-shim.service" "$(grep -v is-active "$STUB_DIR/systemctl.log")"
r=$(call play '{"item_id":"ep-e2"}' | text_of)
p=$(last_req /Sessions/s-shim/Playing)
expect_eq "play: the default is this computer's player once connected, from where it stopped" \
  "$(jq -r '.query.itemIds + " " + .query.startPositionTicks' <<<"$p") $(jq -r .from <<<"$r")" "ep-e2 6000000000 10:00"
r=$(
  call play '{"item_id":"ep-e2","resume":false}' >/dev/null
  last_req /Sessions/s-shim/Playing
)
expect_eq "play resume:false: from the start" "$(jq -r '.query.startPositionTicks // "none"' <<<"$r")" "none"
r=$(call sessions | text_of)
expect_eq "sessions: this computer's player flagged" "$(jq -r '.sessions[] | select(.id=="s-shim") | .this_computer' <<<"$r")" "true"
r=$(call play '{"item_id":"mov-spirited","session":"mpv"}' | text_of)
expect_eq "play session mpv: this computer's" "$(jq -r .on.id <<<"$r")" "s-shim"

# The player signed in, but it never connects.
write_sessions ""
rm -f "$STUB_DIR/shim-session.json"
r=$(call play '{"item_id":"mov-spirited"}' | text_of)
expect_eq "player not connecting: Moonfin instead" "$(jq -r .on.id <<<"$r")" "s-moonfin"
cat >"$sessions" <<'EOF'
[]
EOF
r=$(call play '{"item_id":"mov-spirited"}' | text_of)
expect_match "player not connecting, nothing else: why" "didn't connect to Jellyfin" "$(jq -r .reason <<<"$r")"

# -- control ----------------------------------------------------------------
write_sessions ",$SHIM_SESSION"
: >"$log"
r=$(call control '{"action":"pause"}')
expect_match "control with nothing of mine playing: says so" "isn't playing anything" "$(text_of <<<"$r")"
r=$(call control '{"action":"pause","session":"tv"}' | text_of)
expect_eq "control pause (named)" "$(jq -r .on.id <<<"$r") $(last_req /Sessions/s-tv/Playing/Pause | jq -r .method)" "s-tv POST"
r=$(call control '{"action":"seek","seconds":90,"session":"tv"}' | text_of)
expect_eq "control seek: seekPositionTicks" "$(last_req /Sessions/s-tv/Playing/Seek | jq -r .query.seekPositionTicks) $(jq -r .position <<<"$r")" "900000000 1:30"
call control '{"action":"forward","session":"tv"}' >/dev/null
expect_eq "control forward: from the position (10:00 + 30 s)" "$(last_req /Sessions/s-tv/Playing/Seek | jq -r .query.seekPositionTicks)" "6300000000"
call control '{"action":"next","session":"tv"}' >/dev/null
expect_eq "control next: NextTrack" "$(last_req /Sessions/s-tv/Playing/NextTrack | jq -r .method)" "POST"
call control '{"action":"volume","level":40}' >/dev/null
expect_eq "control volume: SetVolume on this computer's player" "$(last_req /Sessions/s-shim/Command | jq -c .body)" '{"Name":"SetVolume","Arguments":{"Volume":"40"}}'
r=$(call control '{"action":"fullscreen"}')
expect_match "control: a command the player doesn't support" "doesn't support fullscreen" "$(text_of <<<"$r")"
call control '{"action":"fullscreen","session":"moonfin"}' >/dev/null
expect_eq "control fullscreen on Moonfin" "$(last_req /Sessions/s-moonfin/Command/ToggleFullscreen | jq -r .method)" "POST"
r=$(call control '{"action":"seek","session":"tv"}')
expect_match "control seek without seconds" "seek needs seconds" "$(text_of <<<"$r")"

# -- marking, favourites, playlists ----------------------------------------
call mark_played '{"id":"mov-spirited","played":true}' >/dev/null
expect_eq "mark_played" "$(last_req /UserPlayedItems/mov-spirited | jq -r '.method + " " + .query.userId')" "POST u-admin"
call mark_played '{"id":"mov-spirited","played":false}' >/dev/null
expect_eq "mark_played false: DELETE" "$(last_req /UserPlayedItems/mov-spirited | jq -r .method)" "DELETE"
call favorite '{"id":"mov-dune84","on":true}' >/dev/null
expect_eq "favorite" "$(last_req /UserFavoriteItems/mov-dune84 | jq -r .method)" "POST"
r=$(call playlist_add '{"playlist":"road","item_id":"aud-2"}' | text_of)
expect_eq "playlist_add by name" "$(last_req /Playlists/pl-road/Items | jq -r .query.ids) $(jq -r .playlist.name <<<"$r")" "aud-2 Road trip"
r=$(call playlist_add '{"playlist":"gym","item_id":"aud-2"}')
expect_match "playlist_add: unknown playlist" "no playlist named 'gym' \(yours: Road trip\)" "$(text_of <<<"$r")"

# -- older servers ----------------------------------------------------------
touch "$sessions.old"
r=$(call search '{"query":"spirited"}' | text_of)
expect_eq "an older server: search through /Users/{id}/Items" "$(jq -r '.items[0].id' <<<"$r")" "mov-spirited"
expect_eq "an older server: /Items refused, then /Users/{id}/Items" \
  "$(grep -Eo '"path": "(/Items|/Users/u-admin/Items)"' "$log" | tail -n 2 | paste -sd' ')" '"path": "/Items" "path": "/Users/u-admin/Items"'
call mark_played '{"id":"mov-spirited","played":true}' >/dev/null
expect_eq "an older server: mark_played through /Users/{id}/PlayedItems" "$(last_req /Users/u-admin/PlayedItems/mov-spirited | jq -r .method)" "POST"
rm -f "$sessions.old"

# -- errors -----------------------------------------------------------------
r=$(JELLYFIN_URL="http://127.0.0.1:1" call search '{"query":"x"}')
expect_match "a server that isn't there" "couldn't reach Jellyfin at http://127.0.0.1:1" "$(text_of <<<"$r")"
r=$(JELLYFIN_URL="ftp://x" call search '{"query":"x"}')
expect_match "a URL that isn't http(s)" "must start with http" "$(text_of <<<"$r")"
r=$(call search '{}')
expect_match "a missing argument" "query is required" "$(text_of <<<"$r")"

# -- the credentials helper -------------------------------------------------
rm -f "$STUB_DIR/keyring"
r=$(JELLYFIN_API_KEY="" "${jmcp[@]}" credentials status)
expect_eq "credentials status: no key" "$(jq -c '{has_key, key_source}' <<<"$r")" '{"has_key":false,"key_source":null}'
r=$(printf '%s\n' "$KEY" | JELLYFIN_API_KEY="" "${jmcp[@]}" credentials test "$url/")
expect_eq "credentials test: checked, nothing saved" "$(jq -r '.server + " " + .user + " " + (.movies|tostring)' <<<"$r") $([ -f "$STUB_DIR/keyring" ] && echo saved || echo none)" "Fake Jellyfin Khoa 4 none"
r=$(printf '%s\n' "bad-key-777" | JELLYFIN_API_KEY="" "${jmcp[@]}" credentials save "$url" || true)
expect_match "credentials save: a bad key refused, not saved" "refused V's login" "$(jq -r .error <<<"$r")$([ -f "$STUB_DIR/keyring" ] && echo saved)"
expect_no "credentials save: the bad key not printed" "bad-key-777" "$r"
r=$(printf '%s\n' "$KEY" | JELLYFIN_API_KEY="" "${jmcp[@]}" credentials save "$url" Khoa)
expect_eq "credentials save: in the keyring" "$(jq -r '.has_key, .key_source' <<<"$r" | paste -sd' ') $(cat "$STUB_DIR/keyring")" "true keyring $KEY"
expect_no "credentials save: the key not printed" "$KEY" "$r"
r=$(JELLYFIN_API_KEY="" "${jmcp[@]}" credentials forget)
expect_eq "credentials forget" "$(jq -r .has_key <<<"$r") $([ -f "$STUB_DIR/keyring" ] && echo kept || echo gone)" "false gone"
r=$(JELLYFIN_API_KEY="" "${jmcp[@]}" configured || true)
expect_eq "configured: no key" "$(jq -r .configured <<<"$r")" "false"
r=$("${jmcp[@]}" configured)
expect_eq "configured: key and player" "$(jq -c . <<<"$r")" '{"configured":true,"player":true}'

# -- the fast path: play-query ----------------------------------------------
write_sessions ",$SHIM_SESSION"
pq() { "${jmcp[@]}" play-query "$@" || true; }
start=$(date +%s%N)
r=$(pq "play edgerunner season 2 episode 1")
ms=$((($(date +%s%N) - start) / 1000000))
expect_eq "play-query: a season that isn't there" "$(jq -r '(.ok|tostring) + " " + (.matched|tostring) + " " + .said' <<<"$r")" "false true Cyberpunk: Edgerunners has only 1 season."
: >"$log"
start=$(date +%s%N)
r=$(pq "watch edgerunners s1e1")
ms=$((($(date +%s%N) - start) / 1000000))
expect_eq "play-query: s1e1" "$(jq -r '(.ok|tostring) + " " + .said' <<<"$r")" "true Playing Cyberpunk: Edgerunners, S01E01."
expect_eq "play-query: from that episode on, to this computer's player" \
  "$(last_req /Sessions/s-shim/Playing | jq -r '.query.itemIds | split(",") | .[0] + " " + (length|tostring)')" "ep-e1 10"
calls=$(grep -c . "$log")
echo "       (play-query s1e1: ${ms} ms, ${calls} requests)"
if [ "$ms" -lt 1500 ]; then pass "play-query: under 1.5 s against a local server"; else fail "play-query took ${ms} ms"; fi
if [ "$calls" -le 4 ]; then
  pass "play-query: at most 4 requests (search, episodes, sessions, play)"
else
  fail "play-query made $calls requests" "$(cat "$log")"
fi
r=$(pq "lance edgerunners saison 1 épisode 3")
expect_eq "play-query in French" "$(jq -r .said <<<"$r")" "Je lance Cyberpunk: Edgerunners, S01E03."
r=$(pq "spiel Edgerunners Staffel 1 Folge 20")
expect_eq "play-query in German: an episode that isn't there" "$(jq -r .said <<<"$r")" "Staffel 1 von Cyberpunk: Edgerunners hat nur 10 Folgen."
r=$(pq "xem edgerunners tập 4")
expect_eq "play-query in Vietnamese (an episode alone: season 1)" "$(jq -r .said <<<"$r")" "Đang phát Cyberpunk: Edgerunners, S01E04."
r=$(pq "play spirited away")
expect_eq "play-query: a film" "$(jq -r '.kind + " " + .said' <<<"$r")" "movie Playing Spirited Away (2001)."
r=$(pq "play edgerunners")
expect_eq "play-query: a series alone, its next episode" "$(jq -r .said <<<"$r")" "Playing Cyberpunk: Edgerunners, S01E02."
r=$(pq "play dune")
expect_eq "play-query: two of them, asked" "$(jq -r '(.ok|tostring) + " " + (.matched|tostring) + " " + .said' <<<"$r")" "false true Which one: Dune (1984) or Dune (2021)?"
r=$(pq --strict "play some jazz")
expect_eq "play-query --strict: music asked, not a film" "$(jq -r '(.matched|tostring) + " " + .reason' <<<"$r")" "false not found"
r=$(pq "play the matrix")
expect_eq "play-query: nothing found, not matched" "$(jq -r '(.matched|tostring) + " " + .said' <<<"$r")" "false I couldn't find the matrix in Jellyfin."
cat >"$sessions" <<'EOF'
[]
EOF
rm -f "$shimdir/users.json" "$shimdir/users.json.bak"
r=$(pq "play spirited away")
expect_eq "play-query: no player" "$(jq -r '(.ok|tostring) + " " + (.matched|tostring) + " " + .said' <<<"$r")" \
  "false true The player isn't connected: connect it in Settings > Desktop agents > Jellyfin."
r=$(JELLYFIN_API_KEY="" pq "play spirited away")
expect_eq "play-query: not set up" "$(jq -r '(.matched|tostring) + " " + .reason' <<<"$r")" "false not configured"

# -- signing in as a user: no admin, no API key --------------------------------
rm -f "$STUB_DIR/keyring" "$STUB_DIR/keyring.attrs"
state="$HOME/.local/state/jellyfin-mcp/login.json"
login() { printf '%s\n' "$2" | JELLYFIN_API_KEY="" "${jmcp[@]}" credentials login "$url" "$1" "${@:3}" || true; }
r=$(login guest wrong)
expect_match "login: a wrong password" "refused this username or password" "$(jq -r .error <<<"$r")"
expect_match "login: points at app passwords" "app password" "$(jq -r .error <<<"$r")"
expect_no "login: a refused password never printed" "wrong" "$(jq -r .error <<<"$r" | sed 's/refused this username or password//')"
: >"$log"
r=$(login guest guest-pass)
expect_eq "login: signed in as that user, no admin" \
  "$(jq -r '.kind + " " + .signed_in_as + " " + .user + " " + (.movies|tostring)' <<<"$r")" "token guest guest 4"
expect_eq "login: as the assistant's own device" "$(last_req /Users/AuthenticateByName | jq -r .client.Client)" "nixbook-jellyfin-mcp"
expect_match "login: the token kept in the keyring, marked as one" "kind token" "$(cat "$STUB_DIR/keyring.attrs")"
guest_token=$(cat "$STUB_DIR/keyring")
expect_no "login: the token never printed" "$guest_token" "$r"
expect_no "login: the password not kept" "guest-pass" "$(cat "$STUB_DIR/keyring" "$state")"
expect_eq "login: who signed in, 0600" "$(stat -c %a "$state") $(jq -r .user "$state")" "600 guest"
r=$(JELLYFIN_API_KEY="" "${jmcp[@]}" credentials status)
expect_eq "credentials status: signed in" "$(jq -c '{has_key, key_source, kind, signed_in_as}' <<<"$r")" \
  '{"has_key":true,"key_source":"keyring","kind":"token","signed_in_as":"guest"}'
: >"$log"
r=$(JELLYFIN_API_KEY="" JELLYFIN_USER=Khoa call search '{"query":"spirited"}')
expect_match "a user's token: the tools work" "mov-spirited" "$(text_of <<<"$r")"
expect_eq "a user's token: acts as that user (JELLYFIN_USER is for API keys)" "$(last_req /Items | jq -r .query.userId)" "u-guest"
expect_eq "a user's token: never asks for the user list" "$(grep -c '"path": "/Users"' "$log")" "0"
cat >"$sessions" <<'EOF'
[{"Id": "s-tv", "Client": "Jellyfin Android TV", "DeviceName": "Living room TV", "DeviceId": "dev-tv",
  "UserId": "u-guest", "UserName": "guest", "SupportsRemoteControl": true,
  "NowPlayingItem": {"Id": "mov-dune21", "Type": "Movie", "Name": "Dune", "RunTimeTicks": 93000000000},
  "PlayState": {"PositionTicks": 6000000000, "IsPaused": false, "PlayMethod": "Transcode"},
  "TranscodingInfo": {"VideoCodec": "h264", "AudioCodec": "aac", "IsVideoDirect": false, "IsAudioDirect": false,
                      "Bitrate": 10000000, "TranscodeReasons": ["ContainerBitrateExceedsLimit"]}},
 {"Id": "s-moonfin", "Client": "Moonfin", "DeviceName": "totoro", "DeviceId": "dev-moon", "UserId": "u-admin",
  "UserName": "Khoa", "SupportsRemoteControl": true}]
EOF
r=$(JELLYFIN_API_KEY="" call sessions | text_of)
expect_eq "a user's token: only the players that user controls" "$(jq -c '[.sessions[].id]' <<<"$r")" '["s-tv"]'
expect_eq "a user's token: asks for those" "$(last_req /Sessions | jq -r .query.controllableByUserId)" "u-guest"
expect_eq "sessions: how it plays, and why it transcodes" "$(jq -c '.sessions[0].now_playing | {play_method, transcode}' <<<"$r")" \
  '{"play_method":"Transcode","transcode":{"reasons":["ContainerBitrateExceedsLimit"],"video":"h264","audio":"aac","mbps":10.0}}'
r=$(JELLYFIN_API_KEY="" call play '{"item_id":"mov-spirited","session":"tv"}' | text_of)
expect_eq "a user's token: plays on that user's player" "$(jq -r .on.id <<<"$r")" "s-tv"

# A server with a two-factor plugin: the account's password gives a session
# it holds back; an app password works.
: >"$log"
r=$(login Mai mai-password)
expect_match "2FA: the password's session held back, said" "blocks the session.*app password" "$(jq -r .error <<<"$r")"
expect_eq "2FA: that session ended on the server" "$(grep -c '"path": "/Sessions/Logout"' "$log")" "1"
expect_eq "2FA: the previous sign-in kept" "$(cat "$STUB_DIR/keyring")" "$guest_token"
: >"$log"
r=$(login Mai mai-app-password --player)
expect_eq "2FA: an app password signs in" "$(jq -r '.kind + " " + .user' <<<"$r")" "token Mai"
expect_eq "login --player: the player signed in too" \
  "$(jq -r '.player.ok, .player.user' <<<"$r" | paste -sd' ') $(jq -r '.users[0].credentials[-1].username' "$shimdir/users.json")" "true Mai Mai"
expect_eq "login --player: the player as itself" "$(grep -F '"Jellyfin MPV Shim"' "$log" | grep -c AuthenticateByName)" "1"
expect_eq "login again: the previous token ended on the server" "$(grep -c '"path": "/Sessions/Logout"' "$log")" "1"
r=$(JELLYFIN_API_KEY="$guest_token" call search '{"query":"spirited"}')
expect_match "an ended token: refused, says how to fix it" "refused V's login \(HTTP 401\).*sign in again" "$(text_of <<<"$r")"
mai_token=$(cat "$STUB_DIR/keyring")
r=$(JELLYFIN_API_KEY="" "${jmcp[@]}" credentials forget)
expect_eq "sign out: ended on the server, forgotten here" \
  "$(jq -r '.signed_out, .has_key' <<<"$r" | paste -sd' ') $([ -f "$state" ] && echo kept || echo gone)" "true false gone"
r=$(JELLYFIN_API_KEY="$mai_token" call search '{"query":"spirited"}')
expect_match "sign out: the token stops working" "HTTP 401" "$(text_of <<<"$r")"
r=$(printf '%s\n' "$KEY" | JELLYFIN_API_KEY="" "${jmcp[@]}" credentials save "$url" Khoa)
expect_eq "an API key after a sign-in" "$(jq -r .kind <<<"$r")$(tr -s ' ' <"$STUB_DIR/keyring.attrs")" "apikey service jellyfin-mcp kind apikey "

# -- audio and subtitle tracks -------------------------------------------------
write_sessions ",$SHIM_SESSION"
touch "$sessions.live"
r=$(call item '{"id":"ep-e2"}' | text_of)
expect_eq "item: an episode's tracks" "$(jq -c '[.tracks.audio[].language, (.tracks.subtitles | length)]' <<<"$r")" '["jpn","eng",3]'
r=$(JELLYFIN_CONFIRM_WAIT=2 call play '{"item_id":"ep-e2","audio":"Japanese","subtitles":"English"}')
p=$(last_req /Sessions/s-shim/Playing)
expect_eq "play: the tracks asked (full subtitles, not the forced ones), with their source" \
  "$(jq -r '.query | .audioStreamIndex + " " + .subtitleStreamIndex + " " + .mediaSourceId' <<<"$p")" "1 4 ep-e2-src"
expect_eq "play: says which" "$(text_of <<<"$r" | jq -c .tracks)" '{"audio":"Japanese - AAC - Stereo","subtitles":"English - ASS"}'
expect_eq "play: saw the player play it with them: verified" "$(jq -c .result._meta <<<"$r")" '{"verified":true}'
call play '{"item_id":"ser-edge","subtitles":"off","audio":"en"}' >/dev/null
expect_eq "play a series: its next episode's tracks; subtitles off" \
  "$(last_req /Sessions/s-shim/Playing | jq -r '.query | .itemIds[0:5] + " " + .audioStreamIndex + " " + .subtitleStreamIndex')" "ep-e2 2 -1"
r=$(call play '{"item_id":"mov-dune21","audio":"Japanese"}' | text_of)
expect_eq "play: a language it hasn't, said, the player's own choice kept" \
  "$(jq -r '.notes[0]' <<<"$r") $(last_req /Sessions/s-shim/Playing | jq -r '.query.audioStreamIndex // "none"')" "no Japanese audio (it has English) none"
rm -f "$sessions.live"
r=$(call play '{"item_id":"mov-spirited"}')
expect_eq "play: the player not seen playing it: points at sessions" "$(jq -c .result._meta <<<"$r")" '{"observe":{"tool":"sessions","args":{}}}'

touch "$sessions.live"
call play '{"item_id":"ep-e3"}' >/dev/null
r=$(JELLYFIN_CONFIRM_WAIT=2 call control '{"action":"audio","track":"english"}')
expect_eq "control audio: the player told, by index" "$(last_req /Sessions/s-shim/Command | jq -c .body)" '{"Name":"SetAudioStreamIndex","Arguments":{"Index":"2"}}'
expect_eq "control audio: seen switched: verified" "$(jq -r '.result._meta.verified' <<<"$r") $(text_of <<<"$r" | jq -r .track)" "true English - AAC - 5.1"
r=$(call control '{"action":"subtitles","track":"français"}')
expect_eq "control subtitles: by language" "$(last_req /Sessions/s-shim/Command | jq -r .body.Arguments.Index)" "5"
r=$(call control '{"action":"subtitles","track":"off"}')
expect_eq "control subtitles off" "$(last_req /Sessions/s-shim/Command | jq -r .body.Arguments.Index)" "-1"
r=$(call control '{"action":"subtitles","track":"korean"}')
expect_match "control subtitles: one it hasn't, said" "no Korean subtitles \(it has English, French\)" "$(text_of <<<"$r")"
rm -f "$sessions.live"

r=$(call track_preferences | text_of)
expect_eq "track_preferences: read" "$(jq -c '[.audio_language, .subtitle_mode]' <<<"$r")" '[null,"Default"]'
r=$(call track_preferences '{"audio":"japonais","subtitles":"English","subtitle_mode":"smart"}')
expect_eq "track_preferences: set by name, any language" \
  "$(text_of <<<"$r" | jq -r '[.audio_language.code, .subtitle_language.code, .subtitle_mode, .play_default_audio] | map(tostring) | join(" ")')" "jpn eng Smart false"
expect_eq "track_preferences: read back: verified" "$(jq -r .result._meta.verified <<<"$r")" "true"
c=$(last_req /Users/Configuration)
expect_eq "track_preferences: the user's own, the rest of it kept" "$(jq -r '.query.userId + " " + (.body.HidePlayedInLatest|tostring)' <<<"$c")" "u-admin true"
r=$(call track_preferences '{"subtitles":""}' | text_of)
expect_eq "track_preferences: a language cleared" "$(jq -c '[.subtitle_language, .audio_language.code]' <<<"$r")" '[null,"jpn"]'
r=$(call track_preferences '{"audio":"klingon"}')
expect_match "track_preferences: an unknown language" "unknown language 'klingon'" "$(text_of <<<"$r")"

# The fast path: the tracks named in what was said.
r=$(pq "play edgerunners s1e3 in japanese with english subs")
expect_eq "play-query: the tracks said" "$(jq -r .said <<<"$r")" "Playing Cyberpunk: Edgerunners, S01E03 (Japanese audio, English subtitles)."
expect_eq "play-query: sent to the player" "$(last_req /Sessions/s-shim/Playing | jq -r '.query | .itemIds[0:5] + " " + .audioStreamIndex + " " + .subtitleStreamIndex')" "ep-e3 1 4"
r=$(pq "lance edgerunners saison 1 épisode 3 en vostfr")
expect_eq "play-query in French: VOSTFR" "$(jq -r .said <<<"$r")" "Je lance Cyberpunk: Edgerunners, S01E03 (sous-titres français)."
r=$(pq "spiel Spirited Away auf Japanisch")
expect_eq "play-query in German: a language it hasn't" "$(jq -r .said <<<"$r")" "Ich spiele Spirited Away (2001) ab (kein Ton auf Japanisch)."
r=$(pq "xem edgerunners tập 3 tiếng Nhật phụ đề tiếng Anh")
expect_eq "play-query in Vietnamese" "$(jq -r .said <<<"$r")" "Đang phát Cyberpunk: Edgerunners, S01E03 (âm thanh tiếng Nhật, phụ đề tiếng Anh)."
r=$(pq "play lost in translation")
expect_eq "play-query: \"in\" before a word that isn't a language stays in the title" "$(jq -r .query <<<"$r")" "lost in translation"

# -- a slow server ------------------------------------------------------------
kill "$fake_pid"
wait "$fake_pid" 2>/dev/null || true
rm -f "$tmp/port"
FAKE_SLOW=1 python3 "$here/fake-jellyfin.py" "$tmp/port" "$log" "$sessions" &
fake_pid=$!
for _ in $(seq 50); do
  [ -s "$tmp/port" ] && break
  sleep 0.1
done
r=$(JELLYFIN_TIMEOUT=1 JELLYFIN_URL="http://127.0.0.1:$(cat "$tmp/port")" "${jmcp[@]}" credentials test "http://127.0.0.1:$(cat "$tmp/port")" </dev/null || true)
expect_match "a server that doesn't answer: the timeout said" "didn't answer within 1 s" "$(jq -r .error <<<"$r")"

if [ "$fails" -ne 0 ]; then
  echo "jellyfin-mcp: $fails check(s) failed" >&2
  exit 1
fi
echo "jellyfin-mcp: all checks passed"
