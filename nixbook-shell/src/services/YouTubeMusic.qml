pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

/**
 * YouTube Music in the background, without a window (no AI): `nixbook-ytmusic`
 * (scripts/ytmusic.py) reads the library with the YouTube session signed in
 * from a browser or the YouTube Music app, and its player (the
 * `nixbook-ytmusic` user unit, started when something plays) plays it with
 * mpv, audio only, as the MPRIS player "YouTube Music (background)" —
 * scrobbled to Last.fm once signed in there. The right sidebar's YouTube
 * Music tab (sidebar.youtubeMusicTab) lists the playlists; Settings >
 * Services > YouTube Music signs in. Listening along (MeshListen) follows a
 * friend's song with this player when it is signed in.
 */
Singleton {
    id: root

    readonly property string bin: "nixbook-ytmusic"
    // {signedIn, account, browser, player, lastfm: {on, user}}; null until read.
    property var state: null
    readonly property bool signedIn: root.state?.signedIn ?? false
    readonly property string account: root.state?.account ?? ""
    readonly property bool lastfmOn: root.state?.lastfm?.on ?? false
    readonly property string lastfmUser: root.state?.lastfm?.user ?? ""
    // The player on the bus (only while something is loaded).
    readonly property MprisPlayer player: Mpris.players.values.find(p => String(p?.dbusName ?? "").includes("nixbook_ytmusic")) ?? null

    function refresh() {
        root.run(["status"], "", (ok, answer) => {
            if (ok) root.state = answer;
        });
    }
    Component.onCompleted: root.refresh()

    // The playlists ({id, title, count, author, thumb: a cached file}), Liked
    // Music first; kept so the tab shows them at once while it refreshes.
    property var playlists: null
    // The playlists came from their last copy (no network).
    property bool playlistsOffline: false
    property real playlistsAt: 0
    property bool playlistsLoading: false
    property string playlistsError: ""
    function refreshPlaylists(force) {
        if (root.playlistsLoading || !root.signedIn) return;
        if (!force && root.playlists && Date.now() - root.playlistsAt < 5 * 60 * 1000) return;
        root.playlistsLoading = true;
        root.run(["playlists"], "", (ok, answer) => {
            root.playlistsLoading = false;
            if (ok) {
                root.playlists = answer.playlists ?? [];
                root.playlistsOffline = !!answer.offline;
                // Offline, or YouTube Music answered an empty library (the
                // last copy shown: `stale`): tried again soon.
                root.playlistsAt = answer.offline || answer.stale ? Date.now() - 4 * 60 * 1000 : Date.now();
                root.playlistsError = "";
            } else root.playlistsError = answer?.error ?? "";
        });
    }
    onSignedInChanged: {
        if (root.signedIn) {
            root.refreshPlaylists(true);
            root.refreshOffline();
        } else root.playlists = null;
    }

    // Offline listening (`nixbook-ytmusic offline`): {limitMB, auto, used,
    // count, kept: [{id, title, total, cached}], downloading: {videoId,
    // title, artist}|null, left, full, error}. Songs heard 30 s (auto) and
    // the playlists kept offline are downloaded by the player's service, in
    // ~/.cache/nixbook-ytmusic/offline; over limitMB the least recently
    // played go, never a kept playlist's. Read while the tab shows (every
    // 2 s while something downloads), and after each change.
    property var offline: null
    readonly property bool downloading: (root.offline?.downloading ?? null) !== null
    property bool offlineWatched: false
    function refreshOffline() {
        root.run(["offline", "status"], "", (ok, answer) => {
            if (ok) root.offline = answer;
        });
    }
    function offlineDo(args, then) {
        root.run(["offline", ...args], "", (ok, answer) => {
            if (ok) root.offline = answer;
            if (then) then(ok, answer);
        });
    }
    function isKept(id) {
        return (root.offline?.kept ?? []).some(k => k.id === id);
    }
    function keepOffline(id, title, then) {
        root.offlineDo(["keep", id, ...String(title ?? "").split(/\s+/).filter(w => w !== "")], then);
    }
    function unkeepOffline(id, then) {
        root.offlineDo(["unkeep", id], then);
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.offlineWatched && (root.downloading || (root.offline?.left ?? 0) > 0)
        onTriggered: root.refreshOffline()
    }
    onDownloadingChanged: if (!root.downloading && root.signedIn) root.refreshPlaylists(true)

    // The playlists songs can be added to (yours; Liked Music likes the
    // song); a copy of the list from before `own` existed counts them all.
    readonly property var ownPlaylists: (root.playlists ?? []).filter(p => p.id !== "_offline" && (p.own ?? true))
    // A song into one of them: then(ok, answer {status: added|already} or
    // {error}); the playlists read again (their counts).
    function addToPlaylist(playlistId, videoId, then) {
        root.run(["add", playlistId, videoId], "", (ok, answer) => {
            if (ok) root.refreshPlaylists(true);
            if (then) then(ok, answer);
        });
    }
    function isOwn(playlistId) {
        return root.ownPlaylists.some(p => p.id === playlistId);
    }
    // A song out of one of them (`track` from its songs: its setVideoId says
    // which copy; Liked Music: the like taken back): then(ok, answer
    // {status: removed|absent} or {error}); the playlists read again.
    function removeFromPlaylist(playlistId, track, then) {
        const item = track?.setVideoId ? [track.setVideoId] : [];
        root.run(["remove", playlistId, track?.videoId ?? "", ...item], "", (ok, answer) => {
            if (ok) root.refreshPlaylists(true);
            if (then) then(ok, answer);
        });
    }
    // A new private playlist with the song in it: then(ok, {playlist, title}).
    function createPlaylist(title, videoId, then) {
        const words = String(title ?? "").trim().split(/\s+/).filter(w => w !== "");
        root.run(["create", ...words, videoId], "", (ok, answer) => {
            if (ok) root.refreshPlaylists(true);
            if (then) then(ok, answer);
        });
    }

    // A playlist's songs ({id, title, tracks: [{videoId, title, artist,
    // album, duration, art, thumb, cached}], kept, offline: from its last
    // copy}); then(ok, answer). "_offline": every song on this computer.
    function playlist(id, then) {
        root.run(["playlist", id], "", then);
    }
    // Songs and videos on YouTube Music ({query, songs, videos}, each like a
    // playlist's tracks with `kind`, art as links); only the latest search
    // answers: an earlier one still running is dropped when it ends.
    property int _searchGen: 0
    function search(query, then) {
        const gen = ++root._searchGen;
        root.run(["search", ...String(query).trim().split(/\s+/)], "", (ok, answer) => {
            if (gen === root._searchGen && then) then(ok, answer);
        });
    }
    function cancelSearch() {
        root._searchGen++;
    }
    // Plays `tracks` from `index` (shuffled); then(ok, answer).
    function playTracks(tracks, index, shuffle, playlistId, then) {
        root.run(["play-tracks"], JSON.stringify({ tracks: tracks, index: index, shuffle: !!shuffle, playlist: playlistId ?? "" }), then);
    }
    // One song (a friend's, listening along), from `start` seconds.
    function playId(videoId, start, then) {
        root.run(["play-id", videoId, "--start", String(Math.max(0, Math.floor(start ?? 0)))], "", then);
    }
    function control(action, value, then) {
        root.run(["control", action, ...(value !== undefined && value !== "" ? [String(value)] : [])], "", then);
    }

    // Signing in: the browsers (and the YouTube Music app) with a YouTube
    // login, the most recent first; the session of one (or the most recent).
    function browsers(then) {
        root.run(["browsers"], "", then);
    }
    function login(browser, then) {
        root.run(["login-from-browser", ...(browser ? [browser] : [])], "", (ok, answer) => {
            root.refresh();
            if (then) then(ok, answer);
        });
    }
    function forget(then) {
        root.run(["forget"], "", (ok, answer) => {
            root.refresh();
            if (then) then(ok, answer);
        });
    }

    // Last.fm: the desktop sign-in (start opens the page where you allow it;
    // finish once allowed), or the YouTube Music app's own sign-in.
    function lastfm(what, input, then) {
        root.run(["lastfm", what], input ?? "", (ok, answer) => {
            if (ok && what === "start" && answer?.url) AppLaunch.openUrl(answer.url);
            if (what !== "status") root.refresh();
            if (then) then(ok, answer);
        });
    }

    // `nixbook-ytmusic ARGS`, `input` on stdin; then(ok, answer).
    function run(args, input, then) {
        runner.createObject(root, { input: input ?? "", then: then ?? null, command: [root.bin, ...args] });
    }
    Component {
        id: runner
        Process {
            id: proc
            property string input
            property var then
            stdinEnabled: true
            stdout: StdioCollector { id: out }
            Component.onCompleted: proc.running = true
            onRunningChanged: {
                if (!proc.running) return;
                proc.write(proc.input + "\n");
                proc.stdinEnabled = false;
            }
            onExited: code => {
                let answer = null;
                try {
                    answer = JSON.parse(out.text);
                } catch (e) {}
                // The player's commands answer {ok, result}; the others the
                // result itself, or {error}.
                const ok = code === 0 && !!answer && !answer.error && answer.ok !== false;
                const result = answer && "result" in answer ? answer.result : answer;
                const done = proc.then;
                proc.destroy();
                if (done) done(ok, ok ? result : (answer ?? { error: Translation.tr("Couldn't run nixbook-ytmusic") }));
            }
        }
    }

    IpcHandler {
        target: "youtubeMusic"
        function status(): string {
            return JSON.stringify({ signedIn: root.signedIn, account: root.account, lastfm: root.lastfmOn,
                playing: root.player ? { title: root.player.trackTitle, artist: root.player.trackArtist,
                    status: root.player.isPlaying ? "Playing" : "Paused" } : null });
        }
        // A playlist by its id (LM: Liked Music), from its first song.
        function play(playlistId: string): void {
            root.playlist(playlistId, (ok, answer) => {
                if (ok) root.playTracks(answer.tracks ?? [], 0, false, playlistId);
            });
        }
        function shuffle(playlistId: string): void {
            root.playlist(playlistId, (ok, answer) => {
                if (ok) root.playTracks(answer.tracks ?? [], 0, true, playlistId);
            });
        }
        function toggle(): void { root.control("toggle"); }
        function next(): void { root.control("next"); }
        function previous(): void { root.control("previous"); }
        function stop(): void { root.control("stop"); }
    }
}
