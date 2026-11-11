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
 * stops following; one who pauses is held (paused, caught up when they play
 * again). What is shared or followed outlives a shell restart (a deploy, a
 * crash): kept in the runtime dir, gone at logout. Nothing else is kept.
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
    // The player of `service` that plays, else one on a song, else any: the
    // YouTube Music app and the background player (nixbook-ytmusic) can
    // both be there.
    function playerFor(service) {
        const all = root.players().filter(p => root.serviceOf(p) === service);
        return all.find(p => p.isPlaying) ?? all.find(p => root.trackOf(p) !== null) ?? all[0] ?? null;
    }
    // YouTube Music in the background (services/YouTubeMusic.qml): signed
    // in, listening along plays there, without a window (tests set
    // testBackground).
    property var testBackground: null
    function backgroundYt() {
        return root.testBackground !== null ? !!root.testBackground : YouTubeMusic.signedIn;
    }
    function isBackground(p) {
        return /nixbook_ytmusic/.test(`${p?.dbusName ?? ""}`);
    }
    // The player that follows the host: the background one for YouTube
    // Music when it is signed in (there or not yet), else playerFor.
    function followerFor(service) {
        if (service === "youtube-music" && root.backgroundYt())
            return root.players().find(p => root.isBackground(p)) ?? null;
        return root.playerFor(service);
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
        if (service === "youtube-music" && root.backgroundYt()) return service;
        const other = service === "spotify" ? "youtube-music" : "spotify";
        if (root.playerFor(service)) return service;
        if (root.playerFor(other)) return other;
        if (root.installed(service)) return service;
        if (root.installed(other)) return other;
        return "";
    }
    // Jellyfin set up here (services/Jellyfin.qml, Settings > Apps & accounts >
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
    // "opening", "starting", "matching", "search", "nomatch", "unavailable",
    // "noapp".
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
        // Already shared there: nothing to do (a second click used to end
        // the session for everyone listening and start a new one).
        if (root.hosting && root.hosting.to === (conv ?? "") && (root.hosting.kind ?? "music") === kind) return "";
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
        let moved = "";
        if (root.following !== "") {
            const host = root.sessions[root.following];
            root.leave("");
            if (host) moved = Translation.tr("You stopped listening along with %1 to share yours").arg(host.hostName || Mesh.nameOf(host.host));
        }
        if (root.hosting) {
            moved = Translation.tr("Your music was shared with %1: it is now shared here instead").arg(root.hosting.to === "" ? Translation.tr("everyone") : Mesh.nameOf(root.hosting.to));
            root.stop();
        }
        root.hosting = { sid: root._sid(), to: conv ?? "", bus: p.dbusName, kind: kind, listeners: {} };
        root.hostService = root.serviceOf(p);
        root.hostTrack = null;
        root._last = null;
        root._lastState = null;
        root._idleSince = 0;
        root._hostTick(true);
        return moved;
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
            // Still sharing, nothing playing: said every 20 s all the same,
            // so the listeners keep the session (they forget a host silent
            // for long: 75 s), as they do while a song is paused.
            if (root._lastState && !root._lastState.playing && now - root._lastState.at > 20000) {
                root._lastState = Object.assign({}, root._lastState, { at: now });
                root._send(root._lastState);
            }
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
        // Already listening along: nothing restarts (the notification's
        // Listen along clicked after joining, a double click).
        if (root.following === sid) return;
        let note = "";
        if (root.hosting) {
            note = Translation.tr("You stopped sharing your music to listen along with %1").arg(s.hostName || Mesh.nameOf(s.host));
            root.stop();
        }
        if (root.following !== "") root.leave("");
        root._rejoin = null;
        root.following = sid;
        root.notice = note;
        root.followStatus = "";
        root._f = Object.assign(TrackMatch.fresh(), { jfFor: "", jfLocal: "", jfBusy: false, jfError: "", stateRecv: 0, seekAt: 0,
            launchedAt: 0, searched: "" });
        root._send({ to: s.to === "" ? "" : s.host, op: "join", sid: sid });
        root._followTick();
    }
    function leave(reason, rejoin) {
        const s = root.sessions[root.following];
        if (s) root._send({ to: s.to === "" ? "" : s.host, op: "leave", sid: s.sid });
        // A session lost (its host silent): joined again by itself when it
        // comes back within 10 minutes (`rejoin`); any other leave is the
        // listener's, or the host's end.
        root._rejoin = rejoin && s ? { sid: s.sid, host: s.host, to: s.to, until: Date.now() + 10 * 60 * 1000 } : null;
        root.following = "";
        root.followStatus = "";
        root.notice = reason ?? "";
    }
    // { sid, until }: a session to join again by itself when its host's next
    // state comes (lost to a network drop, or followed before a restart).
    property var _rejoin: null
    property var _f: ({})
    // Held (paused here): back with the host now, where they are (the
    // card's Catch up), as pressing play does.
    function catchUp() {
        const f = root._f;
        if (!f.held) return;
        f.held = false;
        f.heldSince = 0;
        f.pausedSince = 0;
        f.sawPlaying = false;
        f.cmdAt = 0;
        f.seekRecv = -1;
        root.followStatus = "";
        root._followTick();
    }
    // The host listened along to has said nothing for a minute.
    property bool quiet: false
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
        // The host's states come every 20 s: none for a minute is a host gone
        // quiet (their shell restarting, a network drop), not a next song.
        root.quiet = now - s.recv > 60000;
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
        const p = root.followerFor(svc);
        // The app closed while listening along (it was there): the listener
        // closed it, so they stop (5 s: an app restarting itself comes back);
        // only an app not started yet is started.
        if (p) {
            if (!f.hadPlayer) f.playerSince = now;
            f.hadPlayer = true;
            f.goneSince = 0;
        } else if (f.hadPlayer) {
            // TrackMatch.goneStep: the background player leaves the bus at
            // its song's end, which isn't closing it.
            const background = svc === "youtube-music" && root.backgroundYt();
            const gone = TrackMatch.goneStep(f, { now: now, wantId: wantId, background: background, target: target });
            if (gone === "leave") {
                root.leave(background
                    ? Translation.tr("YouTube Music stopped, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host))
                    : Translation.tr("You closed %1, so you stopped listening along with %2").arg(root.serviceName(svc)).arg(s.hostName || Mesh.nameOf(s.host)));
                return;
            }
            if (gone === "wait" || gone === "next") {
                root.followStatus = gone === "next" ? "next" : "starting";
                return;
            }
            // "reopen": the host's next song, started as at the beginning.
            f.hadPlayer = false;
            f.launchedAt = 0;
        }
        if (!p) {
            if (now - f.launchedAt > 20000) {
                f.launchedAt = now;
                // YouTube Music starts on the song: in the background player
                // (its yt-dlp takes a few seconds: a little ahead), else the
                // app (the Electron bridge opens it once the app has
                // loaded); never its website.
                if (svc === "youtube-music" && root.backgroundYt()) {
                    root._openSong(svc, wantId, target + 6, f);
                } else if (!root.openInApp(svc, svc === "youtube-music" ? root.uriFor(svc, wantId, target + 5) : "")) {
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
        // A player that just appeared (the app starting): a moment to settle,
        // so the one open takes (Spotify's first, right after it starts,
        // didn't).
        if (f.opens === 0 && f.playerSince && now - f.playerSince < 2500 && root.trackOf(p)?.id !== wantId) {
            root.followStatus = "starting";
            return;
        }
        // Held (paused here): nothing is opened or played for them until
        // they press play again (TrackMatch.playStep: "resume"), then the
        // host's song, where the host is.
        if (f.held) {
            const act = TrackMatch.playStep(f, { now: now, hostPlaying: s.playing, localPlaying: p.isPlaying, hostRecv: s.recv });
            if (act === "leave") {
                root.leave(Translation.tr("You paused, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host)));
                return;
            }
            if (act === "hold") {
                root.followStatus = "held";
                return;
            }
            f.seekRecv = -1; // "resume": caught up at once (seekStep sees news)
        }
        const step = TrackMatch.followStep(f, { now: now, wantId: wantId, want: s.track, cur: root.trackOf(p) });
        if (step.act === "leave") {
            root.leave(Translation.tr("You played something else, so you stopped listening along with %1").arg(s.hostName || Mesh.nameOf(s.host)));
            return;
        }
        if (step.act !== "sync") {
            if (step.act === "open") {
                // The second try on YouTube Music (the link landed on another
                // song: that version doesn't play there): another version of
                // the song.
                if (svc === "youtube-music" && f.opens >= 2) root._openAlternative(s, f, svc, wantId);
                else root._openSong(svc, wantId, target + 1, f);
            }
            // Tried twice: not playable here; waits for the next song.
            root.followStatus = f.opens >= 2 && now - f.openedAt > 12000 ? "unavailable" : "opening";
            return;
        }
        root._keepInSync(p, s, f, now, target, wantId);
    }
    // Opens `id` in the listener's app, at `at` (seconds). YouTube Music:
    // through its Electron bridge first (its socket's `go` `open`: the app's
    // page navigated to the link, as a click on it does; it plays songs
    // MPRIS's OpenUri didn't, never passes by the browser, and doesn't raise
    // the app's window), else MPRIS.
    function _openSong(svc, id, at, f, noBridge) {
        // The background player: `nixbook-ytmusic play-id`, which also
        // starts it.
        if (svc === "youtube-music" && root.backgroundYt()) {
            f.tried = [...(f.tried ?? []).filter(x => x !== id), id];
            if (root.testBackground !== null) root.testBackground(id, at);
            else YouTubeMusic.playId(id, at);
            return;
        }
        const p = root.playerFor(svc);
        if (!p) return;
        const uri = root.uriFor(svc, id, at);
        const scheme = uri.split(":")[0];
        f.tried = [...(f.tried ?? []).filter(x => x !== id), id];
        if (svc === "youtube-music" && !noBridge) {
            const sock = `${Quickshell.env("XDG_RUNTIME_DIR") ?? ""}/nixbook-electron/youtube-music.sock`;
            bridgeOpener.createObject(root, {
                f: f, svc: svc, wantId: id, at: at,
                command: ["sh", "-c", 'test -S "$2" || exit 3; printf "%s\\n" "$1" | socat -t 20 - "UNIX-CONNECT:$2"', "sh",
                    JSON.stringify({ cmd: "go", action: "open", url: uri }), sock]
            });
            return;
        }
        if ((p.supportedUriSchemes ?? []).map(x => String(x).toLowerCase()).includes(scheme)) p.openUri(uri);
        // Its schemes not known yet (just started) or not https: the app's
        // own command, never xdg-open (a browser, where no link routing sends
        // music.youtube.com to the app).
        else if (svc === "youtube-music") root.openInApp(svc, uri);
        else AppLaunch.openUrl(uri);
    }
    // The bridge's answer: not there or refused, MPRIS then.
    Component {
        id: bridgeOpener
        Process {
            id: proc
            property var f
            property string svc
            property string wantId
            property real at
            stdout: StdioCollector { id: bridgeOut }
            Component.onCompleted: proc.running = true
            onExited: code => {
                let ok = false;
                try {
                    ok = code === 0 && JSON.parse(bridgeOut.text.trim().split("\n").pop() || "{}").ok === true;
                } catch (e) {}
                if (!ok && root._f === proc.f) root._openSong(proc.svc, proc.wantId, proc.at, proc.f, true);
                proc.destroy();
            }
        }
    }
    // Another version of the host's song on YouTube Music (`nixbook-mesh
    // match`, the versions tried left out), opened in place of the one that
    // didn't play here.
    function _openAlternative(s, f, svc, wantId) {
        if (f.altAsking) return;
        f.altAsking = true;
        const t = s.track ?? {};
        Mesh.run(["match"], JSON.stringify({ title: t.title, artist: t.artist, album: t.album, length: t.length,
            exclude: [...(f.tried ?? []), wantId] }), (ok, answer) => {
            if (root._f !== f) return;
            f.altAsking = false;
            if (f.openedFor !== wantId) return;
            const id = ok ? `${answer.videoId ?? ""}` : "";
            if (id === "") return;
            f.alt = id;
            f.altFor = wantId;
            f.openedAt = Date.now();
            root._openSong(svc, id, root.positionOf(root.sessions[root.following], Date.now()) + 1, f);
        });
    }
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
    // The song (or film) is the host's: the same play/pause and position.
    function _keepInSync(p, s, f, now, target, wantId) {
        f.syncedTo = wantId;
        f.lastPos = p.position ?? 0;
        f.lastLen = p.length > 0 ? p.length : 0;
        // Play and pause as the host; a pause here that lasts 8 s (not at
        // the song's end, nor right after an open or the host's news) is
        // the listener's: held (TrackMatch.playStep), not left.
        const act = TrackMatch.playStep(f, { now: now, hostPlaying: s.playing, localPlaying: p.isPlaying, hostRecv: s.recv });
        if (act === "hold") {
            root.followStatus = "held";
            return;
        }
        if (act === "resume") f.seekRecv = -1;
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
    // The YouTube Music id of a session's song (to add it to a playlist of
    // yours): its own on YouTube Music, else the match listening along
    // found, else looked for now; then(videoId) ("" when none).
    function youtubeIdOf(s, then) {
        const t = s?.track;
        if (!t || s.service === "jellyfin") { then(""); return; }
        if (s.service === "youtube-music") { then(`${t.id ?? ""}`); return; }
        const key = `${s.service}:${t.id}`;
        if (key in root._matches) { then(root._matches[key] ?? ""); return; }
        Mesh.run(["match"], JSON.stringify({ title: t.title, artist: t.artist, album: t.album, length: t.length }),
            (ok, answer) => {
                const id = ok ? `${answer.videoId ?? ""}` : "";
                root._matches = Object.assign({}, root._matches, { [key]: id || null });
                then(id);
            });
    }

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
        // The host shared again in the same conversation (a new session:
        // their shell restarted, or they clicked share again): the listener
        // goes on with it, without a sound (it used to end with "The
        // session ended", listening along to be joined again by hand).
        const replaced = root.following !== "" && root.following !== sid && root.sessions[root.following]?.host === from
            && root.sessions[root.following]?.to === s.to;
        const next = {};
        for (const [id, x] of Object.entries(root.sessions))
            if (x.host !== from || id === sid) next[id] = x;
        next[sid] = s;
        root.sessions = next;
        if (replaced) {
            root.following = sid;
            root._send({ to: s.to === "" ? "" : s.host, op: "join", sid: sid });
            root.notice = "";
        } else if (root._rejoin && root.following === "" && Date.now() < root._rejoin.until
                && (root._rejoin.sid === sid || (root._rejoin.host === from && root._rejoin.to === s.to))) {
            // Lost (a drop, a restart of either side) and back: joined again.
            root.join(sid);
            return;
        }
        if (!prev && !root._announced[sid] && Date.now() - s.at < 60000) root._announce(s);
        root._announced[sid] = Date.now();
    }
    // The sessions already announced (their notification): not again after
    // the shell restarts (kept in the runtime file with the rest).
    property var _announced: ({})
    function _put(s) {
        root.sessions = Object.assign({}, root.sessions, { [s.sid]: s });
    }
    // A host silent for long has gone (no `end`: a shut computer). The one
    // listened along to is kept 3 minutes: this side's connection to the
    // server may be what was down (a Wi-Fi drop, a suspend), and its
    // states come back with it; a host stopping says `end`.
    Timer {
        interval: 15000
        repeat: true
        running: Object.keys(root.sessions).length > 0
        onTriggered: {
            const now = Date.now();
            const next = {};
            for (const [id, s] of Object.entries(root.sessions))
                if (now - s.recv < (id === root.following ? 180000 : 75000)) next[id] = s;
            // The one listened along to gone quiet: left, joined again by
            // itself when its host is back (within 10 minutes).
            if (root.following !== "" && !next[root.following]) {
                const lost = root.sessions[root.following];
                root.leave(Translation.tr("No news from %1 for 3 minutes: back to listening along as soon as they are").arg(lost.hostName || Mesh.nameOf(lost.host)), true);
            }
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
    // A shell restart (a deploy, a crash) doesn't end listening together:
    // nothing is sent when the shell goes (it used to `end` the session, or
    // didn't manage to before it quit, and the listeners waited on a silent
    // host); what is shared or followed is kept in the runtime dir (gone at
    // logout or a reboot) and taken up again when the shell starts within
    // 5 minutes: the same session, its listeners, the session followed
    // (joined again at its host's next state).
    FileView {
        id: keepFile
        path: `${Directories.runtimeTemp}/listen-along.json`
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }
    property bool _restored: false
    function _keep() {
        if (!root._restored || root.testSend !== null) return;
        const now = Date.now();
        const announced = {};
        for (const [sid, at] of Object.entries(root._announced)) if (now - at < 30 * 60 * 1000) announced[sid] = at;
        root._announced = announced;
        const f = root.sessions[root.following];
        keepFile.setText(JSON.stringify({ at: now,
            hosting: root.hosting ? { sid: root.hosting.sid, to: root.hosting.to, kind: root.hosting.kind ?? "music", listeners: root.hosting.listeners ?? {} } : null,
            following: f ? { sid: f.sid, host: f.host, to: f.to } : (root._rejoin ?? null), announced: announced }));
    }
    onHostingChanged: root._keep()
    onFollowingChanged: root._keep()
    Timer {
        // Kept fresh (`at`) while there is something to take up again.
        interval: 60000
        repeat: true
        running: root.hosting !== null || root.following !== "" || root._rejoin !== null
        onTriggered: root._keep()
    }
    // What the runtime file held when the shell started; applied once the
    // mesh is configured (Mesh.onConfiguredChanged calls restore()).
    property var _atStart: null
    Component.onCompleted: {
        try {
            root._atStart = JSON.parse(keepFile.text() || "null");
        } catch (e) {}
        if (!root._atStart) root._restored = true;
        if (Mesh.configured) root.restore();
    }
    function restore() {
        if (root._restored) return;
        const k = root._atStart;
        root._atStart = null;
        const now = Date.now();
        if (k && now - Number(k.at ?? 0) < 5 * 60 * 1000 && root.testSend === null) {
            root._announced = k.announced ?? {};
            if (k.hosting?.sid && !root.hosting)
                root.hosting = { sid: k.hosting.sid, to: k.hosting.to ?? "", bus: "", kind: k.hosting.kind ?? "music", listeners: k.hosting.listeners ?? {} };
            else if (k.following?.sid && root.following === "")
                root._rejoin = { sid: k.following.sid, host: k.following.host ?? "", to: k.following.to ?? "", until: now + 5 * 60 * 1000 };
        }
        root._restored = true;
        root._keep();
    }
}
