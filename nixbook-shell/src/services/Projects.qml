pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Projects (`nixbook-desktop-mcp project`, scripts/desktop-mcp.py): whole
 * contexts to come back to — a window layout,
 * the Zen tabs of the project's window, Do Not Disturb on or off and a focus
 * timer. "Work on the hackathon" opens it as it was left; "pause the
 * hackathon" saves it as it is now, then does what its rule says (keep it
 * all, or close its tabs) and puts
 * DND and the timer back. Saved in $XDG_STATE_HOME/nixbook-shell/contexts.
 *
 * Here it is the user acting (the bubble's "work on X", the launcher's `#`,
 * Settings > Window layouts > Projects, the `projects` IPC target, which
 * agents can't call: they have the `project` tool). Opening one keeps the
 * windows as they were (the hidden layout _before-undo): `undoOpen()`.
 */
Singleton {
    id: root

    readonly property string command: "nixbook-desktop-mcp"
    // [{ name, state: "open"|"paused", saved, opened, paused, layout, apps,
    //    tabs: [titles], dnd, focus, onPause }]
    property var projects: []
    property string current: ""
    property bool busy: runner.running
    property string busyName: ""

    function load() {
        root.refresh();
    }
    function refresh() {
        if (!lister.running) lister.running = true;
    }
    function names() {
        return root.projects.map(p => p.name);
    }
    function byName(name) {
        const want = String(name ?? "").toLowerCase();
        return root.projects.find(p => p.name.toLowerCase() === want) ?? null;
    }
    function validName(name) {
        return /^[A-Za-z0-9][\w.\-]{0,47}$/.test(String(name ?? "").trim().replace(/\s+/g, "-"));
    }

    function run(args, name = "") {
        if (runner.running) {
            Quickshell.execDetached(["notify-send", "-a", "Projects", "-i", "folder-open",
                Translation.tr("Projects"), Translation.tr("Still busy with the last one: try again in a moment")]);
            return false;
        }
        runner.command = [root.command, "project", ...args];
        root.busyName = name;
        runner.running = true;
        return true;
    }
    function open(name) {
        return root.run(["open", name], name);
    }
    function pause(name) {
        return root.run(["pause", name], name);
    }
    // The desktop as it is now, into it (a new one when the name is new).
    function save(name) {
        const n = String(name ?? "").trim().replace(/\s+/g, "-");
        if (!root.validName(n)) return false;
        return root.run(["save", n], n);
    }
    function remove(name) {
        return root.run(["delete", name], name);
    }
    function rename(from, to) {
        return root.run(["rename", from, to], from);
    }
    // key: dnd (on|off|none), focus (minutes|pomodoro|0), on-pause (keep|tabs)
    function set(name, key, value) {
        return root.run(["set", name, key, String(value)], name);
    }
    // The windows back as they were before the last project opened.
    function undoOpen() {
        return WindowLayouts.restore("_before-undo");
    }

    Process {
        id: lister
        command: [root.command, "project", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.projects = data.projects ?? [];
                    root.current = data.current ?? "";
                } catch (e) {
                    console.warn("[Projects] can't read the projects:", e);
                }
            }
        }
    }

    Process {
        id: runner
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    Quickshell.execDetached(["notify-send", "-a", "Projects", "-i", "dialog-error",
                        Translation.tr("Projects"), text.trim()]);
                }
            }
        }
        onExited: {
            root.busyName = "";
            root.refresh();
            WindowLayouts.refresh();
        }
    }

    IpcHandler {
        target: "projects"

        function open(name: string): void {
            root.open(name);
        }
        function pause(name: string): void {
            root.pause(name);
        }
        function save(name: string): void {
            root.save(name);
        }
        // The one open now paused, else nothing.
        function pauseCurrent(): void {
            if (root.current.length > 0) root.pause(root.current);
        }
        function list(): string {
            return JSON.stringify({ current: root.current, projects: root.names() });
        }
    }
}
