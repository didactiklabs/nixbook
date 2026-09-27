pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// NixOS update indicator — left click toggles an action panel (status line,
// Check / Execute / Logs, changelog, live log tail), right click re-checks.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3

    property bool panelOpen: false

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true

    readonly property bool busy: UpdateState.checking || UpdateState.updating
    readonly property bool cursorNear: containsMouse || popupHover.hovered

    // One shared rotation angle: every icon variant binds `rotation` to it,
    // so stopping the check always snaps them back upright (a per-icon
    // RotationAnimation would freeze at its last angle).
    property real spin: 0
    onBusyChanged: {
        if (!busy) spin = 0
    }

    NumberAnimation on spin {
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
        running: root.busy
    }

    onCursorNearChanged: {
        if (cursorNear) closeTimer.stop()
        else if (panelOpen) closeTimer.start()
    }

    Timer {
        id: closeTimer
        interval: 500
        onTriggered: {
            if (!root.cursorNear) root.panelOpen = false
        }
    }

    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            root.panelOpen = !root.panelOpen
        }
    }

    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            UpdateState.checkUpdate()
            Quickshell.execDetached([
                "notify-send",
                Translation.tr("Updates"),
                Translation.tr("Checking for updates..."),
                "-a", "Shell"
            ])
            mouse.accepted = false
        }
    }

    HyprlandFocusGrab {
        active: root.panelOpen
        windows: [panelContent.QsWindow?.window]
        onCleared: root.panelOpen = false
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: 4

            // Default
            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignVCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                rotation: root.spin
            }

            // Material
            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                    rotation: root.spin
                }
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 4

            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignHCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                rotation: root.spin
            }

            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignHCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                    rotation: root.spin
                }
            }
        }
    }

    StyledPopup {
        id: updatePopup
        hoverTarget: root
        active: root.panelOpen

        ColumnLayout {
            id: panelContent
            implicitWidth: 320
            spacing: 10

            HoverHandler {
                id: popupHover
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: UpdateState.updateAvailable && !UpdateState.checking && !UpdateState.updating
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                text: UpdateState.updating ? Translation.tr("Updating system...")
                    : UpdateState.checking ? Translation.tr("Checking for updates...")
                    : UpdateState.updateAvailable
                        ? Translation.tr("Update available: %1 \u2192 %2").arg(UpdateState.localRev.slice(0, 7)).arg(UpdateState.remoteRev.slice(0, 7))
                        : Translation.tr("System up to date (%1)").arg(UpdateState.localRev.slice(0, 7))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "sync"
                    mainText: UpdateState.checking ? Translation.tr("Checking...") : Translation.tr("Check")
                    enabled: !UpdateState.checking && !UpdateState.updating
                    onClicked: UpdateState.checkUpdate()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    visible: UpdateState.updateAvailable || UpdateState.updating
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "deployed_code_update"
                    mainText: UpdateState.updating ? Translation.tr("Updating...") : Translation.tr("Execute")
                    enabled: !UpdateState.updating
                    onClicked: UpdateState.startUpdate()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "terminal"
                    mainText: UpdateState.viewingLogs ? Translation.tr("Stop Logs") : Translation.tr("Logs")
                    onClicked: {
                        if (UpdateState.viewingLogs) {
                            UpdateState.stopLogs()
                        } else {
                            UpdateState.startLogs()
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: UpdateState.changelogText !== ""
                text: Translation.tr("Changelog")
                color: Appearance.colors.colOnLayer2
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                visible: UpdateState.changelogText !== ""
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                Flickable {
                    id: changelogFlickable
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: changelogLabel.paintedHeight
                    clip: true

                    StyledText {
                        id: changelogLabel
                        width: parent.width
                        text: UpdateState.changelogText
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                visible: UpdateState.viewingLogs
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                Flickable {
                    id: logFlickable
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: logLabel.paintedHeight
                    clip: true

                    StyledText {
                        id: logLabel
                        width: parent.width
                        text: UpdateState.logText || Translation.tr("Waiting for logs...")
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.Wrap
                        onTextChanged: {
                            logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height)
                        }
                    }
                }
            }
        }
    }
}
