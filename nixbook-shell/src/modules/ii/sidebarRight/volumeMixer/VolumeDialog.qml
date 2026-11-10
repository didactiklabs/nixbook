pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

WindowDialog {
    id: root
    property bool isSink: true
    backgroundHeight: 600

    WindowDialogTitle {
        text: root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    VolumeDialogContent {
        isSink: root.isSink
    }

    // The input: the computer's sound kept out of it (services/EchoCancel.qml).
    ConfigSwitch {
        id: echoSwitch
        visible: !root.isSink && EchoCancel.available
        Layout.fillWidth: true
        buttonIcon: EchoCancel.active ? "noise_aware" : "noise_control_off"
        text: Translation.tr("Echo cancellation (keep the computer's sound out of the microphone)")
        checked: EchoCancel.active
        enabled: !EchoCancel.busy
        onCheckedChanged: if (checked !== EchoCancel.active) EchoCancel.set(checked)
        // What it really is (it can fail to start): the switch follows.
        Connections {
            target: EchoCancel
            function onActiveChanged() {
                echoSwitch.checked = EchoCancel.active
            }
            function onBusyChanged() {
                if (!EchoCancel.busy) echoSwitch.checked = EchoCancel.active
            }
        }
        StyledToolTip {
            text: Translation.tr("For calls: music, a film or the other side of the call playing on this computer isn't heard through your microphone; also reduces background noise. Uses the \"Echo-cancelled microphone\" while on.")
        }
    }

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                AppLaunch.spawnShell(Config.options.apps.volumeMixer);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
