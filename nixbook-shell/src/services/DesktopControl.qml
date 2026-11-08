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
 * The "… is driving the desktop" notification can be turned off
 * (`nixbook-desktop-mcp notify off`): ~/.local/state/nixbook-shell/desktop-control-quiet.
 *
 * The `desktopControl` IPC target (pause, resume, toggle, toggleNotify, status)
 * is for the user's key bindings; the MCP server refuses it to agents.
 */
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-desktop-mcp`
    readonly property string stateHome: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell`
    readonly property string allowedFlag: `${root.stateHome}/desktop-control-allowed`
    property bool paused: true
    // A notification when an agent starts driving the desktop.
    property bool notifyOnControl: true
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
        DesktopHelper.run(["pause"]);
        root.paused = true;
    }

    function resume() {
        DesktopHelper.run(["resume"]);
        root.paused = false;
    }

    function toggle() {
        if (root.paused) root.resume();
        else root.pause();
    }

    function toggleNotify() {
        DesktopHelper.run(["notify", root.notifyOnControl ? "off" : "on"]);
        root.notifyOnControl = !root.notifyOnControl;
    }

    // The desktop memory (Settings > Desktop agents): notes agents wrote,
    // aliases and usage learned, as `nixbook-desktop-mcp memory show` prints.
    property var memory: ({ notes: [], aliases: {}, usage: { apps: {}, layouts: {}, tools: {} }, targets: {}, triggers: [], archive: [], routines: [] })
    function refreshMemory() {
        if (!memoryReader.running) memoryReader.running = true;
    }
    // A routine on, off or removed (`nixbook-desktop-mcp routine`).
    function routineCommand(action, id) {
        if (!["on", "off", "remove"].includes(action) || !/^[0-9a-f]{1,16}$/.test(id ?? "")) return;
        root.memoryQueue = [...root.memoryQueue, ["nixbook-desktop-mcp", "routine", action, id]];
        if (!memoryWriter.running) root.nextMemoryCommand();
    }
    function forgetNote(id) {
        if (!/^[0-9a-f]{1,16}$/.test(id ?? "")) return;
        root.memoryCommand(["forget", id]);
    }
    // parts: any of "notes", "usage", "aliases", "targets", "triggers", "routines", "all"
    function clearMemory(parts) {
        if (!parts.every(p => ["notes", "usage", "aliases", "targets", "triggers", "routines", "all"].includes(p))) return;
        root.memoryCommand(["clear", ...parts]);
    }
    // What agents remember about the user's life (Settings > Desktop agents >
    // About you), as `nixbook-desktop-mcp personal show` prints.
    property var personal: []
    function refreshPersonal() {
        if (!personalReader.running) personalReader.running = true;
    }
    function forgetPersonal(id) {
        if (!/^[0-9a-f]{1,16}$/.test(id ?? "")) return;
        root.memoryCommand(["forget", id], "personal");
    }
    function clearPersonal() {
        root.memoryCommand(["clear"], "personal");
    }
    // Usage habits (Settings > Desktop agents > Usage habits), as
    // `nixbook-desktop-mcp habits status` prints: on or not (and whether Nix
    // turned them on, then the switch is locked), paused, what they say now
    // and the week's report.
    property var habits: ({ enabled: false })
    function refreshHabits() {
        if (!habitsReader.running) habitsReader.running = true;
    }
    // On: the nixbook-habits service starts now and with each session; off:
    // it stops, and with `forget` what it recorded is deleted.
    function setHabitsEnabled(on, forget) {
        root.memoryCommand(on ? ["on"] : (forget ? ["off", "--forget"] : ["off"]), "habits");
    }
    function setHabitsPaused(paused) {
        root.memoryCommand([paused ? "pause" : "resume"], "habits");
    }
    function clearHabits() {
        root.memoryCommand(["clear"], "habits");
    }
    // The music listened to only (the music taste), the rest kept.
    function clearMusic() {
        root.memoryCommand(["music-clear"], "habits");
    }
    // One command at a time, in order (quick clicks queue up).
    property var memoryQueue: []
    function memoryCommand(args, part) {
        root.memoryQueue = [...root.memoryQueue, ["nixbook-desktop-mcp", part ?? "memory", ...args]];
        if (!memoryWriter.running) root.nextMemoryCommand();
    }
    function nextMemoryCommand() {
        if (root.memoryQueue.length === 0) {
            root.refreshMemory();
            root.refreshPersonal();
            root.refreshHabits();
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
        id: habitsReader
        command: ["nixbook-desktop-mcp", "habits", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.habits = JSON.parse(text);
                } catch (e) {
                    console.warn("[DesktopControl] can't read the usage habits:", e);
                }
            }
        }
    }
    Process {
        id: personalReader
        command: ["nixbook-desktop-mcp", "personal", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const entries = JSON.parse(text);
                    if (Array.isArray(entries)) root.personal = entries;
                } catch (e) {
                    console.warn("[DesktopControl] can't read the personal memory:", e);
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

    // Agents' keys and clicks look like the user's: nixbook-desktop-mcp
    // stamps the time before each input (mark_agent_input), and what would
    // run something with the user's full rights from typed text (a launcher
    // `$` command, a side-panel chat message) waits until AGENT_INPUT_MS
    // after the last one. Read synchronously, at the moment it would run.
    readonly property int agentInputMs: 3000
    function agentInputRecent(): bool {
        agentInputFile.reload()
        const t = parseInt(agentInputFile.text())
        return !isNaN(t) && Date.now() - t < root.agentInputMs && Date.now() >= t - 1000
    }
    // Refuses with a word to the user; true when refused.
    function refuseIfAgentInput(what: string): bool {
        if (!root.agentInputRecent()) return false
        Quickshell.execDetached(["notify-send", "--app-name=Desktop agent", "--icon=smart_toy",
            Translation.tr("Blocked: %1").arg(what),
            Translation.tr("An agent was typing or clicking just now, so this didn't run (agents can't run commands this way). Do it again in a few seconds if it was you.")])
        return true
    }
    FileView {
        id: agentInputFile
        path: `${Directories.runtimeTemp}/agent-input`
        blockLoading: true
        printErrors: false
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

    // Every second while an agent is active: ages the "active" state.
    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // Safety net for a missed change (the watches above cover the rest). Not while
    // the screens are off (Idle): nothing shows it; caught up on wake. The
    // MCP server checks the files itself.
    Timer {
        interval: 10000
        running: !Idle.screensOff
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            stateFile.reload();
            allowedFile.reload();
            quietFlag.reload();
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
        function status(): string {
            return JSON.stringify({ paused: root.paused, notify: root.notifyOnControl, active: root.active, last: root.last });
        }
    }
}
