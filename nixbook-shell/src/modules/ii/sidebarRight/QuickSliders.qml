import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Slim rows: what it is, the slider, how much.
ColumnLayout {
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    spacing: 0

    Loader {
        Layout.fillWidth: true
        visible: active
        active: Config.options.sidebar.quickSliders.showBrightness
        sourceComponent: RowLayout {
            spacing: 10
            // Below the divider the slider dims with gamma, past what the
            // backlight can do.
            readonly property bool usingGamma: NightLightService.gamma !== 100
            RowIcon {
                text: parent.usingGamma ? "wb_twilight" : "brightness_medium"
            }
            QuickSlider {
                stopIndicatorValues: parent.usingGamma && root.brightnessMonitor?.brightness !== 0 ? [0.3 + root.brightnessMonitor?.brightness * 0.7] : []
                dividerValues: [0.3]
                value: !parent.usingGamma ? 0.3 + root.brightnessMonitor?.brightness * 0.7 : (NightLightService.gamma - NightLightService.gammaLowerLimit) / (100 - NightLightService.gammaLowerLimit) * 0.3
                tooltipContent: !parent.usingGamma ? `${Math.round(root.brightnessMonitor?.brightness * 100)}%` : `${Translation.tr("Gamma")} ${NightLightService.gamma}%`
                onMoved: {
                    if (value >= 0.3) {
                        // 0.3 - 1.0 brightness
                        root.brightnessMonitor.setBrightness((value - 0.3) / 0.7);
                        if (NightLightService.gamma !== 100) {
                            NightLightService.setGamma(100);
                        }
                    } else {
                        // 0 - 0.3 gamma
                        if (root.brightnessMonitor.brightness !== 0) {
                            root.brightnessMonitor.setBrightness(0);
                        }
                        NightLightService.setGamma((value / 0.3 * (100 - NightLightService.gammaLowerLimit) + NightLightService.gammaLowerLimit));
                    }
                }
            }
            RowValue {
                text: `${parent.usingGamma ? NightLightService.gamma : Math.round((root.brightnessMonitor?.brightness ?? 0) * 100)}%`
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        visible: active
        active: Config.options.sidebar.quickSliders.showVolume
        sourceComponent: RowLayout {
            spacing: 10
            RowIcon {
                text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            }
            QuickSlider {
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.sink?.audio)
                        Audio.sink.audio.volume = value
                }
            }
            RowValue {
                text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}%`
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        visible: active
        active: Config.options.sidebar.quickSliders.showMic
        sourceComponent: RowLayout {
            spacing: 10
            RowIcon {
                text: Audio.micMuted ? "mic_off" : "mic"
            }
            QuickSlider {
                value: Audio.source?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.source?.audio)
                        Audio.source.audio.volume = value
                }
            }
            RowValue {
                text: `${Math.round((Audio.source?.audio?.volume ?? 0) * 100)}%`
            }
        }
    }

    component QuickSlider: StyledSlider {
        Layout.fillWidth: true
        configuration: StyledSlider.Configuration.S
        handleHeight: 26
        topPadding: 2
        bottomPadding: 2
        stopIndicatorValues: []
    }

    component RowIcon: MaterialSymbol {
        Layout.leftMargin: 6
        iconSize: 20
        color: Appearance.colors.colOnLayer1
    }

    component RowValue: StyledText {
        Layout.preferredWidth: 38
        Layout.rightMargin: 4
        horizontalAlignment: Text.AlignRight
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
