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
 * fixes and polish only, each a PR with its changelog entry. The work is
 * `nixbook-improve`'s (improve/), in user units of its own (systemd-run),
 * outside the shell; this only starts it on events and shows its files:
 *   - an inbox item comes in (the user, through an agent's report_problem
 *     or Settings): a run, if one is ripe and the day's runs aren't made;
 *   - the shell's QML errors and the desktop tools' crashes are filed
 *     (`collect`: reading, no model) 10 minutes after the start, then every
 *     6 hours; a bug seen often enough gets a run;
 *   - 5 minutes after the start, the shell running a deployed fix is
 *     checked (`health`): a revert is offered if it broke.
 * The PR's Merge, Look, Drop come as a notification, and in Settings.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.ai?.improve?.enable ?? false
    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/improve`
    // Inbox items (newest first) and runs (newest first), as nixbook-improve wrote them.
    property var inbox: []
    property var runs: []
    readonly property var open: root.inbox.filter(i => ["new", "working", "pr"].includes(i.status))
    readonly property var waiting: root.runs.filter(r => r.outcome === "pr")
    readonly property var running: root.runs.find(r => !r.outcome && r.stage !== "done") ?? null

    function load() {
        inboxFile.reload()
        runsFile.reload()
    }

    // Its own unit, the shell's PATH (nix, devenv) and Claude Code with it.
    function _start(unit, args) {
        const env = [`--setenv=PATH=${Quickshell.env("PATH")}`]
        if (Ai.claudeCodePath.length > 0) env.push(`--setenv=NIXBOOK_IMPROVE_CLAUDE=${Ai.claudeCodePath}`)
        Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", `--unit=${unit}`,
            "-p", "RuntimeMaxSec=8h", ...env, "nixbook-improve", ...args])
    }

    // Something to fix, in the user's words (Settings).
    function note(text) {
        if (text.trim().length > 0) Quickshell.execDetached(["nixbook-improve", "note", text.trim()])
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
    function collectNow() {
        root._start("nixbook-improve-collect", ["collect"])
    }

    // A ripe item of the user's: a run (nixbook-improve decides, the day's
    // limit and a run going on included).
    Timer {
        id: runSoon
        interval: 30000
        onTriggered: root._start("nixbook-improve-run", ["run", "--auto"])
    }

    Timer {
        // Collect, then a run if that made an item ripe.
        id: collectTimer
        interval: 10 * 60000
        running: root.enabled
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
        running: root.enabled && root.runs.some(r => r.outcome === "merged" && !r.checked)
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
            // A new report of the user's: a run soon.
            if (root.enabled && items.some(i => i.kind === "user" && i.status === "new" && !before.has(`${i.id}:${i.count}`)))
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
