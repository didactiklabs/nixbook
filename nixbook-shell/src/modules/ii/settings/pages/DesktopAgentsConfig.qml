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
// (ai.claudeCode, services/Ai.qml), the fixes it makes to nixbook itself
// (ai.improve, services/SelfImprove.qml), and the memory agents keep of the
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

        // policies.ai, the one switch for all of it (also Settings > Panels:
        // No, Yes, Local).
        ContentSection {
            icon: "neurology"
            title: Translation.tr("AI features")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Config.options.policies.ai === 0
                    ? Translation.tr("Off: no AI anywhere. No chat in the side panel, Claude never speaks on its own, no routine runs, no memory pass, no fix made, the equalizer agent rests, and every agent's desktop tools are refused (desktop control). What it remembers stays, unused.")
                    : Config.options.policies.ai === 2
                    ? Translation.tr("Local models only: nothing goes to an online model like Claude (no Claude chat, speaking on its own, memory pass, fix or equalizer agent); local agents keep the desktop tools, and fixed routines run.")
                    : Translation.tr("On: the features below, each with its own switch. Turn this off to stop all of them at once (Settings > Panels also has \"Local\": local models only).")
            }
            GroupedList {
                ConfigSwitch {
                    configKey: "policies.ai"
                    enabled: !nixManaged
                    buttonIcon: "neurology"
                    text: Translation.tr("AI features")
                    checked: Config.options.policies.ai !== 0
                    onCheckedChanged: {
                        if (checked !== (Config.options.policies.ai !== 0))
                            Config.options.policies.ai = checked ? 1 : 0
                    }
                }
            }
        }

        // The privacy mask (desktop-mcp.py, "Privacy mask"): what models read
        // has placeholders, swapped back on this computer.
        ContentSection {
            icon: "visibility_off"
            title: Translation.tr("Private details")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Your name, your contacts' names, emails, phones and addresses, card numbers, IBANs and the words below reach Claude as placeholders (⟦Person 2⟧, ⟦Email 1⟧), the same one each time, so it still follows who is who. They become the real values again on this computer when it types, sends or answers you. Done on this computer in a fraction of a millisecond: answers lose nothing but who those people are. Public names and sites stay as they are. For Claude here, its desktop tools and the small model's passes; not for what you paste into other apps.")
            }
            GroupedList {
                ConfigSwitch {
                    configKey: "ai.privacy.mask"
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Hide private details from AI models")
                    checked: Config.options.ai.privacy.mask
                    onCheckedChanged: Config.options.ai.privacy.mask = checked
                }
                ConfigSwitch {
                    configKey: "ai.privacy.screenshots"
                    buttonIcon: "screenshot_monitor"
                    enabled: Config.options.ai.privacy.mask
                    text: Translation.tr("In screenshots too: the details are read (OCR, on this computer) and blacked out, Claude told where they are. About a second more per screenshot; text the OCR misses, faces and photos still show")
                    checked: Config.options.ai.privacy.screenshots
                    onCheckedChanged: Config.options.ai.privacy.screenshots = checked
                }
            }
            // Saved when editing ends, so typing a comma isn't undone.
            ConfigTextArea {
                id: privacyTermsField
                configKey: "ai.privacy.terms"
                enabled: Config.options.ai.privacy.mask
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "edit_note"
                text: Translation.tr("Also private")
                placeholderText: Translation.tr("e.g. Acme Corp, 12 rue des Lilas, Project Falcon")
                value: (Config.options.ai.privacy.terms ?? []).join(", ")
                Connections {
                    target: privacyTermsField.textArea
                    function onEditingFinished() {
                        Config.options.ai.privacy.terms = privacyTermsField.value.split(",")
                            .map(f => f.trim()).filter(f => f.length > 0)
                    }
                }
            }
            GroupedList {
                ConfigSwitch {
                    configKey: "ai.privacy.learn"
                    buttonIcon: "person_search"
                    enabled: Config.options.ai.privacy.mask
                    text: Translation.tr("Learn who else is private: a stranger named where only people are (a mail's sender, a chat's, \"Hi Anna,\") or a personal email, seen in %1 different places, is hidden from then on. Counted on this computer; until then it is sent as it is").arg(Config.options.ai.privacy.learnAfter)
                    checked: Config.options.ai.privacy.learn
                    onCheckedChanged: Config.options.ai.privacy.learn = checked
                }
            }
            // The names learned (`privacy learned`): × says one isn't private.
            ContentSubsection {
                title: Translation.tr("Learned private")
                visible: Config.options.ai.privacy.mask && Config.options.ai.privacy.learn
                Process {
                    id: learnedRead
                    running: true
                    command: ["nixbook-desktop-mcp", "privacy", "learned"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            try {
                                learnedList.entries = JSON.parse(text)
                            } catch (e) {
                                learnedList.entries = []
                            }
                        }
                    }
                }
                Flow {
                    id: learnedList
                    property var entries: []
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        visible: learnedList.entries.length === 0
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("None yet.")
                    }
                    Repeater {
                        model: learnedList.entries
                        delegate: SmallButton {
                            required property var modelData
                            materialIcon: "close"
                            mainText: modelData.value
                            onClicked: {
                                DesktopHelper.run(["privacy", "unlearn", modelData.key])
                                learnedList.entries = learnedList.entries.filter(e => e.key !== modelData.key)
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("× : not private, never learned again.")
                }
            }
            // Wraps onto more lines on a narrow page (a RowLayout widened the page).
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SmallButton {
                    materialIcon: "delete"
                    mainText: Translation.tr("Forget the placeholders")
                    onClicked: DesktopHelper.run(["privacy", "clear"])
                }
            }
        }

        ContentSection {
            icon: "chat_bubble"
            title: Translation.tr("Talks to you on its own")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Claude speaks first when it can help, not on a schedule: when you come back (your day, a plan coming up or just past, your usual setup), when an app it has a broken recipe for is in front, when it learned something. Time-critical things come as its own speech bubble on the left, in the theme's look: answer right in it and Claude answers there (the expand button moves the talk to the side panel; quick answers, Not now, Don't tell me this; at most 8 a day, none at night, in a meeting or fullscreen); the rest waits as a bubble beside the robot in the bar. Now and then, at random and up to four times a day, it says a light word in the bar: a break after a long stretch, a tip for the app you're in, a plan coming up, a question about something you care about. It learns from your answers what is worth saying. Plain code decides; a small model only reads notifications and words tips and questions.")
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
                ConfigSwitch {
                    configKey: "ai.initiative.curious"
                    buttonIcon: "psychology_alt"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Be curious: watch what I do (the app and window title in front, read once a day by the small model), learn it, and tell me what it learned")
                    checked: Config.options.ai.initiative.curious
                    onCheckedChanged: Config.options.ai.initiative.curious = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.reactions"
                    buttonIcon: "bolt"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("React to what I do: a file downloaded, a screenshot, a drive plugged in, with one-click help (open, show in folder, summarize, what's in it). No model call until I click")
                    checked: Config.options.ai.initiative.reactions
                    onCheckedChanged: Config.options.ai.initiative.reactions = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.news"
                    buttonIcon: "newspaper"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Tell me the news I'd care about: about once a day, the small model searches the web for what's new on the subjects I talk about most (from its memory of me; the subjects go to the search) and sums it up, with links")
                    checked: Config.options.ai.initiative.news
                    onCheckedChanged: Config.options.ai.initiative.news = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.pair"
                    buttonIcon: "group"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Pair with me: while I stay on something, it looks at what (the app and window title, never chats, mail, password managers or private windows), guesses what I'm doing and, only when it truly helps, says a tip or a fix (searching the web first if useful). Quietly: it waits in the bar and shows when I pause")
                    checked: Config.options.ai.initiative.pair
                    onCheckedChanged: Config.options.ai.initiative.pair = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.pairReadScreen"
                    buttonIcon: "document_scanner"
                    enabled: Config.options.ai.initiative.enable && Config.options.ai.initiative.pair
                    text: Translation.tr("While pairing, read the screen's text too (OCR on this computer; secrets, addresses and numbers removed before the small model sees it; never while a private window is on the workspace; nothing kept)")
                    checked: Config.options.ai.initiative.pairReadScreen
                    onCheckedChanged: Config.options.ai.initiative.pairReadScreen = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.holdInFocus"
                    buttonIcon: "do_not_disturb_on"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Don't interrupt me while I'm focused: after 10 minutes at something (one or two apps, no break), its quiet words wait and come together at the next break (another app, a minute away). Urgent ones still come")
                    checked: Config.options.ai.initiative.holdInFocus
                    onCheckedChanged: Config.options.ai.initiative.holdInFocus = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.recentContext"
                    buttonIcon: "history"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Know what I was just doing: the windows of the last 15 minutes, a command that failed, an error I copied, kept in memory only (never on disk). Sent only with a question I ask in its bubble (it says so; × leaves it out), private apps and windows left out and secrets removed; and a word on where I was when I'm back from a break")
                    checked: Config.options.ai.initiative.recentContext
                    onCheckedChanged: Config.options.ai.initiative.recentContext = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.terminal"
                    buttonIcon: "terminal"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Help when a terminal command keeps failing: the same command failing twice in 10 minutes offers \"Explain it\" (zsh and bash; only the command and its exit code, never its output; a command starting with a space is never seen). Nothing goes to Claude until I click")
                    checked: Config.options.ai.initiative.terminal
                    onCheckedChanged: Config.options.ai.initiative.terminal = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.clipboardErrors"
                    buttonIcon: "content_paste_search"
                    enabled: Config.options.ai.initiative.enable
                    text: Translation.tr("Help with an error I copy: copying an error or a stack trace offers \"Explain it\" (never what a password manager copied). Nothing goes to Claude until I click")
                    checked: Config.options.ai.initiative.clipboardErrors
                    onCheckedChanged: Config.options.ai.initiative.clipboardErrors = checked
                }
                ConfigSwitch {
                    configKey: "ai.initiative.improveIdeas"
                    shown: SelfImprove.available
                    buttonIcon: "tips_and_updates"
                    enabled: Config.options.ai.initiative.enable && (SelfImprove.enabled || SelfImprove.featuresEnabled)
                    text: Translation.tr("Propose fixes and features of nixbook: every two days at most, from what it saw go wrong or get in my way (what failed in its memory, routines I undid, its tools' errors, the apps pairing saw me in), one fix or feature, offered with why. My yes files it for the fixer, a no is never proposed again. Needs Fixes it makes itself or Features it builds on")
                    checked: Config.options.ai.initiative.improveIdeas
                    onCheckedChanged: Config.options.ai.initiative.improveIdeas = checked
                }
            }

            // What agents watch for me (the watch tool): cancel one.
            Repeater {
                model: Initiative.watches
                delegate: RowLayout {
                    id: watchRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: "visibility"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Translation.tr("Watching %1, to tell you when it's done").arg(watchRow.modelData.label)
                    }
                    SmallButton {
                        materialIcon: "close"
                        mainText: Translation.tr("Stop")
                        onClicked: Quickshell.execDetached(["nixbook-desktop-mcp", "watch", "cancel", watchRow.modelData.id])
                    }
                }
            }

            // Wraps onto more lines on a narrow page (a RowLayout widened the page).
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SmallButton {
                    materialIcon: "campaign"
                    enabled: Config.options.ai.initiative.enable && Initiative.asking === ""
                    mainText: Initiative.asking === "say" ? Translation.tr("Thinking…") : Translation.tr("Say something now")
                    onClicked: Initiative.sayNow()
                }
                SmallButton {
                    materialIcon: "newspaper"
                    visible: Config.options.ai.initiative.news
                    enabled: Config.options.ai.initiative.enable && Initiative.asking === ""
                    mainText: Initiative.asking === "news" ? Translation.tr("Searching the news…") : Translation.tr("Find news now")
                    onClicked: Initiative.newsNow()
                }
                SmallButton {
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Undo every \"Don't tell me this\"")
                    onClicked: DesktopHelper.run(["initiative", "unmute"])
                }
            }
            // Say something now / Find news now: working, then what came of it.
            StyledIndeterminateProgressBar {
                visible: Initiative.asking !== ""
                Layout.fillWidth: true
            }
            StyledText {
                Layout.fillWidth: true
                visible: Initiative.asking === "" && Initiative.asked !== ""
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Initiative.asked === "notify" ? Translation.tr("Said in its bubble, on the left under the bar.")
                    : Initiative.asked === "badge" ? Translation.tr("It waits in the bar: click the robot's bubble.")
                    : Translation.tr("Nothing worth saying right now.")
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

            // What was sent to a model (`nixbook-desktop-mcp sent`): each
            // small-model pass and the context sent with a question, as sent.
            ContentSubsection {
                title: Translation.tr("What it sent")
                tooltip: Translation.tr("Everything the small model was given (notifications, pairing, news, memory passes…) and what went with a question asked in the bubble, the last 7 days. A local model's are marked: they never left this computer. Not your chats in the side panel: you wrote those.")
                // Wraps onto more lines on a narrow page (a RowLayout widened the page).
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    SmallButton {
                        materialIcon: sentList.shown ? "expand_less" : "receipt_long"
                        mainText: sentList.shown ? Translation.tr("Hide") : Translation.tr("Show what it sent")
                        onClicked: {
                            sentList.shown = !sentList.shown
                            if (sentList.shown) sentRead.running = true
                        }
                    }
                    SmallButton {
                        materialIcon: "delete"
                        mainText: Translation.tr("Forget it")
                        onClicked: {
                            DesktopHelper.run(["sent", "clear"])
                            sentList.entries = []
                        }
                    }
                }
                Process {
                    id: sentRead
                    command: ["nixbook-desktop-mcp", "sent", "show"]
                    stdout: StdioCollector {
                        id: sentOut
                        onStreamFinished: {
                            try {
                                sentList.entries = JSON.parse(sentOut.text).slice(0, 30)
                            } catch (e) {
                                sentList.entries = []
                            }
                        }
                    }
                }
                ColumnLayout {
                    id: sentList
                    property bool shown: false
                    property var entries: []
                    visible: shown
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        visible: sentList.entries.length === 0
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Nothing sent lately.")
                    }
                    Repeater {
                        model: sentList.entries
                        delegate: ColumnLayout {
                            id: sentRow
                            required property var modelData
                            property bool open: false
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                font.weight: Font.Medium
                                text: `${Qt.formatDateTime(new Date(sentRow.modelData.time * 1000), "ddd hh:mm")} · ${sentRow.modelData.purpose} · `
                                    + (sentRow.modelData.local ? Translation.tr("%1, on this computer").arg(sentRow.modelData.model.replace(/^local:/, ""))
                                       : sentRow.modelData.model) + (sentRow.modelData.web ? Translation.tr(" · could search the web") : "")
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sentRow.open = !sentRow.open
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                maximumLineCount: sentRow.open ? 400 : 2
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: sentRow.modelData.text
                            }
                        }
                    }
                }
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
                visible: Routines.routines.length === 0
                color: Appearance.colors.colSubtext
                text: Translation.tr("None yet.")
            }
            // What it saw lately and what came of it: why a routine ran or didn't.
            StyledText {
                Layout.fillWidth: true
                visible: Routines.recent.length > 0
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Seen lately:") + "\n" + Routines.recent.slice(-6).reverse().map(n =>
                    `${Qt.formatDateTime(new Date(n.time), "hh:mm")} · ${n.what} · ${n.outcome}`).join("\n")
            }
            Repeater {
                model: Routines.routines
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

        // services/SelfImprove.qml, nixbook-improve: only where Nix made it
        // available (programs.nixbook-shell.selfImprove.enable).
        ContentSection {
            visible: SelfImprove.available
            icon: "build"
            title: Translation.tr("Fixes it makes itself")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Claude fixes nixbook itself: fixes and polish only (a bug, a rough edge, wording); a new feature, or a fix found too big, goes to Features it builds (below). What to fix: what you tell an agent is broken (\"report this\") or write below (your words stay on this computer: the PR says it in its own), the errors the shell prints, the desktop tools' crashes, failed units and errors in the logs of what nixbook defines, a failed update or Nix warning, CI red on main, crashes of nixbook's programs (only what you can already read; what isn't nixbook's is listed below, never sent unasked). Each fix is made in a clone of the repository by a Claude Code session that can only edit files there (no commands, none of your files or logins), checked (its size and files, the tests, the shell started headless with no new error), committed with a changelog entry and opened as a pull request. Once CI passes you get Merge, Look, Drop; nothing reaches main without you, but what you let merge on its own. After a merge, main's checks and the updated shell are watched: what it broke is queued as a fix of its own, never reverted. One it can't do (a place off limits, credentials, hardware, or its change failing twice) is dropped with why and what would make it doable; you're told, and Retry tries again. Its sandbox, the tests, CI and its own code are off limits; what agents may do is never merged on its own. It reaches GitHub only with its own token, below (never your gh login or ssh key; Claude never sees it), and uses your Claude Code; %1.").arg(Config.options.ai.improve.perDay > 0
                    ? Translation.tr("at most %1 a day on its own, each at most $%2").arg(Config.options.ai.improve.perDay).arg(Config.options.ai.improve.budgetUsd)
                    : Translation.tr("no daily limit, each at most $%1").arg(Config.options.ai.improve.budgetUsd))
            }

            // What it is doing now, or why nothing: always shown.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusColumn.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    id: statusColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: SelfImprove.running?.feature === false ? "build" : !SelfImprove.enabled ? "pause_circle"
                                : !SelfImprove.tokenSaved ? "key" : SelfImprove.waitingOf(false).length > 0 ? "pending_actions" : "check_circle"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer2
                            text: SelfImprove.statusOf(false)
                        }
                        SmallButton {
                            visible: SelfImprove.running !== null && SelfImprove.running.feature !== true
                            materialIcon: "stop"
                            mainText: Translation.tr("Stop")
                            onClicked: SelfImprove.stop()
                        }
                    }
                    StyledIndeterminateProgressBar {
                        visible: SelfImprove.running !== null && SelfImprove.running.feature !== true
                        Layout.fillWidth: true
                    }
                }
            }

            // Its GitHub token, kept in the keyring.
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("GitHub token: a fine-grained token (GitHub > Settings > Developer settings > Fine-grained tokens) for this repository only, with Contents and Pull requests set to Read and write, nothing else. Kept in your keyring.")
                    + " " + (SelfImprove.tokenSaved ? Translation.tr("A token is saved.") : Translation.tr("No token yet: it opens no pull request until you add one."))
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialTextField {
                    id: improveToken
                    Layout.fillWidth: true
                    placeholderText: SelfImprove.tokenSaved ? Translation.tr("Token (saved: paste a new one to replace it)") : Translation.tr("Token")
                    echoMode: TextInput.Password
                    onAccepted: improveTokenSave.clicked()
                }
                SmallButton {
                    id: improveTokenSave
                    enabled: !SelfImprove.tokenBusy && improveToken.text.trim() !== ""
                    materialIcon: "key"
                    mainText: SelfImprove.tokenBusy ? Translation.tr("Checking…") : Translation.tr("Save and check")
                    onClicked: {
                        SelfImprove.setToken(improveToken.text)
                        improveToken.text = ""
                    }
                }
                SmallButton {
                    visible: SelfImprove.tokenSaved
                    enabled: !SelfImprove.tokenBusy
                    materialIcon: "key_off"
                    mainText: Translation.tr("Forget the token")
                    onClicked: SelfImprove.forgetToken()
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: SelfImprove.tokenStatus !== ""
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: SelfImprove.tokenStatus
            }

            GroupedList {
                ConfigSwitch {
                    configKey: "ai.improve.enable"
                    buttonIcon: "build"
                    text: Translation.tr("Make fixes on its own")
                    checked: Config.options.ai.improve.enable
                    onCheckedChanged: Config.options.ai.improve.enable = checked
                }
                ConfigSwitch {
                    configKey: "ai.improve.autoMerge"
                    buttonIcon: "merge"
                    enabled: Config.options.ai.improve.enable
                    text: Translation.tr("Merge docs-only fixes on its own")
                    checked: Config.options.ai.improve.autoMerge
                    onCheckedChanged: Config.options.ai.improve.autoMerge = checked
                }
                ConfigSwitch {
                    configKey: "ai.improve.autoMergeFixes"
                    buttonIcon: "auto_mode"
                    enabled: Config.options.ai.improve.enable
                    text: Translation.tr("Merge every fix on its own once CI passes")
                    checked: Config.options.ai.improve.autoMergeFixes
                    onCheckedChanged: Config.options.ai.improve.autoMergeFixes = checked
                    StyledToolTip {
                        text: Translation.tr("Except a fix touching what agents may do (their tools, permissions, switches): that one always waits for your Merge. Main's checks and the updated shell are still watched, and what a merge broke is queued as a fix (never a revert).")
                    }
                }
            }

            ConfigSelectionArray {
                configKey: "ai.improve.model"
                text: Translation.tr("Model")
                icon: "psychology"
                currentValue: Config.options.ai.improve.model
                onSelected: newValue => { Config.options.ai.improve.model = newValue }
                options: [
                    { displayName: "Sonnet", icon: "speed", value: "sonnet" },
                    { displayName: "Opus", icon: "psychology", value: "opus" }
                ]
            }

            // The day's limit of fixes started on its own (0: none) and what
            // each may spend, which bounds an unlimited day.
            ConfigSpinBox {
                configKey: "ai.improve.perDay"
                icon: "event_repeat"
                text: Translation.tr("Fixes a day on its own (0: no limit)")
                value: Config.options.ai.improve.perDay
                from: 0; to: 50; stepSize: 1
                onValueChanged: Config.options.ai.improve.perDay = value
            }
            ConfigSpinBox {
                configKey: "ai.improve.budgetUsd"
                icon: "payments"
                text: Translation.tr("Most a fix may spend ($)")
                value: Config.options.ai.improve.budgetUsd
                from: 1; to: 50; stepSize: 1
                onValueChanged: Config.options.ai.improve.budgetUsd = value
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialTextField {
                    id: improveNote
                    Layout.fillWidth: true
                    enabled: Config.options.ai.improve.enable
                    placeholderText: Translation.tr("Something to fix…")
                    onAccepted: improveAdd.clicked()
                }
                SmallButton {
                    id: improveAdd
                    enabled: Config.options.ai.improve.enable && improveNote.text.trim() !== ""
                    materialIcon: "add"
                    mainText: Translation.tr("Add")
                    onClicked: {
                        SelfImprove.note(improveNote.text)
                        improveNote.text = ""
                    }
                }
                SmallButton {
                    enabled: Config.options.ai.improve.enable
                    materialIcon: "search"
                    mainText: Translation.tr("Look for bugs now")
                    onClicked: SelfImprove.collectNow()
                }
            }


            // The fixes waiting for the user: a PR each (features' below).
            Component {
                id: prItem
                RowLayout {
                    id: prRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    MaterialSymbol {
                        text: prRow.modelData.ci === "fail" ? "error" : prRow.modelData.ci === "pass" ? "check_circle" : "pending"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colOnLayer1
                        text: `#${prRow.modelData.pr} ${prRow.modelData.title}`
                            + (prRow.modelData.sensitive ? " · " + Translation.tr("touches what agents may do") : "")
                    }
                    SmallButton {
                        enabled: prRow.modelData.ci === "pass"
                        materialIcon: "merge"
                        mainText: Translation.tr("Merge")
                        onClicked: SelfImprove.act("merge", prRow.modelData.pr)
                    }
                    SmallButton {
                        materialIcon: "open_in_new"
                        mainText: Translation.tr("Look")
                        onClicked: SelfImprove.act("look", prRow.modelData.pr)
                    }
                    SmallButton {
                        materialIcon: "close"
                        mainText: Translation.tr("Drop")
                        onClicked: SelfImprove.act("drop", prRow.modelData.pr)
                    }
                }
            }
            Repeater {
                model: SelfImprove.waitingOf(false)
                delegate: prItem
            }

            // What it has to fix: the user's reports first. Tried and not fixed
            // too (failed, skipped, too big): Fix now tries again. What it
            // skipped as harmless (ignored) or moved to the features isn't
            // listed. The features' list (below) uses it too.
            Component {
                id: inboxItem
                RowLayout {
                    id: itemRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    readonly property bool feature: itemRow.modelData.kind === "feature"
                    // Given up (it couldn't do it): Retry, As a feature, Dismiss.
                    readonly property bool unable: itemRow.modelData.status === "unable"
                    // Waiting its turn: its place, moved up or down, or taken out.
                    readonly property int queuePos: SelfImprove.queuePos(itemRow.modelData.id)
                    MaterialSymbol {
                        text: ({ user: "person", crash: "bug_report", coredump: "bug_report", service: "dns", log: "receipt_long",
                                 deploy: "system_update", warning: "warning", ci: "fact_check", qml: "code", info: "info", regression: "heart_broken",
                                 feature: itemRow.modelData.from ? "call_split" : "lightbulb" })[itemRow.modelData.kind] ?? "warning"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer1
                            // A failed unit carries its last log lines: the first few here.
                            text: itemRow.modelData.text.split("\n").slice(0, 3).join("\n")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: [itemRow.queuePos > 0 ? Translation.tr("Queued, #%1").arg(itemRow.queuePos) : "",
                                   itemRow.feature ? (itemRow.modelData.from ? Translation.tr("too big for a fix") : itemRow.modelData.count === 1 ? Translation.tr("asked once") : Translation.tr("asked %1 times").arg(itemRow.modelData.count))
                                   : itemRow.modelData.count === 1 ? Translation.tr("seen once") : Translation.tr("seen %1 times").arg(itemRow.modelData.count),
                                   Qt.formatDateTime(new Date(itemRow.modelData.last), "d MMM, hh:mm"),
                                   ({ failed: Translation.tr("failed"), skipped: Translation.tr("skipped"), too_big: Translation.tr("too big for a fix"),
                                      unable: Translation.tr("couldn't do it") })[itemRow.modelData.status] ?? "",
                                   itemRow.modelData.note ?? ""].filter(x => x).join(" · ")
                        }
                    }
                    // While one is being made, it goes in the queue instead.
                    SmallButton {
                        visible: itemRow.queuePos === 0
                        enabled: itemRow.feature ? SelfImprove.featuresEnabled : Config.options.ai.improve.enable
                        materialIcon: SelfImprove.running !== null ? "queue" : itemRow.unable ? "replay" : itemRow.feature ? "construction" : "build"
                        mainText: SelfImprove.running !== null ? Translation.tr("Queue") : itemRow.unable ? Translation.tr("Retry")
                            : itemRow.feature ? Translation.tr("Build now") : Translation.tr("Fix now")
                        onClicked: SelfImprove.fixNow(itemRow.modelData.id)
                    }
                    SmallButton {
                        visible: itemRow.queuePos > 1
                        materialIcon: "arrow_upward"
                        mainText: Translation.tr("Earlier")
                        onClicked: SelfImprove.moveQueued(itemRow.modelData.id, "up")
                    }
                    SmallButton {
                        visible: itemRow.queuePos > 0 && itemRow.queuePos < SelfImprove.queue.length
                        materialIcon: "arrow_downward"
                        mainText: Translation.tr("Later")
                        onClicked: SelfImprove.moveQueued(itemRow.modelData.id, "down")
                    }
                    SmallButton {
                        visible: itemRow.queuePos > 0
                        materialIcon: "remove_from_queue"
                        mainText: Translation.tr("Unqueue")
                        onClicked: SelfImprove.unqueue(itemRow.modelData.id)
                    }
                    // A fix found too big before they moved on their own.
                    SmallButton {
                        visible: !itemRow.feature && (itemRow.modelData.status === "too_big" || itemRow.unable)
                        materialIcon: "lightbulb"
                        mainText: Translation.tr("As a feature")
                        onClicked: SelfImprove.toFeature(itemRow.modelData.id)
                    }
                    SmallButton {
                        materialIcon: itemRow.unable ? "close" : "delete"
                        mainText: itemRow.unable ? Translation.tr("Dismiss") : Translation.tr("Drop")
                        onClicked: SelfImprove.dropItem(itemRow.modelData.id)
                    }
                }
            }
            Repeater {
                model: SelfImprove.inbox.filter(i => i.kind !== "info" && i.kind !== "feature" && ["new", "failed", "skipped", "too_big"].includes(i.status))
                delegate: inboxItem
            }
            // What it gave up, with why: never tried again unless you Retry.
            StyledText {
                Layout.fillWidth: true
                visible: SelfImprove.unableOf(false).length > 0
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnLayer1
                text: Translation.tr("Dropped: it couldn't do these (Retry tries again, Dismiss forgets it)")
            }
            Repeater {
                model: SelfImprove.unableOf(false)
                delegate: inboxItem
            }
            // What isn't nixbook's (another app's crash, the kernel, a unit it
            // doesn't define): to know; sent to Claude only by Fix now.
            StyledText {
                Layout.fillWidth: true
                visible: SelfImprove.inbox.some(i => i.kind === "info" && ["new", "failed", "skipped", "too_big"].includes(i.status))
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnLayer1
                text: Translation.tr("Seen, not nixbook's (never sent to Claude unless you press Fix now)")
            }
            Repeater {
                model: SelfImprove.inbox.filter(i => i.kind === "info" && ["new", "failed", "skipped", "too_big"].includes(i.status)).slice(0, 10)
                delegate: inboxItem
            }

            // What it did and decided lately (activity.json), newest first.
            StyledText {
                Layout.fillWidth: true
                visible: SelfImprove.activityOf(false).length > 0
                text: Translation.tr("Activity")
                color: Appearance.colors.colOnLayer1
            }
            Component {
                id: activityItem
                RowLayout {
                    id: eventRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: ({ look: "search", wait: "hourglass_empty", start: "build", retry: "replay", done: "flag",
                                 pr: "call_split", ci: "fact_check", merged: "merge", broke: "heart_broken", error: "error" })[eventRow.modelData.kind] ?? "info"
                        iconSize: Appearance.font.pixelSize.normal
                        color: eventRow.modelData.kind === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: `${Qt.formatDateTime(new Date(eventRow.modelData.time), "d MMM hh:mm")} · ${eventRow.modelData.text}`
                    }
                }
            }
            Repeater {
                model: SelfImprove.activityOf(false).slice(0, 8)
                delegate: activityItem
            }
        }

        // The features it builds (ai.improve.features), apart from the fixes:
        // the same nixbook-improve, token and model; other rules (bigger, new
        // files), never merged on its own.
        ContentSection {
            visible: SelfImprove.available
            icon: "lightbulb"
            title: Translation.tr("Features it builds")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Claude builds what you ask nixbook to do: a new widget, setting, shortcut or behaviour. Ask an agent (\"I wish the bar showed…\": its request_feature tool files it) or type it below; a fix Claude finds too big for a fix comes here too, with what it found, and with Propose fixes and features on, the agent may offer one itself from what it saw get in your way. Each is built like a fix (a clone, a session that can only edit files there, the same checks and off-limits places) but may be bigger (up to %1 files and %2 lines, new files allowed), committed as feat(…) and opened as a pull request. It is never merged on its own: once CI passes you get Merge, Look, Drop. One it can't do (a design choice only you can make, more than that, a place off limits, credentials, hardware, or its change failing twice) is dropped with why and what would make it doable; you're told, and Retry tries again. It uses the GitHub token and model of Fixes it makes itself; %3, Build now starts one at once.")
                    .arg(Config.options.ai.improve.features.maxFiles).arg(Config.options.ai.improve.features.maxLines)
                    .arg(Config.options.ai.improve.features.perDay > 0
                        ? Translation.tr("at most %1 a day on its own, each at most $%2").arg(Config.options.ai.improve.features.perDay).arg(Config.options.ai.improve.features.budgetUsd)
                        : Translation.tr("no daily limit, each at most $%1").arg(Config.options.ai.improve.features.budgetUsd))
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: featureStatusColumn.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                ColumnLayout {
                    id: featureStatusColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: SelfImprove.running?.feature === true ? "construction" : !SelfImprove.featuresEnabled ? "pause_circle"
                                : !SelfImprove.tokenSaved ? "key" : SelfImprove.waitingOf(true).length > 0 ? "pending_actions" : "check_circle"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer2
                            text: SelfImprove.statusOf(true)
                        }
                        SmallButton {
                            visible: SelfImprove.running?.feature === true
                            materialIcon: "stop"
                            mainText: Translation.tr("Stop")
                            onClicked: SelfImprove.stop()
                        }
                    }
                    StyledIndeterminateProgressBar {
                        visible: SelfImprove.running?.feature === true
                        Layout.fillWidth: true
                    }
                }
            }

            GroupedList {
                ConfigSwitch {
                    configKey: "ai.improve.features.enable"
                    buttonIcon: "construction"
                    text: Translation.tr("Build the features I ask for")
                    checked: Config.options.ai.improve.features.enable
                    onCheckedChanged: Config.options.ai.improve.features.enable = checked
                }
            }

            ConfigSpinBox {
                configKey: "ai.improve.features.perDay"
                icon: "event_repeat"
                text: Translation.tr("Features a day on its own (0: no limit)")
                value: Config.options.ai.improve.features.perDay
                from: 0; to: 50; stepSize: 1
                onValueChanged: Config.options.ai.improve.features.perDay = value
            }
            ConfigSpinBox {
                configKey: "ai.improve.features.budgetUsd"
                icon: "payments"
                text: Translation.tr("Most a feature may spend ($)")
                value: Config.options.ai.improve.features.budgetUsd
                from: 1; to: 100; stepSize: 1
                onValueChanged: Config.options.ai.improve.features.budgetUsd = value
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialTextField {
                    id: featureRequest
                    Layout.fillWidth: true
                    enabled: Config.options.ai.improve.features.enable
                    placeholderText: Translation.tr("A feature to add…")
                    onAccepted: featureAdd.clicked()
                }
                SmallButton {
                    id: featureAdd
                    enabled: Config.options.ai.improve.features.enable && featureRequest.text.trim() !== ""
                    materialIcon: "add"
                    mainText: Translation.tr("Ask")
                    onClicked: {
                        SelfImprove.request(featureRequest.text)
                        featureRequest.text = ""
                    }
                }
            }

            Repeater {
                model: SelfImprove.waitingOf(true)
                delegate: prItem
            }
            Repeater {
                model: SelfImprove.inbox.filter(i => i.kind === "feature" && ["new", "failed", "skipped", "too_big"].includes(i.status))
                delegate: inboxItem
            }
            StyledText {
                Layout.fillWidth: true
                visible: SelfImprove.unableOf(true).length > 0
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnLayer1
                text: Translation.tr("Dropped: it couldn't build these (Retry tries again, Dismiss forgets it)")
            }
            Repeater {
                model: SelfImprove.unableOf(true)
                delegate: inboxItem
            }

            StyledText {
                Layout.fillWidth: true
                visible: SelfImprove.activityOf(true).length > 0
                text: Translation.tr("Activity")
                color: Appearance.colors.colOnLayer1
            }
            Repeater {
                model: SelfImprove.activityOf(true).slice(0, 8)
                delegate: activityItem
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
                    configKey: "ai.claudeCode.commandLine"
                    enabled: !nixManaged
                    buttonIcon: "terminal"
                    text: Translation.tr("Command line")
                    checked: Config.options.ai.claudeCode.commandLine
                    onCheckedChanged: Config.options.ai.claudeCode.commandLine = checked
                    StyledToolTip {
                        text: Translation.tr("Claude may run commands as you (Bash); it asks in the chat before anything that changes the system or your files")
                    }
                }
                ConfigSwitch {
                    configKey: "ai.claudeCode.commandLineFolders"
                    enabled: !nixManaged && Config.options.ai.claudeCode.commandLine
                    buttonIcon: "folder_managed"
                    text: Translation.tr("Only in the allowed folders")
                    checked: Config.options.ai.claudeCode.commandLineFolders
                    onCheckedChanged: Config.options.ai.claudeCode.commandLineFolders = checked
                    StyledToolTip {
                        text: Translation.tr("On: its commands, and what they start, run in a sandbox where only the folders below can be read and the writable ones written. Off: they have your full access")
                    }
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
                    ? Translation.tr("Connectors: %1").arg(Ai.claudeConnectors.map(c => c.replace(/^mcp__(claude_ai|plugin)_/, "").replace(/_/g, " ")).join(", "))
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
                                    immich: ["photo_library", Translation.tr("Immich: search and organize your photos")],
                                    jellyfin: ["movie", Translation.tr("Jellyfin: your films, series and music; play them")],
                                    phone: ["smartphone", Translation.tr("Phone (KDE Connect): send texts, share links, ring it")]
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

                // The phone: reading what it holds is its own switch.
                ConfigSwitch {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: Ai.assistantMcpServers.phone !== undefined
                    configKey: "ai.phone.readMessages"
                    enabled: !nixManaged && !(Config.options.ai.claudeCode.mcpServersOff ?? []).includes("phone")
                    buttonIcon: "sms"
                    text: Translation.tr("Let it read my phone's texts, notifications and contacts (what they say goes to Claude)")
                    checked: Config.options.ai.phone.readMessages
                    onCheckedChanged: Config.options.ai.phone.readMessages = checked
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
                    // Wraps onto more lines on a narrow page (a RowLayout widened the page).
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        SmallButton {
                            id: immichSave
                            readonly property string url: immichUrl.value.trim().replace(/\/+$/, "")
                            enabled: !immich.busy && url !== ""
                                && (immichKey.text !== "" || immich.conn.has_key === true)
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

                // Jellyfin: its server is a setting (ai.jellyfin.url, locked
                // when set in Nix). The assistant signs in as the user (`jellyfin-mcp
                // credentials login`, the password — an app password with 2FA —
                // on stdin, never kept): its own token, in the keyring, no
                // admin needed; the player of this computer (jellyfin-mpv-shim)
                // is signed in with it, with a token of its own. An admin's
                // API key instead (`credentials save`, for ai.jellyfin.user;
                // or a key file set in Nix, ai.jellyfin.apiKeyFile).
                ColumnLayout {
                    id: jellyfin
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: Ai.assistantMcpServers.jellyfin !== undefined
                    spacing: 6
                    readonly property string bin: Ai.assistantMcpServers.jellyfin
                        ? Ai.assistantMcpServers.jellyfin.command : ""
                    readonly property string url: jellyfinUrl.value.trim().replace(/\/+$/, "")
                    // {has_key, key_source: env|file|keyring|null, kind: token|apikey|null, signed_in_as}
                    property var conn: ({})
                    readonly property bool signedIn: jellyfin.conn.kind === "token"
                    // The admin API key's fields: asked for, or that's what is set.
                    property bool useKey: false
                    readonly property bool keyMode: jellyfin.useKey || jellyfin.conn.kind === "apikey"
                    // {signed_in, user, device, service}
                    property var player: ({})
                    property string status: ""
                    property string playerStatus: ""
                    property bool busy: false

                    function run(args, secret) {
                        if (jellyfin.busy || !jellyfin.bin) return
                        jellyfin.busy = true
                        jellyfinProc.secret = secret ?? ""
                        jellyfinProc.args = args
                        jellyfinProc.command = [jellyfin.bin, ...args]
                        jellyfinProc.environment = Ai.jellyfinEnv
                        jellyfinProc.stdinEnabled = ["save", "test", "login", "shim-login"].includes(args[0] === "credentials" ? args[1] : args[0])
                        jellyfinProc.running = true
                    }
                    function refresh() {
                        jellyfin.run(["credentials", "status"])
                    }
                    // assistant-mcp.json is read asynchronously.
                    Component.onCompleted: refresh()
                    onBinChanged: refresh()

                    Process {
                        id: jellyfinProc
                        property string secret: ""
                        property var args: []
                        stdout: StdioCollector { id: jellyfinOut }
                        onRunningChanged: {
                            if (!jellyfinProc.running || !jellyfinProc.stdinEnabled) return
                            jellyfinProc.write(jellyfinProc.secret + "\n")
                            jellyfinProc.secret = ""
                            jellyfinProc.stdinEnabled = false
                        }
                        onExited: code => {
                            jellyfin.busy = false
                            const what = jellyfinProc.args[0] === "credentials" ? jellyfinProc.args[1] : jellyfinProc.args[0]
                            let result = null
                            try {
                                result = JSON.parse(jellyfinOut.text)
                            } catch (e) {}
                            const player = what.startsWith("shim")
                            if (code !== 0 || !result) {
                                const why = result?.error ?? Translation.tr("Couldn't reach the Jellyfin helper")
                                if (player) jellyfin.playerStatus = why
                                else jellyfin.status = why
                                return
                            }
                            if (player) {
                                jellyfin.player = result
                                if (what === "shim-login") {
                                    jellyfinPassword.text = ""
                                    jellyfin.playerStatus = Translation.tr("Player connected as %1 (%2).").arg(result.user).arg(result.device)
                                } else if (what === "shim-logout") {
                                    jellyfin.playerStatus = Translation.tr("Player disconnected.")
                                }
                                if (what !== "shim-status") Qt.callLater(() => jellyfin.run(["shim-status"]))
                                return
                            }
                            jellyfin.conn = result
                            jellyfinKey.text = ""
                            if (what === "login") {
                                jellyfinSignPassword.text = ""
                                jellyfin.useKey = false
                                if (result.player?.error)
                                    jellyfin.playerStatus = Translation.tr("The player couldn't sign in: %1").arg(result.player.error)
                            }
                            jellyfin.status = result.server
                                ? Translation.tr("Connected to %1 as %2: %3 films, %4 series, %5 songs").arg(result.server)
                                    .arg(result.user).arg(result.movies ?? 0).arg(result.series ?? 0).arg(result.songs ?? 0)
                                : what === "forget" ? (result.signed_out ? Translation.tr("Signed out (its session ended on the server too).") : Translation.tr("Forgotten."))
                                : ""
                            if (what === "login" || what === "forget") Qt.callLater(() => jellyfin.run(["shim-status"]))
                            // Its player next (and the bubble's instant "play …" sees the change).
                            QuickIntent.refreshJellyfin()
                            if (what === "status") Qt.callLater(() => jellyfin.run(["shim-status"]))
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Jellyfin: your films, series and music, played fullscreen in mpv on this computer (or on Moonfin, the TV… when you name it). Sign in with your own Jellyfin account, no admin needed: Claude and the player each get their own login, and your password isn't kept. With two-factor authentication (e.g. the JellyfinSecurity plugin), use an app password made for this.")
                    }
                    ConfigTextArea {
                        id: jellyfinUrl
                        configKey: "ai.jellyfin.url"
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "dns"
                        text: Translation.tr("Jellyfin server")
                        placeholderText: Translation.tr("e.g. https://jellyfin.example.org")
                        value: Config.options.ai.jellyfin.url ?? ""
                        Connections {
                            target: jellyfinUrl.textArea
                            function onEditingFinished() {
                                Config.options.ai.jellyfin.url = jellyfinUrl.value.trim().replace(/\/+$/, "")
                            }
                        }
                    }
                    // The assistant's own sign-in: the user's token (and the player's).
                    StyledText {
                        Layout.fillWidth: true
                        visible: jellyfin.signedIn
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Claude is signed in as %1.").arg(jellyfin.conn.signed_in_as ?? "?")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !jellyfin.signedIn && !jellyfin.keyMode
                        spacing: 6
                        MaterialTextField {
                            id: jellyfinSignUser
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Username")
                            text: Config.options.ai.jellyfin.user ?? ""
                        }
                        MaterialTextField {
                            id: jellyfinSignPassword
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Password or app password")
                            echoMode: TextInput.Password
                            onAccepted: jellyfinSignIn.clicked()
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: !jellyfin.keyMode
                        spacing: 6
                        SmallButton {
                            id: jellyfinSignIn
                            visible: !jellyfin.signedIn
                            enabled: !jellyfin.busy && jellyfin.url !== "" && jellyfinSignUser.text.trim() !== ""
                                && jellyfinSignPassword.text !== ""
                            materialIcon: "login"
                            mainText: jellyfin.busy ? Translation.tr("Signing in…") : Translation.tr("Sign in")
                            onClicked: {
                                if (!jellyfinUrl.nixManaged) Config.options.ai.jellyfin.url = jellyfin.url
                                jellyfin.run(["credentials", "login", jellyfin.url, jellyfinSignUser.text.trim(), "--player"],
                                    jellyfinSignPassword.text)
                            }
                        }
                        SmallButton {
                            visible: jellyfin.signedIn
                            enabled: !jellyfin.busy && jellyfin.url !== ""
                            materialIcon: "network_check"
                            mainText: Translation.tr("Test")
                            onClicked: jellyfin.run(["credentials", "test", jellyfin.url], "")
                        }
                        SmallButton {
                            visible: jellyfin.signedIn
                            enabled: !jellyfin.busy
                            materialIcon: "logout"
                            mainText: Translation.tr("Sign out")
                            onClicked: jellyfin.run(["credentials", "forget"])
                        }
                        SmallButton {
                            visible: !jellyfin.signedIn
                            enabled: !jellyfin.busy
                            materialIcon: "key"
                            mainText: Translation.tr("Use an admin API key instead")
                            onClicked: jellyfin.useKey = true
                        }
                    }

                    // Or an admin's API key (Dashboard > API Keys), for a user
                    // picked by name.
                    StyledText {
                        Layout.fillWidth: true
                        visible: jellyfin.keyMode
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("An admin's API key (Jellyfin: Dashboard > API Keys) reaches every user's library: Claude then acts as the user named here.")
                    }
                    ConfigTextArea {
                        id: jellyfinUser
                        configKey: "ai.jellyfin.user"
                        shown: jellyfin.keyMode
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "person"
                        text: Translation.tr("Jellyfin user")
                        placeholderText: Translation.tr("empty: the first administrator")
                        value: Config.options.ai.jellyfin.user ?? ""
                        Connections {
                            target: jellyfinUser.textArea
                            function onEditingFinished() {
                                Config.options.ai.jellyfin.user = jellyfinUser.value.trim()
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: jellyfin.conn.key_source === "file"
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("API key: read from %1 (ai.jellyfin.apiKeyFile).").arg(Config.options.ai.jellyfin.apiKeyFile)
                    }
                    MaterialTextField {
                        id: jellyfinKey
                        Layout.fillWidth: true
                        visible: jellyfin.keyMode && jellyfin.conn.key_source !== "file"
                        placeholderText: jellyfin.conn.has_key
                            ? Translation.tr("API key (saved: leave empty to keep it)")
                            : Translation.tr("API key")
                        echoMode: TextInput.Password
                        onAccepted: jellyfinSave.clicked()
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: jellyfin.keyMode
                        spacing: 6
                        SmallButton {
                            id: jellyfinSave
                            enabled: !jellyfin.busy && jellyfin.url !== ""
                                && (jellyfinKey.text !== "" || jellyfin.conn.has_key === true)
                            materialIcon: "link"
                            mainText: jellyfin.busy ? Translation.tr("Checking…") : Translation.tr("Save and check")
                            onClicked: {
                                // The fields save when they lose focus, which a click may not take.
                                if (!jellyfinUrl.nixManaged) Config.options.ai.jellyfin.url = jellyfin.url
                                if (!jellyfinUser.nixManaged) Config.options.ai.jellyfin.user = jellyfinUser.value.trim()
                                jellyfin.run(["credentials", "save", jellyfin.url, jellyfinUser.value.trim()], jellyfinKey.text)
                            }
                        }
                        SmallButton {
                            enabled: !jellyfin.busy && jellyfin.url !== ""
                                && (jellyfinKey.text !== "" || jellyfin.conn.has_key === true)
                            materialIcon: "network_check"
                            mainText: Translation.tr("Test")
                            onClicked: jellyfin.run(["credentials", "test", jellyfin.url, jellyfinUser.value.trim()], jellyfinKey.text)
                        }
                        SmallButton {
                            visible: jellyfin.conn.key_source === "keyring"
                            enabled: !jellyfin.busy
                            materialIcon: "key_off"
                            mainText: Translation.tr("Forget the key")
                            onClicked: jellyfin.run(["credentials", "forget"])
                        }
                        SmallButton {
                            visible: jellyfin.useKey && jellyfin.conn.kind !== "apikey"
                            enabled: !jellyfin.busy
                            materialIcon: "login"
                            mainText: Translation.tr("Sign in with my account instead")
                            onClicked: jellyfin.useKey = false
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: jellyfin.status !== ""
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: jellyfin.status
                    }

                    // The player of this computer (jellyfin-mpv-shim).
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: jellyfin.player.signed_in
                            ? Translation.tr("Player (mpv on this computer): connected as %1, %2.").arg(jellyfin.player.user ?? "?")
                                .arg(jellyfin.player.service === "active" ? Translation.tr("running") : Translation.tr("not running"))
                            : Translation.tr("Connect the player (jellyfin-mpv-shim): sign in once with your Jellyfin username and password (an app password with two-factor authentication). The password isn't kept; the player keeps its own login, and saves progress and plays the next episode itself.")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !jellyfin.player.signed_in
                        spacing: 6
                        MaterialTextField {
                            id: jellyfinLogin
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Username")
                            text: Config.options.ai.jellyfin.user ?? ""
                        }
                        MaterialTextField {
                            id: jellyfinPassword
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Password")
                            echoMode: TextInput.Password
                            onAccepted: jellyfinConnect.clicked()
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        SmallButton {
                            id: jellyfinConnect
                            visible: !jellyfin.player.signed_in
                            enabled: !jellyfin.busy && jellyfin.url !== "" && jellyfinLogin.text.trim() !== ""
                            materialIcon: "cast"
                            mainText: jellyfin.busy ? Translation.tr("Connecting…") : Translation.tr("Connect the player")
                            onClicked: jellyfin.run(["shim-login", jellyfin.url, jellyfinLogin.text.trim()], jellyfinPassword.text)
                        }
                        SmallButton {
                            visible: jellyfin.player.signed_in === true
                            enabled: !jellyfin.busy
                            materialIcon: "cast_connected"
                            mainText: Translation.tr("Disconnect the player")
                            onClicked: jellyfin.run(["shim-logout"])
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: jellyfin.playerStatus !== ""
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: jellyfin.playerStatus
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

            // Wraps onto more lines on a narrow page (a RowLayout widened the page).
            Flow {
                Layout.fillWidth: true
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

            // Wraps onto more lines on a narrow page (a RowLayout widened the page).
            Flow {
                Layout.fillWidth: true
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

            // Wraps onto more lines on a narrow page (a RowLayout widened the page).
            Flow {
                Layout.fillWidth: true
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
