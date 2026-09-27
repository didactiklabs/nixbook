pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

Variants {
    id: wallpaperBackdropRoot
    model: Quickshell.screens

    Loader {
        id: loader
        required property var modelData
        active: WM.compositor === "niri"

        sourceComponent: PanelWindow {
            id: backdrop
            screen: loader.modelData

            // A video wallpaper plays on the Bottom layer (live-wallpaper.sh):
            // this Background-layer surface — what niri's xray blur samples —
            // holds its still frame, so windows don't re-blur every frame.
            readonly property bool video: Wallpapers.isVideo(Config.options.background.wallpaperPath)
            property string wallpaperPath: video
                ? Config.options.background.thumbnailPath
                : Config.options.background.wallpaperPath

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:wallpaper"
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Image {
                id: sourceImage
                anchors.fill: parent
                source: backdrop.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                // A video's still frame is shown sharp: it is what windows see
                // through their (xray) blur, and niri's blur on top of this one
                // left a flat colour — windows looked opaque.
                visible: backdrop.video
            }

            FastBlur {
                visible: !backdrop.video
                anchors.fill: parent
                source: sourceImage
                radius: 48 // fixme variable
                transparentBorder: false
            }
        }
    }
}
