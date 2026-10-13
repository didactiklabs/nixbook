import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Edge handles for the sidebars: a small pill (EdgePill) half-way down the
 * left and right screen edges of the focused monitor, where the sidebars
 * open. Like the dock, the whole middle stretch of the edge (40% of the
 * screen height) is the trigger, not only the pill: pushing the pointer
 * against it opens that sidebar almost at once as a peek
 * (sidebar.edgeHandles.hoverToOpen), which closes again when the pointer
 * leaves the sidebar; clicking opens it to stay. Each is a narrow surface
 * with no exclusive zone, so windows keep the whole screen; only a 3px edge
 * strip (6px at the pill) takes input. Hidden while its sidebar is open, on
 * fullscreen and on the lock screen.
 */
Scope {
    id: root
    readonly property var cfg: Config.options?.sidebar?.edgeHandles

    component Handle: PanelWindow {
        id: handleWindow
        required property bool right
        property var monitor: WM.monitorFor(screen)

        readonly property bool sidebarOpen: right ? GlobalStates.sidebarRightOpen : GlobalStates.sidebarLeftOpen
        readonly property bool shown: !sidebarOpen
            && !GlobalStates.screenLocked
            && WM.focusedMonitor?.name === monitor?.name
            && !WM.fullscreenOnMonitor(monitor?.name)
        readonly property bool hovered: shown && (edgeArea.containsMouse || pillArea.containsMouse)

        function open(peek) {
            if (right) {
                GlobalStates.sidebarRightPeek = peek;
                GlobalStates.sidebarRightOpen = true;
            } else {
                GlobalStates.sidebarLeftPeek = peek;
                GlobalStates.sidebarLeftOpen = true;
            }
        }

        anchors.left: !right
        anchors.right: right
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarHandle"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: pill.implicitWidth + 4
        implicitHeight: Math.max(pill.implicitHeight + 24, (screen?.height ?? 0) * 0.4)

        Region { id: noInput }
        mask: shown ? hitRegion : noInput
        Region {
            id: hitRegion
            item: edgeArea
            Region { item: pillArea }
        }

        // The edge strip: thin, so it barely overlaps what's beside the edge
        // (a scrollbar), but the pointer stops on it when pushed to the edge.
        MouseArea {
            id: edgeArea
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: handleWindow.right ? undefined : parent.left
            anchors.right: handleWindow.right ? parent.right : undefined
            width: 3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: handleWindow.open(false)
        }
        // Around the pill: a bit wider, and the whole tab once hovered so it
        // doesn't flicker away.
        MouseArea {
            id: pillArea
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: handleWindow.right ? undefined : parent.left
            anchors.right: handleWindow.right ? parent.right : undefined
            height: pill.implicitHeight + 24
            width: handleWindow.hovered ? parent.width : 6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: handleWindow.open(false)
        }

        // A short delay only, so the pointer just sweeping past the edge
        // doesn't open it.
        Timer {
            interval: 80
            running: handleWindow.hovered && (root.cfg?.hoverToOpen ?? true)
            onTriggered: handleWindow.open(true)
        }

        EdgePill {
            id: pill
            vertical: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: handleWindow.right ? undefined : parent.left
            anchors.right: handleWindow.right ? parent.right : undefined
            // Resting pill 3px off the edge; the hovered tab tucks into it
            anchors.leftMargin: -2
            anchors.rightMargin: -2
            shown: handleWindow.shown
            hovered: handleWindow.hovered
            icon: handleWindow.right ? "keyboard_arrow_left" : "keyboard_arrow_right"
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            LazyLoader {
                active: root.cfg?.left ?? true
                Handle { screen: screenScope.modelData; right: false }
            }
            LazyLoader {
                active: root.cfg?.right ?? true
                Handle { screen: screenScope.modelData; right: true }
            }
        }
    }
}
