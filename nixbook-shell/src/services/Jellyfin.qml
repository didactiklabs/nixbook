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
        check.running = false;
        check.command = [root.bin, "configured"];
        check.environment = root.env;
        check.running = true;
    }
    Process {
        id: check
        onExited: code => root.ready = code === 0
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
