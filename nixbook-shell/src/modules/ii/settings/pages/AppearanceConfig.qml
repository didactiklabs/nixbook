import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    // Per-variant wallpaper table (Settings → Appearance → Theme): one cell
    // per variant and screen; click to choose it in the wallpaper selector,
    // × to unset it (desktop: the variant's own/none; lock: the desktop's;
    // login: the lock screen's).
    component VariantWallCell: Rectangle {
        id: cell
        property string slot
        property string variantKey
        property string symbol
        property string value
        property bool isSet
        property bool locked
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 40
        radius: Appearance.rounding.small
        color: cellMouse.containsMouse && !cell.locked ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !cell.locked
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                GlobalStates.wallpaperSelectorTarget = `variant:${cell.slot}:${cell.variantKey}`;
                GlobalStates.wallpaperSelectorOpen = true;
            }
        }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
            spacing: 6
            MaterialSymbol {
                text: cell.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: cell.isSet ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: cell.value
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: cell.isSet ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
            }
            RippleButton {
                visible: cell.isSet && !cell.locked
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                onClicked: ThemeWallpapers.setFor(cell.slot, cell.variantKey, "")
                StyledToolTip { text: Translation.tr("Unset") }
            }
        }
    }
    function fileName(path) {
        return String(path).slice(String(path).lastIndexOf("/") + 1);
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
                    // No effect: the package drops the kde-material-you-colors
                    // hook it gates (qml.nix, not in nixpkgs).
                    visible: false
                    enabled: !nixManaged;
                    buttonIcon: "tv_options_input_settings"
                    text: Translation.tr("Qt apps")
                    checked: Config.options.appearance.wallpaperTheming.enableQtApps
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableQtApps = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.wallpaperTheming.enableTerminal";
                    enabled: !nixManaged;
                    buttonIcon: "terminal"
                    text: Translation.tr("Terminal")
                    checked: Config.options.appearance.wallpaperTheming.enableTerminal
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.enableTerminal = checked }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode";
                        enabled: !nixManaged;
                        buttonIcon: "dark_mode"
                        text: Translation.tr("Force dark mode in terminal")
                        checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                        onCheckedChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked }
                    }
                }
                ConfigSpinBox {
                    configKey: "appearance.wallpaperTheming.terminalGenerationProps.harmony";
                    enabled: !nixManaged;
                    icon: "invert_colors"
                    text: Translation.tr("Terminal: Harmony (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100 }
                }
                ConfigSpinBox {
                    configKey: "appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold";
                    enabled: !nixManaged;
                    icon: "gradient"
                    text: Translation.tr("Terminal: Harmonize threshold")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: { Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value }
                }
                ConfigSpinBox {
                    configKey: "appearance.wallpaperTheming.terminalGenerationProps.termFgBoost";
                    enabled: !nixManaged;
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

        // Theme and its variant (Themes.qml, themes.json): both lists come
        // from the registry, so a new theme shows up here by itself.
        ContentSection {
            icon: "style"
            shape: MaterialShape.Shape.Burst
            title: Translation.tr("Theme")
            GroupedList {
                ConfigSelectionArray {
                    configKey: "appearance.theme";
                    enabled: !nixManaged
                    text: Translation.tr("Theme")
                    icon: Themes.currentTheme?.icon ?? "style"
                    currentValue: Themes.current
                    options: Themes.list.map(t => ({ "displayName": Translation.tr(t.name), "icon": t.icon, "value": t.id }))
                    onSelected: newValue => Themes.setTheme(newValue)
                }
            }
            // Its own list: GroupedList keeps a row's background even when
            // the row is hidden, and a theme may have no variants.
            GroupedList {
                shown: Themes.currentVariants.length > 0
                ConfigSelectionArray {
                    configKey: Themes.variantKey(Themes.current);
                    enabled: !nixManaged
                    text: Translation.tr("Variant")
                    icon: Themes.currentVariant?.icon ?? "sports_esports"
                    currentValue: Themes.variant
                    options: Themes.currentVariants.map(v => ({ "displayName": Translation.tr(v.name), "icon": v.icon, "value": v.id }))
                    onSelected: newValue => Themes.setVariant(Themes.current, newValue)
                }
            }
            // A wallpaper per theme variant (services/ThemeWallpapers.qml).
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.wallpaperPerTheme";
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Each theme keeps its own wallpaper (switching puts it back)")
                    checked: Config.options.appearance.wallpaperPerTheme
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.wallpaperPerTheme = checked }
                }
                // Every variant's wallpapers, set here all at once (or picked
                // while in the variant: they are remembered either way).
                ColumnLayout {
                    visible: Config.options.appearance.wallpaperPerTheme
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            Layout.preferredWidth: 150
                            text: Translation.tr("Variant")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                        Repeater {
                            model: [Translation.tr("Desktop"), Translation.tr("Lock screen"), Translation.tr("Login screen")]
                            delegate: StyledText {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                    Repeater {
                        model: ThemeWallpapers.allKeys
                        delegate: RowLayout {
                            id: variantRow
                            required property var modelData
                            readonly property string key: modelData.key
                            readonly property bool current: key === ThemeWallpapers.key
                            readonly property var desk: ThemeWallpapers.wallpaperFor(key)
                            readonly property string lockPath: ThemeWallpapers.lockMap[key] ?? ""
                            readonly property string loginPath: ThemeWallpapers.loginMap[key] ?? ""
                            Layout.fillWidth: true
                            spacing: 6
                            RowLayout {
                                Layout.preferredWidth: 150
                                Layout.maximumWidth: 150
                                spacing: 6
                                MaterialSymbol {
                                    text: variantRow.modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: variantRow.current ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Translation.tr(variantRow.modelData.name)
                                    font.weight: variantRow.current ? Font.Bold : Font.Normal
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                            VariantWallCell {
                                slot: "main"
                                variantKey: variantRow.key
                                symbol: "wallpaper"
                                isSet: (ThemeWallpapers.map[variantRow.key] ?? "") !== ""
                                value: isSet ? page.fileName(ThemeWallpapers.map[variantRow.key])
                                    : variantRow.desk?.bundled ? Translation.tr("its own") : Translation.tr("not set")
                                locked: ThemeWallpapers.listPinned("main")
                            }
                            VariantWallCell {
                                slot: "lock"
                                variantKey: variantRow.key
                                symbol: "lock"
                                isSet: variantRow.lockPath !== ""
                                value: isSet ? page.fileName(variantRow.lockPath) : Translation.tr("the desktop's")
                                locked: ThemeWallpapers.listPinned("lock")
                            }
                            VariantWallCell {
                                slot: "login"
                                variantKey: variantRow.key
                                symbol: "login"
                                isSet: variantRow.loginPath !== ""
                                value: isSet ? page.fileName(variantRow.loginPath) : Translation.tr("the lock screen's")
                                locked: ThemeWallpapers.listPinned("login")
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Click a cell to choose its wallpaper, × to unset it. Wallpapers picked while in a variant are remembered for it too.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // Persona theme options (only while it is the theme).
        ContentSection {
            shown: Themes.is("persona")
            icon: "theater_comedy"
            shape: MaterialShape.Shape.Burst
            title: Translation.tr("Persona style")
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.persona.palette";
                    buttonIcon: "palette"
                    text: Translation.tr("Game color palette (instead of wallpaper)")
                    checked: Config.options.appearance.persona.palette
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.palette = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.motion";
                    buttonIcon: "animation"
                    text: Translation.tr("Snappy slam-in animations")
                    checked: Config.options.appearance.persona.motion
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.motion = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.shapes";
                    buttonIcon: "change_history"
                    text: Translation.tr("Sharp slanted frames and hard shadows")
                    checked: Config.options.appearance.persona.shapes
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.shapes = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.halftone";
                    buttonIcon: "blur_on"
                    text: Translation.tr("Background art & halftone")
                    checked: Config.options.appearance.persona.halftone
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.halftone = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.fonts";
                    buttonIcon: "title"
                    text: Translation.tr("Condensed display font for titles")
                    checked: Config.options.appearance.persona.fonts
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.fonts = checked }
                }
            }
        }

        // Chiikawa theme options (only while it is the theme).
        ContentSection {
            shown: Themes.is("chiikawa")
            icon: "cruelty_free"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Chiikawa style")
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.chiikawa.palette";
                    buttonIcon: "palette"
                    text: Translation.tr("Character color palette (instead of wallpaper)")
                    checked: Config.options.appearance.chiikawa.palette
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.chiikawa.palette = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.chiikawa.motion";
                    buttonIcon: "animation"
                    text: Translation.tr("Bouncy animations")
                    checked: Config.options.appearance.chiikawa.motion
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.chiikawa.motion = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.chiikawa.shapes";
                    buttonIcon: "rounded_corner"
                    text: Translation.tr("Extra round corners")
                    checked: Config.options.appearance.chiikawa.shapes
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.chiikawa.shapes = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.chiikawa.fonts";
                    buttonIcon: "title"
                    text: Translation.tr("Rounded font (Nunito)")
                    checked: Config.options.appearance.chiikawa.fonts
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.chiikawa.fonts = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.chiikawa.mascot";
                    buttonIcon: "cruelty_free"
                    text: Translation.tr("Show the character (loading screen, sidebars)")
                    checked: Config.options.appearance.chiikawa.mascot
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.chiikawa.mascot = checked }
                }
            }
        }

        // Cyberpunk 2077 theme options (only while it is the theme).
        ContentSection {
            shown: Themes.is("cyberpunk")
            icon: "memory"
            shape: MaterialShape.Shape.Square
            title: Translation.tr("Cyberpunk 2077 style")
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.cyberpunk.palette";
                    buttonIcon: "palette"
                    text: Translation.tr("Neon palette (instead of wallpaper)")
                    checked: Config.options.appearance.cyberpunk.palette
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.cyberpunk.palette = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.cyberpunk.motion";
                    buttonIcon: "animation"
                    text: Translation.tr("Sharp, snappy animations")
                    checked: Config.options.appearance.cyberpunk.motion
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.cyberpunk.motion = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.cyberpunk.shapes";
                    buttonIcon: "crop_square"
                    text: Translation.tr("Near-square corners")
                    checked: Config.options.appearance.cyberpunk.shapes
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.cyberpunk.shapes = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.cyberpunk.fonts";
                    buttonIcon: "title"
                    text: Translation.tr("Condensed tech font (Rajdhani)")
                    checked: Config.options.appearance.cyberpunk.fonts
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.cyberpunk.fonts = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.cyberpunk.glitch";
                    buttonIcon: "blur_on"
                    text: Translation.tr("Glitch and scanlines in the cut-in")
                    checked: Config.options.appearance.cyberpunk.glitch
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.cyberpunk.glitch = checked }
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
