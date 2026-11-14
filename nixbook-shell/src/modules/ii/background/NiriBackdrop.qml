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

    // One of WallpaperLayer's two pictures (see `picture` there).
    component BackdropSlot: Image {
        property string path: ""
        source: path
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        visible: path !== "" && opacity > 0
    }

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

        // Two pictures, the new one fading in over the old one. Windows show
        // this layer (niri's xray blur), not the desktop's: when it switched
        // in one frame, the wallpaper transition (Background.qml) was seen
        // only in the gaps between windows — with a window filling the
        // workspace, hardly at all. The fade lasts as long as that transition
        // and starts, like it, once the new picture is decoded (one shared
        // decode). Blurring the fade is fading the blurs: one FastBlur, which
        // redraws only while the fade runs; the old picture is let go after.
        Item {
            id: picture
            width: parent.width / surface.shrink
            height: parent.height / surface.shrink
            // Blurred, the blur draws it: through `fadeSource` while fading
            // (an item rendered into a texture must be visible), straight
            // from the shown picture's texture otherwise.
            visible: !surface.blurred || picture.fading
            readonly property bool fading: fadeIn.running

            property BackdropSlot shown: slotA
            property BackdropSlot incoming: slotB
            readonly property string target: surface.wallpaperPath
            onTargetChanged: picture.show()
            Component.onCompleted: slotA.path = picture.target

            function show() {
                if (fadeIn.running) picture.settle()
                if (picture.shown.path === picture.target || picture.shown.path === "") {
                    // The same picture, or nothing shown yet: no fade.
                    picture.shown.path = picture.target
                    picture.incoming.path = ""
                    return
                }
                picture.incoming.opacity = 0
                picture.incoming.z = 1
                picture.shown.z = 0
                picture.incoming.path = picture.target
                if (picture.incoming.status === Image.Ready) fadeIn.restart()
            }
            // The new picture on top, the old one let go.
            function settle() {
                fadeIn.stop()
                picture.incoming.opacity = 1
                const old = picture.shown
                picture.shown = picture.incoming
                picture.incoming = old
                old.path = ""
                old.opacity = 0
            }
            function onReady(slot) {
                if (slot === picture.incoming && slot.path !== "" && !fadeIn.running) fadeIn.restart()
            }

            NumberAnimation {
                id: fadeIn
                target: picture.incoming
                property: "opacity"
                from: 0
                to: 1
                duration: 1000 // Background.qml's transitionAnim
                easing.type: Easing.InOutQuad
                onFinished: picture.settle()
            }

            // Screen size, the same request as Background.qml's wallpaper:
            // one shared decode. Unbounded, a wallpaper change decoded the
            // full-resolution file again and uploaded that texture in the
            // middle of the transition.
            readonly property size decodeSize: Qt.size(Math.ceil(surface.pixelSize.width / surface.shrink),
                Math.ceil(surface.pixelSize.height / surface.shrink))
            BackdropSlot {
                id: slotA
                anchors.fill: parent
                sourceSize: picture.decodeSize
                onStatusChanged: if (status === Image.Ready) picture.onReady(slotA)
            }
            BackdropSlot {
                id: slotB
                anchors.fill: parent
                opacity: 0
                sourceSize: picture.decodeSize
                onStatusChanged: if (status === Image.Ready) picture.onReady(slotB)
            }
        }

        // Only while it shows (a video's still frame isn't blurred): hidden
        // after it has drawn, a FastBlur keeps the off-screen textures of its
        // steps, the first two as large as the screen.
        Loader {
            active: surface.blurred
            width: picture.width
            height: picture.height
            scale: surface.shrink
            transformOrigin: Item.TopLeft
            sourceComponent: Item {
                // Both pictures, rendered into one texture, only while the
                // fade runs: at rest the blur reads the shown picture's own
                // texture (no extra screen-sized buffer).
                Loader {
                    id: fadeSource
                    anchors.fill: parent
                    active: picture.fading
                    sourceComponent: ShaderEffectSource {
                        sourceItem: picture
                        hideSource: true
                        visible: false
                    }
                }
                FastBlur {
                    anchors.fill: parent
                    source: picture.fading && fadeSource.item ? fadeSource.item : picture.shown
                    radius: surface.blurRadius
                    transparentBorder: false
                }
            }
        }
    }

    Scope {
        id: perScreen
        required property var modelData

        // The picture the desktop shows (Background.qml): the one just
        // applied (Wallpapers.confirmedPath) before config.json has it, so
        // both change together. A video wallpaper plays on the Bottom layer
        // (live-wallpaper.sh): the surfaces here hold its still frame.
        readonly property string effectivePath: Wallpapers.confirmedPath || Config.options.background.wallpaperPath
        readonly property bool video: Wallpapers.isVideo(effectivePath)
        readonly property string wallpaperPath: video
            ? Wallpapers.posterFor(effectivePath)
            : effectivePath

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
