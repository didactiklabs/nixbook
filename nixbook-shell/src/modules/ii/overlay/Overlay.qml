import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // The overlay window is built the first time it is needed (opened, or a
    // widget pinned) and kept alive afterwards; only the layer surface is
    // mapped/unmapped, so reopening skips rebuilding every overlay widget.
    readonly property bool overlayShown: GlobalStates.overlayOpen || OverlayContext.hasPinnedWidgets
    property bool overlayEverShown: false
    onOverlayShownChanged: if (overlayShown) overlayEverShown = true
    Component.onCompleted: if (overlayShown) overlayEverShown = true

    Loader {
        id: overlayLoader
        active: root.overlayEverShown || Preloader.overlay
        sourceComponent: PanelWindow {
            id: overlayWindow
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            // Use OnDemand for pinned widgets to allow focus switching with mouse clicks
            WlrLayershell.keyboardFocus: GlobalStates.overlayOpen ? WlrKeyboardFocus.Exclusive : (OverlayContext.clickableWidgets.length > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            visible: root.overlayShown
            color: "transparent"

            // Re-arm the opening zoom while hidden so every fresh open animates
            // like it did when the window was recreated each time.
            onVisibleChanged: {
                if (visible)
                    overlayContent.scale = 1;
                else
                    overlayContent.rearmEntrance();
            }

            // One Region per pinned widget, kept while that widget stays
            // pinned (creating them in the mask binding leaked a new set on
            // every change).
            Variants {
                id: clickableRegions
                model: OverlayContext.clickableWidgets
                delegate: Region {
                    required property var modelData
                    item: modelData
                }
            }
            mask: Region {
                item: GlobalStates.overlayOpen ? overlayContent : null
                regions: clickableRegions.instances
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            OverlayContent {
                id: overlayContent
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "overlay"

        function toggle(): void {
            GlobalStates.overlayOpen = !GlobalStates.overlayOpen;
        }
    }
}
