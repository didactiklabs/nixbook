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
            icon: "theater_comedy"
            shape: MaterialShape.Shape.Burst
            title: Translation.tr("Persona style")
            GroupedList {
                ConfigSwitch {
                    configKey: "appearance.persona.enable";
                    buttonIcon: "check"
                    text: Translation.tr("Enable Persona art direction")
                    checked: Config.options.appearance.persona.enable
                    enabled: !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.enable = checked }
                }
                ConfigSelectionArray {
                    configKey: "appearance.persona.variant";
                    enabled: Config.options.appearance.persona.enable && !nixManaged
                    text: Translation.tr("Persona variant")
                    icon: "sports_esports"
                    currentValue: Config.options.appearance.persona.variant
                    options: [
                        { "displayName": "Persona 5", "icon": "local_fire_department", "value": "p5" },
                        { "displayName": "Persona 3 Reload", "icon": "water_drop", "value": "p3r" },
                        { "displayName": "Persona 4 Revival", "icon": "tv", "value": "p4" },
                    ]
                    onSelected: newValue => { Config.options.appearance.persona.variant = newValue }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.palette";
                    buttonIcon: "palette"
                    text: Translation.tr("Game color palette (instead of wallpaper)")
                    checked: Config.options.appearance.persona.palette
                    enabled: Config.options.appearance.persona.enable && !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.palette = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.motion";
                    buttonIcon: "animation"
                    text: Translation.tr("Snappy slam-in animations")
                    checked: Config.options.appearance.persona.motion
                    enabled: Config.options.appearance.persona.enable && !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.motion = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.shapes";
                    buttonIcon: "change_history"
                    text: Translation.tr("Sharp slanted frames and hard shadows")
                    checked: Config.options.appearance.persona.shapes
                    enabled: Config.options.appearance.persona.enable && !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.shapes = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.halftone";
                    buttonIcon: "blur_on"
                    text: Translation.tr("Background art & halftone")
                    checked: Config.options.appearance.persona.halftone
                    enabled: Config.options.appearance.persona.enable && !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.halftone = checked }
                }
                ConfigSwitch {
                    configKey: "appearance.persona.fonts";
                    buttonIcon: "title"
                    text: Translation.tr("Condensed display font for titles")
                    checked: Config.options.appearance.persona.fonts
                    enabled: Config.options.appearance.persona.enable && !nixManaged
                    onCheckedChanged: { Config.options.appearance.persona.fonts = checked }
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
                ConfigSpinBox {
                    configKey: "settings.borderSize";
                    enabled: !nixManaged;
                    icon: "border_style"
                    text: Translation.tr("Border width")
                    value: Config.options.settings.borderSize
                    from: 0
                    to: 10
                    stepSize: 1
                    onValueChanged: { Config.options.settings.borderSize = value }
                }
                ColorSelectionArray {
                    configKey: "settings.borderColor";
                    enabled: !nixManaged;
                    icon: "format_paint"
                    text: Translation.tr("Border Color")
                    options: ["primary", "secondary", "tertiary", "primaryContainer", "secondaryContainer", "tertiaryContainer", "layer0Border"]
                    currentValue: Config.options.settings.borderColor 
                    onSelected: newValue => {
                        Config.options.settings.borderColor = newValue
                    }
                }
            } 
        }

        ContentSection {
            icon: "splitscreen_left"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Left Sidebar")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: aiCol.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: "transparent"

                        ColumnLayout {
                            id: aiCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 8

                            MaterialSymbol {
                                text: "smart_toy"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("AI")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            ConfigSelectionArray {
                                configKey: "policies.ai";
                                enabled: !nixManaged;
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight
                                currentValue: Config.options.policies.ai
                                onSelected: newValue => { Config.options.policies.ai = newValue }
                                options: [
                                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                                    { displayName: Translation.tr("Local"), icon: "sync_saved_locally", value: 2 }
                                ]
                            }
                        }
                    }

                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: translatorCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: "transparent"

                ColumnLayout {
                    id: translatorCol
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        ConfigSwitch {
                            configKey: "sidebar.translator.enable";
                            enabled: !nixManaged;
                            buttonIcon: "translate"
                            text: Translation.tr("Enable Translator")
                            checked: Config.options.sidebar.translator.enable
                            onCheckedChanged: { Config.options.sidebar.translator.enable = checked }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "splitscreen_right"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Right Sidebar")

            GroupedList {
                ConfigSwitch {
                    configKey: "sidebar.banner";
                    enabled: !nixManaged;
                    buttonIcon: "planner_banner_ad_pt"
                    text: Translation.tr('Banner')
                    checked: Config.options.sidebar.banner
                    onCheckedChanged: {
                        Config.options.sidebar.banner = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "sidebar.bottomGroup";
                    enabled: !nixManaged;
                    buttonIcon: "bottom_navigation"
                    text: Translation.tr('Bottom Group')
                    checked: Config.options.sidebar.bottomGroup
                    onCheckedChanged: {
                        Config.options.sidebar.bottomGroup = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "sidebar.mediaPlayer";
                    enabled: !nixManaged;
                    buttonIcon: "music_note"
                    text: Translation.tr('Media Player')
                    checked: Config.options.sidebar.mediaPlayer
                    onCheckedChanged: {
                        Config.options.sidebar.mediaPlayer = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "sidebar.keepRightSidebarLoaded";
                    enabled: !nixManaged;
                    buttonIcon: "memory"
                    text: Translation.tr('Keep right sidebar loaded')
                    checked: Config.options.sidebar.keepRightSidebarLoaded
                    onCheckedChanged: {
                        Config.options.sidebar.keepRightSidebarLoaded = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quick toggles")
                GroupedList {
                    ConfigSelectionArray {
                        configKey: "sidebar.quickToggles.style";
                        enabled: !nixManaged;
                        text: Translation.tr("Style")
                        icon: "toggle_on"
                        Layout.fillWidth: false
                        currentValue: Config.options.sidebar.quickToggles.style
                        onSelected: newValue => {
                            Config.options.sidebar.quickToggles.style = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Classic"),
                                icon: "password_2",
                                value: "classic"
                            },
                            {
                                displayName: Translation.tr("Android"),
                                icon: "action_key",
                                value: "android"
                            }
                        ]
                    }
                    ConfigSpinBox {
                        configKey: "sidebar.quickToggles.android.columns";
                        enabled: (Config.options.sidebar.quickToggles.style === "android") && !nixManaged
                        icon: "add_column_left"
                        text: Translation.tr("Columns")
                        value: Config.options.sidebar.quickToggles.android.columns
                        from: 1
                        to: 8
                        stepSize: 1
                        onValueChanged: {
                            Config.options.sidebar.quickToggles.android.columns = value;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Sliders")
                GroupedList {
                    ConfigSwitch {
                        configKey: "sidebar.quickSliders.enable";
                        enabled: !nixManaged;
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.quickSliders.enable
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.enable = checked;
                        }
                    }

                    ConfigSwitch {
                        configKey: "sidebar.quickSliders.showBrightness";
                        buttonIcon: "brightness_6"
                        text: Translation.tr("Brightness")
                        enabled: (Config.options.sidebar.quickSliders.enable) && !nixManaged
                        checked: Config.options.sidebar.quickSliders.showBrightness
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showBrightness = checked;
                        }
                    }

                    ConfigSwitch {
                        configKey: "sidebar.quickSliders.showVolume";
                        buttonIcon: "volume_up"
                        text: Translation.tr("Volume")
                        enabled: (Config.options.sidebar.quickSliders.enable) && !nixManaged
                        checked: Config.options.sidebar.quickSliders.showVolume
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showVolume = checked;
                        }
                    }

                    ConfigSwitch {
                        configKey: "sidebar.quickSliders.showMic";
                        buttonIcon: "mic"
                        text: Translation.tr("Microphone")
                        enabled: (Config.options.sidebar.quickSliders.enable) && !nixManaged
                        checked: Config.options.sidebar.quickSliders.showMic
                        onCheckedChanged: {
                            Config.options.sidebar.quickSliders.showMic = checked;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "screenshot_frame_2"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Hot Corners")

            ContentSubsection {
                title: Translation.tr("Top")

                GroupedList {
                    ConfigSwitch {
                        configKey: "sidebar.cornerOpen.enable";
                        enabled: !nixManaged;
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.cornerOpen.enable
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.enable = checked }
                    }
                    ConfigSwitch {
                        configKey: "sidebar.cornerOpen.clickless";
                        enabled: !nixManaged;
                        buttonIcon: "highlight_mouse_cursor"
                        text: Translation.tr("Hover to trigger")
                        checked: Config.options.sidebar.cornerOpen.clickless
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.clickless = checked }
                    }
                    ConfigSwitch {
                        configKey: "sidebar.cornerOpen.bottom";
                        enabled: !nixManaged;
                        buttonIcon: "vertical_align_bottom"
                        text: Translation.tr("Place at bottom")
                        checked: Config.options.sidebar.cornerOpen.bottom
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.bottom = checked }
                    }
                    ConfigSwitch {
                        configKey: "sidebar.cornerOpen.valueScroll";
                        enabled: !nixManaged;
                        buttonIcon: "unfold_more_double"
                        text: Translation.tr("Value scroll")
                        checked: Config.options.sidebar.cornerOpen.valueScroll
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.valueScroll = checked }
                    }
                    ConfigSwitch {
                        configKey: "sidebar.cornerOpen.visualize";
                        enabled: !nixManaged;
                        buttonIcon: "visibility"
                        text: Translation.tr("Visualize region")
                        checked: Config.options.sidebar.cornerOpen.visualize
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.visualize = checked }
                    }
                    ConfigSwitch {
                        configKey: "sidebar.cornerOpen.clicklessCornerEnd";
                        enabled: (Config.options.sidebar.cornerOpen.clickless) && !nixManaged
                        buttonIcon: "ads_click"
                        text: Translation.tr("Force hover at absolute corner")
                        checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                        onCheckedChanged: { Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked }
                    }
                    ConfigSpinBox {
                        configKey: "sidebar.cornerOpen.clicklessCornerVerticalOffset";
                        enabled: (Config.options.sidebar.cornerOpen.clickless) && !nixManaged
                        icon: "arrow_cool_down"
                        text: Translation.tr("Vertical offset")
                        value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                        from: 0; to: 20; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value }
                    }
                    ConfigSpinBox {
                        configKey: "sidebar.cornerOpen.cornerRegionWidth";
                        enabled: !nixManaged;
                        icon: "arrow_range"
                        text: Translation.tr("Region width")
                        value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                        from: 1; to: 300; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionWidth = value }
                    }
                    ConfigSpinBox {
                        configKey: "sidebar.cornerOpen.cornerRegionHeight";
                        enabled: !nixManaged;
                        icon: "height"
                        text: Translation.tr("Region height")
                        value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                        from: 1; to: 300; stepSize: 1
                        onValueChanged: { Config.options.sidebar.cornerOpen.cornerRegionHeight = value }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Bottom")
                GroupedList {
                    ConfigComboBox {
                        configKey: "sidebar.cornerOpen.bottomLeftAction";
                        enabled: !nixManaged;
                        Layout.fillWidth: true
                        buttonIcon: "position_bottom_left"
                        text: Translation.tr("Bottom-left")
                        textRole: "displayName"
                        fieldWidth: 50
                        model: GlobalStates.hotCornerOptions
                        currentValue: Config.options.sidebar.cornerOpen.bottomLeftAction
                        onSelected: newValue => { Config.options.sidebar.cornerOpen.bottomLeftAction = newValue }
                    }
                    ConfigComboBox {
                        configKey: "sidebar.cornerOpen.bottomRightAction";
                        enabled: !nixManaged;
                        Layout.fillWidth: true
                        buttonIcon: "position_bottom_right"
                        text: Translation.tr("Bottom-right")
                        textRole: "displayName"
                        fieldWidth: 55
                        model: GlobalStates.hotCornerOptions
                        currentValue: Config.options.sidebar.cornerOpen.bottomRightAction
                        onSelected: newValue => { Config.options.sidebar.cornerOpen.bottomRightAction = newValue }
                    }
                }
            }
        }
    
        ContentSection { // I see that for many the overview is important, I put it first why not
            visible: WM.compositor !== "niri"
            icon: "overview_key"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Overview")

            GroupedList {
                ConfigSwitch {
                    configKey: "overview.enable";
                    enabled: !nixManaged;
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.overview.enable
                    onCheckedChanged: {
                        Config.options.overview.enable = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "overview.centerIcons";
                    enabled: !nixManaged;
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Center icons")
                    checked: Config.options.overview.centerIcons
                    onCheckedChanged: {
                        Config.options.overview.centerIcons = checked;
                    }
                }
                ConfigSpinBox {
                    configKey: "overview.scale";
                    enabled: !nixManaged;
                    icon: "loupe"
                    text: Translation.tr("Scale (%)")
                    value: Config.options.overview.scale * 100
                    from: 1
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.scale = value / 100;
                    }
                }
                ConfigSelectionArray {
                    configKey: "overview.style";
                    enabled: !nixManaged;
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: Config.options.overview.style
                    onSelected: newValue => {
                        Config.options.overview.style = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "grid_on",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Niri Like"),
                            icon: "mobiledata_arrows",
                            value: "niri"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Default Settings")
                visible: Config.options.overview.style !== "niri"

                GroupedList {
                    visible: Config.options.overview.style !== "niri"
                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        ConfigSpinBox {
                            configKey: "overview.rows";
                            enabled: !nixManaged;
                            icon: "splitscreen_bottom"
                            text: Translation.tr("Rows")
                            value: Config.options.overview.rows
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueChanged: {
                                Config.options.overview.rows = value;
                            }
                        }
                        ConfigSpinBox {
                            configKey: "overview.columns";
                            enabled: !nixManaged;
                            icon: "splitscreen_right"
                            text: Translation.tr("Columns")
                            value: Config.options.overview.columns
                            from: 1
                            to: 20
                            stepSize: 1
                            onValueChanged: {
                                Config.options.overview.columns = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        visible: Config.options.overview.style !== "niri"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.leftMargin: 24
                        ConfigSelectionArray {
                            configKey: "overview.orderRightLeft";
                            enabled: !nixManaged;
                            Layout.alignment: Qt.AlignHCenter
                            currentValue: Config.options.overview.orderRightLeft
                            onSelected: newValue => {
                                Config.options.overview.orderRightLeft = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Left to right"),
                                    icon: "arrow_forward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Right to left"),
                                    icon: "arrow_back",
                                    value: 1
                                }
                            ]
                        }
                        ConfigSelectionArray {
                            configKey: "overview.orderBottomUp";
                            enabled: !nixManaged;
                            Layout.alignment: Qt.AlignHCenter
                            currentValue: Config.options.overview.orderBottomUp
                            onSelected: newValue => {
                                Config.options.overview.orderBottomUp = newValue
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Top-down"),
                                    icon: "arrow_downward",
                                    value: 0
                                },
                                {
                                    displayName: Translation.tr("Bottom-up"),
                                    icon: "arrow_upward",
                                    value: 1
                                }
                            ]
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "call_to_action"
            title: Translation.tr("Dock")
            shape: MaterialShape.Shape.Cookie6Sided

            GroupedList {
                ConfigSwitch {
                    configKey: "dock.enable";
                    enabled: !nixManaged;
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.dock.enable
                    onCheckedChanged: { Config.options.dock.enable = checked }
                }
                ConfigSwitch {
                    configKey: "dock.showBackground";
                    enabled: !nixManaged;
                    buttonIcon: "background_dot_small"
                    text: Translation.tr("Background")
                    checked: Config.options.dock.showBackground
                    onCheckedChanged: { Config.options.dock.showBackground = checked }
                }
                ConfigSwitch {
                    configKey: "dock.hoverToReveal";
                    enabled: !nixManaged;
                    buttonIcon: "highlight_mouse_cursor"
                    text: Translation.tr("Hover to reveal")
                    checked: Config.options.dock.hoverToReveal
                    onCheckedChanged: { Config.options.dock.hoverToReveal = checked }
                }
                ConfigSwitch {
                    configKey: "dock.pinnedOnStartup";
                    enabled: !nixManaged;
                    buttonIcon: "push_pin"
                    text: Translation.tr("Pinned on startup")
                    checked: Config.options.dock.pinnedOnStartup
                    onCheckedChanged: { Config.options.dock.pinnedOnStartup = checked }
                }
            }


            ContentSubsection {
                title: Translation.tr("Buttons & Media")
                GroupedList {
                    ConfigSwitch {
                        configKey: "dock.showMedia";
                        enabled: !nixManaged;
                        buttonIcon: "music_note"
                        text: Translation.tr("Media Player")
                        checked: Config.options.dock.showMedia
                        onCheckedChanged: { Config.options.dock.showMedia = checked }
                    }
                    ConfigSwitch {
                        configKey: "dock.showPinButton";
                        enabled: !nixManaged;
                        buttonIcon: "keep"
                        text: Translation.tr("Show Pin Button")
                        checked: Config.options.dock.showPinButton
                        onCheckedChanged: { Config.options.dock.showPinButton = checked }
                    }
                    ConfigSwitch {
                        configKey: "dock.showAppsButton";
                        enabled: !nixManaged;
                        buttonIcon: "apps"
                        text: Translation.tr("Show Apps Button")
                        checked: Config.options.dock.showAppsButton
                        onCheckedChanged: { Config.options.dock.showAppsButton = checked }
                    }
                    ConfigSwitch {
                        configKey: "dock.monochromeIcons";
                        enabled: !nixManaged;
                        buttonIcon: "colors"
                        text: Translation.tr("Tint app icons")
                        checked: Config.options.dock.monochromeIcons
                        onCheckedChanged: { Config.options.dock.monochromeIcons = checked }
                    }
                }
            }
        }

        ContentSection {
            icon: "lock"
            title: Translation.tr("Lock screen")
            shape: MaterialShape.Shape.Pentagon

            GroupedList {
                ConfigSwitch {
                    configKey: "lock.useHyprlock";
                    enabled: !nixManaged;
                    buttonIcon: "water_drop"
                    text: Translation.tr("Use Hyprlock (instead of Quickshell)")
                    checked: Config.options.lock.useHyprlock
                    onCheckedChanged: { Config.options.lock.useHyprlock = checked }
                }
                ConfigSwitch {
                    configKey: "lock.launchOnStartup";
                    enabled: !nixManaged;
                    buttonIcon: "account_circle"
                    text: Translation.tr("Launch on startup")
                    checked: Config.options.lock.launchOnStartup
                    onCheckedChanged: { Config.options.lock.launchOnStartup = checked }
                }
                ConfigSwitch {
                    configKey: "lock.showWidgets";
                    buttonIcon: "widgets"
                    enabled: (WM.compositor !== "niri") && !nixManaged
                    text: Translation.tr("Show Widgets")
                    checked: Config.options.lock.showWidgets
                    onCheckedChanged: { Config.options.lock.showWidgets = checked }
                }
                ConfigSwitch {
                    configKey: "lock.showToolbars";
                    enabled: !nixManaged;
                    buttonIcon: "tools_installation_kit"
                    text: Translation.tr("Show Toolbars")
                    checked: Config.options.lock.showToolbars
                    onCheckedChanged: { Config.options.lock.showToolbars = checked }
                }
                ConfigSwitch {
                    configKey: "lock.showMedia";
                    buttonIcon: "music_note"
                    enabled: (Config.options.lock.showToolbars) && !nixManaged
                    text: Translation.tr("Show media player info")
                    checked: Config.options.lock.showMedia
                    onCheckedChanged: { Config.options.lock.showMedia = checked }
                }
            }

            ContentSubsection {
                title: Translation.tr("Security")
                GroupedList {
                    ConfigSwitch {
                        configKey: "lock.security.requirePasswordToPower";
                        enabled: !nixManaged;
                        buttonIcon: "settings_power"
                        text: Translation.tr("Require password to power off/restart")
                        checked: Config.options.lock.security.requirePasswordToPower
                        onCheckedChanged: { Config.options.lock.security.requirePasswordToPower = checked }
                    }
                    ConfigSwitch {
                        configKey: "lock.security.unlockKeyring";
                        enabled: !nixManaged;
                        buttonIcon: "key_vertical"
                        text: Translation.tr("Also unlock keyring")
                        checked: Config.options.lock.security.unlockKeyring
                        onCheckedChanged: { Config.options.lock.security.unlockKeyring = checked }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: General")
                GroupedList {
                    ConfigSwitch {
                        configKey: "lock.centerClock";
                        enabled: !nixManaged;
                        buttonIcon: "center_focus_weak"
                        text: Translation.tr("Center clock")
                        checked: Config.options.lock.centerClock
                        onCheckedChanged: { Config.options.lock.centerClock = checked }
                    }
                    ConfigSwitch {
                        configKey: "lock.showLockedText";
                        enabled: !nixManaged;
                        buttonIcon: "info"
                        text: Translation.tr('Show "Locked" text')
                        checked: Config.options.lock.showLockedText
                        onCheckedChanged: { Config.options.lock.showLockedText = checked }
                    }
                    ConfigSwitch {
                        configKey: "lock.materialShapeChars";
                        enabled: !nixManaged;
                        buttonIcon: "shapes"
                        text: Translation.tr("Use varying shapes for password characters")
                        checked: Config.options.lock.materialShapeChars
                        onCheckedChanged: { Config.options.lock.materialShapeChars = checked }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: Blurred")
                GroupedList {
                    ConfigSwitch {
                        configKey: "lock.blur.enable";
                        enabled: !nixManaged;
                        buttonIcon: "blur_on"
                        text: Translation.tr("Enable blur")
                        checked: Config.options.lock.blur.enable
                        onCheckedChanged: { Config.options.lock.blur.enable = checked }
                    }
                    ConfigSpinBox {
                        configKey: "lock.blur.size";
                        enabled: !nixManaged;
                        icon: "deblur"
                        text: Translation.tr("Samples")
                        value: Config.options.lock.blur.size
                        from: 20; to: 200; stepSize: 10
                        onValueChanged: { Config.options.lock.blur.size = value }
                    }
                    ConfigSpinBox {
                        configKey: "lock.blur.extraZoom";
                        enabled: !nixManaged;
                        icon: "loupe"
                        text: Translation.tr("Extra wallpaper zoom (%)")
                        value: Config.options.lock.blur.extraZoom * 100
                        from: 1; to: 150; stepSize: 2
                        onValueChanged: { Config.options.lock.blur.extraZoom = value / 100 }
                    }
                }
            }
        }

        ContentSection {
            icon: "select_window"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Overlay")

            GroupedList {
                ConfigSwitch {
                    configKey: "overlay.openingZoomAnimation";
                    enabled: !nixManaged;
                    buttonIcon: "high_density"
                    text: Translation.tr("Enable opening zoom animation")
                    checked: Config.options.overlay.openingZoomAnimation
                    onCheckedChanged: {
                        Config.options.overlay.openingZoomAnimation = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "overlay.darkenScreen";
                    enabled: !nixManaged;
                    buttonIcon: "texture"
                    text: Translation.tr("Darken screen")
                    checked: Config.options.overlay.darkenScreen
                    onCheckedChanged: {
                        Config.options.overlay.darkenScreen = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Floating Image")
                GroupedList {
                    ConfigTextArea {
                        configKey: "overlay.floatingImage.imageSource";
                        enabled: !nixManaged;
                        id: floatingImageSourceField
                        Layout.fillWidth: true
                        fieldWidth: 430
                        buttonIcon: "imagesmode"
                        text: Translation.tr("Image source")
                        value: Config.options.overlay.floatingImage.imageSource
                        onValueChanged: {
                            floatingImageSourceDebounceTimer.restart();
                        }

                        Timer {
                            id: floatingImageSourceDebounceTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                Config.options.overlay.floatingImage.imageSource = floatingImageSourceField.value;
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Crosshair")

                Rectangle {
                    id: crosshairCard
                    Layout.fillWidth: true
                    implicitHeight: crosshairCol.implicitHeight + 28
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: crosshairCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        ConfigTextArea {
                            configKey: "crosshair.code";
                            enabled: !nixManaged;
                            id: crosshairCodeField
                            Layout.fillWidth: true
                            buttonIcon: "point_scan"
                            text: Translation.tr("Crosshair code")
                            placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                            value: Config.options.crosshair.code
                            onValueChanged: {
                                crosshairCodeDebounceTimer.restart();
                            }

                            Timer {
                                id: crosshairCodeDebounceTimer
                                interval: 1000
                                repeat: false
                                onTriggered: {
                                    Config.options.crosshair.code = crosshairCodeField.value;
                                }
                            }
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.leftMargin: 8
                                Layout.fillWidth: true
                                text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }
                            RippleButtonWithIcon {
                                id: editorButton
                                Layout.fillWidth: true
                                Layout.rightMargin: 6
                                Layout.preferredHeight: 40
                                buttonRadius: Appearance.rounding.normal
                                materialIcon: "open_in_new"
                                mainText: Translation.tr("Open editor")
                                onClicked: {
                                    AppLaunch.openUrl(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "screenshot_frame_2"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Region selector (screen snipping/Google Lens)")

            ContentSubsection {
                title: Translation.tr("Hint target regions")
                GroupedList {
                    ConfigSwitch {
                        configKey: "regionSelector.targetRegions.windows";
                        enabled: !nixManaged;
                        buttonIcon: "select_window"
                        text: Translation.tr('Windows')
                        checked: Config.options.regionSelector.targetRegions.windows
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.windows = checked;
                        }
                    }
                    ConfigSwitch {
                        configKey: "regionSelector.targetRegions.layers";
                        enabled: !nixManaged;
                        buttonIcon: "right_panel_open"
                        text: Translation.tr('Layers')
                        checked: Config.options.regionSelector.targetRegions.layers
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.layers = checked;
                        }
                    }
                    ConfigSwitch {
                        configKey: "regionSelector.targetRegions.content";
                        enabled: !nixManaged;
                        buttonIcon: "nearby"
                        text: Translation.tr('Content')
                        checked: Config.options.regionSelector.targetRegions.content
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.content = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Google Lens")
                    
                GroupedList {
                    ConfigSelectionArray {
                        configKey: "search.imageSearch.useCircleSelection";
                        enabled: !nixManaged;
                        text: Translation.tr("Selection Type")
                        icon: "ink_selection"
                        currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                        onSelected: newValue => {
                            Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                        }
                        options: [
                            { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                            { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Rectangular selection")
                GroupedList {
                    ConfigSwitch {
                        configKey: "regionSelector.rect.showAimLines";
                        enabled: !nixManaged;
                        buttonIcon: "point_scan"
                        text: Translation.tr("Show aim lines")
                        checked: Config.options.regionSelector.rect.showAimLines
                        onCheckedChanged: {
                            Config.options.regionSelector.rect.showAimLines = checked;
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Circle selection")

                GroupedList {
                    ConfigSpinBox {
                        configKey: "regionSelector.circle.strokeWidth";
                        enabled: !nixManaged;
                        icon: "eraser_size_3"
                        text: Translation.tr("Stroke width")
                        value: Config.options.regionSelector.circle.strokeWidth
                        from: 1
                        to: 20
                        stepSize: 1
                        onValueChanged: {
                            Config.options.regionSelector.circle.strokeWidth = value;
                        }
                    }

                    ConfigSpinBox {
                        configKey: "regionSelector.circle.padding";
                        enabled: !nixManaged;
                        icon: "screenshot_frame_2"
                        text: Translation.tr("Padding")
                        value: Config.options.regionSelector.circle.padding
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.options.regionSelector.circle.padding = value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "voting_chip"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("On-screen display")
            GroupedList {
                ConfigSpinBox {
                    configKey: "osd.timeout";
                    enabled: !nixManaged;
                    icon: "av_timer"
                    text: Translation.tr("Timeout (ms)")
                    value: Config.options.osd.timeout
                    from: 100
                    to: 3000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.osd.timeout = value;
                    }
                }
            }
        }

        ContentSection {
            shape: MaterialShape.Shape.Puffy
            icon: "panorama"
            title: Translation.tr("Wallpaper selector")

            GroupedList {
                ConfigSwitch {
                    configKey: "wallpaperSelector.useSystemFileDialog";
                    enabled: !nixManaged;
                    buttonIcon: "ad"
                    text: Translation.tr('Use system file picker')
                    checked: Config.options.wallpaperSelector.useSystemFileDialog
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.useSystemFileDialog = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "wallpaperSelector.showHomePath";
                    enabled: !nixManaged;
                    buttonIcon: "home"
                    text: Translation.tr('Show home directory in quick access')
                    checked: Config.options.wallpaperSelector.showHomePath
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.showHomePath = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "wallpaperSelector.closeAfterSelection";
                    enabled: !nixManaged;
                    buttonIcon: "done"
                    text: Translation.tr('Close after selection')
                    checked: Config.options.wallpaperSelector.closeAfterSelection
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.closeAfterSelection = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "wallpaperSelector.showBlurBackground";
                    enabled: !nixManaged;
                    buttonIcon: "blur_on"
                    text: Translation.tr('Show blur background')
                    checked: Config.options.wallpaperSelector.showBlurBackground
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.showBlurBackground = checked;
                    }
                }

                ConfigSpinBox {
                    configKey: "wallpaperSelector.columns";
                    enabled: !nixManaged;
                    icon: "grid_on"
                    text: Translation.tr("Columns in grid view")
                    value: Config.options.wallpaperSelector.columns
                    from: 3
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.wallpaperSelector.columns = value;
                    }
                }

                ConfigSpinBox {
                    configKey: "wallpaperSelector.changeInterval";
                    enabled: !nixManaged;
                    icon: "timer"
                    text: Translation.tr("Wallpaper change interval (min)")
                    value: Config.options.wallpaperSelector.changeInterval / 60000
                    from: 0
                    to: 1440
                    stepSize: 5
                    onValueChanged: {
                        Config.options.wallpaperSelector.changeInterval = value * 60000;
                    }
                }

                ConfigSwitch {
                    configKey: "wallpaperSelector.showSearchbar";
                    enabled: !nixManaged;
                    buttonIcon: "search"
                    text: Translation.tr('Always show search bar')
                    checked: Config.options.wallpaperSelector.showSearchbar
                    onCheckedChanged: {
                        Config.options.wallpaperSelector.showSearchbar = checked;
                    }
                }
                ConfigTextArea {
                    configKey: "wallpaperSelector.userPath";
                    enabled: !nixManaged;
                    id: userPathField
                    Layout.fillWidth: true
                    buttonIcon: "folder"
                    text: Translation.tr("Custom Wallpaper Folder")
                    placeholderText: Translation.tr("e.g., /home/user/Pictures")
                    fieldWidth: 300
                    value: Config.options.wallpaperSelector.userPath ?? ""

                    onValueChanged: {
                        userPathDebounceTimer.restart()
                    }

                    Timer {
                        id: userPathDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.wallpaperSelector.userPath = userPathField.value
                        }
                    }
                }
                ConfigTextArea {
                    configKey: "wallpaperSelector.liveWallpapersPath";
                    enabled: !nixManaged;
                    id: liveWallpapersPathField
                    Layout.fillWidth: true
                    buttonIcon: "video_template"
                    text: Translation.tr("Live Wallpaper Folder")
                    placeholderText: Translation.tr("e.g., /home/user/Videos/Wallpapers")
                    fieldWidth: 300
                    value: Config.options.wallpaperSelector.liveWallpapersPath ?? ""

                    onValueChanged: {
                        liveWallpapersPathDebounceTimer.restart()
                    }

                    Timer {
                        id: liveWallpapersPathDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: {
                            Config.options.wallpaperSelector.liveWallpapersPath = liveWallpapersPathField.value
                        }
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
    }
}
