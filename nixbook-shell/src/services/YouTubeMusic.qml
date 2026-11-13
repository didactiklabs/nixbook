pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
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
    // Created at startup (shell.qml): links reach it before any tab is built.
    function load() {}

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

    // YouTube's videos (the YouTube tab, sidebar.youtubeTab): your home
    // page and your subscriptions' latest with the same session, a search
    // without one too ({feed, items: [{id, title, channel, duration, views,
    // live, thumb}], at}); `cached`: the last copy, at once.
    function videos(feed, count, cached, then) {
        root.run(["videos", feed, "--count", String(count), ...(cached ? ["--cached"] : [])], "", then);
    }
    // Out of New (your subscriptions' videos not seen yet): marked seen.
    function markVideosSeen(ids, then) {
        const valid = (ids ?? []).filter(id => /^[A-Za-z0-9_-]{11}$/.test(String(id)));
        if (!valid.length) return;
        root.run(["videos", "seen", ...valid], "", then);
    }
    // Only the latest search answers (as `search`).
    property int _videoSearchGen: 0
    function searchVideos(query, count, then) {
        const gen = ++root._videoSearchGen;
        root.run(["videos", "search", ...String(query).trim().split(/\s+/), "--count", String(count)], "", (ok, answer) => {
            if (gen === root._videoSearchGen && then) then(ok, answer);
        });
    }
    function cancelVideoSearch() {
        root._videoSearchGen++;
    }
    // A YouTube link (watch?v=, youtu.be/, /shorts/, /live/, /embed/,
    // music.youtube.com): {id, start (seconds, from t=/start=)}, or null.
    // Links only: a bare id looks like an ordinary word to search for.
    function parseVideoLink(text) {
        const t = String(text ?? "").trim();
        const m = t.match(/^(?:https?:\/\/)?(?:(?:www|m|music)\.)?(?:youtube\.com\/(?:watch\?(?:[^#\s]*&)?v=|shorts\/|live\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])([^\s]*)$/);
        if (!m) return null;
        const tm = m[2].match(/[?&#](?:t|start)=([0-9hms]+)/);
        let start = 0;
        if (tm) {
            const v = tm[1];
            if (/^[0-9]+$/.test(v)) start = Number(v);
            else {
                const h = Number((v.match(/([0-9]+)h/) ?? [])[1] ?? 0), mi = Number((v.match(/([0-9]+)m/) ?? [])[1] ?? 0),
                    s = Number((v.match(/([0-9]+)s/) ?? [])[1] ?? 0);
                start = h * 3600 + mi * 60 + s;
            }
        }
        return { id: m[1], start: start };
    }
    // Subscribe to a channel (UC…), or no longer; then(ok, answer).
    function subscribeChannel(channelId, on, then) {
        root.run(["videos", on ? "subscribe" : "unsubscribe", channelId], "", then);
    }
    // One video by its id (its title and channel through oEmbed), as a search
    // answers; only the latest asked answers (shares the search's turn).
    function videoInfo(id, then) {
        const gen = ++root._videoSearchGen;
        root.run(["videos", "video", id], "", (ok, answer) => {
            if (gen === root._videoSearchGen && then) then(ok, answer);
        });
    }
    // A channel's latest videos, newest first (its link, or a video's id
    // when the feed didn't give the link): {channel: {name, url, followers},
    // items}; only the latest asked answers.
    // `tab`: latest|popular|shorts|live|playlists; `query`: a search in it.
    property int _channelGen: 0
    function channelVideos(urlOrVideo, count, then, tab, query) {
        const gen = ++root._channelGen;
        const q = String(query ?? "").trim();
        root.run(["videos", "channel", String(urlOrVideo), "--count", String(count), "--tab", tab || "latest",
            ...(q !== "" ? ["--query", ...q.split(/\s+/)] : [])], "", (ok, answer) => {
            if (gen === root._channelGen && then) then(ok, answer);
        });
    }
    // A playlist's videos (a channel's Playlists tab); shares the channel's turn.
    function playlistVideos(id, count, then) {
        const gen = ++root._channelGen;
        root.run(["videos", "playlist", String(id), "--count", String(count)], "", (ok, answer) => {
            if (gen === root._channelGen && then) then(ok, answer);
        });
    }
    function cancelChannel() {
        root._channelGen++;
    }
    // A video in mpv (the user's, with their config), started through niri
    // so it outlives the shell: `nixbook-ytmusic watch` by its full path
    // (niri's environment hasn't the shell's PATH).
    property string binPath: ""
    Process {
        running: true
        command: ["sh", "-c", `command -v ${root.bin}`]
        stdout: StdioCollector {
            onStreamFinished: root.binPath = this.text.trim()
        }
    }
    // The video opened in mpv (by the YouTube tab or an agent): its MPRIS
    // player, found by the YouTube link mpv publishes; not this background
    // player, nor Jellyfin's. The last one when there are several.
    readonly property MprisPlayer videoPlayer: {
        const found = Mpris.players.values.filter(p => !String(p?.dbusName ?? "").includes("nixbook_ytmusic")
            && /^https:\/\/(www\.|m\.)?(youtube\.com\/watch\?|youtu\.be\/)/.test(String(p?.metadata?.["xesam:url"] ?? "")));
        return found.length ? found[found.length - 1] : null;
    }
    // Its own volume (mpv's), remembered for the next video.
    function setVideoVolume(value) {
        const v = Math.max(0, Math.min(1, value));
        if (root.videoPlayer) MprisController.setPlayerVolume(root.videoPlayer, v);
        Persistent.states.media.videoVolume = v;
    }
    // `start`: from that second (watching along with someone in the mesh).
    function watch(videoId, start) {
        if (!/^[A-Za-z0-9_-]{11}$/.test(String(videoId ?? ""))) return false;
        // At the volume the tab was last left at.
        const volume = Math.round(Math.max(0, Math.min(1, Persistent.states.media.videoVolume ?? 1)) * 100);
        const from = Math.floor(Number(start ?? 0));
        AppLaunch.spawn([root.binPath || root.bin, "watch", videoId, "--volume", String(volume),
            ...(from > 3 ? ["--start", String(from)] : [])]);
        return true;
    }

    // YouTube links opened by the shell instead of the browser, anywhere on
    // the machine (media.youtubeLinks: off by default, Settings > Apps &
    // accounts > YouTube links, or Nix): clicked in Zen (its extension
    // zen-youtube/) or opened by an app (nixbook's http(s) link router);
    // both run `nixbook-youtube-link URL`. A video plays in mpv (the YouTube
    // tab shows it), a YouTube Music song or playlist in the background
    // player, the right panel opened on its YouTube Music tab.
    // "" when taken; "off: …" when the settings don't take that kind of
    // link (Zen and the router then leave such links alone); else why not.
    // Either way the link then opens in the browser or its app.
    readonly property var linkChoice: {
        const c = Config.options?.media?.youtubeLinks;
        return { enable: c?.enable === true, videos: c?.videos !== false, music: c?.music !== false };
    }
    function openLink(url) {
        const t = YouTubeLinks.linkTarget(url);
        if (!t) return "not a YouTube video, song or playlist link";
        if (!YouTubeLinks.wanted(t, root.linkChoice))
            return "off: turned off in Settings > Apps & accounts > YouTube links";
        if (t.kind === "video") {
            if (!root.watch(t.id, t.start)) return "not a YouTube video id";
            // mpv's window is where it plays: the panel isn't opened over
            // it, only set to the tab that shows the video.
            root._showTab("youtube", Config.options.sidebar.youtubeTab, false);
            return "";
        }
        if (t.kind === "playlist") {
            if (!root.signedIn) return "YouTube Music isn't signed in here";
            root.playlist(t.list, (ok, answer) => {
                if (ok && (answer?.tracks ?? []).length) root.playTracks(answer.tracks, 0, false, t.list);
                else root._linkFailed(url, answer?.error);
            });
        } else if (t.list !== "" && !/^RD/.test(t.list) && root.signedIn) {
            // A song played from a playlist: that playlist, from the song
            // (a radio, RD…, isn't a playlist that can be read).
            root.playlist(t.list, (ok, answer) => {
                const tracks = ok ? (answer?.tracks ?? []) : [];
                const at = tracks.findIndex(x => x?.videoId === t.id);
                if (at >= 0) root.playTracks(tracks, at, false, t.list);
                else root._playSong(t, url);
            });
        } else root._playSong(t, url);
        root._showTab("youtubeMusic", Config.options.sidebar.youtubeMusicTab,
            Config.options?.media?.youtubeLinks?.openPanel !== false);
        return "";
    }
    // The choice as Zen's extension (through its native host, which watches
    // this file) and the link router read it, so they know at once which
    // links to bring here: $XDG_RUNTIME_DIR/nixbook-shell/youtube-links.json,
    // replaced by rename. Written once the settings are read, and on change.
    readonly property string linkChoiceFile: `${Directories.runtimeTemp}/youtube-links.json`
    onLinkChoiceChanged: if (Config.ready) root._writeLinkChoice()
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root._writeLinkChoice();
        }
    }
    function _writeLinkChoice() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p -m 700 "${2%/*}" && printf "%s\\n" "$1" > "$2.tmp" && mv -f "$2.tmp" "$2"',
            "sh", JSON.stringify(root.linkChoice), root.linkChoiceFile]);
    }
    // Whether something on this machine brings YouTube links here (Zen's
    // extension, a link router: hm-module.nix's youtubeLinks.available, in
    // youtube-links.json): Settings shows the switches only then.
    property bool linksAvailable: false
    FileView {
        id: linksFile
        path: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/nixbook-shell/youtube-links.json`
        printErrors: false
        onLoaded: {
            try {
                root.linksAvailable = JSON.parse(linksFile.text()).available === true;
            } catch (e) {
                root.linksAvailable = false;
            }
        }
        onLoadFailed: root.linksAvailable = false
    }
    function _playSong(t, url) {
        root.playId(t.id, t.start, (ok, answer) => {
            if (!ok) root._linkFailed(url, answer?.error);
        });
    }
    // `open`: the panel opened on the tab, else the tab only chosen (seen
    // when the panel is open or next opened).
    function _showTab(type, shown, open) {
        if (!shown) return;
        if (open) GlobalStates.sidebarRightOpen = true;
        // After the panel's own choice on opening (Notifications, when one
        // arrived while it was closed): this is the tab asked for.
        Qt.callLater(() => Persistent.states.sidebar.tab = type);
    }
    function _linkFailed(url, why) {
        Quickshell.execDetached(["notify-send", "--app-name=YouTube Music", "--icon=audio-x-generic",
            Translation.tr("Couldn't play that link"), `${why ? String(why) + "\n" : ""}${url}`]);
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

        // A YouTube link (a video, a YouTube Music song or playlist) opened by
        // the shell instead of the browser (`nixbook-youtube-link`,
        // media.youtubeLinks): "ok: KIND", "off: why" (the settings don't
        // take that kind of link), or "error: why".
        function openLink(url: string): string {
            const why = root.openLink(url);
            if (why === "") return `ok: ${YouTubeLinks.linkTarget(url).kind}`;
            return why.startsWith("off: ") ? why : `error: ${why}`;
        }
        // YouTube videos in mpv, as the YouTube tab opens them (desktop-mcp's
        // youtube_videos): a video by its id, at the tab's volume.
        function watch(videoId: string): string {
            return root.watch(videoId) ? "ok" : "error: not a YouTube video id";
        }
        function videoStatus(): string {
            const p = root.videoPlayer;
            if (!p) return JSON.stringify({ playing: null, volume: Math.round((Persistent.states.media.videoVolume ?? 1) * 100) });
            const url = String(p.metadata?.["xesam:url"] ?? "");
            return JSON.stringify({ playing: { title: p.trackTitle, videoId: (url.match(/[?&]v=([A-Za-z0-9_-]{11})/) ?? [])[1] ?? "",
                url: url, status: p.isPlaying ? "Playing" : "Paused", position: Math.round(p.position ?? 0),
                length: Math.round(p.length ?? 0), volume: Math.round(MprisController.playerVolume(p) * 100) } });
        }
        // play|pause|toggle|stop|seek SECONDS|volume 0-100.
        function videoControl(what: string, value: string): string {
            const p = root.videoPlayer;
            if (what === "volume") {
                const v = Number(value);
                if (!(v >= 0 && v <= 100)) return "error: volume: 0 to 100";
                root.setVideoVolume(v / 100);
                return "ok";
            }
            if (!p) return "error: no YouTube video is playing in mpv";
            if (what === "play") p.play();
            else if (what === "pause") p.pause();
            else if (what === "toggle") p.togglePlaying();
            else if (what === "stop") p.stop();
            else if (what === "seek") {
                const s = Number(value);
                if (!(s >= 0)) return "error: seek: seconds from the start";
                p.position = s;
            } else return "error: play, pause, toggle, stop, seek or volume";
            return "ok";
        }
    }
}
