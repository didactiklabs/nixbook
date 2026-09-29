pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Desktop control for AI agents (scripts/desktop-mcp.py, `nixbook-desktop-mcp`):
 * whether it is paused and what an agent did last, from the state file the
 * MCP server writes on every call. Pausing goes through the server's own
 * command, so every agent (Claude Code, opencode, the AI chat…) is stopped at
 * once, including a run_steps batch between two steps.
 *
 * The `desktopControl` IPC target (pause, resume, toggle, status) is for the
 * user's key bindings; the MCP server refuses it to agents.
 */
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-desktop-mcp`
    property bool paused: false
    // { time (ms since the epoch), client, tool, outcome: running|ok|error|paused }
    property var last: null
    property real now: Date.now()
    // An agent counts as active while its calls keep coming (an agent thinks
    // for a few seconds between two calls).
    readonly property int activeWindowMs: 20000
    readonly property bool active: !root.paused && root.last !== null
        && root.last.outcome !== "paused" && (root.now - root.last.time) < root.activeWindowMs
    readonly property bool busy: root.active && root.last?.outcome === "running"

    // Called from shell.qml so the IPC target exists without the bar widget.
    function load() {}

    function pause() {
        Quickshell.execDetached(["nixbook-desktop-mcp", "pause"]);
        root.paused = true;
    }

    function resume() {
        Quickshell.execDetached(["nixbook-desktop-mcp", "resume"]);
        root.paused = false;
    }

    function toggle() {
        if (root.paused) root.resume();
        else root.pause();
    }

    function parse(text) {
        try {
            const state = JSON.parse(text);
            root.paused = state.paused === true;
            root.last = state.last ?? null;
        } catch (e) {
            // Caught mid-write: the next change or tick reads it whole.
        }
    }

    FileView {
        id: stateFile
        path: `${root.stateDir}/state.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                root.paused = false;
                root.last = null;
            }
        }
    }

    // Ages the "active" state, and re-reads the file in case a change was
    // missed (the directory only appears with the first agent).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            stateFile.reload();
        }
    }

    IpcHandler {
        target: "desktopControl"

        function pause(): void {
            root.pause();
        }
        function resume(): void {
            root.resume();
        }
        function toggle(): void {
            root.toggle();
        }
        function status(): string {
            return JSON.stringify({ paused: root.paused, active: root.active, last: root.last });
        }
    }
}
