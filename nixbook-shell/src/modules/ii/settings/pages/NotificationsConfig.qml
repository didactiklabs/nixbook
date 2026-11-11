import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > Notifications: popups, cut-ins, keep on screen, quiet rules,
// duplicates and history (split out of the Bar page).
ContentPage {
    id: page
    forceWidth: true

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

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "notifications"
            shape: MaterialShape.Shape.Bun
            title: Translation.tr("Notifications")
            
            GroupedList {
                ConfigComboBox { // too much items for configselectionarray - I know it's not the best place to put this but I can change it later
                    configKey: "notifications.position";
                    enabled: !nixManaged;
                    text: Translation.tr("Popup position")
                    buttonIcon: "my_location" 
                    currentValue: Config.options.notifications.position
                    fieldWidth: 50
                    onSelected: newValue => {
                        Config.options.notifications.position = newValue;
                    }
                    model: [
                        {
                            displayName: Translation.tr("Top left"),
                            value: "top_left"
                        },
                        {
                            displayName: Translation.tr("Top center"),
                            value: "top_center"
                        },
                        {
                            displayName: Translation.tr("Top right"),
                            value: "top_right"
                        },
                        {
                            displayName: Translation.tr("Bottom left"),
                            value: "bottom_left"
                        },
                        {
                            displayName: Translation.tr("Bottom center"),
                            value: "bottom_center"
                        },
                        {
                            displayName: Translation.tr("Bottom right"),
                            value: "bottom_right"
                        }
                    ]
                }
                ConfigSwitch {
                    configKey: "bar.indicators.notifications.showUnreadCount";
                    enabled: !nixManaged;
                    buttonIcon: "counter_2"
                    text: Translation.tr("Unread indicator: show count")
                    checked: Config.options.bar.indicators.notifications.showUnreadCount
                    onCheckedChanged: { Config.options.bar.indicators.notifications.showUnreadCount = checked; }
                }
                ConfigSwitch {
                    configKey: "notifications.splitPopups";
                    enabled: !nixManaged;
                    buttonIcon: "splitscreen_bottom"
                    text: Translation.tr("Show each popup separately (don't group by app)")
                    checked: Config.options.notifications.splitPopups
                    onCheckedChanged: { Config.options.notifications.splitPopups = checked; }
                }
                ConfigSpinBox {
                    configKey: "notifications.timeout";
                    enabled: !nixManaged;
                    icon: "av_timer"
                    text: Translation.tr("Timeout duration (if not defined by notification) (ms)")
                    value: Config.options.notifications.timeout
                    from: 1000
                    to: 60000
                    stepSize: 1000
                    onValueChanged: {
                        Config.options.notifications.timeout = value;
                    }
                }
            }

            // Popups that stay longer (services/Notifications.qml
            // staysOnScreen, popupLifetime).
            ContentSubsection {
                title: Translation.tr("Keep on screen")
                GroupedList {
                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        text: Translation.tr("Popups from these apps, or whose app name or title contains one of the keywords, stay longer than the others, for the time set below (0: until you dismiss them). They stay in the notification centre after that, where you can still reply.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    ConfigSwitch {
                        configKey: "notifications.persistent.enable"
                        buttonIcon: "push_pin"
                        text: Translation.tr("Keep matching popups on screen longer")
                        checked: Config.options.notifications.persistent.enable
                        onCheckedChanged: Config.options.notifications.persistent.enable = checked
                    }
                    ConfigSpinBox {
                        configKey: "notifications.persistent.timeout"
                        enabled: !nixManaged && Config.options.notifications.persistent.enable
                        icon: "av_timer"
                        text: Translation.tr("How long they stay (ms, 0: until dismissed)")
                        value: Config.options.notifications.persistent.timeout
                        from: 0
                        to: 600000
                        stepSize: 5000
                        onValueChanged: Config.options.notifications.persistent.timeout = value
                    }
                    NotificationRuleEditor {
                        Layout.fillWidth: true
                        enabled: Config.options.notifications.persistent.enable
                        opacity: enabled ? 1 : 0.5
                        ruleKey: "persistent"
                        keywordsLabel: Translation.tr("App or title containing")
                        keywordsPlaceholder: Translation.tr("comma-separated, e.g. Discord, Slack, WhatsApp")
                    }
                }
            }

            // Quiet notifications (services/Notifications.qml quietRule).
            ContentSubsection {
                title: Translation.tr("Quiet")
                GroupedList {
                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        text: Translation.tr("Notifications from these apps, or matching one of the rules (same syntax as the Persona cut-in rules below), don't pop up, cut in or chime: they only go to the notification centre and the history. For copies you already get elsewhere, e.g. the phone's calendar reminders now that the shell shows them.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    ConfigSwitch {
                        configKey: "notifications.quiet.enable"
                        buttonIcon: "notifications_off"
                        text: Translation.tr("Keep matching notifications quiet")
                        checked: Config.options.notifications.quiet.enable
                        onCheckedChanged: Config.options.notifications.quiet.enable = checked
                    }
                    NotificationRuleEditor {
                        Layout.fillWidth: true
                        enabled: Config.options.notifications.quiet.enable
                        opacity: enabled ? 1 : 0.5
                        ruleKey: "quiet"
                        keywordsLabel: Translation.tr("For notifications matching")
                        keywordsPlaceholder: Translation.tr("comma-separated rules, e.g. app:KDE Connect + title:^\"Calendar\"")
                    }
                }
            }

            // Duplicate filter (services/Notifications.qml duplicateVerdict).
            ContentSubsection {
                title: Translation.tr("Duplicates")
                GroupedList {
                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        text: Translation.tr("A message shown by a desktop app and mirrored from your phone (%1) appears once, from the desktop app, whichever copy arrives first. The phone's copy must end with the same message and mention the same sender or channel; when it also brings newer messages, or names the sender the desktop one lacks (Instagram in the browser), it replaces the desktop one, so a conversation shows once.").arg((Config.options.notifications.deduplicate.relayApps ?? []).join(", "))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    ConfigSwitch {
                        configKey: "notifications.deduplicate.enable"
                        buttonIcon: "filter_none"
                        text: Translation.tr("Hide duplicate notifications")
                        checked: Config.options.notifications.deduplicate.enable
                        onCheckedChanged: Config.options.notifications.deduplicate.enable = checked
                    }
                    ConfigSpinBox {
                        configKey: "notifications.deduplicate.window"
                        enabled: Config.options.notifications.deduplicate.enable
                        icon: "timer"
                        text: Translation.tr("Max delay between the two copies (s)")
                        value: Config.options.notifications.deduplicate.window
                        from: 5
                        to: 3600
                        stepSize: 60
                        onValueChanged: Config.options.notifications.deduplicate.window = value
                    }
                    ConfigSwitch {
                        configKey: "notifications.deduplicate.history"
                        enabled: Config.options.notifications.deduplicate.enable
                        buttonIcon: "history"
                        text: Translation.tr("Keep one history entry per message")
                        checked: Config.options.notifications.deduplicate.history
                        onCheckedChanged: Config.options.notifications.deduplicate.history = checked
                    }
                    ConfigSwitch {
                        configKey: "notifications.deduplicate.hideOwnMessages"
                        enabled: Config.options.notifications.deduplicate.enable
                        buttonIcon: "reply"
                        text: Translation.tr("Hide your own replies mirrored from the phone (\"You:\")")
                        checked: Config.options.notifications.deduplicate.hideOwnMessages
                        onCheckedChanged: Config.options.notifications.deduplicate.hideOwnMessages = checked
                    }
                }
            }

            // Log of every notification, kept after it is dismissed
            // (services/NotificationHistory.qml; sidebar → history button).
            ContentSubsection {
                id: historySection
                title: Translation.tr("History")
                property bool confirmClear: false
                Timer {
                    id: historyConfirmTimer
                    interval: 3000
                    onTriggered: historySection.confirmClear = false
                }

                GroupedList {
                    ConfigSwitch {
                        configKey: "notifications.history.enable"
                        buttonIcon: "history"
                        text: Translation.tr("Keep a notification history")
                        checked: Config.options.notifications.history.enable
                        onCheckedChanged: Config.options.notifications.history.enable = checked
                    }
                    ConfigSpinBox {
                        configKey: "notifications.history.retentionDays"
                        enabled: Config.options.notifications.history.enable
                        icon: "auto_delete"
                        text: Translation.tr("Keep for (days, 0 = forever)")
                        value: Config.options.notifications.history.retentionDays
                        from: 0
                        to: 3650
                        stepSize: 1
                        onValueChanged: Config.options.notifications.history.retentionDays = value
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.topMargin: 4
                        text: Translation.tr("%1 notifications in history").arg(NotificationHistory.entries.length)
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        spacing: 6
                        Repeater {
                            model: [7, 30]
                            delegate: RippleButtonWithIcon {
                                required property int modelData
                                readonly property int count: NotificationHistory.countOlderThan(modelData)
                                enabled: count > 0
                                materialIcon: "auto_delete"
                                mainText: Translation.tr("Older than %1 days (%2)").arg(modelData).arg(count)
                                onClicked: NotificationHistory.deleteOlderThan(modelData)
                            }
                        }
                        RippleButtonWithIcon {
                            enabled: NotificationHistory.entries.length > 0
                            materialIcon: "delete_forever"
                            mainText: historySection.confirmClear ? Translation.tr("Click again to delete all") : Translation.tr("Delete all")
                            onClicked: {
                                if (!historySection.confirmClear) {
                                    historySection.confirmClear = true;
                                    historyConfirmTimer.restart();
                                    return;
                                }
                                historySection.confirmClear = false;
                                NotificationHistory.clear();
                            }
                        }
                    }
                }
            }

            // Which notifications get the theme's cut-in: the full-screen
            // Persona one (PersonaCutIn.qml), the Chiikawa speech bubble
            // (ChiikawaAlert.qml), the Cyberpunk holocall (CyberpunkCutIn.qml) or
            // the Ghibli card on the wind (GhibliCutIn.qml).
            ContentSubsection {
                id: cutInSection
                title: Translation.tr("Cut-ins (important notifications)")
                readonly property bool themeHasCutIn: Persona.shapes || Chiikawa.enabled || Cyberpunk.enabled || Ghibli.enabled
                readonly property var rules: Config.options.notifications.cutIn

                GroupedList {
                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        text: Translation.tr("In the Persona theme matching notifications take over the screen like an in-game dialogue; in the Chiikawa theme the character pops up with them in a speech bubble; in the Cyberpunk 2077 theme they glitch in as an incoming holocall; in the Studio Ghibli theme they drift in on the wind as a frosted-glass card with the spirit. An app marks a notification critical itself (e.g. low battery, incoming calls, notify-send -u critical); critical ones show a \"!\" in the notification centre. Most chat apps send normal notifications — pick them below to get cut-ins for them too. Rules also match the message text and hints.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    ConfigSwitch {
                        configKey: "notifications.cutIn.enable"
                        buttonIcon: "theater_comedy"
                        text: Translation.tr("Show cut-ins")
                        checked: cutInSection.rules.enable
                        onCheckedChanged: Config.options.notifications.cutIn.enable = checked
                    }
                    ConfigSwitch {
                        configKey: "notifications.cutIn.critical"
                        enabled: cutInSection.rules.enable
                        buttonIcon: "priority_high"
                        text: Translation.tr("For critical notifications")
                        checked: cutInSection.rules.critical
                        onCheckedChanged: Config.options.notifications.cutIn.critical = checked
                    }
                    ConfigSwitch {
                        configKey: "notifications.cutIn.sound"
                        enabled: cutInSection.rules.enable
                        buttonIcon: "music_note"
                        text: Translation.tr("Play the theme's sound (Persona 5 cut-in, the Chiikawa jingle, the Cyberpunk alert, Totoro's roar…)")
                        checked: cutInSection.rules.sound
                        onCheckedChanged: Config.options.notifications.cutIn.sound = checked
                    }
                    ConfigSwitch {
                        configKey: "notifications.cutIn.mergeUpdates"
                        enabled: cutInSection.rules.enable
                        buttonIcon: "forum"
                        text: Translation.tr("Update the cut-in on screen when its chat gets a new message")
                        checked: cutInSection.rules.mergeUpdates
                        onCheckedChanged: Config.options.notifications.cutIn.mergeUpdates = checked
                    }
                    ConfigSpinBox {
                        configKey: "notifications.cutIn.cooldown"
                        enabled: cutInSection.rules.enable
                        icon: "timer"
                        text: Translation.tr("After a cut-in, show the next ones as regular popups for (s, 0 = off)")
                        value: cutInSection.rules.cooldown
                        from: 0
                        to: 300
                        stepSize: 5
                        onValueChanged: Config.options.notifications.cutIn.cooldown = value
                    }
                    NotificationRuleEditor {
                        Layout.fillWidth: true
                        enabled: cutInSection.rules.enable
                        opacity: enabled ? 1 : 0.5
                        ruleKey: "cutIn"
                        keywordsLabel: Translation.tr("For notifications matching")
                        keywordsPlaceholder: Translation.tr("comma-separated rules, e.g. call, Victor + Instagram, app:Signal")
                        blacklistLabel: Translation.tr("Never for notifications matching")
                        blacklistPlaceholder: Translation.tr("comma-separated rules, e.g. newsletter, app:Instagram + !Victor")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        textFormat: Text.StyledText
                        text: Translation.tr("<b>Rules</b> — each comma-separated rule is checked on its own. Join terms with <b>+</b> to require all of them (<i>Victor + Instagram</i> needs both). <b>!</b> means absent (<i>Victor + !newsletter</i>). <b>app:</b>, <b>title:</b>, <b>body:</b> or <b>hint:</b> look in one field only (<i>app:Instagram + Victor</i>). Quotes match a whole word (<i>\"Diệu\"</i>), <b>^</b> the start of the field (<i>last:^You:</i>: the last chat message is mine). <b>last:</b> is the last message of a chat thread, with its sender; <b>line:</b> its last line (<i>line:Liked your message</i>). Case is ignored. Blacklist rules win over everything, critical included.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    CutInRuleTester {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        enabled: cutInSection.rules.enable
                        opacity: enabled ? 1 : 0.5
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            visible: !cutInSection.themeHasCutIn
                            text: Translation.tr("Needs the Persona, Chiikawa, Cyberpunk 2077 or Studio Ghibli theme (Appearance → Theme).")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                        Item { Layout.fillWidth: true; visible: cutInSection.themeHasCutIn }
                        RippleButtonWithIcon {
                            materialIcon: "visibility"
                            mainText: Translation.tr("Preview")
                            enabled: cutInSection.themeHasCutIn && cutInSection.rules.enable
                            onClicked: GlobalStates.personaCutInPreview += 1
                        }
                    }
                }
            }
        }
    }
}
