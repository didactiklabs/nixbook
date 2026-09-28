pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Calendar events from DankCalendar's daemon (`dcal`), for the calendar
 * widgets (sidebar and desktop).
 *
 * dcal keeps the accounts (Google, Microsoft, CalDAV, iCloud, iCal feeds,
 * local) signed in and in sync; this only reads its local copy over IPC
 * (`dcal ipc calendars.list` / `events.list`, recurring series expanded by
 * the daemon) and asks it to sync or to show its window. Adding and editing
 * events happens in dcal's own window, which syncs them back.
 *
 * The binary comes from NIXBOOK_SHELL_DCAL (set by the Home Manager module's
 * `calendar.package`), else `dcal` on PATH. Without a running daemon
 * `available` stays false and the widgets show a plain calendar.
 */
Singleton {
    id: root

    readonly property string dcal: Quickshell.env("NIXBOOK_SHELL_DCAL") || "dcal"

    property bool available: false
    property bool loading: false
    // "YYYY-MM-DD" (local) -> events on that day, all-day ones first, then
    // by start. Each event: { id, summary, location, meetingUrl, start, end
    // (Date), allDay, color, calendarName }.
    property var eventsByDay: ({})
    // Loaded window: from the first day of the month before `anchor` to
    // the end of the second month after it.
    property var rangeStart: new Date(0)
    property var rangeEnd: new Date(0)

    property var _calendars: ({})
    property var _anchor: new Date()
    property bool _started: false
    // A refresh asked for while one runs (e.g. month navigation): run it
    // once the current one ends, so its window isn't lost.
    property bool _pending: false

    function load() {
        if (root._started) return
        root._started = true
        root.refresh()
    }

    function dayKey(date) {
        const pad = n => (n < 10 ? "0" : "") + n
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
    }

    function eventsOn(date) {
        return root.eventsByDay[root.dayKey(date)] ?? []
    }

    // Reload around `date` when it falls outside the loaded window (month
    // navigation in the widgets).
    function ensureMonth(date) {
        const first = new Date(date.getFullYear(), date.getMonth(), 1)
        const last = new Date(date.getFullYear(), date.getMonth() + 1, 1)
        if (first < root.rangeStart || last > root.rangeEnd) {
            root._anchor = first
            root.refresh()
        }
    }

    function refresh() {
        if (root.loading) {
            root._pending = true
            return
        }
        root.loading = true
        calendarsProc.running = true
    }

    // Sync every account now, then reload.
    function sync() {
        syncProc.running = true
    }

    function openApp() {
        Quickshell.execDetached([root.dcal, "show"])
    }

    // All-day events are dates stored at UTC midnight, their end exclusive.
    function _dayBoundary(iso) {
        const d = new Date(iso)
        return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
    }

    function _finish() {
        root.loading = false
        if (root._pending) {
            root._pending = false
            root.refresh()
        }
    }

    function _index(events) {
        const byDay = {}
        for (const e of events) {
            const cal = root._calendars[e.calendarId]
            if (cal?.hidden || e.status === "cancelled") continue
            const allDay = !!e.allDay
            const start = allDay ? root._dayBoundary(e.start) : new Date(e.start)
            let end = allDay ? root._dayBoundary(e.end) : new Date(e.end)
            if (allDay && end <= start) end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1)
            const item = {
                id: e.id,
                summary: e.summary || Translation.tr("(No title)"),
                location: e.location || "",
                meetingUrl: e.meetingUrl || "",
                start: start,
                end: end,
                allDay: allDay,
                color: cal?.color || "",
                calendarName: cal?.name || "",
            }
            // One entry per day the event touches (the end is exclusive).
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate())
            do {
                const key = root.dayKey(day)
                ;(byDay[key] = byDay[key] ?? []).push(item)
                day.setDate(day.getDate() + 1)
            } while (day < end)
        }
        for (const key in byDay) {
            byDay[key].sort((a, b) => (a.allDay !== b.allDay) ? (a.allDay ? -1 : 1) : a.start - b.start)
        }
        return byDay
    }

    Process {
        id: calendarsProc
        command: [root.dcal, "ipc", "calendars.list"]
        stdout: StdioCollector {
            id: calendarsOut
        }
        onExited: code => {
            if (code !== 0) {
                // No daemon (not installed, not started yet, or no accounts).
                root.available = false
                root._finish()
                return
            }
            try {
                const map = {}
                for (const c of JSON.parse(calendarsOut.text)) map[c.id] = c
                root._calendars = map
            } catch (e) {
                console.warn("CalendarEvents: cannot parse calendars:", e)
            }
            const a = root._anchor
            root.rangeStart = new Date(a.getFullYear(), a.getMonth() - 1, 1)
            root.rangeEnd = new Date(a.getFullYear(), a.getMonth() + 2, 1)
            eventsProc.command = [root.dcal, "ipc", "events.list",
                `from=${root.rangeStart.toISOString()}`, `to=${root.rangeEnd.toISOString()}`]
            eventsProc.running = true
        }
    }

    Process {
        id: eventsProc
        stdout: StdioCollector {
            id: eventsOut
        }
        onExited: code => {
            if (code !== 0) {
                root.available = false
            } else {
                try {
                    root.eventsByDay = root._index(JSON.parse(eventsOut.text).events ?? [])
                    root.available = true
                } catch (e) {
                    console.warn("CalendarEvents: cannot parse events:", e)
                }
            }
            root._finish()
        }
    }

    Process {
        id: syncProc
        command: [root.dcal, "ipc", "accounts.refresh"]
        onExited: root.refresh()
    }

    // dcal syncs on its own schedule; re-read its copy regularly, and at
    // midnight the "today" highlight moves anyway.
    Timer {
        interval: 5 * 60 * 1000
        running: root._started
        repeat: true
        onTriggered: root.refresh()
    }
}
