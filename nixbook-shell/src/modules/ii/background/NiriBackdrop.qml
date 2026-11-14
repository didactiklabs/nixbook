pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

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

    // The picture the desktop shows (Background.qml): the one just applied
    // (Wallpapers.confirmedPath) before config.json has it, so both change
    // together. A video wallpaper plays on the Bottom layer
    // (live-wallpaper.sh): the surfaces here hold its still frame.
    readonly property string effectivePath: Wallpapers.confirmedPath || Config.options.background.wallpaperPath
    readonly property bool video: Wallpapers.isVideo(effectivePath)
    readonly property string wallpaperPath: video
        ? Wallpapers.posterFor(effectivePath)
        : effectivePath

    // What niri's xray blur samples, so windows don't re-blur every frame of a
    // video. A video's still frame is shown sharp: niri's blur on top of this
    // one left a flat colour, and windows looked opaque.
    Variants {
        model: Quickshell.screens
        WallpaperLayer {
            required property var modelData
            screen: modelData
            layerName: "quickshell:wallpaper"
            wallpaperPath: root.wallpaperPath
            blurred: !root.video
        }
    }

    // Behind the workspaces: what the overview shows around them, the
    // wallpaper blurred (niri's place-within-backdrop rule for the namespace
    // "wallpaper", homeManagerModules/niri/niriConfig.nix). Not xray's
    // surface above: one in the backdrop leaves the Background layer xray
    // samples, and with niri's opaque workspace background windows would
    // show that flat colour. And not a window of the shell: niri doesn't
    // count a surface behind the workspaces as shown and sends it its frame
    // callbacks once a second, Qt takes a window without one for 100 ms as
    // obscured and draws it again each time it is exposed, so that window
    // drew the same picture once a second for good, and each of those frames
    // made niri present the whole screen again (the panel never rested).
    // swaybg draws the picture once: blurred here at 1/8 of the largest
    // screen (magick), scaled up by swaybg, one process for every screen.
    readonly property size backdropSize: {
        let w = 0, h = 0;
        for (const screen of Quickshell.screens) {
            const px = Wallpapers.pixelSize(screen.name, screen.width, screen.height, screen.devicePixelRatio);
            if (px.width * px.height > w * h) { w = px.width; h = px.height; }
        }
        return Qt.size(Math.ceil(w / 8), Math.ceil(h / 8));
    }
    readonly property string backdropWanted: root.wallpaperPath === "" || root.backdropSize.width < 1 ? ""
        : `${CF.FileUtils.trimFileProtocol(root.wallpaperPath)}\n${root.backdropSize.width}x${root.backdropSize.height}`
    onBackdropWantedChanged: backdropSoon.restart()
    Component.onCompleted: backdropSoon.restart()
    property string backdropMade: ""   // what the running swaybg shows (a `backdropWanted`)
    property string backdropMaking: ""
    property int backdropSlot: 0       // which of the two swaybg shows it
    property int backdropTries: 0
    function backdropFile(slot) {
        return `${Directories.runtimeTemp}/overview-backdrop-${slot}.png`;
    }
    Timer {
        id: backdropSoon
        interval: 400
        onTriggered: {
            if (root.backdropWanted === root.backdropMade || blurProc.running) return;
            if (root.backdropWanted === "") {
                root.backdropMade = "";
                return;
            }
            const [path, size] = root.backdropWanted.split("\n");
            root.backdropMaking = root.backdropWanted;
            // `[0]`: a GIF's first picture. Covers the size, cut to it, blurred.
            blurProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$3")" && exec magick "$1[0]" -resize "$2^" -gravity center -extent "$2" -blur 0x5 "$3"',
                "sh", path, size, root.backdropFile(1 - root.backdropSlot)];
            blurProc.running = true;
        }
    }
    Process {
        id: blurProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // A video's still frame may not be written yet.
                if (root.backdropTries++ < 5) backdropSoon.restart();
                else console.warn(`[NiriBackdrop] the overview's backdrop couldn't be made from ${root.backdropMaking.split("\n")[0]}`);
                return;
            }
            root.backdropTries = 0;
            // The new one mapped over the old one, which then goes (the
            // timer first: it is what keeps the old one for that moment).
            backdropOldOff.restart();
            root.backdropSlot = 1 - root.backdropSlot;
            root.backdropMade = root.backdropMaking;
            if (root.backdropWanted !== root.backdropMade) backdropSoon.restart();
        }
    }
    Timer {
        id: backdropOldOff
        interval: 800
    }
    component BackdropPlayer: Process {
        id: player
        required property int slot
        readonly property bool wanted: root.backdropMade !== ""
            && (root.backdropSlot === slot || backdropOldOff.running)
        property bool resting: false
        running: wanted && !resting
        command: ["swaybg", "-m", "fill", "-i", root.backdropFile(slot)]
        // Ended on its own (the compositor's socket went, a missing file):
        // tried again after a moment, not in a loop.
        onExited: (exitCode, exitStatus) => {
            if (!wanted) return;
            console.log(`[NiriBackdrop] swaybg ended on its own (exit ${exitCode}), starting it again in 5 s`);
            resting = true;
            again.restart();
        }
        property Timer again: Timer {
            interval: 5000
            onTriggered: player.resting = false
        }
    }
    BackdropPlayer { slot: 0 }
    BackdropPlayer { slot: 1 }
}
