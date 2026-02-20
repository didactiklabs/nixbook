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

    // --- Tailscale Properties ---
    property bool tailscaleIsConnected: false
    property string tailscaleStatusText: "Disconnected"
    property string tailscaleCurrentIP: ""
    property var tailscaleAvailableNetworks: []
    property var tailscaleTempNetworks: []
    property bool tailscaleShowNetworkSelector: false
    property string tailscaleSelectedNetworkName: ""
    property string tailscaleNetworkToSwitch: ""

    // --- NetBird Properties ---
    property bool netbirdIsConnected: false
    property string netbirdStatusText: "Disconnected"
    property string netbirdPeerCount: "0"
    property string netbirdCurrentIP: ""
    property string netbirdSelectedNetwork: ""
    property var netbirdAvailableNetworks: []
    property var netbirdTempNetworks: []
    property bool netbirdShowNetworkSelector: false
    property var netbirdParsingNetwork: ({})
    property string netbirdNetworkIdToSelect: ""

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            tailscaleStatusProcess.running = true
            tailscaleNetworksProcess.running = true
            netbirdStatusProcess.running = true
            netbirdRefreshNetworks()
        }
    }

    Component.onCompleted: {
        tailscaleStatusProcess.running = true
        tailscaleNetworksProcess.running = true
        netbirdStatusProcess.running = true
        netbirdRefreshNetworks()
    }

    // --- Tailscale Logic ---

    Process {
        id: tailscaleStatusProcess
        command: ["tailscale", "status", "--json"]
        
        property string accumulatedOutput: ""
        
        stdout: SplitParser {
            onRead: line => {
                tailscaleStatusProcess.accumulatedOutput += line
            }
        }
        
        onExited: (code) => {
            if (code === 0 || tailscaleStatusProcess.accumulatedOutput.length > 0) {
                 root.tailscaleParseStatus(tailscaleStatusProcess.accumulatedOutput)
            }
            tailscaleStatusProcess.accumulatedOutput = ""
        }
    }

    function tailscaleParseStatus(output) {
        try {
            var data = JSON.parse(output)
            var state = data.BackendState || "Stopped"
            tailscaleIsConnected = state === "Running"
            
            if (tailscaleIsConnected) {
                var ips = data.TailscaleIPs || []
                tailscaleCurrentIP = ips.length > 0 ? ips[0] : ""
                tailscaleStatusText = "Connected"
            } else {
                tailscaleCurrentIP = ""
                if (state !== "Stopped") {
                     tailscaleStatusText = state
                } else {
                     tailscaleStatusText = "Disconnected"
                }
            }
        } catch (e) {
            console.log("Error parsing tailscale status: " + e)
        }
    }

    Process {
        id: tailscaleNetworksProcess
        command: ["tailscale", "switch", "--list"]
        stdout: SplitParser {
            onRead: line => {
                root.tailscaleParseNetworkLine(line)
            }
        }
        onExited: (code) => {
            if (code === 0) {
                root.tailscaleAvailableNetworks = root.tailscaleTempNetworks
                root.tailscaleTempNetworks = []
            }
        }
    }

    function tailscaleParseNetworkLine(line) {
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
            root.tailscaleSelectedNetworkName = tailnet
        }
        
        var net = {
            id: id,
            name: tailnet,
            account: account,
            selected: selected
        }
        
        var list = root.tailscaleTempNetworks
        list.push(net)
        root.tailscaleTempNetworks = list
    }

    function tailscaleToggleConnection() {
        if (root.tailscaleIsConnected) {
            tailscaleToggleProcess.command = ["tailscale", "down"]
        } else {
            tailscaleToggleProcess.command = ["tailscale", "up"]
        }
        tailscaleToggleProcess.running = true
    }

    Process {
        id: tailscaleToggleProcess
        // command is set dynamically
        onExited: (code) => {
            tailscaleStatusProcess.running = true
        }
    }
    
    function tailscaleSwitchNetwork(networkName) {
        tailscaleNetworkToSwitch = networkName
        tailscaleSwitchNetworkProcess.running = true
    }
    
    Process {
        id: tailscaleSwitchNetworkProcess
        command: ["tailscale", "switch", root.tailscaleNetworkToSwitch]
        onExited: (code) => {
            tailscaleStatusProcess.running = true
            tailscaleNetworksProcess.running = true
            root.tailscaleShowNetworkSelector = false
        }
    }

    // --- NetBird Logic ---

    Process {
        id: netbirdStatusProcess
        command: ["netbird", "status", "--json"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim()) {
                    root.netbirdParseStatus(line)
                }
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.netbirdResetStatus()
            }
        }
    }

    function netbirdParseStatus(output) {
        try {
            var data = JSON.parse(output)
            var connectedPeers = data.peers?.connected ?? 0
            netbirdIsConnected = connectedPeers > 0 || data.management?.connected
            if (netbirdIsConnected) {
                netbirdStatusText = connectedPeers > 0 ? "Connected (" + connectedPeers + ")" : "Connecting"
                netbirdPeerCount = connectedPeers.toString()
                netbirdCurrentIP = data.netbirdIp || ""
            } else {
                netbirdStatusText = "Disconnected"
                netbirdPeerCount = "0"
                netbirdCurrentIP = ""
            }
        } catch (e) {
            netbirdResetStatus()
        }
    }

    function netbirdResetStatus() {
        netbirdIsConnected = false
        netbirdStatusText = "Disconnected"
        netbirdPeerCount = "0"
        netbirdCurrentIP = ""
        netbirdSelectedNetwork = ""
    }

    function netbirdToggleConnection() {
        netbirdToggleProcess.running = true
    }

    Process {
        id: netbirdToggleProcess
        command: root.netbirdIsConnected ? ["netbird", "down"] : ["netbird", "up"]
        onExited: () => {
            netbirdStatusProcess.running = true
        }
    }

    function netbirdRefreshNetworks() {
        netbirdTempNetworks = []
        netbirdParsingNetwork = {}
        netbirdNetworksProcess.running = true
    }

    Process {
        id: netbirdNetworksProcess
        command: ["netbird", "networks", "list"]
        stdout: SplitParser {
            onRead: line => {
                var trimmed = line.trim()
                if (trimmed.startsWith("- ID:")) {
                    if (root.netbirdParsingNetwork && root.netbirdParsingNetwork.id) {
                        var list = root.netbirdTempNetworks
                        list.push(root.netbirdParsingNetwork)
                        root.netbirdTempNetworks = list
                    }
                    var idMatch = trimmed.match(/- ID:\s*(.+)/)
                    root.netbirdParsingNetwork = {
                        id: idMatch ? idMatch[1].trim() : "",
                        name: "",
                        cidr: "",
                        selected: trimmed.includes("Selected")
                    }
                } else if (root.netbirdParsingNetwork && root.netbirdParsingNetwork.id) {
                    var nameMatch = trimmed.match(/Name:\s*(.+)/)
                    if (nameMatch) {
                        root.netbirdParsingNetwork.name = nameMatch[1].trim()
                    }
                    var networkMatch = trimmed.match(/Network:\s*([\d.]+\/\d+)/)
                    if (networkMatch) {
                        root.netbirdParsingNetwork.cidr = networkMatch[1].trim()
                    }
                    if (trimmed.includes("Selected")) {
                        root.netbirdParsingNetwork.selected = true
                    }
                }
            }
        }
        onExited: (code) => {
            if (root.netbirdParsingNetwork && root.netbirdParsingNetwork.id) {
                var list = root.netbirdTempNetworks
                list.push(root.netbirdParsingNetwork)
                root.netbirdTempNetworks = list
            }
            root.netbirdAvailableNetworks = root.netbirdTempNetworks
            
            var foundSelected = false
            for (var i = 0; i < root.netbirdAvailableNetworks.length; i++) {
                var net = root.netbirdAvailableNetworks[i]
                if (net.selected) {
                    root.netbirdSelectedNetwork = net.name || net.id
                    foundSelected = true
                    break
                }
            }
            if (!foundSelected) {
                root.netbirdSelectedNetwork = ""
            }
            root.netbirdParsingNetwork = {}
        }
    }

    function netbirdOnNetworkClicked(networkId) {
        netbirdNetworkIdToSelect = networkId
        netbirdSelectNetworkProcess.running = true
    }

    Process {
        id: netbirdSelectNetworkProcess
        command: ["netbird", "networks", "select", root.netbirdNetworkIdToSelect]
        onExited: (code) => {
            if (code === 0) {
                netbirdStatusProcess.running = true
                netbirdRefreshNetworks()
            }
            netbirdShowNetworkSelector = false
        }
    }

    layerNamespacePlugin: "vpnStatus"

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon {
                name: "vpn_lock"
                size: root.iconSize
                color: root.tailscaleIsConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            DankIcon {
                name: "vpn_key"
                size: root.iconSize
                color: root.netbirdIsConnected ? Theme.primary : Theme.surfaceVariantText
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
                color: root.tailscaleIsConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            DankIcon {
                name: "vpn_key"
                size: root.iconSize
                color: root.netbirdIsConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "VPN Status"
            detailsText: (root.tailscaleIsConnected ? "Tailscale: Connected " : "") + (root.netbirdIsConnected ? "NetBird: Connected" : "")
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: (root.tailscaleShowNetworkSelector || root.netbirdShowNetworkSelector) ? 350 : contentColumn.height + Theme.spacingM

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.spacingL
                    visible: !root.tailscaleShowNetworkSelector && !root.netbirdShowNetworkSelector

                    // --- Tailscale Section ---
                    Column {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            text: "Tailscale"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        Row {
                            spacing: Theme.spacingS
                            width: parent.width
                            DankIcon {
                                name: root.tailscaleIsConnected ? "check_circle" : "cancel"
                                size: Theme.iconSizeLarge
                                color: root.tailscaleIsConnected ? Theme.primary : Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: root.tailscaleSelectedNetworkName || root.tailscaleStatusText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: root.tailscaleIsConnected ? "IP: " + root.tailscaleCurrentIP : "Disconnected"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }

                        Row {
                            spacing: Theme.spacingS
                            width: parent.width
                            DankButton {
                                width: (parent.width - Theme.spacingS) / 2
                                text: root.tailscaleIsConnected ? "Disconnect" : "Connect"
                                onClicked: root.tailscaleToggleConnection()
                            }
                            DankButton {
                                width: (parent.width - Theme.spacingS) / 2
                                text: "Switch Account"
                                onClicked: {
                                    root.tailscaleShowNetworkSelector = true
                                    root.tailscaleNetworksProcess.running = true
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.surfaceContainerHighest
                    }

                    // --- NetBird Section ---
                    Column {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            text: "NetBird"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        Row {
                            spacing: Theme.spacingS
                            width: parent.width
                            DankIcon {
                                name: root.netbirdIsConnected ? "check_circle" : "cancel"
                                size: Theme.iconSizeLarge
                                color: root.netbirdIsConnected ? Theme.primary : Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: root.netbirdSelectedNetwork || root.netbirdStatusText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: root.netbirdIsConnected ? "IP: " + root.netbirdCurrentIP : "Disconnected"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }

                        Row {
                            spacing: Theme.spacingS
                            width: parent.width
                            DankButton {
                                width: (parent.width - Theme.spacingS) / 2
                                text: root.netbirdIsConnected ? "Disconnect" : "Connect"
                                onClicked: root.netbirdToggleConnection()
                            }
                            DankButton {
                                width: (parent.width - Theme.spacingS) / 2
                                text: "Select Network"
                                onClicked: {
                                    root.netbirdRefreshNetworks()
                                    root.netbirdShowNetworkSelector = true
                                }
                            }
                        }
                    }
                }

                // --- Tailscale Network Selector ---
                Column {
                    id: tailscaleNetworkListColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tailscaleShowNetworkSelector

                    StyledText {
                        width: parent.width
                        text: "Tailscale Accounts"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    ScrollView {
                        width: parent.width
                        height: 250
                        clip: true
                        GridView {
                            anchors.fill: parent
                            cellWidth: parent.width
                            cellHeight: 50
                            model: root.tailscaleAvailableNetworks
                            delegate: StyledRect {
                                width: parent.width - 10
                                height: 45
                                radius: Theme.cornerRadius
                                color: modelData.selected ? Theme.primaryContainer : (tsMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
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
                                    id: tsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.tailscaleSwitchNetwork(modelData.name)
                                }
                            }
                        }
                    }

                    DankButton {
                        text: "Back"
                        onClicked: root.tailscaleShowNetworkSelector = false
                    }
                }

                // --- NetBird Network Selector ---
                Column {
                    id: netbirdNetworkListColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.netbirdShowNetworkSelector

                    StyledText {
                        width: parent.width
                        text: "NetBird Networks"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    ScrollView {
                        width: parent.width
                        height: 250
                        clip: true
                        GridView {
                            anchors.fill: parent
                            cellWidth: parent.width
                            cellHeight: 50
                            model: root.netbirdAvailableNetworks
                            delegate: StyledRect {
                                width: parent.width - 10
                                height: 45
                                radius: Theme.cornerRadius
                                color: modelData.selected ? Theme.primaryContainer : (nbMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
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
                                    id: nbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.netbirdOnNetworkClicked(modelData.id)
                                }
                            }
                        }
                    }

                    DankButton {
                        text: "Back"
                        onClicked: root.netbirdShowNetworkSelector = false
                    }
                }
            }
        }
    }

    popoutWidth: 350
    popoutHeight: 450
}
