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
// own (accent while its window is open, faint while it waits for their next
// app, red once the user closed it: they're stopped; a hand while the user
// has taken it over); right-click switches between theirs and the user's.
// A speech bubble beside it while the agent has something to tell the user
// (services/Initiative.qml), or a conversation put away, breathing slowly:
// click brings it back in Claude's speech bubble, right-click is "not now".
// Middle-click (or Mod+Shift+Space) calls Claude up to ask anything. The
// robot hops when Claude has something new to say, and nods while Claude
// answers in its bubble.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) Initiative.summon();
        else if (mouse.button === Qt.RightButton) DesktopControl.toggleDesktop();
        else DesktopControl.toggle();
    }

    readonly property bool ownDesktop: DesktopControl.onAgentDesktop
    readonly property string deskIcon: DesktopControl.userHasControl ? "touch_app" : "picture_in_picture"
    readonly property color deskColor: DesktopControl.agentDesktopOpen ? Appearance.colors.colPrimary
        : Appearance.colors.colOnLayer1

    readonly property string icon: DesktopControl.paused ? "pan_tool" : "smart_toy"
    readonly property bool lively: DesktopControl.active || Initiative.thinking
    readonly property color iconColor: DesktopControl.paused ? Appearance.m3colors.m3error
        : root.lively ? Appearance.colors.colPrimary
        : Appearance.colors.colOnLayer1

    // Breathes while an agent acts, so it's noticed from the corner of an eye.
    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.lively
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.pulse = 1
    }

    // A hop when Claude has something new to say (out loud or waiting).
    property real hop: 0
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: root; property: "hop"; to: -4; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hop"; to: 0; duration: 380; easing.type: Easing.OutBounce }
    }
    Connections {
        target: Initiative
        function onSpeakingChanged() { if (Initiative.speaking) hopAnim.restart(); }
        function onLiveChanged() { if (Initiative.live.length > 0) hopAnim.restart(); }
    }

    // What the agent waits to tell the user, the latest, or the
    // conversation put away.
    readonly property var said: Initiative.live.length > 0 ? Initiative.live[Initiative.live.length - 1] : null
    readonly property bool waiting: root.said !== null || Initiative.parked !== null
    component Bubble: MaterialSymbol {
        id: bubble
        readonly property var said: root.said
        visible: root.waiting
        text: "chat_bubble"
        fill: 1
        color: Appearance.colors.colPrimary
        SequentialAnimation on opacity {
            running: root.waiting
            loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -3
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    if (bubble.said) Initiative.answer(bubble.said.id, "later");
                    else Initiative.parked = null;
                } else if (bubble.said) Initiative.open(bubble.said);
                else Initiative.resume();
            }
        }
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
                anchors.verticalCenterOffset: root.hop
                spacing: 2
                MaterialSymbol {
                    text: root.icon
                    fill: DesktopControl.paused || root.lively ? 1 : 0
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.iconColor
                    // Idle: faint, so the accent colour of an acting agent stands out.
                    opacity: root.lively ? root.pulse : DesktopControl.paused ? 1 : 0.45
                }
                MaterialSymbol {
                    visible: root.ownDesktop
                    text: root.deskIcon
                    fill: DesktopControl.agentDesktopOpen ? 1 : 0
                    iconSize: Appearance.font.pixelSize.small
                    color: root.deskColor
                    anchors.verticalCenter: parent.verticalCenter
                }
                Bubble {
                    iconSize: Appearance.font.pixelSize.small
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
            // Something to tell: a bubble on the button's top corner.
            Bubble {
                z: 1
                anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -1 }
                iconSize: 12
            }
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
                anchors.verticalCenterOffset: root.hop
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: DesktopControl.paused ? Appearance.m3colors.m3error
                    : root.lively ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: DesktopControl.paused || root.lively ? Appearance.colors.colOnPrimary
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
                    : Translation.tr("Its own, opens with its next app")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: root.said !== null
                icon: "chat_bubble"
                label: Translation.tr("Has something for you")
                value: ""
            }
            StyledText {
                visible: root.said !== null
                Layout.fillWidth: true
                Layout.maximumWidth: 320
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.said ? root.said.text : ""
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: root.said === null && Initiative.parked !== null
                icon: "forum"
                label: Translation.tr("Your conversation with Claude")
                value: Initiative.thinking ? Translation.tr("Answering…") : ""
            }
            StyledText {
                visible: root.waiting
                Layout.fillWidth: true
                text: Translation.tr("Click the bubble to bring it back, right-click for not now")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
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
                    : Translation.tr("Right-click to bring them back to yours")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Middle-click to ask Claude anything (Mod+Shift+Space)")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
