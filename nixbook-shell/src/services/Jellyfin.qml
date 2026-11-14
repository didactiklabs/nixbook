pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Jellyfin on this computer, as a plain service (no AI): the helper nixbook
 * installs (`jellyfin-mcp`, its CLI: sign-in, the player of this computer —
 * jellyfin-mpv-shim —, listen-info / listen-play for watching along in the
 * Mesh), the settings it runs with (ai.jellyfin: the server, the user, a
 * key file; their names are older than this service), and whether it is
 * set up (`jellyfin-mcp configured`). Watching along (MeshListen) works
 * whatever the AI switches say; DAI's own Jellyfin tool (the chat's MCP
 * server) and its instant "play …" (QuickIntent) also need the chat's
 * switch. Signed in from Settings > Apps & accounts > Jellyfin (also shown in
 * Settings > Apps & accounts and Settings > Assistant).
 */
Singleton {
    id: root

    // The helper's path, from the shell's MCP server list (nixbook installs
    // it there with nixbookShellConfig.jellyfinMcp.enable): "" = not here.
    readonly property string bin: Ai.assistantMcpServers.jellyfin?.command ?? ""
    readonly property bool available: root.bin !== ""
    readonly property var env: Ai.jellyfinEnv
    // A server and a login (or a key) are set.
    property bool ready: false

    readonly property string _signature: root.available ? `${root.bin} ${JSON.stringify(root.env)}` : ""
    on_SignatureChanged: root.refresh()
    Component.onCompleted: root.refresh()
    function refresh() {
        if (!root.available) {
            root.ready = false;
            return;
        }
        // One process per check: only the latest one's answer counts. A
        // single Process restarted delivered the killed check's exit late,
        // saying "not ready" for a moment (the Jellyfin tab came and went).
        const run = ++root._checkRun;
        checkComponent.createObject(root, { run: run, command: [root.bin, "configured"], environment: root.env });
    }
    property int _checkRun: 0
    Component {
        id: checkComponent
        Process {
            id: check
            property int run: 0
            running: true
            onExited: code => {
                if (check.run === root._checkRun) root.ready = code === 0;
                check.destroy();
            }
        }
    }
    // Created at startup (shell.qml), for the player's streaming limit below.
    function load() {}

    // The player's limit for a server it doesn't see on the local network
    // (ai.jellyfin.maxBitrateMbps, 0: none), written into its own settings
    // once the settings are read and when it changes (`shim-bitrate`: nothing
    // to do when it already is that or without a player; otherwise the player
    // restarts). Settled a moment first: the spin box writes every step.
    readonly property int maxBitrateMbps: Math.max(0, Config.options?.ai?.jellyfin?.maxBitrateMbps ?? 0)
    onMaxBitrateMbpsChanged: if (Config.ready) bitrateTimer.restart()
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) bitrateTimer.restart();
        }
    }
    Timer {
        id: bitrateTimer
        interval: 1500
        onTriggered: if (root.available) root.run(["shim-bitrate", String(root.maxBitrateMbps)], "", (ok, answer) => {
            if (!ok) console.warn(`[Jellyfin] the player's streaming limit wasn't set: ${answer?.error ?? ""}`);
        })
    }

    // The right sidebar's Jellyfin tab (sidebar.jellyfinTab): what to watch
    // next (in progress, then next episodes) and what's new, each {id,
    // title, subtitle, kind, progress, image (a cached file)}; kept here so
    // the tab shows the last one at once while it refreshes.
    property var shelf: null
    property real shelfAt: 0
    property bool shelfLoading: false
    property string shelfError: ""
    function refreshShelf(force) {
        if (root.shelfLoading || !root.ready) return;
        if (!force && root.shelf && Date.now() - root.shelfAt < 2 * 60 * 1000) return;
        root.shelfLoading = true;
        root.run(["shelf"], "", (ok, answer) => {
            root.shelfLoading = false;
            if (ok) {
                root.shelf = answer;
                root.shelfAt = Date.now();
                root.shelfError = "";
            } else root.shelfError = answer?.error ?? "";
        });
    }
    // Plays it in mpv on this computer, where you stopped; then(ok, error).
    function playItem(id, then) {
        root.run(["play-id", id], "", (ok, answer) => {
            if (then) then(ok, ok ? "" : (answer?.error || answer?.reason || ""));
            if (ok) Qt.callLater(() => root.refreshShelf(true));
        });
    }

    // A series' seasons and episodes (`jellyfin-mcp episodes ID`, a series
    // or one of its episodes); then(ok, answer).
    function episodes(id, then) {
        root.run(["episodes", id], "", then);
    }

    // Downloads (`jellyfin-mcp offline`): films and episodes kept on this
    // computer, their files as the server has them, downloaded in the
    // background by the helper's own unit (it outlives the shell) and played
    // from there in mpv, with or without the server. `offline`: the helper's
    // status {running, used, free, online?, items: [{id, title, subtitle,
    // kind, seriesId, state queued|downloading|done|error, error, size, done,
    // image, played, progress}]}. Read when Jellyfin is ready, when the tab
    // shows (with the progress synced with the server: what was watched here
    // goes up, the server's comes back), and while something downloads:
    // every 2 s with the tab in view, every 20 s otherwise.
    property var offline: null
    readonly property var offlineItems: root.offline?.items ?? []
    readonly property var offlineById: {
        const map = {};
        for (const it of root.offlineItems) map[it.id] = it;
        return map;
    }
    readonly property bool offlineActive: root.offlineItems.some(it => it.state === "queued" || it.state === "downloading")
    // Set by the tab while it is on screen.
    property bool offlineShown: false
    property bool _offlineAsking: false
    property real _offlineResumedAt: 0
    onReadyChanged: if (root.ready) root.refreshOffline(true)
    function _offlineAnswer(ok, answer) {
        if (!ok) return;
        root.offline = answer;
        // Downloads waiting with no downloader (a reboot, a failure of
        // its unit): started again, once a minute at most.
        const waiting = (answer.items ?? []).some(it => it.state === "queued" || it.state === "downloading");
        if (waiting && !answer.running && Date.now() - root._offlineResumedAt > 60 * 1000) {
            root._offlineResumedAt = Date.now();
            root.run(["offline", "resume"], "", root._offlineAnswer);
        }
    }
    function refreshOffline(sync) {
        if (!root.available || root._offlineAsking) return;
        root._offlineAsking = true;
        root.run(["offline", "status", ...(sync ? ["--sync"] : [])], "", (ok, answer) => {
            root._offlineAsking = false;
            root._offlineAnswer(ok, answer);
        });
    }
    Timer {
        interval: root.offlineShown ? 2000 : 20000
        repeat: true
        running: root.offlineActive && !Idle.screensOff
        onTriggered: root.refreshOffline(false)
    }
    // ids: films, episodes, or a season or series (its episodes); then(ok, error).
    function keepOffline(ids, then) {
        root._offlineResumedAt = Date.now();
        root.run(["offline", "keep", ...ids], "", (ok, answer) => {
            root._offlineAnswer(ok, answer);
            if (then) then(ok, ok ? "" : (answer?.error ?? ""));
        });
    }
    function removeOffline(ids, then) {
        root.run(["offline", "remove", ...ids], "", (ok, answer) => {
            root._offlineAnswer(ok, answer);
            if (then) then(ok, ok ? "" : (answer?.error ?? ""));
        });
    }
    // The downloaded file in mpv, from where you stopped. Started through
    // niri, so it outlives the shell; the helper stays with mpv, notes how
    // far you got and tells the server when it can.
    function playOffline(id) {
        const env = Object.keys(root.env).map(k => `${k}=${root.env[k]}`);
        AppLaunch.spawn(["env", ...env, root.bin, "offline", "play", id]);
    }

    // `jellyfin-mcp ARGS`, `input` on stdin; then(ok, answer).
    function run(args, input, then) {
        if (!root.available) {
            if (then) then(false, { error: Translation.tr("Jellyfin isn't installed on this computer") });
            return;
        }
        runner.createObject(root, { input: input ?? "", then: then ?? null, command: [root.bin, ...args],
            environment: root.env });
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
                const done = proc.then;
                proc.destroy();
                if (done) done(code === 0 && !!answer?.ok, answer ?? { error: Translation.tr("Couldn't run the Jellyfin helper") });
            }
        }
    }
}
