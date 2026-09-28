//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
// The loading screen, before the shell is up: its own small Quickshell
// instance (`nixbook-shell splash`, the nixbook-shell-splash user service),
// started with the session. It draws what the shell's BootSplash draws
// (modules/ii/splash/BootSplashArt.qml), with an indeterminate bar, from the
// moment the compositor is up until BootSplash has taken over — no black
// screen or half-drawn desktop between the login screen and the shell — and
// then quits. It only reads the settings (never writes them) and loads none of
// the shell's services.
import "modules/common"
import "services"
import "modules/ii/splash"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string marker: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-shell/boot-splash-shown`
    // Never outlive a shell that fails to start.
    readonly property int maxMs: 20000
    property bool leaving: false

    Component.onCompleted: {
        // The shell owns config.json: never write it from here.
        Config.blockWrites = true;
        MaterialThemeLoader.reapplyTheme();
    }

    function leave() {
        if (root.leaving)
            return;
        root.leaving = true;
        quitTimer.restart();
    }

    // BootSplash announces itself with the marker (removed by the service
    // before this starts). Polled: FileView can't watch a file that doesn't
    // exist yet.
    Process {
        id: markerCheck
        command: ["test", "-e", root.marker]
        onExited: code => {
            if (code === 0)
                root.leave();
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: !root.leaving
        onTriggered: markerCheck.running = true
    }
    Timer {
        interval: root.maxMs
        running: true
        onTriggered: root.leave()
    }
    // Fade out, then quit: BootSplash (identical) is below or above by now.
    Timer {
        id: quitTimer
        interval: 250
        onTriggered: Qt.quit()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: splash
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:earlySplash"
            WlrLayershell.layer: WlrLayer.Overlay
            // BootSplash takes the keyboard; don't fight it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            BootSplashArt {
                anchors.fill: parent
                opacity: root.leaving ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                progress: -1
                stageText: Translation.tr("Starting")
                screenWidth: splash.screen?.width ?? 16
                screenHeight: splash.screen?.height ?? 9
            }
        }
    }
}
