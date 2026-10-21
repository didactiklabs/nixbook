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

    // policies.ai: 1 (online models) only; Claude is one.
    readonly property bool enabled: (Config.options?.ai?.initiative?.enable ?? false) && (Config.options?.policies?.ai ?? 1) === 1
    readonly property bool readNotifications: Config.options?.ai?.initiative?.readNotifications ?? false
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/initiative.json`
    // What waits for the user, newest last: {id, kind, text, chat, time, expires}
    // (what it says out loud too: the bar shows it once its bubble goes).
    property var pending: []
    // Its last decisions, newest last: {time, event, action, said, why}.
    property var log: []
    property real now: Date.now()
    readonly property var live: root.pending.filter(p => (p.expires ?? 0) * 1000 > root.now && p.id !== root.speaking?.id
        && !root.stack.some(q => q.id === p.id))
    // Its other words while the bubble is taken, newest last: small bubbles
    // under it, like notifications (AgentSpeech.qml). Only the bubble holds
    // a conversation (and only it comes back from the bar or Mod+C); a small
    // one is opened into it with a click. One that waits for an answer (a
    // question, a Yes, buttons: `waits`) stays until it expires; the others
    // go to the bar after a while (`unstack`).
    property var stack: []
    readonly property int stackMax: 3
    readonly property var stacked: root.stack.filter(p => (p.expires ?? 0) * 1000 > root.now && p.id !== root.speaking?.id)
    function waits(item) {
        return !!item && (!!item.accept || (item.actions ?? []).length > 0 || /[?？]\s*$/.test(item.text ?? ""))
    }
    function _stackPush(item) {
        if (!item?.id) return
        root.stack = [...root.stack.filter(p => p.id !== item.id), item].slice(-root.stackMax)
    }
    // To the bar (still there, answered later).
    function unstack(item) {
        root.stack = root.stack.filter(p => p.id !== item?.id)
    }
    // Closed (its x): seen, not taken up, as "Not now" in the bubble.
    function dismissStacked(item, outcome) {
        root.unstack(item)
        root.markRead(item)
        if (item?.id) root.answer(item.id, outcome ?? "later")
    }
    // Read: what the user has seen in the bubble (hovered, answered, closed
    // or opened from the bar), by id. Still there, but the bar's bubble only
    // lights up for what they haven't, and for a routine it offered until
    // they answer it (its Yes is there).
    property var _read: ({})
    readonly property var unread: root.live.filter(p => p.accept || !root._read[p.id])

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
        const what = event.force !== true ? "" : event.event === "news" ? "news" : "say"
        if (what !== "") root._askNow(what)
        considerer.createObject(root, { command: ["nixbook-desktop-mcp", "initiative", "consider", JSON.stringify(event)], running: true,
                                        asked: what })
    }
    // Say something now / Find news now waiting for their answer ("say",
    // "news"; Settings shows it), and what came of the last one (its
    // action: "notify", "badge" or "none").
    property string asking: ""
    property string asked: ""
    function _askNow(what) {
        root.asking = what
        root.asked = ""
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
    // News (ai.initiative.news): about once a day, what's new on the subjects
    // the user talks about most, found on the web by the small model, said
    // with its links (buttons under the bubble).
    readonly property bool news: Config.options?.ai?.initiative?.news ?? false
    readonly property string newsHint: "You found this news for the user, from what they talk about with you. "
        + "If they want more on one, read it (WebFetch) or search for more (WebSearch) and tell them, with links. "
        + "If they say a subject doesn't interest them (any more), update your memory of them, briefly."
    // Pairing (ai.initiative.pair): while the user stays on one thing, a look
    // at it every couple of minutes (nixbook-desktop-mcp decides whether a
    // look is worth it, at no token); with ai.initiative.pairReadScreen the
    // screen's text too (OCR, redacted). A word it has waits in the bar and
    // pops its bubble only once the user pauses (no input for a few
    // seconds), never over what they type.
    readonly property bool pair: Config.options?.ai?.initiative?.pair ?? false
    readonly property bool pairReadScreen: Config.options?.ai?.initiative?.pairReadScreen ?? false
    property var _pairWaiting: null
    property real _pairSince: Date.now()
    // Another window: the word waiting was about the one before (it stays
    // in the bar).
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root._pairSince = Date.now()
            if (root._pairWaiting && root._pairWaiting.app !== (ToplevelManager.activeToplevel?.appId ?? "")) root._pairWaiting = null
        }
    }
    Timer {
        interval: 2 * 60000
        running: root.enabled && root.pair && !Idle.screensOff
        repeat: true
        onTriggered: {
            // Not right after a switch: on something, not passing through.
            if (GlobalStates.screenLocked || Date.now() - root._pairSince < 60000) return
            const top = ToplevelManager.activeToplevel
            if (!top) return
            root.consider({ event: "pair", app: top.appId ?? "", title: top.title ?? "", screen: root.pairReadScreen })
        }
    }
    IdleMonitor {
        id: pairPause
        enabled: root._pairWaiting !== null
        timeout: 4
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) root._popPair()
    }
    function _popPair() {
        const item = root._pairWaiting
        if (!item) return
        if ((item.expires ?? 0) * 1000 < Date.now() || !root.pending.some(p => p.id === item.id)) {
            root._pairWaiting = null
            return
        }
        if (root.typing || root.busy()) return
        root._pairWaiting = null
        root._say(item)
    }
    // Settings > Find news now: at once, whatever the day's already had.
    function newsNow() {
        if (!root.enabled) return
        root.consider({ event: "news", force: true, location: root.newsLocation() })
    }
    // Where the user is, for local news: the weather's city (the one set,
    // or found by GPS), city and country only.
    function newsLocation() {
        const city = Weather.data?.city ?? ""
        if (city.length === 0 || city === "City") return ""
        return [city, Weather.data?.country ?? ""].filter(s => s.length > 0).join(", ")
    }
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
        root.unstack(item)
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
        // AI off (policies.ai): no bubble to ask Claude in.
        if ((Config.options?.policies?.ai ?? 1) !== 1) return
        if (root.parked && !root.speaking) root.resume()
        else if (!root.speaking) root.speaking = root._ask()
        root.focusWanted()
    }
    // Mod+C, the bar's robot button: called up, or put away when shown.
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
        if (before && !before.fromClaude) Ai.dropIfEmpty(before)
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
    // Called up by the user for a new conversation (kind "ask"): a normal
    // one (Ai.askThread), not a "From Claude" thread: Claude said nothing yet.
    function prepare() {
        const item = root.speaking
        if (root.chat || !item) return
        const thread = item.kind === "ask" ? Ai.askThread(false) : Ai.claudeThread(false)
        if (item.kind !== "ask")
            thread.addMessage(item.chat || item.text, "assistant", true, root._hint(item))
        root.chat = thread
        if ((Ai.models[Ai.currentModelId]?.api_format ?? "") === "claude-code" && Ai.claudeCodePath.length > 0)
            thread.prewarm()
    }
    function _hint(item) {
        return item.curious ? root.learnHint : item.kind === "news" ? root.newsHint : ""
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
    function accept(from) {
        const item = from ?? root.speaking
        if (!item?.accept) return
        if (root.speaking === item) root.speaking = null
        root.answer(item.id, "replied")
    }
    // A button of a reaction: open the file, show it in its folder, or ask
    // Claude about it (in the bubble, the file attached).
    // `from`: a small bubble's (Initiative.stack); "ask" opens it in the
    // bubble first, the others act from where it is.
    function act(a, from) {
        const item = from ?? root.speaking
        if (!a || !item) return
        if (a.do === "ask") {
            if (item !== root.speaking) root.open(item)
            root.reply(a.text, a.attach ?? "")
            return
        }
        // A link of the news: opened in the browser, the bubble left as it
        // is (the others to open too).
        if (a.do === "link") {
            const url = String(a.url ?? "")
            if (/^https?:\/\//.test(url)) AppLaunch.openUrl(url) // the browser brought to the front too
            root._taken(item)
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
        if (root.speaking === item) root.speaking = null
    }
    // The conversation (or what it said) in the side panel, for more room.
    function expand() {
        const item = root.speaking
        if (!root.chat && item) {
            const thread = item.kind === "ask" ? Ai.askThread() : Ai.claudeThread()
            if (item.kind !== "ask")
                thread.addMessage(item.chat || item.text, "assistant", true, root._hint(item))
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
            // Still waiting for an answer: a small bubble, not out of sight.
            if (root.waits(before)) root._stackPush(before)
        }
        const left = root.chat
        root.speaking = null
        root.chat = null
        root.typing = false
        if (left && !left.fromClaude && !root.holds(left)) Ai.dropIfEmpty(left)
    }
    function _notify(item) {
        root._aside()
        root.speaking = item
    }
    // Something new to say: not over what the user is writing or talking
    // about in the bubble (to the bar then).
    // Something new to say: the bubble when free, else a small bubble under
    // it (never over what the user is reading, writing or talking about).
    function _say(item) {
        if (root.speaking && item?.id) {
            if (!root.pending.some(p => p.id === item.id)) root.pending = [...root.pending, item]
            root._stackPush(item)
        } else if (root.typing) root.pending = [...root.pending, item]
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
        root.stack = root.stack.filter(p => p.id !== id)
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
            property string asked: ""
            stdout: StdioCollector { id: out }
            onExited: {
                let action = "none"
                try {
                    const answer = JSON.parse(out.text)
                    if (answer.action === "notify") root._say(answer.item)
                    if (answer.action === "badge") {
                        root.pending = [...root.pending, answer.item]
                        if (answer.item?.pop) root._pairWaiting = answer.item
                    }
                    if (answer.action === "notify" || answer.action === "badge") action = answer.action
                } catch (e) {
                    // Nothing to say, or the server is missing: silence.
                }
                if (proc.asked !== "" && proc.asked === root.asking) {
                    root.asking = ""
                    root.asked = action
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
            root.consider({ event: "moment", curious: root.curious, news: root.news,
                            location: root.news ? root.newsLocation() : "", app: ToplevelManager.activeToplevel?.appId ?? "",
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
        running: root.live.length > 0 || root.stack.length > 0
        repeat: true
        onTriggered: root.now = Date.now()
    }
}
