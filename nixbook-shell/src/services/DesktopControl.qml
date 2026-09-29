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
 * Paused until the user first allows it, and the choice survives a reboot:
 * agents may act only while ~/.local/state/nixbook-shell/desktop-control-allowed
 * exists (the server's kill switch), which this watches.
 *
 * The `desktopControl` IPC target (pause, resume, toggle, status) is for the
 * user's key bindings; the MCP server refuses it to agents.
 */
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-desktop-mcp`
    readonly property string allowedFlag: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/desktop-control-allowed`
    property bool paused: true
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

    // The desktop memory (Settings > Desktop agents): notes agents wrote,
    // aliases and usage learned, as `nixbook-desktop-mcp memory show` prints.
    property var memory: ({ notes: [], aliases: {}, usage: { apps: {}, layouts: {}, tools: {} } })
    function refreshMemory() {
        if (!memoryReader.running) memoryReader.running = true;
    }
    function forgetNote(id) {
        if (!/^[0-9a-f]{1,16}$/.test(id ?? "")) return;
        root.memoryCommand(["forget", id]);
    }
    // parts: any of "notes", "usage", "aliases", "all"
    function clearMemory(parts) {
        if (!parts.every(p => ["notes", "usage", "aliases", "all"].includes(p))) return;
        root.memoryCommand(["clear", ...parts]);
    }
    // One command at a time, in order (quick clicks queue up).
    property var memoryQueue: []
    function memoryCommand(args) {
        root.memoryQueue = [...root.memoryQueue, ["nixbook-desktop-mcp", "memory", ...args]];
        if (!memoryWriter.running) root.nextMemoryCommand();
    }
    function nextMemoryCommand() {
        if (root.memoryQueue.length === 0) {
            root.refreshMemory();
            return;
        }
        memoryWriter.command = root.memoryQueue[0];
        root.memoryQueue = root.memoryQueue.slice(1);
        memoryWriter.running = true;
    }

    Process {
        id: memoryReader
        command: ["nixbook-desktop-mcp", "memory", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.memory = JSON.parse(text);
                } catch (e) {
                    console.warn("[DesktopControl] can't read the desktop memory:", e);
                }
            }
        }
    }
    Process {
        id: memoryWriter
        onExited: root.nextMemoryCommand()
    }

    function parse(text) {
        try {
            const state = JSON.parse(text);
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
            if (error == FileViewError.FileNotFound)
                root.last = null;
        }
    }

    // The kill switch itself: present = allowed, anything else = paused.
    FileView {
        id: allowedFile
        path: root.allowedFlag
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.paused = false
        onLoadFailed: error => root.paused = true
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
            allowedFile.reload();
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
