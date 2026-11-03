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
 * The smart clipboard's chips (services/SmartClipboard.qml): a small card
 * "Copied a tracking number — Track it · Not now" for ~8 s, at the top
 * left under the bar, beside DAI's speech bubble when it shows (AgentSpeech,
 * 404 px wide there). Never takes the keyboard; only the card takes
 * clicks. Built on the first copy offered, then kept mapped (hidden: no
 * input, transparent), so showing it again costs nothing. Hovering it holds
 * it; out of an agent's screenshots (MakeWay).
 */
Scope {
    id: root
    property bool everShown: false
    Connections {
        target: SmartClipboard
        function onCurrentChanged() {
            if (SmartClipboard.current) root.everShown = true
        }
    }

    LazyLoader {
        active: root.everShown
        component: PanelWindow {
            id: window
            readonly property bool open: SmartClipboard.current !== null && !GlobalStates.screenLocked
            // What it shows, kept while it fades out.
            property var offer: null
            Connections {
                target: SmartClipboard
                function onCurrentChanged() {
                    if (SmartClipboard.current) window.offer = SmartClipboard.current
                }
            }
            Component.onCompleted: window.offer = SmartClipboard.current

            screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? Quickshell.screens[0]

            color: "transparent"
            implicitWidth: Math.min(560, card.implicitWidth + 8)
            implicitHeight: card.implicitHeight + 8
            anchors {
                top: true
                left: true
            }
            readonly property bool barTop: !(Config.options.bar.bottom ?? false) && !(Config.options.bar.vertical ?? false)
            readonly property bool barLeft: (Config.options.bar.vertical ?? false) && !(Config.options.bar.bottom ?? false)
            // DAI's bubble (AgentSpeech: 404 px from the same corner): beside it.
            readonly property bool bubbleShown: Initiative.speaking !== null
            margins {
                top: window.barTop ? Appearance.sizes.barHeight + 6 : 12
                left: (window.barLeft ? Appearance.sizes.verticalBarWidth + 6 : 12) + (window.bubbleShown ? 412 : 0)
            }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:smartClipboard"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            property Region noInput: Region {}
            property Region cardInput: Region { item: card }
            mask: window.open && !MakeWay.active ? window.cardInput : window.noInput

            Rectangle {
                id: card
                x: 4
                y: 4
                implicitWidth: Math.min(552, column.implicitWidth + 24)
                implicitHeight: column.implicitHeight + 18
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1
                border.color: Appearance.m3colors.m3outlineVariant
                opacity: window.open && !MakeWay.capture ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    enabled: !MakeWay.capture
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                transform: Translate {
                    y: window.open ? 0 : -8
                    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
                HoverHandler {
                    id: hover
                    onHoveredChanged: SmartClipboard.hovered = hover.hovered && window.open
                }

                ColumnLayout {
                    id: column
                    x: 12
                    y: 9
                    width: Math.min(implicitWidth, 528)
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        Layout.maximumWidth: 528
                        MaterialSymbol {
                            text: SmartClipboard.kindIcons[window.offer?.kind ?? ""] ?? "content_paste"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.m3colors.m3primary
                        }
                        StyledText {
                            text: window.offer?.title ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 300
                            visible: text.length > 0
                            text: window.offer?.detail ? `· ${window.offer.detail}` : ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                    // Three chips at most, short labels: one row.
                    Row {
                        spacing: 6
                        Repeater {
                            id: chips
                            model: window.offer?.chips ?? []
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                required property int index
                                readonly property bool main: chip.index === 0
                                implicitWidth: chipRow.implicitWidth + 20
                                implicitHeight: 28
                                radius: 14
                                color: chip.main ? (chipMouse.containsMouse ? Qt.lighter(Appearance.m3colors.m3primary, 1.1) : Appearance.m3colors.m3primary)
                                    : (chipMouse.containsMouse ? Qt.alpha(Appearance.m3colors.m3primary, 0.16) : "transparent")
                                border.color: Appearance.m3colors.m3primary
                                border.width: chip.main ? 0 : 1
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.modelData.model ? "auto_awesome" : chip.modelData.icon
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: chip.main ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3primary
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: chip.main ? Font.Bold : Font.Normal
                                        color: chip.main ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                                    }
                                }
                                MouseArea {
                                    id: chipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SmartClipboard.runChip(chip.modelData)
                                }
                            }
                        }
                        Rectangle {
                            id: notNow
                            implicitWidth: notNowText.implicitWidth + 18
                            implicitHeight: 28
                            radius: 14
                            color: notNowMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                            StyledText {
                                id: notNowText
                                anchors.centerIn: parent
                                text: Translation.tr("Not now")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MouseArea {
                                id: notNowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: SmartClipboard.dismiss(true)
                            }
                        }
                    }
                }

                // The time left, a thin line along the bottom (still while hovered).
                Rectangle {
                    id: timeLeft
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: card.radius
                    height: 2
                    radius: 1
                    color: Qt.alpha(Appearance.m3colors.m3primary, 0.5)
                    width: 0
                    NumberAnimation {
                        id: drain
                        target: timeLeft
                        property: "width"
                        from: card.width - 2 * card.radius
                        to: 0
                        duration: SmartClipboard.showMs
                        paused: SmartClipboard.hovered
                    }
                    Connections {
                        target: SmartClipboard
                        function onCurrentChanged() {
                            drain.stop()
                            if (SmartClipboard.current) drain.start()
                        }
                        function onHoveredChanged() {
                            // The countdown starts over once the pointer leaves.
                            if (!SmartClipboard.hovered && SmartClipboard.current) drain.restart()
                        }
                    }
                }
            }
        }
    }
}
