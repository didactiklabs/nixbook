pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

/**
 * The smart clipboard (ai.clipboard): copy something, get the right action
 * at once. What was copied is read in plain code, in a few milliseconds
 * (modules/common/functions/clipboard_kinds.js: a tracking number, an
 * address, a date, text in another language, an error, a link, a phone
 * number, an e-mail address, a long text, code, an amount), and a small row
 * of chips shows for ~8 s at the top left, beside V's speech bubble
 * (modules/ii/smartClipboard/SmartClipboardChips.qml), never taking the
 * keyboard: "Copied a tracking number — Track it · Not now".
 * Plain actions run at once (a page opened, the calendar's editor filled
 * in, the phone dialling through KDE Connect); model actions (✦: Translate,
 * Explain, Summarize, Rewrite, Fix it, Summarize the page) are an order for
 * V in its bubble (Initiative.order, as Kiroshi's offers: Claude Code, the
 * message masked by the chat's privacy mask like every other). On screen,
 * real names.
 * Never what a password manager copied (wl-paste's CLIPBOARD_STATE
 * "sensitive", or a password manager in front), never a secret (a
 * password, a one-time code, a key or token, a card number: the
 * classifier's secret check), nor an agent's paste. Nothing with
 * policies.ai 0; plain actions only with 2 (local); not while locked;
 * quiet (no chip) in Do Not Disturb, a meeting or a fullscreen app
 * (Initiative.busy): the clipboard history (Mod+Q) still has the action.
 * It learns lightly: a kind ignored 5 times in a row is no longer offered
 * (until "Offer them again" in Settings), kinds and actions taken are put
 * first. State in $XDG_STATE_HOME/nixbook-shell/smart-clipboard.json.
 * An error copied is offered here (Explain it · Fix it), not also by the
 * reactor's error_copied offer (RecentContext asks `handlesErrors`).
 * IPC `smartClipboard`: status, classify TEXT, offer TEXT, run, runChip N,
 * dismiss, reset (denied to agents: desktop-mcp's shellIpcDenyTargets).
 */
Singleton {
    id: root
    // Referenced at startup (shell.qml): its IPC target exists from the start.
    function load() {
        stateFile.reload()
    }

    readonly property int policy: Config.options?.policies?.ai ?? 1
    readonly property var cfg: Config.options?.ai?.clipboard ?? ({})
    readonly property bool enabled: Config.ready && (root.cfg.enable ?? true) && root.policy !== 0
    // Model actions: AI fully on, and Claude Code found (as Kiroshi's).
    readonly property bool modelOk: root.policy === 1 && Ai.claudeCodePath.length > 0
    readonly property int showMs: 8000
    readonly property int muteAfter: 5
    function kindOn(kind) {
        return root.cfg.kinds?.[kind] ?? true
    }
    // The bubble's error offer gives way: an error copied gets its chips here.
    readonly property bool handlesErrors: root.enabled && root.kindOn("error") && !(root.stats.error?.muted ?? false)

    // Learning: kind -> {shown, accepted, ignored (in a row), muted};
    // action id -> times taken.
    property var stats: ({})
    property var actionStats: ({})

    // The chips on screen: {text, kind, title, detail, chips: [{id, label,
    // icon, model, kind, run}], time}, or null.
    property var current: null
    // The last copy read (also while quiet), for status.
    property var last: null
    property bool hovered: false
    onHoveredChanged: root.hovered ? hideTimer.stop() : (root.current ? hideTimer.restart() : undefined)

    readonly property string dir: Directories.runtimeTemp
    readonly property string copiedPath: `${root.dir}/copied-text`
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/smart-clipboard.json`

    // ── Reading the clipboard ──
    // Quickshell sees the clipboard only while one of its windows has the
    // focus: wl-paste watches it, as RecentContext's error watch does, and
    // writes a copy (≤ 20000 bytes) to the runtime dir; never what a
    // password manager copied (CLIPBOARD_STATE "sensitive").
    Process {
        running: root.enabled
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
            '[ "$CLIPBOARD_STATE" = data ] || exit 0; t=$(head -c 20000); [ ${#t} -ge 3 ] || exit 0; '
            + 'printf "%s" "$t" >"$1.tmp" && mv -f "$1.tmp" "$1"',
            "copied", root.copiedPath]
    }
    FileView {
        id: copied
        path: root.enabled ? root.copiedPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._copied(copied.text())
    }
    property string _lastKey: ""
    property real _lastAt: 0
    // When the watch started: wl-paste reports what is already in the
    // clipboard first, which nobody just copied.
    property real _since: Date.now()
    onEnabledChanged: {
        root._since = Date.now()
        if (!root.enabled) root.dismiss(false)
    }

    function _copied(text) {
        if (Date.now() - root._since < 2500) return
        if (!root.enabled || GlobalStates.screenLocked) return
        // An agent's paste (type_text goes through the clipboard).
        if (DesktopControl.active || DesktopControl.agentInputRecent()) return
        const key = Qt.md5(text)
        if (key === root._lastKey && Date.now() - root._lastAt < 30000) return
        root._lastKey = key
        root._lastAt = Date.now()
        // The shell's own copies (a bubble answer's Copy) aren't offered back.
        if (root._ownAnswer(text)) return
        const offer = root.read(text, ToplevelManager.activeToplevel?.appId ?? "")
        root.last = { time: Date.now(), kind: offer?.kind ?? "", secret: offer?.secret ?? false, why: offer?.why ?? "" }
        if (!offer || offer.secret || offer.chips.length === 0) return
        // Quiet: no chip (the clipboard history keeps the action).
        if (Initiative.busy()) {
            root.last.quiet = true
            return
        }
        root.show(offer)
    }

    // The bubble's last answer: copying it back isn't a new copy.
    function _ownAnswer(text) {
        const chat = Initiative.chat
        const ids = chat?.messageIDs ?? []
        for (let i = ids.length - 1; i >= 0 && i >= ids.length - 4; i--) {
            const m = chat.messageByID[ids[i]]
            if (m?.role === "assistant" && String(m.content ?? "").trim() === String(text).trim()) return true
        }
        return false
    }

    // ── What it is, and what to offer ──
    function options(app) {
        return { now: new Date(), lang: ConfigAssistant.uiLang(), known: root.cfg.knownLanguages ?? [],
                 app: app ?? "", currency: root.cfg.currency ?? "" }
    }
    // The classifier's answer, as an offer: the kinds on and not muted, the
    // ones taken before first; the best kind's actions (those it can run
    // now, those taken before first), then the next kind's best one, three
    // chips at most.
    function read(text, app) {
        const r = ClipboardKinds.classify(text, root.options(app))
        if (r.secret) return { secret: true, why: r.why, chips: [] }
        const cands = r.candidates.filter(c => root.kindOn(c.kind) && !(root.stats[c.kind]?.muted ?? false))
        const ranked = cands.map((c, i) => ({ c: c, i: i, a: Math.min(5, root.stats[c.kind]?.accepted ?? 0) }))
        ranked.sort((x, y) => (y.a - x.a) || (x.i - y.i))
        const chips = []
        let first = null
        for (const x of ranked) {
            const usable = x.c.actions.filter(a => root.canRun(a))
                .map((a, i) => ({ a: a, i: i, n: root.actionStats[a.id] ?? 0 }))
            usable.sort((p, q) => (q.n - p.n) || (p.i - q.i))
            if (usable.length === 0) continue
            if (!first) {
                first = x.c
                for (const u of usable.slice(0, 3)) chips.push(root.chip(u.a, x.c, text))
            } else if (chips.length < 3 && !chips.some(ch => ch.id === usable[0].a.id)) {
                chips.push(root.chip(usable[0].a, x.c, text))
            }
            if (chips.length >= 3) break
        }
        if (!first) return { secret: false, chips: [], kind: r.candidates[0]?.kind ?? "" }
        return { secret: false, text: String(text), kind: first.kind, title: root.title(first), detail: root.detail(first),
                 chips: chips, candidates: r.candidates, time: Date.now(), app: app ?? "" }
    }
    function canRun(a) {
        if (a.model) return root.modelOk
        if (a.id === "call" || a.id === "text") return (KdeConnect.reachableDevices ?? []).length > 0
        return true
    }
    readonly property var languageNames: ({
        en: Translation.tr("English"), fr: Translation.tr("French"), de: Translation.tr("German"), vi: Translation.tr("Vietnamese"),
        es: Translation.tr("Spanish"), it: Translation.tr("Italian"), pt: Translation.tr("Portuguese"), nl: Translation.tr("Dutch"),
        ja: Translation.tr("Japanese"), zh: Translation.tr("Chinese"), ko: Translation.tr("Korean"), ru: Translation.tr("Russian"),
        ar: Translation.tr("Arabic"), he: Translation.tr("Hebrew"), el: Translation.tr("Greek"), th: Translation.tr("Thai"), hi: Translation.tr("Hindi")
    })
    // "Copied a tracking number" and the like.
    function title(c) {
        const k = c.kind
        return k === "tracking" ? Translation.tr("Copied a tracking number")
            : k === "address" ? Translation.tr("Copied an address")
            : k === "date" ? Translation.tr("Copied a date")
            : k === "language" ? Translation.tr("Copied text in %1").arg(root.languageNames[c.language] ?? c.language)
            : k === "error" ? Translation.tr("Copied an error")
            : k === "url" ? Translation.tr("Copied a link")
            : k === "phone" ? Translation.tr("Copied a phone number")
            : k === "email" ? Translation.tr("Copied an e-mail address")
            : k === "paragraph" ? Translation.tr("Copied a long text")
            : k === "code" ? Translation.tr("Copied some code")
            : k === "amount" ? Translation.tr("Copied an amount")
            : Translation.tr("Copied")
    }
    function detail(c) {
        if (c.kind === "date") {
            const d = new Date(c.when)
            const shown = c.hasTime ? Qt.formatDateTime(d, "ddd d MMM, hh:mm") : Qt.formatDate(d, "ddd d MMM yyyy")
            // Said in another time zone: the local time, then what was said.
            return c.said ? `${shown} (${c.said})` : shown
        }
        if (c.kind === "error" || c.kind === "address") return String(c.detail ?? "").slice(0, 48)
        return String(c.detail ?? "")
    }
    readonly property var kindIcons: ({
        tracking: "local_shipping", address: "location_on", date: "event", language: "translate", error: "bug_report",
        url: "link", phone: "call", email: "mail", paragraph: "subject", code: "code", amount: "currency_exchange"
    })
    // A chip: its label, icon, and what it does.
    function chip(a, c, text) {
        const short = s => s.length > 28 ? s.slice(0, 27) + "…" : s
        const label = a.id === "track" ? Translation.tr("Track it")
            : a.id === "directions" ? Translation.tr("Directions")
            : a.id === "map" ? Translation.tr("Show on the map")
            : a.id === "calendar" ? Translation.tr("Add to calendar")
            : a.id === "translate" ? Translation.tr("Translate")
            : a.id === "explain" ? (c.kind === "error" ? Translation.tr("Explain it") : Translation.tr("Explain"))
            : a.id === "fixError" ? Translation.tr("Fix it")
            : a.id === "summarizePage" ? Translation.tr("Summarize the page")
            : a.id === "open" ? Translation.tr("Open")
            : a.id === "call" ? Translation.tr("Call from the phone")
            : a.id === "text" ? Translation.tr("Text from the phone")
            : a.id === "mail" ? Translation.tr("Write to %1").arg(short(a.address))
            : a.id === "summarize" ? Translation.tr("Summarize")
            : a.id === "rewrite" ? Translation.tr("Rewrite")
            : a.id === "convert" ? Translation.tr("Convert to %1").arg(a.to)
            : a.id
        const icon = { track: "local_shipping", directions: "directions", map: "map", calendar: "event", translate: "translate",
                       explain: "lightbulb", fixError: "build", summarizePage: "summarize", open: "open_in_new", call: "call",
                       text: "sms", mail: "mail", summarize: "summarize", rewrite: "edit_note", convert: "currency_exchange" }[a.id] ?? "bolt"
        return { id: a.id, label: label, icon: icon, model: a.model === true, kind: c.kind, action: a, text: String(text) }
    }

    // ── Showing it ──
    function show(offer) {
        if (!offer || (offer.chips ?? []).length === 0) return
        root.current = offer
        const s = Object.assign({}, root.stats[offer.kind] ?? {})
        s.shown = (s.shown ?? 0) + 1
        root.stats = Object.assign({}, root.stats, { [offer.kind]: s })
        hideTimer.restart()
    }
    Timer {
        id: hideTimer
        interval: root.showMs
        onTriggered: if (!root.hovered) root.dismiss(true)
    }
    // Gone: ignored (`ignored`: timed out or Not now) counts for its kind.
    function dismiss(ignored) {
        const c = root.current
        if (!c) return
        root.current = null
        hideTimer.stop()
        root.hovered = false
        if (!ignored) return
        const s = Object.assign({}, root.stats[c.kind] ?? {})
        s.ignored = (s.ignored ?? 0) + 1
        if (s.ignored >= root.muteAfter) s.muted = true
        root.stats = Object.assign({}, root.stats, { [c.kind]: s })
        root._save()
    }
    function _accepted(chip) {
        const s = Object.assign({}, root.stats[chip.kind] ?? {})
        s.accepted = (s.accepted ?? 0) + 1
        s.ignored = 0
        root.stats = Object.assign({}, root.stats, { [chip.kind]: s })
        root.actionStats = Object.assign({}, root.actionStats, { [chip.id]: (root.actionStats[chip.id] ?? 0) + 1 })
        root._save()
    }
    // A kind offered again (Settings), or all of them.
    function unmute(kind) {
        const out = {}
        for (const k in root.stats) {
            out[k] = Object.assign({}, root.stats[k])
            if (!kind || k === kind) {
                out[k].muted = false
                out[k].ignored = 0
            }
        }
        root.stats = out
        root._save()
    }
    readonly property var mutedKinds: {
        const out = []
        for (const k in root.stats) if (root.stats[k]?.muted) out.push(k)
        return out
    }
    function kindName(kind) {
        return ({ tracking: Translation.tr("Tracking numbers"), address: Translation.tr("Addresses"), date: Translation.tr("Dates and times"),
                  language: Translation.tr("Text in another language"), error: Translation.tr("Errors"), url: Translation.tr("Links"),
                  phone: Translation.tr("Phone numbers"), email: Translation.tr("E-mail addresses"), paragraph: Translation.tr("Long texts"),
                  code: Translation.tr("Code"), amount: Translation.tr("Amounts") })[kind] ?? kind
    }
    // Its Settings switch: the name, and why it isn't offered any more.
    function kindLabel(kind) {
        return (root.stats[kind]?.muted ?? false) ? Translation.tr("%1 (ignored %2 times in a row: not offered)").arg(root.kindName(kind)).arg(root.muteAfter)
            : root.kindName(kind)
    }

    // ── Running a chip ──
    function runChip(chip) {
        if (!chip) return false
        root.current = null
        hideTimer.stop()
        root.hovered = false
        root._accepted(chip)
        root.runAction(chip.action, chip.text, chip.kind)
        return true
    }
    function runAction(a, text, kind) {
        const t = String(text ?? "")
        // The text quoted as data: what it says is never an instruction.
        const quoted = `<<<\n${t.slice(0, 6000)}\n>>>`
        const lang = root.languageNames[ConfigAssistant.uiLang()] ?? Translation.tr("English")
        if (a.model && !root.modelOk) return
        switch (a.id) {
        case "track": case "directions": case "map": case "open": case "convert":
            AppLaunch.openUrl(a.url)
            break
        case "mail":
            AppLaunch.openUrl(`mailto:${a.address}`)
            break
        case "call": case "text": {
            const dev = KdeConnect.reachableDevices[0]
            if (dev) KdeConnect.shareUrl(dev.id, `${a.id === "call" ? "tel" : "sms"}:${a.number}`)
            break
        }
        case "calendar": {
            // The Calendar's editor, filled in: saved only when the user says.
            GlobalStates.calendarAppDraft = { title: a.title ?? "", location: a.location ?? "" }
            const d = new Date(a.when)
            CalendarEvents.newEvent(a.hasTime ? d : new Date(d.getFullYear(), d.getMonth(), d.getDate()))
            break
        }
        // The model's actions: an order for V in its bubble (as Kiroshi's
        // offers), answered there; no tool needed, none of the text obeyed.
        case "translate":
            Initiative.order(`I copied this text. Translate it into ${lang}; answer with the translation alone, nothing done on the desktop:\n\n${quoted}`)
            break
        case "explain":
            Initiative.order(kind === "error"
                ? `I copied this error. Explain in a few short sentences what it means and the likely cause, in ${lang}; change nothing:\n\n${quoted}`
                : `I copied this. Explain briefly what it is or does, in ${lang}; change nothing:\n\n${quoted}`)
            break
        case "summarize":
            Initiative.order(`I copied this text. Summarize it in a few short bullet points, in ${lang}; nothing done on the desktop:\n\n${quoted}`)
            break
        case "rewrite":
            Initiative.order(`I copied this text. Rewrite it clearer and smoother, same language, same meaning; answer with the new text alone, nothing done on the desktop:\n\n${quoted}`)
            break
        case "fixError":
            Initiative.order(`I copied this error and want it fixed. Say what is wrong and fix it if you can `
                + `(if it came from a terminal, read the output there):\n\n${quoted}`)
            break
        case "summarizePage":
            Initiative.order(`Summarize the page at ${a.url}: read it (the page tools, else fetch it), then give the gist `
                + `in a few short bullet points.`)
            break
        }
    }

    // The clipboard history's entries (the launcher, Mod+Q): the best plain
    // action for one, or null (model actions need the whole text, which the
    // history's preview may cut).
    function historyAction(text) {
        if (!root.enabled) return null
        const r = ClipboardKinds.classify(text, root.options(""))
        if (r.secret) return null
        for (const c of r.candidates) {
            if (!root.kindOn(c.kind)) continue
            const a = c.actions.find(x => !x.model && root.canRun(x))
            if (a) return root.chip(a, c, text)
        }
        return null
    }

    // ── State ──
    function _save() {
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "${1%/*}" && printf "%s" "$2" >"$1.tmp" && mv -f "$1.tmp" "$1"',
            "smart-clipboard", root.statePath, JSON.stringify({ kinds: root.stats, actions: root.actionStats })])
    }
    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(stateFile.text())
                root.stats = d.kinds ?? {}
                root.actionStats = d.actions ?? {}
            } catch (e) {
                root.stats = {}
                root.actionStats = {}
            }
        }
    }

    function _brief(offer) {
        return offer ? { kind: offer.kind ?? "", title: offer.title ?? "", detail: offer.detail ?? "", secret: offer.secret ?? false,
                         why: offer.why ?? "", chips: (offer.chips ?? []).map(c => ({ id: c.id, label: c.label, model: c.model })) } : null
    }
    IpcHandler {
        target: "smartClipboard"
        function status(): string {
            return JSON.stringify({ enabled: root.enabled, policy: root.policy, modelActions: root.modelOk,
                shown: root._brief(root.current), last: root.last, kinds: root.stats, actions: root.actionStats })
        }
        // What a text is and what would be offered (no side effect).
        function classify(text: string): string {
            const r = ClipboardKinds.classify(text, root.options(ToplevelManager.activeToplevel?.appId ?? ""))
            return JSON.stringify({ secret: r.secret, why: r.why, candidates: r.candidates.map(c => ({ kind: c.kind, detail: c.detail,
                actions: c.actions.map(a => a.id) })), offer: root._brief(root.read(text, ToplevelManager.activeToplevel?.appId ?? "")) })
        }
        // The chips for a text as if just copied (demos; never a secret).
        function offer(text: string): string {
            if (!root.enabled || GlobalStates.screenLocked) return "nothing: off or locked"
            const o = root.read(text, "")
            if (o.secret) return `nothing: ${o.why}`
            if (o.chips.length === 0) return "nothing to offer"
            root.show(o)
            return JSON.stringify(root._brief(o))
        }
        // The first chip shown (the key), or the Nth (1-based).
        function run(): string {
            return root.runChip(root.current?.chips?.[0]) ? "ok" : "nothing shown"
        }
        function runChip(n: int): string {
            return root.runChip(root.current?.chips?.[n - 1]) ? "ok" : "nothing shown"
        }
        function dismiss(): void {
            root.dismiss(true)
        }
        // Forget what it learned (every kind offered again).
        function reset(): void {
            root.stats = {}
            root.actionStats = {}
            root._save()
        }
    }
}
