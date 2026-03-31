pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string localRev: "Unknown"
    property string localBranch: "Unknown"
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string repoUrl: "https://github.com/didactiklabs/nixbook"
    property string repoOwner: "didactiklabs"
    property string repoName: "nixbook"
    property string changelogText: ""
    property bool updating: false
    property bool checking: false
    property bool viewingLogs: false
    property string logText: ""

    function checkUpdate() {
        if (checking || updating) return
        checking = true
        versionProcess.running = true
    }

    function parseRepoUrl() {
        const parts = repoUrl.split('/')
        if (parts.length >= 5) {
            repoOwner = parts[3]
            repoName = parts[4]
        }
    }

    function compareRevs() {
        updateAvailable = (localRev !== "Unknown" && remoteRev !== "Unknown" && localRev !== remoteRev)
        fetchChangelog()
    }

    function fetchChangelog() {
        if (updateAvailable && localBranch === "refs/heads/main" && localRev !== "0".repeat(40)) {
            changelogProcess.running = true
        } else {
            changelogText = ""
            checking = false
        }
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
                    console.error("NixOSUpdate: Failed to parse version:", e)
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
                    console.error("NixOSUpdate: Failed to parse changelog:", e)
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

    function startLogs() {
        logText = ""
        viewingLogs = true
        logProcess.running = true
    }

    function stopLogs() {
        logProcess.signal(15) // SIGTERM
        viewingLogs = false
    }

    property Timer updateTimer: Timer {
        interval: 300000 // 5 minutes
        running: true
        repeat: true
        onTriggered: root.checkUpdate()
    }

    Component.onCompleted: {
        root.monitorProcess.running = true
        root.checkUpdate()
    }
}
