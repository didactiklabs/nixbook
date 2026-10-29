pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Full AI mode (Mod+Shift+T, `fullAi toggle`): Claude runs the desktop and
 * the user tells it what to do in its speech bubble. A cute mascot
 * (modules/ii/fullAi) moves around the screen as the MC: what it thinks
 * and does (a thought cloud: each step of the bubble's Claude Code session),
 * what it answers (a speech balloon) and what it asks (Yes / No right on the
 * balloon), over a glow at the screens' edges (FullAiOverlay.qml) that takes
 * neither keys nor clicks: the user keeps their desktop.
 * It reacts to what happens (ai.fullAi.react): a notification, a download,
 * the battery, a screen plugged in, the network lost, the user back: a
 * model (desktop-mcp's `fullai react`, ai.fullAi through desktop-mcp.json's
 * fullAiModel, Sonnet by default) ignores it, tells it, asks what to do
 * ("Julien asks if you come tonight. Shall I say yes?") or does it — alone
 * only on what the user told it (this conversation, a saved note) or chose
 * twice before for the same kind of thing. Every reaction and the user's
 * answer is kept (`fullai learn`, full-ai-learned.json) and given back the
 * next time. While the mode is on it takes these events instead of the
 * initiative (Initiative.qml steps back), one decision at a time.
 */
Singleton {
    id: root
    // Referenced at startup (shell.qml): its IPC target exists from the start.
    function load() {}

    property bool active: false
    // The output the mascot lives on (the focused one when entering).
    property string screenName: ""
    // A short reaction after a task: "happy" or "sad", for a moment.
    property string flash: ""
    // What it last said, shown a while in its balloon.
    property string said: ""

    readonly property var steps: Initiative.chat?.strategy?.steps ?? []
    readonly property bool busy: Initiative.thinking
    readonly property string mood: {
        if (!root.active) return "idle";
        if (root.flash) return root.flash;
        if (root.reacting) return "thinking";
        if (talk.running) return "speaking";
        if (root.busy) return root.steps.some(s => s.status === "run") ? "acting" : "thinking";
        return "idle";
    }

    // A message's words, without the steps and thinking blocks or Markdown.
    function plain(m) {
        return String(m?.content ?? "").replace(/<think>[\s\S]*?(<\/think>|$)/g, " ")
            .replace(/```[\s\S]*?```/g, " ").replace(/[*_`#>]+/g, "").replace(/\s+/g, " ").trim();
    }
    function lastAnswer() {
        const chat = Initiative.chat;
        const ids = chat?.messageIDs ?? [];
        const id = ids.length > 0 ? ids[ids.length - 1] : "";
        const m = id ? chat.messageByID[id] : null;
        return m && m.role === "assistant" ? { id: id, text: root.plain(m) } : null;
    }
    // A question waiting for the user, shown in the balloon until answered
    // (the bubble needn't be called up): its last answer asking back (a yes
    // or no one gets Yes / No).
    property var oldMessages: ({})
    readonly property var question: {
        if (!root.active || root.busy) return null;
        const a = root.lastAnswer();
        if (!a || root.oldMessages[a.id] || !/\?\s*$/.test(a.text)) return null;
        // The question itself: its last sentence (the rest was said).
        const parts = a.text.match(/[^.!?…]+[.!?…]*/g) ?? [a.text];
        const q = (parts[parts.length - 1] ?? a.text).trim();
        const yesNo = /^(do|does|did|should|shall|can|could|would|will|is|are|want|may|voulez|veux|dois|est-ce|faut-il|puis-je|souhaites|soll|willst|möchtest|kann|darf|ist|sind)\b/i.test(q)
            || /\bkhông\s*\?$/i.test(q);
        return { text: q.slice(0, 300), yesNo: yesNo };
    }
    function answer(yes) {
        if (!root.question) return;
        if (!Initiative.speaking) Initiative.openLatest();
        Initiative.reply(yes ? Translation.tr("Yes") : Translation.tr("No"));
    }
    // What fits the balloon: whitespace squashed, and the latest sentences
    // (how it ended), not the beginning cut short.
    function tailOf(text, max = 220) {
        const t = String(text ?? "").replace(/\s+/g, " ").trim();
        if (t.length <= max) return t;
        const parts = t.match(/[^.!?…]+[.!?…]*\s*/g) ?? [t];
        let out = "";
        for (let i = parts.length - 1; i >= 0; i--) {
            if (out.length > 0 && out.length + parts[i].length > max) break;
            out = parts[i] + out;
        }
        out = out.trim();
        return out.length > max ? "…" + out.slice(out.length - max + 1) : out;
    }
    // The balloon: what it says ("say": a speech balloon), what it thinks
    // or does ("thought": a thought cloud), what it asks ("ask") and how to
    // talk to it ("status").
    readonly property var balloon: {
        if (!root.active) return { text: "", kind: "status" };
        if (root.question) return { text: root.question.text, kind: "ask" };
        if (root.reacting) return { text: root.reactingLine, kind: "thought" };
        if (root.busy) {
            const step = [...root.steps].reverse().find(s => s.status === "run") ?? root.steps[root.steps.length - 1];
            if (step) return { text: `${step.tool.replace(/_/g, " ")}${step.summary ? " · " + step.summary : ""}…`, kind: "thought" };
            return { text: Translation.tr("Thinking…"), kind: "thought" };
        }
        if (root.said.length > 0) return { text: root.tailOf(root.said), kind: "say" };
        return { text: Translation.tr("I'm watching. Tell me what to do in my bubble (Mod+C)."), kind: "status" };
    }
    readonly property string line: root.balloon.text
    readonly property string lineKind: root.balloon.kind
    // Yes / No on the balloon while a yes/no question waits (clickable: the
    // overlay takes clicks there only).
    readonly property bool yesNo: root.lineKind === "ask" && (root.question?.yesNo ?? false)
    readonly property string hint: Translation.tr("Mod+Shift+T: leave Full AI · Mod+C: my bubble")

    // A new line in the balloon (its mouth moves a moment).
    function say(text) {
        root.said = String(text ?? "");
        saidOff.restart();
        talk.restart();
    }
    Timer {
        id: talk
        interval: 2600
    }
    function enter() {
        if (root.active) return;
        // AI off or local only (policies.ai): Claude can't run the desktop.
        if ((Config.options?.policies?.ai ?? 1) !== 1) {
            Quickshell.execDetached(["notify-send", "-a", "Muse", Translation.tr("Full AI mode"),
                Translation.tr("AI features are off or local only (Settings > Desktop agents).")]);
            return;
        }
        root.screenName = WM.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        root.said = "";
        // What was asked before the mode started isn't asked now.
        const old = {};
        for (const id of (Initiative.chat?.messageIDs ?? [])) old[id] = true;
        root.oldMessages = old;
        root.active = true;
        root.say(Translation.tr("I've got it from here. Tell me what to do."));
        // Its bubble, ready to type in.
        Initiative.summon();
    }
    function exit() {
        if (!root.active) return;
        root.active = false;
        root.queue = [];
        root.reacting = false;
        root.asked = null;
        root.didAlone = null;
        root.flash = "";
    }
    // AI features switched off (policies.ai) while on: the mode ends.
    readonly property bool aiOnline: (Config.options?.policies?.ai ?? 1) === 1
    onAiOnlineChanged: if (!aiOnline) root.exit()
    function toggle() {
        if (root.active) root.exit();
        else root.enter();
    }

    // ── Reacting to what happens ──
    readonly property bool reactOn: Config.options.ai.fullAi?.react ?? true
    property var queue: []
    property bool reacting: false
    property string reactingLine: ""
    // The question it asked, waiting for the user's answer: {sig, at}.
    property var asked: null
    // What it just did on its own: the user saying no undoes the learning.
    property var didAlone: null
    // Its own words and the shell's: not events.
    // (desktop-mcp.py's INITIATIVE_OWN_APPS names the same.)
    readonly property var ownApps: ["muse", "claude", "desktop agent", "desktop agents", "snoozed", "nixbook", "nixbook-shell",
        "nixbook-desktop-mcp", "quickshell", "shell", "window layouts", "usage habits", "screenshot", "recorder", "reminder", "calendar"]
    readonly property var reactEvents: ["download", "battery_low", "monitor_connected", "monitor_disconnected",
        "audio_output", "wifi_disconnected", "back", "day_start"]
    function event(ev) {
        if (!root.active || !root.reactOn) return;
        if (ev.event === "back" && (ev.away ?? 0) < 10) return;
        // A burst from one app: one event, its messages together (two
        // people writing in a second mustn't lose the first).
        const same = root.queue.find(q => q.event === ev.event && q.app && q.app === ev.app);
        if (same && ev.event === "notification") {
            const merged = Object.assign({}, ev, {
                title: same.title === ev.title ? ev.title : `${same.title} / ${ev.title}`.slice(0, 200),
                text: `${same.text ?? ""}\n${ev.title && same.title !== ev.title ? ev.title + ": " : ""}${ev.text ?? ""}`.trim().slice(-900) });
            root.queue = root.queue.map(q => q === same ? merged : q);
        } else {
            root.queue = root.queue.filter(q => !(q.event === ev.event && q.app && q.app === ev.app)).concat([ev]).slice(-6);
        }
        pump.restart();
    }
    Connections {
        target: Notifications
        function onNotify(n) {
            if (!root.active || !root.reactOn || Notifications.silent || !root.aiOnline) return;
            const app = String(n.appName ?? "");
            if (root.ownApps.includes(app.toLowerCase()) || (n.transient ?? false)) return;
            root.event({ event: "notification", app: app, title: String(n.summary ?? ""),
                         text: String(n.body ?? "").replace(/<[^>]+>/g, "").slice(0, 600), id: n.notificationId ?? n.id ?? 0 });
        }
    }
    Connections {
        target: Routines
        function onHappened(ev) {
            if (root.reactEvents.includes(ev.event) && !DesktopControl.active) root.event(ev);
        }
    }
    // One at a time, a moment after the last (a burst read as one), never
    // over an order of the user's being done.
    Timer {
        id: pump
        interval: 1200
        onTriggered: {
            if (!root.active || root.reacting || root.queue.length === 0) return;
            if (root.busy) { pump.restart(); return; }
            const ev = root.queue[0];
            root.queue = root.queue.slice(1);
            root.react(ev);
        }
    }
    function describe(ev) {
        if (ev.event === "notification") return `${ev.app}${ev.title ? " · " + ev.title : ""}${ev.text ? ": " + ev.text : ""}`;
        return [String(ev.event).replace(/_/g, " "), ev.name, ev.app, ev.percent !== undefined ? ev.percent + "%" : ""].filter(x => x).join(" · ");
    }
    // The conversation so far, for the decision: what the user told it.
    function recentText(n) {
        const chat = Initiative.chat;
        const ids = (chat?.messageIDs ?? []).slice(-n);
        return ids.map(id => chat.messageByID[id]).filter(m => m && (m.role === "user" || m.role === "assistant"))
            .map(m => `${m.role === "user" ? "User" : "Muse"}: ${root.plain(m).slice(0, 400)}`).join("\n");
    }
    function react(ev) {
        root.reacting = true;
        root.reactingLine = "🔔 " + root.describe(ev).slice(0, 160);
        const req = { event: ev, lang: ConfigAssistant.uiLang(), recent: root.recentText(12), claude: Ai.claudeCodePath };
        DesktopHelper.run(["fullai", "react", JSON.stringify(req)], "", (code, out) => {
            let d = null;
            try { d = code === 0 && out ? JSON.parse(out) : null; } catch (e) {}
            root.decided(ev, d);
        });
    }
    // Shown in the bubble as Claude's own message: the user's reply carries
    // it (Initiative.prepare makes it the thread's first message).
    function _item(ev, said) {
        return { id: "", kind: "fullai", level: "notify", title: "Muse", text: said,
                 chat: `${Translation.tr("Something happened")}: ${root.describe(ev)}\n\n${said}` };
    }
    function decided(ev, d) {
        root.reacting = false;
        if (!d || !root.active) {
            pump.restart();
            return;
        }
        const said = d.say || "";
        // A lasting preference it heard: kept in the personal memory.
        if (d.learn) DesktopHelper.run(["fullai", "learn", JSON.stringify({ pref: d.learn, app: ev.app ?? "" })]);
        if (d.action === "ignore") {
            pump.restart();
            return;
        }
        if (d.action === "tell") {
            Initiative._say(root._item(ev, said));
            if (said) root.say(said);
            root.remember(d.sig, "tell", "");
        } else if (d.action === "ask") {
            Initiative._say(root._item(ev, said));
            root.asked = { sig: d.sig, at: Date.now() };
            if (said) root.say(said);
        } else if (d.action === "do") {
            root.didAlone = { sig: d.sig, at: Date.now() };
            if (said) root.say(said);
            Initiative.open(root._item(ev, said));
            Initiative.reply(d.instruction);
            root.remember(d.sig, "do", "did it");
        }
        pump.restart();
    }
    function remember(sig, decision, outcome, words = "") {
        DesktopHelper.run(["fullai", "learn", JSON.stringify({ sig: sig, decision: decision, outcome: outcome, said: words })]);
    }
    // What the user said next in the bubble (Initiative.reply): the answer
    // to its question, or a no to what it just did alone; it learns from both.
    readonly property var yes: /^(yes|yeah|yep|sure|ok(ay)?|go( ahead)?|do it|please|oui|ouais|vas-?y|d'?accord|ja|klar|mach|c[oó]|[dđ][uư][oợ]c)\b/i
    readonly property var no: /^(no|nope|don'?t|stop|cancel|non|nein|kh[oô]ng|annule|laisse)\b/i
    function userSaid(text) {
        const t = String(text ?? "").trim();
        if (root.asked && Date.now() - root.asked.at < 120000) {
            root.remember(root.asked.sig, "ask", root.no.test(t) ? "declined" : root.yes.test(t) ? "agreed" : "answered", t);
            root.asked = null;
        } else if (root.didAlone && Date.now() - root.didAlone.at < 45000 && root.no.test(t)) {
            root.remember(root.didAlone.sig, "do", "undone", t);
            root.didAlone = null;
        }
    }

    // A task done: a happy jump, or a wobble when something failed; the
    // answer's end stays in the balloon a while.
    onBusyChanged: if (root.active && !root.busy) Qt.callLater(root._taskEnded)
    function _taskEnded() {
        if (!root.active || root.busy) return;
        const a = root.lastAnswer();
        if (!a || !a.text) return;
        const failed = root.steps.length > 0 && root.steps.every(s => s.status === "error") || /\*\*Error\*\*/.test(a.text);
        root.flash = failed ? "sad" : "happy";
        root.said = root.tailOf(a.text);
        flashOff.restart();
        saidOff.restart();
        talk.restart();
    }
    Timer {
        id: flashOff
        interval: 1800
        onTriggered: root.flash = ""
    }
    Timer {
        id: saidOff
        interval: 12000
        onTriggered: root.said = ""
    }
    // Locked: out of the mode (the lock screen takes over).
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.exit(); }
    }

    IpcHandler {
        target: "fullAi"
        function enter(): void { root.enter(); }
        function exit(): void { root.exit(); }
        function toggle(): void { root.toggle(); }
        function status(): string {
            return JSON.stringify({ active: root.active, mood: root.mood, line: root.line, screen: root.screenName,
                react: root.reactOn, queued: root.queue.length, reacting: root.reacting });
        }
        // An event as if it had happened (tests): {event, app, title, text…}.
        function simulate(json: string): void {
            try { root.event(JSON.parse(json)); } catch (e) {}
        }
    }
}
