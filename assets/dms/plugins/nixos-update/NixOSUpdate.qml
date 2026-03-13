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

    property string localRev: "Unknown"
    property string localBranch: "Unknown"
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string repoUrl: "https://github.com/didactiklabs/nixbook"
    property string repoOwner: "didactiklabs"
    property string repoName: "nixbook"
    property string updateCmd: "osupdate"
    property string updateOutput: ""
    property string changelogText: ""
    property bool updating: false
    property bool checking: false

    layerNamespacePlugin: "nixosUpdate"
    popoutWidth: 320
    popoutHeight: (updateOutput || changelogText) ? 600 : 300

    Timer {
        interval: 300000 // 5 minutes
        running: true
        repeat: true
        onTriggered: checkUpdate()
    }

    Component.onCompleted: checkUpdate()

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

    Process {
        id: versionProcess
        command: ["cat", "/etc/nixos/version"]
        property string buffer: ""
        stdout: SplitParser {
            onRead: line => versionProcess.buffer += line
        }
        onExited: (code) => {
            if (code === 0 && buffer.trim()) {
                try {
                    const data = JSON.parse(buffer)
                    localRev = data.rev || "Unknown"
                    localBranch = data.branch || "Unknown"
                    parseRepoUrl()

                    if (localRev !== "Unknown") {
                        remoteProcess.running = true
                    } else {
                        checking = false
                    }
                } catch (e) {
                    console.error("NixOSUpdate: Failed to parse version:", e)
                    checking = false
                }
            } else {
                checking = false
            }
            buffer = ""
        }
    }

    Process {
        id: remoteProcess
        command: ["git", "ls-remote", repoUrl, "refs/heads/main"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split('\t')
                if (parts.length > 0) remoteRev = parts[0].trim()
            }
        }
        onExited: code => {
            if (code === 0) {
                compareRevs()
            } else {
                checking = false
            }
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

    Process {
        id: changelogProcess
        command: ["curl", "-s", `https://api.github.com/repos/${repoOwner}/${repoName}/compare/${localRev}...${remoteRev}`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: line => changelogProcess.buffer += line
        }
        onExited: code => {
            checking = false
            if (code === 0 && buffer.trim()) {
                try {
                    const data = JSON.parse(buffer)
                    changelogText = (data.commits || []).map(c => `- ${c.commit.message.split('\n')[0]}`).join('\n')
                } catch (e) {
                    console.error("NixOSUpdate: Failed to parse changelog:", e)
                }
            }
            buffer = ""
        }
    }

    Process {
        id: updateProcess
        // Stream logs from the systemd service
        command: ["journalctl", "--user", "-u", "nixos-upgrade-manual.service", "-f", "-n", "0", "--output=cat"]
        stdout: SplitParser {
            onRead: line => updateOutput += line + "\n"
        }
        stderr: SplitParser {
            onRead: line => updateOutput += line + "\n"
        }
        onExited: code => {
            if (updating) {
                updateOutput += `\n[Log monitor exited with code ${code}]\n`
            }
        }
    }

    Process {
        id: monitorProcess
        command: ["systemctl", "--user","is-active", "--quiet", "nixos-upgrade-manual.service"]
        onExited: code => {
            if (code !== 0) { // Service stopped
                updating = false
                updateProcess.running = false
                checkUpdate()
            } else {
                monitorTimer.start()
            }
        }
    }

    Timer {
        id: monitorTimer
        interval: 2000
        onTriggered: monitorProcess.running = true
    }

    Process {
        id: startUpdateProcess
        command: ["systemctl", "--user", "start", "--no-block", "nixos-upgrade-manual.service"]
        onExited: code => {
            // Using --no-block prevents systemctl from waiting for the job to finish.
            // This avoids "D-Bus connection terminated" errors when the update 
            // reloads the user session.
            if (code !== 0) {
                updateOutput += `\nFailed to trigger update service (code ${code}).\n`
                updating = false
                updateProcess.running = false
            } else {
                updateOutput += "Update service successfully triggered. Monitoring logs...\n"
                monitorProcess.running = true
            }
        }
    }

    Component {
        id: statusPillBase
        Item {
            property bool vertical: false
            implicitWidth: content.implicitWidth + Theme.spacingM
            implicitHeight: content.implicitHeight

            readonly property bool isActive: checking || updating || updateAvailable

            QtObject {
                id: d
                readonly property string statusText: {
                    if (updating) return vertical ? "Upd..." : "Updating"
                    if (checking) return vertical ? "Chk..." : "Checking"
                    return vertical ? "Upd" : "Update"
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
                    DankIcon {
                        name: "sync"
                        size: Theme.iconSize
                        color: updateAvailable ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 1000
                            loops: Animation.Infinite
                            running: checking || updating
                        }
                    }
                    StyledText {
                        visible: isActive
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
                    DankIcon {
                        name: "sync"
                        size: Theme.iconSize
                        color: updateAvailable ? Theme.primary : Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 1000
                            loops: Animation.Infinite
                            running: checking || updating
                        }
                    }
                    StyledText {
                        visible: isActive
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
            detailsText: updating ? "Updating system..." : (checking ? "Checking for updates..." : (updateAvailable ? "New version available" : "System up to date"))
            showCloseButton: true

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
                    text: ma.containsMouse ? version : (version !== "Unknown" ? version.substring(0, 7) + "..." : "Unknown")
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: "Fira Code"
                    Layout.fillWidth: true
                    color: highlight ? Theme.primary : Theme.surfaceText
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingM

                VersionDisplay {
                    label: "Current Version"
                    version: localRev
                }

                VersionDisplay {
                    label: "Latest Version"
                    version: remoteRev
                    highlight: updateAvailable
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: changelogText !== ""
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
                            ScrollBar.vertical: ScrollBar {}

                            StyledText {
                                id: changelogLabel
                                width: parent.width
                                text: changelogText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                DankButton {
                    Layout.fillWidth: true
                    text: updating ? "Updating..." : "Execute Update"
                    visible: updateAvailable || updating
                    enabled: !updating
                    onClicked: {
                        updateOutput = ""
                        updating = true
                        updateOutput += "Starting log monitor...\n"
                        updateProcess.running = true
                        startUpdateProcess.running = true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 200
                    visible: updateOutput !== ""
                    color: Theme.surfaceVariant
                    radius: Theme.cornerRadius

                    Flickable {
                        id: logFlickable
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        contentWidth: logText.width
                        contentHeight: logText.height
                        clip: true

                        StyledText {
                            id: logText
                            width: logFlickable.width
                            text: updateOutput
                            font.family: "Fira Code"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            wrapMode: Text.WrapAnywhere
                            onTextChanged: {
                                if (logFlickable.contentHeight > logFlickable.height) {
                                    logFlickable.contentY = logFlickable.contentHeight - logFlickable.height
                                }
                            }
                        }
                    }
                }

                DankButton {
                    Layout.fillWidth: true
                    text: checking ? "Checking..." : "Check for Updates"
                    enabled: !checking && !updating
                    onClicked: checkUpdate()
                }
            }
        }
    }
}
