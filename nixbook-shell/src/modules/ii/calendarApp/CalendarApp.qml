import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Calendar: every account's events (services/CalendarEvents.qml, through
 * nixbook-accounts) as an app. The month on the left (each day's events),
 * the selected day's events on the right; an event opens in the editor
 * there (time, place, calendar, repeat, reminders; this occurrence or the
 * whole series), "New" (Ctrl+N) adds one.
 *
 * A normal application window (xdg-toplevel, title "Calendar"), tiled like
 * any app. Opened from the calendar widgets and the bar clock
 * (CalendarEvents.openApp, newEvent), its launcher entry or
 * `nixbook-shell ipc call calendar open [YYYY-MM-DD]`.
 */
Scope {
    id: root

    property bool everOpened: false

    Connections {
        target: GlobalStates
        function onCalendarAppOpenChanged() {
            if (!GlobalStates.calendarAppOpen) return
            root.everOpened = true
            CalendarEvents.load()
        }
    }

    Loader {
        active: root.everOpened

        sourceComponent: FloatingWindow {
            id: calendarWindow
            title: Translation.tr("Calendar")
            visible: GlobalStates.calendarAppOpen
            implicitWidth: 1240
            implicitHeight: 820
            minimumSize: Qt.size(360, 420)
            color: Appearance.colors.colLayer0Base

            onClosed: GlobalStates.calendarAppOpen = false
            onVisibleChanged: {
                if (!visible && GlobalStates.calendarAppOpen)
                    GlobalStates.calendarAppOpen = false
            }
            Component.onCompleted: content.opened(GlobalStates.calendarAppDate, GlobalStates.calendarAppMode)

            // Opened again (another day, a new event asked for).
            Connections {
                target: GlobalStates
                function onCalendarAppRequestChanged() {
                    content.opened(GlobalStates.calendarAppDate, GlobalStates.calendarAppMode)
                }
            }

            CalendarAppContent {
                id: content
                anchors.fill: parent
                focus: true
            }
        }
    }
}
