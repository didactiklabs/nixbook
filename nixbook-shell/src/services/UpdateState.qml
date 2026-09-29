pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * NixOS update state — port of the DMS nixos-update plugin singleton
 * (assets/dms/plugins/nixos-update/UpdateState.qml) to nixbook-shell.
 *
 * Compares the deployed revision (/etc/nixos/version, JSON {rev, branch,
 * dirty}, e.g. nixbook's customNixOSModules.getRevision) against the remote
 * repository (updates.repoUrl; the check is off while it is empty), fetches the
 * changelog from the GitHub API, and drives the nixos-upgrade-manual systemd
 * oneshot (osupdate) plus its journal. Used by the bar widget
 * (modules/ii/bar/UpdatesCount.qml) and the Services settings page.
 *
 * Replaces upstream services/Updates.qml, which relied on a distro package
 * manager and was inert on NixOS.
 */
Singleton {
    id: root

    property string localRev: "Unknown"
    // Deployed from a tree with uncommitted changes: localRev is the commit
    // they were made on (older builds wrote an all-zero rev instead).
    property bool localDirty: false
    property string localBranch: "Unknown"
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string repoUrl: Config.options.updates.repoUrl
    property string repoOwner: ""
    property string repoName: ""
    property string changelogText: ""
    property bool updating: false
    property bool checking: false
    // When the last check ended ("" before the first), and why it failed
    // ("" when it worked): a check that finds nothing new still shows it ran.
    property string lastCheckTime: ""
    property string checkError: ""
    property bool viewingLogs: false
    property string logText: ""
    // The last nixos-upgrade-manual run: "success", "failed" or "" (never
    // ran this boot), when it ended, and its journal.
    property string lastResult: ""
    property string lastRunTime: ""
    property string lastRunLog: ""

    property bool started: false

    // Called from shell.qml on startup; safe to call repeatedly and before
    // Config has finished loading (start() is gated on Config.ready).
    function load() {
        root.start()
    }

    function start() {
        if (root.started || !Config.ready) return
        root.started = true
        root.monitorProcess.running = true
        root.lastRunProcess.running = true
        root.checkUpdate()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root.start()
        }
    }

    // Returns whether a check started (false: one is running, an update is,
    // or no repository is configured).
    function checkUpdate() {
        // No repository configured (updates.repoUrl): nothing to compare with.
        if (root.checking || root.updating || !root.repoUrl) return false
        root.checking = true
        root.checkError = ""
        root.checkWatchdog.restart()
        root.versionProcess.running = true
        return true
    }

    function finishCheck(error) {
        root.checkWatchdog.stop()
        root.checkError = error ?? ""
        root.lastCheckTime = Qt.formatTime(new Date(), "hh:mm")
        root.checking = false
    }

    // Every step has its own timeout; this only guarantees the button can
    // never stay stuck on "Checking..." (it used to, while `git ls-remote`
    // waited on a dead network).
    property Timer checkWatchdog: Timer {
        interval: 45000
        onTriggered: {
            root.remoteProcess.running = false
            root.changelogProcess.running = false
            root.finishCheck(Translation.tr("timed out"))
        }
    }

    function startUpdate() {
        if (root.updating) return false
        root.updating = true
        root.lastResult = ""
        root.lastRunLog = ""
        root.startUpdateProcess.running = true
        return true
    }

    function parseRepoUrl() {
        const parts = root.repoUrl.split('/')
        if (parts.length >= 5) {
            root.repoOwner = parts[3]
            root.repoName = parts[4]
        }
    }

    function compareRevs() {
        root.updateAvailable = (root.remoteRev !== "Unknown" && root.localRev !== root.remoteRev)
        root.fetchChangelog()
    }

    function fetchChangelog() {
        if (root.updateAvailable && root.localBranch === "refs/heads/main" && root.localRev !== "0".repeat(40)) {
            root.changelogProcess.running = true
        } else {
            root.changelogText = ""
            root.finishCheck()
        }
    }

    function startLogs() {
        root.logText = ""
        root.viewingLogs = true
        root.logProcess.running = true
    }

    function stopLogs() {
        root.logProcess.signal(15) // SIGTERM
        root.viewingLogs = false
    }

    property Process versionProcess: Process {
        command: ["cat", "/etc/nixos/version"]
        property string buffer: ""
        stdout: SplitParser {
            onRead: line => root.versionProcess.buffer += line
        }
        onExited: (code) => {
            if (code === 0 && root.versionProcess.buffer.trim()) {
                try {
                    const data = JSON.parse(root.versionProcess.buffer)
                    const rev = data.rev || ""
                    root.localDirty = data.dirty === true || /^0+$/.test(rev)
                    root.localRev = (rev && !/^0+$/.test(rev)) ? rev : "Unknown"
                    root.localBranch = data.branch || "Unknown"
                    root.parseRepoUrl()

                    // An unknown local rev still gets compared: any remote
                    // commit is then an update.
                    root.remoteProcess.running = true
                } catch (e) {
                    console.error("UpdateState: Failed to parse version:", e)
                    root.finishCheck(Translation.tr("unreadable /etc/nixos/version"))
                }
            } else {
                root.finishCheck(Translation.tr("no /etc/nixos/version"))
            }
            root.versionProcess.buffer = ""
        }
    }

    property Process remoteProcess: Process {
        // Bounded, and never prompting (credentials, ssh host keys): a
        // prompt nobody can answer used to hang the check.
        command: ["timeout", "20", "git", "ls-remote", root.repoUrl, "refs/heads/main"]
        environment: ({
            GIT_TERMINAL_PROMPT: "0",
            GIT_SSH_COMMAND: "ssh -o BatchMode=yes -o ConnectTimeout=10"
        })
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split('\t')
                if (parts.length > 0) root.remoteRev = parts[0].trim()
            }
        }
        onExited: code => {
            if (!root.checking) return // the watchdog gave up on it
            if (code === 0) {
                root.compareRevs()
            } else {
                root.finishCheck(code === 124 ? Translation.tr("timed out") : Translation.tr("can't reach the repository"))
            }
        }
    }

    property Process changelogProcess: Process {
        command: ["curl", "-sfL", "--max-time", "15", `https://api.github.com/repos/${root.repoOwner}/${root.repoName}/compare/${root.localRev}...${root.remoteRev}`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: line => root.changelogProcess.buffer += line
        }
        onExited: code => {
            if (!root.checking) { // the watchdog gave up on it
                root.changelogProcess.buffer = ""
                return
            }
            // The changelog is a bonus: the check succeeded without it
            // (e.g. GitHub's API rate limit).
            root.finishCheck()
            if (code === 0 && root.changelogProcess.buffer.trim()) {
                try {
                    const data = JSON.parse(root.changelogProcess.buffer)
                    root.changelogText = (data.commits || []).map(c => `- ${c.commit.message.split('\n')[0]}`).join('\n')
                } catch (e) {
                    console.error("UpdateState: Failed to parse changelog:", e)
                }
            }
            root.changelogProcess.buffer = ""
        }
    }

    property Process monitorProcess: Process {
        command: ["systemctl", "show", "-p", "ActiveState", "--value", "nixos-upgrade-manual.service"]
        property string state: ""
        stdout: SplitParser {
            onRead: line => root.monitorProcess.state = line.trim()
        }
        onExited: code => {
            if (root.monitorProcess.state === "active" || root.monitorProcess.state === "activating") {
                root.updating = true
                root.monitorTimer.start()
            } else {
                if (root.updating) {
                    root.updating = false
                    root.lastRunProcess.running = true
                    root.checkUpdate()
                }
            }
            root.monitorProcess.state = ""
        }
    }

    property Timer monitorTimer: Timer {
        interval: 2000
        onTriggered: root.monitorProcess.running = true
    }

    property Process startUpdateProcess: Process {
        command: ["systemctl", "start", "--no-block", "nixos-upgrade-manual.service"]
        onExited: code => {
            if (code !== 0) {
                root.updating = false
                root.checkUpdate()
            } else {
                root.monitorTimer.start()
                root.checkUpdate()
            }
        }
    }

    // Outcome + journal of the latest run (`--invocation=0`: that run only).
    property Process lastRunProcess: Process {
        // A finished oneshot is unloaded (its Result is gone) unless it
        // failed, so the time comes from the journal and the outcome from
        // the unit state plus the log (older osupdate builds exited 0 even
        // when colmena failed).
        command: ["bash", "-c", "echo ActiveState=$(systemctl show -p ActiveState --value nixos-upgrade-manual.service); "
            + "echo Time=$(journalctl -u nixos-upgrade-manual --invocation=0 -n 1 -o short --no-pager 2>/dev/null | cut -c1-15); "
            + "echo ---; journalctl -u nixos-upgrade-manual --invocation=0 -o cat --no-pager -n 400 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cut = text.indexOf("\n---\n")
                const props = {}
                for (const line of (cut >= 0 ? text.slice(0, cut) : text).split("\n")) {
                    const eq = line.indexOf("=")
                    if (eq > 0) props[line.slice(0, eq)] = line.slice(eq + 1).trim()
                }
                const log = cut >= 0 ? text.slice(cut + 5).replace(/\s+$/, "") : ""
                root.lastRunLog = log
                root.lastRunTime = props.Time ?? ""
                // Current osupdate exits 1 on failure and ends with
                // "updated to <rev>" on success: trust those. Nix/colmena
                // output of a successful deploy can contain "error:" lines,
                // so the log patterns are only a fallback for older builds.
                let result = ""
                if (log === "") result = ""
                else if (/^updated to \S+$/m.test(log)) result = "success"
                else if (props.ActiveState === "failed" || /Failed with result/.test(log)) result = "failed"
                else if (/panicked at|Failed to run command|^error:/m.test(log)) result = "failed"
                else if (/Finished|Deactivated successfully/.test(log)) result = "success"
                root.lastResult = result
            }
        }
    }

    property Process logProcess: Process {
        command: ["journalctl", "-u", "nixos-upgrade-manual", "-f", "--no-pager", "-o", "cat"]
        stdout: SplitParser {
            onRead: line => {
                root.logText += line + "\n"
                // Keep last 500 lines to avoid unbounded growth
                const lines = root.logText.split("\n")
                if (lines.length > 500) {
                    root.logText = lines.slice(-500).join("\n")
                }
            }
        }
        onExited: code => {
            root.viewingLogs = false
        }
    }

    // Periodic check — driven by the same config as the old service, so the
    // Services settings page (enable switch + interval) keeps working.
    property Timer updateTimer: Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        running: Config.ready && Config.options.updates.enableCheck
        repeat: true
        onTriggered: root.checkUpdate()
    }

    Component.onCompleted: root.start()
}
