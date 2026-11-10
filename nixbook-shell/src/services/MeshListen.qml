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
    // mpris:trackid as its object path: Quickshell hands it over as a
    // QVariant(QDBusObjectPath, QDBusObjectPath("/…")), whose string is that.
    function trackPath(md) {
        const raw = String(md?.["mpris:trackid"] ?? "");
        return (raw.match(/QDBusObjectPath\("([^"]*)"\)/) ?? [])[1] ?? raw;
    }
    function trackOf(p) {
        if (!p) return null;
        const md = p.metadata ?? {};
        const path = root.trackPath(md);
        let id = "";
        if (root.serviceOf(p) === "jellyfin") {
            // jellyfin-mpv-shim: the Jellyfin item's id, in the track path.
            id = (path.match(/\/jellyfin_mpv_shim\/track\/([\w-]+)$/) ?? [])[1] ?? "";
        } else if (root.serviceOf(p) === "youtube-music") {
            id = (String(md["xesam:url"] ?? "").match(/[?&]v=([\w-]{11})/) ?? [])[1]
                ?? (path.match(/\/([\w-]{11})$/) ?? [])[1] ?? "";
        } else {
            id = (path.match(/^\/com\/spotify\/track\/(\w+)$/) ?? [])[1] ?? "";
        }
        if (id === "") return null;
        return { id: id, title: p.trackTitle ?? "", artist: p.trackArtist ?? "", album: p.trackAlbum ?? "",
            length: p.length > 0 ? p.length : 0, art: /^https:\/\//.test(p.trackArtUrl ?? "") ? p.trackArtUrl : "" };
    }
    // `at`: where to start (seconds), so the song opens at the host's
    // position instead of a jump right after it starts.
    function uriFor(service, id, at) {
        if (service === "spotify") return `spotify:track:${id}`;
        const t = Math.floor(at ?? 0);
        return `https://music.youtube.com/watch?v=${id}${t > 3 ? `&t=${t}` : ""}`;
    }
    function installed(service) {
        const ids = service === "spotify" ? ["spotify", "com.spotify.Client"]
            : ["com.github.th-ch.youtube-music", "pear-desktop", "youtube-music"];
        return ids.map(id => DesktopEntries.byId(id)).find(e => !!e) ?? null;
    }
    // Starts `service`'s app (with `uri` on its command line: a bridged app,
    // lib/electronA11y.nix's --open-host, opens it itself, in the running
    // copy or once loaded). False when it isn't installed.
    function openInApp(service, uri) {
        const entry = root.installed(service);
        if (!entry) return false;
        const argv = entry.command ?? [];
        if (uri === "" || argv.length === 0) AppLaunch.launchEntry(entry);
        else AppLaunch.spawn([...argv, uri]);
        return true;
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

    // Music (YouTube Music, Spotify: Listen together) or video (Jellyfin's
    // mpv: Watch together): two buttons, each sharing its own players only.
    function kindOf(service) {
        return service === "jellyfin" ? "video" : service === "" ? "" : "music";
    }
    // What can be shared now, of a kind: a player with something on
    // (playing first, the one in front first among equals), else an empty one.
    function shareablePlayer(kind) {
        kind = kind ?? "music";
        const active = MprisController.activePlayer;
        const players = root.players().filter(p => root.kindOf(root.serviceOf(p)) === kind);
        const has = p => root.trackOf(p) !== null;
        // Something on it first (playing, then paused), the one in front
        // first among equals; an empty one last.
        const order = [p => has(p) && p.isPlaying, p => has(p), p => true];
        for (const ok of order) {
            if (root.kindOf(root.serviceOf(active)) === kind && ok(active)) return active;
            const p = players.find(ok);
            if (p) return p;
        }
        return null;
    }
    readonly property bool canShareMusic: root.shareablePlayer("music") !== null
    readonly property bool canShareVideo: root.shareablePlayer("video") !== null
    // Watch together is offered where Jellyfin is installed.
    readonly property bool videoOffered: root.canShareVideo || (root.testJellyfin === null && Jellyfin.available)

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

    // Share in the conversation `conv` ("" = everyone) what plays: `kind`
    // "music" (YouTube Music, Spotify) or "video" (Jellyfin). Returns "" or
    // why not.
    function start(conv, kind) {
        kind = kind ?? "music";
        if (!Mesh.configured) return Translation.tr("The mesh isn't set up");
        const p = root.shareablePlayer(kind);
        if (!p) {
            if (kind === "video")
                return Translation.tr("Jellyfin's player isn't running: play something on this computer from Jellyfin first");
            // Music in a browser tab (YouTube Music's website): it tells no
            // song id over MPRIS, so it can't be shared.
            if (root.players().some(x => x.isPlaying && MprisController.playerSource(x) === "browser"))
                return Translation.tr("Music playing in the browser can't be shared: play it in the YouTube Music (or Spotify) app instead");
            return Translation.tr("Play something in YouTube Music or Spotify first");
        }
        if (root.following !== "") root.leave("");
        if (root.hosting) root.stop();
        root.hosting = { sid: root._sid(), to: conv ?? "", bus: p.dbusName, kind: kind, listeners: {} };
        root.hostService = root.serviceOf(p);
        root.hostTrack = null;
        root._last = null;
        root._lastState = null;
        root._idleSince = 0;
        root._hostTick(true);
        return "";
    }
    function stop() {
        if (!root.hosting) return;
        root._send({ to: root.hosting.to, op: "end", sid: root.hosting.sid });
        root.hosting = null;
        root.hostTrack = null;
    }
    // The song (or film) shared now, and its app (the Mesh tab shows it).
    property var hostTrack: null
    property string hostService: ""
    property var _jfAsking: ({})
    // The last state sent (a stop is told from it), and since when the shared
    // player has had nothing on it.
    property var _lastState: null
    property real _idleSince: 0
    // What goes to the mesh (tests catch it in testSend).
    property var testSend: null
    function _send(data) {
        if (root.testSend !== null) root.testSend(data);
        else Mesh._send("listen", data);
    }
    property var _last: null // what was sent last: { key, playing, position, at }
    property string _pendingKey: ""
    property real _goneSince: 0
    function _hostTick(force) {
        const h = root.hosting;
        if (!h) return;
        const now = Date.now();
        let p = root.players().find(x => x.dbusName === h.bus) ?? root.shareablePlayer(h.kind);
        // Nothing on the one shared, something on another of its kind: that one now.
        if (p && root.trackOf(p) === null) {
            const other = root.shareablePlayer(h.kind);
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
        if (!track) {
            // It ended (or was stopped): after 3 s, once, the listeners are
            // told it stopped there (they pause), and the bar says nothing
            // plays; the next one is shared as usual.
            if (root._idleSince === 0) root._idleSince = now;
            if (now - root._idleSince > 3000 && root._lastState && root._lastState.playing) {
                const st = root._lastState;
                const len = st.track.length > 0 ? st.track.length : Number.MAX_SAFE_INTEGER;
                const position = Math.min(len, st.position + (now - st.at) / 1000);
                root._lastState = Object.assign({}, st, { playing: false, position: position, at: now });
                root._last = { key: root._last?.key ?? "", playing: false, position: position, at: now };
                root._send(root._lastState);
            }
            if (now - root._idleSince > 3000) root.hostTrack = null;
            return;
        }
        root._idleSince = 0;
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
        root._lastState = state;
        root._send(state);
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
        root._f = Object.assign(TrackMatch.fresh(), { jfFor: "", jfLocal: "", jfBusy: false, jfError: "", stateRecv: 0, seekAt: 0,
            launchedAt: 0, searched: "" });
        root._send({ to: s.to === "" ? "" : s.host, op: "join", sid: sid });
        root._followTick();
    }
    function leave(reason) {
        const s = root.sessions[root.following];
        if (s) root._send({ to: s.to === "" ? "" : s.host, op: "leave", sid: s.sid });
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
        const target = root.positionOf(s, now);
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
                // YouTube Music starts on the song (the Electron bridge opens
                // it once the app has loaded); never its website.
                if (!root.openInApp(svc, svc === "youtube-music" ? root.uriFor(svc, wantId, target + 5) : "")) {
                    root.followStatus = "noapp";
                    return;
                }
                if (svc === "youtube-music") {
                    f.openedFor = wantId;
                    f.openedAt = now;
                    f.opens = 1;
                }
            }
            root.followStatus = "starting";
            return;
        }
        // On the host's song (the same id, or the same title and artist:
        // YouTube Music often plays a song under another id), or not: open
        // it (three times at most), wait (loading; the song ended here and
        // the host's next one is coming), or leave (something else played
        // here for 3 s). TrackMatch (track_match.js, tested under node).
        const step = TrackMatch.followStep(f, { now: now, wantId: wantId, want: s.track, cur: root.trackOf(p) });
        if (step.act === "leave") {
            root.leave(Translation.tr("You played something else, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host)));
            return;
        }
        if (step.act !== "sync") {
            if (step.act === "open") {
                const uri = root.uriFor(svc, wantId, target + 1);
                const scheme = uri.split(":")[0];
                if ((p.supportedUriSchemes ?? []).map(x => String(x).toLowerCase()).includes(scheme)) p.openUri(uri);
                // Its schemes not known yet (just started) or not https: the
                // app's own command, never xdg-open (a browser, where no link
                // routing sends music.youtube.com to the app).
                else if (svc === "youtube-music") root.openInApp(svc, uri);
                else AppLaunch.openUrl(uri);
            }
            root.followStatus = "opening";
            return;
        }
        root._keepInSync(p, s, f, now, target, wantId);
    }
    // The song (or film) is the host's: the same play/pause and position.
    // Where the host is now: its position, moved on by the time since its
    // state, by the host's clock (right when a state arrives late), or by
    // when it arrived here when the host's clock is ahead (a state from
    // the future: the two clocks disagree).
    function positionOf(s, now) {
        if (!s) return 0;
        const since = s.recv !== undefined && s.at > s.recv + 3000 ? s.recv : s.at;
        const at = s.position + (s.playing ? (now - since) / 1000 : 0);
        return Math.max(0, s.track?.length > 0 ? Math.min(s.track.length, at) : at);
    }
    function _keepInSync(p, s, f, now, target, wantId) {
        f.syncedTo = wantId;
        f.lastPos = p.position ?? 0;
        f.lastLen = p.length > 0 ? p.length : 0;
        // Play and pause as the host; a pause here that lasts 5 s (not at
        // the song's end, nor right after an open or the host's news) is
        // the listener's: they stop listening along.
        const act = TrackMatch.playStep(f, { now: now, hostPlaying: s.playing, localPlaying: p.isPlaying, hostRecv: s.recv });
        if (act === "leave") {
            root.leave(Translation.tr("You paused, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host)));
            return;
        }
        if (act === "play" && p.canPlay) p.play();
        if (act === "pause" && p.canPause) p.pause();
        // To the host's position: after the open, on the host's news, else
        // a drift at most every 30 s (each jump rebuffers: it looks like a
        // reload).
        const len = p.length > 0 ? p.length : s.track.length;
        const to = p.canSeek ? TrackMatch.seekStep(f, { now: now, pos: p.position ?? 0, target: target, len: len, hostRecv: s.recv,
            playing: p.isPlaying }) : -1;
        if (to >= 0) p.position = to;
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
                // A new open for the jumps (seekStep): mpv starts at the
                // host's position, so most often none is needed.
                f.openedFor = key;
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
