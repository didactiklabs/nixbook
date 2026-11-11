import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > Themes: the shell theme and variant, its wallpapers, and each
// theme's own style options (split out of the Appearance page).
ContentPage {
    id: page
    forceWidth: true

    // Per-variant wallpaper table (Settings → Themes): one cell
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
                    configKey: "appearance.cyberpunk.frames";
                    buttonIcon: "select"
                    text: Translation.tr("HUD frames on panels (cut corners, rulers, tags)")
                    checked: Config.options.appearance.cyberpunk.frames
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.cyberpunk.frames = checked }
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

        // Studio Ghibli theme options (only while it is the theme).
        ContentSection {
            shown: Themes.is("ghibli")
            icon: "forest"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Studio Ghibli style")
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.ghibli.palette";
                    buttonIcon: "palette"
                    text: Translation.tr("Watercolour palette of the film (instead of wallpaper)")
                    checked: Config.options.appearance.ghibli.palette
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.ghibli.palette = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.ghibli.motion";
                    buttonIcon: "animation"
                    text: Translation.tr("Gentle, floating animations")
                    checked: Config.options.appearance.ghibli.motion
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.ghibli.motion = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.ghibli.shapes";
                    buttonIcon: "rounded_corner"
                    text: Translation.tr("Soft rounded corners")
                    checked: Config.options.appearance.ghibli.shapes
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.ghibli.shapes = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.ghibli.fonts";
                    buttonIcon: "title"
                    text: Translation.tr("Storybook fonts (Zen Maru Gothic, Klee One)")
                    checked: Config.options.appearance.ghibli.fonts
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.ghibli.fonts = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.ghibli.spirits";
                    buttonIcon: "emoji_nature"
                    text: Translation.tr("The spirit on panels, the loading screen and cut-ins")
                    checked: Config.options.appearance.ghibli.spirits
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.ghibli.spirits = checked }
                }
            }
        }
    }
}
