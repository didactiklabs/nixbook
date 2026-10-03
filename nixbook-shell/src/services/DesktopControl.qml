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
 * Where agents work: on the user's desktop, or on a desktop of their own
 * (`nixbook-desktop-mcp desktop agent`: a nested niri shown as a window, a
 * view the user can't type into). It's never left open empty: it opens when
 * an agent starts an app and closes once its last app is gone; the user
 * closing it only closes it (the agent's next app opens it again). Switching
 * goes through the server's command too; this watches its flag
 * (~/.local/state/nixbook-shell/agent-desktop) and
 * whether the agent desktop is open (its env file in the runtime directory).
 *
 * The user can take the agent desktop over for a moment (`desktop interact`:
 * their clicks and keys reach it, the agent's input waits), shown by its flag
 * in the runtime directory.
 *
 * The "… is driving the desktop" notification can be turned off
 * (`nixbook-desktop-mcp notify off`): ~/.local/state/nixbook-shell/desktop-control-quiet.
 *
 * The `desktopControl` IPC target (pause, resume, toggle, toggleNotify, status, and
 * agentDesktop, userDesktop, toggleDesktop, closeAgentDesktop, toggleInteract)
 * is for the user's key bindings; the MCP server refuses it to agents.
 */
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-desktop-mcp`
    // The agent desktop's launcher (scripts/agent-desktop.sh) writes these.
    readonly property string agentDesktopDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-agent-desktop`
    readonly property string stateHome: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell`
    readonly property string allowedFlag: `${root.stateHome}/desktop-control-allowed`
    property bool paused: true
    // A notification when an agent starts driving the desktop.
    property bool notifyOnControl: true
    // Agents work on their own desktop (else on the user's).
    property bool onAgentDesktop: false
    // Their desktop is open (an app on it); closed in between.
    property bool agentDesktopOpen: false
    // The user has taken their desktop over (clicks and keys get through).
    property bool userHasControl: false
    readonly property bool canTakeOver: root.onAgentDesktop && root.agentDesktopOpen
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

    function toggleNotify() {
        Quickshell.execDetached(["nixbook-desktop-mcp", "notify", root.notifyOnControl ? "off" : "on"]);
        root.notifyOnControl = !root.notifyOnControl;
    }

    // Agents on their own desktop.
    function agentDesktop() {
        Quickshell.execDetached(["nixbook-desktop-mcp", "desktop", "agent"]);
        root.onAgentDesktop = true;
    }

    function userDesktop() {
        Quickshell.execDetached(["nixbook-desktop-mcp", "desktop", "user"]);
        root.onAgentDesktop = false;
    }

    // Like Mod+Shift+A: to theirs, or back to the user's.
    function toggleDesktop() {
        if (root.onAgentDesktop) root.userDesktop();
        else root.agentDesktop();
    }

    // Take the agent desktop over, or give it back.
    function toggleInteract() {
        if (!root.userHasControl && !root.canTakeOver) return;
        Quickshell.execDetached(["nixbook-desktop-mcp", "desktop", "interact", root.userHasControl ? "off" : "on"]);
        root.userHasControl = !root.userHasControl;
    }

    function closeAgentDesktop() {
        Quickshell.execDetached(["nixbook-desktop-mcp", "desktop", "stop"]);
        root.agentDesktopOpen = false;
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
        onLoaded: {
            root.now = Date.now();
            root.parse(text());
        }
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

    FileView {
        id: quietFlag
        path: `${root.stateHome}/desktop-control-quiet`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.notifyOnControl = false
        onLoadFailed: error => root.notifyOnControl = true
    }

    FileView {
        id: agentDesktopFlag
        path: `${root.stateHome}/agent-desktop`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.onAgentDesktop = true
        onLoadFailed: error => root.onAgentDesktop = false
    }

    // Written once the agent desktop is up, removed when it closes.
    FileView {
        id: agentDesktopEnv
        path: `${root.agentDesktopDir}/agent-desktop.env`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.agentDesktopOpen = true
        onLoadFailed: error => root.agentDesktopOpen = false
    }

    FileView {
        id: agentDesktopInput
        path: `${root.agentDesktopDir}/agent-desktop-input`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.userHasControl = true
        onLoadFailed: error => root.userHasControl = false
    }

    // Every second, only while something can change on its own: ages the
    // "active" state while an agent is active, and re-reads the agent desktop's
    // files while that desktop is in use (agent-desktop.sh deletes and
    // recreates their directory, which drops the file watch).
    Timer {
        interval: 1000
        running: root.active || root.onAgentDesktop || root.agentDesktopOpen
        repeat: true
        onTriggered: {
            root.now = Date.now();
            agentDesktopEnv.reload();
            agentDesktopInput.reload();
        }
    }

    // Safety net for a missed change (the watches above cover the rest: the
    // launcher creates their directories before the shell starts).
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            stateFile.reload();
            allowedFile.reload();
            quietFlag.reload();
            agentDesktopFlag.reload();
            agentDesktopEnv.reload();
            agentDesktopInput.reload();
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
        function toggleNotify(): void {
            root.toggleNotify();
        }
        function agentDesktop(): void {
            root.agentDesktop();
        }
        function userDesktop(): void {
            root.userDesktop();
        }
        function toggleDesktop(): void {
            root.toggleDesktop();
        }
        function closeAgentDesktop(): void {
            root.closeAgentDesktop();
        }
        function toggleInteract(): void {
            root.toggleInteract();
        }
        function status(): string {
            return JSON.stringify({ paused: root.paused, notify: root.notifyOnControl, active: root.active, last: root.last,
                desktop: root.onAgentDesktop ? "agent" : "user", agentDesktopOpen: root.agentDesktopOpen,
                userHasControl: root.userHasControl });
        }
    }
}
