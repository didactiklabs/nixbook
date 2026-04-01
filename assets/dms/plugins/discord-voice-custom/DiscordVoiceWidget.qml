import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "discord-voice-custom"

    property var popoutService: null

    // --- Bridge state ---
    property bool bridgeReady: false
    property bool authenticated: false
    property string authError: ""

    // --- Voice state ---
    property var currentChannel: null
    property var voiceUsers: []
    property var voiceSettings: ({mute: false, deaf: false})
    property var speakingUsers: ({})

    // --- Settings ---
    readonly property string clientId: "207646673902501888"
    readonly property int maxBarAvatars: parseInt(pluginData.maxBarAvatars) || 5

    // --- Computed ---
    readonly property bool inVoice: currentChannel !== null && currentChannel !== undefined
    readonly property bool isMuted: voiceSettings.mute || false
    readonly property bool isDeafened: voiceSettings.deaf || false

    // --- Socket path ---
    readonly property string bridgeSocketPath: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        return runtime + "/dms-discord-voice-custom.sock"
    }

    // --- Helpers (accessible from popout via root.xxx) ---
    function avatarUrl(userId, avatarHash) {
        if (!avatarHash) return ""
        return "https://cdn.discordapp.com/avatars/" + userId + "/" + avatarHash + ".png?size=64"
    }

    function sendBridgeCommand(cmd) {
        console.warn("DiscordVoiceCustom: sendBridgeCommand", JSON.stringify(cmd))
        bridgeSocket.send(cmd)
    }

    // --- Visibility: hide pill when authenticated and no active call ---
    Component.onCompleted: {
        if (authenticated) {
            setVisibilityOverride(false)
        } else {
            clearVisibilityOverride()
        }
    }

    onInVoiceChanged: {
        if (inVoice) {
            clearVisibilityOverride()
        } else if (authenticated) {
            setVisibilityOverride(false)
        }
    }

    onAuthenticatedChanged: {
        if (authenticated && !inVoice) {
            setVisibilityOverride(false)
        } else if (!authenticated) {
            clearVisibilityOverride()
        }
    }

    // =====================================================================
    // Bridge process
    // =====================================================================

    Process {
        id: bridgeProcess
        command: ["python3", Qt.resolvedUrl("discord_bridge.py").toString().replace("file://", ""), root.bridgeSocketPath, root.clientId]
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim()) {
                    console.warn("DiscordVoice bridge:", text.trim())
                }
            }
        }

        onExited: (exitCode) => {
            console.warn("DiscordVoice bridge exited:", exitCode)
            root.bridgeReady = false
            root.authenticated = false
            root.currentChannel = null
            root.voiceUsers = []
            bridgeRestartTimer.start()
        }
    }

    // Start bridge after a short delay so the socket path is ready
    // before DankSocket tries to connect.
    Timer {
        id: bridgeStartTimer
        interval: 100
        running: true
        onTriggered: bridgeProcess.running = true
    }

    Timer {
        id: bridgeRestartTimer
        interval: 3000
        onTriggered: bridgeProcess.running = true
    }

    // =====================================================================
    // DankSocket connection to bridge
    // =====================================================================

    DankSocket {
        id: bridgeSocket
        path: root.bridgeSocketPath
        // Don't connect until bridge has had time to start.
        connected: false

        parser: SplitParser {
            onRead: message => {
                if (!message || message.length === 0) return
                try {
                    const msg = JSON.parse(message)
                    root.handleBridgeMessage(msg)
                } catch (e) {
                    console.warn("DiscordVoiceCustom: parse error:", e)
                }
            }
        }
    }

    // Connect socket after bridge process has had time to create its socket file.
    Timer {
        id: socketConnectTimer
        interval: 800
        running: bridgeProcess.running
        onTriggered: {
            console.warn("DiscordVoiceCustom: connecting socket to bridge")
            bridgeSocket.connected = true
        }
    }

    // =====================================================================
    // Message handler
    // =====================================================================

    function handleBridgeMessage(msg) {
        console.warn("DiscordVoiceCustom: bridge msg:", JSON.stringify(msg))
        switch (msg.type) {
        case "ready":
            bridgeReady = true
            // Trigger connect flow with any cached token.
            const token = pluginData.accessToken || ""
            bridgeSocket.send({cmd: "connect", token: token})
            break

        case "auth_required":
            authenticated = false
            authError = ""
            break

        case "auth_complete":
            authenticated = true
            authError = ""
            if (msg.access_token && pluginService) {
                pluginService.savePluginData("discordVoiceCustom", "accessToken", msg.access_token)
            }
            break

        case "auth_error":
            authError = msg.error || "Authentication failed"
            authenticated = false
            // Clear bad cached token.
            if (pluginService) {
                pluginService.savePluginData("discordVoiceCustom", "accessToken", "")
            }
            break

        case "voice_channel":
            currentChannel = msg.channel || null
            if (!msg.channel) {
                voiceUsers = []
                speakingUsers = {}
            }
            break

        case "voice_state":
            voiceUsers = msg.users || []
            break

        case "speaking":
            let updated = Object.assign({}, speakingUsers)
            updated[msg.user_id] = msg.speaking
            speakingUsers = updated
            break

        case "voice_settings":
            voiceSettings = {
                mute: msg.mute || false,
                deaf: msg.deaf || false
            }
            break

        case "disconnected":
            authenticated = false
            currentChannel = null
            voiceUsers = []
            speakingUsers = {}
            break

        case "error":
            console.warn("DiscordVoice bridge error:", msg.error)
            break
        }
    }

    // =====================================================================
    // IPC Handler (for keybinds: dms ipc call discord ...)
    // =====================================================================

    IpcHandler {
        target: "discordCustom"

        function toggleMute(): string {
            root.sendBridgeCommand({cmd: "set_voice_settings", mute: !root.isMuted})
            return root.isMuted ? "UNMUTED" : "MUTED"
        }

        function toggleDeafen(): string {
            root.sendBridgeCommand({cmd: "set_voice_settings", deaf: !root.isDeafened})
            return root.isDeafened ? "UNDEAFENED" : "DEAFENED"
        }

        function muteOn(): string {
            root.sendBridgeCommand({cmd: "set_voice_settings", mute: true})
            return "MUTE_ON"
        }

        function muteOff(): string {
            root.sendBridgeCommand({cmd: "set_voice_settings", mute: false})
            return "MUTE_OFF"
        }

        function deafenOn(): string {
            root.sendBridgeCommand({cmd: "set_voice_settings", deaf: true})
            return "DEAFEN_ON"
        }

        function deafenOff(): string {
            root.sendBridgeCommand({cmd: "set_voice_settings", deaf: false})
            return "DEAFEN_OFF"
        }

        function authorize(): string {
            root.sendBridgeCommand({cmd: "authorize"})
            return "AUTHORIZING"
        }

        function login(): string {
            root.sendBridgeCommand({cmd: "login"})
            return "LOGGING_IN"
        }

        function status(): string {
            if (!root.authenticated) return "NOT_AUTHENTICATED"
            if (!root.inVoice) return "NOT_IN_VOICE"
            return JSON.stringify({
                channel: root.currentChannel ? root.currentChannel.name : "",
                users: root.voiceUsers.length,
                muted: root.isMuted,
                deafened: root.isDeafened
            })
        }
    }

    // =====================================================================
    // Bar pills
    // =====================================================================

    horizontalBarPill: Component {
        Row {
            spacing: -4

            // Discord icon shown when not authenticated (click to authorize)
            DankIcon {
                visible: !root.authenticated
                name: "headset_mic"
                size: root.iconSize || 18
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                model: {
                    if (!root.inVoice) return []
                    const users = root.voiceUsers
                    return users.length > root.maxBarAvatars
                        ? users.slice(0, root.maxBarAvatars)
                        : users
                }

                Item {
                    width: root.widgetThickness
                    height: root.widgetThickness
                    anchors.verticalCenter: parent.verticalCenter

                    // Speaking / mute ring
                    Rectangle {
                        id: avatarRing
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: {
                            const isMuted = modelData.self_mute || modelData.mute
                            const isDeaf = modelData.self_deaf || modelData.deaf
                            const isSpeaking = root.speakingUsers[modelData.id] === true

                            if (isDeaf || isMuted) return Theme.error
                            if (isSpeaking) return Theme.success || "#4CAF50"
                            return "transparent"
                        }

                        Behavior on border.color {
                            DankColorAnim {
                                duration: Theme.shorterDuration
                            }
                        }
                    }

                    // Avatar image
                    DankCircularImage {
                        anchors.fill: parent
                        anchors.margins: 2
                        imageSource: root.avatarUrl(modelData.id, modelData.avatar)
                        fallbackText: modelData.username ? modelData.username.charAt(0).toUpperCase() : "?"
                        fallbackIcon: ""
                    }

                    // Mute/deafen badge
                    Rectangle {
                        visible: modelData.self_mute || modelData.mute || modelData.self_deaf || modelData.deaf
                        width: Math.max(10, root.widgetThickness * 0.35)
                        height: width
                        radius: width / 2
                        color: Theme.error
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right

                        DankIcon {
                            anchors.centerIn: parent
                            name: (modelData.self_deaf || modelData.deaf) ? "headset_off" : "mic_off"
                            size: parent.width - 2
                            color: Theme.onError || "white"
                        }
                    }
                }
            }

            // Overflow count
            StyledText {
                visible: root.inVoice && root.voiceUsers.length > root.maxBarAvatars
                text: "+" + (root.voiceUsers.length - root.maxBarAvatars)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: -4

            // Discord icon shown when not authenticated (click to authorize)
            DankIcon {
                visible: !root.authenticated
                name: "headset_mic"
                size: root.iconSize || 18
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Repeater {
                model: {
                    if (!root.inVoice) return []
                    const users = root.voiceUsers
                    return users.length > root.maxBarAvatars
                        ? users.slice(0, root.maxBarAvatars)
                        : users
                }

                Item {
                    width: root.widgetThickness
                    height: root.widgetThickness
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: {
                            const isMuted = modelData.self_mute || modelData.mute
                            const isDeaf = modelData.self_deaf || modelData.deaf
                            const isSpeaking = root.speakingUsers[modelData.id] === true

                            if (isDeaf || isMuted) return Theme.error
                            if (isSpeaking) return Theme.success || "#4CAF50"
                            return "transparent"
                        }

                        Behavior on border.color {
                            DankColorAnim {
                                duration: Theme.shorterDuration
                            }
                        }
                    }

                    DankCircularImage {
                        anchors.fill: parent
                        anchors.margins: 2
                        imageSource: root.avatarUrl(modelData.id, modelData.avatar)
                        fallbackText: modelData.username ? modelData.username.charAt(0).toUpperCase() : "?"
                        fallbackIcon: ""
                    }

                    Rectangle {
                        visible: modelData.self_mute || modelData.mute || modelData.self_deaf || modelData.deaf
                        width: Math.max(10, root.widgetThickness * 0.35)
                        height: width
                        radius: width / 2
                        color: Theme.error
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right

                        DankIcon {
                            anchors.centerIn: parent
                            name: (modelData.self_deaf || modelData.deaf) ? "headset_off" : "mic_off"
                            size: parent.width - 2
                            color: Theme.onError || "white"
                        }
                    }
                }
            }

            StyledText {
                visible: root.inVoice && root.voiceUsers.length > root.maxBarAvatars
                text: "+" + (root.voiceUsers.length - root.maxBarAvatars)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // =====================================================================
    // Popout
    // =====================================================================

    popoutWidth: 320
    popoutHeight: 400

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: root.inVoice ? (root.currentChannel ? root.currentChannel.name : "Voice Channel") : "Discord Call Overlay"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // --- Not authenticated ---
                Column {
                    visible: !root.authenticated
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.authError ? "error" : "link"
                        size: 48
                        color: root.authError ? Theme.error : Theme.surfaceVariantText
                    }

                    StyledText {
                        width: parent.width
                        text: root.authError
                              ? root.authError
                              : "Connecting to Discord..."
                        color: root.authError ? Theme.error : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    // Login button (for Vesktop/Gateway mode)
                    Rectangle {
                        visible: root.authError && root.authError.includes("Vesktop")
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: loginRow.width + Theme.spacingL * 2
                        height: loginRow.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.primary

                        Row {
                            id: loginRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "login"
                                size: Theme.fontSizeMedium
                                color: Theme.onPrimary || "white"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Login with Discord"
                                color: Theme.onPrimary || "white"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                console.warn("DiscordVoiceCustom: login button clicked")
                                root.sendBridgeCommand({cmd: "login"})
                            }
                        }
                    }

                    // Authorize button (for official Discord client)
                    Rectangle {
                        visible: !root.authError || (!root.authError.includes("Vesktop") && !root.authError.includes("Gateway"))
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: authRow.width + Theme.spacingL * 2
                        height: authRow.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.primary

                        Row {
                            id: authRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "login"
                                size: Theme.fontSizeMedium
                                color: Theme.onPrimary || "white"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Authorize Discord"
                                color: Theme.onPrimary || "white"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                console.warn("DiscordVoiceCustom: authorize button clicked")
                                root.sendBridgeCommand({cmd: "authorize"})
                            }
                        }
                    }
                }

                // --- Authenticated, in voice ---
                Column {
                    visible: root.authenticated && root.inVoice
                    width: parent.width
                    spacing: Theme.spacingS

                    // Participant list
                    Repeater {
                        model: root.voiceUsers

                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingS

                                DankCircularImage {
                                    width: 32
                                    height: 32
                                    anchors.verticalCenter: parent.verticalCenter
                                    imageSource: root.avatarUrl(modelData.id, modelData.avatar)
                                    fallbackText: modelData.username ? modelData.username.charAt(0).toUpperCase() : "?"
                                    fallbackIcon: ""
                                    border.width: root.speakingUsers[modelData.id] === true ? 2 : 0
                                    border.color: Theme.success || "#4CAF50"
                                }

                                StyledText {
                                    text: modelData.nick || modelData.username || "Unknown"
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    width: parent.width - 32 - statusRow.width - Theme.spacingS * 3
                                }

                                Row {
                                    id: statusRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    DankIcon {
                                        visible: modelData.self_mute || modelData.mute
                                        name: "mic_off"
                                        size: 16
                                        color: Theme.error
                                    }
                                    DankIcon {
                                        visible: modelData.self_deaf || modelData.deaf
                                        name: "headset_off"
                                        size: 16
                                        color: Theme.error
                                    }
                                }
                            }
                        }
                    }

                    // Mute / deafen controls
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        topPadding: Theme.spacingS

                        Rectangle {
                            width: (parent.width - Theme.spacingS) / 2
                            height: 40
                            radius: Theme.cornerRadius
                            color: root.isMuted ? Theme.error : Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: root.isMuted ? "mic_off" : "mic"
                                    size: 18
                                    color: root.isMuted ? (Theme.onError || "white") : Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.isMuted ? "Unmute" : "Mute"
                                    color: root.isMuted ? (Theme.onError || "white") : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sendBridgeCommand({cmd: "set_voice_settings", mute: !root.isMuted})
                            }
                        }

                        Rectangle {
                            width: (parent.width - Theme.spacingS) / 2
                            height: 40
                            radius: Theme.cornerRadius
                            color: root.isDeafened ? Theme.error : Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: root.isDeafened ? "headset_off" : "headset"
                                    size: 18
                                    color: root.isDeafened ? (Theme.onError || "white") : Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.isDeafened ? "Undeafen" : "Deafen"
                                    color: root.isDeafened ? (Theme.onError || "white") : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sendBridgeCommand({cmd: "set_voice_settings", deaf: !root.isDeafened})
                            }
                        }
                    }
                }

                // --- Authenticated, not in voice ---
                Column {
                    visible: root.authenticated && !root.inVoice
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: "No active Discord call found"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
