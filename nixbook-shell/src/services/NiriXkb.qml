pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Exposes the active niri Xkb keyboard layout name and code for indicators.
 */
Singleton {
    id: root
    property list<string> layoutNames: []
    property int currentIdx: 0
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"

    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (!root.currentLayoutName) return;
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName];
        } else {
            getLayoutProc.running = true;
        }
    }

    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                lines.find(line => {
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1];
                        root.currentLayoutCode = matchLayout[1];
                        return true;
                    }

                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout;
                        root.currentLayoutCode = complexLayout;
                        return true;
                    }

                    return false;
                });
            }
        }
    }

    function refresh() {
        fetchLayoutsProc.running = true;
    }

    Process {
        id: fetchLayoutsProc
        command: ["niri", "msg", "-j", "keyboard-layouts"]

        stdout: StdioCollector {
            id: layoutsCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(layoutsCollector.text);
                    root.layoutNames = parsed.names ?? [];
                    root.currentIdx = parsed.current_idx ?? 0;
                    root.currentLayoutName = root.layoutNames[root.currentIdx] ?? "";
                } catch (e) {
                    console.log("[NiriXkb] keyboard-layouts parse error: " + e);
                }
            }
        }
    }

    // Layout changes come from the niri backend's event stream (a second
    // `niri msg event-stream` here parsed every niri event twice, including
    // the per-frame WindowLayoutsChanged ones).
    function applyFromBackend() {
        const backend = WM.backend;
        if (!backend?.keyboardLayoutsKnown) return;
        root.layoutNames = backend.keyboardLayoutNames;
        root.currentIdx = backend.keyboardLayoutIdx;
        root.currentLayoutName = root.layoutNames[root.currentIdx] ?? "";
    }
    Connections {
        target: WM.backend
        function onKeyboardLayoutNamesChanged() { root.applyFromBackend() }
        function onKeyboardLayoutIdxChanged() { root.applyFromBackend() }
        function onKeyboardLayoutsKnownChanged() { root.applyFromBackend() }
    }

    Component.onCompleted: {
        if (WM.backend?.keyboardLayoutsKnown) applyFromBackend();
        else refresh();
    }
}