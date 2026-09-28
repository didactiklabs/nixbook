import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

// The next calendar events (DankCalendar, services/CalendarEvents.qml): the
// next one large (when, title, time and place, a Join button for a meeting
// link), the three after it below. The account button connects Google or
// opens DankCalendar.
AbstractBackgroundWidget {
    id: root
    configEntryName: "nextEvent"
    hoverEnabled: true

    implicitWidth: 276
    implicitHeight: 252

    // Ticks so "in N min" and the next event follow the clock.
    property var now: new Date()
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property var events: CalendarEvents.upcoming(4, root.now, false)
    readonly property var next: events.length > 0 ? events[0] : null
    readonly property var later: events.slice(1)
    readonly property string fmt: Config.options?.time.format ?? "hh:mm"

    WidgetShadow {
        target: card
        visible: Config.options.background.widgets.shadow
    }
    WidgetOutline {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Appearance.colors.colWidgetCard
        radius: Appearance.rounding?.verylarge ?? 30

        FastBlurred {
            anchors.fill: parent
            blurSource: root.wallpaperItem
            cardRadius: card.radius
            tint: Appearance.colors.colLayer1
            tintOpacity: 0.55
            trackX: root.x
            trackY: root.y
            visible: Config.options.background.widgets.blurWidgets
        }

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: "event_upcoming"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Next up")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimaryContainer
                }
                CalendarAccountButton {
                    size: 30
                    colIcon: Appearance.colors.colOnPrimaryContainer
                }
            }

            // The next event
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: nextColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
                visible: root.next !== null

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 10 }
                    width: 4
                    radius: 2
                    color: root.next?.color || Appearance.colors.colPrimary
                }

                ColumnLayout {
                    id: nextColumn
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 22; rightMargin: 10 }
                    spacing: 2

                    StyledText {
                        text: root.next ? CalendarEvents.whenText(root.next, root.now) : ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.next?.summary ?? ""
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: !root.next ? ""
                            : (root.next.allDay ? "" : `${Qt.locale().toString(root.next.start, root.fmt)} – ${Qt.locale().toString(root.next.end, root.fmt)}`)
                              + (root.next.location ? `${root.next.allDay ? "" : " • "}${root.next.location}` : "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                    }
                    RippleButton {
                        Layout.topMargin: 4
                        visible: (root.next?.meetingUrl ?? "").length > 0
                        implicitHeight: 30
                        implicitWidth: joinRow.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        releaseAction: () => Qt.openUrlExternally(root.next.meetingUrl)
                        contentItem: RowLayout {
                            id: joinRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "videocam"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: Translation.tr("Join")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            // Nothing coming
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.next === null
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 4
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: CalendarEvents.hasAccounts ? "event_available" : "person_add"
                        iconSize: 36
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: !CalendarEvents.available ? Translation.tr("DankCalendar isn't running")
                            : CalendarEvents.hasAccounts ? Translation.tr("Nothing this week")
                            : Translation.tr("Connect a Google account with the button above")
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.8
                    }
                }
            }

            // The ones after it
            Repeater {
                model: root.later
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        implicitWidth: 4
                        implicitHeight: 14
                        radius: 2
                        color: modelData.color || Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: CalendarEvents.whenText(modelData, root.now)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.summary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            Item {
                Layout.fillHeight: true
                visible: root.next !== null
            }
        }
    }
}
