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

    // --- Settings ---
    property bool enableTailscale: pluginData.enableTailscale !== undefined ? pluginData.enableTailscale : true
    property bool enableNetbird: pluginData.enableNetbird !== undefined ? pluginData.enableNetbird : true

    // --- Tailscale Properties ---
    property bool tailscaleIsConnected: false
    property string tailscaleStatusText: "Disconnected"
    property string tailscaleCurrentIP: ""
    property var tailscaleAvailableNetworks: []
    property var tailscaleTempNetworks: []
    property bool tailscaleShowNetworkSelector: false
    property string tailscaleSelectedNetworkName: ""
    property string tailscaleNetworkToSwitch: ""

    // --- Tailscale Exit Node Properties ---
    property var tailscaleExitNodes: []
    property string tailscaleCurrentExitNode: ""
    property string tailscaleCurrentExitNodeIP: ""
    property bool tailscaleShowExitNodeSelector: false
    property string tailscaleExitNodeToSet: ""

    // --- NetBird Properties ---
    property bool netbirdIsConnected: false
    property string netbirdStatusText: "Disconnected"
    property string netbirdPeerCount: "0"
    property string netbirdCurrentIP: ""
    property string netbirdSelectedProfile: ""
    property var netbirdAvailableProfiles: []
    property var netbirdTempProfiles: []
    property bool netbirdShowProfileSelector: false
    property var netbirdParsingProfile: ({})
    property string netbirdProfileToSelect: ""

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (root.enableTailscale) {
                tailscaleStatusProcess.running = true
                tailscaleNetworksProcess.running = true
            }
            if (root.enableNetbird) {
                netbirdStatusProcess.running = true
                netbirdRefreshProfiles()
            }
        }
    }

    Component.onCompleted: {
        if (root.enableTailscale) {
            tailscaleStatusProcess.running = true
            tailscaleNetworksProcess.running = true
        }
        if (root.enableNetbird) {
            netbirdStatusProcess.running = true
            netbirdRefreshProfiles()
        }
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

                // Parse exit nodes from peers
                var exitNodes = []
                var currentExit = ""
                var currentExitIP = ""
                var peers = data.Peer || {}
                for (var key in peers) {
                    var peer = peers[key]
                    if (peer.ExitNodeOption) {
                        var node = {
                            hostname: peer.HostName || "",
                            ip: (peer.TailscaleIPs && peer.TailscaleIPs.length > 0) ? peer.TailscaleIPs[0] : "",
                            online: peer.Online || false,
                            active: peer.ExitNode || false,
                            os: peer.OS || "",
                            country: (peer.Location && peer.Location.Country) ? peer.Location.Country : "",
                            city: (peer.Location && peer.Location.City) ? peer.Location.City : ""
                        }
                        exitNodes.push(node)
                        if (peer.ExitNode) {
                            currentExit = peer.HostName || ""
                            currentExitIP = node.ip
                        }
                    }
                }
                tailscaleExitNodes = exitNodes
                tailscaleCurrentExitNode = currentExit
                tailscaleCurrentExitNodeIP = currentExitIP
            } else {
                tailscaleCurrentIP = ""
                tailscaleExitNodes = []
                tailscaleCurrentExitNode = ""
                tailscaleCurrentExitNodeIP = ""
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

    // --- Tailscale Exit Node Logic ---

    function tailscaleSetExitNode(hostname) {
        tailscaleExitNodeToSet = hostname
        tailscaleSetExitNodeProcess.command = ["tailscale", "set", "--exit-node=" + hostname]
        tailscaleSetExitNodeProcess.running = true
    }

    function tailscaleClearExitNode() {
        tailscaleSetExitNodeProcess.command = ["tailscale", "set", "--exit-node="]
        tailscaleSetExitNodeProcess.running = true
    }

    Process {
        id: tailscaleSetExitNodeProcess
        // command is set dynamically
        onExited: (code) => {
            tailscaleStatusProcess.running = true
            root.tailscaleShowExitNodeSelector = false
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
        netbirdSelectedProfile = ""
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

    function netbirdRefreshProfiles() {
        netbirdTempProfiles = []
        netbirdParsingProfile = {}
        netbirdProfilesProcess.running = true
    }

    Process {
        id: netbirdProfilesProcess
        command: ["netbird", "profile", "list"]
        stdout: SplitParser {
            onRead: line => {
                var trimmed = line.trim()
                if (trimmed.startsWith("Found") || !trimmed) return

                var selected = trimmed.startsWith("✓")
                // Strip leading symbols (checkmark ✓, cross ✗, etc.) and whitespace
                var name = trimmed.replace(/^[✓✗\s]+/, "").trim()
                
                console.log("NetBird: Parsing line: '" + trimmed + "' -> name: '" + name + "', selected: " + selected)

                var profile = {
                    id: name,
                    name: name,
                    selected: selected
                }

                var list = root.netbirdTempProfiles
                list.push(profile)
                root.netbirdTempProfiles = list
            }
        }
        onExited: (code) => {
            root.netbirdAvailableProfiles = root.netbirdTempProfiles

            var foundSelected = false
            for (var i = 0; i < root.netbirdAvailableProfiles.length; i++) {
                var prof = root.netbirdAvailableProfiles[i]
                if (prof.selected) {
                    root.netbirdSelectedProfile = prof.name
                    foundSelected = true
                    break
                }
            }
            if (!foundSelected) {
                root.netbirdSelectedProfile = ""
            }
            root.netbirdParsingProfile = {}
            root.netbirdTempProfiles = []
        }
    }

    function netbirdOnProfileClicked(profileName) {
        console.log("NetBird: Selecting profile: " + profileName)
        netbirdProfileToSelect = profileName
        netbirdSelectProfileProcess.command = ["netbird", "profile", "select", profileName]
        netbirdSelectProfileProcess.running = true
    }

    Process {
        id: netbirdSelectProfileProcess
        // command is set dynamically in netbirdOnProfileClicked
        onExited: (code) => {
            console.log("NetBird: Profile select process exited with code: " + code)
            if (code === 0) {
                netbirdStatusProcess.running = true
                netbirdRefreshProfiles()
            }
            netbirdShowProfileSelector = false
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
                visible: root.enableTailscale
            }
            DankIcon {
                name: "vpn_key"
                size: root.iconSize
                color: root.netbirdIsConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.enableNetbird
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
                visible: root.enableTailscale
            }
            DankIcon {
                name: "vpn_key"
                size: root.iconSize
                color: root.netbirdIsConnected ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.enableNetbird
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "VPN Status"
            detailsText: (root.enableTailscale && root.tailscaleIsConnected ? "Tailscale: Connected " : "") + (root.enableNetbird && root.netbirdIsConnected ? "NetBird: Connected" : "")
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: (root.tailscaleShowNetworkSelector || root.netbirdShowProfileSelector || root.tailscaleShowExitNodeSelector) ? 350 : contentColumn.height + Theme.spacingM

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.spacingL
                    visible: !root.tailscaleShowNetworkSelector && !root.netbirdShowProfileSelector && !root.tailscaleShowExitNodeSelector

                    // --- Tailscale Section ---
                    Column {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: root.enableTailscale

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
                                StyledText {
                                    text: "Exit: " + root.tailscaleCurrentExitNode
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    visible: root.tailscaleIsConnected && root.tailscaleCurrentExitNode !== ""
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

                        DankButton {
                            width: parent.width
                            text: root.tailscaleCurrentExitNode ? ("Exit Node: " + root.tailscaleCurrentExitNode) : "Select Exit Node"
                            onClicked: root.tailscaleShowExitNodeSelector = true
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
                        visible: root.enableNetbird

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
                                    text: root.netbirdSelectedProfile || root.netbirdStatusText
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
                                text: "Select Profile"
                                onClicked: {
                                    root.netbirdRefreshProfiles()
                                    root.netbirdShowProfileSelector = true
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
                        width: parent.width
                        text: "Back"
                        onClicked: root.tailscaleShowNetworkSelector = false
                    }
                }

                // --- Tailscale Exit Node Selector ---
                Column {
                    id: tailscaleExitNodeListColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.tailscaleShowExitNodeSelector

                    StyledText {
                        width: parent.width
                        text: "Tailscale Exit Nodes"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    StyledRect {
                        width: parent.width
                        height: 45
                        radius: Theme.cornerRadius
                        color: root.tailscaleCurrentExitNode === "" ? Theme.primaryContainer : (exitNoneMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                        Row {
                            spacing: Theme.spacingS
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            DankIcon {
                                name: root.tailscaleCurrentExitNode === "" ? "radio_button_checked" : "radio_button_unchecked"
                                size: Theme.iconSize
                                color: root.tailscaleCurrentExitNode === "" ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "None (Direct)"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: exitNoneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tailscaleClearExitNode()
                        }
                    }

                    ScrollView {
                        width: parent.width
                        height: 200
                        clip: true
                        GridView {
                            anchors.fill: parent
                            cellWidth: parent.width
                            cellHeight: 50
                            model: root.tailscaleExitNodes
                            delegate: StyledRect {
                                width: parent.width - 10
                                height: 45
                                radius: Theme.cornerRadius
                                color: modelData.active ? Theme.primaryContainer : (exitNodeMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                                Row {
                                    spacing: Theme.spacingS
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingS
                                    DankIcon {
                                        name: modelData.active ? "radio_button_checked" : "radio_button_unchecked"
                                        size: Theme.iconSize
                                        color: modelData.active ? Theme.primary : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        StyledText {
                                            text: modelData.hostname
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: {
                                                var parts = []
                                                if (modelData.city) parts.push(modelData.city)
                                                if (modelData.country) parts.push(modelData.country)
                                                var loc = parts.join(", ")
                                                return loc ? loc : (modelData.online ? "Online" : "Offline")
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: !modelData.online ? Theme.error : Theme.surfaceVariantText
                                        }
                                    }
                                }
                                MouseArea {
                                    id: exitNodeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.tailscaleSetExitNode(modelData.hostname)
                                }
                            }
                        }
                    }

                    DankButton {
                        width: parent.width
                        text: "Back"
                        onClicked: root.tailscaleShowExitNodeSelector = false
                    }
                }

                // --- NetBird Profile Selector ---
                Column {
                    id: netbirdProfileListColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.netbirdShowProfileSelector

                    StyledText {
                        width: parent.width
                        text: "NetBird Profiles"
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
                            model: root.netbirdAvailableProfiles
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
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                        }
                                    }
                                }
                                MouseArea {
                                    id: nbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.netbirdOnProfileClicked(modelData.name)
                                }
                            }
                        }
                    }

                    DankButton {
                        width: parent.width
                        text: "Back"
                        onClicked: root.netbirdShowProfileSelector = false
                    }
                }
            }
        }
    }

    popoutWidth: 350
    popoutHeight: 450
}
