pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The desktop agent fixing nixbook itself (ai.improve, off by default):
 * fixes and polish, each a PR with its changelog entry; and apart, the
 * features asked for (ai.improve.features, off by default: request_feature,
 * Settings, a fix found too big), never merged on its own. The work is
 * `nixbook-improve`'s (improve/), in user units of its own (systemd-run),
 * outside the shell; this only starts it on events and shows its files:
 *   - an inbox item comes in (the user, through an agent's report_problem
 *     or request_feature, or Settings): a run, if one is ripe and the day's
 *     runs aren't made;
 *   - the shell's QML errors and the desktop tools' crashes are filed
 *     (`collect`: reading, no model) 10 minutes after the start, then every
 *     6 hours; a bug seen often enough gets a run;
 *   - 5 minutes after the start, the shell running a deployed fix is
 *     checked (`health`): a revert is offered if it broke.
 * The PR's Merge, Look, Drop come as a notification, and in Settings.
 * Only on machines whose Nix configuration made it available
 * (programs.nixbook-shell.selfImprove.enable), and with its own GitHub
 * token (Settings, kept in the keyring): never the user's gh or ssh.
 */
Singleton {
    id: root

    // On this machine at all: programs.nixbook-shell.selfImprove.enable,
    // "improve" in desktop-mcp.json (Nix's). Otherwise no section, no runs.
    property bool available: false
    readonly property bool aiAllowed: (Config.options?.policies?.ai ?? 1) === 1 // AI off, or local models only: no Claude
    readonly property bool enabled: root.available && (Config.options?.ai?.improve?.enable ?? false) && root.aiAllowed
    readonly property bool featuresEnabled: root.available && (Config.options?.ai?.improve?.features?.enable ?? false) && root.aiAllowed
    // Its GitHub token is in the keyring; what the last save said.
    property bool tokenSaved: false
    property bool tokenBusy: false
    property string tokenStatus: ""
    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/improve`
    // Inbox items (newest first) and runs (newest first), as nixbook-improve wrote them.
    property var inbox: []
    property var runs: []
    readonly property var open: root.inbox.filter(i => ["new", "working", "pr"].includes(i.status))
    readonly property var waiting: root.runs.filter(r => r.outcome === "pr")
    readonly property var running: root.runs.find(r => !r.outcome && r.stage !== "done") ?? null
    // Fixes and features apart (Settings shows them in two sections).
    function isFeatureItem(i) { return i.kind === "feature" }
    function waitingOf(feature) { return root.waiting.filter(r => (r.feature === true) === feature) }
    function activityOf(feature) { return root.activity.filter(e => (e.feature === true) === feature) }
    // What it did and decided, newest first: {time, kind, text, feature} (activity.json).
    property var activity: []
    // Ticks while a fix is made: its elapsed time in Settings.
    property real now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.running !== null
        onTriggered: root.now = Date.now()
    }
    // A run's stage in words (its `doing` says what right now).
    function stageText(stage) {
        return ({
            clone: Translation.tr("getting the repository up to date"),
            fix: Translation.tr("Claude looks for the cause"),
            build: Translation.tr("Claude builds the feature"),
            check: Translation.tr("checking the change"),
            push: Translation.tr("opening the pull request"),
            ci: Translation.tr("waiting for CI")
        })[stage] ?? stage
    }
    // One line: what it is doing, or why nothing (the fixes', or with
    // feature the features').
    function statusOf(feature) {
        if (!(feature ? root.featuresEnabled : root.enabled)) return Translation.tr("Off.")
        if (!root.tokenSaved) return feature ? Translation.tr("Needs its GitHub token (in Fixes it makes itself) to open pull requests.")
            : Translation.tr("Needs its GitHub token (below) to open pull requests.")
        if (root.running) {
            const mins = Math.max(0, Math.round((root.now - root.running.started) / 60000))
            const doing = root.running.doing || root.stageText(root.running.stage)
            if ((root.running.feature === true) === feature)
                return (feature ? Translation.tr("Building “%1” — %2 (%3 min)") : Translation.tr("Fixing “%1” — %2 (%3 min)"))
                    .arg(root.running.itemText).arg(doing).arg(mins)
            return feature ? Translation.tr("Waiting: a fix is being made (one at a time).")
                : Translation.tr("Waiting: a feature is being built (one at a time).")
        }
        const mine = root.waitingOf(feature)
        const ci = mine.filter(r => r.ci === "pending")
        if (ci.length > 0) return Translation.tr("#%1 waits for CI.").arg(ci[0].pr)
        if (mine.length > 0) return (feature ? Translation.tr("%1 feature(s) wait for you below.") : Translation.tr("%1 fix(es) wait for you below."))
            .arg(mine.length)
        const last = root.activityOf(feature)[0]
        if (last) return Translation.tr("Idle. Last: %1 — %2").arg(Qt.formatDateTime(new Date(last.time), "d MMM hh:mm")).arg(last.text)
        return feature ? Translation.tr("Idle: nothing asked yet. Ask an agent for a feature, or type it below.")
            : Translation.tr("Idle: nothing yet. It looks for bugs 10 minutes after the shell starts; Look for bugs now does it at once.")
    }
    readonly property string status: root.running?.feature === true ? root.statusOf(true) : root.statusOf(false)

    // Stop the fix being made.
    function stop() {
        Quickshell.execDetached(["nixbook-improve", "stop"])
    }

    function load() {
        mcpConfig.reload()
        inboxFile.reload()
        runsFile.reload()
        activityFile.reload()
    }

    FileView {
        id: activityFile
        path: `${root.dir}/activity.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.activity = (JSON.parse(activityFile.text()) ?? []).slice().reverse()
            } catch (e) {
            }
        }
    }

    // The token: checked on the repository, then kept in the keyring
    // (nixbook-improve token set, on stdin: never on a command line).
    function setToken(token) {
        if (token.trim().length === 0) return
        root.tokenBusy = true
        tokenProc.secret = token.trim()
        tokenProc.command = ["nixbook-improve", "token", "set"]
        tokenProc.stdinEnabled = true
        tokenProc.running = true
    }
    function forgetToken() {
        root.tokenBusy = true
        tokenProc.command = ["nixbook-improve", "token", "forget"]
        tokenProc.stdinEnabled = false
        tokenProc.running = true
    }
    Process {
        id: tokenProc
        property string secret: ""
        onRunningChanged: {
            if (!tokenProc.running || !tokenProc.stdinEnabled) return
            tokenProc.write(tokenProc.secret + "\n")
            tokenProc.secret = ""
            // End of the token.
            tokenProc.stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.tokenBusy = false
                try {
                    const out = JSON.parse(text)
                    if (out.error) {
                        root.tokenStatus = out.error
                    } else {
                        root.tokenSaved = out.saved === true
                        root.tokenStatus = out.saved ? Translation.tr("Saved: it can reach %1.").arg(out.repo) + (out.warning ? ` ${out.warning}` : "")
                            : Translation.tr("Forgotten.")
                    }
                } catch (e) {
                    root.tokenStatus = Translation.tr("nixbook-improve didn't answer")
                }
            }
        }
    }
    Process {
        id: tokenCheck
        command: ["nixbook-improve", "token", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.tokenSaved = JSON.parse(text).saved === true
                } catch (e) {
                }
            }
        }
    }

    // Its open PRs merged or closed on GitHub meanwhile leave the list
    // (nixbook-improve sync): at the start, then every 30 minutes while one waits.
    Process {
        id: syncProc
        command: ["nixbook-improve", "sync"]
    }
    Timer {
        interval: 30 * 60000
        repeat: true
        running: root.available && root.waiting.length > 0
        onTriggered: syncProc.running = true
    }

    FileView {
        id: mcpConfig
        path: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/nixbook-shell/desktop-mcp.json`
        printErrors: false
        onLoaded: {
            try {
                root.available = JSON.parse(mcpConfig.text()).improve === true
            } catch (e) {
                root.available = false
            }
            if (root.available) {
                tokenCheck.running = true
                syncProc.running = true
            }
        }
    }

    // Its own unit, the shell's PATH (nix, devenv) and Claude Code with it.
    // Named per call: a run waiting on CI or the user's answer keeps its
    // unit for hours, and a second one by the same name wouldn't start
    // (nixbook-improve's run lock keeps it to one fix at a time).
    function _start(name, args) {
        const unit = `${name}-${Date.now()}`
        const env = [`--setenv=PATH=${Quickshell.env("PATH")}`]
        if (Ai.claudeCodePath.length > 0) env.push(`--setenv=NIXBOOK_IMPROVE_CLAUDE=${Ai.claudeCodePath}`)
        // At the lowest CPU and disk priority: a fix's tests and headless
        // shell take only what the user's own work leaves.
        Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", `--unit=${unit}`,
            "-p", "RuntimeMaxSec=8h", "-p", "Nice=19", "-p", "CPUWeight=idle", "-p", "IOSchedulingClass=idle",
            ...env, "nixbook-improve", ...args])
    }

    // Something to fix, in the user's words (Settings).
    function note(text) {
        if (text.trim().length > 0) Quickshell.execDetached(["nixbook-improve", "note", text.trim()])
    }
    // A feature to build, in the user's words (Settings).
    function request(text) {
        if (text.trim().length > 0) Quickshell.execDetached(["nixbook-improve", "request", text.trim()])
    }
    // A fix item to the feature requests (one found too big, by hand).
    function toFeature(id) {
        Quickshell.execDetached(["nixbook-improve", "to-feature", id])
    }
    function dropItem(id) {
        Quickshell.execDetached(["nixbook-improve", "drop-item", id])
    }
    // "Fix now": this item, past the day's limit.
    function fixNow(id) {
        root._start("nixbook-improve-run", ["run", "--item", id])
    }
    // merge, drop or look, as the notification's buttons.
    function act(action, pr) {
        if (action === "look") Quickshell.execDetached(["nixbook-improve", "look", String(pr)])
        else root._start(`nixbook-improve-${action}-${pr}`, [action, String(pr)])
    }
    // Then a run, if that made an item ripe (its answer in the activity).
    function collectNow() {
        collectProc.running = true
    }

    // A ripe item of the user's: a run (nixbook-improve decides, the day's
    // limit and a run going on included).
    Timer {
        id: runSoon
        interval: 30000
        onTriggered: root._start("nixbook-improve-run", ["run", "--auto"])
    }

    // Also with features only: a request left for a later day gets its run.
    Timer {
        // Collect, then a run if that made an item ripe.
        id: collectTimer
        interval: 10 * 60000
        running: root.enabled || root.featuresEnabled
        onTriggered: {
            interval = 6 * 3600000
            restart()
            collectProc.running = true
        }
    }
    Process {
        id: collectProc
        command: ["nixbook-improve", "collect"]
        onExited: runSoon.restart()
    }

    Timer {
        interval: 5 * 60000
        running: (root.enabled || root.featuresEnabled) && root.runs.some(r => r.outcome === "merged" && !r.checked)
            && UpdateState.localRev !== "Unknown" && !UpdateState.localDirty
        onTriggered: root._start("nixbook-improve-health", ["health", UpdateState.localRev])
    }

    FileView {
        id: inboxFile
        path: `${root.dir}/inbox.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let items = []
            try {
                items = JSON.parse(inboxFile.text()).items ?? []
            } catch (e) {
                return // caught mid-write: the next change reads it whole
            }
            const before = new Set(root.inbox.map(i => `${i.id}:${i.count}`))
            root.inbox = items.slice().sort((a, b) => b.last - a.last)
            // A new report or feature request of the user's: a run soon.
            const fresh = i => i.status === "new" && !before.has(`${i.id}:${i.count}`)
            if ((root.enabled && items.some(i => i.kind === "user" && fresh(i)))
                    || (root.featuresEnabled && items.some(i => i.kind === "feature" && fresh(i))))
                runSoon.restart()
        }
    }

    FileView {
        id: runsFile
        path: `${root.dir}/runs.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.runs = (JSON.parse(runsFile.text()) ?? []).slice().reverse()
            } catch (e) {
            }
        }
    }
}
