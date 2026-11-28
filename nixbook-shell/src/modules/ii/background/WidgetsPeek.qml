pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * A peek at the desktop widgets over the windows (GlobalStates.desktopWidgetsPeek:
 * the Widgets quick toggle, Mod+Shift+D, `ipc call widgetsPeek toggle`). The
 * widgets live on the wallpaper, behind the windows, and never take a click
 * there; a peek moves them into an Overlay window per screen, over a light
 * scrim, where they work as on the desktop (drag, type in a note…). It ends
 * on a click on the empty space, Escape, the toggle again, a workspace switch
 * or another popup opening (GlobalFocusGrab), the lock, or an agent starting
 * to work on the desktop (MakeWay): nothing stays over the windows.
 */
Scope {
    id: root

    function close() {
        GlobalStates.desktopWidgetsPeek = false;
    }

    Connections {
        target: MakeWay
        function onActiveChanged() {
            if (MakeWay.active) root.close();
        }
    }

    IpcHandler {
        target: "widgetsPeek"
        function toggle(): void {
            GlobalStates.desktopWidgetsPeek = !GlobalStates.desktopWidgetsPeek;
        }
        function open(): void {
            GlobalStates.desktopWidgetsPeek = true;
        }
        function close(): void {
            root.close();
        }
        function status(): string {
            return GlobalStates.desktopWidgetsPeek ? "open" : "closed";
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            Loader {
                active: GlobalStates.desktopWidgetsOnTop
                sourceComponent: PanelWindow {
                    id: win
                    screen: screenScope.modelData
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "quickshell:desktopWidgetsPeek"
                    // The keyboard while it shows: Escape, and typing into a note.
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"

                    // With the other popups: opening it closes them (the right
                    // panel the toggle was clicked in), one opening or a
                    // workspace switch closes it. Every screen's peek is one group.
                    Component.onCompleted: GlobalFocusGrab.addDismissable(win, "desktopWidgetsPeek")
                    Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
                    Connections {
                        target: GlobalFocusGrab
                        function onDismissed() {
                            if (!GlobalFocusGrab.spares(win)) root.close();
                        }
                    }

                    readonly property bool wallpaperSafetyTriggered: {
                        const path = Config.options.background.wallpaperPath.toLowerCase();
                        return Config.options.workSafety.enable.wallpaper
                            && CF.StringUtils.stringListContainsSubstring(path, Config.options.workSafety.triggerCondition.fileKeywords)
                            && CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords);
                    }

                    Item {
                        id: content
                        anchors.fill: parent
                        focus: true
                        opacity: 0
                        Component.onCompleted: opacity = 1
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Keys.onEscapePressed: root.close()

                        // The windows dimmed a little: what is on top is a peek.
                        Rectangle {
                            anchors.fill: parent
                            color: CF.ColorUtils.transparentize(Appearance.colors.colScrim, 0.65)
                        }

                        WidgetCanvas {
                            id: canvas
                            anchors.fill: parent
                            // A click on the empty space (not a drag selecting
                            // widgets) ends the peek.
                            onClicked: {
                                if (canvas.selectionRect.width < 6 && canvas.selectionRect.height < 6)
                                    root.close();
                            }

                            WidgetsLoader {
                                anchors.fill: parent
                                instant: true
                                screen: win.screen
                                // The wallpaper is in the desktop window: "Blur
                                // widgets" has nothing to blur here (the tint stays).
                                wallpaperItem: null
                                wallpaperSafetyTriggered: win.wallpaperSafetyTriggered
                            }
                        }
                    }
                }
            }
        }
    }
}
