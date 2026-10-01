pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell

// Desktop control indicator (services/DesktopControl.qml): whether an AI
// agent is driving the desktop through nixbook-desktop-mcp, with the stop
// button. Idle: a dim robot; an agent acting: a pulsing robot in the accent
// colour; paused: a red hand. Click pauses every agent (or allows them again).
// Where they work: a window icon beside it while they're on a desktop of their
// own (red once its window is closed: they're stopped; a hand while the user
// has taken it over); right-click switches between theirs and the user's.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) DesktopControl.toggleDesktop();
        else DesktopControl.toggle();
    }

    readonly property bool ownDesktop: DesktopControl.onAgentDesktop
    readonly property string deskIcon: DesktopControl.userHasControl ? "touch_app" : "picture_in_picture"
    readonly property color deskColor: DesktopControl.agentDesktopOpen ? Appearance.colors.colPrimary
        : Appearance.m3colors.m3error

    readonly property string icon: DesktopControl.paused ? "pan_tool" : "smart_toy"
    readonly property color iconColor: DesktopControl.paused ? Appearance.m3colors.m3error
        : DesktopControl.active ? Appearance.colors.colPrimary
        : Appearance.colors.colOnLayer1

    // Breathes while an agent acts, so it's noticed from the corner of an eye.
    property real pulse: 1
    SequentialAnimation on pulse {
        running: DesktopControl.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.pulse = 1
    }

    function ago(ms) {
        const s = Math.max(0, Math.round((DesktopControl.now - ms) / 1000));
        if (s < 60) return Translation.tr("%1 s ago").arg(s);
        if (s < 3600) return Translation.tr("%1 min ago").arg(Math.round(s / 60));
        return Translation.tr("%1 h ago").arg(Math.round(s / 3600));
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.isMaterial ? materialContent : plainContent
    }

    Component {
        id: plainContent
        Item {
            implicitWidth: plainRow.implicitWidth + 8
            implicitHeight: plainRow.implicitHeight + 6
            Row {
                id: plainRow
                anchors.centerIn: parent
                spacing: 2
                MaterialSymbol {
                    text: root.icon
                    fill: DesktopControl.paused || DesktopControl.active ? 1 : 0
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.iconColor
                    // Idle: faint, so the accent colour of an acting agent stands out.
                    opacity: DesktopControl.active ? root.pulse : DesktopControl.paused ? 1 : 0.45
                }
                MaterialSymbol {
                    visible: root.ownDesktop
                    text: root.deskIcon
                    fill: DesktopControl.agentDesktopOpen ? 1 : 0
                    iconSize: Appearance.font.pixelSize.small
                    color: root.deskColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Component {
        id: materialContent
        Item {
            implicitWidth: 24 + 8
            implicitHeight: 24 + 6
            // Their own desktop: a badge on the button's corner.
            Rectangle {
                z: 1
                visible: root.ownDesktop
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 1; bottomMargin: 1 }
                width: 14
                height: 14
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.deskIcon
                    fill: DesktopControl.agentDesktopOpen ? 1 : 0
                    iconSize: 10
                    color: root.deskColor
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: DesktopControl.paused ? Appearance.m3colors.m3error
                    : DesktopControl.active ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: DesktopControl.paused || DesktopControl.active ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer2
                    opacity: root.pulse
                }
            }
        }
    }

    StyledPopup {
        hoverTarget: root
        active: root.containsMouse && Config.options.bar.tooltips.enable

        ColumnLayout {
            spacing: 4

            StyledPopupHeaderRow {
                icon: "smart_toy"
                label: Translation.tr("Desktop control")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: DesktopControl.paused ? "pan_tool" : DesktopControl.active ? "play_circle" : "pause_circle"
                label: Translation.tr("Status")
                value: DesktopControl.paused ? Translation.tr("Paused: agents can't act")
                    : DesktopControl.active ? Translation.tr("An agent is acting")
                    : Translation.tr("Idle")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: root.ownDesktop ? root.deskIcon : "desktop_windows"
                label: Translation.tr("Desktop")
                value: !root.ownDesktop ? Translation.tr("Yours")
                    : DesktopControl.userHasControl ? Translation.tr("Its own, you have control")
                    : DesktopControl.agentDesktopOpen ? Translation.tr("Its own, in a window")
                    : Translation.tr("Its own, closed: stopped")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: DesktopControl.last !== null
                icon: "history"
                label: Translation.tr("Last")
                value: DesktopControl.last
                    ? `${DesktopControl.last.client} · ${DesktopControl.last.tool} · ${root.ago(DesktopControl.last.time)}`
                    : ""
            }

            StyledText {
                Layout.fillWidth: true
                text: DesktopControl.paused ? Translation.tr("Click to allow agents again")
                    : Translation.tr("Click to stop every agent")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: !root.ownDesktop ? Translation.tr("Right-click to give them their own desktop")
                    : DesktopControl.agentDesktopOpen ? Translation.tr("Right-click to bring them back to yours")
                    : Translation.tr("Right-click to open their desktop again")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
