pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Saved window layouts (`nixbook-desktop-mcp layout`, scripts/desktop-mcp.py):
 * where every window is — monitor, workspace, column or floating position,
 * size — under a name; restoring one moves the windows back and starts the
 * apps that aren't open. The same layouts AI agents save and restore through
 * the desktop MCP tools. Here it is the user acting: the agents' pause
 * doesn't apply.
 *
 * Used by the desktop's right-click menu, Settings > Window layouts and the
 * `layouts` IPC target for key bindings (`cycle`, `restoreNumber N`,
 * `saveCurrent`, `restore NAME`, `save NAME`), which agents can't call.
 * The list is read again after every change and when a menu shows it.
 */
Singleton {
    id: root

    readonly property string command: "nixbook-desktop-mcp"
    // [{ name, saved, windows, apps }]
    property var layouts: []
    property string current: ""
    property bool busy: runner.running

    function load() {
        root.refresh();
    }

    function refresh() {
        if (!lister.running) lister.running = true;
    }

    function validName(name) {
        return /^[\w.\-]{1,64}$/.test(name ?? "");
    }

    // A free name for "save as new": layout-1, layout-2…
    function nextName() {
        const taken = root.layouts.map(l => l.name);
        let i = root.layouts.length + 1;
        while (taken.includes(`layout-${i}`)) i++;
        return `layout-${i}`;
    }

    function run(args) {
        if (runner.running) return false;
        runner.command = [root.command, "layout", ...args];
        runner.running = true;
        return true;
    }

    function save(name) {
        if (!root.validName(name)) return false;
        return root.run(["save", name]);
    }
    function restore(name) {
        if (!root.validName(name)) return false;
        return root.run(["restore", name]);
    }
    function remove(name) {
        if (!root.validName(name)) return false;
        return root.run(["delete", name]);
    }
    function rename(from, to) {
        if (!root.validName(from) || !root.validName(to)) return false;
        return root.run(["rename", from, to]);
    }
    function cycle() {
        return root.run(["cycle"]);
    }
    // Into the current layout (the last saved or restored), else a new one.
    function saveCurrent() {
        return root.save(root.current.length > 0 ? root.current : root.nextName());
    }
    // The n-th layout (1-based, in the listed order), for key bindings.
    function restoreNumber(n) {
        const layout = root.layouts[n - 1];
        if (!layout) {
            Quickshell.execDetached(["notify-send", "-a", "Window layouts", "-i", "view-grid",
                Translation.tr("Window layouts"), Translation.tr("No layout number %1").arg(n)]);
            return false;
        }
        return root.restore(layout.name);
    }

    Process {
        id: lister
        command: [root.command, "layout", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.layouts = data.layouts ?? [];
                    root.current = data.current ?? "";
                } catch (e) {
                    console.warn("[WindowLayouts] can't read the layouts:", e);
                }
            }
        }
    }

    Process {
        id: runner
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    Quickshell.execDetached(["notify-send", "-a", "Window layouts", "-i", "dialog-error",
                        Translation.tr("Window layouts"), text.trim()]);
                }
            }
        }
        onExited: root.refresh()
    }

    IpcHandler {
        target: "layouts"

        function save(name: string): void {
            root.save(name);
        }
        function restore(name: string): void {
            root.restore(name);
        }
        function cycle(): void {
            root.cycle();
        }
        function saveCurrent(): void {
            root.saveCurrent();
        }
        function restoreNumber(n: int): void {
            root.restoreNumber(n);
        }
        function list(): string {
            return JSON.stringify({ current: root.current, layouts: root.layouts.map(l => l.name) });
        }
    }
}
