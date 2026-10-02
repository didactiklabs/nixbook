import QtQuick
import QtQuick.Layouts
import qs
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

    Component.onCompleted: DesktopControl.refreshMemory()

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
                    buttonIcon: "picture_in_picture"
                    text: Translation.tr("Agents work on their own desktop")
                    checked: DesktopControl.onAgentDesktop && !DesktopControl.agentStopped
                    onClicked: {
                        if (DesktopControl.onAgentDesktop && !DesktopControl.agentStopped) DesktopControl.userDesktop();
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
                text: Translation.tr("On their own desktop, agents work in a window you watch but can't click or type into, with their own browser and apps, so they don't get in your way; your notes, to-do list and calendar stay reachable. The window opens when they start an app and closes once it's gone; close it yourself to stop them. Mod+Shift+A, right-clicking the bar widget and the desktop menu switch too. To use their desktop yourself for a moment (to log their browser in somewhere), take it over: your clicks and keys reach it and the agent waits until you give it back.")
                    + (DesktopControl.onAgentDesktop && DesktopControl.agentStopped ? " " + Translation.tr("You closed their desktop: they're stopped until you switch this on again.") : "")
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
                text: Translation.tr("The AI chat's Claude model runs Claude Code on your own Claude account (no API key), with the desktop tools. It can't run commands or edit files, and reads none of your files but the folders you allow below (and a file you attach to a message); below, what else it may do.")
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

            // The folders the apps on the agents' desktop may write too: the
            // first is where its browser downloads.
            ConfigTextArea {
                id: writableField
                configKey: "ai.writableFolders"
                enabled: !nixManaged
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "drive_folder_upload"
                text: Translation.tr("Folders the agents' desktop may write")
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
                text: Translation.tr("The apps on the agents' own desktop can save files there (from its next start), and its browser downloads into the first one, so an agent can fetch a file for you, a wallpaper say. Claude here can read them but not write them. Made if missing; not your whole home.")
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
                                text: noteRow.modelData.kind === "recipe" ? "format_list_numbered" : "sticky_note_2"
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
                                    text: Translation.tr("by %1 · %2 · used %3 times")
                                        .arg(noteRow.modelData.client ?? "?")
                                        .arg(page.ago(noteRow.modelData.updated))
                                        .arg(noteRow.modelData.uses ?? 0)
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
                    mainText: Translation.tr("Clear usage and aliases")
                    onClicked: DesktopControl.clearMemory(["usage", "aliases"])
                }
                SmallButton {
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh")
                    onClicked: DesktopControl.refreshMemory()
                }
            }
        }
    }
}
