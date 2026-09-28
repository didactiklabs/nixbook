pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Loading screen shown while the shell starts: covers every output and takes
 * the input (keyboard and pointer) while services/Preloader.qml builds and
 * pre-renders every popup, so nothing is opened half-ready and the first open
 * of anything is as fast as the next. Lifts with a short fade when the
 * preloader is done (everything built and drawn, see Preloader) — or after
 * Preloader.maxBootMs at the latest — and is then
 * unmapped for good. The session lock, if any, is drawn above it by the
 * compositor.
 */
Scope {
    id: root

    readonly property bool booting: Preloader.booting
    // Stay mapped through the fade-out.
    property bool shown: true
    onBootingChanged: if (!booting) fadeOut.restart()
    Timer {
        id: fadeOut
        interval: 320
        onTriggered: root.shown = false
    }

    // earlySplash.qml (the same loading screen, up while the shell itself
    // was still loading) leaves once this marker appears: by then this
    // splash has drawn its first frames underneath it.
    Timer {
        id: announceShown
        interval: 150
        onTriggered: Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$XDG_RUNTIME_DIR/nixbook-shell" && touch "$XDG_RUNTIME_DIR/nixbook-shell/boot-splash-shown"'])
    }

    // Destroyed (not just hidden) once the fade-out is over.
    LazyLoader {
        active: root.shown
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: splash
            required property var modelData
            screen: modelData
            visible: root.shown

            Component.onCompleted: announceShown.restart()

            WlrLayershell.namespace: "quickshell:bootSplash"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.booting ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            Item {
                id: content
                anchors.fill: parent
                opacity: root.booting ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }

                // Swallow every click and key while loading.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    hoverEnabled: true
                }
                focus: true
                Keys.onPressed: event => event.accepted = true

                BootSplashArt {
                    anchors.fill: parent
                    // Sweeping (like earlySplash.qml, which it takes over
                    // from) until the first stage is built.
                    progress: Preloader.progress > 0 ? Preloader.progress : -1
                    stageText: Preloader.currentStage !== "" ? Preloader.currentStage
                        : Preloader.bootPhase === "rendering" ? Translation.tr("Finishing up") : Translation.tr("Starting")
                    screenWidth: splash.screen?.width ?? 16
                    screenHeight: splash.screen?.height ?? 9
                }
            }
        }
    }
    }
}
