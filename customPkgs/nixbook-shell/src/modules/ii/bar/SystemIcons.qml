import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool isDi: GlobalStates.dynamicIslandEnabled && Config.options.bar.dynamicIsland.rightWidget === "systemIcons" 

    readonly property color iconColor: root.isDi ? Appearance.colors.colOnLayer1 : (root.isMaterial ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)
    // Connected network / Bluetooth device: accent colour; switched off: dimmed.
    // (On the material pill everything stays on-primary.)
    readonly property color activeColor: root.isMaterial ? root.iconColor : Appearance.colors.colPrimary
    readonly property color offColor: root.isMaterial ? root.iconColor : Appearance.colors.colSubtext

    readonly property bool networkConnected: Network.ethernet || (Network.wifiEnabled && Network.wifiStatus === "connected")
    readonly property string clickHint: Translation.tr("Click to open quick settings")

    // Hover popup for one icon: what it shows, and that clicking opens the
    // right sidebar (quick settings).
    component IconHint: StyledPopup {
        id: hint
        property string title
        property string detail: ""
        property string action: root.clickHint
        ColumnLayout {
            spacing: 2
            StyledText {
                text: hint.title
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                visible: hint.detail !== ""
                text: hint.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: hint.action
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.italic: true
                color: Appearance.colors.colSubtext
            }
        }
    }
    // An icon with its own hover area (for the popup); click opens the sidebar.
    component HintedIcon: Item {
        id: hinted
        property alias text: icon.text
        property alias color: icon.color
        property alias hintTitle: iconHint.title
        property alias hintDetail: iconHint.detail
        implicitWidth: icon.implicitWidth
        implicitHeight: icon.implicitHeight
        MaterialSymbol {
            id: icon
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.larger
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        MouseArea {
            id: iconArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
        }
        IconHint {
            id: iconHint
            hoverTarget: iconArea
        }
    }

    implicitWidth: root.vertical ? 32 : flow.implicitWidth + 4
    implicitHeight: root.vertical ? flow.implicitHeight + 4 : 32

    MouseArea {
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }

    Flow {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: isMaterial ? 2 : root.vertical ? 6 : 10

        Revealer {
            reveal: true
            Item {
                id: volumeItem
                implicitWidth: root.vertical ? volumeColLayout.implicitWidth : volumeRowLayout.implicitWidth
                implicitHeight: root.vertical ? volumeColLayout.implicitHeight : volumeRowLayout.implicitHeight
                property bool hovered: false

                RowLayout {
                    id: volumeRowLayout
                    visible: !root.vertical
                    anchors.centerIn: parent
                    spacing: 3

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: {
                            if (Audio.sink?.audio?.muted) return "volume_off"
                            return "volume_up";
                        }
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.iconColor
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        visible: false
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.features: { "tnum": 1 }
                        color: root.iconColor
                        text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}`
                    }
                }

                ColumnLayout {
                    id: volumeColLayout
                    visible: root.vertical
                    anchors.centerIn: parent
                    spacing: 1

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (Audio.sink?.audio?.muted) return "volume_off";
                            return "volume_up";
                        }
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.iconColor
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: false
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: root.iconColor
                        text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}`
                    }
                }

                IconHint {
                    hoverTarget: volumeArea
                    title: (Audio.sink?.audio?.muted ?? false)
                        ? Translation.tr("Volume muted")
                        : Translation.tr("Volume %1%").arg(Math.round((Audio.sink?.audio?.volume ?? 0) * 100))
                    detail: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : ""
                    action: Translation.tr("Scroll to adjust · click to open quick settings")
                }
                MouseArea {
                    id: volumeArea
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    onEntered: volumeItem.hovered = true
                    onExited: volumeItem.hovered = false
                    onWheel: wheel => {
                        if (wheel.angleDelta.y > 0) {
                            Audio.incrementVolume();
                        } else if (wheel.angleDelta.y < 0) {
                            Audio.decrementVolume();
                        }
                    }
                    onPressed: mouse => {
                        GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                    }
                }
            }
        }
        Revealer {
            reveal: Audio.source?.audio?.muted ?? false
            HintedIcon {
                text: "mic_off"
                color: root.iconColor
                hintTitle: Translation.tr("Microphone muted")
                hintDetail: Audio.source ? Audio.friendlyDeviceName(Audio.source) : ""
            }
        }
        Loader {
            source: "HyprlandXkbIndicator.qml"
            onLoaded: item.color = root.iconColor
        }
        HintedIcon {
            text: Network.materialSymbol
            color: root.networkConnected ? root.activeColor : root.offColor
            hintTitle: Network.ethernet ? Translation.tr("Ethernet connected")
                : root.networkConnected ? Translation.tr("Wi-Fi: %1").arg(Network.networkName)
                : Network.wifiEnabled ? Translation.tr("Wi-Fi on, not connected")
                : Translation.tr("Wi-Fi off")
            hintDetail: !root.networkConnected ? ""
                : [Network.ethernet ? "" : Translation.tr("%1% signal").arg(Network.active?.strength ?? 0),
                   Network.ipAddress].filter(s => s && s.length > 0).join(" · ")
        }
        HintedIcon {
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            color: BluetoothStatus.connected ? root.activeColor : BluetoothStatus.enabled ? root.iconColor : root.offColor
            readonly property var device: BluetoothStatus.primaryConnectedDevice
            hintTitle: BluetoothStatus.connected
                ? Translation.tr("Bluetooth: %1").arg(device?.name ?? "")
                    + (BluetoothStatus.activeDeviceCount > 1 ? ` +${BluetoothStatus.activeDeviceCount - 1}` : "")
                : BluetoothStatus.enabled ? Translation.tr("Bluetooth on, no device connected")
                : Translation.tr("Bluetooth off")
            hintDetail: (device?.batteryAvailable && Number.isFinite(Number(device?.battery)))
                ? Translation.tr("%1% battery").arg(Math.round(Number(device.battery) * 100)) : ""
        }
        Loader {
            id: notifLoader
            active: Notifications.silent || Notifications.unread > 0
            visible: active
            width: active ? item?.implicitWidth ?? 0 : 0
            height: active ? item?.implicitHeight ?? 0 : 0
            source: "NotificationUnreadCount.qml"
            MouseArea {
                id: notifArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
            }
            IconHint {
                hoverTarget: notifArea
                title: Notifications.silent ? Translation.tr("Do not disturb")
                    : Translation.tr("%1 unread notification(s)").arg(Notifications.unread)
                action: Translation.tr("Click to open the notification centre")
            }
        }
    }
}