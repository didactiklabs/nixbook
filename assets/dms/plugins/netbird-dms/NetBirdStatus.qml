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
    property string peerCount: "0"
    property string currentIP: ""
    property string selectedNetwork: ""
    property var availableNetworks: []
    property var tempNetworks: []
    property bool showNetworkSelector: false
    property var parsingNetwork: ({})

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            statusProcess.running = true
            refreshNetworks()
        }
    }

    Component.onCompleted: {
        statusProcess.running = true
        refreshNetworks()
    }

    Process {
        id: statusProcess
        command: ["netbird", "status", "--json"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    root.parseStatus(line)
                }
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.resetStatus()
            }
        }
    }

    function parseStatus(output) {
        try {
            var data = JSON.parse(output)
            var connectedPeers = data.peers?.connected ?? 0
            isConnected = connectedPeers > 0 || data.management?.connected
            if (isConnected) {
                statusText = connectedPeers > 0 ? "Connected (" + connectedPeers + ")" : "Connecting"
                peerCount = connectedPeers.toString()
                currentIP = data.netbirdIp || ""
            } else {
                statusText = "Disconnected"
                peerCount = "0"
                currentIP = ""
            }
        } catch (e) {
            resetStatus()
        }
    }

    function resetStatus() {
        isConnected = false
        statusText = "Disconnected"
        peerCount = "0"
        currentIP = ""
        selectedNetwork = ""
    }

    function toggleConnection() {
        toggleProcess.running = true
    }

    Process {
        id: toggleProcess
        command: root.isConnected ? ["netbird", "down"] : ["netbird", "up"]
        onExited: () => {
            statusProcess.running = true
        }
    }

    function refreshNetworks() {
        tempNetworks = []
        parsingNetwork = {}
        // Don't clear availableNetworks immediately to prevent flickering
        networksProcess.running = true
    }

    Process {
        id: networksProcess
        command: ["netbird", "networks", "list"]
        stdout: SplitParser {
            onRead: line => {
                var trimmed = line.trim()
                if (trimmed.startsWith("- ID:")) {
                    // Push previous network if exists
                    if (root.parsingNetwork && root.parsingNetwork.id) {
                        var list = root.tempNetworks
                        list.push(root.parsingNetwork)
                        root.tempNetworks = list
                    }
                    
                    // Start parsing new network
                    var idMatch = trimmed.match(/- ID:\s*(.+)/)
                    root.parsingNetwork = {
                        id: idMatch ? idMatch[1].trim() : "",
                        name: "",
                        cidr: "",
                        selected: trimmed.includes("Selected")
                    }
                } else if (root.parsingNetwork && root.parsingNetwork.id) {
                    // Parse other fields
                    var nameMatch = trimmed.match(/Name:\s*(.+)/)
                    if (nameMatch) {
                        root.parsingNetwork.name = nameMatch[1].trim()
                    }
                    
                    var networkMatch = trimmed.match(/Network:\s*([\d.]+\/\d+)/)
                    if (networkMatch) {
                        root.parsingNetwork.cidr = networkMatch[1].trim()
                    }
                    
                    if (trimmed.includes("Selected")) {
                        root.parsingNetwork.selected = true
                    }
                }
            }
        }
        onExited: (code) => {
            // Push the last network
            if (root.parsingNetwork && root.parsingNetwork.id) {
                var list = root.tempNetworks
                list.push(root.parsingNetwork)
                root.tempNetworks = list
            }
            
            // Update the main list
            root.availableNetworks = root.tempNetworks
            
            // Update selected network name
            var foundSelected = false
            for (var i = 0; i < root.availableNetworks.length; i++) {
                var net = root.availableNetworks[i]
                if (net.selected) {
                    root.selectedNetwork = net.name || net.id
                    foundSelected = true
                    break
                }
            }
            if (!foundSelected) {
                root.selectedNetwork = ""
            }
            
            root.parsingNetwork = {}
        }
    }

    property string networkIdToSelect: ""

    function onNetworkClicked(networkId) {
        networkIdToSelect = networkId
        selectNetworkProcess.running = true
    }

    function selectNetwork(networkId) {
        networkIdToSelect = networkId
        selectNetworkProcess.running = true
    }

    Process {
        id: selectNetworkProcess
        command: ["netbird", "networks", "select", root.networkIdToSelect]
        onExited: (code) => {
            if (code === 0) {
                statusProcess.running = true
                refreshNetworks()
            }
            showNetworkSelector = false
        }
    }

    layerNamespacePlugin: "netbird"

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon {
                name: root.isConnected ? "vpn_key" : "vpn_key_off"
                size: root.iconSize
                color: root.isConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.selectedNetwork || root.statusText
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
                name: root.isConnected ? "vpn_key" : "vpn_key_off"
                size: root.iconSize
                color: root.isConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.selectedNetwork || root.statusText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "NetBird VPN"
            detailsText: root.isConnected ? "IP: " + root.currentIP : "Not connected"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.showNetworkSelector ? selectorColumn.height + Theme.spacingM : contentColumn.height + Theme.spacingM

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
                                text: root.selectedNetwork || root.statusText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: root.isConnected ? root.peerCount + " peers" : ""
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
                        text: "Select Network"
                        onClicked: {
                            refreshNetworks()
                            root.showNetworkSelector = true
                        }
                    }
                }

                Column {
                    id: selectorColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.showNetworkSelector

                    StyledText {
                        width: parent.width
                        text: "Available Networks"
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
                                            text: modelData.name || modelData.id
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: modelData.cidr
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
                                        root.onNetworkClicked(modelData.id)
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
