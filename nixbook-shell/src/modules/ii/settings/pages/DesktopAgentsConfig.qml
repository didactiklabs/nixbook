import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > Desktop agents (services/DesktopControl.qml): whether AI agents
// may drive the desktop (nixbook-desktop-mcp), Claude in the AI chat
// (ai.claudeCode, services/Ai.qml), and the memory agents keep of the
// desktop — notes they wrote, app aliases and usage learned — to review,
// prune or clear.
ContentPage {
    id: page
    forceWidth: true

    Component.onCompleted: {
        DesktopControl.refreshMemory();
        DesktopControl.refreshPersonal();
        DesktopControl.refreshHabits();
    }

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }

    function ago(seconds) {
        if (!seconds) return ""
        const d = new Date(seconds * 1000)
        return Qt.formatDateTime(d, "d MMM, hh:mm")
    }

    // [[key, {count, last}], …], most used first.
    function ranked(obj) {
        return Object.entries(obj ?? {}).sort((a, b) => (b[1].count ?? 0) - (a[1].count ?? 0))
    }

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "chat_bubble"
            title: Translation.tr("Talks to you on its own")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Claude speaks first when it can help, not on a schedule: when you come back (your day, a plan coming up or just past, your usual setup), when an app it has a broken recipe for is in front, when it learned something. Time-critical things come as its own speech bubble on the left, in the theme's look (Reply opens its From Claude tab, Not now, Don't tell me this; at most 6 a day, none at night, in a meeting or fullscreen); the rest waits as a bubble beside the robot in the bar. Now and then, at random and at most twice a day, it says a light word in the bar: a break after a long stretch, a tip for the app you're in, a plan coming up, a question about something you care about. It learns from your answers what is worth saying. Plain code decides; a small model only reads notifications and words tips and questions.")
            }

            GroupedList {
                ConfigSwitch {
                    configKey: "ai.initiative.enable"
                    buttonIcon: "record_voice_over"
                    text: Translation.tr("Talk to me on its own")
                    checked: Config.options.ai.initiative.enable
                    onCheckedChanged: Config.options.ai.initiative.enable = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.readNotifications"
                    buttonIcon: "notifications_active"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Read my notifications, to react, advise or suggest (what they say goes to the small model)")
                    checked: Config.options.ai.initiative.readNotifications
                    onCheckedChanged: Config.options.ai.initiative.readNotifications = checked
                }
            }

            RowLayout {
                spacing: 8
                SmallButton {
                    materialIcon: "campaign"
                    enabled: Config.options.ai.initiative.enable
                    mainText: Translation.tr("Say something now")
                    onClicked: Initiative.sayNow()
                }
                SmallButton {
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Undo every \"Don't tell me this\"")
                    onClicked: Quickshell.execDetached(["nixbook-desktop-mcp", "initiative", "unmute"])
                }
            }

            // Why it spoke or kept quiet lately: its last decisions.
            StyledText {
                Layout.fillWidth: true
                visible: Initiative.log.length > 0
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Lately:") + "\n" + Initiative.log.slice(-6).reverse().map(l =>
                    `${Qt.formatDateTime(new Date(l.time * 1000), "hh:mm")} · ${l.event} · `
                    + (l.action === "none" ? Translation.tr("kept quiet: %1").arg(l.why) : (l.said || l.action))).join("\n")
            }
        }

        ContentSection {
            icon: "bolt"
            title: Translation.tr("Routines")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Ask Claude \"whenever the music ends, play something I like\", \"when my headphones connect, resume the music\", \"when a PDF lands in Downloads, open it\": it does it on its own when that happens. Cues: music, apps, window titles, notifications, coming back, the lock, a time, battery and power, Wi-Fi, VPN, audio output, monitors, Downloads, calendar events. A fixed action costs nothing; one that takes judgment is a short Claude run. It never fights you: music you stop stays stopped, and a routine you undo twice turns itself off. Desktop control's pause stops routines too.")
            }

            GroupedList {
                ConfigSwitch {
                    configKey: "ai.routines.enable"
                    buttonIcon: "bolt"
                    text: Translation.tr("Run my routines")
                    checked: Config.options.ai.routines.enable
                    onCheckedChanged: Config.options.ai.routines.enable = checked
                }
            }

            ConfigSelectionArray {
                configKey: "ai.routines.learn"
                text: Translation.tr("Learn routines from my habits")
                icon: "auto_awesome"
                currentValue: Config.options.ai.routines.learn
                onSelected: newValue => { Config.options.ai.routines.learn = newValue }
                options: [
                    { displayName: Translation.tr("Off"), icon: "block", value: "off" },
                    { displayName: Translation.tr("Suggest"), icon: "help", value: "suggest" },
                    { displayName: Translation.tr("On its own"), icon: "auto_awesome", value: "auto" }
                ]
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Once a day it looks at your usage habits (which need to be on, below) for what you do by hand after the same cue (headphones connecting, unlocking, opening an app…) or at the same time of day, on 3 days or more. Suggest: it asks first. On its own: a strong pattern (5 days, 4 times out of 5) is turned on at once, and it tells you each time it acts; undo it twice and it stops. It never costs a token: a learned routine is a fixed action.")
            }

            StyledText {
                visible: (DesktopControl.memory.routines ?? []).length === 0
                color: Appearance.colors.colSubtext
                text: Translation.tr("None yet.")
            }
            Repeater {
                model: DesktopControl.memory.routines ?? []
                delegate: RowLayout {
                    id: routineRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    MaterialSymbol {
                        text: routineRow.modelData.do?.agent ? "psychology" : "bolt"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                        opacity: routineRow.modelData.on === false ? 0.4 : 1
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: routineRow.modelData.text
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: [Translation.tr("ran %1 times").arg(routineRow.modelData.runs ?? 0),
                                   routineRow.modelData.last ? page.ago(routineRow.modelData.last) : "",
                                   routineRow.modelData.lastResult ?? ""].filter(x => x).join(" · ")
                        }
                    }
                    StyledSwitch {
                        checked: routineRow.modelData.on !== false
                        onClicked: DesktopControl.routineCommand(checked ? "on" : "off", routineRow.modelData.id)
                    }
                    SmallButton {
                        materialIcon: "delete"
                        mainText: Translation.tr("Delete")
                        onClicked: DesktopControl.routineCommand("remove", routineRow.modelData.id)
                    }
                }
            }
        }

        ContentSection {
            icon: "smart_toy"
            title: Translation.tr("Desktop control")
            shape: MaterialShape.Shape.Pentagon

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("AI agents (Claude Code, the AI chat, any MCP client using nixbook-desktop-mcp) can see and drive the desktop. Pausing refuses every tool to every agent until you allow them again; the Desktop Control bar widget and Mod+Shift+Escape do the same. It starts paused and keeps its position across reboots.")
            }

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "pan_tool"
                    text: Translation.tr("Pause desktop control")
                    checked: DesktopControl.paused
                    onClicked: DesktopControl.toggle()
                }
                ConfigSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notify when an agent starts driving the desktop")
                    checked: DesktopControl.notifyOnControl
                    onClicked: DesktopControl.toggleNotify()
                }
                ConfigSwitch {
                    buttonIcon: "picture_in_picture"
                    text: Translation.tr("Agents work on their own desktop")
                    checked: DesktopControl.onAgentDesktop
                    onClicked: {
                        if (DesktopControl.onAgentDesktop) DesktopControl.userDesktop();
                        else DesktopControl.agentDesktop();
                    }
                }
                ConfigSwitch {
                    buttonIcon: "touch_app"
                    text: Translation.tr("Use their desktop myself (Mod+Ctrl+A)")
                    enabled: DesktopControl.canTakeOver || DesktopControl.userHasControl
                    checked: DesktopControl.userHasControl
                    onClicked: DesktopControl.toggleInteract()
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("On their own desktop, agents work in a window you watch but can't click or type into, with their own browser and apps, so they don't get in your way; your notes, to-do list and calendar stay reachable. The window opens when they start an app and closes once it's gone; if you close it, their next app opens it again (switch this off, or pause them, to stop them). Mod+Shift+A, right-clicking the bar widget and the desktop menu switch too. To use their desktop yourself for a moment (to log their browser in somewhere), take it over: your clicks and keys reach it and the agent waits until you give it back.")
            }

            // Their desktop's sandbox (scripts/agent-desktop.sh): both on by
            // default, read when it starts.
            GroupedList {
                ConfigSwitch {
                    configKey: "ai.agentDesktop.hideSystemSockets"
                    enabled: !nixManaged
                    buttonIcon: "lan"
                    text: Translation.tr("Hide the system's services from their apps")
                    checked: Config.options.ai.agentDesktop.hideSystemSockets
                    onCheckedChanged: Config.options.ai.agentDesktop.hideSystemSockets = checked
                    StyledToolTip {
                        text: Translation.tr("Their apps see none of the system daemons' sockets (printing, input helpers…), only what they need to run and look up names")
                    }
                }
                ConfigSwitch {
                    configKey: "ai.agentDesktop.privateNetwork"
                    enabled: !nixManaged
                    buttonIcon: "vpn_lock"
                    text: Translation.tr("Keep their apps off this computer's local services")
                    checked: Config.options.ai.agentDesktop.privateNetwork
                    onCheckedChanged: Config.options.ai.agentDesktop.privateNetwork = checked
                    StyledToolTip {
                        text: Translation.tr("Their own network: the internet and your local network, not what runs on this computer (a dev server on localhost, printer pages…). Off: their browser can open those too")
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Their apps run sandboxed: none of your files but the folders you allow, none of your windows, clipboard or screen (they can't capture or type into your desktop). These two switches take effect when their desktop next opens.")
            }
        }

        ContentSection {
            id: claudeSection
            icon: "neurology"
            title: Translation.tr("Claude in the side panel")
            shape: MaterialShape.Shape.Ghostish

            readonly property var tools: Config.options.ai.claudeCode.allowedTools ?? []
            function hasAll(names) {
                return names.every(n => claudeSection.tools.includes(n))
            }
            function setTools(names, on) {
                const hasNone = !names.some(n => claudeSection.tools.includes(n))
                if ((on && claudeSection.hasAll(names)) || (!on && hasNone)) return
                const rest = claudeSection.tools.filter(t => !names.includes(t))
                Config.options.ai.claudeCode.allowedTools = on ? [...rest, ...names] : rest
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("The AI chat's Claude model runs Claude Code on your own Claude account (no API key), with the desktop tools. It can't run commands, reads none of your files but the folders you allow below (and a file you attach to a message) and writes only in the folders you let it write; below, what else it may do.")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol {
                    text: Ai.claudeCodePath.length > 0 ? "check_circle" : "error"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Ai.claudeCodePath.length > 0 ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    text: Ai.claudeCodePath.length > 0
                        ? Translation.tr("Claude Code found: %1").arg(Ai.claudeCodePath)
                        : Translation.tr("Claude Code not found. Install it, run `claude` once in a terminal to log in, or give its path below.")
                }
                SmallButton {
                    visible: Ai.claudeCodePath.length > 0
                    materialIcon: Ai.currentModelId === "claude" ? "check" : "chat"
                    mainText: Ai.currentModelId === "claude" ? Translation.tr("In use") : Translation.tr("Use in the side panel")
                    enabled: Ai.currentModelId !== "claude"
                    onClicked: Ai.setModel("claude")
                }
            }

            ConfigSelectionArray {
                configKey: "ai.claudeCode.model"
                enabled: !nixManaged
                text: Translation.tr("Model")
                icon: "neurology"
                currentValue: Config.options.ai.claudeCode.model
                onSelected: newValue => { Config.options.ai.claudeCode.model = newValue }
                options: [
                    { displayName: Translation.tr("Default"), icon: "auto_awesome", value: "" },
                    { displayName: "Sonnet", icon: "bolt", value: "sonnet" },
                    { displayName: "Opus", icon: "psychology", value: "opus" },
                    { displayName: "Haiku", icon: "speed", value: "haiku" }
                ]
            }

            ConfigSelectionArray {
                configKey: "ai.claudeCode.effort"
                enabled: !nixManaged
                text: Translation.tr("Thinking effort (low: quicker steps on the desktop)")
                icon: "speed"
                currentValue: Config.options.ai.claudeCode.effort
                onSelected: newValue => { Config.options.ai.claudeCode.effort = newValue }
                options: [
                    { displayName: Translation.tr("Low"), icon: "bolt", value: "low" },
                    { displayName: Translation.tr("Medium"), icon: "tune", value: "medium" },
                    { displayName: Translation.tr("High"), icon: "psychology", value: "high" },
                    { displayName: Translation.tr("Default"), icon: "auto_awesome", value: "" }
                ]
            }

            GroupedList {
                ConfigSwitch {
                    configKey: "ai.claudeCode.allowedTools"
                    enabled: !nixManaged
                    buttonIcon: "travel_explore"
                    text: Translation.tr("Search and read the web")
                    checked: claudeSection.hasAll(["WebSearch", "WebFetch"])
                    onCheckedChanged: claudeSection.setTools(["WebSearch", "WebFetch"], checked)
                }
                ConfigSwitch {
                    configKey: "ai.claudeCode.asComputer"
                    enabled: !nixManaged
                    buttonIcon: "computer"
                    text: Translation.tr("Speak as this computer")
                    checked: Config.options.ai.claudeCode.asComputer
                    onCheckedChanged: Config.options.ai.claudeCode.asComputer = checked
                    StyledToolTip {
                        text: Translation.tr("Claude answers as the machine itself, from its live hardware, OS and kernel readings")
                    }
                }
                ConfigSwitch {
                    configKey: "ai.claudeCode.connectors"
                    enabled: !nixManaged
                    buttonIcon: "hub"
                    text: Translation.tr("Use your claude.ai connectors")
                    checked: Config.options.ai.claudeCode.connectors
                    onCheckedChanged: Config.options.ai.claudeCode.connectors = checked
                    StyledToolTip {
                        text: Translation.tr("Gmail, Calendar, Drive… as connected on claude.ai, without asking before each use")
                    }
                }
            }

            StyledText {
                visible: Config.options.ai.claudeCode.connectors
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Ai.claudeConnectors.length > 0
                    ? Translation.tr("Connectors: %1").arg(Ai.claudeConnectors.map(c => c.replace(/^mcp__claude_ai_/, "").replace(/_/g, " ")).join(", "))
                    : Translation.tr("No connectors found. Add them on claude.ai (Settings → Connectors).")
            }
            SmallButton {
                visible: Config.options.ai.claudeCode.connectors
                materialIcon: "refresh"
                mainText: Translation.tr("Reload connectors")
                onClicked: Ai.reloadClaudeConnectors()
                StyledToolTip {
                    text: Translation.tr("After adding or signing in to a connector on claude.ai: Claude starts again with it, keeping the conversation")
                }
            }

            // The MCP servers Nix gives this chat (assistant.mcpServers), each
            // with its switch. Only this chat has them. Rows of their own, in
            // GroupedList's look: GroupedList lays out fixed items only, not
            // a Repeater's.
            ContentSubsection {
                visible: Object.keys(Ai.assistantMcpServers).length > 0
                title: Translation.tr("Apps it can use (this chat only)")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        id: serverRows
                        model: Object.keys(Ai.assistantMcpServers).sort()
                        delegate: Rectangle {
                            id: serverRow
                            required property string modelData
                            required property int index
                            readonly property real outer: Appearance.rounding.normal
                            readonly property real inner: Appearance.rounding.unsharpenmore
                            Layout.fillWidth: true
                            implicitHeight: serverSwitch.implicitHeight + 24
                            color: Appearance.colors.colLayer1
                            topLeftRadius: serverRow.index === 0 ? serverRow.outer : serverRow.inner
                            topRightRadius: serverRow.index === 0 ? serverRow.outer : serverRow.inner
                            bottomLeftRadius: serverRow.index === serverRows.count - 1 ? serverRow.outer : serverRow.inner
                            bottomRightRadius: serverRow.index === serverRows.count - 1 ? serverRow.outer : serverRow.inner

                            ConfigSwitch {
                                id: serverSwitch
                                readonly property var known: ({
                                    nixos: ["deployed_code", Translation.tr("NixOS packages and options (MCP-NixOS)")],
                                    "youtube-music": ["music_note", Translation.tr("YouTube Music: play and control")],
                                    spotify: ["queue_music", Translation.tr("Spotify: play and control")],
                                    linkedin: ["work", Translation.tr("LinkedIn: profiles, messages, jobs (your account)")],
                                    immich: ["photo_library", Translation.tr("Immich: search and organize your photos")]
                                })[serverRow.modelData] ?? ["extension", serverRow.modelData]
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                                configKey: "ai.claudeCode.mcpServersOff"
                                enabled: !nixManaged
                                buttonIcon: serverSwitch.known[0]
                                text: serverSwitch.known[1]
                                checked: !(Config.options.ai.claudeCode.mcpServersOff ?? []).includes(serverRow.modelData)
                                onCheckedChanged: {
                                    const off = Config.options.ai.claudeCode.mcpServersOff ?? []
                                    if (checked === !off.includes(serverRow.modelData)) return
                                    Config.options.ai.claudeCode.mcpServersOff = checked
                                        ? off.filter(n => n !== serverRow.modelData) : [...off, serverRow.modelData]
                                }
                            }
                        }
                    }
                }

                // LinkedIn: what turning it on means, and its sign-in.
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: Ai.assistantMcpServers.linkedin !== undefined
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("LinkedIn works through your own session in a browser of its own (~/.linkedin-mcp). LinkedIn's terms forbid automated access and it may restrict accounts using it: use it lightly. Before sending a message or an invitation, Claude shows it and waits for your yes.")
                }
                SmallButton {
                    visible: Ai.assistantMcpServers.linkedin !== undefined
                    materialIcon: "login"
                    mainText: Translation.tr("Sign in to LinkedIn")
                    onClicked: Quickshell.execDetached([Ai.assistantMcpServers.linkedin.command, "--login"])
                }

                // Immich: its server is a setting (ai.immich.url, locked when
                // set in Nix), its API key goes to the keyring through
                // immich-photo-manager-credentials (on stdin, checked on the
                // server first, never shown again); or a key file set in Nix
                // (ai.immich.apiKeyFile).
                ColumnLayout {
                    id: immich
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: Ai.assistantMcpServers.immich !== undefined
                    spacing: 6
                    readonly property string bin: Ai.assistantMcpServers.immich
                        ? Ai.assistantMcpServers.immich.command + "-credentials" : ""
                    // {has_key, key_source: env|file|keyring|null}
                    property var conn: ({})
                    property string status: ""
                    property bool busy: false

                    function run(args, key) {
                        if (immich.busy || !immich.bin) return
                        immich.busy = true
                        immichProc.key = key ?? ""
                        immichProc.command = [immich.bin, ...args]
                        immichProc.environment = Ai.immichEnv
                        immichProc.stdinEnabled = args[0] === "save"
                        immichProc.running = true
                    }
                    // assistant-mcp.json is read asynchronously.
                    Component.onCompleted: run(["status"])
                    onBinChanged: run(["status"])

                    Process {
                        id: immichProc
                        property string key: ""
                        stdout: StdioCollector { id: immichOut }
                        onRunningChanged: {
                            if (!immichProc.running || !immichProc.stdinEnabled) return
                            immichProc.write(immichProc.key + "\n")
                            immichProc.key = ""
                            immichProc.stdinEnabled = false
                        }
                        onExited: code => {
                            immich.busy = false
                            let result = null
                            try {
                                result = JSON.parse(immichOut.text)
                            } catch (e) {}
                            if (code !== 0 || !result) {
                                immich.status = result?.error ?? Translation.tr("Couldn't reach the Immich helper")
                                return
                            }
                            immich.conn = result
                            immichKey.text = ""
                            immich.status = result.photos !== undefined && result.photos !== null
                                ? Translation.tr("Connected: %1 photos, %2 videos").arg(result.photos).arg(result.videos ?? 0)
                                : ""
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Immich: your photo library, through its API. Create an API key in Immich (Account Settings > API Keys); it is kept in your keyring. Before deleting photos or making a public link, Claude says what it would do and waits for your yes.")
                    }
                    ConfigTextArea {
                        id: immichUrl
                        configKey: "ai.immich.url"
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "dns"
                        text: Translation.tr("Immich server")
                        placeholderText: Translation.tr("e.g. https://photos.example.org")
                        value: Config.options.ai.immich.url ?? ""
                        Connections {
                            target: immichUrl.textArea
                            function onEditingFinished() {
                                Config.options.ai.immich.url = immichUrl.value.trim().replace(/\/+$/, "")
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: immich.conn.key_source === "file"
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("API key: read from %1 (ai.immich.apiKeyFile).").arg(Config.options.ai.immich.apiKeyFile)
                    }
                    MaterialTextField {
                        id: immichKey
                        Layout.fillWidth: true
                        visible: immich.conn.key_source !== "file"
                        placeholderText: immich.conn.has_key
                            ? Translation.tr("API key (saved: leave empty to keep it)")
                            : Translation.tr("API key")
                        echoMode: TextInput.Password
                        onAccepted: immichSave.clicked()
                    }
                    RowLayout {
                        spacing: 6
                        SmallButton {
                            id: immichSave
                            readonly property string url: immichUrl.value.trim().replace(/\/+$/, "")
                            enabled: !immich.busy && url !== ""
                                && (immichKey.text !== "" || immich.conn.has_key)
                            materialIcon: "link"
                            mainText: immich.busy ? Translation.tr("Checking…") : Translation.tr("Save and check")
                            onClicked: {
                                // The field saves when it loses focus, which a click may not take.
                                if (!immichUrl.nixManaged) Config.options.ai.immich.url = url
                                immich.run(["save", url], immichKey.text)
                            }
                        }
                        SmallButton {
                            visible: immich.conn.key_source === "keyring"
                            enabled: !immich.busy
                            materialIcon: "key_off"
                            mainText: Translation.tr("Forget the key")
                            onClicked: immich.run(["forget"])
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: immich.status !== ""
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: immich.status
                    }
                }
            }


            // The folders AI agents may read (Claude here, and the apps on
            // their own desktop): none unless listed. Saved when editing ends,
            // so typing a comma isn't undone.
            ConfigTextArea {
                id: foldersField
                configKey: "ai.allowedFolders"
                enabled: !nixManaged
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "folder_open"
                text: Translation.tr("Folders AI agents may read")
                placeholderText: Translation.tr("none: e.g. ~/Documents/flats, ~/Downloads")
                value: (Config.options.ai.allowedFolders ?? []).join(", ")
                Connections {
                    target: foldersField.textArea
                    function onEditingFinished() {
                        Config.options.ai.allowedFolders = foldersField.value.split(",")
                            .map(f => f.trim()).filter(f => f.length > 0)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Read-only, for Claude here and for the apps on the agents' own desktop (from its next start). Absolute paths or ~/…, separated by commas. Other agents (Claude Code in a terminal…) follow their own permissions.")
            }

            // The folders Claude here and the apps on the agents' desktop may
            // write too: the first is where its browser downloads.
            ConfigTextArea {
                id: writableField
                configKey: "ai.writableFolders"
                enabled: !nixManaged
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "drive_folder_upload"
                text: Translation.tr("Folders AI agents may write")
                placeholderText: Translation.tr("none: e.g. ~/Pictures/Assistant")
                value: (Config.options.ai.writableFolders ?? []).join(", ")
                Connections {
                    target: writableField.textArea
                    function onEditingFinished() {
                        Config.options.ai.writableFolders = writableField.value.split(",")
                            .map(f => f.trim()).filter(f => f.length > 0)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Claude here can create and edit files there (nowhere else), and so can the apps on the agents' own desktop (from its next start), whose browser downloads into the first one, so an agent can fetch a file for you, a wallpaper say. Made if missing; not your whole home.")
            }

            ConfigTextArea {
                configKey: "ai.claudeCode.command"
                enabled: !nixManaged
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "terminal"
                text: Translation.tr("Claude Code command")
                placeholderText: Translation.tr("found automatically")
                value: Config.options.ai.claudeCode.command
                onValueChanged: Config.options.ai.claudeCode.command = value.trim()
            }
        }

        // EqualizerAutoService's agent mode.
        ContentSection {
            icon: "graphic_eq"
            title: Translation.tr("Equalizer agent")
            shape: MaterialShape.Shape.Burst

            GroupedList {
                ConfigSwitch {
                    configKey: "equalizer.agent"
                    enabled: !nixManaged && Ai.claudeCodePath !== ""
                    buttonIcon: "smart_toy"
                    text: Translation.tr("Tune the equalizer for each song")
                    checked: Config.options.equalizer.agent
                    onCheckedChanged: Config.options.equalizer.agent = checked
                    StyledToolTip {
                        text: Translation.tr("When a new song has played a few seconds, Claude (Claude Code, your account) reads what it is and sets the equalizer for it. Replaces Auto.")
                    }
                }
                ConfigSelectionArray {
                    configKey: "equalizer.agentModel"
                    text: Translation.tr("Model")
                    icon: "neurology"
                    enabled: Config.options.equalizer.agent
                    currentValue: Config.options.equalizer.agentModel
                    onSelected: newValue => Config.options.equalizer.agentModel = newValue
                    options: [
                        { displayName: Translation.tr("Haiku (fast)"), icon: "bolt", value: "haiku" },
                        { displayName: "Sonnet", icon: "auto_awesome", value: "sonnet" },
                        { displayName: Translation.tr("Default"), icon: "tune", value: "" }
                    ]
                }
            }
        }

        ContentSection {
            icon: "psychology"
            title: Translation.tr("Desktop memory")
            shape: MaterialShape.Shape.Cookie4Sided

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("What agents learned about this desktop, so the next task is faster: notes they wrote (shortcuts, where things are, recipes), app names they resolved and what gets used. Every agent receives it when it connects, as hints — never as your instructions. Delete what is wrong or private.")
            }

            ContentSubsection {
                title: Translation.tr("Notes")

                StyledText {
                    visible: (DesktopControl.memory.notes ?? []).length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("None yet.")
                }

                Repeater {
                    model: DesktopControl.memory.notes ?? []
                    delegate: Rectangle {
                        id: noteRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: noteLayout.implicitHeight + 20
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            id: noteLayout
                            anchors { fill: parent; margins: 10; leftMargin: 14 }
                            spacing: 10

                            MaterialSymbol {
                                text: noteRow.modelData.kind !== "recipe" ? "sticky_note_2"
                                    : (noteRow.modelData.steps && new Set(noteRow.modelData.runs ?? []).size >= 3 && !noteRow.modelData.failStep) ? "bolt"
                                    : "format_list_numbered"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: noteRow.modelData.topic
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    text: noteRow.modelData.text
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    // What it proved (tasks it helped, failed), how
                                    // often agents got it, and where it came from.
                                    text: [Translation.tr("by %1 · %2").arg(noteRow.modelData.client ?? "?").arg(page.ago(noteRow.modelData.updated)),
                                           Translation.tr("helped %1 · failed %2 · shown %3 times")
                                               .arg(noteRow.modelData.ok ?? 0).arg(noteRow.modelData.fail ?? 0)
                                               .arg(noteRow.modelData.shown ?? noteRow.modelData.uses ?? 0),
                                           ({ user: Translation.tr("told by you"), read: Translation.tr("read in content, unverified"),
                                              inferred: Translation.tr("learned in the background") })[noteRow.modelData.source] ?? "",
                                           noteRow.modelData.tentative ? Translation.tr("tentative") : "",
                                           noteRow.modelData.failStep ? Translation.tr("step %1 failed").arg(noteRow.modelData.failStep.step) : ""]
                                        .filter(x => x).join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            SmallButton {
                                materialIcon: "delete"
                                mainText: Translation.tr("Delete")
                                onClicked: DesktopControl.forgetNote(noteRow.modelData.id)
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Reminders")

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    readonly property int archived: (DesktopControl.memory.archive ?? []).length
                    text: Translation.tr("Ask an agent \"remind me when I open Gmail to…\" or \"…at 18:00\": a notification comes then.")
                        + (archived > 0 ? " " + Translation.tr("%1 faded notes are in the archive: agents find them again when they need them.").arg(archived) : "")
                }
                StyledText {
                    visible: (DesktopControl.memory.triggers ?? []).length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("None yet.")
                }
                Repeater {
                    model: DesktopControl.memory.triggers ?? []
                    delegate: RowLayout {
                        id: triggerRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: "alarm"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer1
                            text: [triggerRow.modelData.app ? Translation.tr("when %1 opens").arg(triggerRow.modelData.app) : "",
                                   triggerRow.modelData.title ? Translation.tr("when a title has \"%1\"").arg(triggerRow.modelData.title) : "",
                                   triggerRow.modelData.at ? Translation.tr("at %1").arg(triggerRow.modelData.at) : "",
                                   triggerRow.modelData.repeat ? Translation.tr("every day") : ""]
                                .filter(x => x).join(", ") + " — " + triggerRow.modelData.text
                        }
                        SmallButton {
                            materialIcon: "delete"
                            mainText: Translation.tr("Delete")
                            onClicked: DesktopControl.forgetNote(triggerRow.modelData.id)
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Learned")

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var aliases: Object.entries(DesktopControl.memory.aliases ?? {})
                    text: aliases.length === 0 ? Translation.tr("App aliases: none yet.")
                        : Translation.tr("App aliases: %1").arg(aliases.map(([k, v]) => `${k} → ${v}`).join(", "))
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var apps: page.ranked(DesktopControl.memory.usage?.apps).slice(0, 10)
                    text: apps.length === 0 ? Translation.tr("Apps launched by agents: none yet.")
                        : Translation.tr("Apps launched by agents: %1").arg(apps.map(([k, v]) => `${k} (${v.count})`).join(", "))
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var tools: page.ranked(DesktopControl.memory.usage?.tools).slice(0, 8)
                    text: tools.length === 0 ? Translation.tr("Tools used: none yet.")
                        : Translation.tr("Tools used: %1").arg(tools.map(([k, v]) => `${k} (${v.count})`).join(", "))
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    // Buttons, tabs, menu items agents acted on: the next
                    // time they reach them by name, without reading the window.
                    readonly property var apps: Object.entries(DesktopControl.memory.targets ?? {})
                        .sort((a, b) => b[1].length - a[1].length)
                    text: apps.length === 0 ? Translation.tr("Controls learned: none yet.")
                        : Translation.tr("Controls learned: %1").arg(apps.slice(0, 6)
                            .map(([k, v]) => `${k} (${v.slice(0, 4).map(t => t.name).join(", ")}${v.length > 4 ? ", …" : ""})`).join("; "))
                }
            }

            RowLayout {
                spacing: 8
                SmallButton {
                    materialIcon: "delete_sweep"
                    mainText: Translation.tr("Clear notes")
                    onClicked: DesktopControl.clearMemory(["notes"])
                }
                SmallButton {
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Clear usage, aliases and controls")
                    onClicked: DesktopControl.clearMemory(["usage", "aliases", "targets"])
                }
                SmallButton {
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh")
                    onClicked: DesktopControl.refreshMemory()
                }
            }
        }

        ContentSection {
            icon: "insights"
            title: Translation.tr("Usage habits")
            shape: MaterialShape.Shape.Cookie4Sided

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: DesktopControl.habits.enabled
                    ? Translation.tr("What you do on this computer, counted here without any model: which app has the focus and for how long, the windows you open, the layouts and themes you choose, the music you play. App names and times only — never window titles, files, sites or what you type; for music, the artist, title and album — and nothing but music while the screen is locked or an agent acts, nothing for password managers or in private browser windows. Kept %1 days (music: %3). The launcher ranks apps with it; agents get %2.")
                        .arg(DesktopControl.habits.keepDays ?? 28)
                        .arg(DesktopControl.habits.agents === "off" ? Translation.tr("nothing of it")
                            : DesktopControl.habits.agents === "timeline" ? Translation.tr("a short summary, and what you used on a given day when they ask")
                            : Translation.tr("a short summary (usual apps and layout now, how your sessions start, the week's top apps, your favourite artists)"))
                        .arg(!(DesktopControl.habits.musicOn ?? true) ? Translation.tr("not recorded")
                            : Translation.tr("%1 days").arg(DesktopControl.habits.musicKeepDays ?? 365))
                    : Translation.tr("Off. When on, the launcher, a weekly report and agents learn from your own use of this computer, counted here without any model: app names and times only, never titles, files, sites or what you type.")
            }

            ConfigSwitch {
                enabled: !(DesktopControl.habits.nix ?? false)
                buttonIcon: "insights"
                text: Translation.tr("Learn from my usage")
                checked: DesktopControl.habits.enabled ?? false
                onCheckedChanged: if (checked !== (DesktopControl.habits.enabled ?? false)) DesktopControl.setHabitsEnabled(checked, false)
                StyledToolTip {
                    text: (DesktopControl.habits.nix ?? false)
                        ? Translation.tr("On in the Nix configuration (programs.nixbook-shell.desktopMcp.habits.enable)")
                        : Translation.tr("Starts or stops the recorder; what it recorded stays until you forget it")
                }
            }

            ConfigSwitch {
                visible: DesktopControl.habits.enabled ?? false
                buttonIcon: "pause_circle"
                text: Translation.tr("Record my usage")
                checked: !(DesktopControl.habits.paused ?? false)
                onCheckedChanged: if (checked === (DesktopControl.habits.paused ?? false)) DesktopControl.setHabitsPaused(!checked)
            }

            ContentSubsection {
                visible: DesktopControl.habits.enabled ?? false
                title: Translation.tr("What it learned")

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var lines: DesktopControl.habits.now ?? []
                    text: lines.length === 0 ? Translation.tr("Not enough recorded yet (%1 days).").arg(DesktopControl.habits.days ?? 0)
                        : lines.join("\n")
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: DesktopControl.habits.musicOn ?? false
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var lines: DesktopControl.habits.music ?? []
                    text: lines.length === 0
                        ? Translation.tr("Music: nothing played yet. What you play on any player (Spotify, YouTube Music…, not web browsers) teaches agents your taste: artist, title and album only.")
                        : Translation.tr("Music:") + "\n" + lines.join("\n")
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (DesktopControl.habits.report ?? "").length > 0
                    wrapMode: Text.WordWrap
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: DesktopControl.habits.report ?? ""
                }
            }

            RowLayout {
                visible: (DesktopControl.habits.enabled ?? false) || (DesktopControl.habits.days ?? 0) > 0
                spacing: 8
                SmallButton {
                    materialIcon: "delete_sweep"
                    mainText: Translation.tr("Forget everything")
                    onClicked: DesktopControl.clearHabits()
                }
                SmallButton {
                    visible: (DesktopControl.habits.music ?? []).length > 0
                    materialIcon: "music_off"
                    mainText: Translation.tr("Forget my music")
                    onClicked: DesktopControl.clearMusic()
                }
                SmallButton {
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh")
                    onClicked: DesktopControl.refreshHabits()
                }
            }
        }

        ContentSection {
            icon: "person_book"
            title: Translation.tr("About you")
            shape: MaterialShape.Shape.Cookie4Sided

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("What you told agents about your life — events, plans, people, interests — so later conversations know it. They keep the meaningful parts, one entry per subject, merged as things change. Only what a conversation needs is sent: your profile, events coming up, and the entries about what you're talking about; the rest by subject only. Kept apart from the desktop memory; delete anything.")
            }

            ConfigSwitch {
                configKey: "ai.claudeCode.autoMemory"
                buttonIcon: "auto_awesome"
                text: Translation.tr("Remember on their own: after a chat in the side panel, a small model keeps what matters")
                checked: Config.options.ai.claudeCode.autoMemory
                onCheckedChanged: Config.options.ai.claudeCode.autoMemory = checked
            }

            StyledText {
                visible: DesktopControl.personal.length === 0
                color: Appearance.colors.colSubtext
                text: Translation.tr("Nothing yet. Tell Claude in the side panel about yourself, or ask it to remember something.")
            }

            Repeater {
                model: [...DesktopControl.personal].sort((a, b) =>
                    ((a.kind === "profile" ? 0 : 1) - (b.kind === "profile" ? 0 : 1)) || (b.updated ?? 0) - (a.updated ?? 0))
                delegate: Rectangle {
                    id: entryRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: entryLayout.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        id: entryLayout
                        anchors { fill: parent; margins: 10; leftMargin: 14 }
                        spacing: 10

                        MaterialSymbol {
                            text: ({ profile: "badge", person: "person", event: "event" })[entryRow.modelData.kind] ?? "label"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: entryRow.modelData.topic + (entryRow.modelData.date ? ` · ${entryRow.modelData.date}` : "")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 5
                                elide: Text.ElideRight
                                text: entryRow.modelData.text
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: (entryRow.modelData.tentative ? Translation.tr("tentative (kept if it comes up again)") + " · " : "")
                                    + Translation.tr("importance %1/5 · by %2 · %3 · used %4 times")
                                    .arg(entryRow.modelData.kind === "profile" ? 5 : (entryRow.modelData.importance ?? 3))
                                    .arg(entryRow.modelData.client ?? "?")
                                    .arg(page.ago(entryRow.modelData.updated))
                                    .arg(entryRow.modelData.uses ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        SmallButton {
                            materialIcon: "delete"
                            mainText: Translation.tr("Delete")
                            onClicked: DesktopControl.forgetPersonal(entryRow.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                spacing: 8
                SmallButton {
                    materialIcon: "delete_sweep"
                    mainText: Translation.tr("Forget everything")
                    onClicked: DesktopControl.clearPersonal()
                }
                SmallButton {
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh")
                    onClicked: DesktopControl.refreshPersonal()
                }
            }
        }
    }
}
