pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var windowList: []
    property var workspaces: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var focusedMonitor: null

    function switchWorkspaceRelative(direction) {
        Quickshell.execDetached(["niri", "msg", "action", direction === "next" ? "focus-workspace-down" : "focus-workspace-up"]);
    }

    function normalizeWindow(w) {
        return {
            id: String(w.id),
            address: String(w.id),
            title: w.title ?? "",
            appId: w.app_id ?? "",
            class: w.app_id ?? "",
            workspaceId: w.workspace_id,
            focused: w.is_focused ?? false,
            width: w.layout?.window_size?.[0] ?? 0,
            height: w.layout?.window_size?.[1] ?? 0,
            floating: w.is_floating ?? false,
            // Floating windows only: the tile's rect in output-logical
            // coordinates (niri gives no position for tiled windows).
            tileX: w.layout?.tile_pos_in_workspace_view?.[0] ?? null,
            tileY: w.layout?.tile_pos_in_workspace_view?.[1] ?? null,
            tileWidth: w.layout?.tile_size?.[0] ?? 0,
            tileHeight: w.layout?.tile_size?.[1] ?? 0,
            // Tiled windows only: 1-based column and tile index in the
            // scrolling layout.
            column: w.layout?.pos_in_scrolling_layout?.[0] ?? null,
            tileIndex: w.layout?.pos_in_scrolling_layout?.[1] ?? null,
            // The window's visual geometry within its tile (borders).
            windowOffsetX: w.layout?.window_offset_in_tile?.[0] ?? 0,
            windowOffsetY: w.layout?.window_offset_in_tile?.[1] ?? 0
        };
    }

    function focusWindow(id) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", id]);
    }
    function closeWindow(id) {
        Quickshell.execDetached(["niri", "msg", "action", "close-window", "--id", id]);
    }
    function switchWorkspace(id) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(id)]);
    }
    function moveWindowToWorkspace(id, wsId) {
        Quickshell.execDetached(["niri", "msg", "action", "move-window-to-workspace", "--window-id", id, String(wsId)]);
    }

    function monitorFor(screen) {
        if (!screen) return null;
        return root.monitors.find(m => m.name === screen.name) ?? null;
    }

    function activeWorkspaceForMonitor(monitorName) {
        if (!monitorName) return null;
        return root.workspaces.find(ws => ws.output === monitorName && ws.is_active) ?? null;
    }

    function biggestWindowForWorkspace(wsId) {
        const wins = root.windowList.filter(w => w.workspaceId === wsId);
        if (wins.length === 0) return null;
        return wins.reduce((a, b) => (a.width * a.height >= b.width * b.height ? a : b));
    }

    function fullscreenOnMonitor(monitorName) {
        const mon = root.monitors.find(m => m.name === monitorName);
        if (!mon || !mon.logical) return false;
        const ws = root.workspaces.find(w => w.output === monitorName && w.is_active);
        if (!ws) return false;
        return root.windowList.some(w => w.workspaceId === ws.id
            && w.width === mon.logical.width
            && w.height === mon.logical.height);
    }

    function monitorGeometry(screen) {
        const m = root.monitors.find(mm => mm.name === screen?.name);
        if (!m || !m.logical) return { x: 0, y: 0, scale: 1 };
        return { x: m.logical.x, y: m.logical.y, scale: m.logical.scale };
    }


    // State is driven by niri's event stream, which carries the full model
    // (initial WorkspacesChanged/WindowsChanged on connect, then deltas).
    // Upstream re-ran `niri msg windows/workspaces/outputs` (3 processes + 3
    // full JSON parses) on every event burst, and derived the focused output in
    // the outputs callback from whatever `workspaces` held at that moment -
    // both queries race, so the focused monitor was often stale (the session
    // menu kept opening on the built-in display). Outputs are not part of the
    // event stream, so they are fetched on start, on screen changes and when
    // niri reloads its config.
    property var _windows: ({})      // id -> raw niri window
    property var _workspaces: ({})   // id -> raw niri workspace
    property bool _dirty: false

    function updateAll() {
        getWindows.running = true;
        getWorkspaces.running = true;
        getOutputs.running = true;
    }

    function publish() {
        root._dirty = true;
        publishTimer.restart();
    }

    // Coalesce event bursts (layout changes during resizes/animations) into
    // one model update per ~frame.
    Timer {
        id: publishTimer
        interval: 16
        onTriggered: root.flush()
    }

    function flush() {
        if (!root._dirty) return;
        root._dirty = false;
        const wsList = Object.values(root._workspaces).sort((a, b) =>
            (a.output ?? "").localeCompare(b.output ?? "") || (a.idx ?? 0) - (b.idx ?? 0));
        const byId = {};
        for (const ws of wsList) byId[ws.id] = ws;
        root.workspaces = wsList;
        root.workspaceById = byId;
        root.activeWorkspace = wsList.find(ws => ws.is_focused) ?? null;
        root.windowList = Object.values(root._windows).map(root.normalizeWindow);
        root.updateFocusedMonitor();
    }

    function updateFocusedMonitor() {
        const out = root.activeWorkspace?.output ?? "";
        const mon = root.monitors.find(m => m.name === out) ?? null;
        if (mon !== root.focusedMonitor) root.focusedMonitor = mon;
    }

    function setWorkspaces(list) {
        const map = {};
        for (const ws of list) map[ws.id] = ws;
        root._workspaces = map;
    }

    function setWindows(list) {
        const map = {};
        for (const w of list) map[w.id] = w;
        root._windows = map;
    }

    function handleEvent(ev) {
        const [type] = Object.keys(ev);
        const d = ev[type];
        switch (type) {
        case "WorkspacesChanged":
            root.setWorkspaces(d.workspaces ?? []);
            break;
        case "WorkspaceActivated": {
            const target = root._workspaces[d.id];
            if (!target) { getWorkspaces.running = true; return; }
            for (const id in root._workspaces) {
                const ws = root._workspaces[id];
                if (ws.output === target.output) ws.is_active = (ws.id === d.id);
                if (d.focused) ws.is_focused = (ws.id === d.id);
            }
            break;
        }
        case "WorkspaceActiveWindowChanged": {
            const ws = root._workspaces[d.workspace_id];
            if (ws) ws.active_window_id = d.active_window_id;
            break;
        }
        case "WorkspaceUrgencyChanged": {
            const ws = root._workspaces[d.id];
            if (ws) ws.is_urgent = d.urgent;
            break;
        }
        case "WindowsChanged":
            root.setWindows(d.windows ?? []);
            break;
        case "WindowOpenedOrChanged": {
            const w = d.window;
            if (!w) return;
            if (w.is_focused)
                for (const id in root._windows) root._windows[id].is_focused = false;
            root._windows[w.id] = w;
            break;
        }
        case "WindowClosed":
            delete root._windows[d.id];
            break;
        case "WindowFocusChanged":
            for (const id in root._windows) root._windows[id].is_focused = (d.id !== null && Number(id) === d.id);
            break;
        case "WindowUrgencyChanged": {
            const w = root._windows[d.id];
            if (w) w.is_urgent = d.urgent;
            break;
        }
        case "WindowLayoutsChanged":
            for (const [id, layout] of (d.changes ?? [])) {
                const w = root._windows[id];
                if (w) w.layout = layout;
            }
            break;
        case "ConfigLoaded":
            getOutputs.running = true;
            return;
        default:
            return; // keyboard layouts, overview, casts, screenshots...
        }
        root.publish();
    }

    Connections {
        target: Quickshell
        function onScreensChanged() { getOutputs.running = true }
    }

    Component.onCompleted: getOutputs.running = true

    Process {
        id: getWindows
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.setWindows(JSON.parse(text));
                    root.publish();
                } catch (e) { console.log("[NiriBackend] windows parse error: " + e) }
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.setWorkspaces(JSON.parse(text));
                    root.publish();
                } catch (e) { console.log("[NiriBackend] workspaces parse error: " + e) }
            }
        }
    }

    Process {
        id: getOutputs
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const raw = JSON.parse(text);
                    root.monitors = Object.keys(raw).map(name => {
                        const o = raw[name];
                        return {
                            name: name,
                            make: o.make ?? "",
                            model: o.model ?? "",
                            current_mode: o.current_mode,
                            modes: o.modes,
                            logical: o.logical
                        };
                    });
                    root.focusedMonitor = null;
                    root.updateFocusedMonitor();
                } catch (e) { console.log("[NiriBackend] outputs parse error: " + e) }
            }
        }
    }

    Process {
        id: eventStream
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.length === 0) return;
                try {
                    root.handleEvent(JSON.parse(line));
                } catch (e) { console.log("[NiriBackend] event parse error: " + e) }
            }
        }
        onExited: restartTimer.restart()
    }
    // The stream replays full state on reconnect.
    Timer { id: restartTimer; interval: 1000; onTriggered: eventStream.running = true }
}
