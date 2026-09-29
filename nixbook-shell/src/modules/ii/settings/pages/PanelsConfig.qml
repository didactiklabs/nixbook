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
    }
}
