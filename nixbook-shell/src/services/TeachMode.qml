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
 * Teach mode, "watch me once" (`nixbook-desktop-mcp teach`,
 * scripts/desktop-mcp.py): the user shows DAI a task once, and it becomes a
 * recipe of the desktop memory that DAI runs again in one call ("do the
 * expense report again for March").
 *
 * Started from the bubble ("watch me", "regarde-moi faire", "schau mir zu",
 * "xem tôi làm": QuickIntent), Settings > Desktop agents > Teach DAI or the
 * `teach` IPC target; stopped by "done" / "c'est fini" / "fertig" / "xong",
 * or Done on the recording bar (modules/ii/teach/TeachPanel.qml).
 *
 * What is recorded is what the shell already sees, never a key: the app in
 * front (after 1.2 s, passing through isn't using it), the apps started and
 * the links opened from the shell (AppLaunch), a window layout restored
 * (WindowLayouts), and — read by desktop-mcp when Zen comes to the front —
 * the Zen tabs opened or moved to another page. Text only when the user
 * gives it: what they type in the bar's "I typed…" field, or what they copy
 * (a candidate they tick in the review; never a secret: desktop-mcp
 * checks). Nothing while an agent acts
 * (DesktopControl), nothing of a password manager in front, no keylogging.
 *
 * Done: `teach draft` makes the steps (one model call when a model is
 * ready, masked, the model choosing among the recorded steps and naming the variables), shown
 * for approval — name, steps (copied text unticked), variables (renamable)
 * — and `teach save` keeps it as the user's recipe. With policies.ai 0
 * there is no teach mode; with 2 (local) the draft is every step recorded,
 * without the model unless a local one is set.
 * IPC `teach`: start, stop, cancel, status, mark TEXT (denied to agents:
 * desktop-mcp's shellIpcDenyTargets).
 */
Singleton {
    id: root

    function load() {}

    readonly property string command: "nixbook-desktop-mcp"
    readonly property int policy: Config.options?.policies?.ai ?? 1
    readonly property bool enabled: (Config.options?.ai?.teach?.enable ?? true) && root.policy !== 0
    // idle | recording | drafting | review | saving
    property string phase: "idle"
    readonly property bool recording: root.phase === "recording"
    property int events: 0
    property var startedAt: null
    // The draft to approve: {topic, summary, vars: {name: example}, steps:
    // [{tool, args, pending, label}], source, note}
    property var draft: null
    // Per step of the draft: kept or not (copied text unticked).
    property var include: []
    property var renames: ({})
    property string topic: ""
    property string error: ""
    // Saved last: {id, topic, gist, vars}.
    property var saved: null

    signal recordingStarted()
    signal draftReady()
    signal recipeSaved(var recipe)

    function _say(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "DAI", "-i", "school", title, body ?? ""]);
    }

    function start() {
        if (!root.enabled) {
            root._say(Translation.tr("Teach mode is off"), root.policy === 0
                ? Translation.tr("AI features are off (Settings > Desktop agents)")
                : Translation.tr("Turn it on in Settings > Desktop agents > Teach DAI"));
            return false;
        }
        if (root.phase === "recording") return true;
        root.error = "";
        root.draft = null;
        root.saved = null;
        root.events = 0;
        DesktopHelper.run(["teach", "start"], "", (code, out) => {
            if (code !== 0) {
                root.error = out.trim() || Translation.tr("Couldn't start watching");
                root._say(Translation.tr("Teach mode"), root.error);
                root.phase = "idle";
                return;
            }
            root.startedAt = new Date();
            root.phase = "recording";
            root._focusApp = "";
            focusSettle.restart();
            root.recordingStarted();
        });
        return true;
    }

    function stop() {
        if (root.phase !== "recording") return false;
        focusSettle.stop();
        root.phase = "drafting";
        drafter.command = [root.command, "teach", "draft"];
        // Stopped first (Zen's tabs read a last time), then the draft.
        stopper.running = true;
        return true;
    }

    function cancel() {
        focusSettle.stop();
        root.phase = "idle";
        root.draft = null;
        Quickshell.execDetached([root.command, "teach", "cancel"]);
    }

    // What the user typed, given by them (the bar's field): a step.
    function mark(text) {
        const t = String(text ?? "").trim();
        if (!root.recording || t.length === 0) return false;
        root._record({ kind: "text", text: t });
        return true;
    }

    function setIncluded(index, on) {
        const inc = root.include.slice();
        inc[index] = on;
        root.include = inc;
    }
    function rename(from, to) {
        const r = Object.assign({}, root.renames);
        const name = String(to ?? "").trim().toLowerCase();
        if (name.length === 0 || name === from) delete r[from];
        else r[from] = name;
        root.renames = r;
    }

    function save() {
        if (root.phase !== "review" || !root.draft) return false;
        const include = [];
        for (let i = 0; i < root.include.length; i++) if (root.include[i]) include.push(i);
        if (include.length === 0) {
            root.error = Translation.tr("Keep at least one step");
            return false;
        }
        const rename = {};
        for (const k of Object.keys(root.renames))
            if (/^[a-z][a-z0-9_]{0,20}$/.test(root.renames[k])) rename[k] = root.renames[k];
        root.phase = "saving";
        DesktopHelper.run(["teach", "save", "-"], JSON.stringify({ topic: root.topic.trim(), include: include, rename: rename }), (code, out) => {
            let r = null;
            try {
                r = JSON.parse(out);
            } catch (e) {}
            if (code !== 0 || !r?.id) {
                root.error = out.trim() || Translation.tr("Couldn't save it");
                root.phase = "review";
                return;
            }
            root.saved = r;
            root.draft = null;
            root.phase = "idle";
            const vars = (r.vars ?? []).length > 0 ? Translation.tr(" (it asks for: %1)").arg(r.vars.join(", ")) : "";
            root._say(Translation.tr("Learned: %1").arg(r.topic),
                Translation.tr("Ask DAI to do it again%1.").arg(vars));
            root.recipeSaved(r);
        });
        return true;
    }

    function _record(ev) {
        if (!root.recording) return;
        // An agent acting: its steps aren't the user's.
        if (DesktopControl.active || DesktopControl.agentInputRecent()) return;
        DesktopHelper.run(["teach", "event", JSON.stringify(ev)], "", (code, out) => {
            try {
                const r = JSON.parse(out);
                if (typeof r.recorded === "number") root.events = r.recorded;
                if (r.skipped === "too long: stop and save it") root.stop();
            } catch (e) {}
        });
    }

    // ── What the shell sees ──
    property string _focusApp: ""
    Connections {
        target: ToplevelManager
        enabled: root.recording
        function onActiveToplevelChanged() {
            focusSettle.restart();
        }
    }
    // In the browser, a new page in front (its title changes): Zen's tabs
    // read again by desktop-mcp, so the links come in the order visited.
    Connections {
        target: ToplevelManager.activeToplevel
        enabled: root.recording
        ignoreUnknownSignals: true
        function onTitleChanged() {
            if (/zen|firefox|librewolf|floorp|chrom|brave|vivaldi/i.test(ToplevelManager.activeToplevel?.appId ?? "")) {
                root._focusApp = "";
                focusSettle.restart();
            }
        }
    }
    Timer {
        id: focusSettle
        interval: 1200
        onTriggered: {
            const top = ToplevelManager.activeToplevel;
            const app = String(top?.appId ?? "");
            if (!app || app === root._focusApp) return;
            root._focusApp = app;
            const entry = DesktopEntries.heuristicLookup(app);
            root._record({ kind: "focus", app: app, title: String(top?.title ?? ""),
                desktop: String(entry?.id ?? ""), name: String(entry?.name ?? "") });
        }
    }
    Connections {
        target: AppLaunch
        enabled: root.recording
        function onEntryLaunched(id, name) {
            if (id.length > 0) root._record({ kind: "launch", desktop: id, app: id, name: name });
        }
        function onUrlOpened(url) {
            root._record({ kind: "url", url: url });
        }
    }
    Connections {
        target: WindowLayouts
        enabled: root.recording
        function onRestoringChanged() {
            if (WindowLayouts.restoring && WindowLayouts.restoringName.length > 0)
                root._record({ kind: "layout", name: WindowLayouts.restoringName });
        }
    }
    // What is copied while recording: a candidate step (ticked in the
    // review), never a password manager's copy nor a secret.
    readonly property string copiedPath: `${Directories.runtimeTemp}/teach-copied`
    Process {
        running: root.recording
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
            '[ "$CLIPBOARD_STATE" = data ] || exit 0; t=$(head -c 600); [ ${#t} -ge 2 ] || exit 0; '
            + 'printf "%s" "$t" >"$1.tmp" && mv -f "$1.tmp" "$1"',
            "copied", root.copiedPath]
    }
    property real _copySince: 0
    onRecordingChanged: if (root.recording) root._copySince = Date.now()
    FileView {
        id: copied
        path: root.recording ? root.copiedPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // The watch reports what was already there first.
            if (Date.now() - root._copySince < 1500) return;
            const text = copied.text();
            root._record({ kind: "clipboard", text: text });
        }
    }

    Process {
        id: stopper
        command: [root.command, "teach", "stop"]
        onExited: drafter.running = true
    }
    Process {
        id: drafter
        stdout: StdioCollector { id: draftOut }
        stderr: StdioCollector { id: draftErr }
        onExited: code => {
            let d = null;
            try {
                d = JSON.parse(draftOut.text);
            } catch (e) {}
            if (code !== 0 || !d?.steps) {
                root.error = draftErr.text.trim() || Translation.tr("Nothing to make a recipe of");
                root._say(Translation.tr("Teach mode"), root.error);
                root.phase = "idle";
                return;
            }
            root.draft = d;
            root.topic = d.topic ?? "";
            root.include = d.steps.map(s => !s.pending);
            root.renames = ({});
            root.error = "";
            root.phase = "review";
            root.draftReady();
        }
    }

    IpcHandler {
        target: "teach"

        function start(): string {
            return root.start() ? "ok: watching" : "error: teach mode is off";
        }
        function stop(): string {
            return root.stop() ? "ok: drafting the recipe" : "error: not watching";
        }
        function cancel(): string {
            root.cancel();
            return "ok";
        }
        function mark(text: string): string {
            return root.mark(text) ? "ok" : "error: not watching";
        }
        function status(): string {
            return JSON.stringify({ phase: root.phase, events: root.events, topic: root.topic,
                steps: (root.draft?.steps ?? []).length });
        }
    }
}
