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
 * What it says comes out loud (`speaking`: its own bubble on the left,
 * AgentSpeech.qml, with Reply, Not now, Don't) or waits in the bar
 * (`pending`: the robot's bubble), until it expires. Reply opens the side
 * panel's "From Claude" tab with it as Claude's message, in a thread of its
 * own, so the user just answers; the answer teaches it what the user values.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.ai?.initiative?.enable ?? false
    readonly property bool readNotifications: Config.options?.ai?.initiative?.readNotifications ?? false
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/initiative.json`
    // What waits for the user, newest last: {id, kind, text, chat, time, expires}
    // (what it says out loud too: the bar shows it once its bubble goes).
    property var pending: []
    // Its last decisions, newest last: {time, event, action, said, why}.
    property var log: []
    property real now: Date.now()
    readonly property var live: root.pending.filter(p => (p.expires ?? 0) * 1000 > root.now && p.id !== root.speaking?.id)

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
        event.busy = event.force === true ? false : root.busy()
        // The shell's PATH may not have Claude Code: its own, for the small model.
        if (Ai.claudeCodePath.length > 0) event.claude = Ai.claudeCodePath
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

    // Opens what it said in the side panel's chat, as Claude's message; a
    // routine offered (`accept`) is shown first in its speech bubble (what
    // it would do, Yes, do it), and turned on by that Yes.
    // Curiosity (ai.initiative.curious): it watches what is in front (app and
    // window title, every few minutes) and learns what the user does from it,
    // saying what it learned; the reply corrects or completes it.
    readonly property bool curious: Config.options?.ai?.initiative?.curious ?? false
    readonly property string learnHint: "You said this from watching what the user does, to learn about them. "
        + "If they correct what you noticed or tell you more, update your memory of them (recall_about_user, then "
        + "remember_about_user with the entry's id; forget_about_user what was wrong), briefly. If you offered help "
        + "and they want it, do it now with your tools (look at their screen first if needed); then answer naturally."
    function open(item) {
        if (!item) return
        if (item.accept && root.speaking?.id !== item.id) {
            root._notify(item)
            return
        }
        if (root.speaking?.id === item.id) root.speaking = null
        if (item.accept) {
            root.answer(item.id, "replied")
            return
        }
        root._opened = { id: item.id, time: Date.now() }
        const thread = Ai.claudeThread()
        thread.addMessage(item.chat || item.text, "assistant", true, item.curious ? root.learnHint : "")
        Ai.saveHistory(thread)
        GlobalStates.sidebarLeftOpen = true
        GlobalStates.aiChatRequested()
        root.answer(item.id, "replied")
    }
    // Settings > Say something now: a light word at once, to try it.
    function sayNow() {
        root.consider({ event: "moment", force: true, curious: root.curious, app: ToplevelManager.activeToplevel?.appId ?? "",
                        title: root.curious ? (ToplevelManager.activeToplevel?.title ?? "") : "",
                        activeMinutes: Math.round((Date.now() - root._activeSince) / 60000),
                        tasksDue: Todo.dueTodayCount, weatherCode: Weather.data?.wCode ?? 0,
                        weather: Weather.data?.description ?? "" })
    }
    function openLatest() {
        root.open(root.live[root.live.length - 1])
    }
    // The conversation it opened goes on: worth more than a one-word reply.
    property var _opened: null
    function engaged() {
        if (root._opened && Date.now() - root._opened.time < 1800000)
            Quickshell.execDetached(["nixbook-desktop-mcp", "initiative", "answer", root._opened.id, "engaged"])
    }
    function answer(id, outcome) {
        if (!/^[0-9a-f]{1,16}$/.test(id ?? "")) return
        root.pending = root.pending.filter(p => p.id !== id)
        Quickshell.execDetached(["nixbook-desktop-mcp", "initiative", "answer", id, outcome])
    }

    // What it says out loud now (modules/ii/notificationPopup/AgentSpeech.qml,
    // on the left under the bar): one at a time, the one before to the bar.
    property var speaking: null
    function _notify(item) {
        const before = root.speaking
        if (before) root.pending = [...root.pending.filter(p => p.id !== before.id), before]
        root.speaking = item
    }
    // Its speech answered without a reply: later, never, or "wait" (no
    // answer: to the bar's bubble).
    function hush(outcome) {
        const item = root.speaking
        if (!item) return
        root.speaking = null
        if (outcome === "wait") root.pending = [...root.pending.filter(p => p.id !== item.id), item]
        else root.answer(item.id, outcome)
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

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(stateFile.text())
                root.pending = data.pending ?? []
                root.log = data.log ?? []
            } catch (e) {
                root.pending = []
                root.log = []
            }
        }
    }

    // What the user does with their notifications, sent every few minutes:
    // the apps they act on, the ones they dismiss.
    property var _seen: ({})
    function _count(app, what) {
        if (!root.enabled || !app) return
        const c = root._seen[app] ?? { acted: 0, dismissed: 0 }
        c[what] += 1
        root._seen = Object.assign({}, root._seen, { [app]: c })
        if (!seenTimer.running) seenTimer.start()
    }
    Connections {
        target: Notifications
        function onActed(app) { root._count(app, "acted") }
        function onDismissed(app) { root._count(app, "dismissed") }
    }
    Timer {
        id: seenTimer
        interval: 300000
        onTriggered: {
            const seen = root._seen
            root._seen = {}
            Quickshell.execDetached(["nixbook-desktop-mcp", "initiative", "notices", JSON.stringify(seen)])
        }
    }

    // Notifications, in batches: a burst is read once.
    Connections {
        target: Notifications
        function onNotify(n) {
            if (!root.enabled || !root.readNotifications) return
            // Not while away (locked) or on Do Not Disturb: nobody to tell,
            // and what comes then isn't read by the model either.
            if (GlobalStates.screenLocked || Notifications.silent) return
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
        // Asks every few minutes; when a light word is due (40 to 120 minutes
        // apart, at random) is kept by nixbook-desktop-mcp, so a shell
        // restart doesn't start the wait over.
        running: root.enabled
        interval: 5 * 60000
        repeat: true
        onTriggered: {
            if (Idle.screensOff || GlobalStates.screenLocked) return
            root.consider({ event: "moment", curious: root.curious, app: ToplevelManager.activeToplevel?.appId ?? "",
                        title: root.curious ? (ToplevelManager.activeToplevel?.title ?? "") : "",
                            activeMinutes: Math.round((Date.now() - root._activeSince) / 60000),
                            tasksDue: Todo.dueTodayCount, weatherCode: Weather.data?.wCode ?? 0,
                            weather: Weather.data?.description ?? "" })
        }
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
