pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Variants {
    id: root
    model: Quickshell.screens

    // Each screen's desktop window. A surface stacks over those of its layer
    // mapped before it, so when new video players appear (Bottom layer, like
    // this window) the desktop is moved back above them by a new window — the
    // old one stays until the new one is drawn, then goes: nothing disappears
    // on the way (re-mapping this window instead left the screen without its
    // widgets for a few frames). The players are held transparent meanwhile
    // (Wallpapers.holdPlayers).
    Scope {
        id: screenScope
        required property var modelData
        readonly property int restack: GlobalStates.backgroundRestack
        property int firstGeneration: -1
        ListModel { id: generations }
        Component.onCompleted: {
            screenScope.firstGeneration = screenScope.restack;
            generations.append({ gen: screenScope.restack });
        }
        onRestackChanged: generations.append({ gen: screenScope.restack })
        // A newer window has drawn everything: it shows, the older ones hide
        // (a frame later, so the desktop is never empty in between) and go.
        signal tookOver(int gen)
        function takeOver(gen) {
            screenScope.tookOver(gen);
            Wallpapers.backgroundRestacked(screenScope.modelData.name, gen);
            dropOld.gen = Math.max(dropOld.gen, gen);
            dropOld.restart();
        }
        Timer {
            id: dropOld
            property int gen: -1
            interval: 300
            onTriggered: {
                for (let i = generations.count - 1; i >= 0; i--)
                    if (generations.get(i).gen < dropOld.gen) generations.remove(i);
            }
        }

        Instantiator {
            model: generations
            delegate: PanelWindow {
                id: bgRoot

                required property int gen
                readonly property var modelData: screenScope.modelData
                // Made to replace another window (see above): drawn invisibly until
                // everything in it is ready, then takes over.
                readonly property bool replacing: bgRoot.gen !== screenScope.firstGeneration
                property bool shownNow: !bgRoot.replacing
                property bool retired: false
                Connections {
                    target: screenScope
                    function onTookOver(gen) {
                        if (gen === bgRoot.gen) {
                            bgRoot.shownNow = true;
                        } else if (gen > bgRoot.gen) {
                            retireTimer.restart();
                        }
                    }
                }
                Timer {
                    id: retireTimer
                    interval: 40
                    onTriggered: bgRoot.retired = true
                }
                Timer {
                    id: settleTimer
                    interval: 250
                    onTriggered: if (!bgRoot.shownNow) screenScope.takeOver(bgRoot.gen)
                }
                // At most: a wallpaper that never loads.
                Timer {
                    running: bgRoot.replacing
                    interval: 2500
                    onTriggered: if (!bgRoot.shownNow) screenScope.takeOver(bgRoot.gen)
                }
                // The image shown (a video's thumbnail), never the video itself.
                property string currentWallpaperSource: bgRoot.wallpaperPath
                property string previousWallpaperSource: bgRoot.wallpaperPath
                property bool videoRevealed: false
                // The playing video has been on screen since the last change: the
                // next transition starts from the frame it was paused on
                // (Wallpapers.frozenFrame), not from its first frame.
                property bool liveShown: false
                onShowVideoChanged: if (bgRoot.showVideo) bgRoot.liveShown = true
                // The video itself shows (the window clear over mpvpaper) only once
                // it plays: until then — and for a preview or the lock wall — its
                // still frame is shown like any image (Wallpapers.playingPath).
                readonly property bool showVideo: bgRoot.videoRevealed && bgRoot.wallpaperIsVideo
                    && Wallpapers.playingPath === CF.FileUtils.trimFileProtocol(bgRoot.effectiveWallpaperPath)

                readonly property real splitFraction: {
                    switch (Config.options.background.splitRatio) {
                        case "25": return 0.28
                        case "50": return 0.54
                        default:   return 1.0
                    }
                }
                readonly property bool userBlurActive: Config.options.background.showBlur && !bgRoot.wallpaperIsVideo
                readonly property bool blurFullScreen: bgRoot.splitFraction >= 1.0

                property var shaderList: ["circlePit", "circleSelect", "magic", "Doom", "Peel", "transition", "pixelate", "stripes", "crt", "dissolve", "glitch", "ripple", "shatter"]
                property string currentShader: "pixelate"
                property string wallpaperAnimation: Config.options.background.wallpaperAnimation ?? "random"

                visible: true

                property string effectiveWallpaperPath: {
                    if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                        return Config.options.background.lockWall;
                    return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
                }

                property bool wallpaperIsVideo: Wallpapers.isVideo(bgRoot.effectiveWallpaperPath)
                // A video's own still frame (a previewed one's too, not the playing one's).
                property string wallpaperPath: wallpaperIsVideo ? Wallpapers.posterFor(bgRoot.effectiveWallpaperPath) : bgRoot.effectiveWallpaperPath
                property bool wallpaperSafetyTriggered: {
                    const enabled = Config.options.workSafety.enable.wallpaper;
                    const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
                    const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
                    return enabled && sensitiveWallpaper && sensitiveNetwork;
                }

                property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
                property color dominantColor: Appearance.colors.colPrimary
                property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
                property color colText: {
                    if (wallpaperSafetyTriggered)
                        return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
                    return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
                }
                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                // Decode wallpapers at screen resolution. Uploading a 5K+ image and its mipmaps to the GPU
                // stalls the render thread, and the GUI thread with it while an animation is running.
                readonly property size wallpaperSourceSize: Wallpapers.pixelSize(modelData.name, modelData.width, modelData.height,
                    modelData.devicePixelRatio)

                property real transitionProgress: 1.0
                property bool transitionPending: false
                // Reported to GlobalStates so palette updates wait for the transition.
                readonly property bool transitionBusy: transitionPending || transitionAnim.running
                onTransitionBusyChanged: GlobalStates.wallpaperTransitionsBusy += transitionBusy ? 1 : -1
                Component.onDestruction: if (transitionBusy) GlobalStates.wallpaperTransitionsBusy -= 1

                screen: modelData
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
                WlrLayershell.namespace: "quickshell:background"
                // niri picks the keyboard target on the press itself: requesting
                // OnDemand only once a widget was pressed was too late for that
                // click (typing into a new note needed a second click). Hovering a
                // widget requests it in advance; hovering alone never takes focus.
                WlrLayershell.keyboardFocus: (GlobalStates.desktopWidgetKeyboardFocus || GlobalStates.desktopWidgetsHovered > 0)
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: {
                    if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                        return "transparent";
                    return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Component.onCompleted: {
                    // previousWallpaper follows once `wallpaper` has decoded it (see
                    // its onStatusChanged): set now, it decoded on the GUI thread.
                    wallpaper.source = bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                    bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
                    bgRoot.previousWallpaperSource = ""
                    bgRoot.transitionProgress = 1.0
                    if (bgRoot.wallpaperAnimation !== "") {
                        bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                            ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                            : bgRoot.wallpaperAnimation
                    }
                    bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                    bgRoot.liveShown = bgRoot.showVideo
                    if (bgRoot.replacing && String(wallpaper.source) === "") settleTimer.restart()
                }

                onWallpaperPathChanged: {
                    if (!bgRoot.shownNow) {
                        // A replacing window not shown yet (its bindings settling):
                        // the picture as it is, no transition.
                        wallpaper.source = bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                        bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
                        bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                        return
                    }
                    const frozen = bgRoot.liveShown ? Wallpapers.frozenFrame(bgRoot.modelData.name) : ""
                    bgRoot.liveShown = false
                    // `wallpaper` would show its previous image (retainWhileLoading)
                    // over that frame while the new one decodes: dropped first.
                    if (frozen !== "") wallpaper.source = ""
                    bgRoot.videoRevealed = false
                    if (wallpaperSafetyTriggered) {
                        bgRoot.transitionPending = false
                        previousWallpaper.source = ""
                        wallpaper.source = ""
                        bgRoot.transitionProgress = 1.0
                        return
                    }
                    if (bgRoot.wallpaperAnimation === "" || GlobalStates.startupLockPending) {
                        bgRoot.transitionPending = false
                        // previousWallpaper keeps the old one showing until this has
                        // decoded, then follows it from the cache (onStatusChanged).
                        if (frozen !== "") previousWallpaper.source = frozen
                        wallpaper.source = wallpaperPath
                        bgRoot.currentWallpaperSource = wallpaperPath
                        if (!bgRoot.wallpaperIsVideo) return
                        bgRoot.videoRevealed = true
                        return
                    }

                    previousWallpaper.source = frozen !== "" ? frozen : bgRoot.currentWallpaperSource
                    bgRoot.currentWallpaperSource = wallpaperPath
                    if (bgRoot.wallpaperAnimation === "random") {
                        bgRoot.currentShader = bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    } else {
                        bgRoot.currentShader = bgRoot.wallpaperAnimation
                    }
                    bgRoot.transitionPending = true
                    wallpaper.source = wallpaperPath
                    if (wallpaper.status === Image.Ready) {
                        bgRoot.transitionPending = false
                        bgRoot.transitionProgress = 0.0
                        transitionAnim.restart()
                    }
                }

                NumberAnimation {
                    id: transitionAnim
                    target: bgRoot
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: 1000
                    easing.type: Easing.InOutQuad
                    onFinished: {
                        previousWallpaper.source = bgRoot.currentWallpaperSource
                        bgRoot.previousWallpaperSource = ""
                        bgRoot.transitionProgress = 1.0
                        bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                    }
                }

                Timer {
                    id: wallpaperChangeTimer
                    interval: Config.options.wallpaperSelector.changeInterval
                    running: Config.options.wallpaperSelector.changeInterval > 0
                    repeat: true
                    onTriggered: {
                        if (Wallpapers.folderModel.count > 0) {
                            Wallpapers.randomFromCurrentFolder()
                        }
                    }
                }

                Connections {
                    target: Config
                    function onReadyChanged() {
                        if (!Config.ready) return
                        centeredWallpaper.setCenteredProgress(GlobalStates.screenLocked ? 0 : (centeredWallpaper.centeredOnlyWhenLocked ? 1 : 0))
                        centeredWallpaper.centeredAnimationReady = true
                    }
                }

                Connections {
                    target: GlobalStates
                    function onScreenLockedChanged() {
                        if (!GlobalStates.screenLocked) {
                            bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    // A replacing window draws at an invisible opacity until it takes
                    // over (so its textures are ready), and the replaced one is cleared
                    // at once: no fade between two copies of the same picture.
                    opacity: bgRoot.retired ? 0
                        : !bgRoot.shownNow ? 0.004
                        : GlobalStates.startupLockPending ? 0 : 1

                    Behavior on opacity {
                        enabled: !bgRoot.replacing && !bgRoot.retired
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    Image {
                        id: previousWallpaper
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        // Same size as `wallpaper` so this synchronous Image reuses its
                        // cached pixmap: it is given a source `wallpaper` has already
                        // decoded (a cache hit, never a GUI-thread decode) — but for a
                        // playing video's paused frame (Wallpapers.frozenFrame), decoded
                        // here once, before the transition starts.
                        sourceSize: bgRoot.wallpaperSourceSize
                        cache: true
                        // No mipmaps: decoded at screen size and drawn 1:1 into its
                        // layer, they were never sampled, but were built (and uploaded,
                        // +1/3) on the transition's first frame.
                        smooth: true
                        // Its layer (the cropped image the transition shader samples)
                        // only exists for a transition: otherwise a full-screen
                        // buffer in (shared) GPU memory and an extra pass per repaint.
                        layer.enabled: bgRoot.transitionPending || transitionEffect.visible
                        // Drawn only where `wallpaper` doesn't cover it (loading,
                        // fading) and during a transition (a hidden item's layer isn't
                        // redrawn): not underneath on every repaint.
                        visible: !bgRoot.showVideo && (transitionEffect.visible || bgRoot.transitionPending
                            || !(wallpaper.visible && wallpaper.opacity >= 1 && wallpaper.status === Image.Ready))
                        opacity: bgRoot.showVideo ? 0 : 1
                    }

                    StyledImage {
                        id: wallpaper
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: bgRoot.wallpaperSourceSize
                        cache: true
                        smooth: true
                        asynchronous: true
                        // Its layer is also what the transition shader and the blurs
                        // sample: the raw texture of a video's still frame (decoded to
                        // cover the screen, wider than a 16:10 one) came out squeezed,
                        // and jumped back to its real width once the video took over.
                        layer.enabled: !bgRoot.showVideo || blurLoader.active
                        // Not hidden during a transition (the shader's output covers it):
                        // the layer of a hidden item isn't redrawn, and the transition
                        // went to the previous picture.
                        visible: !blurLoader.active && !bgRoot.showVideo
                            && !centeredWallpaper.centeredHidesFullWallpaper
                        opacity: centeredWallpaper.centeredFullWallpaperOpacity()
                        onStatusChanged: {
                            if (status === Image.Ready && !bgRoot.shownNow) settleTimer.restart()
                            if (status === Image.Ready && bgRoot.transitionPending) {
                                bgRoot.transitionPending = false
                                bgRoot.transitionProgress = 0.0
                                transitionAnim.restart()
                            } else if (status === Image.Ready && !transitionAnim.running
                                    && String(previousWallpaper.source) !== String(source)) {
                                previousWallpaper.source = source
                            }
                        }
                    }

                    ShaderEffect {
                        id: transitionEffect
                        anchors.fill: parent
                        visible: !blurLoader.active && bgRoot.wallpaperAnimation !== "" && !centeredWallpaper.centeredShapeActive && !bgRoot.showVideo
                            && bgRoot.transitionProgress < 1.0

                        property var fromImage: previousWallpaper
                        property var toImage: wallpaper
                        property var source1: previousWallpaper
                        property var source2: wallpaper
                        property real time: 0.0
                        property real progress: bgRoot.transitionProgress
                        property real aspectX: width / height
                        property real aspectY: 1.0
                        property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                        property vector2d origin: Qt.vector2d(0.5, 0.5)

                        fragmentShader: bgRoot.wallpaperAnimation !== ""
                            ? Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
                            : ""

                        // Advanced by the real frame time, in step with the display
                        // (a 16 ms Timer drifted against the refresh rate: stutter).
                        FrameAnimation {
                            running: transitionEffect.visible
                            onTriggered: transitionEffect.time += frameTime
                        }
                        onVisibleChanged: if (!visible) transitionEffect.time = 0.0
                    }

                    Loader {
                        id: blurLoader
                        // The blur is invisible while the centered wallpaper is active
                        // (opaque shape + solid background cover it), so skip it to
                        // save the expensive multi-sample blur pass on lock/unlock.
                        active: Config.options.lock.blur.enable && !centeredWallpaper.centeredWallpaperEnabled
                            && (GlobalStates.screenLocked || scaleAnim.running)
                            && !bgRoot.userBlurActive
                        anchors.fill: parent
                        scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                        Behavior on scale {
                            NumberAnimation {
                                id: scaleAnim
                                duration: 400
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                            }
                        }
                        sourceComponent: GaussianBlur {
                            source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                            radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                            samples: Config.options.lock.blur.size 
                            Rectangle {
                                opacity: GlobalStates.screenLocked ? 1 : 0
                                anchors.fill: parent
                                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                            }
                        }
                    }

                    Loader {
                        id: fastBlurLoader
                        active: bgRoot.userBlurActive
                            && (!GlobalStates.screenLocked || !centeredWallpaper.centeredWallpaperEnabled || bgRoot.blurFullScreen)
                        anchors.fill: parent
                
                        sourceComponent: Item {
                            id: blurRoot
                            anchors.fill: parent

                            readonly property real fadeWidth: 140
                            readonly property real blurRadius: 48
                            readonly property bool alignRight: Config.options.background.splitSide === "right"
                            property real coreWidth: bgRoot.blurFullScreen ? blurRoot.width : blurRoot.width * bgRoot.splitFraction

                            Behavior on coreWidth {
                                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                            }

                            FastBlur {
                                id: blurLayer
                                anchors.fill: parent
                                source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                                radius: Config.options.background.blurRadius

                                layer.enabled: !bgRoot.blurFullScreen
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: blurLayer.width
                                        height: blurLayer.height
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: blurRoot.alignRight ? 1 - (blurRoot.coreWidth / blurRoot.width) : Math.max(0, (blurRoot.coreWidth - blurRoot.fadeWidth) / blurRoot.width); color: blurRoot.alignRight ? "transparent" : "white" }
                                            GradientStop { position: blurRoot.alignRight ? Math.min(1, 1 - (blurRoot.coreWidth - blurRoot.fadeWidth) / blurRoot.width) : Math.min(1, blurRoot.coreWidth / blurRoot.width); color: blurRoot.alignRight ? "white" : "transparent" }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    /* Centered Wallpaper */
                    CenteredWallpaper {
                        id: centeredWallpaper
                        anchors.fill: parent
                        screen: bgRoot.screen
                        wallpaperPath: bgRoot.wallpaperPath
                        wallpaperIsVideo: bgRoot.wallpaperIsVideo
                    }

                    /* Wallpaper Drop Area */
                    WallpaperDropArea {
                        anchors.fill: parent
                    }

                    /* Widgets Loader */
                    WidgetCanvas {
                        id: widgetCanvas
                        anchors.fill: parent

                        transitions: Transition {
                            PropertyAnimation {
                                properties: "width,height"
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Appearance.animation.elementMove.type
                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                            }
                            AnchorAnimation {
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Appearance.animation.elementMove.type
                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                            }
                        }

                        MouseArea {
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            id: centeredDesktopThumpArea
                            width: Math.max(1, centeredWallpaper.centeredShapeSize())
                            height: width
                            anchors.centerIn: parent
                            visible: centeredWallpaper.centeredWallpaperEnabled
                                && !GlobalStates.screenLocked
                                && (centeredWallpaper.centeredProgress < 1 || centeredWallpaper.centeredAnimating)
                            acceptedButtons: Qt.LeftButton
                            onClicked: GlobalStates.centeredWallpaperThumpRequested()
                        }

                        WidgetsLoader {
                            instant: !bgRoot.shownNow
                            screen: bgRoot.screen
                            wallpaperItem: wallpaper
                            wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                        }
                    }

                    /* Desktop menu */
                    MouseArea {
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        id: desktopRightClickArea
                        anchors.fill: parent
                        z: -2
                        acceptedButtons: Qt.RightButton
                        onClicked: (mouse) => {
                            GlobalStates.desktopMenuScreen = bgRoot.screen
                            GlobalStates.desktopMenuX = mouse.x
                            GlobalStates.desktopMenuY = mouse.y
                            GlobalStates.desktopMenuOpen = true
                        }
                    }
                }
            }
        }
    }
}
