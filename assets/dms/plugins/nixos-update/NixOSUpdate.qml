import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ==================== Configuration ====================
    // Default timing intervals (in milliseconds)
    readonly property int defaultCheckIntervalMs: 5 * 60 * 1000  // 5 minutes
    readonly property int defaultProcessTimeoutMs: 30 * 1000     // 30 seconds
    readonly property int defaultMonitorPollMs: 2000              // 2 seconds
    readonly property int shortHashLen: 7                         // Git short SHA length

    // Settings-bound timing intervals (falls back to defaults)
    readonly property int checkIntervalMs: settings?.checkIntervalMs || root.defaultCheckIntervalMs
    readonly property int processTimeoutMs: settings?.processTimeoutMs || root.defaultProcessTimeoutMs
    readonly property int monitorPollMs: settings?.monitorPollMs || root.defaultMonitorPollMs

    // Service and repository configuration (settings-bound with defaults)
    property string systemdServiceName: settings?.systemdServiceName || "nixos-upgrade-manual.service"
    property string remoteBranch: settings?.remoteBranch || "refs/heads/main"
    property string repoUrl: settings?.repoUrl || "https://github.com/didactiklabs/nixbook"
    property string repoOwner: "didactiklabs"
    property string repoName: "nixbook"

    // ==================== State Properties ====================
    property string localRev: "Unknown"
    property string localBranch: "Unknown"
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string changelogText: ""
    property bool updating: false
    property bool checking: false

    // UI Configuration
    layerNamespacePlugin: "nixosUpdate"
    popoutWidth: 320
    popoutHeight: changelogText ? 600 : 300

    // ==================== Initialization & Periodic Checks ====================
    Timer {
        id: checkTimer
        interval: root.checkIntervalMs
        running: true
        repeat: true
        onTriggered: root.checkUpdate()

        Connections {
            target: root
            function onCheckIntervalMsChanged() {
                checkTimer.interval = root.checkIntervalMs
                checkTimer.restart()
            }
        }
    }

    Timer {
        id: processTimeoutTimer
        interval: root.processTimeoutMs
        onTriggered: {
            console.warn("NixOSUpdate: Process timeout detected")
            root.checking = false
        }

        Connections {
            target: root
            function onProcessTimeoutMsChanged() {
                processTimeoutTimer.interval = root.processTimeoutMs
            }
        }
    }

    Component.onCompleted: {
        monitorProcess.running = true
        checkUpdate()
    }

    // ==================== Core Functions ====================

    /**
     * Initiates update check sequence: version → remote → changelog
     * Prevents concurrent checks using the 'checking' flag
     */
    function checkUpdate() {
        if (checking || updating) return
        checking = true
        processTimeoutTimer.restart()
        versionProcess.running = true
    }

    /**
     * Parses repository URL to extract owner and name
     * Validates URL format to prevent silent failures
     */
    function parseRepoUrl() {
        const parts = repoUrl.split('/')
        if (parts.length >= 5) {
            repoOwner = parts[3]
            repoName = parts[4]
        } else {
            console.warn("NixOSUpdate: Invalid repo URL format:", repoUrl)
        }
    }

    /**
     * Compares local and remote revisions to determine update availability
     * Triggers changelog fetch if update is available
     */
    function compareRevs() {
        const isValid = localRev !== "Unknown" && remoteRev !== "Unknown"
        updateAvailable = isValid && localRev !== remoteRev
        fetchChangelog()
    }

    /**
     * Initiates changelog fetch only when applicable
     * Prevents fetching for non-main branches or zero-hashes
     */
    function fetchChangelog() {
        const isNullSha = localRev === "0".repeat(40)
        if (updateAvailable && localBranch === remoteBranch && !isNullSha) {
            changelogProcess.running = true
        } else {
            changelogText = ""
            checking = false
            processTimeoutTimer.stop()
        }
    }

    /**
     * Safely parses changelog from GitHub API response
     * Handles missing commit messages and malformed data gracefully
     */
    function parseChangelog(data) {
        if (!data || !data.commits || !Array.isArray(data.commits)) {
            return ""
        }

        return data.commits
            .map(c => c?.commit?.message?.split('\n')[0])
            .filter(msg => msg && msg.length > 0)
            .join('\n')
    }

    // ==================== Processes ====================

    /**
     * Reads local NixOS version from /etc/nixos/version
     * Expected format: { "rev": "hash...", "branch": "refs/heads/main" }
     */
    Process {
        id: versionProcess
        command: ["cat", "/etc/nixos/version"]
        property string buffer: ""

        onRunningChanged: if (running) buffer = ""  // Clear buffer on restart

        stdout: SplitParser {
            onRead: line => versionProcess.buffer += line
        }

        onExited: (code) => {
            if (code === 0 && buffer.trim()) {
                try {
                    const data = JSON.parse(buffer)
                    root.localRev = data.rev?.trim?.() || "Unknown"
                    root.localBranch = data.branch?.trim?.() || "Unknown"
                    root.parseRepoUrl()

                    if (root.localRev !== "Unknown") {
                        remoteProcess.running = true
                    } else {
                        root.checking = false
                        processTimeoutTimer.stop()
                    }
                } catch (e) {
                    console.error("NixOSUpdate: Failed to parse version file:", e)
                    root.checking = false
                    processTimeoutTimer.stop()
                }
            } else {
                if (code !== 0) {
                    console.warn("NixOSUpdate: Failed to read version file (exit code: " + code + ")")
                }
                root.checking = false
                processTimeoutTimer.stop()
            }
            buffer = ""
        }
    }

    /**
     * Fetches remote repository HEAD from git
     * Uses git ls-remote to avoid network overhead of full clone
     */
    Process {
        id: remoteProcess
        command: ["git", "ls-remote", root.repoUrl, root.remoteBranch]
        property string buffer: ""

        onRunningChanged: if (running) buffer = ""

        stdout: SplitParser {
            onRead: line => remoteProcess.buffer += line
        }

        onExited: code => {
            if (code === 0 && remoteProcess.buffer.trim()) {
                const parts = remoteProcess.buffer.trim().split('\t')
                if (parts.length > 0) {
                    root.remoteRev = parts[0].trim()
                    root.compareRevs()
                } else {
                    console.warn("NixOSUpdate: Unexpected git ls-remote output format")
                    root.checking = false
                    processTimeoutTimer.stop()
                }
            } else {
                if (code !== 0) {
                    console.warn("NixOSUpdate: Failed to fetch remote (exit code: " + code + ")")
                }
                root.checking = false
                processTimeoutTimer.stop()
            }
            buffer = ""
        }
    }

    /**
     * Fetches commit changelog from GitHub API
     * Only runs when an update is available
     */
    Process {
        id: changelogProcess
        command: ["curl", "-s", `https://api.github.com/repos/${root.repoOwner}/${root.repoName}/compare/${root.localRev}...${root.remoteRev}`]
        property string buffer: ""

        onRunningChanged: if (running) buffer = ""

        stdout: SplitParser {
            onRead: line => changelogProcess.buffer += line
        }

        onExited: code => {
            if (code === 0 && changelogProcess.buffer.trim()) {
                try {
                    const data = JSON.parse(changelogProcess.buffer)
                    root.changelogText = root.parseChangelog(data)
                } catch (e) {
                    console.error("NixOSUpdate: Failed to parse changelog:", e)
                    root.changelogText = ""
                }
            } else {
                if (code !== 0) {
                    console.warn("NixOSUpdate: Failed to fetch changelog (exit code: " + code + ")")
                }
                root.changelogText = ""
            }
            root.checking = false
            processTimeoutTimer.stop()
            buffer = ""
        }
    }

    /**
     * Monitors systemd service state to detect active upgrades
     * Periodically polls until service is no longer active
     */
    Process {
        id: monitorProcess
        command: ["systemctl", "--user", "show", "-p", "ActiveState", "--value", root.systemdServiceName]
        property string state: ""

        onRunningChanged: if (running) state = ""

        stdout: SplitParser {
            onRead: line => monitorProcess.state = line.trim()
        }

        onExited: code => {
            if (code === 0 && (monitorProcess.state === "active" || monitorProcess.state === "activating")) {
                root.updating = true
                monitorTimer.restart()
            } else {
                if (root.updating) {
                    root.updating = false
                    root.checkUpdate()
                }
                monitorTimer.stop()
            }
            state = ""
        }
    }

    Timer {
        id: monitorTimer
        interval: root.monitorPollMs
        onTriggered: monitorProcess.running = true

        Connections {
            target: root
            function onMonitorPollMsChanged() {
                monitorTimer.interval = root.monitorPollMs
            }
        }
    }

    /**
     * Initiates the NixOS upgrade via systemd service
     * Uses --no-block to prevent D-Bus connection errors during session reload
     */
    Process {
        id: startUpdateProcess
        command: ["systemctl", "--user", "start", "--no-block", root.systemdServiceName]

        onExited: code => {
            if (code !== 0) {
                console.error("NixOSUpdate: Failed to start upgrade service (exit code: " + code + ")")
                root.updating = false
                root.checkUpdate()
            } else {
                monitorTimer.restart()
                root.checkUpdate()
            }
        }
    }

    // ==================== UI Components ====================

    /**
     * Shared status icon and text component
     * Automatically rotates when checking or updating
     */
    Component {
        id: statusIcon
        DankIcon {
            name: "sync"
            size: Theme.iconSize
            color: root.updateAvailable ? Theme.primary : Theme.surfaceVariantText
            RotationAnimator on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: root.checking || root.updating
            }
        }
    }

    /**
     * Reusable status pill for both bar orientations
     * Eliminates duplicate layout code with single responsive component
     */
    Component {
        id: statusPillBase
        Item {
            property bool vertical: false
            implicitWidth: content.implicitWidth + Theme.spacingM
            implicitHeight: content.implicitHeight

            readonly property bool isActive: root.checking || root.updating || root.updateAvailable
            readonly property bool isAnimating: root.checking || root.updating

            QtObject {
                id: d
                readonly property string statusText: {
                    if (root.updating) return root.vertical ? "Upd..." : "Updating"
                    if (root.checking) return root.vertical ? "Chk..." : "Checking"
                    return root.vertical ? "Upd" : "Update"
                }
            }

            Loader {
                id: content
                anchors.centerIn: parent
                sourceComponent: vertical ? verticalLayout : horizontalLayout
            }

            Component {
                id: horizontalLayout
                Row {
                    spacing: Theme.spacingS
                    Loader {
                        sourceComponent: statusIcon
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        visible: parent.parent.isActive
                        text: d.statusText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Component {
                id: verticalLayout
                Column {
                    spacing: Theme.spacingS
                    Loader {
                        sourceComponent: statusIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        visible: parent.parent.isActive
                        text: d.statusText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    // Bar pills use shared statusPillBase with layout orientation
    horizontalBarPill: Loader {
        sourceComponent: statusPillBase
        onLoaded: item.vertical = false
    }

    verticalBarPill: Loader {
        sourceComponent: statusPillBase
        onLoaded: item.vertical = true
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "NixOS Update"
            detailsText: {
                if (root.updating) return "Updating system..."
                if (root.checking) return "Checking for updates..."
                return root.updateAvailable ? "New version available" : "System up to date"
            }
            showCloseButton: true

            /**
             * Displays a version hash with hover-to-expand tooltip behavior
             * Shows full hash on hover, abbreviated on normal view
             */
            component VersionDisplay: ColumnLayout {
                property string label: ""
                property string version: ""
                property bool highlight: false
                Layout.fillWidth: true
                spacing: Theme.spacingS

                StyledText {
                    text: label
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    text: {
                        const unknown = "Unknown"
                        if (version === unknown) return unknown
                        return ma.containsMouse ? version : version.substring(0, root.shortHashLen) + "..."
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: "Fira Code"
                    Layout.fillWidth: true
                    color: highlight ? Theme.primary : Theme.surfaceText

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }

            // Main popout layout
            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingM

                VersionDisplay {
                    label: "Current Version"
                    version: root.localRev
                }

                VersionDisplay {
                    label: "Latest Version"
                    version: root.remoteRev
                    highlight: root.updateAvailable
                }

                // Changelog section (only visible when available)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.changelogText !== ""
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Changelog"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        color: Theme.surfaceVariant
                        radius: Theme.cornerRadius

                        Flickable {
                            id: changelogFlickable
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            contentWidth: width
                            contentHeight: changelogLabel.paintedHeight
                            clip: true
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            StyledText {
                                id: changelogLabel
                                width: parent.width
                                text: root.changelogText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                // Update button
                DankButton {
                    Layout.fillWidth: true
                    text: root.updating ? "Updating..." : "Execute Update"
                    visible: root.updateAvailable || root.updating
                    enabled: !root.updating
                    onClicked: {
                        root.updating = true
                        startUpdateProcess.running = true
                    }
                }

                // Check updates button
                DankButton {
                    Layout.fillWidth: true
                    text: root.checking ? "Checking..." : "Check for Updates"
                    enabled: !root.checking && !root.updating
                    onClicked: root.checkUpdate()
                }
            }
        }
    }
}
