import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property var device
    property bool expanded: false
    readonly property bool busy: BluetoothStatus.busyDevicePath === (root.device?.dbusPath ?? "-")
    readonly property bool failed: BluetoothStatus.failedDevicePath === (root.device?.dbusPath ?? "-")
    pointingHandCursor: !expanded

    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded
    
    component ActionButton: DialogButton {
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnPrimary
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            // Name
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.device?.name || Translation.tr("Unknown device")
                    textFormat: Text.PlainText
                }
                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        if (root.busy) {
                            switch (BluetoothStatus.busyAction) {
                            case "disconnect": return Translation.tr("Disconnecting...");
                            case "pair": return Translation.tr("Pairing...");
                            default: return Translation.tr("Connecting...");
                            }
                        }
                        if (root.failed)
                            return BluetoothStatus.failedMessage || Translation.tr("Failed");
                        // Connected without pairing happens too (BLE devices, controllers)
                        const connected = BluetoothStatus.isConnected(root.device);
                        if (!connected && !root.device?.paired) return "";
                        let statusText = connected ? Translation.tr("Connected") : Translation.tr("Paired");
                        if (!root.device?.batteryAvailable) return statusText;
                        statusText += ` • ${Math.round(root.device?.battery * 100)}%`;
                        return statusText;
                    }
                }
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.topMargin: 8
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                readonly property bool p: root.device?.paired ?? false
                enabled: !BluetoothStatus.busy
                colBackground: p ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: p ? Appearance.colors.colErrorHover : ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colRipple: p ? Appearance.colors.colErrorActive : Appearance.colors.colLayer3Hover
                colText: p ? Appearance.colors.colOnError : Appearance.colors.colPrimary

                buttonText: p ? Translation.tr("Forget") : Translation.tr("Always connect")
                onClicked: {
                    if (p) BluetoothStatus.forgetDevice(root.device);
                    else BluetoothStatus.pairDevice(root.device);
                }
            }
            ActionButton {
                enabled: !BluetoothStatus.busy
                buttonText: BluetoothStatus.isConnected(root.device) ? Translation.tr("Disconnect") : Translation.tr("Connect")

                onClicked: {
                    if (BluetoothStatus.isConnected(root.device))
                        BluetoothStatus.disconnectDevice(root.device);
                    else
                        BluetoothStatus.connectDevice(root.device);
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
