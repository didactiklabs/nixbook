import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    // The day picked in the grid (null: none).
    property var selectedDate: null
    // The day listed under the grid: the one picked, else today, or the first
    // of a month browsed to (today's events may no longer be loaded then).
    readonly property var agendaDate: selectedDate ?? (monthShift === 0 ? DateTime.clock.date : viewingDate)
    // The grid gives way to the agenda on short screens.
    readonly property int agendaMinHeight: 96
    readonly property int cellMinHeight: 26
    // Too short for both: the month wins, the Calendar window has the rest.
    readonly property bool agendaFits: height >= monthHeader.implicitHeight + 7 * (cellMinHeight + 5) + agendaMinHeight + 8
    readonly property real cellWidth: Math.min(52, Math.floor((width - 6 * 5) / 7))
    readonly property real cellHeight: {
        const reserved = monthHeader.implicitHeight + 7 * 5 + (agenda.visible ? agendaMinHeight + 8 : 0);
        return Math.max(cellMinHeight, Math.min(38, Math.floor((height - reserved) / 7)));
    }

    Component.onCompleted: CalendarEvents.load()
    onViewingDateChanged: CalendarEvents.ensureMonth(viewingDate)

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && selectedDate !== null) {
            selectedDate = null;
            event.accepted = true;
        } else if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                monthShift++;
            } else if (event.key === Qt.Key_PageUp) {
                monthShift--;
            }
            event.accepted = true;
        }
    }
    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 5

        // Calendar header
        RowLayout {
            id: monthHeader
            Layout.fillWidth: true
            spacing: 5
            CalendarHeaderButton {
                clip: true
                buttonText: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                downAction: () => {
                    monthShift = 0;
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
            CalendarHeaderButton {
                // Sync the accounts and reload now (otherwise re-read every
                // `calendar.refreshMinutes`).
                visible: CalendarEvents.available
                forceCircle: true
                tooltipText: Translation.tr("Refresh events")
                downAction: () => {
                    if (!CalendarEvents.syncing) CalendarEvents.sync();
                }
                contentItem: MaterialSymbol {
                    id: refreshIcon
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                    RotationAnimation on rotation {
                        // Background syncs run while the (kept-mapped) sidebar is closed.
                        running: CalendarEvents.syncing && ObjectUtils.shown(refreshIcon)
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) refreshIcon.rotation = 0
                    }
                }
            }
            CalendarAccountButton {}
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift--;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift++;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Week days row
        RowLayout {
            id: weekDaysRow
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            spacing: 5
            Repeater {
                model: CalendarLayout.weekDays
                delegate: CalendarDayButton {
                    implicitWidth: root.cellWidth
                    implicitHeight: root.cellHeight
                    day: Translation.tr(modelData.day)
                    isToday: modelData.today
                    bold: true
                    enabled: false
                }
            }
        }

        // Real week rows
        Repeater {
            id: calendarRows
            // model: calendarLayout
            model: 6
            delegate: RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: 5
                Repeater {
                    model: Array(7).fill(modelData)
                    delegate: CalendarDayButton {
                        readonly property var date: calendarLayout[modelData][index].date
                        implicitWidth: root.cellWidth
                        implicitHeight: root.cellHeight
                        day: calendarLayout[modelData][index].day
                        isToday: calendarLayout[modelData][index].today
                        selected: selectedDate !== null && CalendarEvents.dayKey(selectedDate) === CalendarEvents.dayKey(date)
                        events: CalendarEvents.eventsByDay[CalendarEvents.dayKey(date)] ?? []
                        releaseAction: () => {
                            if (CalendarEvents.available)
                                selectedDate = selected ? null : date;
                        }
                    }
                }
            }
        }

        // The day's events
        ColumnLayout {
            id: agenda
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            visible: CalendarEvents.available && root.agendaFits
            spacing: 2
            property var events: CalendarEvents.eventsByDay[CalendarEvents.dayKey(root.agendaDate)] ?? []

            function timeText(event) {
                if (event.allDay)
                    return Translation.tr("All day");
                const fmt = Config.options?.time.format ?? "hh:mm";
                const sameDay = CalendarEvents.dayKey(event.start) === CalendarEvents.dayKey(root.agendaDate);
                const start = sameDay ? Qt.locale().toString(event.start, fmt) : "…";
                const endsToday = CalendarEvents.dayKey(event.end) === CalendarEvents.dayKey(root.agendaDate);
                return `${start} – ${endsToday ? Qt.locale().toString(event.end, fmt) : "…"}`;
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Layout.leftMargin: 6
                    text: root.agendaDate.toLocaleDateString(Qt.locale(), "dddd d MMMM")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                CalendarHeaderButton {
                    forceCircle: true
                    tooltipText: Translation.tr("Add an event")
                    downAction: () => {
                        // 09:00 on the selected day.
                        CalendarEvents.newEvent(new Date(root.agendaDate.getFullYear(), root.agendaDate.getMonth(), root.agendaDate.getDate(), 9));
                    }
                    contentItem: MaterialSymbol {
                        text: "add"
                        iconSize: Appearance.font.pixelSize.larger
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colOnLayer1
                    }
                }
                CalendarHeaderButton {
                    forceCircle: true
                    tooltipText: Translation.tr("Open the calendar (events, new event)")
                    downAction: () => {
                        CalendarEvents.openApp();
                    }
                    contentItem: MaterialSymbol {
                        text: "edit_calendar"
                        iconSize: Appearance.font.pixelSize.larger
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledText {
                    anchors.centerIn: parent
                    visible: agenda.events.length === 0
                    text: Translation.tr("No events")
                    color: Appearance.colors.colSubtext
                }

                StyledListView {
                    anchors.fill: parent
                    clip: true
                    popin: false
                    animateAppearance: false
                    model: agenda.events
                    delegate: RippleButton {
                        id: eventItem
                        required property var modelData
                        width: ListView.view.width
                        implicitHeight: eventRow.implicitHeight + 16
                        buttonRadius: Appearance.rounding.small
                        // Opens the event's meeting link when it has one.
                        enabled: modelData.meetingUrl.length > 0
                        releaseAction: () => {
                            Qt.openUrlExternally(modelData.meetingUrl);
                        }

                        contentItem: RowLayout {
                            id: eventRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Rectangle {
                                Layout.fillHeight: true
                                implicitWidth: 4
                                radius: 2
                                color: eventItem.modelData.color || Appearance.colors.colPrimary
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: eventItem.modelData.summary
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: agenda.timeText(eventItem.modelData)
                                        + (eventItem.modelData.location ? ` • ${eventItem.modelData.location}` : "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol {
                                visible: eventItem.modelData.meetingUrl.length > 0
                                text: "videocam"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        // No agenda to fill the rest.
        Item {
            Layout.fillHeight: true
            visible: !agenda.visible
        }
    }
}
