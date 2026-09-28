import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    property var today: new Date()

    function usageColor(value) {
        if (value > 0.9) return Appearance.colors.colError
        if (value > 0.6) return Appearance.m3colors.m3tertiary
        return Appearance.colors.colPrimary
    }

    ColumnLayout {
        spacing: 8
        width: 340

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Qt.locale().toString(root.today, " MMMM")
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: " " + Qt.locale().toString(root.today, "yyyy")
                font.pixelSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            // DankCalendar: connect an account, or open it (events, tasks).
            CalendarAccountButton {
                size: 32
            }
        }

        RowLayout {
            width: parent.width
            spacing: 4

            Repeater {
                model: 7
                delegate: Rectangle {
                    required property int index

                    readonly property var date: {
                        const today = root.today
                        const dow = today.getDay()
                        const d = new Date(today)
                        d.setDate(today.getDate() - dow + index)
                        return d
                    }
                    readonly property bool isToday: {
                        const t = root.today
                        return date.getDate()     === t.getDate() &&
                               date.getMonth()    === t.getMonth() &&
                               date.getFullYear() === t.getFullYear()
                    }

                    Layout.fillWidth: true
                    height: 56
                    radius: Appearance.rounding.normal
                    color: isToday
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colSurfaceContainerHigh

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.locale().toString(date, "ddd").slice(0, 2)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: isToday
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurfaceVariant
                            font.weight: isToday ? Font.Bold : Font.Normal
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: date.getDate()
                            font.pixelSize: isToday
                                ? Appearance.font.pixelSize.normal
                                : Appearance.font.pixelSize.small
                            font.weight: isToday ? Font.Bold : Font.Normal
                            color: isToday
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer1
                        }
                    }

                    // The day's events (CalendarEvents), up to three dots.
                    Row {
                        readonly property var events: CalendarEvents.eventsOn(date)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        spacing: 2
                        Repeater {
                            model: parent.events.slice(0, 3)
                            delegate: Rectangle {
                                required property var modelData
                                width: 4
                                height: 4
                                radius: 2
                                color: modelData.color || Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }

        // Next events (the coming week), from DankCalendar.
        Column {
            id: nextUp
            readonly property var events: CalendarEvents.upcoming(3)
            Layout.fillWidth: true
            spacing: 2
            visible: events.length > 0

            Repeater {
                model: nextUp.events
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isFirst: index === 0
                    readonly property bool isLast: index === nextUp.events.length - 1
                    readonly property real bigRadius: Appearance.rounding.normal
                    readonly property real smallRadius: Appearance.rounding.unsharpenmore
                    readonly property string fmt: Config.options?.time.format ?? "hh:mm"
                    readonly property bool startsToday: CalendarEvents.dayKey(modelData.start) === CalendarEvents.dayKey(new Date())

                    width: parent.width
                    height: 32
                    topLeftRadius:     isFirst ? bigRadius : smallRadius
                    topRightRadius:    isFirst ? bigRadius : smallRadius
                    bottomLeftRadius:  isLast  ? bigRadius : smallRadius
                    bottomRightRadius: isLast  ? bigRadius : smallRadius
                    color: Appearance.colors.colSurfaceContainerHigh

                    Rectangle {
                        id: eventColor
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 4
                        height: 16
                        radius: 2
                        color: modelData.color || Appearance.colors.colPrimary
                    }
                    StyledText {
                        id: eventWhen
                        anchors { left: eventColor.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        text: modelData.allDay ? Translation.tr("All day")
                            : (startsToday ? "" : Qt.locale().toString(modelData.start, "ddd") + " ")
                              + Qt.locale().toString(modelData.start, fmt)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        anchors { left: eventWhen.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: modelData.summary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 6

            Column {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter

                MaterialShapeWrappedMaterialSymbol {
                    shape: MaterialShape.Shape.Clover4Leaf
                    text: "checklist"
                    iconSize: Appearance.font.pixelSize.large
                    implicitSize: 36
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colPrimary
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `${Todo.list.filter(t => !t.done).length}`
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
            }

            Column {
                width: parent.width - 36 - 6
                spacing: 2

                Repeater {
                    id: todoRepeater
                    model: Todo.pending(3)

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        readonly property var todo: modelData
                        readonly property int total: todoRepeater.count
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === total - 1
                        readonly property real bigRadius: Appearance.rounding.normal
                        readonly property real smallRadius: Appearance.rounding.unsharpenmore

                        width: parent.width
                        height: 32
                        topLeftRadius:     isFirst ? bigRadius : smallRadius
                        topRightRadius:    isFirst ? bigRadius : smallRadius
                        bottomLeftRadius:  isLast  ? bigRadius : smallRadius
                        bottomRightRadius: isLast  ? bigRadius : smallRadius
                        color: Appearance.colors.colSurfaceContainerHigh

                        StyledText {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                                right: parent.right
                                rightMargin: 10
                            }
                            text: `    ${todo.content} `
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 64
                    visible: Todo.list.filter(t => !t.done).length === 0
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerHigh

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("No pending tasks")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 10
            color: "transparent"

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: "timelapse"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: Translation.tr("System Uptime")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: "•"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: DateTime.uptime
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }
}