import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool isConnected: false
    property string statusText: "Disconnected"
    property string currentIP: ""
    
    property var availableNetworks: []
    property var tempNetworks: []
    property bool showNetworkSelector: false
    property string selectedNetworkName: ""
    
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            statusProcess.running = true
            networksProcess.running = true
        }
    }

    Component.onCompleted: {
        statusProcess.running = true
        networksProcess.running = true
    }

    Process {
        id: statusProcess
        command: ["tailscale", "status", "--json"]
        
        property string accumulatedOutput: ""
        
        stdout: SplitParser {
            onRead: line => {
                statusProcess.accumulatedOutput += line
            }
        }
        
        onExited: (code) => {
            if (code === 0 || statusProcess.accumulatedOutput.length > 0) {
                 root.parseStatus(statusProcess.accumulatedOutput)
            }
            statusProcess.accumulatedOutput = ""
        }
    }

    function parseStatus(output) {
        try {
            var data = JSON.parse(output)
            var state = data.BackendState || "Stopped"
            isConnected = state === "Running"
            
            if (isConnected) {
                var ips = data.TailscaleIPs || []
                currentIP = ips.length > 0 ? ips[0] : ""
                statusText = "Connected"
            } else {
                currentIP = ""
                if (state !== "Stopped") {
                     statusText = state
                } else {
                     statusText = "Disconnected"
                }
            }
        } catch (e) {
            console.log("Error parsing tailscale status: " + e)
            // Only set error if we really can't determine state
            // If output was empty, maybe tailscaled is down
        }
    }

    Process {
        id: networksProcess
        command: ["tailscale", "switch", "--list"]
        stdout: SplitParser {
            onRead: line => {
                root.parseNetworkLine(line)
            }
        }
        onExited: (code) => {
            if (code === 0) {
                root.availableNetworks = root.tempNetworks
                root.tempNetworks = []
            }
        }
    }

    function parseNetworkLine(line) {
        var trimmed = line.trim()
        if (!trimmed || trimmed.startsWith("ID") || trimmed.startsWith("---")) return
        
        var parts = trimmed.split(/\s+/)
        if (parts.length < 3) return
        
        var id = parts[0]
        var tailnet = parts[1]
        var account = parts[2]
        var selected = false
        
        if (account.endsWith("*")) {
            selected = true
            account = account.substring(0, account.length - 1)
            root.selectedNetworkName = tailnet
        }
        
        var net = {
            id: id,
            name: tailnet,
            account: account,
            selected: selected
        }
        
        var list = root.tempNetworks
        list.push(net)
        root.tempNetworks = list
    }

    function toggleConnection() {
        if (root.isConnected) {
            toggleProcess.command = ["tailscale", "down"]
        } else {
            toggleProcess.command = ["tailscale", "up"]
        }
        toggleProcess.running = true
    }

    Process {
        id: toggleProcess
        // command is set dynamically
        onExited: (code) => {
            // Refresh status immediately after toggle finishes
            statusProcess.running = true
        }
    }
    
    property string networkToSwitch: ""
    
    function switchNetwork(networkName) {
        networkToSwitch = networkName
        switchNetworkProcess.running = true
    }
    
    Process {
        id: switchNetworkProcess
        command: ["tailscale", "switch", root.networkToSwitch]
        onExited: (code) => {
            statusProcess.running = true
            networksProcess.running = true
            root.showNetworkSelector = false
        }
    }

    layerNamespacePlugin: "tailscale"

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon {
                name: "vpn_lock"
                size: root.iconSize
                color: root.isConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.selectedNetworkName || root.statusText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DankIcon {
                name: "vpn_lock"
                size: root.iconSize
                color: root.isConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.selectedNetworkName || root.statusText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Tailscale"
            detailsText: root.isConnected ? "IP: " + root.currentIP : "Not connected"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.showNetworkSelector ? networkListColumn.height + Theme.spacingM : contentColumn.height + Theme.spacingM

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: !root.showNetworkSelector

                    Row {
                        spacing: Theme.spacingS
                        width: parent.width
                        DankIcon {
                            name: root.isConnected ? "check_circle" : "cancel"
                            size: Theme.iconSizeLarge
                            color: root.isConnected ? Theme.primary : Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText {
                                text: root.selectedNetworkName || root.statusText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: root.isConnected ? "Connected" : "Disconnected"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }

                    DankButton {
                        text: root.isConnected ? "Disconnect" : "Connect"
                        onClicked: {
                            toggleConnection()
                            popout.closePopout()
                        }
                    }

                    DankButton {
                        text: "Switch Account"
                        onClicked: {
                            root.showNetworkSelector = true
                            networksProcess.running = true
                        }
                    }
                }

                Column {
                    id: networkListColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.showNetworkSelector

                    StyledText {
                        width: parent.width
                        text: "Available Accounts"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    ScrollView {
                        width: parent.width
                        height: 150
                        GridView {
                            anchors.fill: parent
                            cellWidth: parent.width
                            cellHeight: 50
                            model: root.availableNetworks
                            delegate: StyledRect {
                                width: parent.width - 10
                                height: 45
                                radius: Theme.cornerRadius
                                color: modelData.selected ? Theme.primaryContainer : (networkMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                Row {
                                    spacing: Theme.spacingS
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingS
                                    DankIcon {
                                        name: modelData.selected ? "radio_button_checked" : "radio_button_unchecked"
                                        size: Theme.iconSize
                                        color: modelData.selected ? Theme.primary : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        StyledText {
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: modelData.account
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                    }
                                }
                                MouseArea {
                                    id: networkMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.switchNetwork(modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    DankButton {
                        text: "Back"
                        onClicked: {
                            root.showNetworkSelector = false
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 320
    popoutHeight: 350
}
