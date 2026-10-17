pragma Singleton
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Calendar events from every account (services/Accounts.qml: Google,
 * CalDAV), through `nixbook-accounts`, for every calendar in the shell
 * (sidebar, desktop widget, bar clock popup, next-event widgets), the
 * Calendar window (modules/ii/calendarApp/) and the reminders
 * (services/CalendarReminders.qml).
 *
 * nixbook-accounts keeps each account's events in its local copy
 * ($XDG_STATE_HOME/nixbook-accounts/events.json, watched) and expands
 * recurring series for the window asked (`calendar events`); this reads
 * that window around the month shown, and asks it to sync (at start, every
 * `calendar.refreshMinutes`, on demand). Changes (`apply`) go to the
 * event's account first.
 */
Singleton {
    id: root

    // Some account with calendars added.
    readonly property bool available: Accounts.statusKnown && Accounts.accounts.some(a => a.calendar)
    property bool loading: false
    property bool syncing: false
    // "YYYY-MM-DD" (local) -> events on that day, all-day ones first, then
    // by start. Each event: { id (the event or its series), occurrence (a
    // series' occurrence's original start, "" for a single event), recurring,
    // summary, description, location, meetingUrl, start, end (Date), allDay,
    // color, calendarName, calendarId, account, readOnly, reminders (minutes
    // before) }.
    property var eventsByDay: ({})
    // Loaded window: from the first day of the month before `anchor` to
    // the end of the second month after it.
    property var rangeStart: new Date(0)
    property var rangeEnd: new Date(0)
    // [{ id, account, name, color, primary, readOnly, defaultReminders }]
    property var calendars: []
    readonly property var writableCalendars: root.calendars.filter(c => !c.readOnly)
    // Some calendar synced: some account has calendars.
    readonly property bool hasAccounts: root.calendars.length > 0
    // An account being signed in (Accounts').
    readonly property bool connecting: Accounts.connecting
    // The last change that failed ({ message, at }), for the Calendar
    // window's message bar; null when none. `error` is the last sync's.
    property var lastError: null
    property string error: ""

    // After each successful reload.
    signal refreshed()

    property var _anchor: new Date()
    property bool _started: false
    // A refresh asked for while one runs (e.g. month navigation): run it
    // once the current one ends, so its window isn't lost.
    property bool _pending: false
    property string _lastText: ""

    readonly property string cachePath: {
        const state = Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
        return `${state}/nixbook-accounts/events.json`
    }

    function load() {
        if (root._started) return
        root._started = true
        Accounts.load()
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

    // Reload around `date` when it falls outside the loaded window (month
    // navigation).
    function ensureMonth(date) {
        const first = new Date(date.getFullYear(), date.getMonth(), 1)
        const last = new Date(date.getFullYear(), date.getMonth() + 1, 1)
        if (first < root.rangeStart || last > root.rangeEnd) {
            root._anchor = first
            root.refresh()
        }
    }

    // `YYYY-MM-DDTHH:MM` (local) for nixbook-accounts.
    function localIso(d) {
        const pad = n => (n < 10 ? "0" : "") + n
        return `${root.dayKey(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`
    }

    // The loaded window read again from the copy.
    function refresh() {
        if (!root._started) return
        if (root.loading) {
            root._pending = true
            return
        }
        const a = root._anchor
        const start = new Date(a.getFullYear(), a.getMonth() - 1, 1)
        const end = new Date(a.getFullYear(), a.getMonth() + 2, 1)
        root.loading = true
        Accounts.call(["calendar", "events", "--from", root.dayKey(start), "--to", root.dayKey(end)], (ok, result) => {
            root.loading = false
            if (ok && result) {
                if (start.getTime() !== root.rangeStart.getTime()) root.rangeStart = start
                if (end.getTime() !== root.rangeEnd.getTime()) root.rangeEnd = end
                // Re-indexed only when something changed: a new eventsByDay
                // redraws every calendar (sidebar, desktop, bar).
                const text = JSON.stringify([result.events, result.calendars])
                if (text !== root._lastText) {
                    root._lastText = text
                    root.calendars = result.calendars ?? []
                    root.eventsByDay = root._index(result.events ?? [])
                }
                root.error = result.error ?? ""
                root.refreshed()
            }
            if (root._pending) {
                root._pending = false
                Qt.callLater(root.refresh)
            }
        }, "calendar")
    }

    // Every account's changes now, then reload.
    function sync() {
        if (root.syncing || !Accounts.connected) return
        root.syncing = true
        Accounts.call(["calendar", "sync"], () => {
            root.syncing = false
            root.refresh()
        }, "calendar")
    }

    // The Calendar window (events, day by day; the editor).
    function openApp() {
        GlobalStates.openCalendarApp(null, null)
    }

    // Its new-event editor, starting at `date` (a Date; default: the next
    // half hour).
    function newEvent(date) {
        GlobalStates.openCalendarApp(date ?? null, "new")
    }

    // Adding an account (Accounts').
    function connectGoogle() {
        Accounts.connect()
    }

    // Changes ({ op: create | update | delete, … } or a list); onDone(results)
    // with [{ ok, result | error }], a failure also in lastError.
    function apply(ops, onDone) {
        const request = Array.isArray(ops) ? { ops: ops } : ops
        Accounts.call(["calendar", "apply", JSON.stringify(request)], (ok, result, error) => {
            const results = ok && Array.isArray(result) ? result : [{ ok: false, error: error }]
            const failed = results.find(r => !r.ok)
            root.lastError = failed ? { message: failed.error, at: Date.now() } : null
            root.refresh()
            if (onDone) onDone(results)
        }, "calendar")
    }

    // All-day events are dates, their end exclusive.
    function _day(s) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
        return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(s)
    }

    function _index(events) {
        const byDay = {}
        for (const e of events) {
            const allDay = !!e.allDay
            const start = allDay ? root._day(e.start) : new Date(e.start)
            let end = allDay ? root._day(e.end) : new Date(e.end)
            if (allDay && end <= start) end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1)
            const item = {
                id: e.id,
                occurrence: e.occurrence ?? "",
                recurring: !!e.recurring,
                summary: e.summary || Translation.tr("(No title)"),
                description: e.description ?? "",
                location: e.location ?? "",
                meetingUrl: e.meetingUrl ?? "",
                start: start,
                end: end,
                allDay: allDay,
                color: e.color || "",
                calendarName: e.calendar ?? "",
                calendarId: e.calendarId,
                account: e.account,
                readOnly: !!e.readOnly,
                reminders: e.reminders ?? [],
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

    // Accounts known (at start): sync; one added synced already, one removed
    // is gone from the copy: read it.
    Connections {
        target: Accounts
        function onConnectedChanged() {
            if (Accounts.connected && root._started) root.sync()
        }
        function onAdded() {
            root.refresh()
        }
        function onAccountsChanged() {
            root.refresh()
        }
    }

    // The copy changed (a sync, an agent's change): read the window again.
    FileView {
        path: root._started ? root.cachePath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }

    // Sync regularly; the sidebar calendar's refresh button syncs now.
    Timer {
        interval: Math.max(1, Config.options.calendar.refreshMinutes ?? 30) * 60 * 1000
        running: root._started && Accounts.connected
        repeat: true
        onTriggered: root.sync()
    }

    // `nixbook-shell ipc call calendar next|upcoming DAYS|day YYYY-MM-DD`:
    // the synced events, read-only, for key bindings and the desktop MCP
    // server's `calendar` tool. JSON; times in local ISO form.
    function _localIso(d) {
        return root.localIso(d)
    }
    function _eventJson(e, now) {
        const iso = d => e.allDay ? root.dayKey(d) : root._localIso(d)
        return {
            id: e.id,
            occurrence: e.occurrence || undefined,
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
        if (!Accounts.connected)
            return "error: no account connected (add one in the accounts window)";
        if (!root.hasAccounts)
            return "error: no calendar yet: the accounts are syncing, or have none";
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
        // The Calendar window, on today.
        function launch(): string {
            root.load();
            GlobalStates.openCalendarApp(null, null);
            return "ok: opened the Calendar window";
        }
        // The Calendar window (on that day, YYYY-MM-DD, or today).
        function open(date: string): string {
            root.load();
            const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
            GlobalStates.openCalendarApp(m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null, null);
            return "ok: opened the Calendar window";
        }
    }
}
