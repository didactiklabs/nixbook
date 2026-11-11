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

# -- Searching YouTube Music ------------------------------------------------------------
# A fake ytmusicapi: songs (one twice, one unavailable, one not a song) and
# videos, asked with their filter; signed out it still answers.
mkdir -p "$tmp/fakeapi/ytmusicapi"
cat >"$tmp/fakeapi/ytmusicapi/__init__.py" <<'EOF'
def _r(kind, vid, title, **kw):
    return dict({"resultType": kind, "videoId": vid, "title": title, "artists": [{"name": "Artist"}],
                 "duration_seconds": 61, "thumbnails": [{"url": "https://img.example/s.jpg", "width": 60},
                                                         {"url": "https://img.example/l.jpg", "width": 120}]}, **kw)
class YTMusic:
    def __init__(self, auth=None):
        self.auth = auth
    def search(self, query, filter=None, limit=20):
        if filter == "songs":
            return [_r("song", "song1111111", query + " song", album={"name": "Album"}),
                    _r("song", "song1111111", "again"), _r("song", "gone1111111", "gone", isAvailable=False),
                    _r("album", None, "an album"), _r("song", "song2222222", "two")]
        if filter == "videos":
            return [_r("video", "video111111", query + " live")]
        raise AssertionError(filter)
    # Playlist edits, logged: PLtheirs isn't yours, dupe1111111 is already in.
    def _log(self, *what):
        import os
        with open(os.environ["FAKE_YTM_LOG"], "a") as f:
            f.write(" ".join(map(str, what)) + "\n")
    def rate_song(self, vid, rating="INDIFFERENT"):
        self._log("rate", vid, rating)
    def add_playlist_items(self, pid, vids, duplicates=False):
        self._log("add", pid, ",".join(vids), duplicates)
        if pid == "PLtheirs":
            return {"error": "forbidden"}
        if vids == ["dupe1111111"]:
            return {"status": "STATUS_FAILED", "actions": [{"confirmDialogEndpoint": {"content": "This song is already in the playlist"}}]}
        return {"status": "STATUS_SUCCEEDED", "playlistEditResults": []}
    def create_playlist(self, title, description, privacy_status="PRIVATE", video_ids=None):
        self._log("create", title, privacy_status, video_ids)
        return "PLnew123"
EOF
found="$(PYTHONPATH="$tmp/fakeapi" "$py" -P "$script" search persona 5 | "$py" -c 'import json,sys
a = json.load(sys.stdin)
print(a["query"], [(t["videoId"], t["kind"], t["album"], t["duration"], t["art"]) for t in a["songs"] + a["videos"]])')"
expect "search: songs then videos, each once, available ones only, art as links" \
  "persona 5 [('song1111111', 'song', 'Album', 61, 'https://img.example/l.jpg'), ('song2222222', 'song', '', 61, 'https://img.example/l.jpg'), ('video111111', 'video', '', 61, 'https://img.example/l.jpg')]" "$found"
expect "search: no words refused" "1" "$(
  PYTHONPATH="$tmp/fakeapi" "$py" -P "$script" search >/dev/null 2>&1
  echo $?
)"

# -- Adding a song to a playlist (listening along, the tab) --------------------------------
export FAKE_YTM_LOG="$tmp/ytm-edits.log"
printf '{"cookie": "SAPISID=x; __Secure-3PAPISID=x"}' >"$tmp/keyring/session"
ya() { PYTHONPATH="$tmp/fakeapi" "$py" -P "$script" "$@" 2>/dev/null; }
field() { "$py" -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
expect "add: into a playlist of yours, duplicates refused" '{"ok": true, "playlist": "PLmine", "videoId": "song1111111", "status": "added"}' "$(ya add PLmine song1111111)"
expect "add: a song already in it said so" "already" "$(ya add PLmine dupe1111111 | field status)"
expect "add: Liked Music likes the song" "added" "$(ya add LM song2222222 | field status)"
expect "add: a playlist that isn't yours refused" "1" "$(
  ya add PLtheirs song1111111 >/dev/null
  echo $?
)"
expect "add: ids checked before anything is asked" "1" "$(
  ya add PLmine 'not an id' >/dev/null
  echo $?
)"
expect "create: a private playlist with the song" '{"ok": true, "playlist": "PLnew123", "title": "From Victor", "videoId": "song1111111"}' "$(ya create From Victor song1111111)"
expect "edits: what YouTube Music was asked" "add PLmine song1111111 False
add PLmine dupe1111111 False
rate song2222222 LIKE
add PLtheirs song1111111 False
create From Victor PRIVATE ['song1111111']" "$(cat "$tmp/ytm-edits.log")"
rm -f "$tmp/keyring/session" # the player's tests run signed out

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
busctl --user set-property org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Volume d 0.4
echo "volume-mpris=\$(mp Volume)"
sleep 1.4
echo "volume-saved=\$(cat "$tmp/state/nixbook-ytmusic/volume.json")"
echo "volume-cli=\$(y control volume 25 | j 'r["volume"]') \$(mp Volume)"
echo "volume-bad=\$(y control volume 300 2>/dev/null | j 'r.get("error")')"
busctl --user set-property org.mpris.MediaPlayer2.nixbook_ytmusic /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Volume d 0.4
# Songs that don't end on their own while skipping.
echo 60 >"$tmp/len"
y control repeat playlist >/dev/null
for _ in 1 2 3; do [ "\$(y control next | j 'r["index"]')" = 2 ] && break; done
echo "wrap=\$(y control next | j 'r["index"]')"
y control repeat none >/dev/null
y control next >/dev/null; y control next >/dev/null
echo 1.5 >"$tmp/len"
# The last song ends 1.5 s in: waited for (up to 6 s), not slept on, so a
# loaded machine doesn't fail it.
for _ in \$(seq 60); do [ "\$(y status | j 'r["player"]["status"]')" = Stopped ] && break; sleep 0.1; done
sleep 0.3
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
expect "mpris: Volume set from there" "d 0.4" "$(get volume-mpris)"
expect "player: the volume kept for the next start" '{"volume": 0.4}' "$(get volume-saved)"
expect "control volume: 0-100, the same volume as MPRIS's" "25 d 0.25" "$(get volume-cli)"
expect "control volume: over 100 refused" "volume: 0 to 100" "$(get volume-bad)"
expect "player: shuffle from MPRIS keeps the song playing first" "True 0 bbbbbbbbbbb" "$(get shuffle)"
expect "player: shuffle off, the playlist's order back on the same song" "False bbbbbbbbbbb" "$(get unshuffle)"
expect "player: repeat the playlist wraps to the first song" "0" "$(get wrap)"
expect "player: the last song ended, nothing to repeat: stopped" "{'status': 'Stopped', 'track': None, 'index': -1, 'count': 0, 'playlist': '', 'position': 0, 'volume': 40, 'loading': False, 'shuffle': False, 'loop': 'None', 'lastfm': False}" "$(get end)"
expect "player: the MPRIS name released once stopped" "0" "$(get names-after)"
expect "player: a failing stream tried again through yt-dlp" "2 music.youtube.com" "$(get fallback)"
expect "player: nothing left behind" "0" "$(find "$tmp/run/nixbook-ytmusic" -name 'cookies.txt' | wc -l)"

# -- Offline listening ---------------------------------------------------------------
# A kept playlist downloaded by the player's service (yt-dlp -o writes a
# file), played from its copy, listed from its copy with the network down;
# the garbage collection (least recently played first, never a kept
# playlist's song, leftovers gone); unkeep and clear.
cat >"$tmp/bin/yt-dlp-dl" <<'EOF'
#!/usr/bin/env bash
o=""; prev=""
for a in "$@"; do [ "$prev" = -o ] && o=$a; prev=$a; case "$a" in *watch?v=*) id=${a##*v=};; esac; done
[ -n "$o" ] || { echo "https://stream.example/$id"; exit 0; }
case "$id" in nodown*) echo "ERROR: [youtube] $id: Video unavailable" >&2; exit 1;; esac
f=$(printf '%s' "$o" | sed "s/%(id)s/$id/; s/%(ext)s/webm/")
head -c 1000 /dev/zero >"$f"
echo "$f"
EOF
chmod +x "$tmp/bin/yt-dlp-dl"
cat >"$tmp/fakeapi/ytmusicapi/__init__.py" <<'EOF'
import os
def _down():
    if os.path.exists(os.environ["FAKE_YTM_DOWN"]):
        raise ConnectionError("no network")
def _t(vid):
    return {"videoId": vid, "title": "Kept " + vid, "artists": [{"name": "Artist"}], "duration_seconds": 100,
            "thumbnails": []}
class YTMusic:
    def __init__(self, auth=None):
        pass
    def get_library_playlists(self, limit=None):
        _down()
        return [{"playlistId": "PLkeep", "title": "Keep me", "count": "4", "thumbnails": []}]
    def get_playlist(self, pid, limit=None):
        _down()
        return {"title": "Keep me", "tracks": [_t("keep1111111"), _t("keep2222222"), _t("keep3333333"),
                                              _t("nodown11111")]}
EOF
printf '{"cookie": "SAPISID=x; __Secure-3PAPISID=x"}' >"$tmp/keyring/session"
cat >"$tmp/offline.sh" <<EOF
set -u
export PYTHONPATH="$tmp/fakeapi" FAKE_YTM_DOWN="$tmp/down" NIXBOOK_YTMUSIC_YT_DLP="$tmp/bin/yt-dlp-dl"
export NIXBOOK_YTMUSIC_MPV="$tmp/bin/mpv" FAKE_MPV_LOG="$tmp/mpv2.log" FAKE_MPV_LEN=60
y() { "$py" -P "$script" "\$@"; }
j() { "$py" -c "import json,sys; d=json.load(sys.stdin); r=d.get('result', d); print(\$1)"; }
echo "before=\$(y offline status | j 'r["limitMB"], r["auto"], r["count"], r["used"]')"
echo "lists=\$(y playlists | j '[p["id"] for p in r["playlists"]], r.get("offline", False)')"
"$py" -P "$script" serve 2>"$tmp/serve2.log" &
for _ in \$(seq 100); do [ -S "$tmp/run/nixbook-ytmusic/player.sock" ] && break; sleep 0.05; done
y offline keep PLkeep Keep me >/dev/null
for _ in \$(seq 100); do [ "\$(y offline status | j 'r["count"], r["left"]')" = "3 0" ] && break; sleep 0.1; done
echo "kept=\$(y offline status | j 'r["count"], r["used"], r["kept"], r["downloading"]')"
echo "playlist=\$(y playlist PLkeep | j '[t["cached"] for t in r["tracks"]], r["kept"], r.get("offline", False)')"
echo "play=\$(printf '{"tracks":[{"videoId":"keep2222222","title":"K"}],"index":0}' | y play-tracks | j 'r["status"]')"
sleep 0.4
echo "played-from=\$(tail -n1 "$tmp/mpv2.log" | "$py" -c 'import json,sys; print(json.load(sys.stdin)["url"].split("/nixbook-ytmusic/")[1])')"
y control stop >/dev/null
touch "$tmp/down"
echo "lists-down=\$(y playlists | j '[(p["id"], p["count"], p["kept"]) for p in r["playlists"]], r.get("offline", False)')"
echo "playlist-down=\$(y playlist PLkeep | j 'len(r["tracks"]), sum(t["cached"] for t in r["tracks"]), r["offline"]')"
echo "on-this-computer=\$(y playlist _offline | j '[t["videoId"] for t in r["tracks"]][0], len(r["tracks"])')"
EOF
env -u DBUS_SESSION_BUS_ADDRESS dbus-run-session -- bash "$tmp/offline.sh" >"$tmp/offline.out" 2>&1
[ -z "${YTM_DEBUG:-}" ] || cat "$tmp/offline.out" "$tmp/serve2.log"
oget() { grep "^$1=" "$tmp/offline.out" | head -n1 | cut -d= -f2-; }
expect "offline: the defaults (4 GB, songs heard kept), nothing yet" "4096 True 0 0" "$(oget before)"
expect "offline: no 'on this computer' list while nothing is kept" "['PLkeep'] False" "$(oget lists)"
expect "offline: a kept playlist downloaded by the player (an unavailable song skipped)" \
  "3 3000 [{'id': 'PLkeep', 'title': 'Keep me', 'total': 4, 'cached': 3}] None" "$(oget kept)"
expect "offline: its songs flagged as on this computer" "[True, True, True, False] True False" "$(oget playlist)"
expect "offline: a kept song plays from its copy" "Playing" "$(oget play)"
expect "offline: … the file, not the network" "offline/keep2222222.webm" "$(oget played-from)"
expect "offline: no network, the last copy of the playlists, 'on this computer' after them" \
  "[('_offline', '3', False), ('PLkeep', '4', True)] True" "$(oget lists-down)"
expect "offline: no network, a playlist from its copy" "4 3 True" "$(oget playlist-down)"
expect "offline: 'on this computer', the last played first" "keep2222222 3" "$(oget on-this-computer)"

gc=$(XDG_CACHE_HOME="$tmp/cache" "$py" -c "
import importlib.util, json, os, time
s = importlib.util.spec_from_file_location('y', '$script'); y = importlib.util.module_from_spec(s); s.loader.exec_module(y)
print(y.gc_plan({'a': {'size': 10, 'played': 3}, 'b': {'size': 10, 'played': 1}, 'c': {'size': 10, 'added': 2}}, {'b'}, 15))
d = y.offline_dir()
with y.IndexLock() as idx:
    for vid, when in (('heard111111', 100), ('heard222222', 200)):
        open(os.path.join(d, vid + '.webm'), 'wb').write(b'x' * 1000)
        idx['songs'][vid] = {'file': vid + '.webm', 'size': 1000, 'track': {'videoId': vid}, 'added': when, 'played': 0}
for name, age in (('old.part', 7200), ('new.part', 10)):
    open(os.path.join(d, name), 'w').close(); os.utime(os.path.join(d, name), (time.time() - age,) * 2)
st = dict(y.offline_settings(), limitMB=4089 / 1024 / 1024)
print(y.collect_garbage(st), sorted(y.read_index()['songs']), sorted(n for n in os.listdir(d) if n.endswith('.part')))
")
expect "gc: the least recently played first, never a kept one" "(['c', 'a'], 10)" "$(sed -n 1p <<<"$gc")"
expect "gc: over the limit the oldest heard song goes, the kept playlist's stay; an old leftover goes" \
  "{'removed': 1, 'freed': 1000, 'used': 4000} ['heard222222', 'keep1111111', 'keep2222222', 'keep3333333'] ['new.part']" \
  "$(sed -n 2p <<<"$gc")"
expect "offline: unkeep takes its songs away, the others stay" "1 []" \
  "$(PYTHONPATH="$tmp/fakeapi" FAKE_YTM_DOWN="$tmp/down" ytm offline unkeep PLkeep | "$py" -c 'import json,sys; r=json.load(sys.stdin); print(r["count"], r["kept"])')"
expect "offline: clear --all, nothing left" "0 0" \
  "$(ytm offline clear --all | "$py" -c 'import json,sys; r=json.load(sys.stdin); print(r["count"], r["used"])')"
expect "offline: a limit under 256 MB is 256 MB" "256" \
  "$(ytm offline set limit 1 | "$py" -c 'import json,sys; print(json.load(sys.stdin)["limitMB"])')"
expect "offline: songs heard no longer kept" "False" \
  "$(ytm offline set auto off | "$py" -c 'import json,sys; print(json.load(sys.stdin)["auto"])')"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all nixbook-ytmusic tests passed"
