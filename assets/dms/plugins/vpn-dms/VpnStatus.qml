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
            tailscaleStatusProcess.running = true
            tailscaleNetworksProcess.running = true
            netbirdStatusProcess.running = true
            netbirdRefreshProfiles()
        }
    }

    Component.onCompleted: {
        tailscaleStatusProcess.running = true
        tailscaleNetworksProcess.running = true
        netbirdStatusProcess.running = true
        netbirdRefreshProfiles()
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
                implicitHeight: (root.tailscaleShowNetworkSelector || root.netbirdShowProfileSelector) ? 350 : contentColumn.height + Theme.spacingM

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.spacingL
                    visible: !root.tailscaleShowNetworkSelector && !root.netbirdShowProfileSelector

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
                        text: "Back"
                        onClicked: root.tailscaleShowNetworkSelector = false
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
