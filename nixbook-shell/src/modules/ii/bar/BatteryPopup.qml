import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

// The battery panel of the bar: charge, health and draw, then what can be
// chosen from it: the power profile (power-profiles-daemon) and, where the
// battery has one, the level charging stops at (Battery.chargeLimit).
StyledPopup {
    id: root

    // Content width: the two cards, and room for three labelled buttons.
    readonly property real panelWidth: 420
    readonly property var limitChoices: {
        const choices = [60, 80, 100];
        const current = Battery.chargeLimit;
        if (current > 0 && choices.indexOf(current) < 0) choices.push(current);
        return choices.sort((a, b) => a - b);
    }
    readonly property var profileChoices: {
        const choices = [
            { profile: PowerProfile.PowerSaver, icon: "energy_savings_leaf", name: Translation.tr("Power saver") },
            { profile: PowerProfile.Balanced, icon: "airwave", name: Translation.tr("Balanced") },
        ];
        if (PowerProfiles.hasPerformanceProfile)
            choices.push({ profile: PowerProfile.Performance, icon: "local_fire_department", name: Translation.tr("Performance") });
        return choices;
    }

    function formatTime(seconds) {
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        if (h > 0) return `${h}h, ${m}m`
        return `${m}m`
    }

    readonly property bool showTime: !(Battery.chargeState == 4
        || (Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty) <= 0
        || Battery.energyRate <= 0.01)

    ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            spacing: 7

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.ClamShell
                text: "battery_android_full"
                iconSize: Appearance.font.pixelSize.large
                implicitSize: 36
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -3

                StyledText {
                    text: Translation.tr("Battery")
                    font {
                        weight: Font.Medium
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                    text: {
                        if (Battery.chargeState == 4)
                            return Translation.tr("Fully charged")
                        if (Battery.heldAtLimit)
                            return Translation.tr("Plugged in · held at %1%").arg(Battery.chargeLimit)
                        if (Battery.isCharging)
                            return Translation.tr("Charging") + (root.showTime ? " · " + formatTime(Battery.timeToFull) : "")
                        return Translation.tr("Time to empty") + (root.showTime ? " · " + formatTime(Battery.timeToEmpty) : "")
                    }
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                Layout.rightMargin: 8
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                text: `${Math.round(Battery.percentage * 100)}`
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ResourceCard {
                label: Translation.tr("Health")
                iconText: "heart_check"
                iconShape: MaterialShape.Shape.Clover4Leaf
                value: Battery.health / 100
                sublabel: Battery.chargeCycles > 0
                    ? `${Battery.chargeCycles} ${Translation.tr("cycles")}`
                    : Translation.tr("N/A")
                sublabelColor: Appearance.colors.colOnSurfaceVariant
                cardWidth: (root.panelWidth - 6) / 2
            }

            ResourceCard {
                label: Battery.isCharging
                    ? Translation.tr("Charging")
                    : Translation.tr("Draw")
                iconText: "bolt"
                iconShape: MaterialShape.Shape.Pentagon
                value: Math.min(Battery.energyRate / 60, 1.0)
                sublabel: Battery.chargeState == 4
                    ? Translation.tr("Full")
                    : `${Battery.energyRate.toFixed(2)}W`
                sublabelColor: Appearance.colors.colOnSurfaceVariant
                cardWidth: (root.panelWidth - 6) / 2
            }
        }

        StyledPopupHeaderRow {
            Layout.leftMargin: 3
            icon: "speed"
            label: Translation.tr("Power profile")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: root.panelWidth
            spacing: 2
            uniformCellSizes: true

            Repeater {
                model: root.profileChoices
                delegate: SelectionGroupButton {
                    id: profileButton
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    horizontalPadding: 8
                    leftmost: index === 0
                    rightmost: index === root.profileChoices.length - 1
                    buttonIcon: modelData.icon
                    buttonText: modelData.name
                    toggled: PowerProfiles.profile === modelData.profile
                    onClicked: PowerProfiles.profile = profileButton.modelData.profile
                }
            }
        }

        StyledPopupHeaderRow {
            visible: Battery.chargeLimit > 0
            Layout.leftMargin: 3
            icon: "battery_saver"
            label: Translation.tr("Charge limit")
        }

        RowLayout {
            visible: Battery.chargeLimit > 0
            Layout.fillWidth: true
            Layout.preferredWidth: root.panelWidth
            spacing: 2
            uniformCellSizes: true

            Repeater {
                model: root.limitChoices
                delegate: SelectionGroupButton {
                    id: limitButton
                    required property int modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    leftmost: index === 0
                    rightmost: index === root.limitChoices.length - 1
                    buttonText: `${modelData}%`
                    toggled: Battery.chargeLimit === modelData
                    // Not `enabled: false` where it can't be changed: a
                    // disabled button drops its highlight, and the limit in
                    // force must still show.
                    opacity: Battery.chargeLimitSettable || toggled ? 1 : 0.45
                    onClicked: if (Battery.chargeLimitSettable) Battery.setChargeLimit(limitButton.modelData)
                }
            }
        }

        StyledText {
            visible: Battery.chargeLimit > 0
            Layout.fillWidth: true
            Layout.preferredWidth: root.panelWidth
            Layout.leftMargin: 3
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Battery.chargeLimitError !== "" ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
            text: Battery.chargeLimitError !== "" ? Battery.chargeLimitError
                : !Battery.chargeLimitSettable ? Translation.tr("Charging stops at %1%. It can't be changed from here.").arg(Battery.chargeLimit)
                : Battery.chargeLimit >= 100 ? Translation.tr("No limit: kept at 100% on the charger, a battery wears faster.")
                : Translation.tr("Charging stops at %1%: a battery kept below full lasts longer.").arg(Battery.chargeLimit)
        }
    }
}
