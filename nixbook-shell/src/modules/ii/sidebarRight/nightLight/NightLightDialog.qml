import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland

WindowDialog {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    backgroundHeight: 580

    WindowDialogTitle {
        text: Translation.tr("Eye protection")
    }
    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }
    
    WindowDialogSectionHeader {
        text: Translation.tr("Night Light")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh  
        ConfigSwitch {
            Layout.topMargin: -2
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "check"
            text: Translation.tr("Enable now")
            checked: NightLightService.temperatureActive
            onCheckedChanged: {
                NightLightService.toggleTemperature(checked)
            }
        }

        ConfigSwitch {
            Layout.topMargin: -2
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "night_sight_auto"
            text: Translation.tr("Automatic")
            checked: Config.options.light.night.automatic
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }

        WindowDialogSlider {
            Layout.topMargin: -2    
            text: Translation.tr("")
            from: 6500
            to: 1200
            stopIndicatorValues: [5000, to]
            value: Config.options.light.night.colorTemperature
            onMoved: Config.options.light.night.colorTemperature = value
            tooltipContent: `${Math.round(value)}K`
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Brightness")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh  

        WindowDialogSlider {
            Layout.topMargin: -2
            value: root.brightnessMonitor.brightness
            onMoved: root.brightnessMonitor.setBrightness(value)
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Gamma")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh
        WindowDialogSlider {
            from: NightLightService.gammaLowerLimit / 100
            value: NightLightService.gamma / 100
            onMoved: NightLightService.setGamma(value * 100)
            tooltipContent: `${Math.round(value * 100)}%`
        }
    }
    
    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
