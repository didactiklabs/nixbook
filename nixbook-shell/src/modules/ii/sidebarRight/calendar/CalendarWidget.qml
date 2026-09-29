import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    // Layout.topMargin: 10
    anchors.topMargin: 10
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    // The day whose events are listed (null: the month grid).
    property var selectedDate: null
    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 10 * 2

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
        enabled: selectedDate === null
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
        }
    }

    ColumnLayout {
        id: calendarColumn
        anchors.centerIn: parent
        spacing: 5
        // Hidden, not removed, behind the day's events: it keeps the size.
        opacity: selectedDate === null ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Calendar header
        RowLayout {
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
                        running: CalendarEvents.syncing
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
                        day: calendarLayout[modelData][index].day
                        isToday: calendarLayout[modelData][index].today
                        events: CalendarEvents.eventsByDay[CalendarEvents.dayKey(calendarLayout[modelData][index].date)] ?? []
                        releaseAction: () => {
                            if (CalendarEvents.available)
                                selectedDate = calendarLayout[modelData][index].date;
                        }
                    }
                }
            }
        }
    }

    // The selected day's events
    ColumnLayout {
        id: dayView
        anchors.fill: calendarColumn
        spacing: 5
        opacity: selectedDate === null ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        property var events: selectedDate ? (CalendarEvents.eventsByDay[CalendarEvents.dayKey(selectedDate)] ?? []) : []

        function timeText(event) {
            if (event.allDay)
                return Translation.tr("All day");
            const fmt = Config.options?.time.format ?? "hh:mm";
            const sameDay = CalendarEvents.dayKey(event.start) === CalendarEvents.dayKey(selectedDate);
            const start = sameDay ? Qt.locale().toString(event.start, fmt) : "…";
            const endsToday = CalendarEvents.dayKey(event.end) === CalendarEvents.dayKey(selectedDate);
            return `${start} – ${endsToday ? Qt.locale().toString(event.end, fmt) : "…"}`;
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Back to the month")
                downAction: () => {
                    selectedDate = null;
                }
                contentItem: MaterialSymbol {
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: selectedDate ? selectedDate.toLocaleDateString(Qt.locale(), "dddd d MMMM") : ""
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }
            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Add an event")
                downAction: () => {
                    // 09:00 on the selected day.
                    CalendarEvents.newEvent(new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate(), 9));
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
                tooltipText: Translation.tr("Open DankCalendar (events, accounts)")
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
                visible: dayView.events.length === 0
                text: Translation.tr("No events")
                color: Appearance.colors.colSubtext
            }

            StyledListView {
                anchors.fill: parent
                clip: true
                popin: false
                animateAppearance: false
                model: dayView.events
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
                                text: dayView.timeText(eventItem.modelData)
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
}
