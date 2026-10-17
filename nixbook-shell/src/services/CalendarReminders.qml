pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Calendar reminders: a notification (app "Calendar") at each reminder time
 * of the events the shell knows (services/CalendarEvents.qml; each
 * event's reminders, else its calendar's), with Join (a meeting), Snooze
 * (5 minutes) and Open (the Calendar window, on that day). Shown by the
 * shell's notification server: Do Not Disturb silences them, the
 * notification rules can make them a cut-in (`app:^"Calendar"`).
 *
 * The reminders shown are remembered (Directories.state/user/
 * calendar-reminders.json, two days) so a restart doesn't show them again;
 * one missed while the shell wasn't running is shown if at most 10 minutes
 * late.
 */
Singleton {
    id: root

    readonly property int lateMinutes: 10
    readonly property int snoozeMinutes: 5
    readonly property string statePath: `${Directories.state}/user/calendar-reminders.json`
    // "<event id>@<start ms>@<minutes>" -> when it was shown (ms).
    property var shown: ({})
    // The same keys -> when to show again (snoozed).
    property var snoozed: ({})
    property bool _loaded: false

    function load() {
        CalendarEvents.load()
    }

    function _key(e, minutes) {
        return `${e.id}@${e.start.getTime()}@${minutes}`
    }

    function check() {
        if (!root._loaded) return
        const now = new Date()
        const seen = {}
        let changed = false
        for (let i = 0; i < 2; i++) {
            const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i)
            for (const e of CalendarEvents.eventsOn(day)) {
                if (e.end <= now) continue
                for (const minutes of e.reminders ?? []) {
                    const key = root._key(e, minutes)
                    if (seen[key]) continue
                    seen[key] = true
                    const at = e.start.getTime() - minutes * 60000
                    const snooze = root.snoozed[key]
                    if (snooze) {
                        if (now.getTime() < snooze) continue
                        const s = Object.assign({}, root.snoozed)
                        delete s[key]
                        root.snoozed = s
                    } else if (root.shown[key] || now.getTime() < at || now.getTime() - at > root.lateMinutes * 60000) {
                        continue
                    }
                    root.shown[key] = now.getTime()
                    changed = true
                    root._notify(e, key)
                }
            }
        }
        if (changed) root._save()
    }

    // "in 10 min · 14:00 – 15:00 · Room 4", "Now · …", "All day".
    function _body(e) {
        const fmt = Config.options?.time.format ?? "hh:mm"
        const parts = [CalendarEvents.whenText(e, new Date())]
        if (!e.allDay) parts.push(`${Qt.locale().toString(e.start, fmt)} – ${Qt.locale().toString(e.end, fmt)}`)
        if (e.location) parts.push(e.location)
        if (e.calendarName) parts.push(e.calendarName)
        return parts.join(" · ")
    }

    function _notify(e, key) {
        const args = ["notify-send", "--app-name=Calendar", "--icon=x-office-calendar", "--urgency=normal",
            "--expire-time=0", "--wait"]
        if (e.meetingUrl) args.push("--action=join=" + Translation.tr("Join"))
        args.push("--action=snooze=" + Translation.tr("Snooze %1 min").arg(root.snoozeMinutes))
        args.push("--action=open=" + Translation.tr("Open"))
        args.push(e.summary, root._body(e))
        notifier.createObject(root, { event: e, key: key, command: args, running: true })
    }

    // One notification, waiting for its action.
    Component {
        id: notifier
        Process {
            id: proc
            property var event
            property string key
            stdout: StdioCollector {
                id: out
            }
            onExited: {
                const action = out.text.trim()
                if (action === "join") {
                    Qt.openUrlExternally(proc.event.meetingUrl)
                } else if (action === "open") {
                    GlobalStates.openCalendarApp(proc.event.start, null)
                } else if (action === "snooze") {
                    root.snoozed = Object.assign({}, root.snoozed, { [proc.key]: Date.now() + root.snoozeMinutes * 60000 })
                }
                proc.destroy()
            }
        }
    }

    function _save() {
        // Two days kept: older ones can't come back.
        const cutoff = Date.now() - 2 * 24 * 3600 * 1000
        const kept = {}
        for (const k in root.shown)
            if (root.shown[k] > cutoff) kept[k] = root.shown[k]
        root.shown = kept
        stateFile.setText(JSON.stringify(kept))
    }

    Timer {
        interval: 30000
        running: root._loaded
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
    Connections {
        target: CalendarEvents
        function onRefreshed() {
            root.check()
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                root.shown = JSON.parse(stateFile.text()) ?? {}
            } catch (e) {
                root.shown = {}
            }
            root._loaded = true
        }
        onLoadFailed: {
            root.shown = {}
            root._loaded = true
        }
    }
}
