import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    //This was intended to go into the results more deeply but in the end I didn't like it but I left it just in case lol
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
            icon: "neurology"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("AI")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("System prompt")
                text: Config.options.ai.systemPrompt
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.ai.systemPrompt = text;
                    });
                }
            }
            ConfigSwitch {
                configKey: "ai.includeSystemContext"
                buttonIcon: "developer_board"
                text: Translation.tr("Include this machine's configuration (Nix modules, keybinds, shell settings, packages)")
                checked: Config.options.ai.includeSystemContext
                onCheckedChanged: Config.options.ai.includeSystemContext = checked
                StyledToolTip {
                    text: Translation.tr("Appended to the system prompt, so the assistant knows how this system is set up.\nIt is sent to the selected AI provider with each request.")
                }
            }
            ConfigSwitch {
                configKey: "ai.notifyWhenDone"
                buttonIcon: "notifications_active"
                text: Translation.tr("Notify me when the assistant is done or waiting for me")
                checked: Config.options.ai.notifyWhenDone
                onCheckedChanged: Config.options.ai.notifyWhenDone = checked
                StyledToolTip {
                    text: Translation.tr("Only while the side panel is closed, and not in Do Not Disturb.")
                }
            }
        }

        ContentSection {
            icon: "cell_tower"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Networking")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("User agent (for services that require it)")
                text: Config.options.networking.userAgent
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.networking.userAgent = text;
                }
            }
        }

        ContentSection {
            icon: "music_cast"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Music Recognition")

            GroupedList {
                ConfigSpinBox {
                    configKey: "musicRecognition.timeout";
                    enabled: !nixManaged;
                    icon: "timer_off"
                    text: Translation.tr("Total duration timeout (s)")
                    value: Config.options.musicRecognition.timeout
                    from: 10
                    to: 100
                    stepSize: 2
                    onValueChanged: {
                        Config.options.musicRecognition.timeout = value;
                    }
                }
                ConfigSpinBox {
                    configKey: "musicRecognition.interval";
                    enabled: !nixManaged;
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (s)")
                    value: Config.options.musicRecognition.interval
                    from: 2
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.musicRecognition.interval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "file_open"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Save paths")

            GroupedList {
                ConfigTextArea {
                    configKey: "screenRecord.savePath";
                    enabled: !nixManaged;
                    id: videoRecordPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "video_file"
                    text: Translation.tr("Video Recording Path")
                    value: Config.options.screenRecord.savePath
                    onValueChanged: {
                        videoRecordPathDebounceTimer.restart();
                    }

                    Timer {
                        id: videoRecordPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenRecord.savePath = videoRecordPathField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "screenSnip.savePath";
                    enabled: !nixManaged;
                    id: screenshotPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "screenshot_monitor"
                    text: Translation.tr("Screenshot Path (leave empty to just copy)")
                    value: Config.options.screenSnip.savePath
                    onValueChanged: {
                        screenshotPathDebounceTimer.restart();
                    }

                    Timer {
                        id: screenshotPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenSnip.savePath = screenshotPathField.value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "search"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Search")

            GroupedList {
                ConfigSwitch {
                    configKey: "search.sloppy";
                    enabled: !nixManaged;
                    text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
                    checked: Config.options.search.sloppy
                    onCheckedChanged: {
                        Config.options.search.sloppy = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Prefixes")

                GroupedList {
                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            configKey: "search.prefix.action";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "bolt"
                            fieldWidth: 100
                            text: Translation.tr("Action")
                            value: Config.options.search.prefix.action
                            onValueChanged: {
                                Config.options.search.prefix.action = value;
                            }
                        }
                        ConfigTextArea {
                            configKey: "search.prefix.clipboard";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "content_paste"
                            fieldWidth: 100
                            text: Translation.tr("Clipboard")
                            value: Config.options.search.prefix.clipboard
                            onValueChanged: {
                                Config.options.search.prefix.clipboard = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            configKey: "search.prefix.emojis";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "mood"
                            fieldWidth: 100
                            text: Translation.tr("Emojis")
                            value: Config.options.search.prefix.emojis
                            onValueChanged: {
                                Config.options.search.prefix.emojis = value;
                            }
                        }
                        ConfigTextArea {
                            configKey: "search.prefix.symbols";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "emoji_symbols"
                            fieldWidth: 100
                            text: Translation.tr("Icons")
                            value: Config.options.search.prefix.symbols
                            onValueChanged: {
                                Config.options.search.prefix.symbols = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            configKey: "search.prefix.shellCommand";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "terminal"
                            fieldWidth: 100
                            text: Translation.tr("Shell command")
                            value: Config.options.search.prefix.shellCommand
                            onValueChanged: {
                                Config.options.search.prefix.shellCommand = value;
                            }
                        }
                        ConfigTextArea {
                            configKey: "search.prefix.webSearch";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            fieldWidth: 100
                            buttonIcon: "travel_explore"
                            text: Translation.tr("Web search")
                            value: Config.options.search.prefix.webSearch
                            onValueChanged: {
                                Config.options.search.prefix.webSearch = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            configKey: "search.prefix.app";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "apps"
                            fieldWidth: 100
                            text: Translation.tr("Apps")
                            value: Config.options.search.prefix.app
                            onValueChanged: {
                                Config.options.search.prefix.app = value;
                            }
                        }
                        ConfigTextArea {
                            configKey: "search.prefix.themes";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "palette"
                            fieldWidth: 100
                            text: Translation.tr("Themes")
                            value: Config.options.search.prefix.themes
                            onValueChanged: {
                                Config.options.search.prefix.themes = value;
                            }
                        }
                        ConfigTextArea {
                            configKey: "search.prefix.layouts";
                            enabled: !nixManaged;
                            Layout.fillWidth: true
                            buttonIcon: "view_quilt"
                            fieldWidth: 100
                            text: Translation.tr("Window layouts")
                            value: Config.options.search.prefix.layouts
                            onValueChanged: {
                                Config.options.search.prefix.layouts = value;
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Web search")

                GroupedList {
                    ConfigTextArea {
                        configKey: "search.engineBaseUrl";
                        enabled: !nixManaged;
                        id: baseUrlField
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "travel_explore"
                        text: Translation.tr("Base URL")
                        value: Config.options.search.engineBaseUrl
                        onValueChanged: {
                            baseUrlDebounceTimer.restart();
                        }

                        Timer {
                            id: baseUrlDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.search.engineBaseUrl = baseUrlField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "deployed_code_update"
            title: Translation.tr("System updates")

            GroupedList {
                ConfigSwitch {
                    configKey: "updates.enableCheck";
                    enabled: !nixManaged;
                    buttonIcon: "update"
                    text: Translation.tr("Enable update checks")
                    checked: Config.options.updates.enableCheck
                    onCheckedChanged: {
                        Config.options.updates.enableCheck = checked;
                    }
                }

                ConfigSpinBox {
                    configKey: "updates.checkInterval";
                    enabled: !nixManaged;
                    icon: "av_timer"
                    text: Translation.tr("Check interval (mins)")
                    value: Config.options.updates.checkInterval
                    from: 60
                    to: 1440
                    stepSize: 60
                    onValueChanged: {
                        Config.options.updates.checkInterval = value;
                    }
                }

                ConfigTextArea {
                    configKey: "updates.repoUrl";
                    enabled: !nixManaged;
                    id: repoUrlField
                    Layout.fillWidth: true
                    buttonIcon: "link"
                    text: Translation.tr("Repository URL")
                    value: Config.options.updates.repoUrl
                    onValueChanged: repoUrlDebounceTimer.restart()

                    Timer {
                        id: repoUrlDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: Config.options.updates.repoUrl = repoUrlField.value;
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: UpdateState.updateAvailable && !UpdateState.checking && !UpdateState.updating
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                text: UpdateState.updating ? Translation.tr("Updating system...")
                    : UpdateState.checking ? Translation.tr("Checking for updates...")
                    : UpdateState.updateAvailable
                        ? Translation.tr("Update available: %1 \u2192 %2").arg(UpdateState.localRev.slice(0, 7)).arg(UpdateState.remoteRev.slice(0, 7))
                        : Translation.tr("System up to date (%1)").arg(UpdateState.localRev.slice(0, 7))
            }

            ConfigRow {
                uniform: true

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "sync"
                    mainText: UpdateState.checking ? Translation.tr("Checking...") : Translation.tr("Check for Updates")
                    enabled: !UpdateState.checking && !UpdateState.updating
                    onClicked: UpdateState.checkUpdate()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    visible: UpdateState.updateAvailable || UpdateState.updating
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "deployed_code_update"
                    mainText: UpdateState.updating ? Translation.tr("Updating...") : Translation.tr("Execute Update")
                    enabled: !UpdateState.updating
                    onClicked: UpdateState.startUpdate()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "terminal"
                    mainText: UpdateState.viewingLogs ? Translation.tr("Stop Logs") : Translation.tr("View Logs")
                    onClicked: {
                        if (UpdateState.viewingLogs) {
                            UpdateState.stopLogs()
                        } else {
                            UpdateState.startLogs()
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: UpdateState.changelogText !== ""
                text: Translation.tr("Changelog")
                color: Appearance.colors.colOnLayer2
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                visible: UpdateState.changelogText !== ""
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                Flickable {
                    id: changelogFlickable
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: changelogLabel.paintedHeight
                    clip: true

                    StyledText {
                        id: changelogLabel
                        width: parent.width
                        text: UpdateState.changelogText
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                visible: UpdateState.viewingLogs
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                Flickable {
                    id: logFlickable
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: logLabel.paintedHeight
                    clip: true

                    StyledText {
                        id: logLabel
                        width: parent.width
                        text: UpdateState.logText || Translation.tr("Waiting for logs...")
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.Wrap
                        onTextChanged: {
                            logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height)
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "weather_mix"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Weather")
            GroupedList {
                ConfigSwitch {
                    configKey: "bar.weather.enableGPS";
                    enabled: !nixManaged;
                    buttonIcon: "assistant_navigation"
                    text: Translation.tr("Enable GPS based location")
                    checked: Config.options.bar.weather.enableGPS
                    onCheckedChanged: {
                        Config.options.bar.weather.enableGPS = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "bar.weather.useUSCS";
                    enabled: !nixManaged;
                    buttonIcon: "thermometer"
                    text: Translation.tr("Fahrenheit unit")
                    checked: Config.options.bar.weather.useUSCS
                    onCheckedChanged: {
                        Config.options.bar.weather.useUSCS = checked;
                    }
                }
                ConfigSpinBox {
                    configKey: "bar.weather.fetchInterval";
                    enabled: !nixManaged;
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (m)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 50
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.weather.fetchInterval = value;
                    }
                }
                ConfigTextArea {
                    configKey: "bar.weather.city";
                    enabled: !nixManaged;
                    id: cityField
                    Layout.fillWidth: true
                    buttonIcon: "location_city"
                    text: Translation.tr("City name")
                    value: Config.options.bar.weather.city
                    onValueChanged: cityDebounceTimer.restart()

                    Timer {
                        id: cityDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: Config.options.bar.weather.city = cityField.value
                    }
                }
            }
        }
        WorldMap {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
        }
    }
}
