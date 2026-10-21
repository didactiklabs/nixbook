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
 *   - happened (ai.initiative.reactions, off by default): what the user
 *     just did (a download, a screenshot, a drive), with one-click help.
 * What it says comes out loud (`speaking`: its own bubble on the left,
 * AgentSpeech.qml) or waits in the bar (`pending`: the robot's bubble),
 * until it expires. The bubble is a small chat: the user answers in it and
 * Claude answers there (`chat`, a thread of its own, the side panel's "From
 * Claude" tab, opened there only on expand()); the answer teaches it what
 * the user values. Mod+C calls the bubble up to ask anything.
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
    // Read: what the user has seen in the bubble (hovered, answered, closed
    // or opened from the bar), by id. Still there, but the bar's bubble only
    // lights up for what they haven't.
    property var _read: ({})
    readonly property var unread: root.live.filter(p => !root._read[p.id])

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

    // Curiosity (ai.initiative.curious): it watches what is in front (app and
    // window title, every few minutes) and learns what the user does from it,
    // saying what it learned; the reply corrects or completes it.
    readonly property bool curious: Config.options?.ai?.initiative?.curious ?? false
    readonly property string learnHint: "You said this from watching what the user does, to learn about them. "
        + "If they correct what you noticed or tell you more, update your memory of them (recall_about_user, then "
        + "remember_about_user with the entry's id; forget_about_user what was wrong), briefly. If you offered help "
        + "and they want it, do it now with your tools (look at their screen first if needed); then answer naturally."
    // Reactions (ai.initiative.reactions): what the user just did (a file
    // downloaded, a screenshot, a drive plugged in), offered at once with
    // buttons that act in one click (services/Routines.qml sees them).
    readonly property bool reactions: Config.options?.ai?.initiative?.reactions ?? false
    readonly property var reactTo: ["download", "screenshot", "drive_connected"]

    // What it says out loud now (modules/ii/notificationPopup/AgentSpeech.qml,
    // on the left under the bar): one at a time, the one before to the bar.
    // {id, kind, text, chat?, accept?, actions?}; kind "ask" (the user
    // called it: Mod+C) and "done" (a chat of the side panel
    // answered while it was closed) have no id: nothing to learn from.
    property var speaking: null
    // The conversation in the bubble (an AiChatSession): Claude's own thread
    // (Ai.claudeThread, the side panel's "From Claude" tab) once the user
    // answers in the bubble, or the panel's tab whose answer it shows. The
    // bubble is the chat: the panel only when asked (expand()).
    property var chat: null
    readonly property bool conversing: root.chat !== null && (root.chat.messageIDs ?? []).some(id => root.chat.messageByID[id]?.role === "user")
    // Put away with its conversation (closed, or left a while): the bar's
    // bubble brings it back, and so does Claude's next answer in it.
    // {item, chat, unread}: unread once Claude answered in it put away (not
    // brought back then: the user busy), so the bar's bubble lights up.
    property var parked: null
    readonly property bool thinking: (root.chat?.responding ?? false) || (root.parked?.chat?.responding ?? false)
    // The user is writing in the bubble: nothing takes its place meanwhile.
    property bool typing: false
    // The bubble's field wants the keys (it was called up with the keyboard).
    signal focusWanted()
    property string _answeredId: ""

    // Shows it in the bubble (the bar's bubble, a word waiting).
    function open(item) {
        if (!item) return
        root.markRead(item)
        if (root.speaking && root.speaking === item) return
        root._notify(item)
    }
    function openLatest() {
        if (root.parked) root.resume()
        else root.open(root.live[root.live.length - 1])
    }
    // Settings > Say something now: a light word at once, to try it.
    function sayNow() {
        root.consider({ event: "moment", force: true, curious: root.curious, app: ToplevelManager.activeToplevel?.appId ?? "",
                        title: root.curious ? (ToplevelManager.activeToplevel?.title ?? "") : "",
                        activeMinutes: Math.round((Date.now() - root._activeSince) / 60000),
                        tasksDue: Todo.dueTodayCount, weatherCode: Weather.data?.wCode ?? 0,
                        weather: Weather.data?.description ?? "" })
    }
    // Called up (Mod+C, the bar's robot): its bubble, to ask
    // anything; the conversation put away comes back instead.
    function summon() {
        if (root.parked && !root.speaking) root.resume()
        else if (!root.speaking) root.speaking = root._ask()
        root.focusWanted()
    }
    // Mod+C, the robot's middle-click: called up, or put away when shown.
    function toggle() {
        if (root.speaking) root.hush("wait")
        else root.summon()
    }
    function _ask() {
        return { id: "", kind: "ask", text: root._pick([Translation.tr("What can I do for you?"),
            Translation.tr("I'm here. What do you need?"), Translation.tr("Yes? Ask me anything.")]) }
    }
    // Its threads (the "From Claude" ones of the history), newest first, to
    // go back to one in the bubble.
    readonly property var threads: Ai.history.filter(c => c.fromClaude).slice(0, 8)
    function openThread(id) {
        let chat = Ai.chats.find(c => c.chatId === id)
        if (!chat) {
            if (root.chat?.chatId === id) chat = root.chat
            else {
                chat = Ai.claudeThread(false)
                if (!Ai.openChatIn(chat, id)) return
            }
        }
        if (root.parked?.chat === chat) root.parked = null
        if (root.chat !== chat) root._aside()
        root.chat = chat
        root.speaking = { id: "", kind: "done", text: "", title: Ai.history.find(c => c.id === id)?.title ?? "" }
    }
    // A new conversation in the bubble (its new-chat button, /new or
    // /clear): the one before is left as it is, in the side panel's history
    // (the next message's thread saves it, Ai.claudeThread); one still
    // answering goes on in its tab.
    function fresh() {
        const before = root.chat
        if (before && !root.conversing && before.fromClaude && !before.responding) before.clearMessages()
        if (root.parked?.chat === before) root.parked = null
        root.chat = null
        root.speaking = root._ask()
        root.focusWanted()
    }
    // The user saw it (the bubble hovered, typed in, closed).
    function markRead(item) {
        const it = item ?? root.speaking
        if (it?.id && !root._read[it.id]) root._read = Object.assign({}, root._read, { [it.id]: true })
    }
    function _pick(list) {
        return list[Math.floor(Math.random() * list.length)]
    }

    // The conversation with what it said as Claude's first message, in its
    // own thread (the "From Claude" tab, not selected): made when the user
    // starts typing, so Claude Code is warm by the time they send.
    function prepare() {
        const item = root.speaking
        if (root.chat || !item) return
        const thread = Ai.claudeThread(false)
        if (item.kind !== "ask")
            thread.addMessage(item.chat || item.text, "assistant", true, item.curious ? root.learnHint : "")
        root.chat = thread
        if ((Ai.models[Ai.currentModelId]?.api_format ?? "") === "claude-code" && Ai.claudeCodePath.length > 0)
            thread.prewarm()
    }
    // What it said, taken up: counted once, and the talk that follows too.
    function _taken(item) {
        if (!item?.id || root._answeredId === item.id) return
        root._answeredId = item.id
        root.markRead(item)
        root._opened = { id: item.id, time: Date.now() }
        root.answer(item.id, "replied")
    }
    // The user's answer, in the bubble: Claude answers there.
    function reply(text, attach) {
        const said = String(text ?? "").trim()
        if (said.length === 0) return
        const item = root.speaking
        if (!root.chat) root.prepare()
        if (!root.chat) return
        root._taken(item)
        if (attach) root.chat.attachFile(attach)
        root.chat.sendUserMessage(said)
    }
    // A routine it offered: "Yes, do it" turns it on.
    function accept() {
        const item = root.speaking
        if (!item?.accept) return
        root.speaking = null
        root.answer(item.id, "replied")
    }
    // A button of a reaction: open the file, show it in its folder, or ask
    // Claude about it (in the bubble, the file attached).
    function act(a) {
        const item = root.speaking
        if (!a || !item) return
        if (a.do === "ask") {
            root.reply(a.text, a.attach ?? "")
            return
        }
        const path = String(a.path ?? "")
        if (!path.startsWith("/")) return
        if (a.do === "open") Quickshell.execDetached(["xdg-open", path])
        else if (a.do === "reveal") {
            // The file manager with the file selected, else its folder.
            const uri = "file://" + path.split("/").map(encodeURIComponent).join("/")
            Quickshell.execDetached(["bash", "-c", 'dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 '
                + '/org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:"$1" string:"" >/dev/null 2>&1 '
                + '|| xdg-open "$(dirname "$2")"', "reveal", uri, path])
        }
        root._taken(item)
        root.speaking = null
    }
    // The conversation (or what it said) in the side panel, for more room.
    function expand() {
        const item = root.speaking
        if (!root.chat && item) {
            const thread = Ai.claudeThread()
            if (item.kind !== "ask")
                thread.addMessage(item.chat || item.text, "assistant", true, item.curious ? root.learnHint : "")
            root.chat = thread
        }
        if (root.chat) Ai.selectChat(root.chat)
        root._taken(item)
        root.speaking = null
        root.chat = null
        root.typing = false
        GlobalStates.sidebarLeftOpen = true
        GlobalStates.aiChatRequested()
    }
    // The conversation put away, to the bar's bubble; brought back.
    function park() {
        if (!root.conversing) return
        root.parked = { item: root.speaking, chat: root.chat, unread: false }
        root.speaking = null
        root.chat = null
        root.typing = false
    }
    function resume() {
        const p = root.parked
        if (!p) return
        root._aside()
        root.parked = null
        root.chat = p.chat
        root.speaking = p.item ?? { id: "", kind: "done", text: "" }
    }
    // Whether the bubble holds this chat, now or put away.
    function holds(c) {
        return c !== null && (root.chat === c || root.parked?.chat === c)
    }
    // Claude answered in a conversation of the bubble: one put away comes
    // back to say it (not while the user is busy: the bar's bubble then).
    function chatAnswered(c) {
        if (root.parked?.chat !== c) return
        if (!root.speaking && !root.busy()) root.resume()
        else if (!root.parked.unread) root.parked = Object.assign({}, root.parked, { unread: true })
    }
    // A chat of the side panel answered while it is closed: said in the
    // bubble, to answer there. False when the bubble is taken.
    function chatDone(c) {
        if (root.typing || (root.speaking && root.chat?.responding)) return false
        root._aside()
        root.chat = c
        root.speaking = { id: "", kind: "done", text: "", title: Ai.chats.length > 1 ? c.title : "" }
        return true
    }
    // What the bubble shows now goes aside for something new: a
    // conversation put away, a word to the bar.
    function _aside() {
        const before = root.speaking
        if (root.conversing) root.park()
        else if (before) {
            if (root.chat && root.chat.fromClaude && !root.chat.responding) root.chat.clearMessages()
            if (before.id) root.pending = [...root.pending.filter(p => p.id !== before.id), before]
        }
        root.speaking = null
        root.chat = null
        root.typing = false
    }
    function _notify(item) {
        root._aside()
        root.speaking = item
    }
    // Something new to say: not over what the user is writing or talking
    // about in the bubble (to the bar then).
    function _say(item) {
        if (root.typing || (root.conversing && root.speaking)) root.pending = [...root.pending, item]
        else root._notify(item)
    }
    // Its speech answered without a reply: later, never, or "wait" (no
    // answer: to the bar's bubble). A conversation is put away instead.
    function hush(outcome) {
        const item = root.speaking
        if (!item) return
        if (root.conversing) {
            root.park()
            return
        }
        root._aside()
        if (outcome !== "wait" && item.id) root.answer(item.id, outcome)
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
                    if (answer.action === "notify") root._say(answer.item)
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
            if (root.enabled)
                Quickshell.execDetached(["nixbook-desktop-mcp", "initiative", "notices", JSON.stringify(seen)])
        }
    }

    // What the user just did, to lend a hand with (reactions): not what an
    // agent did (its downloads, its screenshots).
    Connections {
        target: Routines
        function onHappened(ev) {
            if (!root.enabled || !root.reactions || !root.reactTo.includes(ev.event) || !ev.path || DesktopControl.active) return
            root.consider({ event: "happened", what: ev.event, name: ev.name ?? "", path: ev.path })
        }
    }

    // `nixbook-shell ipc call claude toggle` (Mod+C): its bubble, to ask, or
    // put away; `ask`: always called up.
    IpcHandler {
        target: "claude"
        function ask(): void {
            root.summon()
        }
        function toggle(): void {
            root.toggle()
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
            // The switch may have gone off while the batch waited.
            if (items.length > 0 && root.enabled && root.readNotifications)
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
