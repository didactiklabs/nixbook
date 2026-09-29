import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell.Io

QuickToggleButton {
    id: nightLightButton
    toggled: NightLightService.temperatureActive
    buttonIcon: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
    onClicked: {
        NightLightService.toggleTemperature()
    }

    altAction: () => {
        Config.options.light.night.automatic = !Config.options.light.night.automatic
    }

    Component.onCompleted: {
        NightLightService.fetchState()
    }
    
    StyledToolTip {
        text: Translation.tr("Night Light | Right-click to toggle Auto mode")
    }
}
