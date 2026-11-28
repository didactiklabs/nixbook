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
 * screen height) is the trigger, not only the pill: holding the pointer
 * against it for sidebar.edgeHandles.hoverDelay opens that sidebar as a peek
 * (sidebar.edgeHandles.hoverToOpen), which closes again when the pointer
 * leaves the sidebar, and takes the keyboard only once used (`glancing` in
 * the sidebars); clicking opens it to stay. Each is a narrow surface
 * with no exclusive zone, so windows keep the whole screen; only a 3px edge
 * strip (6px at the pill) takes input. Hidden while its sidebar is open, on
 * fullscreen and on the lock screen.
 *
 * With the vertical bar on that side (not auto-hiding), the window ignores
 * the bar's exclusive zone and sits on the Overlay layer: the trigger strip
 * is the true screen edge again, over the bar's outer padding, so the pointer
 * thrown at the edge finds it (Fitts); the pill stays visible just outside
 * the bar's inner edge (`inset`), clickable too. It used to start after the
 * bar's zone, a 3px target floating in mid-screen.
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

        // The vertical bar on this edge of this screen: its width, which the
        // pill sits beyond (0: no bar here).
        readonly property var barOpts: Config.options?.bar
        readonly property bool barHere: (barOpts?.vertical ?? false)
            && (barOpts?.bottom ?? false) === right
            && !(barOpts?.autoHide?.enable ?? false)
            && GlobalStates.barOpen
            && ((barOpts?.screenList ?? []).length === 0 || barOpts.screenList.includes(screen?.name))
        readonly property real inset: !barHere ? 0
            : Appearance.sizes.baseVerticalBarWidth
                + (barOpts.cornerStyle === 1 ? Appearance.sizes.gapsOut : 0)
                + (barOpts.cornerStyle === 3 ? (Appearance.sizes.gapsOut || 5) : 0)

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
        exclusionMode: barHere ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarHandle"
        // Above the bar, whose outer edge the trigger strip lies on.
        WlrLayershell.layer: barHere ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: inset + pill.implicitWidth + 4
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
            anchors.leftMargin: handleWindow.inset
            anchors.rightMargin: handleWindow.inset
            height: pill.implicitHeight + 24
            width: handleWindow.hovered ? parent.width - handleWindow.inset : 6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: handleWindow.open(false)
        }

        // Long enough that the pointer reaching for something at the edge,
        // or crossing to the next monitor, can leave before it opens.
        Timer {
            interval: root.cfg?.hoverDelay ?? 200
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
            anchors.leftMargin: handleWindow.inset - 2
            anchors.rightMargin: handleWindow.inset - 2
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
