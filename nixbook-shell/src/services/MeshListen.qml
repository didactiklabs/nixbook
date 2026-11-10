pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

/**
 * Listening together over the mesh (services/Mesh.qml): one person shares
 * what their YouTube Music or Spotify plays, in a conversation (everyone, or
 * one person); the others listen along: their own player opens the same
 * song, at the same moment, and follows the host's pauses, seeks and next
 * songs. A listener with the other app follows there: a Spotify song is
 * found on YouTube Music (`nixbook-mesh match`); a YouTube Music song opens
 * Spotify's search (Spotify has no search without an account).
 *
 * The host sends a `listen` event {op: state, sid, service, track, position,
 * playing, at} when something changes and every 20 s; listeners say join /
 * leave; `end` closes the session. Private sessions are sealed for their
 * member alone, like private messages. A listener who plays something else
 * or pauses stops following. Nothing is kept on disk.
 */
Singleton {
    id: root

    // -- Players -------------------------------------------------------------------

    // The MPRIS players (tests put fakes here).
    property var testPlayers: null
    function players() {
        return root.testPlayers ?? Mpris.players.values;
    }

    function serviceOf(p) {
        const names = `${p?.dbusName ?? ""} ${p?.identity ?? ""} ${p?.desktopEntry ?? ""}`;
        if (/jellyfin.?mpv.?shim|iwalton3/i.test(names)) return "jellyfin";
        if (/youtube.?music|pear.?desktop|th.ch/i.test(names)) return "youtube-music";
        if (/spotify/i.test(names)) return "spotify";
        return "";
    }
    function serviceName(service) {
        return service === "spotify" ? "Spotify" : service === "youtube-music" ? "YouTube Music"
            : service === "jellyfin" ? "Jellyfin" : "";
    }
    function playerFor(service) {
        return root.players().find(p => root.serviceOf(p) === service) ?? null;
    }
    // The song a player is on: { id, title, artist, album, length, art }, or
    // null (nothing, or an ad).
    function trackOf(p) {
        if (!p) return null;
        const md = p.metadata ?? {};
        let id = "";
        if (root.serviceOf(p) === "jellyfin") {
            // jellyfin-mpv-shim: the Jellyfin item's id, in the track path.
            id = (String(md["mpris:trackid"] ?? "").match(/\/jellyfin_mpv_shim\/track\/([\w-]+)$/) ?? [])[1] ?? "";
        } else if (root.serviceOf(p) === "youtube-music") {
            id = (String(md["xesam:url"] ?? "").match(/[?&]v=([\w-]{11})/) ?? [])[1]
                ?? (String(md["mpris:trackid"] ?? "").match(/\/([\w-]{11})$/) ?? [])[1] ?? "";
        } else {
            id = (String(md["mpris:trackid"] ?? "").match(/^\/com\/spotify\/track\/(\w+)$/) ?? [])[1] ?? "";
        }
        if (id === "") return null;
        return { id: id, title: p.trackTitle ?? "", artist: p.trackArtist ?? "", album: p.trackAlbum ?? "",
            length: p.length > 0 ? p.length : 0, art: /^https:\/\//.test(p.trackArtUrl ?? "") ? p.trackArtUrl : "" };
    }
    function uriFor(service, id) {
        return service === "spotify" ? `spotify:track:${id}` : `https://music.youtube.com/watch?v=${id}`;
    }
    function installed(service) {
        const ids = service === "spotify" ? ["spotify", "com.spotify.Client"]
            : ["com.github.th-ch.youtube-music", "pear-desktop", "youtube-music"];
        return ids.map(id => DesktopEntries.byId(id)).find(e => !!e) ?? null;
    }
    // Where this desktop listens to `service`'s songs: an app already open
    // (the host's, else the other), else one to start (the host's first).
    function localService(service) {
        // Jellyfin: this computer's mpv, once Jellyfin is set up here.
        if (service === "jellyfin") return root.jellyfinReady() ? "jellyfin" : "";
        const other = service === "spotify" ? "youtube-music" : "spotify";
        if (root.playerFor(service)) return service;
        if (root.playerFor(other)) return other;
        if (root.installed(service)) return service;
        if (root.installed(other)) return other;
        return "";
    }
    // Jellyfin set up here (services/Jellyfin.qml, Settings > Services >
    // Jellyfin): a plain service, whatever the AI switches say.
    property var testJellyfin: null
    function jellyfinReady() {
        return root.testJellyfin !== null ? true : Jellyfin.ready;
    }
    // `jellyfin-mcp ARGS` (stdin: `input`), then(ok, answer). Tests answer
    // through testJellyfin(args, input).
    function jellyfin(args, input, then) {
        if (root.testJellyfin !== null) {
            const answer = root.testJellyfin(args, input);
            Qt.callLater(() => then(!!answer?.ok, answer ?? {}));
            return;
        }
        Jellyfin.run(args, input, then);
    }
    // What a Jellyfin item is, for listeners on other servers: { id: info | null }.
    property var _jfInfo: ({})

    // What can be shared now: the player in front if it is one of the two,
    // else one of them playing, else any of them.
    function shareablePlayer() {
        const active = MprisController.activePlayer;
        const players = root.players().filter(p => root.serviceOf(p) !== "");
        const has = p => root.trackOf(p) !== null;
        // Something on it first (playing, then paused), the one in front
        // first among equals; an empty one last.
        const order = [p => has(p) && p.isPlaying, p => has(p), p => true];
        for (const ok of order) {
            if (root.serviceOf(active) !== "" && ok(active)) return active;
            const p = players.find(ok);
            if (p) return p;
        }
        return null;
    }
    readonly property bool canShare: root.shareablePlayer() !== null

    // -- Sessions --------------------------------------------------------------------

    // Everyone else's: { sid: { sid, host, hostName, to, service, track,
    // position, playing, at, recv, listeners: { id: ms } } }.
    property var sessions: ({})
    // This desktop's own: { sid, to, bus, listeners } or null.
    property var hosting: null
    // The session followed ("" = none), and how it goes: "synced",
    // "opening", "starting", "matching", "search", "nomatch", "noapp".
    property string following: ""
    property string followStatus: ""
    // Why the last session followed ended, for the Mesh tab.
    property string notice: ""

    function conversationOf(s) {
        return (s?.to ?? "") === "" ? "" : s.host;
    }
    function sessionIn(conv) {
        return Object.values(root.sessions).find(s => root.conversationOf(s) === conv) ?? null;
    }
    function hostingIn(conv) {
        return root.hosting && root.hosting.to === conv;
    }
    function listenersOf(listeners) {
        return Object.keys(listeners ?? {}).map(id => Mesh.nameOf(id));
    }
    function _sid() {
        let s = "";
        for (let i = 0; i < 16; i++) s += Math.floor(Math.random() * 16).toString(16);
        return s;
    }

    // -- Hosting ------------------------------------------------------------------------

    // Share what plays in the conversation `conv` ("" = everyone). Returns
    // "" or why not.
    function start(conv) {
        if (!Mesh.configured) return Translation.tr("The mesh isn't set up");
        const p = root.shareablePlayer();
        if (!p) return Translation.tr("Play something in YouTube Music, Spotify or Jellyfin first");
        if (root.following !== "") root.leave("");
        if (root.hosting) root.stop();
        root.hosting = { sid: root._sid(), to: conv ?? "", bus: p.dbusName, listeners: {} };
        root.hostService = root.serviceOf(p);
        root.hostTrack = null;
        root._last = null;
        root._hostTick(true);
        return "";
    }
    function stop() {
        if (!root.hosting) return;
        Mesh._send("listen", { to: root.hosting.to, op: "end", sid: root.hosting.sid });
        root.hosting = null;
        root.hostTrack = null;
    }
    // The song (or film) shared now, and its app (the Mesh tab shows it).
    property var hostTrack: null
    property string hostService: ""
    property var _jfAsking: ({})
    property var _last: null // what was sent last: { key, playing, position, at }
    property string _pendingKey: ""
    property real _goneSince: 0
    function _hostTick(force) {
        const h = root.hosting;
        if (!h) return;
        const now = Date.now();
        let p = root.players().find(x => x.dbusName === h.bus) ?? root.shareablePlayer();
        // Nothing on the one shared, something on another: that one now.
        if (p && root.trackOf(p) === null) {
            const other = root.shareablePlayer();
            if (other && root.trackOf(other) !== null) p = other;
        }
        if (!p) {
            if (root._goneSince === 0) root._goneSince = now;
            else if (now - root._goneSince > 60000) root.stop();
            return;
        }
        root._goneSince = 0;
        if (p.dbusName !== h.bus) root.hosting = Object.assign({}, h, { bus: p.dbusName });
        root.hostService = root.serviceOf(p);
        const track = root.trackOf(p);
        if (!track) return;
        const service = root.serviceOf(p);
        const key = `${service}:${track.id}`;
        const position = p.position ?? 0;
        // Jellyfin: what the item is, once (a listener on another server
        // finds it by that), before the first state.
        if (service === "jellyfin" && !(track.id in root._jfInfo)) {
            if (!root._jfAsking[track.id]) {
                root._jfAsking[track.id] = true;
                root.jellyfin(["listen-info", track.id], "", (ok, answer) => {
                    root._jfInfo = Object.assign({}, root._jfInfo, { [track.id]: ok ? answer : null });
                    delete root._jfAsking[track.id];
                });
            }
            return;
        }
        const last = root._last;
        let send = force || !last;
        if (last && key !== last.key) {
            // A new song: once its metadata has settled (one tick).
            if (root._pendingKey !== key) {
                root._pendingKey = key;
                return;
            }
            send = true;
        }
        if (last && p.isPlaying !== last.playing) send = true;
        if (last && key === last.key) {
            const expected = last.position + (last.playing ? (now - last.at) / 1000 : 0);
            if (Math.abs(expected - position) > 3) send = true; // a seek
        }
        if (last && now - last.at > 20000) send = true;
        if (!send) return;
        root._pendingKey = "";
        root._last = { key: key, playing: p.isPlaying, position: position, at: now };
        root.hostTrack = track;
        root.hostService = service;
        const state = { to: h.to, op: "state", sid: h.sid, service: service, track: track,
            position: position, playing: p.isPlaying, at: now };
        if (service === "jellyfin" && root._jfInfo[track.id]) state.jf = root._jfInfo[track.id];
        Mesh._send("listen", state);
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.hosting !== null
        onTriggered: root._hostTick(false)
    }

    // -- Listening along ---------------------------------------------------------------

    function join(sid) {
        const s = root.sessions[sid];
        if (!s) return;
        if (root.hosting) root.stop();
        if (root.following !== "" && root.following !== sid) root.leave("");
        root.following = sid;
        root.notice = "";
        root.followStatus = "";
        root._f = { jfFor: "", jfLocal: "", jfBusy: false, jfError: "", syncedTo: "", openedFor: "", stateRecv: 0, openedAt: 0, cmdAt: 0, seekAt: 0, launchedAt: 0, sawPlaying: false, lastPos: 0, lastLen: 0, searched: "" };
        Mesh._send("listen", { to: s.to === "" ? "" : s.host, op: "join", sid: sid });
        root._followTick();
    }
    function leave(reason) {
        const s = root.sessions[root.following];
        if (s) Mesh._send("listen", { to: s.to === "" ? "" : s.host, op: "leave", sid: s.sid });
        root.following = "";
        root.followStatus = "";
        root.notice = reason ?? "";
    }
    property var _f: ({})
    // Spotify songs found on YouTube Music: { "spotify:<id>": videoId | null }.
    property var _matches: ({})
    function _followTick() {
        const s = root.sessions[root.following];
        const now = Date.now();
        if (!s) {
            root.leave(Translation.tr("The session ended"));
            return;
        }
        const f = root._f;
        const svc = root.localService(s.service);
        if (svc === "") {
            root.followStatus = "noapp";
            return;
        }
        const target = s.position + (s.playing ? (now - s.at) / 1000 : 0);
        if (s.service === "jellyfin") {
            root._followJellyfin(s, f, now, target);
            return;
        }
        const key = `${s.service}:${s.track.id}`;
        let wantId = s.track.id;
        if (svc !== s.service) {
            if (svc === "youtube-music") {
                if (!(key in root._matches)) {
                    root.followStatus = "matching";
                    root._match(key, s.track);
                    return;
                }
                if (root._matches[key] === null) {
                    root.followStatus = "nomatch";
                    return;
                }
                wantId = root._matches[key];
            } else {
                // YouTube Music → Spotify: its search, the listener picks.
                if (f.searched !== key) {
                    f.searched = key;
                    AppLaunch.openUrl(`spotify:search:${encodeURIComponent(`${s.track.artist} ${s.track.title}`.trim())}`);
                }
                root.followStatus = "search";
                return;
            }
        }
        const p = root.playerFor(svc);
        if (!p) {
            if (now - f.launchedAt > 20000) {
                f.launchedAt = now;
                const entry = root.installed(svc);
                if (entry) AppLaunch.launchEntry(entry);
                else AppLaunch.openUrl(root.uriFor(svc, wantId));
            }
            root.followStatus = "starting";
            return;
        }
        const cur = root.trackOf(p)?.id ?? "";
        if (cur !== wantId) {
            // Synced on this very song, and it changed here while the host
            // stayed on it, not at its end: the listener played something else.
            if (f.syncedTo === wantId && cur !== "" && !(f.lastLen > 0 && f.lastPos > f.lastLen - 8)) {
                root.leave(Translation.tr("You played something else, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host)));
                return;
            }
            // Once per song (again after 8 s, if it didn't take).
            if (f.openedFor !== wantId || now - f.openedAt > 8000) {
                const uri = root.uriFor(svc, wantId);
                const scheme = uri.split(":")[0];
                if ((p.supportedUriSchemes ?? []).map(x => String(x).toLowerCase()).includes(scheme)) p.openUri(uri);
                else AppLaunch.openUrl(uri);
                f.openedAt = now;
                f.openedFor = wantId;
                f.sawPlaying = false;
            }
            root.followStatus = "opening";
            return;
        }
        root._keepInSync(p, s, f, now, target, wantId);
    }
    // The song (or film) is the host's: the same play/pause and position.
    function _keepInSync(p, s, f, now, target, wantId) {
        f.syncedTo = wantId;
        // A new state from the host (a seek, a pause): followed at once.
        if (f.stateRecv !== s.recv) {
            f.stateRecv = s.recv;
            f.seekAt = 0;
        }
        f.lastPos = p.position ?? 0;
        f.lastLen = p.length > 0 ? p.length : 0;
        if (s.playing) {
            if (p.isPlaying) {
                f.sawPlaying = true;
            } else if (f.sawPlaying && now - f.cmdAt > 3000 && now - f.openedAt > 6000 && now - s.recv > 2000) {
                root.leave(Translation.tr("You paused, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host)));
                return;
            } else if (now - f.cmdAt > 2000 && p.canPlay) {
                p.play();
                f.cmdAt = now;
            }
        } else if (p.isPlaying && now - f.cmdAt > 1500 && p.canPause) {
            p.pause();
            f.cmdAt = now;
            f.sawPlaying = false;
        }
        const len = p.length > 0 ? p.length : s.track.length;
        if (p.canSeek && now - f.openedAt > 2500 && now - f.seekAt > 4000 && Math.abs((p.position ?? 0) - target) > 2.5
                && (len <= 0 || target < len - 2)) {
            p.position = Math.max(0, target);
            f.seekAt = now;
        }
        root.followStatus = "synced";
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.following !== ""
        onTriggered: root._followTick()
    }
    // Jellyfin: jellyfin-mcp finds the item on this computer's server (the
    // same one, or by its IMDb/TMDb/TVDb ids, or names) and plays it on mpv
    // from the host's position; then mpv's MPRIS follows like music.
    function _followJellyfin(s, f, now, target) {
        const host = s.hostName || Mesh.nameOf(s.host);
        const key = `jellyfin:${s.track.id}`;
        const p = root.playerFor("jellyfin");
        const cur = root.trackOf(p)?.id ?? "";
        const nearEnd = f.lastLen > 0 && f.lastPos > f.lastLen - 15;
        if (f.jfFor !== key || (f.jfLocal !== "" && cur !== f.jfLocal && f.syncedTo !== f.jfLocal && now - f.openedAt > 25000)) {
            if (f.jfBusy) {
                root.followStatus = "opening";
                return;
            }
            f.jfFor = key;
            f.jfBusy = true;
            f.jfLocal = "";
            f.jfError = "";
            f.syncedTo = "";
            f.sawPlaying = false;
            const want = Object.assign({ id: s.track.id }, s.jf ?? {}, { position: target + 2 });
            root.jellyfin(["listen-play"], JSON.stringify(want), (ok, answer) => {
                if (root._f !== f) return;
                f.jfBusy = false;
                f.openedAt = Date.now();
                if (ok) f.jfLocal = `${answer.id ?? ""}`;
                else f.jfError = answer.notFound ? "notonserver" : `${answer.error ?? ""}`;
            });
            root.followStatus = "opening";
            return;
        }
        if (f.jfBusy) {
            root.followStatus = "opening";
            return;
        }
        if (f.jfLocal === "") {
            root.followStatus = f.jfError === "notonserver" ? "notonserver" : "jferror";
            root.followError = f.jfError;
            return;
        }
        if (!p || cur !== f.jfLocal) {
            // Watching it here, and it changed (or stopped) not at its end:
            // the listener did something else.
            if (f.syncedTo === f.jfLocal && !nearEnd) {
                root.leave(cur === ""
                    ? Translation.tr("You stopped, so you stopped watching along with %1").arg(host)
                    : Translation.tr("You played something else, so you stopped watching along with %1").arg(host));
                return;
            }
            root.followStatus = "opening";
            return;
        }
        root._keepInSync(p, s, f, now, target, f.jfLocal);
    }
    property string followError: ""
    function _match(key, track) {
        if (root._matching[key]) return;
        root._matching = Object.assign({}, root._matching, { [key]: true });
        Mesh.run(["match"], JSON.stringify({ title: track.title, artist: track.artist, album: track.album, length: track.length }),
            (ok, answer) => {
                root._matches = Object.assign({}, root._matches, { [key]: ok ? answer.videoId : null });
                const m = Object.assign({}, root._matching);
                delete m[key];
                root._matching = m;
            });
    }
    property var _matching: ({})

    // -- What arrives (Mesh._event) -------------------------------------------------------

    function receive(e) {
        const d = e.data ?? {};
        const sid = `${d.sid ?? ""}`;
        if (sid === "" || e.mine) return;
        const from = `${e.from ?? ""}`;
        if (d.op === "join" || d.op === "leave") {
            const h = root.hosting;
            if (h && h.sid === sid) {
                const l = Object.assign({}, h.listeners);
                if (d.op === "join") l[from] = Date.now();
                else delete l[from];
                root.hosting = Object.assign({}, h, { listeners: l });
                // A newcomer: the state now, not in 20 s.
                if (d.op === "join") root._hostTick(true);
            }
            const s = root.sessions[sid];
            if (s) {
                const l = Object.assign({}, s.listeners);
                if (d.op === "join") l[from] = Date.now();
                else delete l[from];
                root._put(Object.assign({}, s, { listeners: l }));
            }
            return;
        }
        if (d.op === "end") {
            const s = root.sessions[sid];
            if (!s) return;
            const next = Object.assign({}, root.sessions);
            delete next[sid];
            root.sessions = next;
            if (root.following === sid)
                root.leave(Translation.tr("%1 stopped sharing their music").arg(s.hostName || Mesh.nameOf(s.host)));
            return;
        }
        if (d.op !== "state" || !d.track?.id) return;
        // The host's other sessions are over: one at a time.
        const prev = root.sessions[sid];
        const s = { sid: sid, host: from, hostName: e.name ?? "", to: e.to ?? "", service: d.service, track: d.track,
            jf: d.jf ?? null,
            position: Number(d.position ?? 0), playing: !!d.playing, at: Number(d.at ?? Date.now()), recv: Date.now(),
            listeners: prev?.listeners ?? {} };
        const next = {};
        for (const [id, x] of Object.entries(root.sessions))
            if (x.host !== from || id === sid) next[id] = x;
        next[sid] = s;
        root.sessions = next;
        if (!prev && Date.now() - s.at < 60000) root._announce(s);
    }
    function _put(s) {
        root.sessions = Object.assign({}, root.sessions, { [s.sid]: s });
    }
    // A host silent for long has gone (no `end`: a shut computer).
    Timer {
        interval: 15000
        repeat: true
        running: Object.keys(root.sessions).length > 0
        onTriggered: {
            const now = Date.now();
            const next = {};
            for (const [id, s] of Object.entries(root.sessions))
                if (now - s.recv < 75000) next[id] = s;
            if (Object.keys(next).length !== Object.keys(root.sessions).length) root.sessions = next;
        }
    }

    function _announce(s) {
        if (!(Config.options?.mesh?.notify ?? true)) return;
        const who = s.hostName || Mesh.nameOf(s.host);
        const what = [s.track.title, s.track.artist].filter(x => x).join(" — ");
        const video = s.service === "jellyfin";
        notifier.createObject(root, {
            sid: s.sid,
            command: ["notify-send", `--app-name=${who}`, "--icon=audio-headphones",
                `--hint=string:x-nixbook-mesh:${s.to === "" ? "nixbook-mesh-everyone" : "nixbook-mesh-direct"}`,
                "--wait", `--action=listen=${video ? Translation.tr("Watch along") : Translation.tr("Listen along")}`, "--",
                video ? Translation.tr("%1 is sharing what they watch").arg(who) : Translation.tr("%1 is sharing their music").arg(who), what]
        });
    }
    Component {
        id: notifier
        Process {
            id: proc
            property string sid
            stdout: StdioCollector { id: out }
            Component.onCompleted: proc.running = true
            onExited: {
                if (out.text.trim() === "listen" && root.sessions[proc.sid]) {
                    root.join(proc.sid);
                    Mesh.open(root.conversationOf(root.sessions[proc.sid]));
                }
                proc.destroy();
            }
        }
    }

    // Stopping the mesh, or the shell: tell the others.
    Connections {
        target: Mesh
        function onConfiguredChanged() {
            if (!Mesh.configured) {
                root.hosting = null;
                root.following = "";
                root.sessions = {};
            }
        }
    }
    Component.onDestruction: {
        if (root.hosting) root.stop();
        if (root.following !== "") root.leave("");
    }
}
