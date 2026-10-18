pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick

/**
 * The desktop agent speaking first (ai.initiative): when something happens
 * it can help with, not on a schedule. This hands what happens to
 * `nixbook-desktop-mcp initiative consider` (plain code decides whether a
 * word is worth it, the user's past answers, their being busy, the day's
 * budget; a small model only reads notifications):
 *   - back: the screens come on, or the session unlocks, after a while;
 *   - focus: an app gets the focus (at most every few minutes);
 *   - notifications (ai.initiative.readNotifications, off by default):
 *     what came in, in batches;
 *   - moment: now and then, at random (40 minutes to 2 hours apart while
 *     the user is at the computer), a chance for a light word: most of the
 *     time nothing is said, at most a couple a day, only in the bar.
 * What it says comes as a notification from "Claude" (Reply, Not now,
 * Don't) or waits in the bar (`pending`: the robot's bubble), until it
 * expires. Reply opens the side panel's chat with it as Claude's message, so
 * the user just answers; the answer teaches it what the user values.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.ai?.initiative?.enable ?? false
    readonly property bool readNotifications: Config.options?.ai?.initiative?.readNotifications ?? false
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/initiative.json`
    // What waits for the user, newest last: {id, kind, text, chat, time, expires}.
    property var pending: []
    property real now: Date.now()
    readonly property var live: root.pending.filter(p => (p.expires ?? 0) * 1000 > root.now)

    property var _batch: []
    property real _awaySince: 0
    // At the computer since (back from the last break).
    property real _activeSince: Date.now()
    property real _lastFocus: 0
    property string _lastApp: ""

    function load() {
        stateFile.reload()
    }

    // Busy: not to be interrupted (Do Not Disturb, a meeting now, a
    // fullscreen window, the screens off): what it has to say then waits.
    function busy() {
        if (Notifications.silent || GlobalStates.screenLocked || Idle.screensOff) return true
        const t = new Date()
        if (CalendarEvents.eventsOn(t).some(e => !e.allDay && e.start <= t && e.end > t)) return true
        const mon = WM.focusedMonitor?.name ?? ""
        return mon !== "" && WM.fullscreenOnMonitor(mon)
    }

    function _nextEvent() {
        const e = CalendarEvents.upcoming(1, new Date(), true)[0]
        return e ? `${e.summary} ${CalendarEvents.whenText(e, new Date())}` : ""
    }

    function consider(event) {
        if (!root.enabled) return
        event.busy = root.busy()
        considerer.createObject(root, { command: ["nixbook-desktop-mcp", "initiative", "consider", JSON.stringify(event)], running: true })
    }

    function back(awayMinutes) {
        const t = new Date()
        const fmt = Config.options?.time.format ?? "hh:mm"
        const events = CalendarEvents.upcoming(4, t).filter(e => e.allDay || e.start.toDateString() === t.toDateString())
            .map(e => ({ title: e.summary, start: e.allDay ? "" : Qt.locale().toString(e.start, fmt), allDay: e.allDay,
                         inMinutes: e.allDay ? null : Math.round((e.start - t) / 60000) }))
        root.consider({ event: "back", away: Math.round(awayMinutes), events: events, tasksDue: Todo.dueTodayCount,
                        open: WM.windowList.map(w => w.appId) })
    }

    // Opens what it said in the side panel's chat, as Claude's message.
    function open(item) {
        if (!item) return
        Ai.newChat()
        Ai.addMessage(item.chat || item.text, "assistant")
        GlobalStates.sidebarLeftOpen = true
        GlobalStates.aiChatRequested()
        root.answer(item.id, "replied")
    }
    function openLatest() {
        root.open(root.live[root.live.length - 1])
    }
    function answer(id, outcome) {
        if (!/^[0-9a-f]{1,16}$/.test(id ?? "")) return
        root.pending = root.pending.filter(p => p.id !== id)
        Quickshell.execDetached(["nixbook-desktop-mcp", "initiative", "answer", id, outcome])
    }

    function _notify(item) {
        notifier.createObject(root, { item: item, running: true, command: ["notify-send", "--app-name=Claude",
            "--icon=smart_toy", "--urgency=normal", "--wait",
            "--action=reply=" + Translation.tr("Reply"), "--action=later=" + Translation.tr("Not now"),
            "--action=never=" + Translation.tr("Don't tell me this"), item.title || "Claude", item.text] })
    }

    function _urgency(n) {
        const u = n.urgency
        return (u == NotificationUrgency.Critical || u === "critical") ? "critical"
            : (u == NotificationUrgency.Low || u === "low") ? "low" : "normal"
    }

    Component {
        id: considerer
        Process {
            id: proc
            stdout: StdioCollector { id: out }
            onExited: {
                try {
                    const answer = JSON.parse(out.text)
                    if (answer.action === "notify") root._notify(answer.item)
                    if (answer.action === "badge") root.pending = [...root.pending, answer.item]
                } catch (e) {
                    // Nothing to say, or the server is missing: silence.
                }
                proc.destroy()
            }
        }
    }

    Component {
        id: notifier
        Process {
            id: notifyProc
            property var item
            stdout: StdioCollector { id: chosen }
            onExited: {
                const action = chosen.text.trim()
                if (action === "reply") root.open(notifyProc.item)
                else if (action === "never") root.answer(notifyProc.item.id, "never")
                else if (action === "later") root.answer(notifyProc.item.id, "later")
                // Closed or expired: it waits in the bar a while instead.
                else root.pending = [...root.pending.filter(p => p.id !== notifyProc.item.id), notifyProc.item]
                notifyProc.destroy()
            }
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.pending = JSON.parse(stateFile.text()).pending ?? []
            } catch (e) {
                root.pending = []
            }
        }
    }

    // Notifications, in batches: a burst is read once.
    Connections {
        target: Notifications
        function onNotify(n) {
            if (!root.enabled || !root.readNotifications) return
            root._batch = [...root._batch, { app: n.appName, summary: n.summary, body: n.body, urgency: root._urgency(n) }].slice(-12)
            if (!batchTimer.running) batchTimer.start()
        }
    }
    Timer {
        id: batchTimer
        interval: 45000
        onTriggered: {
            const items = root._batch
            root._batch = []
            if (items.length > 0)
                root.consider({ event: "notifications", read: true, items: items,
                                focused: ToplevelManager.activeToplevel?.appId ?? "", next: root._nextEvent() })
        }
    }

    // Back after a while: the screens come on again, or the session unlocks.
    Connections {
        target: Idle
        function onScreensOffChanged() {
            if (Idle.screensOff) root._awaySince = Date.now()
            else if (root._awaySince > 0 && !GlobalStates.screenLocked) {
                root.back((Date.now() - root._awaySince) / 60000)
                root._awaySince = 0
                root._activeSince = Date.now()
            }
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                if (root._awaySince === 0) root._awaySince = Date.now()
            } else if (root._awaySince > 0) {
                root.back((Date.now() - root._awaySince) / 60000)
                root._awaySince = 0
                root._activeSince = Date.now()
            }
        }
    }

    // A new app in front: once per app, every few minutes at most.
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const app = ToplevelManager.activeToplevel?.appId ?? ""
            if (!app || app === root._lastApp || Date.now() - root._lastFocus < 180000) return
            root._lastApp = app
            root._lastFocus = Date.now()
            root.consider({ event: "focus", app: app })
        }
    }

    // Now and then, at random, a chance for a light word.
    Timer {
        id: momentTimer
        running: root.enabled
        interval: root._nextMoment()
        repeat: true
        onTriggered: {
            interval = root._nextMoment()
            if (Idle.screensOff || GlobalStates.screenLocked) return
            root.consider({ event: "moment", app: ToplevelManager.activeToplevel?.appId ?? "",
                            activeMinutes: Math.round((Date.now() - root._activeSince) / 60000),
                            tasksDue: Todo.dueTodayCount, weatherCode: Weather.data?.wCode ?? 0,
                            weather: Weather.data?.description ?? "" })
        }
    }
    function _nextMoment() {
        return (40 + Math.random() * 80) * 60000
    }

    // The first start of the day counts as coming back.
    Timer {
        interval: 20000
        running: root.enabled
        onTriggered: root.back(0)
    }
    Timer {
        interval: 60000
        running: root.live.length > 0
        repeat: true
        onTriggered: root.now = Date.now()
    }
}
