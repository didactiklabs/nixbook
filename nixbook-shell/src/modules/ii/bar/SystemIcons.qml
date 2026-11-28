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
    // Each icon is its own button (no shared pill: that made the whole
    // group one button opening the right panel): its own hover pill, a
    // click opening its dialog in the right panel, a right click switching
    // it (mute, Wi-Fi, Bluetooth). The notifications are the bell
    // (NotificationButton), which opens the panel.
    readonly property bool ownHoverFeedback: true

    // Hover popup for one icon: what it shows, and what a click does.
    component IconHint: StyledPopup {
        id: hint
        hoverTint: false // the icon's own pill lights up already
        property string title
        property string detail: ""
        property string action: ""
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
                visible: hint.action !== ""
                text: hint.action
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.italic: true
                color: Appearance.colors.colSubtext
            }
        }
    }
    // One icon, one button: hover pill, left/right click, wheel.
    component IconButton: Item {
        id: btn
        property alias text: icon.text
        property alias color: icon.color
        property alias hintTitle: iconHint.title
        property alias hintDetail: iconHint.detail
        property alias hintAction: iconHint.action
        // Its dialog is on screen in the right panel.
        property bool toggled: false
        signal leftClicked()
        signal rightClicked()
        signal scrolled(int delta)
        readonly property bool hovered: area.containsMouse
        implicitWidth: root.vertical ? 28 : icon.implicitWidth + 10
        implicitHeight: root.vertical ? icon.implicitHeight + 8 : 28

        Rectangle {
            id: pill
            anchors.fill: parent
            // Persona style: slanted like the BarGroup background around it.
            readonly property bool slanted: Persona.shapes && !root.vertical
            readonly property real skew: slanted ? Math.tan(-15 * Math.PI / 180) : 0
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, pill.skew, 0, -pill.skew * pill.height / 2,
                                     0, 1, 0, 0,
                                     0, 0, 1, 0,
                                     0, 0, 0, 1)
            }
            radius: slanted ? Persona.corner : Appearance.rounding.full
            color: root.isMaterial
                ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, btn.toggled ? 0.75 : btn.hovered ? 0.85 : 1)
                : btn.toggled
                    ? (btn.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                    : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, btn.hovered ? 0.6 : 1)
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        MaterialSymbol {
            id: icon
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.larger
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => mouse.button === Qt.RightButton ? btn.rightClicked() : btn.leftClicked()
            onWheel: wheel => {
                if (wheel.angleDelta.y !== 0) btn.scrolled(wheel.angleDelta.y > 0 ? 1 : -1);
            }
        }
        IconHint {
            id: iconHint
            hoverTarget: area
        }
    }

    implicitWidth: root.vertical ? 32 : flow.implicitWidth + 8
    implicitHeight: root.vertical ? flow.implicitHeight + 8 : 32

    Flow {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: 2

        IconButton {
            text: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"
            color: root.iconColor
            toggled: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightDialogShown === "audioOutput"
            hintTitle: (Audio.sink?.audio?.muted ?? false)
                ? Translation.tr("Volume muted")
                : Translation.tr("Volume %1%").arg(Math.round((Audio.sink?.audio?.volume ?? 0) * 100))
            hintDetail: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : ""
            hintAction: Translation.tr("Click: sound output · right click: mute · scroll: volume")
            onLeftClicked: GlobalStates.toggleSidebarRightDialog("audioOutput")
            onRightClicked: Audio.toggleMute()
            onScrolled: delta => delta > 0 ? Audio.incrementVolume() : Audio.decrementVolume()
        }
        Revealer {
            reveal: Audio.micMuted
            IconButton {
                text: "mic_off"
                color: root.iconColor
                toggled: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightDialogShown === "audioInput"
                hintTitle: Translation.tr("Microphone muted")
                hintDetail: Audio.source ? Audio.friendlyDeviceName(Audio.source) : ""
                hintAction: Translation.tr("Click: microphones · right click: unmute")
                onLeftClicked: GlobalStates.toggleSidebarRightDialog("audioInput")
                onRightClicked: Audio.toggleMicMute()
            }
        }
        KeyboardLayoutIndicator {
            color: root.iconColor
        }
        IconButton {
            text: Network.materialSymbol
            color: root.networkConnected ? root.activeColor : root.offColor
            toggled: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightDialogShown === "wifi"
            hintTitle: Network.ethernet ? Translation.tr("Ethernet connected")
                : root.networkConnected ? Translation.tr("Wi-Fi: %1").arg(Network.networkName)
                : Network.wifiEnabled ? Translation.tr("Wi-Fi on, not connected")
                : Translation.tr("Wi-Fi off")
            hintDetail: !root.networkConnected ? ""
                : [Network.ethernet ? "" : Translation.tr("%1% signal").arg(Network.active?.strength ?? 0),
                   Network.ipAddress].filter(s => s && s.length > 0).join(" · ")
            hintAction: Network.wifiEnabled
                ? Translation.tr("Click: Wi-Fi networks · right click: turn Wi-Fi off")
                : Translation.tr("Click: Wi-Fi networks · right click: turn Wi-Fi on")
            onLeftClicked: GlobalStates.toggleSidebarRightDialog("wifi")
            onRightClicked: Network.toggleWifi()
        }
        IconButton {
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            color: BluetoothStatus.connected ? root.activeColor : BluetoothStatus.enabled ? root.iconColor : root.offColor
            toggled: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightDialogShown === "bluetooth"
            readonly property var device: BluetoothStatus.primaryConnectedDevice
            hintTitle: BluetoothStatus.connected
                ? Translation.tr("Bluetooth: %1").arg(device?.name ?? "")
                    + (BluetoothStatus.activeDeviceCount > 1 ? ` +${BluetoothStatus.activeDeviceCount - 1}` : "")
                : BluetoothStatus.enabled ? Translation.tr("Bluetooth on, no device connected")
                : Translation.tr("Bluetooth off")
            hintDetail: (device?.batteryAvailable && Number.isFinite(Number(device?.battery)))
                ? Translation.tr("%1% battery").arg(Math.round(Number(device.battery) * 100)) : ""
            hintAction: BluetoothStatus.enabled
                ? Translation.tr("Click: Bluetooth devices · right click: turn Bluetooth off")
                : Translation.tr("Click: Bluetooth devices · right click: turn Bluetooth on")
            onLeftClicked: GlobalStates.toggleSidebarRightDialog("bluetooth")
            onRightClicked: BluetoothStatus.togglePower()
        }
    }
}
