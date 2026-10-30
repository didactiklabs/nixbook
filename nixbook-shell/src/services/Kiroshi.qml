pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

/**
 * Kiroshi scan (Mod+K, `kiroshi scan`): a situational brief of the focused
 * screen, and the busywork on it handed off. A screenshot of the output
 * (1280 px wide) goes with what the user is doing (the focused window and
 * its accessibility text, the open windows, their recent activity when
 * ai.initiative.recentContext is on, the latest notifications, the next
 * events, the time) to `nixbook-desktop-mcp kiroshi scan` (desktop-mcp.py's
 * Kiroshi section: Claude Code with the image, `kiroshiModel`, Sonnet by
 * default), masked on the way. It answers in waves: the brief (what they are
 * doing, the one thing that matters now) in ~3 s, the 3–8 things on screen
 * (boxes, urgency, a gist) in ~6 s, then each one's substance (facts, why it
 * matters, the next step) and up to three options as they come, and last
 * their order (best first: the options' value × urgency). An option exists
 * only when it saves real effort (the script drops one-click work and
 * anything malformed): a quick one is one desktop-mcp tool call, run here
 * at once (`nixbook-desktop-mcp call`: desktop control's pause and guards
 * apply), its ✓ or error shown in the card, and one that sends something
 * (a reply) waits for the user's Send; the notifications' own (a reply, a
 * button, several cleared) are done here by the shell, which owns them; an
 * agent one hands its instruction (with the draft as edited) to DAI in a
 * new conversation of its speech bubble (Initiative.order). Each option the
 * user uses is kept (`kiroshi taken`), and the next scans are told the
 * offers this user takes. Tell me more asks DAI about the item's crop, and
 * the routine ones are done in one go. Needs Claude Code and policies.ai on.
 */
Singleton {
    id: root
    // Referenced at startup (shell.qml): its IPC target exists from the start.
    function load() {}

    property bool open: false
    // From the key until every item's detail is in.
    property bool scanning: false
    // The output scanned (its name), the screenshot (kept for crops) and its size.
    property string screenName: ""
    // The focused app when it scanned (the feedback's).
    property string scanApp: ""
    property string imagePath: ""
    property int imageWidth: 0
    property int imageHeight: 0
    // The brief.
    property string doing: ""
    property string focus: ""
    property bool briefIn: false
    // [{key (its index in the script's answer), label, kind, box: [x, y, w, h]
    // (image px), urgency: now|soon|later|noise, gist, facts, why, next,
    // detail, options: [{title, saves, value 1-3, kind quick|agent, tool,
    // args, confirm, draft, draftKey | plan, draft, instruction}], handle (the
    // best agent option, older answers), pending, results: {option: {state
    // running|done|error, text}}, confirming: the option waiting for Send}]
    property var items: []
    // The items' new places once ranked: perm[old index] = new index.
    signal reordered(var perm)
    property bool itemsIn: false
    // Indexes of the items the agent can handle without the user's judgment.
    property var routine: []
    property string error: ""
    property string provider: ""
    property string model: ""
    property int briefMs: 0
    property int itemsMs: 0
    property int lastMs: 0
    property real startedAt: 0
    // The item opened in the overlay (-1: none).
    property int expanded: -1

    readonly property var routineReady: root.routine.filter(i => root.routineOption(i) >= 0)
    // Claude Code found and AI on (policies.ai): what the scan runs on.
    readonly property bool available: (Config.options?.policies?.ai ?? 1) === 1 && Ai.claudeCodePath.length > 0
    // The quick options the shell does itself (the notifications are its own).
    readonly property var shellTools: ["notification_action", "dismiss_notifications"]

    // The option a routine item is done with: its best worth it (value ≥ 2)
    // that needs no Send, -1 if none.
    function routineOption(i) {
        const opts = root.items[i]?.options ?? [];
        return opts.findIndex(o => (o.value ?? 1) >= 2 && !o.confirm);
    }

    function scan() {
        if (!root.available) {
            Quickshell.execDetached(["notify-send", "-a", "Kiroshi", Translation.tr("Kiroshi scan"),
                (Config.options?.policies?.ai ?? 1) !== 1 ? Translation.tr("AI is off (Settings > Desktop agents > AI features).")
                    : Translation.tr("It needs Claude Code: install it and log in once (run claude in a terminal).")]);
            return;
        }
        if (root.scanning) return;
        // The focused output, if it is one of this session's screens.
        const focused = WM.focusedMonitor?.name ?? "";
        const name = Quickshell.screens.some(s => s.name === focused) ? focused : (Quickshell.screens[0]?.name ?? "");
        const top = ToplevelManager.activeToplevel;
        root.screenName = name;
        root.scanApp = top?.appId ?? "";
        root.items = [];
        root.routine = [];
        root.doing = "";
        root.focus = "";
        root.briefIn = false;
        root.itemsIn = false;
        root.error = "";
        root.expanded = -1;
        root.imagePath = "";
        root.imageWidth = 0;
        root.imageHeight = 0;
        root.briefMs = 0;
        root.itemsMs = 0;
        root.lastMs = 0;
        root.startedAt = Date.now();
        root.scanning = true;
        // Shown once the screen is captured (the overlay isn't in it).
        root.open = false;
        proc.serial++;
        proc.requestJson = JSON.stringify(Object.assign({
            mode: "scan", lang: ConfigAssistant.uiLang(), claude: Ai.claudeCodePath,
            context: { app: top?.appId ?? "", title: top?.title ?? "", source: "scan",
                now: Qt.formatDateTime(new Date(), "ddd d MMM yyyy hh:mm") },
        }, root.situation()));
        proc.output = name;
        proc.running = true;
    }
    // What the user is doing, for the model (masked by the script).
    function situation() {
        const windows = (WM.windowList ?? []).slice().sort((a, b) => (b.focusedAt ?? 0) - (a.focusedAt ?? 0))
            .slice(0, 10).map(w => ({ app: w.appId ?? "", title: w.title ?? "" }));
        // With their ids, buttons and whether they take a typed reply: what
        // a quick option acts on (notification_action, dismiss_notifications).
        const notifications = (Notifications.list ?? []).slice().sort((a, b) => (b.time ?? 0) - (a.time ?? 0))
            .slice(0, 8).map(n => ({ id: n.notificationId, time: Qt.formatDateTime(new Date(n.time), "hh:mm"),
                app: n.appName ?? "", summary: n.summary ?? "", body: String(n.body ?? "").replace(/<[^>]+>/g, "").slice(0, 300),
                actions: (n.actions ?? []).filter(a => a.identifier !== "default").map(a => a.text || a.identifier),
                canReply: !!n.notification && !!n.hasInlineReply }));
        let events = [];
        try {
            events = CalendarEvents.upcoming(3).map(e => ({ when: CalendarEvents.whenText(e), summary: e.summary ?? "",
                location: e.location ?? "", meeting: !!e.meetingUrl }));
        } catch (e) {}
        const recent = RecentContext.enabled ? RecentContext.snapshot() : [];
        return { windows: windows, notifications: notifications, events: events, recent: recent };
    }
    function close() {
        if (proc.running) {
            proc.serial++;
            proc.running = false;
        }
        root.scanning = false;
        root.open = false;
        root.expanded = -1;
    }
    function expand(i) {
        root.expanded = root.expanded === i ? -1 : (i >= 0 && i < root.items.length ? i : -1);
    }
    function setItem(i, changes) {
        if (i < 0 || i >= root.items.length) return;
        const items = root.items.slice();
        items[i] = Object.assign({}, items[i], changes);
        root.items = items;
    }
    function indexOfKey(key) {
        return root.items.findIndex(it => it.key === key);
    }
    // The script's order (its indexes, best first) and routine ones.
    function applyRank(order, routine) {
        const old = root.items;
        if (!Array.isArray(order) || order.length !== old.length) return;
        const items = order.map(k => old.find(it => it.key === k));
        if (items.some(it => !it)) return;
        const pos = {};
        items.forEach((it, i) => pos[it.key] = i);
        const perm = old.map(it => pos[it.key]);
        root.items = items;
        root.routine = (routine ?? []).map(k => pos[k]).filter(i => i !== undefined).sort((a, b) => a - b);
        if (root.expanded >= 0) root.expanded = perm[root.expanded];
        root.reordered(perm);
    }

    // ── Handing off ──
    // Option n of item i. A quick one runs its tool call here (one that
    // sends first waits for Send: `confirmed`, the user's click in the
    // card, never from IPC); an agent one goes to DAI with its instruction. `draft`: the text as the user left it. `fromUser`:
    // a click or a key (kept as a 👍 for the next scans).
    function runOption(i, n, draft, confirmed, fromUser) {
        const it = root.items[i];
        const o = it?.options?.[n];
        if (!o) return;
        const edited = draft !== undefined && draft !== null && String(draft) !== (o.draft ?? "") ? String(draft) : null;
        if (o.kind === "quick") {
            if (o.confirm && !confirmed) {
                root.setItem(i, { confirming: n });
                return;
            }
            const args = Object.assign({}, o.args);
            if (edited !== null && o.draftKey) args[o.draftKey] = edited;
            if (o.draftKey && String(args[o.draftKey] ?? "").trim().length === 0) return;
            root.setResult(i, n, { state: "running", text: "" }, -1);
            if (root.shellTools.includes(o.tool)) root.setResult(i, n, root.shellAction(o.tool, args), -1);
            else quickCall.createObject(root, { key: it.key, option: n, serial: proc.serial, tool: o.tool, args: args });
            if (fromUser !== false) root.taken(it, o);
            return;
        }
        let text = o.instruction;
        if (edited !== null)
            text += `\n\nThe text to send or type is exactly this (the user edited it):\n<<<\n${edited}\n>>>`;
        if (fromUser !== false) root.taken(it, o);
        root.close();
        Initiative.order(text);
    }
    // A notification's reply or button, or several cleared: the shell's
    // own, done here. {state, text} for the card.
    function shellAction(tool, args) {
        const done = text => ({ state: "done", text: text });
        const failed = text => ({ state: "error", text: text });
        if (tool === "notification_action") {
            const n = Notifications.list.find(x => x.notificationId === args.id);
            if (!n) return failed(Translation.tr("That notification is gone"));
            if (args.reply !== undefined)
                return Notifications.sendReply(args.id, String(args.reply)) ? done(Translation.tr("Sent"))
                    : failed(Translation.tr("%1 takes no reply here").arg(n.appName));
            const a = (n.actions ?? []).find(x => (x.text || x.identifier) === args.action);
            if (!a) return failed(Translation.tr("No button \"%1\"").arg(args.action));
            Notifications.attemptInvokeAction(args.id, a.identifier);
            return done(args.action);
        }
        const ids = Array.isArray(args.ids) ? args.ids
            : Notifications.list.filter(x => args.app ? x.appName === args.app
                : String(`${x.summary} ${x.body}`).toLowerCase().includes(String(args.contains ?? "").toLowerCase()))
                .map(x => x.notificationId);
        const there = ids.filter(id => Notifications.list.some(x => x.notificationId === id));
        if (there.length === 0) return failed(Translation.tr("Nothing to clear"));
        Notifications.discardNotifications(there);
        return done(Translation.tr("%1 cleared").arg(there.length));
    }
    function cancelConfirm(i) {
        root.setItem(i, { confirming: -1 });
    }
    function setResult(i, n, result, confirming) {
        const results = Object.assign({}, root.items[i]?.results ?? {});
        results[n] = result;
        root.setItem(i, confirming === undefined ? { results: results } : { results: results, confirming: confirming });
    }
    // The item's best option (Enter, IPC doIt): option 0.
    function doIt(i, draft) {
        root.runOption(i, 0, draft, false, true);
    }
    // An option the user used, which the next scans read back ("Offers
    // this user takes"). Nothing goes to a model here.
    function taken(it, o) {
        const entry = { title: String(o.title ?? "").slice(0, 200), on: `${it.label}: ${it.gist ?? ""}`.slice(0, 300),
            app: root.scanApp };
        DesktopHelper.run(["kiroshi", "taken", JSON.stringify(entry)], "", (code, out) => {
            if (code !== 0) console.log("[Kiroshi] Offer taken not saved:", out);
        });
    }
    // The routine ones, in one go: the quick ones run here, the agent ones
    // in one combined instruction.
    function handleRoutine() {
        const ready = root.routineReady;
        if (ready.length === 0) return;
        const agent = [];
        for (const i of ready) {
            const n = root.routineOption(i);
            const it = root.items[i];
            const o = it.options[n];
            if (o.kind === "quick") root.runOption(i, n, undefined, false, true);
            else {
                agent.push({ it: it, o: o });
                root.taken(it, o);
            }
        }
        if (agent.length === 0) return;
        const lines = agent.map((a, n) => `${n + 1}. ${a.it.label}: ${a.o.instruction}`);
        root.close();
        Initiative.order(`Handle these small things for me, in order, without asking:\n${lines.join("\n")}`);
    }
    // A quick option's tool call, as the user's own (desktop control's
    // pause, tool groups and guards apply in desktop-mcp).
    Component {
        id: quickCall
        Process {
            id: qc
            property int key: -1
            property int option: 0
            property int serial: 0
            property string tool: ""
            property var args: ({})
            command: ["nixbook-desktop-mcp", "call", qc.tool, JSON.stringify(qc.args)]
            environment: ({ NIXBOOK_DESKTOP_MCP_CLIENT: "Kiroshi" })
            running: true
            stdout: StdioCollector { id: qcOut }
            stderr: StdioCollector { id: qcErr }
            onExited: (code) => {
                const i = root.indexOfKey(qc.key);
                if (qc.serial === proc.serial && i >= 0) {
                    const said = (qcOut.text.trim() || qcErr.text.trim()).split("\n")[0].slice(0, 200);
                    root.setResult(i, qc.option, code === 0 ? { state: "done", text: said }
                        : { state: "error", text: said || Translation.tr("Failed (exit %1)").arg(code) });
                }
                qc.destroy();
            }
        }
    }
    // The item's part of the screen, explained in context.
    function tellMore(i) {
        const it = root.items[i];
        if (!it || !root.imagePath) return;
        const [x, y, w, h] = it.box;
        const pad = 24;
        const x0 = Math.max(0, x - pad), y0 = Math.max(0, y - pad);
        const cw = Math.min(root.imageWidth - x0, w + 2 * pad), ch = Math.min(root.imageHeight - y0, h + 2 * pad);
        crop.question = Translation.tr("Explain this in detail, in context (I'm %1). What should I know or do? It's \"%2\": %3")
            .arg(root.doing || Translation.tr("at my desk")).arg(it.label).arg(it.detail || it.gist || "");
        crop.target = root.imagePath.replace(/\.jpg$/, `-crop${i}.png`);
        crop.command = ["magick", root.imagePath, "-crop", `${Math.round(cw)}x${Math.round(ch)}+${Math.round(x0)}+${Math.round(y0)}`,
            "+repage", crop.target];
        root.close();
        crop.running = true;
    }
    Process {
        id: crop
        property string target: ""
        property string question: ""
        onExited: (code) => {
            if (code === 0) Initiative.order(crop.question, crop.target);
        }
    }

    Process {
        id: proc
        property int serial: 0
        property int mine: 0
        property string requestJson: "{}"
        property string output: ""
        onRunningChanged: if (running) mine = serial
        command: ["bash", "-c", 'dir="${XDG_RUNTIME_DIR:-/tmp}/nixbook-shell/kiroshi"; mkdir -p -m 700 "$dir"; '
            + 'shot="$dir/kiroshi-$$.png"; img="$dir/kiroshi-$$.jpg"; f="$dir/kiroshi-$$.json"; '
            + 'trap \'rm -f "$shot" "$f"\' EXIT; '
            + 'find "$dir" -maxdepth 1 -name "kiroshi-*" -mmin +60 -delete 2>/dev/null; '
            + 'grim -l 0 ${2:+-o "$2"} "$shot" || { echo \'{"type":"error","error":"no screenshot (grim)"}\'; exit 1; }; '
            + 'echo \'{"type":"captured"}\'; '
            + 'magick "$shot" -resize "1280x>" -quality 85 "$img" || { echo \'{"type":"error","error":"no image (magick)"}\'; exit 1; }; '
            + 'echo "{\\"type\\":\\"image\\",\\"path\\":\\"$img\\"}"; '
            + 'printf "%s" "$1" | jq -c --arg img "$img" \'. + {image: $img}\' > "$f"; '
            + 'nixbook-desktop-mcp kiroshi scan "$f"', "_", proc.requestJson, proc.output]
        stdout: SplitParser {
            onRead: (line) => {
                if (proc.mine !== proc.serial) return;
                let ev;
                try { ev = JSON.parse(line); } catch (e) {
                    if (line.trim().length > 0) root.error = line.trim();
                    return;
                }
                switch (ev.type) {
                case "captured": root.open = true; break;
                case "image": root.imagePath = ev.path ?? ""; break;
                case "start":
                    root.provider = ev.provider ?? "";
                    root.model = ev.model ?? "";
                    break;
                case "brief":
                    root.briefMs = ev.ms ?? 0;
                    root.doing = ev.doing ?? "";
                    root.focus = ev.focus ?? "";
                    root.briefIn = true;
                    break;
                case "scan":
                    root.imageWidth = ev.width ?? 0;
                    root.imageHeight = ev.height ?? 0;
                    root.itemsMs = ev.ms ?? 0;
                    root.items = (ev.items ?? []).map((it, k) => Object.assign({ key: k, facts: [], why: "", next: "",
                        detail: "", options: [], handle: null, pending: true, results: ({}), confirming: -1 }, it));
                    root.routine = ev.routine ?? [];
                    root.itemsIn = true;
                    break;
                case "item": {
                    const at = root.indexOfKey(ev.index);
                    if (at >= 0)
                        root.setItem(at, { facts: ev.facts ?? [], why: ev.why ?? "", next: ev.next ?? "",
                            detail: ev.detail ?? "", handle: ev.handle ?? null, failed: ev.error ?? "", pending: false,
                            // Older scripts: the handle alone, as an agent option.
                            options: ev.options ?? (ev.handle ? [Object.assign({ kind: "agent", value: 2, saves: "" }, ev.handle)] : []) });
                    break;
                }
                case "ranked": root.applyRank(ev.order ?? [], ev.routine ?? root.routine); break;
                case "error": root.error = ev.error ?? Translation.tr("No answer"); break;
                case "done": root.lastMs = ev.ms ?? (Date.now() - root.startedAt); break;
                }
            }
        }
        onExited: (code) => {
            if (proc.mine !== proc.serial) return;
            root.scanning = false;
            root.items = root.items.map(it => it.pending ? Object.assign({}, it, { pending: false }) : it);
            if (code !== 0) root.open = true;
            if (code !== 0 && root.error.length === 0 && root.items.length === 0)
                root.error = Translation.tr("The scan failed (exit %1)").arg(code);
        }
    }

    IpcHandler {
        target: "kiroshi"
        // The focused screen, scanned and briefed (again while open or scanning: closes it).
        function scan(): void {
            if (root.open || root.scanning) root.close();
            else root.scan();
        }
        function close(): void { root.close(); }
        // Item N (from 1): opened, done (its best option), or explained.
        function expand(n: int): void { root.expand(n - 1); }
        function doIt(n: int): void { root.runOption(n - 1, 0, undefined, false, false); }
        // Option M (from 1) of item N: run (one that sends still waits for
        // the Send click in the card: never sent from here).
        function option(n: int, m: int): void { root.runOption(n - 1, m - 1, undefined, false, false); }
        function tellMore(n: int): void { root.tellMore(n - 1); }
        function handleRoutine(): void { root.handleRoutine(); }
        function status(): string {
            return JSON.stringify({ open: root.open, scanning: root.scanning, screen: root.screenName,
                width: root.imageWidth, height: root.imageHeight, doing: root.doing, focus: root.focus,
                routine: root.routine, error: root.error, briefMs: root.briefMs, itemsMs: root.itemsMs,
                ms: root.lastMs, items: root.items });
        }
    }
}
