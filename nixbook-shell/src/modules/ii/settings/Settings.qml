//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Scope {
    id: root

    readonly property real sizeScale: Config.options.settings.style === "minimal" ? 0.75 : 1.0
    property bool isMinimal: Config.options.settings.style === "minimal"

    Component.onCompleted: {
        GlobalStates.settingsOpen = false;
    }

    // A normal application window (xdg-toplevel), managed by the compositor
    // like any app: it can be moved, resized, tiled/floated, focused and
    // closed from the WM (e.g. Mod+Q), and it no longer closes itself when you
    // click elsewhere. It used to be a full-screen Overlay layer surface
    // dismissed by any outside click.
    FloatingWindow {
        id: settingsWindow
        title: Translation.tr("Shell settings")
        visible: false
        implicitWidth: Math.round(1180 * root.sizeScale)
        implicitHeight: Math.round(800 * root.sizeScale)
        minimumSize: Qt.size(640, 460)
        color: Appearance.colors.colLayer0

        // Two-way sync with GlobalStates.settingsOpen (IPC, sidebar button,
        // launcher…): the window's own visibility changes when the compositor
        // closes it, so it isn't a plain binding.
        Connections {
            target: GlobalStates
            function onSettingsOpenChanged() {
                settingsWindow.visible = GlobalStates.settingsOpen;
            }
        }
        onClosed: GlobalStates.settingsOpen = false
        onVisibleChanged: {
            if (!visible && GlobalStates.settingsOpen)
                GlobalStates.settingsOpen = false;
        }

        Item {
            id: keyHandler
            anchors.fill: parent
            focus: true

            Keys.onTabPressed: (event) => {
                const count = settingsContent.pages.length;
                settingsContent.currentPage = (settingsContent.currentPage + 1) % count;
                settingsContent.showingProfile = false;
                event.accepted = true;
            }

            Keys.onBacktabPressed: (event) => {
                const count = settingsContent.pages.length;
                settingsContent.currentPage = (settingsContent.currentPage - 1 + count) % count;
                settingsContent.showingProfile = false;
                event.accepted = true;
            }

            Keys.onPressed: (event) => {
                // Ctrl+F: the sidebar's search.
                if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                    settingsContent.focusSearch();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.settingsOpen = false;
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    const instance = GlobalStates.currentPageInstance;
                    if (instance && instance.contentY !== undefined) {
                        const step = 60;
                        const delta = event.key === Qt.Key_Down ? step : -step;
                        const maxY = Math.max(0, (instance.contentHeight ?? 0) - instance.height);
                        instance.contentY = Math.max(0, Math.min(maxY, instance.contentY + delta));
                    }
                    event.accepted = true;
                    return;
                }
            }

            SettingsContent {
                id: settingsContent
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen; }
        function open(): void   { GlobalStates.settingsOpen = true; }
        function close(): void  { GlobalStates.settingsOpen = false; }
    }
}
