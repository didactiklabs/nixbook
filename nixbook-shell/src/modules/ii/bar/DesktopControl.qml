pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell

// The desktop agent in the bar, one button per thing a click does (each its
// own hover and tooltip saying what it does):
// - Claude (a robot): ask Claude anything in its speech bubble, again to put
//   it away (Mod+C). It hops when Claude has something new to say and nods
//   while Claude answers in its bubble.
// - What Claude has for the user (a speech bubble, breathing slowly; only
//   then): something new it waits to tell (services/Initiative.qml) or an
//   answer not read in a conversation put away. Click brings it back in
//   Claude's speech bubble, right-click is "not now". What they've read
//   stays dark.
// - Desktop control (services/DesktopControl.qml): a pause button while
//   agents may act (faint idle, pulsing in the accent colour while one
//   acts), a red play button while paused. Click pauses every agent, or
//   allows them again.
// - Where they work: their own desktop or the user's (a window icon; accent
//   while its window is open, faint while it waits for their next app, a
//   hand while the user has taken it over). Click switches.
// - Fixing nixbook (a wrench, services/SelfImprove.qml; only then): click
//   opens it in Settings.
// - Looking at the screen (an eye; only then): pairing reads the screen's
//   text now (Initiative.looking), never unseen. Click stops screen reading.
Item {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : buttons.implicitWidth + 8
    implicitHeight: vertical ? buttons.implicitHeight + 6 : Appearance.sizes.barHeight

    readonly property bool ownDesktop: DesktopControl.onAgentDesktop
    readonly property string deskIcon: !root.ownDesktop ? "desktop_windows"
        : DesktopControl.userHasControl ? "touch_app" : "picture_in_picture"
    readonly property bool lively: DesktopControl.active || Initiative.thinking

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
        function onUnreadChanged() { if (Initiative.unread.length > 0) hopAnim.restart(); }
        function onParkedChanged() { if (Initiative.parked?.unread) hopAnim.restart(); }
    }

    // What the agent waits to tell the user and they haven't read, the
    // latest, or an unread answer in the conversation put away.
    readonly property var said: Initiative.unread.length > 0 ? Initiative.unread[Initiative.unread.length - 1] : null
    readonly property bool waiting: root.said !== null || (Initiative.parked?.unread ?? false)
    property real breathe: 1
    SequentialAnimation on breathe {
        running: root.waiting
        loops: Animation.Infinite
        NumberAnimation { to: 0.5; duration: 1600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.breathe = 1
    }

    function ago(ms) {
        const s = Math.max(0, Math.round((DesktopControl.now - ms) / 1000));
        if (s < 60) return Translation.tr("%1 s ago").arg(s);
        if (s < 3600) return Translation.tr("%1 min ago").arg(Math.round(s / 60));
        return Translation.tr("%1 h ago").arg(Math.round(s / 3600));
    }

    // One button: an icon, plain or on a round chip (the Material corner
    // style), its own click; the bar's hover cue and tooltip come with it
    // (StyledPopup).
    component AgentButton: MouseArea {
        id: button
        property string icon
        property bool filled: false
        property color tone: Appearance.colors.colOnLayer1
        // Material: the chip's colour (and the icon on it).
        property color chip: Appearance.colors.colLayer2
        property color onChip: Appearance.colors.colOnLayer2
        property real iconOpacity: 1
        property real offset: 0
        property bool small: false
        implicitWidth: root.isMaterial ? 26 : glyph.implicitWidth + 8
        implicitHeight: root.isMaterial ? 26 : glyph.implicitHeight + 6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            visible: root.isMaterial
            anchors.centerIn: parent
            anchors.verticalCenterOffset: button.offset
            width: button.small ? 20 : 24
            height: width
            radius: Appearance.rounding.full
            color: button.chip
        }
        MaterialSymbol {
            id: glyph
            anchors.centerIn: parent
            anchors.verticalCenterOffset: button.offset
            text: button.icon
            fill: root.isMaterial || button.filled ? 1 : 0
            iconSize: button.small ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
            color: root.isMaterial ? button.onChip : button.tone
            opacity: button.iconOpacity
        }
    }
    component Hint: StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    GridLayout {
        id: buttons
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 6
        rowSpacing: 2
        columnSpacing: root.isMaterial ? 2 : 0

        // Claude: ask anything.
        AgentButton {
            id: claudeButton
            icon: "smart_toy"
            filled: root.lively || Initiative.speaking !== null
            tone: Initiative.thinking ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            chip: Initiative.thinking ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
            onChip: Initiative.thinking ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            iconOpacity: Initiative.thinking ? root.pulse : Initiative.speaking ? 1 : 0.6
            offset: root.hop
            onClicked: Initiative.toggle()
            StyledPopup {
                hoverTarget: claudeButton
                ColumnLayout {
                    spacing: 4
                    StyledPopupHeaderRow {
                        icon: "smart_toy"
                        label: Translation.tr("Claude")
                    }
                    StyledPopupValueRow {
                        Layout.fillWidth: true
                        visible: Initiative.thinking
                        icon: "forum"
                        label: Translation.tr("Answering…")
                        value: ""
                    }
                    Hint {
                        text: Initiative.speaking ? Translation.tr("Click to put its bubble away (Mod+C)")
                            : Translation.tr("Click to ask Claude anything (Mod+C)")
                    }
                }
            }
        }

        // Something for the user: brought back in the bubble.
        AgentButton {
            id: saidButton
            visible: root.waiting
            small: true
            icon: "chat_bubble"
            filled: true
            tone: Appearance.colors.colPrimary
            chip: Appearance.colors.colPrimary
            onChip: Appearance.colors.colOnPrimary
            iconOpacity: root.breathe
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    if (root.said) Initiative.answer(root.said.id, "later");
                    else Initiative.parked = null;
                } else if (root.said) Initiative.open(root.said);
                else Initiative.resume();
            }
            StyledPopup {
                hoverTarget: saidButton
                ColumnLayout {
                    spacing: 4
                    StyledPopupHeaderRow {
                        icon: "chat_bubble"
                        label: root.said ? Translation.tr("Claude has something for you")
                            : Translation.tr("Your conversation with Claude")
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
                    Hint {
                        text: Translation.tr("Click to read it in Claude's bubble, right-click for not now")
                    }
                }
            }
        }

        // Desktop control: pause every agent, or allow them again.
        AgentButton {
            id: pauseButton
            icon: DesktopControl.paused ? "play_arrow" : "pause"
            filled: DesktopControl.paused || DesktopControl.active
            tone: DesktopControl.paused ? Appearance.m3colors.m3error
                : DesktopControl.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            chip: DesktopControl.paused ? Appearance.m3colors.m3error
                : DesktopControl.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
            onChip: DesktopControl.paused ? Appearance.m3colors.m3onError
                : DesktopControl.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            // Idle: faint, so the accent colour of an acting agent stands out.
            iconOpacity: DesktopControl.active ? root.pulse : DesktopControl.paused ? 1 : 0.45
            onClicked: DesktopControl.toggle()
            StyledPopup {
                hoverTarget: pauseButton
                ColumnLayout {
                    spacing: 4
                    StyledPopupHeaderRow {
                        icon: DesktopControl.paused ? "pan_tool" : "smart_toy"
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
                        visible: DesktopControl.last !== null
                        icon: "history"
                        label: Translation.tr("Last")
                        value: DesktopControl.last
                            ? `${DesktopControl.last.client} · ${DesktopControl.last.tool} · ${root.ago(DesktopControl.last.time)}`
                            : ""
                    }
                    Hint {
                        text: DesktopControl.paused ? Translation.tr("Click to allow agents again")
                            : Translation.tr("Click to stop every agent (Mod+Shift+Escape)")
                    }
                }
            }
        }

        // Where they work: their own desktop or the user's.
        AgentButton {
            id: deskButton
            small: true
            icon: root.deskIcon
            filled: DesktopControl.agentDesktopOpen
            tone: DesktopControl.agentDesktopOpen ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            chip: DesktopControl.agentDesktopOpen ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
            onChip: DesktopControl.agentDesktopOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            iconOpacity: root.ownDesktop ? 1 : 0.45
            onClicked: DesktopControl.toggleDesktop()
            StyledPopup {
                hoverTarget: deskButton
                ColumnLayout {
                    spacing: 4
                    StyledPopupHeaderRow {
                        icon: root.deskIcon
                        label: Translation.tr("Where agents work")
                    }
                    StyledPopupValueRow {
                        Layout.fillWidth: true
                        icon: root.deskIcon
                        label: Translation.tr("Desktop")
                        value: !root.ownDesktop ? Translation.tr("Yours")
                            : DesktopControl.userHasControl ? Translation.tr("Its own, you have control")
                            : DesktopControl.agentDesktopOpen ? Translation.tr("Its own, in a window")
                            : Translation.tr("Its own, opens with its next app")
                    }
                    Hint {
                        text: !root.ownDesktop ? Translation.tr("Click to give them their own desktop")
                            : Translation.tr("Click to bring them back to yours")
                    }
                }
            }
        }

        // Fixing nixbook or building a feature of it: shown in Settings.
        AgentButton {
            id: fixButton
            visible: SelfImprove.running !== null
            small: true
            icon: "build"
            filled: true
            tone: Appearance.colors.colPrimary
            chip: Appearance.colors.colPrimary
            onChip: Appearance.colors.colOnPrimary
            onClicked: {
                GlobalStates.settingsPage = "Desktop agents";
                GlobalStates.settingsOpen = true;
            }
            StyledPopup {
                hoverTarget: fixButton
                ColumnLayout {
                    spacing: 4
                    StyledPopupHeaderRow {
                        icon: "build"
                        label: SelfImprove.running?.feature === true ? Translation.tr("Building a feature of nixbook") : Translation.tr("Fixing nixbook")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 320
                        wrapMode: Text.WordWrap
                        text: SelfImprove.status
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    Hint {
                        text: Translation.tr("Click to see it in Settings")
                    }
                }
            }
        }

        // Looking at the screen: pairing reads its text now.
        AgentButton {
            id: eyeButton
            visible: Initiative.looking > 0
            small: true
            icon: "visibility"
            filled: true
            tone: Appearance.colors.colPrimary
            chip: Appearance.colors.colPrimary
            onChip: Appearance.colors.colOnPrimary
            onClicked: Config.options.ai.initiative.pairReadScreen = false
            StyledPopup {
                hoverTarget: eyeButton
                ColumnLayout {
                    spacing: 4
                    StyledPopupHeaderRow {
                        icon: "visibility"
                        label: Translation.tr("Reading the screen")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 320
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Pairing reads the screen's text on this computer, secrets and numbers removed before the small model sees it. Nothing is kept.")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    Hint {
                        text: Translation.tr("Click to stop reading the screen (the window title only)")
                    }
                }
            }
        }
    }
}
