pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.mesh
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * A nudge from the mesh (services/Mesh.qml `nudged`: a quick message picked
 * in the Mesh tab's ✨ picker): its own cut-in, in place of the
 * notification. The sender's picture and a big bouncing emoji drop in under
 * the bar of the focused screen with the nudge's words, a few copies of the
 * emoji floating up around it, in the theme's look (its palette; the
 * Cyberpunk or Persona frame when those are on). It never takes the
 * keyboard nor the screen: only the card takes clicks. Click: open the
 * conversation. Right click: away. It leaves by itself after 6 s (hovering
 * holds it); several queue up. Mesh decides when one shows
 * (Mesh._nudgeCutInNow): not locked, Do Not Disturb or over a fullscreen
 * window; with the Mesh tab open too.
 */
Scope {
    id: root

    property var queue: []
    readonly property var current: root.queue.length > 0 ? root.queue[0] : null
    readonly property var nudge: root.current ? Mesh.nudgeOf(root.current.quick) : null
    onCurrentChanged: MakeWay.setCutIn("meshNudge", root.current !== null)
    Component.onDestruction: MakeWay.setCutIn("meshNudge", false)
    Connections {
        target: MakeWay
        function onClearCutIns() {
            root.queue = [];
        }
    }
    Connections {
        target: Mesh
        function onNudged(m) {
            root.queue = root.queue.concat([m]).slice(-5);
            Notifications.playNotificationSound({ hints: {} });
        }
    }
    function next() {
        root.queue = root.queue.slice(1);
    }
    function leave() {
        if (!leaveAnim.running) leaveAnim.start();
    }

    PanelWindow {
        id: window
        visible: root.current !== null && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null
        WlrLayershell.namespace: "quickshell:meshNudge"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        // Only the card takes clicks; what floats around it doesn't.
        mask: Region { item: card }
        color: "transparent"
        anchors.top: true
        margins.top: (Config.options.bar.bottom ?? false) ? 12 : Appearance.sizes.barHeight + 8
        implicitWidth: 520
        implicitHeight: 260

        Item {
            id: stage
            anchors.fill: parent
            // A new nudge: drops in again.
            Connections {
                target: root
                function onCurrentChanged() {
                    if (root.current === null) return;
                    leaveAnim.stop();
                    card.opacity = 1;
                    enterAnim.restart();
                    stay.restart();
                    burst.model = 0;
                    burst.model = 7;
                }
            }

            // Copies of the emoji floating up around the card.
            Repeater {
                id: burst
                model: 7
                delegate: StyledText {
                    id: bit
                    required property int index
                    text: root.nudge?.emoji ?? ""
                    font.pixelSize: 22 + (index % 3) * 6
                    x: card.x + card.width * ((index + 0.5) / 7) - width / 2
                    y: card.y + card.height - 20
                    opacity: 0
                    SequentialAnimation {
                        running: root.current !== null
                        PauseAnimation { duration: 120 + bit.index * 90 }
                        ParallelAnimation {
                            NumberAnimation { target: bit; property: "y"; from: card.y + card.height - 20; to: card.y - 40 - (bit.index % 4) * 18; duration: 1600; easing.type: Easing.OutCubic }
                            SequentialAnimation {
                                NumberAnimation { target: bit; property: "opacity"; from: 0; to: 0.9; duration: 250 }
                                PauseAnimation { duration: 700 }
                                NumberAnimation { target: bit; property: "opacity"; to: 0; duration: 650 }
                            }
                            NumberAnimation { target: bit; property: "rotation"; from: -20 + bit.index * 7; to: 20 - bit.index * 5; duration: 1600 }
                        }
                    }
                }
            }

            CyberpunkFrame {
                visible: Cyberpunk.frames && !Persona.shapes
                anchors.fill: card
                opacity: card.opacity
                scale: card.scale
                color: Appearance.colors.colLayer1Base
                cut: 12
            }
            PersonaFrame {
                visible: Persona.shapes
                anchors.fill: card
                opacity: card.opacity
                scale: card.scale
            }
            StyledRectangularShadow {
                visible: !Persona.shapes && !Cyberpunk.frames
                target: card
                opacity: card.opacity
            }

            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                width: Math.min(440, row.implicitWidth + 40)
                height: row.implicitHeight + 32
                radius: Appearance.rounding.large
                // The theme's accent, not a plain card: it is a cut-in.
                readonly property bool framed: Persona.shapes || Cyberpunk.frames
                color: framed ? "transparent" : Appearance.colors.colPrimaryContainer
                border.width: framed ? 0 : 2
                border.color: Appearance.colors.colPrimary
                readonly property color fg: framed ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnPrimaryContainer
                transformOrigin: Item.Top

                HoverHandler {
                    id: cardHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        const m = root.current;
                        if (m) Mesh.open(Mesh.conversationOf(m));
                        root.leave();
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.leave()
                }

                RowLayout {
                    id: row
                    anchors.centerIn: parent
                    spacing: 14
                    // Head pats: a hand pats the receiver's own picture (a
                    // private one; one to everyone pats a face), squashing it
                    // on each pat.
                    Item {
                        id: pet
                        visible: root.current?.quick === "pet"
                        implicitWidth: 96
                        implicitHeight: 96
                        readonly property bool toMe: (root.current?.to ?? "") !== ""
                        // 0 → 1 → 0 per pat, about three a second.
                        property real press: 0
                        SequentialAnimation on press {
                            running: window.visible && pet.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 1; duration: 140; easing.type: Easing.InQuad }
                            NumberAnimation { from: 1; to: 0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }
                        Item {
                            id: patted
                            width: 72
                            height: 72
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            transform: Scale {
                                origin.x: patted.width / 2
                                origin.y: patted.height
                                xScale: 1 + 0.14 * pet.press
                                yScale: 1 - 0.24 * pet.press
                            }
                            MeshAvatar {
                                visible: pet.toMe
                                anchors.fill: parent
                                size: 72
                                memberId: Mesh.me
                            }
                            StyledText {
                                visible: !pet.toMe
                                anchors.centerIn: parent
                                text: "🥰"
                                font.pixelSize: 60
                            }
                        }
                        StyledText {
                            text: "🫳"
                            font.pixelSize: 54
                            x: 18 + 4 * pet.press
                            y: -6 + 16 * pet.press
                            rotation: -12 + 10 * pet.press
                        }
                    }
                    Item {
                        visible: root.current?.quick !== "pet"
                        implicitWidth: 76
                        implicitHeight: 76
                        MeshAvatar {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            size: 54
                            memberId: root.current?.from ?? ""
                        }
                        // The nudge's emoji, big, bouncing on the picture.
                        StyledText {
                            id: bigEmoji
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -14
                            anchors.topMargin: -16
                            text: root.nudge?.emoji ?? ""
                            font.pixelSize: 50
                            transformOrigin: Item.Bottom
                            SequentialAnimation on scale {
                                running: window.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.18; duration: 260; easing.type: Easing.OutQuad }
                                NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.OutBounce }
                                PauseAnimation { duration: 700 }
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        StyledText {
                            text: root.current ? (root.current.name || Mesh.nameOf(root.current.from)) : ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: card.fg
                            opacity: 0.8
                        }
                        StyledText {
                            Layout.maximumWidth: 320
                            text: root.current?.quick === "pet"
                                ? ((root.current?.to ?? "") !== "" ? Translation.tr("Head pats for you") : Translation.tr("Head pats for everyone"))
                                : root.nudge?.text ?? (root.current?.text ?? "")
                            font.pixelSize: Appearance.font.pixelSize.hugeass + 4
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                            color: card.fg
                        }
                        StyledText {
                            text: (root.current?.to ?? "") === "" ? Translation.tr("To everyone · click to answer")
                                : Translation.tr("Click to answer")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: card.fg
                            opacity: 0.7
                        }
                    }
                }
            }

            // Drops in from above with a little overshoot.
            ParallelAnimation {
                id: enterAnim
                NumberAnimation { target: card; property: "y"; from: -card.height; to: 40; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 200 }
                SequentialAnimation {
                    NumberAnimation { target: card; property: "rotation"; from: -4; to: 3; duration: 260 }
                    NumberAnimation { target: card; property: "rotation"; to: 0; duration: 260; easing.type: Easing.OutBack }
                }
            }
            SequentialAnimation {
                id: leaveAnim
                ParallelAnimation {
                    NumberAnimation { target: card; property: "y"; to: -card.height; duration: 280; easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: 280 }
                }
                ScriptAction { script: root.next() }
            }
            // Left alone: away after 6 s; hovering holds it.
            Timer {
                id: stay
                interval: 6000
                running: root.current !== null && !cardHover.hovered && !leaveAnim.running
                onTriggered: root.leave()
            }
        }
    }
}
