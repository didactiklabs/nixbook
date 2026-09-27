import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical
    readonly property real barCenterOnlyOffset: (Config.options.bar.centerOnlyReserveFrame && root.centerOnly)
        ? Config.options.bar.frameThickness
        : Appearance.sizes.barHeight

    PanelWindow {
        id: panelWindow

        readonly property bool animatedEntrance: WM.compositor !== "hyprland"
        // Open, or still playing the exit animation.
        property bool reallyVisible: false

        // Kept mapped once built (niri/animated entrance). Hiding a Wayland
        // window destroys its surface, and Qt's threaded renderer then throws
        // away the window's GL context; every open used to recreate it
        // (eglCreateContext + shader/glyph caches: 130–230 ms per open,
        // measured). While closed the surface stays mapped as a sidebar-wide
        // strip with no input region, no keyboard focus and invisible content
        // (opacity 0 → nothing drawn); opening only widens it. The content
        // keeps its size, so nothing is re-laid-out either.
        property bool keepMapped: false
        visible: reallyVisible || keepMapped
        Region { id: noInput }
        mask: reallyVisible ? null : noInput
        Connections {
            target: Preloader
            function onSidebarRightChanged() {
                if (Preloader.sidebarRight && panelWindow.animatedEntrance)
                    panelWindow.keepMapped = true;
            }
        }
        // A mapped layer surface stays on its output: follow the focused
        // monitor on open (re-creates the surface only when it changes).
        screen: null
        function followFocusedScreen() {
            const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name);
            if (s && panelWindow.screen !== s) panelWindow.screen = s;
        }

        Component.onCompleted: reallyVisible = GlobalStates.sidebarRightOpen

        Connections {
            target: GlobalStates
            function onSidebarRightOpenChanged() {
                if (GlobalStates.sidebarRightOpen) {
                    closeAnimTimer.stop();
                    panelWindow.followFocusedScreen();
                    panelWindow.reallyVisible = true;
                    if (panelWindow.animatedEntrance) panelWindow.keepMapped = true;
                } else if (panelWindow.animatedEntrance) {
                    closeAnimTimer.restart();
                } else {
                    panelWindow.reallyVisible = false;
                }
            }
        }

        Timer {
            id: closeAnimTimer
            interval: 150
            onTriggered: panelWindow.reallyVisible = false
        }

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        onReallyVisibleChanged: {
            if (reallyVisible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (GlobalFocusGrab.spares(panelWindow)) return;
                panelWindow.hide();
            }
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        // Overlay so it stays above GlobalFocusGrab's click catcher (Top).
        WlrLayershell.layer: WlrLayer.Overlay
        // Open panels take the keyboard (see SidebarLeft): OnDemand only got it
        // after a click on this kept-mapped surface.
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
            // Full width (for the click-outside area) only while shown.
            left: animatedEntrance && panelWindow.reallyVisible
        }

        margins {
            top: {
                if (Config.options.bar.bottom) return 0;
                if (Config?.options.bar.autoHide.enable) return 0;
                if (!centerOnly) return 0;
                switch (Config.options.bar.cornerStyle) {
                case 0: return -root.barCenterOnlyOffset;
                case 1: return -root.barCenterOnlyOffset + Appearance.sizes.hyprlandGapsOut;
                case 2: return -root.barCenterOnlyOffset + Appearance.sizes.hyprlandGapsOut;
                case 3: return -root.barCenterOnlyOffset - Appearance.sizes.hyprlandGapsOut;
                default: return 0;
                }
            }
            bottom: {
                if (!Config.options.bar.bottom) return 0;
                if (Config?.options.bar.autoHide.enable) return 0;
                if (!centerOnly) return 0;
                switch (Config.options.bar.cornerStyle) {
                case 0: return -root.barCenterOnlyOffset;
                case 1: return -root.barCenterOnlyOffset + Appearance.sizes.hyprlandGapsOut;
                case 2: return -root.barCenterOnlyOffset + Appearance.sizes.hyprlandGapsOut;
                case 3: return -root.barCenterOnlyOffset - Appearance.sizes.hyprlandGapsOut;
                default: return 0;
                }
            }
        }

        Item {
            anchors.fill: parent

            MouseArea {
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                id: outsideClickArea
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            Item {
                id: entranceWrapper
                // Nothing drawn while closed (the surface stays mapped).
                // (≈invisible while booting: draws once so textures are uploaded)
                opacity: panelWindow.reallyVisible ? 1 : (Preloader.prerender ? 0.004 : 0)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: sidebarWidth
                clip: true

                readonly property bool open: GlobalStates.sidebarRightOpen
                // Right-anchored and slid with a transform, so widening the
                // window on open (see keepMapped) doesn't move the content.
                anchors.right: parent.right
                transform: Translate {
                    x: panelWindow.animatedEntrance && !entranceWrapper.open ? entranceWrapper.width : 0
                    Behavior on x {
                        enabled: panelWindow.animatedEntrance
                        NumberAnimation {
                            duration: entranceWrapper.open
                                ? Appearance.animation.sidebarSlideEnter.duration
                                : Appearance.animation.sidebarSlideExit.duration
                            easing.type: entranceWrapper.open
                                ? Appearance.animation.sidebarSlideEnter.type
                                : Appearance.animation.sidebarSlideExit.type
                            easing.bezierCurve: entranceWrapper.open
                                ? Appearance.animation.sidebarSlideEnter.bezierCurve
                                : Appearance.animation.sidebarSlideExit.bezierCurve
                        }
                    }
                }

                MouseArea {
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                    z: -1
                }

                Loader {
                    id: sidebarContentLoader
                    active: panelWindow.reallyVisible || Config?.options.sidebar.keepRightSidebarLoaded
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.hyprlandGapsOut
                        leftMargin: Appearance.sizes.elevationMargin
                    }
                    width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

                    focus: GlobalStates.sidebarRightOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {}
                }
            }
        }

        IpcHandler {
            target: "sidebarRight"

            function toggle(): void {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }

            function close(): void {
                GlobalStates.sidebarRightOpen = false;
            }

            function open(): void {
                GlobalStates.sidebarRightOpen = true;
            }
        }

        CompositorGlobalShortcut {
            name: "sidebarRightToggle"
            description: "Toggles right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }
        CompositorGlobalShortcut {
            name: "sidebarRightOpen"
            description: "Opens right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = true;
            }
        }
        CompositorGlobalShortcut {
            name: "sidebarRightClose"
            description: "Closes right sidebar on press"

            onPressed: {
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }
}