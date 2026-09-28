import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The next calendar event (DankCalendar, services/CalendarEvents.qml): its
// time ("in 12 min", "Now · until 10:30", "14:00") and title; hovering lists
// the following ones. Left click: join the meeting when it has a link and
// starts within 10 minutes (or is on), else open DankCalendar; right click:
// sync now. Just an icon when nothing is coming up this week.
BarWidgetSwitcher {
    id: root
    vertical: Config.options.bar.vertical
    visible: CalendarEvents.available

    // Ticks so the "in N min" text and the next event follow the clock.
    property var now: new Date()
    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property var events: CalendarEvents.upcoming(5, root.now, true)
    readonly property var next: events.length > 0 ? events[0] : null
    readonly property bool soon: next !== null && next.start - root.now <= 10 * 60000
    readonly property string whenText: next ? CalendarEvents.whenText(next, root.now) : ""
    readonly property color accent: soon ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1

    rowDefault: Component {
        RowLayout {
            spacing: 6
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: root.next ? (root.next.meetingUrl ? "video_call" : "event_upcoming") : "event_available"
                iconSize: Appearance.font.pixelSize.larger
                fill: root.soon ? 1 : 0
                color: root.accent
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.next !== null
                text: root.whenText
                font.weight: Font.DemiBold
                color: root.accent
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 180
                visible: root.next !== null
                text: root.next?.summary ?? ""
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
            }
        }
    }
    rowMaterial: rowDefault

    colDefault: Component {
        ColumnLayout {
            spacing: 0
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.next ? (root.next.meetingUrl ? "video_call" : "event_upcoming") : "event_available"
                iconSize: Appearance.font.pixelSize.larger
                fill: root.soon ? 1 : 0
                color: root.accent
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 4
                visible: root.next !== null
                text: root.next ? (root.next.start <= root.now ? Translation.tr("now")
                    : Qt.locale().toString(root.next.start, Config.options?.time.format ?? "hh:mm")) : ""
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.accent
            }
        }
    }
    colMaterial: colDefault

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                CalendarEvents.sync();
            else if (root.soon && root.next.meetingUrl)
                Qt.openUrlExternally(root.next.meetingUrl);
            else
                CalendarEvents.openApp();
        }

        StyledPopup {
            hoverTarget: mouseArea

            ColumnLayout {
                spacing: 6
                width: 300

                StyledPopupHeaderRow {
                    icon: "event_upcoming"
                    label: Translation.tr("Next events")
                }

                StyledText {
                    visible: root.events.length === 0
                    text: CalendarEvents.hasAccounts ? Translation.tr("Nothing this week")
                        : Translation.tr("No calendar connected: click the person icon in a calendar widget")
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: root.events
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillHeight: true
                            implicitWidth: 4
                            radius: 2
                            color: modelData.color || Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.summary
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: CalendarEvents.whenText(modelData, root.now)
                                    + (modelData.location ? ` • ${modelData.location}` : "")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        MaterialSymbol {
                            visible: modelData.meetingUrl.length > 0
                            text: "videocam"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
