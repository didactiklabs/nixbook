pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Claude speaking first (services/Initiative.qml, `speaking`): not a
 * notification but the agent itself, on the left of the screen under the
 * bar, a speech bubble from the robot with Reply, Not now and Don't tell me
 * this. Looks like the theme, unlike its notifications: a Material card
 * with a tail, a slanted Persona frame, a round pastel Chiikawa bubble, a
 * chamfered neon Cyberpunk panel, a paper Ghibli card. After 25 s unanswered
 * (the timer waits while hovered) it goes to the bar's bubble.
 */
Scope {
    id: root

    readonly property var item: Initiative.speaking
    readonly property string style: Persona.enabled ? "persona" : Chiikawa.enabled ? "chiikawa"
        : Cyberpunk.enabled ? "cyberpunk" : Ghibli.enabled ? "ghibli" : "material"

    readonly property color bg: root.style === "persona" ? Persona.frameColor
        : root.style === "chiikawa" ? (Chiikawa.spec.background ?? "#fff6f8")
        : root.style === "cyberpunk" ? Cyberpunk.panel
        : root.style === "ghibli" ? Ghibli.paper
        : Appearance.colors.colPrimaryContainer
    readonly property color fg: root.style === "persona" ? Appearance.colors.colOnLayer1
        : root.style === "chiikawa" ? (Chiikawa.spec.ink ?? "#4a3a3f")
        : root.style === "cyberpunk" ? Cyberpunk.ink
        : root.style === "ghibli" ? Ghibli.ink
        : Appearance.colors.colOnPrimaryContainer
    readonly property color accent: root.style === "persona" ? Persona.stripeColor
        : root.style === "chiikawa" ? (Chiikawa.spec.accent ?? "#f29bb2")
        : root.style === "cyberpunk" ? Cyberpunk.glitchColor
        : root.style === "ghibli" ? Ghibli.accent
        : Appearance.colors.colPrimary
    readonly property color edge: root.style === "chiikawa" ? (Chiikawa.spec.line ?? "#7a5560")
        : root.style === "cyberpunk" ? Cyberpunk.accent
        : root.style === "ghibli" ? Ghibli.warm
        : root.accent
    readonly property string font: root.style === "cyberpunk" ? Cyberpunk.font
        : root.style === "ghibli" ? Ghibli.titleFont : Appearance.font.family.main
    readonly property real radius: root.style === "chiikawa" ? 28 : root.style === "ghibli" ? 16
        : root.style === "material" ? Appearance.rounding.large : 0

    PanelWindow {
        id: window
        visible: root.item !== null && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:agentSpeech"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        color: "transparent"
        anchors { top: true; left: true }
        readonly property bool barTop: !(Config.options.bar.bottom ?? false) && !(Config.options.bar.vertical ?? false)
        readonly property bool barLeft: (Config.options.bar.vertical ?? false) && !(Config.options.bar.bottom ?? false)
        margins {
            top: window.barTop ? Appearance.sizes.barHeight + 6 : 12
            left: window.barLeft ? Appearance.sizes.verticalBarWidth + 6 : 12
        }
        implicitWidth: 380
        implicitHeight: card.implicitHeight + 24

        // Slides in from the left, a little bounce (a snap in Persona).
        Item {
            id: card
            x: 12
            y: 14
            width: 352
            implicitHeight: body.implicitHeight + 28
            opacity: 0
            transform: Translate { id: slide; x: -60 }
            Connections {
                target: root
                function onItemChanged() {
                    if (root.item) {
                        enter.restart()
                        unanswered.restart()
                    }
                }
            }
            Component.onCompleted: if (root.item) enter.restart()
            ParallelAnimation {
                id: enter
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: root.style === "persona" ? 120 : 260 }
                NumberAnimation { target: slide; property: "x"; from: -60; to: 0; duration: root.style === "persona" ? 140 : 420
                                  easing.type: root.style === "persona" ? Easing.OutQuart : Easing.OutBack }
            }

            // The tail, pointing up to the bar's robot.
            Rectangle {
                visible: root.style !== "persona" && root.style !== "cyberpunk"
                x: 26
                y: -7
                width: 16
                height: 16
                rotation: 45
                color: root.bg
                border.color: root.edge
                border.width: root.style === "material" ? 0 : 2
            }
            PersonaFrame {
                visible: root.style === "persona"
                anchors.fill: parent
            }
            Rectangle {
                visible: root.style !== "persona"
                anchors.fill: parent
                radius: root.radius
                color: root.bg
                border.color: root.edge
                border.width: root.style === "material" ? 0 : root.style === "cyberpunk" ? 2 : 3
                // Covers the tail's base, so the bubble and the tail are one.
                Rectangle {
                    visible: root.style !== "cyberpunk"
                    x: 22
                    y: root.style === "material" ? 0 : 3
                    width: 24
                    height: 8
                    color: root.bg
                }
            }
            // Cyberpunk: a notched corner and a neon stripe.
            Item {
                visible: root.style === "cyberpunk"
                anchors { top: parent.top; right: parent.right }
                width: Cyberpunk.chamfer * 0.7
                height: width
                clip: true
                Rectangle {
                    width: parent.width * 1.42
                    height: width
                    x: parent.width - width / 2
                    y: -height / 2
                    rotation: 45
                    color: Cyberpunk.accent
                }
            }
            Rectangle {
                visible: root.style === "cyberpunk"
                width: 4
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 6 }
                color: root.accent
            }

            HoverHandler { id: hover }

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: root.style === "cyberpunk" ? 20 : 14 }
                spacing: 8

                RowLayout {
                    spacing: 8
                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: root.style === "cyberpunk" || root.style === "persona" ? 0 : 13
                        color: root.accent
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "smart_toy"
                            fill: 1
                            iconSize: 17
                            color: root.bg
                        }
                    }
                    StyledText {
                        text: root.style === "cyberpunk" ? "CLAUDE //" : "Claude"
                        font.family: root.font
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.style === "persona" ? root.accent : root.fg
                    }
                    Item { Layout.fillWidth: true }
                    MaterialSymbol {
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.fg
                        opacity: 0.6
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Initiative.hush("later")
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.item?.text ?? ""
                    font.family: root.font
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.fg
                }

                RowLayout {
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "reply", label: Translation.tr("Reply"), main: true },
                            { id: "later", label: Translation.tr("Not now"), main: false },
                            { id: "never", label: Translation.tr("Don't tell me this"), main: false },
                        ]
                        delegate: Rectangle {
                            id: button
                            required property var modelData
                            implicitWidth: label.implicitWidth + 22
                            implicitHeight: 28
                            radius: root.style === "cyberpunk" || root.style === "persona" ? 0 : 14
                            color: button.modelData.main ? root.accent : (mouse.containsMouse ? Qt.alpha(root.accent, 0.18) : "transparent")
                            border.color: root.accent
                            border.width: button.modelData.main ? 0 : 1
                            StyledText {
                                id: label
                                anchors.centerIn: parent
                                text: button.modelData.label
                                font.family: root.font
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: button.modelData.main ? Font.Bold : Font.Normal
                                color: button.modelData.main ? root.bg : root.fg
                            }
                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (button.modelData.id === "reply") Initiative.open(root.item);
                                    else Initiative.hush(button.modelData.id);
                                }
                            }
                        }
                    }
                }
            }

            // Unanswered: into the bar's bubble (the timer waits while hovered).
            Timer {
                id: unanswered
                interval: 25000
                running: root.item !== null && !hover.hovered
                onTriggered: Initiative.hush("wait")
            }
        }
    }
}
