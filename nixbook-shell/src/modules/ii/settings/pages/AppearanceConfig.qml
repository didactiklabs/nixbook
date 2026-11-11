import QtQuick
import QtQuick.Layouts
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

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "colors"
            title: Translation.tr("Color generation")
            shape: MaterialShape.Shape.VerySunny

            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.wallpaperTheming.enableAppsAndShell";
                    enabled: !nixManaged;
                    buttonIcon: "hardware"
                    text: Translation.tr("Shell & utilities")
                    checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.wallpaperTheming.enableQtApps";
                    // All the apps below (services/AppTheming.qml); the key
                    // keeps its upstream name.
                    enabled: !nixManaged;
                    buttonIcon: "tv_options_input_settings"
                    text: Translation.tr("Apps")
                    checked: Config.options.appearance.wallpaperTheming.enableQtApps
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableQtApps = checked }
                }
                // Each app: greyed out while "Apps" is off. Switching one off
                // undoes its setup.
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "appearance.wallpaperTheming.apps.qt";
                        enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableQtApps;
                        buttonIcon: "widgets"
                        text: Translation.tr("Qt & KDE")
                        checked: Config.options.appearance.wallpaperTheming.apps.qt
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.apps.qt = checked }
                        StyledToolTip {
                            text: Translation.tr("Dolphin and other Qt/KDE apps, live. Qt apps also need programs.nixbook-shell.appTheming.qt")
                        }
                    }
                    ConfigSwitch {
                        configKey: "appearance.wallpaperTheming.apps.vesktop";
                        enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableQtApps;
                        buttonIcon: "forum"
                        text: Translation.tr("Discord (Vesktop)")
                        checked: Config.options.appearance.wallpaperTheming.apps.vesktop
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.apps.vesktop = checked }
                        StyledToolTip {
                            text: Translation.tr("Live")
                        }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "appearance.wallpaperTheming.apps.youtubeMusic";
                        enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableQtApps;
                        buttonIcon: "music_note"
                        text: Translation.tr("YouTube Music")
                        checked: Config.options.appearance.wallpaperTheming.apps.youtubeMusic
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.apps.youtubeMusic = checked }
                        StyledToolTip {
                            text: Translation.tr("Live, through its bridge: always dark (the app has no light look), in the theme's colours")
                        }
                    }
                    ConfigSwitch {
                        configKey: "appearance.wallpaperTheming.apps.zen";
                        enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableQtApps;
                        buttonIcon: "public"
                        text: Translation.tr("Zen Browser")
                        checked: Config.options.appearance.wallpaperTheming.apps.zen
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.apps.zen = checked }
                        StyledToolTip {
                            text: Translation.tr("Zen reads them when it starts: while it runs, a notification offers to restart it (tabs restored)")
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                ConfigSwitch {
                    configKey: "appearance.wallpaperTheming.enableTerminal";
                    enabled: !nixManaged;
                    buttonIcon: "terminal"
                    text: Translation.tr("Terminal")
                    checked: Config.options.appearance.wallpaperTheming.enableTerminal
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableTerminal = checked }
                }
                // The terminal options only act on terminal theming: greyed
                // out while it is off.
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode";
                        enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableTerminal;
                        buttonIcon: "dark_mode"
                        text: Translation.tr("Force dark mode in terminal")
                        checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked }
                    }
                }
                ConfigSpinBox {
                    configKey: "appearance.wallpaperTheming.terminalGenerationProps.harmony";
                    enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableTerminal;
                    icon: "invert_colors"
                    text: Translation.tr("Terminal: Harmony (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100 }
                }
                ConfigSpinBox {
                    configKey: "appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold";
                    enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableTerminal;
                    icon: "gradient"
                    text: Translation.tr("Terminal: Harmonize threshold")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value }
                }
                ConfigSpinBox {
                    configKey: "appearance.wallpaperTheming.terminalGenerationProps.termFgBoost";
                    enabled: !nixManaged && Config.options.appearance.wallpaperTheming.enableTerminal;
                    icon: "format_color_text"
                    text: Translation.tr("Terminal: Foreground boost (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100 }
                }
            }
        }

        ContentSection {
            icon: "motion_mode"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Transparency")
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.transparency.enable";
                    enabled: !nixManaged;
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.appearance.transparency.enable
                    onCheckedChanged: { Config.options.appearance.transparency.enable = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.transparency.automatic";
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Automatic (from wallpaper)")
                    checked: Config.options.appearance.transparency.automatic
                    enabled: (Config.options.appearance.transparency.enable) && !nixManaged
                    onCheckedChanged: { Config.options.appearance.transparency.automatic = checked }
                }
                ConfigSlider {
                    configKey: "appearance.transparency.backgroundTransparency";
                    buttonIcon: "layers"
                    text: Translation.tr("Background")
                    enabled: (Config.options.appearance.transparency.enable) && !nixManaged
                            && !Config.options.appearance.transparency.automatic
                    from: 0; to: 0.6
                    stopIndicatorValues: [0.11]
                    value: Config.options.appearance.transparency.backgroundTransparency
                    onValueChanged: {
                        Config.options.appearance.transparency.backgroundTransparency = value
                    }
                }
                ConfigSlider {
                    configKey: "appearance.transparency.contentTransparency";
                    buttonIcon: "opacity"
                    text: Translation.tr("Content")
                    enabled: (Config.options.appearance.transparency.enable) && !nixManaged
                            && !Config.options.appearance.transparency.automatic
                    from: 0; to: 1
                    stopIndicatorValues: [0.57]
                    value: Config.options.appearance.transparency.contentTransparency
                    onValueChanged: {
                        Config.options.appearance.transparency.contentTransparency = value
                    }
                }
            }
        }

        ContentSection {
            icon: "text_format"
            shape: MaterialShape.Shape.Arrow
            title: Translation.tr("Fonts")

            GroupedList {
                ConfigTextArea {
                    configKey: "appearance.fonts.main";
                    enabled: !nixManaged;
                    id: mainFontField
                    Layout.fillWidth: true
                    buttonIcon: "font_download"
                    text: Translation.tr("Font family name (e.g., Google Sans Flex)")
                    value: Config.options.appearance.fonts.main
                    onValueChanged: {
                        mainFontDebounceTimer.restart();
                    }

                    Timer {
                        id: mainFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.main = mainFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "appearance.fonts.numbers";
                    enabled: !nixManaged;
                    id: numbersFontField
                    Layout.fillWidth: true
                    buttonIcon: "123"
                    text: Translation.tr("Numbers family name")
                    value: Config.options.appearance.fonts.numbers
                    onValueChanged: {
                        numbersFontDebounceTimer.restart();
                    }

                    Timer {
                        id: numbersFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.numbers = numbersFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "appearance.fonts.title";
                    enabled: !nixManaged;
                    id: titleFontField
                    Layout.fillWidth: true
                    buttonIcon: "title"
                    text: Translation.tr("Title family name")
                    value: Config.options.appearance.fonts.title
                    onValueChanged: {
                        titleFontDebounceTimer.restart();
                    }

                    Timer {
                        id: titleFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.title = titleFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "appearance.fonts.monospace";
                    enabled: !nixManaged;
                    id: monospaceFontField
                    Layout.fillWidth: true
                    buttonIcon: "space_bar"
                    text: Translation.tr("Monospace font name (e.g., JetBrains Mono NF)")
                    value: Config.options.appearance.fonts.monospace
                    onValueChanged: {
                        monospaceFontDebounceTimer.restart();
                    }

                    Timer {
                        id: monospaceFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.monospace = monospaceFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "appearance.fonts.iconNerd";
                    enabled: !nixManaged;
                    id: iconNerdFontField
                    Layout.fillWidth: true
                    buttonIcon: "emoticon"
                    text: Translation.tr("Nerd Fonts Icons (e.g., JetBrains Mono NF)")
                    value: Config.options.appearance.fonts.iconNerd
                    onValueChanged: {
                        iconNerdFontDebounceTimer.restart();
                    }

                    Timer {
                        id: iconNerdFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.iconNerd = iconNerdFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "appearance.fonts.reading";
                    enabled: !nixManaged;
                    id: readingFontField
                    Layout.fillWidth: true
                    buttonIcon: "book_ribbon"
                    text: Translation.tr("Reading font name (e.g., Readex Pro)")
                    value: Config.options.appearance.fonts.reading
                    onValueChanged: {
                        readingFontDebounceTimer.restart();
                    }

                    Timer {
                        id: readingFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.reading = readingFontField.value;
                        }
                    }
                }

                ConfigTextArea {
                    configKey: "appearance.fonts.expressive";
                    enabled: !nixManaged;
                    id: expressiveFontField
                    Layout.fillWidth: true
                    buttonIcon: "mood_heart"
                    text: Translation.tr("Expressive font name (e.g., Space Grotesk)")
                    value: Config.options.appearance.fonts.expressive
                    onValueChanged: {
                        expressiveFontDebounceTimer.restart();
                    }

                    Timer {
                        id: expressiveFontDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.appearance.fonts.expressive = expressiveFontField.value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "settings"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Settings Panel")
            GroupedList {
                ConfigSelectionArray {
                    configKey: "settings.style";
                    enabled: !nixManaged;
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.settings.style
                    onSelected: newValue => { Config.options.settings.style = newValue }
                    options: [
                        { displayName: Translation.tr("Default"), icon: "settings_panorama", value: "default" },
                        { displayName: Translation.tr("Minimal"), icon: "settings_heart", value: "minimal" }
                    ]
                }
            }
        }
    }
}
