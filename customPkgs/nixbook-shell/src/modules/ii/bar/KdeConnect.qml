pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell

// KDE Connect ("Phone Connect", ported from DankMaterialShell's DankKDEConnect
// plugin). Bar: device icon + battery of the connected phone. Left click opens
// a panel with every paired device (battery, signal) and its actions: find
// (ring), ping, send clipboard, send a file, browse files, messages, photo,
// plus pairing requests. Right click refreshes. State: services/KdeConnect.qml.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical

    readonly property var device: KdeConnect.primaryDevice
    readonly property bool connected: device?.reachable ?? false
    readonly property int battery: device?.battery ?? -1
    readonly property bool lowBattery: connected && battery >= 0 && battery <= 15 && !(device?.charging ?? false)

    property bool panelOpen: false
    readonly property bool cursorNear: containsMouse || panelHover.hovered

    readonly property color fg: !KdeConnect.available || !connected ? Appearance.colors.colOnLayer2
        : lowBattery ? Appearance.m3colors.m3error
        : Appearance.colors.colOnLayer1

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true

    onCursorNearChanged: {
        if (cursorNear) closeTimer.stop();
        else if (panelOpen) closeTimer.start();
    }
    Timer {
        id: closeTimer
        interval: 500
        onTriggered: if (!root.cursorNear) root.panelOpen = false
    }

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton) {
            root.panelOpen = !root.panelOpen;
            if (root.panelOpen) KdeConnect.refresh();
        } else {
            KdeConnect.refresh();
        }
    }

    Component.onCompleted: KdeConnect.load()

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: 4
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: !KdeConnect.available ? "phonelink_off" : KdeConnect.deviceIcon(root.device)
                iconSize: Appearance.font.pixelSize.normal
                fill: root.connected ? 1 : 0
                color: root.fg
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.connected && root.battery >= 0
                text: root.battery + "%"
                color: root.fg
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.connected && (root.device?.charging ?? false)
                text: "bolt"
                iconSize: Appearance.font.pixelSize.small
                color: root.fg
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 2
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: !KdeConnect.available ? "phonelink_off" : KdeConnect.deviceIcon(root.device)
                iconSize: Appearance.font.pixelSize.normal
                fill: root.connected ? 1 : 0
                color: root.fg
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.connected && root.battery >= 0
                text: root.battery
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.fg
            }
        }
    }

    component ActionButton: RippleButtonWithIcon {
        Layout.fillWidth: true
        buttonRadius: Appearance.rounding.normal
    }

    StyledPopup {
        hoverTarget: root
        active: root.panelOpen

        ColumnLayout {
            spacing: 10

            HoverHandler {
                id: panelHover
            }

            // A ColumnLayout recomputes its own implicitWidth from its children
            // (an explicit `implicitWidth` on it gets overwritten), so the panel
            // width is set here, via the header's minimum width.
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 400
                spacing: 6
                MaterialSymbol {
                    text: "devices"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Phone Connect")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    visible: KdeConnect.selfName !== ""
                    text: KdeConnect.selfName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !KdeConnect.available || (KdeConnect.loaded && KdeConnect.devices.length === 0)
                wrapMode: Text.Wrap
                text: !KdeConnect.available
                    ? Translation.tr("KDE Connect is not running (kdeconnectd).")
                    : Translation.tr("No devices. Install KDE Connect on your phone and pair it on the same network.")
                color: Appearance.colors.colOnLayer2
            }

            // Incoming pairing requests
            Repeater {
                model: KdeConnect.pairRequests
                delegate: Rectangle {
                    id: req
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: reqCol.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSecondaryContainer
                    ColumnLayout {
                        id: reqCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("%1 wants to pair").arg(req.modelData.name)
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            visible: req.modelData.verificationKey !== ""
                            text: Translation.tr("Verification key: %1").arg(req.modelData.verificationKey)
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ActionButton { materialIcon: "check"; mainText: Translation.tr("Accept"); onClicked: KdeConnect.acceptPairing(req.modelData.id) }
                            ActionButton { materialIcon: "close"; mainText: Translation.tr("Reject"); onClicked: KdeConnect.rejectPairing(req.modelData.id) }
                        }
                    }
                }
            }

            // Devices
            Repeater {
                model: KdeConnect.devices.filter(d => d.paired || (d.reachable && !d.pairRequested))
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool online: modelData.reachable && modelData.paired
                    Layout.fillWidth: true
                    implicitHeight: cardCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            MaterialShapeWrappedMaterialSymbol {
                                text: KdeConnect.deviceIcon(card.modelData)
                                iconSize: Appearance.font.pixelSize.huge
                                wrappedShape: MaterialShape.Shape.Cookie7Sided
                                color: card.online ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                                colSymbol: card.online ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: card.modelData.name
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    text: !card.modelData.paired ? Translation.tr("Not paired")
                                        : card.modelData.reachable ? Translation.tr("Connected") : Translation.tr("Disconnected")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: card.online ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                            }
                            // Battery + signal
                            ColumnLayout {
                                visible: card.online
                                spacing: 2
                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    visible: card.modelData.battery >= 0
                                    spacing: 2
                                    MaterialSymbol {
                                        text: KdeConnect.batteryIcon(card.modelData)
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: card.modelData.battery + "%"
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    visible: card.modelData.signal >= 0
                                    spacing: 2
                                    MaterialSymbol {
                                        text: KdeConnect.signalIcon(card.modelData)
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: card.modelData.network
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            visible: card.online
                            columns: 2
                            rowSpacing: 6
                            columnSpacing: 6
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "findmyphone")
                                materialIcon: "ring_volume"
                                mainText: Translation.tr("Find")
                                onClicked: KdeConnect.ring(card.modelData.id)
                            }
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "ping")
                                materialIcon: "notifications_active"
                                mainText: Translation.tr("Ping")
                                onClicked: KdeConnect.ping(card.modelData.id)
                            }
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "clipboard")
                                materialIcon: "content_paste_go"
                                mainText: Translation.tr("Clipboard")
                                onClicked: KdeConnect.sendClipboard(card.modelData.id)
                            }
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "share")
                                materialIcon: "upload_file"
                                mainText: Translation.tr("Send file")
                                onClicked: {
                                    root.panelOpen = false;
                                    KdeConnect.pickAndShareFile(card.modelData.id);
                                }
                            }
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "sftp")
                                materialIcon: "folder_open"
                                mainText: Translation.tr("Browse")
                                onClicked: KdeConnect.browse(card.modelData.id)
                            }
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "sms")
                                materialIcon: "sms"
                                mainText: Translation.tr("Messages")
                                onClicked: KdeConnect.openSms(card.modelData.id)
                            }
                            ActionButton {
                                visible: KdeConnect.hasPlugin(card.modelData, "photo")
                                materialIcon: "photo_camera"
                                mainText: Translation.tr("Photo")
                                onClicked: KdeConnect.requestPhoto(card.modelData.id)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ActionButton {
                                visible: !card.modelData.paired && card.modelData.reachable
                                materialIcon: "link"
                                mainText: Translation.tr("Pair")
                                onClicked: KdeConnect.requestPairing(card.modelData.id)
                            }
                            ActionButton {
                                visible: card.modelData.paired
                                materialIcon: "link_off"
                                mainText: Translation.tr("Unpair")
                                onClicked: KdeConnect.unpair(card.modelData.id)
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: KdeConnect.lastError !== ""
                wrapMode: Text.Wrap
                text: KdeConnect.lastError
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }
        }
    }
}
