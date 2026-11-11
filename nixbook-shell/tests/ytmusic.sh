#!/usr/bin/env bash
# nixbook-ytmusic (scripts/ytmusic.py) without the network: the YouTube login
# read from a browser's cookies (Firefox containers, expired cookies, the most
# recent login), Last.fm's signature, and the player (`serve`) on a private
# D-Bus with tests/fake-mpv.py and a fake yt-dlp: a queue played, next and
# previous, shuffle, repeat (none, playlist, one song), what ends a song,
# the next song's stream resolved ahead, an error tried the next way then
# skipped, MPRIS (Seeked again when the sound starts: what lyrics count from), (the bus name only while something is loaded, its metadata,
# Shuffle and LoopStatus set from there).
#
# Needs: NIXBOOK_YTMUSIC_PYTHON (ytmusic.nix's pythonEnv: dbus-python,
# PyGObject), dbus-run-session and busctl (tests/run.sh).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../scripts/ytmusic.py"
py="${NIXBOOK_YTMUSIC_PYTHON:-python3}"
# A short directory: the player's socket lives under it.
tmp="$(mktemp -d /tmp/ytm.XXXXXX)"
cleanup() {
  for p in /proc/[0-9]*; do
    grep -qzx "XDG_RUNTIME_DIR=$tmp/run" "$p/environ" 2>/dev/null && kill "${p#/proc/}" 2>/dev/null || true
  done
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

mkdir -m 700 "$tmp/run" "$tmp/state" "$tmp/cache" "$tmp/keyring" "$tmp/bin"
export XDG_RUNTIME_DIR="$tmp/run" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" XDG_CONFIG_HOME="$tmp/config"
# A keyring in files: one per kind.
cat >"$tmp/bin/secret-tool" <<EOF
#!/usr/bin/env bash
kind=""; for ((i=1;i<=\$#;i++)); do [ "\${!i}" = kind ] && { j=\$((i+1)); kind=\${!j}; }; done
case "\$1" in store) cat >"$tmp/keyring/\$kind";; lookup) [ -n "\$kind" ] && cat "$tmp/keyring/\$kind" 2>/dev/null || exit 1;; clear) rm -f "$tmp/keyring/\$kind";; esac
EOF
# yt-dlp -g: a stream URL per song (the song "failsdirect" resolves to one
# that fails).
cat >"$tmp/bin/yt-dlp" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *watch?v=*) id=${a##*v=};; esac; done
case "$id" in failsdirec*) echo "https://stream.example/fail/$id";; *) echo "https://stream.example/$id";; esac
EOF
chmod +x "$tmp/bin/secret-tool" "$tmp/bin/yt-dlp"
export NIXBOOK_YTMUSIC_SECRET_TOOL="$tmp/bin/secret-tool" NIXBOOK_YTMUSIC_YT_DLP="$tmp/bin/yt-dlp"
ytm() { "$py" -P "$script" "$@"; }

# -- The login from a browser's cookies --------------------------------------------
# Two Zen containers: the default one with an older login, container 2 with
# a newer one (and an expired cookie, left out); a profile without a login.
mkdir -p "$tmp/home/.zen/a.default" "$tmp/home/.zen/b.other"
"$py" - "$tmp/home/.zen/a.default/cookies.sqlite" "$tmp/home/.zen/b.other/cookies.sqlite" <<'EOF'
import sqlite3, sys, time
now = int(time.time())
def db(path, rows):
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE moz_cookies (name, value, host, lastAccessed, originAttributes, expiry)")
    c.executemany("INSERT INTO moz_cookies VALUES (?,?,?,?,?,?)", rows)
    c.commit()
db(sys.argv[1], [
    ("__Secure-3PAPISID", "old", ".youtube.com", 1000, "", now + 9999),
    ("SID", "oldsid", ".youtube.com", 1000, "", now + 9999),
    ("__Secure-3PAPISID", "new", ".youtube.com", 2000, "^userContextId=2", now + 9999),
    ("SID", "newsid", ".youtube.com", 2000, "^userContextId=2", now + 9999),
    ("GONE", "x", ".youtube.com", 2000, "^userContextId=2", now - 10),
    ("OTHER", "y", ".example.com", 3000, "", now + 9999),
])
db(sys.argv[2], [("PREF", "f6=1", ".youtube.com", 5000, "", now + 9999)])
EOF
logins=$(HOME="$tmp/home" NIXBOOK_YTMUSIC_COOKIE_DBS="" "$py" -P -c "
import importlib.util, json, sys
s = importlib.util.spec_from_file_location('y', '$script'); y = importlib.util.module_from_spec(s); s.loader.exec_module(y)
print(json.dumps([[sorted(c.items()), b] for c, b in y.browser_logins()], separators=(',', ':')))")
expect "login: the most recent Google login first, its container's cookies only, expired ones out" \
  '[[[["SID","newsid"],["__Secure-3PAPISID","new"]],"Zen"],[[["SID","oldsid"],["__Secure-3PAPISID","old"]],"Zen"]]' "$logins"
expect "browsers: the ones with a login" '{"browsers": ["Zen"]}' "$(HOME="$tmp/home" ytm browsers)"
expect "login: a browser without a YouTube login said" "true" \
  "$(HOME="$tmp/home" ytm login-from-browser Chrome 2>/dev/null | "$py" -c 'import json,sys; print(str("no YouTube login in Chrome" in json.load(sys.stdin)["error"]).lower())' || true)"
expect "status: signed out" "false" "$(ytm status | "$py" -c 'import json,sys; print(str(json.load(sys.stdin)["signedIn"]).lower())')"

# -- Last.fm -------------------------------------------------------------------------
sig=$("$py" -P -c "
import importlib.util
s = importlib.util.spec_from_file_location('y', '$script'); y = importlib.util.module_from_spec(s); s.loader.exec_module(y)
print(y.lastfm_sign({'method': 'track.scrobble', 'api_key': 'k', 'sk': 's', 'artist': 'A', 'format': 'json'}, 'secret'))")
expect "lastfm: the signature (sorted parameters, the secret; format left out)" \
  "$(printf 'api_keykartistAmethodtrack.scrobbleskssecret' | md5sum | cut -d' ' -f1)" "$sig"
mkdir -p "$tmp/config/YouTube Music"
echo '{"plugins":{"scrobbler":{"scrobblers":{"lastfm":{"apiKey":"zz","secret":""}}}}}' >"$tmp/config/YouTube Music/config.json"
expect "lastfm start: a key that isn't one refused, with where to make one" "true" \
  "$(ytm lastfm start </dev/null 2>/dev/null | "$py" -c 'import json,sys; print(str("last.fm/api/account/create" in json.load(sys.stdin)["error"]).lower())' || true)"
expect "lastfm status: off, the app's key said absent" '{"on": false, "user": null, "fromApp": false, "appKey": true, "newKey": "https://www.last.fm/api/account/create"}' \
  "$(ytm lastfm status)"

# -- The player ------------------------------------------------------------------------
track() { printf '{"videoId":"%s","title":"Song %s","artist":"Artist A, Artist B","album":"Album","duration":200,"art":"https://img.example/%s.jpg"}' "$1" "$1" "$1"; }
q() { printf '{"tracks":[%s,%s,%s],"index":%s,"playlist":"PLtest"}' "$(track aaaaaaaaaaa)" "$(track bbbbbbbbbbb)" "$(track ccccccccccc)" "${1:-0}"; }
printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' "$py" "$here/fake-mpv.py" >"$tmp/bin/mpv"
chmod +x "$tmp/bin/mpv"
cat >"$tmp/session.sh" <<EOF
set -u
export NIXBOOK_YTMUSIC_MPV="$tmp/bin/mpv" FAKE_MPV_LOG="$tmp/mpv.log" FAKE_MPV_LEN=1.5 FAKE_MPV_LEN_FILE="$tmp/len"
"$py" -P "$script" serve 2>"$tmp/serve.log" &
for _ in \$(seq 100); do [ -S "$tmp/run/nixbook-ytmusic/player.sock" ] && break; sleep 0.05; done
y() { "$py" -P "$script" "\$@"; }
j() { "$py" -c "import json,sys; d=json.load(sys.stdin); r=d.get('result', d); print(\$1)"; }
mp() { busctl --user get-property org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player "\$1" 2>&1; }
echo "names-before=\$(busctl --user list | grep -c nixbook_ytmusic)"
busctl --user monitor --json=short --match "type='signal',member='Seeked'" >"$tmp/seeked.log" 2>/dev/null &
echo "play=\$(echo '$(q 1)' | y play-tracks | j 'r["status"], r["index"], r["count"]')"
sleep 0.6
echo "names-playing=\$(busctl --user list | grep -c nixbook_ytmusic)"
echo "seeked=\$(grep -c '"member":"Seeked"' "$tmp/seeked.log")"
echo "status=\$(mp PlaybackStatus)"
md=\$(busctl --user call org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.freedesktop.DBus.Properties Get ss org.mpris.MediaPlayer2.Player Metadata)
echo "md-url=\$(grep -o 'watch?v=[a-z]*' <<<"\$md")"
echo "md-trackid=\$(grep -o '/nixbook/ytmusic/track/[a-z]*' <<<"\$md")"
echo "md-artists=\$(grep -o 'as 2 "Artist A" "Artist B"' <<<"\$md")"
echo "identity=\$(busctl --user get-property org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Identity)"
sleep 1.6
echo "after-eof=\$(y status | j 'r["player"]["index"]')"
echo "prefetched=\$(tail -n1 "$tmp/mpv.log")"
echo "pause=\$(y control pause | j 'r["status"]')"
echo "toggle=\$(y control toggle | j 'r["status"]')"
echo "prev=\$(y control previous | j 'r["index"]')"
echo "repeat=\$(y control repeat | j 'r["loop"]')"
busctl --user set-property org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player LoopStatus s Track
echo "loop-mpris=\$(mp LoopStatus)"
sleep 1.8
echo "track-repeat=\$(y status | j 'r["player"]["index"], r["player"]["loop"]')"
y control repeat none >/dev/null
busctl --user set-property org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Shuffle b true
echo "shuffle=\$(y status | j 'r["player"]["shuffle"], r["player"]["index"], r["player"]["track"]["videoId"]')"
echo "unshuffle=\$(y control shuffle off | j 'r["shuffle"], r["track"]["videoId"]')"
# Songs that don't end on their own while skipping.
echo 60 >"$tmp/len"
y control repeat playlist >/dev/null
for _ in 1 2 3; do [ "\$(y control next | j 'r["index"]')" = 2 ] && break; done
echo "wrap=\$(y control next | j 'r["index"]')"
y control repeat none >/dev/null
y control next >/dev/null; y control next >/dev/null
echo 1.5 >"$tmp/len"
sleep 1.8
echo "end=\$(y status | j 'r["player"]')"
echo "names-after=\$(busctl --user list | grep -c nixbook_ytmusic)"
# A song whose resolved stream fails: yt-dlp through mpv next.
printf '{"tracks":[%s,%s],"index":0}' "\$(echo '$(track aaaaaaaaaaa)')" '{"videoId":"failsdirect","title":"F","artist":"","album":"","duration":200,"art":""}' | y play-tracks >/dev/null
sleep 2.4
echo "fallback=\$(grep -c 'failsdirect' "$tmp/mpv.log") \$(grep 'failsdirect' "$tmp/mpv.log" | tail -n1 | grep -o 'music.youtube.com' || true)"
y control stop >/dev/null
EOF
out=$(env -u DBUS_SESSION_BUS_ADDRESS dbus-run-session -- bash "$tmp/session.sh" 2>&1)
[ -z "${YTM_DEBUG:-}" ] || {
  echo "$out"
  cat "$tmp/serve.log"
}
get() { grep "^$1=" <<<"$out" | head -n1 | cut -d= -f2-; }
expect "player: no bus name until something plays" "0" "$(get names-before)"
expect "player: a queue played from the song asked" "Playing 1 3" "$(get play)"
expect "player: the MPRIS name while it plays" "1" "$(get names-playing)"
expect "mpris: Seeked when a song loads and again when its sound starts (lyrics count from it)" "2" "$(get seeked)"
expect "mpris: playing" 's "Playing"' "$(get status)"
expect "mpris: the song's YouTube Music link" "watch?v=bbbbbbbbbbb" "$(get md-url)"
expect "mpris: its id in the track path" "/nixbook/ytmusic/track/bbbbbbbbbbb" "$(get md-trackid)"
expect "mpris: every artist" 'as 2 "Artist A" "Artist B"' "$(get md-artists)"
expect "mpris: who it is" 's "YouTube Music (background)"' "$(get identity)"
expect "player: the end of a song plays the next" "2" "$(get after-eof)"
expect "player: the next song from its stream resolved ahead" '{"url": "https://stream.example/ccccccccccc", "opts": "start=0.0"}' "$(get prefetched)"
expect "player: pause" "Paused" "$(get pause)"
expect "player: play again" "Playing" "$(get toggle)"
expect "player: previous" "1" "$(get prev)"
expect "player: repeat cycles (off → the playlist)" "Playlist" "$(get repeat)"
expect "mpris: LoopStatus set from there" 's "Track"' "$(get loop-mpris)"
expect "player: repeat one song plays it again" "1 Track" "$(get track-repeat)"
expect "player: shuffle from MPRIS keeps the song playing first" "True 0 bbbbbbbbbbb" "$(get shuffle)"
expect "player: shuffle off, the playlist's order back on the same song" "False bbbbbbbbbbb" "$(get unshuffle)"
expect "player: repeat the playlist wraps to the first song" "0" "$(get wrap)"
expect "player: the last song ended, nothing to repeat: stopped" "{'status': 'Stopped', 'track': None, 'index': -1, 'count': 0, 'playlist': '', 'position': 0, 'loading': False, 'shuffle': False, 'loop': 'None', 'lastfm': False}" "$(get end)"
expect "player: the MPRIS name released once stopped" "0" "$(get names-after)"
expect "player: a failing stream tried again through yt-dlp" "2 music.youtube.com" "$(get fallback)"
expect "player: nothing left behind" "0" "$(find "$tmp/run/nixbook-ytmusic" -name 'cookies.txt' | wc -l)"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all nixbook-ytmusic tests passed"
