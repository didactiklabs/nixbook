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
 * open. Clicking one opens that sidebar; hovering it a moment
 * (sidebar.edgeHandles.hoverToOpen) opens it as a peek, which closes again
 * when the pointer leaves the sidebar. Each is a tiny surface with no exclusive zone, so
 * windows keep the whole screen; only a 6px strip of it takes input.
 * Hidden while its sidebar is open, on fullscreen and on the lock screen.
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
        readonly property bool hovered: shown && hitArea.containsMouse

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
        implicitHeight: pill.implicitHeight + 24

        Region { id: noInput }
        mask: shown ? hitRegion : noInput
        Region { id: hitRegion; item: hitArea }

        MouseArea {
            id: hitArea
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: handleWindow.right ? undefined : parent.left
            anchors.right: handleWindow.right ? parent.right : undefined
            // Grows with the tab once hovered, so it doesn't flicker away
            width: containsMouse ? parent.width : 6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: handleWindow.open(false)
        }

        Timer {
            interval: 250
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
