import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

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

    property var allWidgets: [
        { id: "leftSidebarButton", name: Translation.tr("Left Sidebar Button"),  icon: "left_panel_open" },
        { id: "workspaces",        name: Translation.tr("Workspaces"),           icon: "steppers" },
        { id: "weatherBar",        name: Translation.tr("Weather"),              icon: "flare" },
        { id: "media",             name: Translation.tr("Media"),                icon: "music_note" },
        { id: "resources",         name: Translation.tr("Resources"),            icon: "empty_dashboard" },
        { id: "systemIcons",       name: Translation.tr("System Icons"),         icon: "info" },
        { id: "networkSpeed",      name: Translation.tr("Network Speed"),        icon: "network_check" },
        { id: "clockWidget",       name: Translation.tr("Clock"),                icon: "schedule" },
        { id: "nextEvent",         name: Translation.tr("Next Event"),           icon: "event_upcoming" },
        { id: "utilButtons",       name: Translation.tr("Util Buttons"),         icon: "toggle_on" },
        { id: "sysTray",           name: Translation.tr("Tray"),                 icon: "inbox" },
        { id: "batteryIndicator",  name: Translation.tr("Battery"),              icon: "battery_android_frame_full" },
        { id: "bluetooth",         name: Translation.tr("Bluetooth"),            icon: "bluetooth" },
        { id: "activeWindow",      name: Translation.tr("Active Window"),        icon: "subtitles" },
        { id: "powerButton",       name: Translation.tr("Power Button"),         icon: "power_settings_new" },
        { id: "updatesCount",      name: Translation.tr("Updates"),              icon: "deployed_code_update" },
        { id: "vpnStatus",         name: Translation.tr("VPN"),                   icon: "vpn_lock" },
        { id: "anthropicUsage",    name: Translation.tr("Claude Usage"),          icon: "data_usage" },
        { id: "desktopControl",    name: Translation.tr("Desktop Control"),       icon: "smart_toy" },
        { id: "musicRecognition",  name: Translation.tr("Music Recognition"),     icon: "music_cast" },
        { id: "kdeConnect",        name: Translation.tr("Phone Connect"),         icon: "devices" },
        { id: "docktoPanel",       name: Translation.tr("Dock to Panel"),        icon: "apps" },
        { id: "visualizer",        name: Translation.tr("Visualizer"),           icon: "graphic_eq" },
        { id: "keyboardLayoutIndicator", name: Translation.tr("Keyboard Layout"), icon: "keyboard" },
        { id: "divisor",            name: Translation.tr("Divider"),             icon: "horizontal_distribute" },
        { id: "launcherButton",     name: Translation.tr("Launcher Button"),     icon: "search" },
        { id: "dynamicIsland",     name: Translation.tr("Dynamic Island"),     icon: "nest_wifi_pro" },
    ]

    function availableFor(section) {
        let used = [
            ...Config.options.bar.layouts.leftLayout,
            ...Config.options.bar.layouts.middleLayout,
            ...Config.options.bar.layouts.rightLayout
        ]
        if (section === "middle" && Config.options.bar.layouts.middleLayout.length > 0) {
            return Config.options.bar.layouts.middleLayout.includes("dynamicIsland") ? [] : allWidgets.filter(w => {
                if (w.id === "dynamicIsland") return false
                if (w.id === "divisor" && Config.options.bar.borderless !== "transparent") return false
                const multipleAllowed = ["visualizer", "divisor"]
                return !used.includes(w.id) || multipleAllowed.includes(w.id)
            })
        }
        const multipleAllowed = ["visualizer", "divisor"]
        return allWidgets.filter(w => {
            if (w.id === "divisor" && Config.options.bar.borderless !== "transparent") return false
            if (w.id === "dynamicIsland" && (Config.options.bar.vertical || section !== "middle")) return false
            return !used.includes(w.id) || multipleAllowed.includes(w.id)
        })
    }

    function getWidgetName(id) {
        const w = allWidgets.find(w => w.id === id)
        return w ? w.name : id
    }

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "monitor"
            shape: MaterialShape.Shape.ClamShell
            shown: Quickshell.screens.length > 1
            title: Translation.tr("Screens")
            ContentSubsection {
                title: Translation.tr("Show bar on")

                ColumnLayout {
                    id: monitorsCol
                    Layout.fillWidth: true
                    spacing: 2

                    Rectangle {
                        id: allRow
                        Layout.fillWidth: true
                        implicitHeight: allSwitchItem.implicitHeight + 16 + 8
                        color: Appearance.colors.colLayer1
                        topLeftRadius: Appearance.rounding.normal
                        topRightRadius: Appearance.rounding.normal
                        bottomLeftRadius: Appearance.rounding.unsharpenmore
                        bottomRightRadius: Appearance.rounding.unsharpenmore

                        ConfigSwitch {
                            configKey: "bar.screenList";
                            enabled: !nixManaged;
                            id: allSwitchItem
                            anchors { fill: parent; margins: 8 }
                            buttonIcon: "tv_displays"
                            text: Translation.tr("All")
                            onCheckedChanged: {
                                if (checked) Config.options.bar.screenList = []
                            }

                            Binding {
                                target: allSwitchItem
                                property: "checked"
                                value: Config.options.bar.screenList.length === 0
                                restoreMode: Binding.RestoreBinding
                            }
                        }
                    }

                    Repeater {
                        model: Quickshell.screens
                        delegate: Rectangle {
                            id: monitorRow
                            required property var modelData
                            required property int index
                            readonly property bool isLast: index === Quickshell.screens.length - 1

                            Layout.fillWidth: true
                            implicitHeight: switchItem.implicitHeight + 16 + 8
                            color: Appearance.colors.colLayer1
                            topLeftRadius:     Appearance.rounding.unsharpenmore
                            topRightRadius:    Appearance.rounding.unsharpenmore
                            bottomLeftRadius:  isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                            bottomRightRadius: isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore

                            ConfigSwitch {
                                configKey: "bar.screenList";
                                enabled: !nixManaged;
                                id: switchItem
                                anchors { fill: parent; margins: 8 }
                                buttonIcon: "monitor"
                                text: monitorRow.modelData.name
                                onCheckedChanged: {
                                    const allNames = Quickshell.screens.map(m => m.name)
                                    let list = Config.options.bar.screenList.length === 0 ? allNames.slice() : Config.options.bar.screenList.slice()
                                    if (checked) {
                                        if (!list.includes(monitorRow.modelData.name)) list.push(monitorRow.modelData.name)
                                    } else {
                                        list = list.filter(s => s !== monitorRow.modelData.name)
                                    }
                                    Config.options.bar.screenList = list.length === allNames.length ? [] : list
                                }

                                Binding {
                                    target: switchItem
                                    property: "checked"
                                    value: Config.options.bar.screenList.length === 0 || Config.options.bar.screenList.includes(monitorRow.modelData.name)
                                    restoreMode: Binding.RestoreBinding
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "splitscreen_add"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Bar layout")

            GroupedList {
                LayoutSection {
                    sectionTitle: Config.options.bar.vertical ? Translation.tr("Top") : Translation.tr("Left")
                    layout: Config.options.bar.layouts.leftLayout
                    configKey: "bar.layouts.leftLayout"
                    availableWidgets: page.availableFor("left")
                    getWidgetName: page.getWidgetName
                    onUpdate: list => Config.options.bar.layouts.leftLayout = list
                }

                LayoutSection {
                    sectionTitle: Translation.tr("Center")
                    layout: Config.options.bar.layouts.middleLayout
                    configKey: "bar.layouts.middleLayout"
                    availableWidgets: page.availableFor("middle")
                    getWidgetName: page.getWidgetName
                    onUpdate: list => Config.options.bar.layouts.middleLayout = list
                }

                LayoutSection {
                    sectionTitle: Config.options.bar.vertical ? Translation.tr("Bottom") : Translation.tr("Right")
                    layout: Config.options.bar.layouts.rightLayout
                    configKey: "bar.layouts.rightLayout"
                    availableWidgets: page.availableFor("right")
                    getWidgetName: page.getWidgetName
                    onUpdate: list => Config.options.bar.layouts.rightLayout = list
                }
            }
        }

        ContentSection {
            icon: "pivot_table_chart"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Positioning & Styles")
            GroupedList {
                ConfigSelectionArray {
                    configKey: "bar.bottom";
                    enabled: !nixManaged;
                    text: Translation.tr("Bar position")
                    icon: "swap_vert"
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        { displayName: Translation.tr("Top"),    icon: "arrow_upward",   value: 0 },
                        { displayName: Translation.tr("Left"),   icon: "arrow_back",     value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"),  icon: "arrow_forward",  value: 3 }
                    ]
                }
                ConfigSelectionArray {
                    configKey: "bar.cornerStyle";
                    enabled: !nixManaged;
                    text: Translation.tr("Bar style")
                    icon: "style"
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                    options: [
                        { displayName: Translation.tr("Hug"),     icon: "line_curve", value: 0 },
                        { displayName: Translation.tr("Float"),   icon: "view_day",   value: 1 },
                        { displayName: Translation.tr("Islands"), icon: "crop_3_2",   value: 2 },
                        { displayName: Translation.tr("M3"), icon: "interests",   value: 3 },
                        { displayName: Translation.tr("Panel"), icon: "toolbar",   value: 4 }
                    ]
                }
                ConfigSelectionArray {
                    configKey: "bar.borderless";
                    enabled: !nixManaged;
                    text: Translation.tr("Group style")
                    icon: "tab_group"
                    currentValue: Config.options.bar.borderless
                    onSelected: newValue => { Config.options.bar.borderless = newValue; }
                    options: [
                        { displayName: Translation.tr(""),          icon: "block",          value: "transparent" },
                        { displayName: Translation.tr("Pills"),     icon: "pill",           value: "pills" },
                        { displayName: Translation.tr("Separated"), icon: "view_column_2",  value: "separated" },
                        { displayName: Translation.tr("Segmented"), icon: "tablet",           value: "segmented" },
                    ]
                }
                ColorSelectionArray {
                    configKey: "bar.groupColor";
                    enabled: !nixManaged;
                    icon: "brush"
                    text: Translation.tr("Group Color")
                    options: ["primaryContainer", "secondaryContainer", "tertiaryContainer", "layer1", "layer0"]
                    currentValue: Config.options.bar.groupColor
                    onSelected: newValue => {
                        Config.options.bar.groupColor = newValue
                    }
                }
                ConfigRow{
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.showBackground";
                        buttonIcon: "variable_insert"
                        text: Translation.tr("Show Background")
                        enabled: (Config.options.bar.cornerStyle === 0 || Config.options.bar.cornerStyle === 1) && !nixManaged
                        checked: Config.options.bar.showBackground
                        onCheckedChanged: { Config.options.bar.showBackground = checked; }
                    }
                    ConfigSelectionArray {
                        configKey: "bar.autoHide.enable";
                        enabled: !nixManaged;
                        text: Translation.tr("Autohide")
                        icon: "preview_off"
                        currentValue: Config.options.bar.autoHide.enable
                        onSelected: newValue => { Config.options.bar.autoHide.enable = newValue; }
                        options: [
                            { displayName: Translation.tr("No"),  icon: "close", value: false },
                            { displayName: Translation.tr("Yes"), icon: "check", value: true }
                        ]
                    }
                }
                ConfigSwitch {
                    configKey: "bar.centerOnlyReserveFrame";
                    buttonIcon: "expand"
                    enabled: (Config.options.bar.showFrame) && !nixManaged
                    text: Translation.tr("Overlap windows when center-only")
                    checked: Config.options.bar.centerOnlyReserveFrame
                    onCheckedChanged: { Config.options.bar.centerOnlyReserveFrame = checked; }
                }
                ConfigRow {
                    ConfigSwitch {
                        configKey: "bar.showFrame";
                        enabled: !nixManaged;
                        buttonIcon: "panorama_wide_angle"
                        text: Translation.tr("Show Frame")
                        checked: Config.options.bar.showFrame

                        property bool switchReady: false
                        Component.onCompleted: Qt.callLater(() => switchReady = true)

                        onCheckedChanged: {
                            if (switchReady && checked) {
                                GlobalStates.refreshBar();
                            }
                            Config.options.bar.showFrame = checked;
                        }
                    }
                    ConfigSwitch {
                        configKey: "bar.followFrameColor";
                        buttonIcon: "colors"
                        enabled: (Config.options.bar.showFrame) && !nixManaged
                        text: Translation.tr("Follow Frame Color")
                        checked: Config.options.bar.followFrameColor
                        onCheckedChanged: { Config.options.bar.followFrameColor = checked; }
                    }
                }
                ConfigSpinBox {
                    configKey: "bar.frameThickness";
                    enabled: !nixManaged;
                    icon: "eraser_size_1"
                    text: Translation.tr("Frame thickness")
                    value: Config.options.bar.frameThickness
                    from: 2
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.bar.frameThickness = value;
                    }
                }
                ColorSelectionArray {
                    configKey: "bar.frameColor";
                    enabled: !nixManaged;
                    icon: "imagesearch_roller"
                    text: Translation.tr("Frame Color")
                    options: ["primaryContainer", "secondaryContainer", "tertiaryContainer", "layer0", "black"] // sorry only solid colors transparency looks bad
                    currentValue: Config.options.bar.frameColor
                    onSelected: newValue => {
                        Config.options.bar.frameColor = newValue
                    }
                }
            }
        }

        ContentSection {
            icon: "nest_wifi_pro"
            shape: MaterialShape.Shape.Cookie4Sided
            title: Translation.tr("Dynamic Island")

            GroupedList {
                ConfigSelectionArray {
                    configKey: "bar.dynamicIsland.leftWidget";
                    enabled: !nixManaged;
                    text: Translation.tr("Left widget")
                    icon: "right_panel_open"
                    currentValue: Config.options.bar.dynamicIsland.leftWidget
                    onSelected: newValue => { Config.options.bar.dynamicIsland.leftWidget = newValue; }
                    options: [
                        { displayName: Translation.tr(""),    icon: "block",        value: "none" },
                        { displayName: Translation.tr("Clock"),   icon: "schedule",     value: "clockWidget" },
                        { displayName: Translation.tr("Weather"), icon: "partly_cloudy_day", value: "weatherBar" },
                        { displayName: Translation.tr("Updates"), icon: "update",       value: "updatesCount" }
                    ]
                }
                ConfigSelectionArray {
                    configKey: "bar.dynamicIsland.rightWidget";
                    enabled: !nixManaged;
                    text: Translation.tr("Right widget")
                    icon: "left_panel_open"
                    currentValue: Config.options.bar.dynamicIsland.rightWidget
                    onSelected: newValue => { Config.options.bar.dynamicIsland.rightWidget = newValue; }
                    options: [
                        { displayName: Translation.tr(""),         icon: "block",        value: "none" },
                        { displayName: Translation.tr("System icons"), icon: "settings",     value: "systemIcons" },
                        { displayName: Translation.tr("Tray"),  icon: "apps",         value: "sysTray" },
                        { displayName: Translation.tr("Util buttons"), icon: "widgets",   value: "utilButtons" }
                    ]
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: Translation.tr("Media")
                GroupedList {
                    ConfigSelectionArray {
                        configKey: "bar.dynamicIsland.visualizerStyle";
                        enabled: !nixManaged;
                        text: Translation.tr("Visualizer style")
                        icon: "graphic_eq"
                        currentValue: Config.options.bar.dynamicIsland.visualizerStyle
                        onSelected: newValue => { Config.options.bar.dynamicIsland.visualizerStyle = newValue; }
                        options: [
                            { displayName: Translation.tr(""),      icon: "block",       value: "none" },
                            { displayName: Translation.tr("Dots"),  icon: "steppers",     value: "dots" },
                            { displayName: Translation.tr("Wave"),  icon: "ssid_chart",   value: "wave" }
                        ]
                    }
                    ConfigSwitch {
                        configKey: "bar.dynamicIsland.showMediaControls";
                        enabled: !nixManaged;
                        buttonIcon: "play_circle"
                        text: Translation.tr("Show media controls")
                        checked: Config.options.bar.dynamicIsland.showMediaControls
                        onCheckedChanged: { Config.options.bar.dynamicIsland.showMediaControls = checked; }
                    }
                }
            }
        }

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

            // Popups that stay until dismissed (services/Notifications.qml
            // staysOnScreen).
            ContentSubsection {
                title: Translation.tr("Keep on screen")
                GroupedList {
                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        wrapMode: Text.Wrap
                        text: Translation.tr("Popups from these apps, or whose app name or title contains one of the keywords, stay until you dismiss them instead of timing out — for messages from people. The message text itself is not matched.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    ConfigSwitch {
                        configKey: "notifications.persistent.enable"
                        buttonIcon: "push_pin"
                        text: Translation.tr("Keep matching popups on screen")
                        checked: Config.options.notifications.persistent.enable
                        onCheckedChanged: Config.options.notifications.persistent.enable = checked
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
                        text: Translation.tr("Notifications from these apps, or matching one of the rules (same syntax as the Persona cut-in rules below), don't pop up, cut in or chime: they only go to the notification centre and the history. For copies you already get elsewhere, e.g. the phone's calendar reminders now that DankCalendar shows them.")
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
                        text: Translation.tr("A message shown by a desktop app and mirrored from your phone (%1) appears once, from the desktop app, whichever copy arrives first. The phone's copy must end with the same message and mention the same sender or channel; when it also brings newer messages, it replaces the desktop one, so a conversation shows once.").arg((Config.options.notifications.deduplicate.relayApps ?? []).join(", "))
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
                        text: Translation.tr("In the Persona theme matching notifications take over the screen like an in-game dialogue; in the Chiikawa theme the character pops up with them in a speech bubble; in the Cyberpunk 2077 theme they glitch in as an incoming holocall; in the Studio Ghibli theme they drift in on the wind as a painted card with the spirit. An app marks a notification critical itself (e.g. low battery, incoming calls, notify-send -u critical); critical ones show a \"!\" in the notification centre. Most chat apps send normal notifications — pick them below to get cut-ins for them too. Rules also match the message text and hints.")
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
                        text: Translation.tr("Play the theme's sound (Persona 5 cut-in, the Chiikawa jingle, the Relic glitch, Totoro's roar…)")
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

        ContentSection {
            shape: MaterialShape.Shape.Square
            icon: "inbox_customize"
            title: Translation.tr("Tray")
            GroupedList {
                ConfigSwitch {
                    configKey: "tray.invertPinnedItems";
                    enabled: !nixManaged;
                    buttonIcon: "keep"; text: Translation.tr("Make icons pinned by default")
                    checked: Config.options.tray.invertPinnedItems
                    onCheckedChanged: { Config.options.tray.invertPinnedItems = checked; }
                }
                ConfigSwitch {
                    configKey: "tray.monochromeIcons";
                    enabled: !nixManaged;
                    buttonIcon: "colors"; text: Translation.tr("Tint icons")
                    checked: Config.options.tray.monochromeIcons
                    onCheckedChanged: { Config.options.tray.monochromeIcons = checked; }
                }
            }
        }

        ContentSection {
            icon: "vertical_align_center"
            shape: MaterialShape.Shape.Diamond
            title: Translation.tr("Divider")

            GroupedList {
                ConfigSelectionArray {
                    configKey: "bar.divider.style";
                    enabled: !nixManaged;
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.bar.divider.style
                    onSelected: newValue => { Config.options.bar.divider.style = newValue; }
                    options: [
                        { displayName: Translation.tr("Line"),  icon: "more_vert",       value: "rect" },
                        { displayName: Translation.tr("Dot"),   icon: "fiber_manual_record", value: "dot" },
                        { displayName: Translation.tr("Space"), icon: "space_bar",       value: "space" }
                    ]
                }
                ConfigSpinBox {
                    configKey: "bar.divider.spacing";
                    icon: "width"
                    enabled: (Config.options.bar.divider.style === "space") && !nixManaged
                    text: Translation.tr("Space width (px)")
                    value: Config.options.bar.divider.spacing
                    from: 4
                    to: 400
                    stepSize: 2
                    onValueChanged: {
                        Config.options.bar.divider.spacing = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "buttons_alt"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Utility buttons")

            GroupedList {
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showScreenSnip";
                        enabled: !nixManaged;
                        buttonIcon: "screenshot_region"
                        text: Translation.tr("Screen snip")
                        checked: Config.options.bar.utilButtons.showScreenSnip
                        onCheckedChanged: { Config.options.bar.utilButtons.showScreenSnip = checked }
                    }
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showColorPicker";
                        enabled: !nixManaged;
                        buttonIcon: "colorize"
                        text: Translation.tr("Color picker")
                        checked: Config.options.bar.utilButtons.showColorPicker
                        onCheckedChanged: { Config.options.bar.utilButtons.showColorPicker = checked }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showKeyboardToggle";
                        enabled: !nixManaged;
                        buttonIcon: "keyboard"
                        text: Translation.tr("Keyboard toggle")
                        checked: Config.options.bar.utilButtons.showKeyboardToggle
                        onCheckedChanged: { Config.options.bar.utilButtons.showKeyboardToggle = checked }
                    }
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showMicToggle";
                        enabled: !nixManaged;
                        buttonIcon: "mic"
                        text: Translation.tr("Mic toggle")
                        checked: Config.options.bar.utilButtons.showMicToggle
                        onCheckedChanged: { Config.options.bar.utilButtons.showMicToggle = checked }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showDarkModeToggle";
                        enabled: !nixManaged;
                        buttonIcon: "dark_mode"
                        text: Translation.tr("Dark/Light toggle")
                        checked: Config.options.bar.utilButtons.showDarkModeToggle
                        onCheckedChanged: { Config.options.bar.utilButtons.showDarkModeToggle = checked }
                    }
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showPerformanceProfileToggle";
                        enabled: !nixManaged;
                        buttonIcon: "speed"
                        text: Translation.tr("Performance Profile")
                        checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                        onCheckedChanged: { Config.options.bar.utilButtons.showPerformanceProfileToggle = checked }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showScreenRecord";
                        enabled: !nixManaged;
                        buttonIcon: "screen_record"
                        text: Translation.tr("Record Screen")
                        checked: Config.options.bar.utilButtons.showScreenRecord
                        onCheckedChanged: { Config.options.bar.utilButtons.showScreenRecord = checked }
                    }
                    ConfigSwitch {
                        configKey: "bar.utilButtons.showWallpaperToggle";
                        enabled: !nixManaged;
                        buttonIcon: "imagesmode"
                        text: Translation.tr("Wallpapers Toggle")
                        checked: Config.options.bar.utilButtons.showWallpaperToggle
                        onCheckedChanged: { Config.options.bar.utilButtons.showWallpaperToggle = checked }
                    }
                }
            }
        }

        ContentSection {
            shape: MaterialShape.Shape.Cookie12Sided
            icon: "steppers"; title: Translation.tr("Workspaces")
            GroupedList {
                ConfigSwitch {
                    configKey: "bar.workspaces.alwaysShowNumbers";
                    enabled: !nixManaged;
                    buttonIcon: "counter_1"; text: Translation.tr("Always show numbers")
                    checked: Config.options.bar.workspaces.alwaysShowNumbers
                    onCheckedChanged: { Config.options.bar.workspaces.alwaysShowNumbers = checked; }
                }
                ConfigSelectionArray {
                    configKey: "bar.workspaces.numberMap";
                    enabled: !nixManaged;
                    text: Translation.tr("Numbers style")
                    icon: "looks_3"
                    currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                    onSelected: newValue => {
                        Config.options.bar.workspaces.numberMap = JSON.parse(newValue)
                    }
                    options: [
                        { displayName: Translation.tr("Normal"),    icon: "timer_10",        value: '[]' },
                        { displayName: Translation.tr("Han chars"), icon: "glyphs",          value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]' },
                        { displayName: Translation.tr("Roman"),     icon: "account_balance", value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]' }
                    ]
                }
                ConfigSwitch {
                    configKey: "bar.workspaces.showAppIcons";
                    enabled: !nixManaged;
                    buttonIcon: "award_star"; text: Translation.tr("Show app icons")
                    checked: Config.options.bar.workspaces.showAppIcons
                    onCheckedChanged: { Config.options.bar.workspaces.showAppIcons = checked; }
                }
                ConfigSpinBox {
                    configKey: "bar.workspaces.shown";
                    enabled: !nixManaged;
                    icon: "view_column"; text: Translation.tr("Workspaces shown")
                    value: Config.options.bar.workspaces.shown
                    from: 1; to: 30
                    onValueChanged: { Config.options.bar.workspaces.shown = value; }
                }
                ConfigSelectionArray {
                    configKey: "bar.workspaces.indicatorStyle";
                    enabled: !nixManaged;
                    text: Translation.tr("Indicator style")
                    icon: "page_control"
                    currentValue: Config.options.bar.workspaces.indicatorStyle ?? "icon"
                    onSelected: newValue => {
                        Config.options.bar.workspaces.indicatorStyle = newValue
                    }
                    options: [
                        { displayName: Translation.tr("Dots"),  icon: "radio_button_checked",   value: "dot" },
                        { displayName: Translation.tr("Icons"), icon: "interests",              value: "icon" },
                    ]
                }
            }
        }

        ContentSection {
            icon: "empty_dashboard"
            shape: MaterialShape.Shape.Burst
            title: Translation.tr("Resources")

            GroupedList {
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.resources.alwaysShowCpu";
                        enabled: !nixManaged;
                        buttonIcon: "planner_review"
                        text: Translation.tr("CPU")
                        checked: Config.options.bar.resources.alwaysShowCpu
                        onCheckedChanged: { Config.options.bar.resources.alwaysShowCpu = checked }
                    }
                    ConfigSwitch {
                        configKey: "bar.resources.alwaysShowCpuTemp";
                        enabled: !nixManaged;
                        buttonIcon: "thermostat"
                        text: Translation.tr("CPU Temperature")
                        checked: Config.options.bar.resources.alwaysShowCpuTemp
                        onCheckedChanged: { Config.options.bar.resources.alwaysShowCpuTemp = checked }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.resources.alwaysShowRam";
                        enabled: !nixManaged;
                        buttonIcon: "memory"
                        text: Translation.tr("RAM")
                        checked: Config.options.bar.resources.alwaysShowRam
                        onCheckedChanged: { Config.options.bar.resources.alwaysShowRam = checked }
                    }
                    ConfigSwitch {
                        configKey: "bar.resources.alwaysShowDisk";
                        enabled: !nixManaged;
                        buttonIcon: "storage"
                        text: Translation.tr("Disk")
                        checked: Config.options.bar.resources.alwaysShowDisk
                        onCheckedChanged: { Config.options.bar.resources.alwaysShowDisk = checked }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "bar.resources.alwaysShowSwap";
                        enabled: !nixManaged;
                        buttonIcon: "swap_horiz"
                        text: Translation.tr("Swap")
                        checked: Config.options.bar.resources.alwaysShowSwap
                        onCheckedChanged: { Config.options.bar.resources.alwaysShowSwap = checked }
                    }
                }
                ConfigSelectionArray {
                    configKey: "bar.resources.style";
                    enabled: !nixManaged;
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.bar.resources.style
                    onSelected: newValue => { Config.options.bar.resources.style = newValue; }
                    options: [
                        { displayName: Translation.tr("Filled"),    icon: "incomplete_circle",  value: "filled" },
                        { displayName: Translation.tr("Outline"),   icon: "circles",            value: "outline" }
                    ]
                }
                ConfigSwitch {
                    configKey: "bar.resources.showValue";
                    enabled: !nixManaged;
                    buttonIcon: "decimal_increase"; text: Translation.tr("Show Percentage")
                    checked: Config.options.bar.resources.showValue
                    onCheckedChanged: { Config.options.bar.resources.showValue = checked; }
                }
                ConfigSpinBox {
                    configKey: "resources.updateInterval";
                    enabled: !nixManaged;
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (ms)")
                    value: Config.options.resources.updateInterval
                    from: 100
                    to: 10000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.resources.updateInterval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "music_note"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Media")

            GroupedList {
                ConfigTextArea {
                    configKey: "bar.media.preferredPlayer";
                    enabled: !nixManaged;
                    id: preferredPlayerField
                    Layout.fillWidth: true
                    buttonIcon: "play_circle"
                    text: Translation.tr("Preferred Player")
                    placeholderText: Translation.tr("e.g. spotify, firefox")
                    value: Config.options.bar.media.preferredPlayer
                    onValueChanged: {
                        mediaDebounceTimer.restart();
                    }

                    Timer {
                        id: mediaDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.bar.media.preferredPlayer = preferredPlayerField.value;
                        }
                    }
                }
                ConfigSwitch {
                    configKey: "bar.media.alwaysVisible";
                    enabled: !nixManaged;
                    buttonIcon: "keep"; text: Translation.tr("Pin media controls")
                    checked: Config.options.bar.media.alwaysVisible
                    onCheckedChanged: { Config.options.bar.media.alwaysVisible = checked; }
                }
                ConfigSwitch {
                    configKey: "bar.media.onlyTitle";
                    enabled: !nixManaged;
                    buttonIcon: "titlecase"; text: Translation.tr("Show only title")
                    checked: Config.options.bar.media.onlyTitle
                    onCheckedChanged: { Config.options.bar.media.onlyTitle = checked; }
                }
                ConfigSpinBox {
                    configKey: "bar.media.maxWidth";
                    enabled: !nixManaged;
                    icon: "width"
                    text: Translation.tr("Max media width")
                    value: Config.options.bar.media.maxWidth
                    from: 100
                    to: 500
                    stepSize: 10
                    onValueChanged: {
                        Config.options.bar.media.maxWidth = value;
                    }
                }
            }
        }

        ContentSection {
            shape: MaterialShape.Shape.Puffy
            icon: "tooltip"; title: Translation.tr("Tooltips")
            GroupedList {
                ConfigSwitch {
                    configKey: "bar.tooltips.enable";
                    enabled: !nixManaged;
                    buttonIcon: "visibility"; text: Translation.tr("Enable")
                    checked: Config.options.bar.tooltips.enable
                    onCheckedChanged: { Config.options.bar.tooltips.enable = checked; }
                }
                ConfigSwitch {
                    configKey: "bar.tooltips.clickToShow";
                    buttonIcon: "ads_click"; text: Translation.tr("Click to show")
                    checked: Config.options.bar.tooltips.clickToShow
                    onCheckedChanged: { Config.options.bar.tooltips.clickToShow = checked; }
                    enabled: (Config.options.bar.tooltips.enable) && !nixManaged
                }
            }
        }
    }
}
