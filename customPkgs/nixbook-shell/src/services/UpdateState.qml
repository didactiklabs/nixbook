pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * NixOS update state — port of the DMS nixos-update plugin singleton
 * (assets/dms/plugins/nixos-update/UpdateState.qml) to nixbook-shell.
 *
 * Compares the deployed revision (/etc/nixos/version, written by
 * customNixOSModules.getRevision) against the remote repository, fetches the
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
    property string localBranch: "Unknown"
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string repoUrl: Config.options.updates.repoUrl
    property string repoOwner: "didactiklabs"
    property string repoName: "nixbook"
    property string changelogText: ""
    property bool updating: false
    property bool checking: false
    property bool viewingLogs: false
    property string logText: ""

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
        root.checkUpdate()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root.start()
        }
    }

    function checkUpdate() {
        if (root.checking || root.updating) return
        root.checking = true
        root.versionProcess.running = true
    }

    function startUpdate() {
        if (root.updating) return false
        root.updating = true
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
        root.updateAvailable = (root.localRev !== "Unknown" && root.remoteRev !== "Unknown" && root.localRev !== root.remoteRev)
        root.fetchChangelog()
    }

    function fetchChangelog() {
        if (root.updateAvailable && root.localBranch === "refs/heads/main" && root.localRev !== "0".repeat(40)) {
            root.changelogProcess.running = true
        } else {
            root.changelogText = ""
            root.checking = false
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
                    root.localRev = data.rev || "Unknown"
                    root.localBranch = data.branch || "Unknown"
                    root.parseRepoUrl()

                    if (root.localRev !== "Unknown") {
                        root.remoteProcess.running = true
                    } else {
                        root.checking = false
                    }
                } catch (e) {
                    console.error("UpdateState: Failed to parse version:", e)
                    root.checking = false
                }
            } else {
                root.checking = false
            }
            root.versionProcess.buffer = ""
        }
    }

    property Process remoteProcess: Process {
        command: ["git", "ls-remote", root.repoUrl, "refs/heads/main"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split('\t')
                if (parts.length > 0) root.remoteRev = parts[0].trim()
            }
        }
        onExited: code => {
            if (code === 0) {
                root.compareRevs()
            } else {
                root.checking = false
            }
        }
    }

    property Process changelogProcess: Process {
        command: ["curl", "-s", `https://api.github.com/repos/${root.repoOwner}/${root.repoName}/compare/${root.localRev}...${root.remoteRev}`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: line => root.changelogProcess.buffer += line
        }
        onExited: code => {
            root.checking = false
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
