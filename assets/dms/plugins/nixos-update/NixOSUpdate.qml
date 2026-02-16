import QtQuick
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
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string repoUrl: "https://github.com/didactiklabs/nixbook"
    property string updateCmd: "osupdate"
    property string jsonBuffer: ""
    property string updateOutput: ""
    property bool updating: false

    layerNamespacePlugin: "nixosUpdate"
    popoutWidth: 320
    popoutHeight: root.updateOutput !== "" ? 600 : 300

    Timer {
        interval: 300000 // Check every 5 minutes
        running: true
        repeat: true
        onTriggered: {
            checkUpdate()
        }
    }

    Component.onCompleted: {
        checkUpdate()
    }

    function checkUpdate() {
        jsonBuffer = ""
        versionProcess.running = true
    }

    Process {
        id: versionProcess
        command: ["cat", "/etc/nixos/version"]
        stdout: SplitParser {
            onRead: line => {
                root.jsonBuffer += line
            }
        }
        onExited: (code) => {
            if (code === 0 && root.jsonBuffer.trim() !== "") {
                try {
                    var data = JSON.parse(root.jsonBuffer)
                    root.localRev = data.rev || "Unknown"
                    if (root.localRev !== "Unknown") {
                        remoteProcess.running = true
                    }
                } catch (e) {
                    console.log("Error parsing /etc/nixos/version: " + e)
                }
            }
        }
    }

    Process {
        id: remoteProcess
        command: ["git", "ls-remote", root.repoUrl, "refs/heads/main"]
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split('\t')
                if (parts.length > 0) {
                    root.remoteRev = parts[0].trim()
                }
            }
        }
        onExited: (code) => {
            if (code === 0) {
                compareRevs()
            }
        }
    }

    function compareRevs() {
        if (root.localRev !== "Unknown" && root.remoteRev !== "Unknown") {
            root.updateAvailable = (root.localRev !== root.remoteRev)
        } else {
            root.updateAvailable = false
        }
    }

    Process {
        id: updateProcess
        command: ["sh", "-c", root.updateCmd]
        stdout: SplitParser {
            onRead: line => {
                root.updateOutput += line + "\n"
            }
        }
        stderr: SplitParser {
            onRead: line => {
                root.updateOutput += line + "\n"
            }
        }
        onExited: (code) => {
            root.updating = false
            root.updateOutput += "\nProcess finished with exit code: " + code + "\n"
            console.log("Update command exited with code: " + code)
            root.checkUpdate()
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: row.implicitWidth + Theme.spacingM
            implicitHeight: row.implicitHeight

            Row {
                id: row
                spacing: Theme.spacingS
                anchors.centerIn: parent

                DankIcon {
                    name: "sync"
                    size: Theme.iconSize
                    color: root.updateAvailable ? Theme.primary : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                StyledText {
                    visible: root.updateAvailable
                    text: "Update"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: col.implicitWidth + Theme.spacingM
            implicitHeight: col.implicitHeight

            Column {
                id: col
                spacing: Theme.spacingS
                anchors.centerIn: parent

                DankIcon {
                    name: "sync"
                    size: Theme.iconSize
                    color: root.updateAvailable ? Theme.primary : Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                StyledText {
                    visible: root.updateAvailable
                    text: "Upd"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "NixOS Update"
            detailsText: root.updateAvailable ? "New version available" : "System up to date"
            showCloseButton: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingM

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Current Version"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        text: root.localRev.substring(0, 7) + "..."
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: "Fira Code"
                        Layout.fillWidth: true
                        color: Theme.surfaceText
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.text = root.localRev
                            onExited: parent.text = root.localRev.substring(0, 7) + "..."
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Latest Version"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        text: root.remoteRev !== "Unknown" ? root.remoteRev.substring(0, 7) + "..." : "Unknown"
                        font.pixelSize: Theme.fontSizeMedium
                        font.family: "Fira Code"
                        Layout.fillWidth: true
                        color: root.updateAvailable ? Theme.primary : Theme.surfaceText
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.text = root.remoteRev
                            onExited: parent.text = (root.remoteRev !== "Unknown" ? root.remoteRev.substring(0, 7) + "..." : "Unknown")
                        }
                    }
                }

                DankButton {
                    Layout.fillWidth: true
                    text: root.updating ? "Updating..." : "Execute Update"
                    visible: root.updateAvailable || root.updating
                    enabled: !root.updating
                    onClicked: {
                        root.updateOutput = ""
                        root.updating = true
                        updateProcess.running = true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 200
                    visible: root.updateOutput !== ""
                    color: Theme.surfaceVariant
                    radius: Theme.radiusS
                    
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
                            text: root.updateOutput
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
                    text: "Check for Updates"
                    onClicked: {
                        root.checkUpdate()
                    }
                }
            }
        }
    }
}
