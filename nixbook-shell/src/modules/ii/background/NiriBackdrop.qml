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

    component WallpaperLayer: PanelWindow {
        id: surface

        required property string layerName
        required property string wallpaperPath
        property bool blurred: true
        // Blurred at 1/shrink of the screen and scaled up: nothing of the
        // picture is finer than the blur, and the source and FastBlur's
        // intermediate textures stay in memory for as long as the shell runs.
        property int shrink: 1
        property int blurRadius: 48 // fixme variable
        readonly property size pixelSize: Wallpapers.pixelSize(surface.screen.name, surface.screen.width, surface.screen.height,
            surface.screen.devicePixelRatio)

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: surface.layerName
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // A single picture (or its blur) and nothing over it: no depth and
        // stencil buffers, which are as large as the surface (28 MB each at
        // 2880×1800) and serve overlapping or rotated, clipped content only
        // (quickshell.nix, patches/quickshell-surface-no-depth-stencil.patch).
        surfaceFormat.depthStencil: false

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Image {
            id: sourceImage
            width: parent.width / surface.shrink
            height: parent.height / surface.shrink
            source: surface.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            // Screen size, the same request as Background.qml's wallpaper:
            // one shared decode. Unbounded, a wallpaper change decoded the
            // full-resolution file again and uploaded that texture in the
            // middle of the transition.
            sourceSize: Qt.size(Math.ceil(surface.pixelSize.width / surface.shrink),
                Math.ceil(surface.pixelSize.height / surface.shrink))
            asynchronous: true
            // The previous picture until the new one is decoded: cleared, the
            // surface was empty for a few frames and the windows above showed
            // niri's background colour.
            retainWhileLoading: true
            cache: true
            smooth: true
            visible: !surface.blurred
        }

        // Only while it shows (a video's still frame isn't blurred): hidden
        // after it has drawn, a FastBlur keeps the off-screen textures of its
        // steps, the first two as large as the screen.
        Loader {
            active: surface.blurred
            width: sourceImage.width
            height: sourceImage.height
            scale: surface.shrink
            transformOrigin: Item.TopLeft
            sourceComponent: FastBlur {
                source: sourceImage
                radius: surface.blurRadius
                transparentBorder: false
            }
        }
    }

    Scope {
        id: perScreen
        required property var modelData

        // A video wallpaper plays on the Bottom layer (live-wallpaper.sh):
        // the surfaces here hold its still frame.
        readonly property bool video: Wallpapers.isVideo(Config.options.background.wallpaperPath)
        readonly property string wallpaperPath: video
            ? Config.options.background.thumbnailPath
            : Config.options.background.wallpaperPath

        // What niri's xray blur samples, so windows don't re-blur every frame
        // of a video. A video's still frame is shown sharp: niri's blur on top
        // of this one left a flat colour, and windows looked opaque.
        WallpaperLayer {
            screen: perScreen.modelData
            layerName: "quickshell:wallpaper"
            wallpaperPath: perScreen.wallpaperPath
            blurred: !perScreen.video
        }

        // Behind the workspaces: what the overview shows around them (niri's
        // place-within-backdrop rule, homeManagerModules/niri/niriConfig.nix).
        // A surface of its own, since one in the backdrop leaves the Background
        // layer xray samples: with niri's opaque workspace background, windows
        // would show that flat colour instead of the wallpaper.
        WallpaperLayer {
            screen: perScreen.modelData
            layerName: "quickshell:wallpaperBackdrop"
            wallpaperPath: perScreen.wallpaperPath
            shrink: 8
            blurRadius: 20
        }
    }
}
