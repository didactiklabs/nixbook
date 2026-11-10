import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Echo cancellation (services/EchoCancel.qml): the computer's sound kept out
// of the microphone during calls.
QuickToggleModel {
    name: Translation.tr("Echo cancellation")
    statusText: EchoCancel.busy ? Translation.tr("…") : toggled ? Translation.tr("On") : Translation.tr("Off")
    toggled: EchoCancel.active
    available: EchoCancel.available
    icon: toggled ? "noise_aware" : "noise_control_off"
    mainAction: () => {
        EchoCancel.toggle()
    }
    hasMenu: true

    tooltipText: Translation.tr("Echo cancellation: keeps the computer's own sound (music, a film, the other side of a call) out of your microphone | Right-click for the input devices")
}
