pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Calendar events from DankCalendar's daemon (`dcal`), for every calendar in
 * the shell (sidebar, desktop widget, bar clock popup); its task lists back
 * services/Todo.qml.
 *
 * dcal keeps the accounts (Google, Microsoft, CalDAV, iCloud, iCal feeds,
 * local) signed in and in sync; this only reads its local copy over IPC
 * (`dcal ipc calendars.list` / `events.list`, recurring series expanded by
 * the daemon) and asks it to sync or to show its window. Adding and editing
 * events happens in dcal's own window, which syncs them back.
 *
 * `dcal` is on the shell's PATH (package.nix) and its daemon is the `dcal`
 * user service (hm-module.nix). Until it answers, `available` stays false
 * and the widgets show a plain calendar and the local to-do list.
 */
Singleton {
    id: root

    readonly property string dcal: "dcal"

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
    // dcal's task lists (Google Tasks, CalDAV VTODO…) that aren't hidden:
    // [{ id, name, color }].
    property var taskLists: []
    // At least one calendar synced: some account is connected.
    readonly property bool hasAccounts: Object.keys(root._calendars).length > 0
    // A Google sign-in is waiting for the browser.
    property bool connecting: false

    // After each successful reload (Todo reloads its tasks then).
    signal refreshed()

    property var _calendars: ({})
    property var _anchor: new Date()
    property bool _started: false
    // A refresh asked for while one runs (e.g. month navigation): run it
    // once the current one ends, so its window isn't lost.
    property bool _pending: false
    // Queued `dcal ipc` calls: [{ args, onDone }], run one at a time.
    property var _calls: []
    property string _lastCalendarsText: ""
    property string _lastEventsText: ""
    property bool _calendarsChanged: false

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

    // The next `limit` events not over yet at `now` within the coming week:
    // timed ones, and today's all-day ones unless `timedOnly`. Pass a `now`
    // that ticks for a binding to follow the clock.
    function upcoming(limit, now = new Date(), timedOnly = false) {
        const seen = {}
        const out = []
        const day = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        for (let i = 0; i < 7 && out.length < limit; i++) {
            for (const e of root.eventsOn(day)) {
                const key = `${e.id}@${e.start.getTime()}`
                if (seen[key] || e.end <= now || (e.allDay && (timedOnly || i > 0))) continue
                seen[key] = true
                out.push(e)
                if (out.length >= limit) break
            }
            day.setDate(day.getDate() + 1)
        }
        return out
    }

    // "Now · until 10:30", "in 12 min", "14:00", "Tomorrow 09:00",
    // "Fri 09:00", "All day".
    function whenText(event, now = new Date()) {
        const fmt = Config.options?.time.format ?? "hh:mm"
        const at = d => Qt.locale().toString(d, fmt)
        if (event.allDay)
            return Translation.tr("All day")
        if (event.start <= now)
            return Translation.tr("Now · until %1").arg(at(event.end))
        const minutes = Math.round((event.start - now) / 60000)
        if (minutes < 60)
            return Translation.tr("in %1 min").arg(Math.max(1, minutes))
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const days = Math.floor((new Date(event.start.getFullYear(), event.start.getMonth(), event.start.getDate()) - today) / 86400000)
        if (days === 0) return at(event.start)
        if (days === 1) return Translation.tr("Tomorrow %1").arg(at(event.start))
        return `${Qt.locale().toString(event.start, "ddd")} ${at(event.start)}`
    }

    // `dcal ipc <method> key=value…`; onDone(ok, result) gets the parsed JSON.
    function call(method, params, onDone) {
        const args = [root.dcal, "ipc", method]
        for (const key in params) args.push(`${key}=${params[key]}`)
        root._calls.push({ args: args, onDone: onDone })
        // Otherwise the running call starts the next one when it ends.
        if (root._calls.length === 1) root._nextCall()
    }

    function _nextCall() {
        const next = root._calls[0]
        if (!next) return
        callProc.command = next.args
        callProc.running = true
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
    readonly property bool syncing: syncProc.running

    // DankCalendar's window: events, tasks, and its settings (accounts:
    // Google, Microsoft, CalDAV, iCloud, iCal feeds).
    function openApp() {
        Quickshell.execDetached([root.dcal, "show"])
    }

    // Its new-event editor, starting at `date` (a Date; default: the next
    // half hour).
    function newEvent(date) {
        root.call("ui.newEvent", date ? { start: date.toISOString() } : {})
    }

    // Google sign-in with dcal's built-in OAuth client: the browser opens
    // Google's consent page, dcal gets the token on 127.0.0.1 and keeps it
    // in the keyring. No client ID or Cloud project needed.
    function connectGoogle() {
        if (root.connecting) return
        root.connecting = true
        root.call("accounts.google.start", {}, (ok, result) => {
            if (!ok || !result?.authUrl) {
                root.connecting = false
                return
            }
            Qt.openUrlExternally(result.authUrl)
            connectProc.command = [root.dcal, "ipc", "accounts.google.complete", `state=${result.state}`]
            connectProc.running = true
        })
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
            // Unchanged since the last read (the usual case): keep the same
            // objects, so nothing bound to them re-evaluates or redraws.
            const calendarsChanged = calendarsOut.text !== root._lastCalendarsText
            if (calendarsChanged) try {
                root._lastCalendarsText = calendarsOut.text
                const map = {}
                const lists = []
                for (const c of JSON.parse(calendarsOut.text)) {
                    map[c.id] = c
                    if (c.holdsTasks && !c.hidden && !c.syncDisabled)
                        lists.push({ id: c.id, name: c.name, color: c.color || "" })
                }
                root._calendars = map
                root.taskLists = lists
            } catch (e) {
                console.warn("CalendarEvents: cannot parse calendars:", e)
            }
            root._calendarsChanged = calendarsChanged
            const a = root._anchor
            const start = new Date(a.getFullYear(), a.getMonth() - 1, 1)
            const end = new Date(a.getFullYear(), a.getMonth() + 2, 1)
            if (start.getTime() !== root.rangeStart.getTime()) root.rangeStart = start
            if (end.getTime() !== root.rangeEnd.getTime()) root.rangeEnd = end
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
                    // Re-indexed only when the events (or the calendars'
                    // colours/visibility) changed: a new eventsByDay redraws
                    // every calendar (sidebar, desktop, bar).
                    if (root._calendarsChanged || eventsOut.text !== root._lastEventsText) {
                        root.eventsByDay = root._index(JSON.parse(eventsOut.text).events ?? [])
                        root._lastEventsText = eventsOut.text
                    }
                    root.available = true
                } catch (e) {
                    console.warn("CalendarEvents: cannot parse events:", e)
                }
            }
            root._finish()
            if (root.available) root.refreshed()
        }
    }

    Process {
        id: callProc
        stdout: StdioCollector {
            id: callOut
        }
        stderr: StdioCollector {
            id: callErr
        }
        onExited: code => {
            const done = root._calls.shift()
            let result = null
            if (code === 0) {
                try {
                    result = JSON.parse(callOut.text)
                } catch (e) {}
            } else {
                console.warn(`CalendarEvents: ${done.args.slice(2, 3)} failed: ${callErr.text.trim()}`)
            }
            if (done.onDone) done.onDone(code === 0, result)
            // Not from inside this process's own exit handler.
            Qt.callLater(root._nextCall)
        }
    }

    // Waits (up to 5 minutes) for the browser to hand the token back.
    Process {
        id: connectProc
        onExited: code => {
            root.connecting = false
            if (code === 0) root.sync()
        }
    }

    Process {
        id: syncProc
        command: [root.dcal, "ipc", "accounts.refresh"]
        onExited: root.refresh()
    }

    // dcal syncs on its own schedule; re-read its copy regularly (unchanged
    // data is dropped above). The sidebar calendar's refresh button syncs
    // right away.
    Timer {
        interval: Math.max(1, Config.options.calendar.refreshMinutes ?? 30) * 60 * 1000
        running: root._started
        repeat: true
        onTriggered: root.refresh()
    }

    // `nixbook-shell ipc call calendar next|upcoming DAYS|day YYYY-MM-DD`:
    // the synced events (DankCalendar), read-only, for key bindings and the
    // desktop MCP server's `calendar` tool. JSON; times in local ISO form.
    function _localIso(d) {
        const pad = n => (n < 10 ? "0" : "") + n
        return `${root.dayKey(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`
    }
    function _eventJson(e, now) {
        const iso = d => e.allDay ? root.dayKey(d) : root._localIso(d)
        return {
            summary: e.summary,
            start: iso(e.start),
            end: iso(e.end),
            allDay: e.allDay,
            when: root.whenText(e, now),
            location: e.location,
            meetingUrl: e.meetingUrl,
            calendar: e.calendarName,
        }
    }
    function _ipcState() {
        if (!root.available)
            return "error: DankCalendar (dcal) isn't running";
        if (!root.hasAccounts)
            return "error: no calendar account connected (connect Google from the calendar widget)";
        return "";
    }

    IpcHandler {
        target: "calendar"

        function next(): string {
            const err = root._ipcState();
            if (err)
                return err;
            const now = new Date();
            const e = root.upcoming(1, now, false)[0];
            return JSON.stringify({ now: root._localIso(now), next: e ? root._eventJson(e, now) : null });
        }
        // The events not over yet from now to the end of the DAYS-th day
        // (1 = today), at most the loaded window (about two months).
        function upcoming(days: int): string {
            const err = root._ipcState();
            if (err)
                return err;
            const now = new Date();
            const n = Math.max(1, Math.min(days, 60));
            const seen = {};
            const out = [];
            const day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
            for (let i = 0; i < n; i++) {
                for (const e of root.eventsOn(day)) {
                    const key = `${e.id}@${e.start.getTime()}`;
                    if (seen[key] || e.end <= now) continue;
                    seen[key] = true;
                    out.push(root._eventJson(e, now));
                }
                day.setDate(day.getDate() + 1);
            }
            return JSON.stringify({ now: root._localIso(now), days: n, loadedUntil: root.dayKey(new Date(root.rangeEnd - 1)), events: out });
        }
        function day(date: string): string {
            const err = root._ipcState();
            if (err)
                return err;
            const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
            if (!m)
                return "error: the date must be YYYY-MM-DD";
            const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
            if (d < root.rangeStart || d >= root.rangeEnd) {
                root.ensureMonth(d);
                return "error: that month isn't loaded yet: ask again in a few seconds";
            }
            const now = new Date();
            return JSON.stringify({ date: root.dayKey(d), events: root.eventsOn(d).map(e => root._eventJson(e, now)) });
        }
    }
}
