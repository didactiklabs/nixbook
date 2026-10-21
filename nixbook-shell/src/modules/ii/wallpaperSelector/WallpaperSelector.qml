import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool reallyOpen: false
    // Keep the selector instantiated once it has been opened the first time:
    // building the whole content tree (folder list, thumbnail grids, delegates)
    // is what made the panel pop up slowly, and there is nothing to gain from
    // tearing it down again — while hidden the only live timers in the
    // content only run during a drag.
    property bool everOpened: false

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                closeAnimTimer.stop();
                // Before the content's own handlers: it checks the monitor.
                wallpaperSelectorLoader.item?.followFocusedScreen();
                root.reallyOpen = true;
                root.everOpened = true;
            } else {
                closeAnimTimer.restart();
            }
        }
    }

    Timer {
        id: closeAnimTimer
        interval: Appearance.animation.sidebarSlideExit.duration
        onTriggered: root.reallyOpen = false
    }

    Loader {
        id: wallpaperSelectorLoader
        active: root.everOpened || Preloader.wallpaperSelector

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property var monitor: WM.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: WM.focusedMonitor?.name == monitor?.name

            // Stays mapped once opened or preloaded: unmapping destroys the
            // surface and Qt rebuilt its GL context on the next open
            // (≈100–200 ms, the start of the slide-in). Closed = no input
            // region, no keyboard focus, content slid out of the window.
            property bool keepMapped: false
            visible: keepMapped || root.reallyOpen
            function followFocusedScreen() {
                const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name);
                if (s && panelWindow.screen !== s) panelWindow.screen = s;
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            // Takes the keyboard while shown (arrow keys, search, Escape).
            WlrLayershell.keyboardFocus: root.reallyOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.gapsOut : Appearance.sizes.barHeight + Appearance.sizes.gapsOut
            }

            mask: Region {
                item: root.reallyOpen ? content : null
            }

            implicitHeight: Appearance.sizes.wallpaperSelectorHeight
            implicitWidth: Appearance.sizes.wallpaperSelectorWidth

            Component.onCompleted: {
                panelWindow.keepMapped = true;
                panelWindow.followFocusedScreen();
                if (!root.reallyOpen) { // preloaded hidden
                    content.y = -content.height;
                    return;
                }
                GlobalFocusGrab.addDismissable(panelWindow);
                content.slideIn();
            }
            // The window survives a close, so the focus grab has to follow
            // being open instead of the window's lifetime — a closed member of
            // the grab list would keep the grab armed with nothing on screen.
            Connections {
                target: root
                function onReallyOpenChanged() {
                    if (root.reallyOpen) GlobalFocusGrab.addDismissable(panelWindow);
                    else GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (GlobalFocusGrab.spares(panelWindow)) return;
                    GlobalStates.wallpaperSelectorOpen = false;
                }
            }

            WallpaperSelectorContent {
                id: content
                width: parent.width
                height: parent.height
                x: 0
                y: 0
                // Closed: transparent too, so what's gated on being shown
                // (spinners, ObjectUtils.shown) stops.
                opacity: root.reallyOpen ? 1 : 0

                function slideIn() {
                    content.y = -content.height;
                    Qt.callLater(() => { Qt.callLater(() => { content.y = 0; }); });
                }

                Connections {
                    target: GlobalStates
                    function onWallpaperSelectorOpenChanged() {
                        if (GlobalStates.wallpaperSelectorOpen) {
                            // Re-opened (including a reopen mid-close-animation).
                            content.slideIn();
                        } else {
                            content.y = -content.height;
                        }
                    }
                }

                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.animation.sidebarSlideEnter.duration
                        easing.type: GlobalStates.wallpaperSelectorOpen
                            ? Appearance.animation.sidebarSlideEnter.type
                            : Appearance.animation.sidebarSlideExit.type
                        easing.bezierCurve: GlobalStates.wallpaperSelectorOpen
                            ? Appearance.animation.sidebarSlideEnter.bezierCurve
                            : Appearance.animation.sidebarSlideExit.bezierCurve
                    }
                }
            }
        }
    }

    function toggleWallpaperSelector() {
        if (Config.options.wallpaperSelector.useSystemFileDialog) {
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
            return;
        }
        GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
    }

    IpcHandler {
        target: "wallpaperSelector"

        function toggle(): void {
            root.toggleWallpaperSelector();
        }

        function random(): void {
            Wallpapers.randomFromCurrentFolder();
        }
    }
}