import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property string displayText: (root.vertical && root.percentage > 99) ? "" : batteryProgress.text

    implicitWidth:  vertical ? Appearance.sizes.verticalBarWidth : batteryProgress.valueBarWidth + 8
    implicitHeight: vertical ? batteryProgress.valueBarWidth + 8 : Appearance.sizes.barHeight

    // The battery panel (BatteryPopup) has controls, so it stays open while
    // the pointer is on the widget or on it: hovering opens it (unless popups
    // are off or shown on click), a click opens it too (and closes it when a
    // click is what shows it), and it closes a moment after the pointer left.
    property bool panelOpen: false
    readonly property bool hoverOpens: Config.options.bar.tooltips.enable && !Config.options.bar.tooltips.clickToShow
    readonly property bool cursorNear: containsMouse || batteryPopup.hovered

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onCursorNearChanged: {
        if (cursorNear) {
            closeTimer.stop()
            if (!panelOpen && hoverOpens) hoverOpenTimer.restart()
        } else {
            hoverOpenTimer.stop()
            if (panelOpen) closeTimer.restart()
        }
    }
    onClicked: {
        hoverOpenTimer.stop()
        root.panelOpen = root.hoverOpens ? true : !root.panelOpen
    }
    onPanelOpenChanged: if (panelOpen) Battery.refreshChargeLimit()

    Timer {
        id: hoverOpenTimer
        interval: 120
        onTriggered: if (root.cursorNear) root.panelOpen = true
    }
    Timer {
        id: closeTimer
        interval: 700
        onTriggered: if (!root.cursorNear) root.panelOpen = false
    }

    ClippedProgressBar {
        id: batteryProgress
        anchors.centerIn: parent
        value: percentage
        rotation: root.vertical ? -90 : 0
        highlightColor: (isLow && !isCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer
        Item {
            anchors.centerIn: parent
            width: batteryProgress.valueBarWidth
            height: batteryProgress.valueBarHeight
            // Horizontal
            Loader {
                id: rowLoader
                active: !root.vertical
                visible: active
                anchors.centerIn: parent
                sourceComponent: RowLayout {
                    spacing: 0
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2
                        Layout.leftMargin: -2
                        Layout.rightMargin: -2
                        fill: 1
                        text: "bolt"
                        iconSize: Appearance.font.pixelSize.smaller
                        visible: root.isCharging && root.percentage < 1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2
                        font: batteryProgress.font
                        text: batteryProgress.text
                    }
                }
            }
            // Vertical
            Loader {
                id: colLoader
                active: root.vertical
                visible: active
                anchors.centerIn: parent
                sourceComponent: ColumnLayout {
                    rotation: 90
                    spacing: -7
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        fill: 1
                        text: "bolt"
                        Layout.topMargin: 4
                        iconSize: Appearance.font.pixelSize.smaller
                        visible: root.isCharging && root.percentage < 1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: root.isCharging ? 2 : 4
                        font: batteryProgress.font
                        text: root.percentage * 100 
                        visible: root.percentage < 1
                    }
                }
            }
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
        hoverMargin: 10
        active: root.panelOpen
    }
}