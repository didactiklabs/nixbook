import QtQuick
import Quickshell
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Io
import Qt5Compat.GraphicalEffects


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

    // The wallpaper each screen really shows ("" falls back along the chain).
    readonly property string lockWallEffective: Config.options.background.lockWall !== ""
        ? Config.options.background.lockWall : Config.options.background.wallpaperPath
    readonly property string greeterWallEffective: Config.options.background.greeterWall !== ""
        ? Config.options.background.greeterWall
        : (page.greeterInfo?.background ?? "") !== "" ? page.greeterInfo.background : page.lockWallEffective

    // Written by the nixbook-shell.greeter NixOS module (greeter.nix): the
    // login screen follows this user's settings.
    property var greeterInfo: null
    readonly property bool greeterAvailable: page.greeterInfo !== null && page.greeterInfo.user === SystemInfo.username
    FileView {
        path: "/etc/nixbook-shell/greeter.json"
        onLoaded: {
            try {
                page.greeterInfo = JSON.parse(text());
            } catch (e) {
                page.greeterInfo = null;
            }
        }
    }

    component WallCard: ColumnLayout {
        id: card
        required property string target
        required property string icon
        required property string label
        required property string path
        property bool inherited: false
        property string inheritedText: ""
        readonly property bool locked: card.target !== "wallpaper" && NixManaged.isPinned(`background.${card.target}`)

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 6

        Rectangle {
            id: thumbBg
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: Appearance.rounding.large
            color: Appearance.colors.colSurfaceContainerHigh
            clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: thumbBg.width
                    height: thumbBg.height
                    radius: thumbBg.radius
                }
            }

            ThumbnailImage {
                anchors.fill: parent
                visible: card.path !== ""
                sourcePath: FileUtils.trimFileProtocol(page.displayPathFor(card.path))
                thumbnailSizeName: "x-large"
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: thumbBg.width * 1.5
                sourceSize.height: thumbBg.height * 1.5
                opacity: card.inherited ? 0.55 : 1
            }

            MouseArea {
                anchors.fill: parent
                enabled: !card.locked
                hoverEnabled: true
                cursorShape: card.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    GlobalStates.wallpaperSelectorTarget = card.target
                    GlobalStates.wallpaperSelectorOpen = true
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            MaterialSymbol {
                text: card.icon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: card.label
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            NixManagedBadge {
                pinned: card.locked
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: card.inherited ? card.inheritedText : card.path.split("/").pop()
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    function displayPathFor(path) {
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20
            
        ContentSection {
            icon: "panorama"
            title: Translation.tr("Wallpaper")
            shape: MaterialShape.Shape.Clover4Leaf

            // The desktop, lock screen and (with the nixbook-shell.greeter
            // NixOS module) login screen wallpapers: click one to choose it in
            // the wallpaper selector.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                WallCard {
                    target: "wallpaper"
                    icon: "desktop_windows"
                    label: Translation.tr("Desktop")
                    path: Config.options.background.wallpaperPath
                }
                WallCard {
                    target: "lockWall"
                    icon: "lock"
                    label: Translation.tr("Lock screen")
                    path: page.lockWallEffective
                    inherited: Config.options.background.lockWall === ""
                    inheritedText: Translation.tr("Same as the desktop")
                }
                WallCard {
                    visible: page.greeterAvailable
                    target: "greeterWall"
                    icon: "login"
                    label: Translation.tr("Login screen")
                    path: page.greeterWallEffective
                    inherited: Config.options.background.greeterWall === ""
                    inheritedText: (page.greeterInfo?.background ?? "") !== ""
                        ? Translation.tr("Set in Nix")
                        : Translation.tr("Same as the lock screen")
                }
            }

            GroupedList {
                Layout.topMargin: -2

                ConfigSwitch {
                    configKey: "background.lockWall";
                    enabled: !nixManaged;
                    id: syncWallpaperSwitch
                    buttonIcon: "sync"
                    text: Translation.tr("Lock screen uses the desktop wallpaper")
                    checked: Config.options.background.lockWall === ""
                    onCheckedChanged: {
                        if (checked) {
                            Config.options.background.lockWall = "";
                        }
                    }
                }

                ConfigSwitch {
                    configKey: "background.greeterWall";
                    enabled: !nixManaged;
                    shown: page.greeterAvailable
                    id: syncGreeterWallpaperSwitch
                    buttonIcon: "sync"
                    text: Translation.tr("Login screen uses the lock screen wallpaper")
                    checked: Config.options.background.greeterWall === ""
                    onCheckedChanged: {
                        if (checked) {
                            Config.options.background.greeterWall = "";
                        }
                    }
                }

                ConfigSwitch {
                    configKey: "background.enableWallpaperPreview";
                    enabled: !nixManaged;
                    buttonIcon: "preview"
                    text: Translation.tr("Preview wallpaper")
                    checked: Config.options.background.enableWallpaperPreview
                    onCheckedChanged: {
                        Config.options.background.enableWallpaperPreview = checked;
                    }
                }

                ConfigSwitch {
                    configKey: "background.showBlur";
                    enabled: !nixManaged;
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur wall")
                    checked: Config.options.background.showBlur
                    onCheckedChanged: {
                        Config.options.background.showBlur = checked;
                    }
                }

                ConfigSlider {
                    configKey: "background.blurRadius";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    text: Translation.tr("Blur Size")
                    value: Config.options.background.blurRadius ?? 32
                    usePercentTooltip: false
                    buttonIcon: "aspect_ratio"
                    from: 1
                    to: 64
                    stopIndicatorValues: [32]
                    onValueChanged: Config.options.background.blurRadius = value
                }

                ConfigSelectionArray {
                    configKey: "background.splitRatio";
                    enabled: !nixManaged;
                    text: Translation.tr("Split blur amount")
                    icon: "split_scene"
                    currentValue: Config.options.background.splitRatio
                    options: [
                        { "displayName": "25%",  "icon": "thumbnail_bar",              "value": "25" },
                        { "displayName": "50%",  "icon": "side_navigation",              "value": "50" },
                        { "displayName": "100%", "icon": "fullscreen",    "value": "100" },
                    ]
                    onSelected: newValue => {
                        Config.options.background.splitRatio = newValue
                    }
                }

                ConfigSelectionArray {
                    configKey: "background.splitSide";
                    enabled: !nixManaged;
                    text: Translation.tr("Split blur side")
                    icon: "align_horizontal_left"
                    currentValue: Config.options.background.splitSide
                    options: [
                        { "displayName": Translation.tr("Left"),  "icon": "align_horizontal_left",  "value": "left" },
                        { "displayName": Translation.tr("Right"), "icon": "align_horizontal_right", "value": "right" },
                    ]
                    onSelected: newValue => {
                        Config.options.background.splitSide = newValue
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

                ConfigComboBox {
                    configKey: "background.wallpaperAnimation";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    buttonIcon: "texture"
                    text: Translation.tr("Transitions")
                    fieldWidth: 50
                    model: [
                        { displayName: Translation.tr("None"), icon: "block", value: "" },
                        { displayName: Translation.tr("Circle"), icon: "circle", value: "circleSelect" },
                        { displayName: Translation.tr("Circle Pit"), icon: "blur_circular", value: "circlePit" },
                        { displayName: Translation.tr("Magic"), icon: "auto_awesome", value: "magic" },
                        { displayName: Translation.tr("Doom"), icon: "whatshot", value: "Doom" },
                        { displayName: Translation.tr("Peel"), icon: "layers", value: "Peel" },
                        { displayName: Translation.tr("Fade"), icon: "gradient", value: "transition" },
                        { displayName: Translation.tr("Pixelate"), icon: "grain", value: "pixelate" },
                        { displayName: Translation.tr("Stripes"), icon: "texture_minus", value: "stripes" },
                        { displayName: Translation.tr("CRT"), icon: "tv", value: "crt" },
                        { displayName: Translation.tr("Dissolve"), icon: "blur_on", value: "dissolve" },
                        { displayName: Translation.tr("Glitch"), icon: "bug_report", value: "glitch" },
                        { displayName: Translation.tr("Ripple"), icon: "water", value: "ripple" },
                        { displayName: Translation.tr("Shatter"), icon: "broken_image", value: "shatter" },
                        { displayName: Translation.tr("Random"), icon: "shuffle", value: "random" },
                    ]
                    currentValue: Config.options.background.wallpaperAnimation
                    onSelected: newValue => {
                        Config.options.background.wallpaperAnimation = newValue;
                    }
                }
            }

            Connections {
                target: Config.options.background
                function onLockWallChanged() {
                    syncWallpaperSwitch.checked = Qt.binding(() => Config.options.background.lockWall === "")
                }
                function onGreeterWallChanged() {
                    syncGreeterWallpaperSwitch.checked = Qt.binding(() => Config.options.background.greeterWall === "")
                }
            }
        
            ContentSubsection {
                title: Translation.tr("Centered wallpaper")
                Layout.fillWidth: true

                GroupedList {
                    ConfigSwitch {
                        configKey: "background.centeredWallpaper";
                        enabled: !nixManaged;
                        Layout.fillWidth: true
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.centeredWallpaper
                        onClicked: {
                            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper;
                        }
                    }
                }

                GroupedList {
                    Layout.topMargin: 0
                    shown: Config.options.background.centeredWallpaper
                    ConfigSelectionShapeArray {
                        configKey: "background.centeredWallpaperShape";
                        enabled: !nixManaged;
                        currentValue: Config.options.background.centeredWallpaperShape
                        shapeColor: Appearance.colors.colPrimary
                        backgroundColor: Appearance.colors.colPrimaryContainer
                        options: [
                            "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                            "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                            "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                            "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                            "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                        ]
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperShape = newValue
                        }
                    }
                    ColorSelectionArray {
                        configKey: "background.centeredWallpaperColor";
                        enabled: !nixManaged;
                        shown: Config.options.background.centeredWallpaper
                        icon: "palette"
                        text: Translation.tr("Background Color")
                        currentValue: Config.options.background.centeredWallpaperColor
                        onSelected: newValue => {
                            Config.options.background.centeredWallpaperColor = newValue
                        }
                    }
                    ConfigSlider {
                        configKey: "background.centeredWallpaperSize";
                        enabled: !nixManaged;
                        shown: Config.options.background.centeredWallpaper
                        text: Translation.tr("Size")
                        value: Config.options.background.centeredWallpaperSize
                        usePercentTooltip: false
                        buttonIcon: "aspect_ratio"
                        from: 400
                        to: 800
                        stopIndicatorValues: [400]
                        onValueChanged: {
                            Config.options.background.centeredWallpaperSize = value;
                        }
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
            id: settingsClock
            icon: "clock_loader_40"
            shape: MaterialShape.Shape.Bun
            title: Translation.tr("Clock")

            function stylePresent(styleName) {
                if (!Config.options.background.widgets.clock.showOnlyWhenLocked && Config.options.background.widgets.clock.style === styleName) {
                    return true;
                }
                if (Config.options.background.widgets.clock.styleLocked === styleName) {
                    return true;
                }
                return false;
            }

            readonly property bool digitalPresent: stylePresent("digital")
            readonly property bool cookiePresent: stylePresent("cookie")

            GroupedList {
                ConfigSwitch {
                    configKey: "background.widgets.clock.enable";
                    enabled: !nixManaged;
                    Layout.fillWidth: false
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.clock.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.enable = checked;
                    }
                }

                ConfigSelectionArray {
                    configKey: "background.widgets.clock.placementStrategy";
                    enabled: !nixManaged;
                    text: Translation.tr("Placement strategy")
                    icon: "move"
                    Layout.fillWidth: false
                    currentValue: Config.options.background.widgets.clock.placementStrategy
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.placementStrategy = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Draggable"),
                            icon: "drag_pan",
                            value: "free"
                        },
                        {
                            displayName: Translation.tr("Least busy"),
                            icon: "category",
                            value: "leastBusy"
                        },
                        {
                            displayName: Translation.tr("Most busy"),
                            icon: "shapes",
                            value: "mostBusy"
                        },
                    ]
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.style";
                    enabled: !nixManaged;
                    text: Translation.tr("Clock style")
                    icon: "nest_clock_farsight_analog"
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_view",
                            value: "pixel"
                        }
                    ]
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.styleLocked";
                    enabled: !nixManaged;
                    text: Translation.tr("Clock style (locked)")
                    icon: "shield_watch"
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_view",
                            value: "pixel"
                        }
                    ]
                }
            }

            ContentSubsection {
                shown: settingsClock.digitalPresent
                title: Translation.tr("Digital clock settings")

                ConfigRow {
                    uniform: true

                    GroupedList {
                        ConfigSwitch {
                            configKey: "background.widgets.clock.digital.vertical";
                            enabled: !nixManaged;
                            buttonIcon: "vertical_distribute"
                            text: Translation.tr("Vertical")
                            checked: Config.options.background.widgets.clock.digital.vertical
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.vertical = checked }
                        }
                        ConfigSwitch {
                            configKey: "background.widgets.clock.digital.showDate";
                            enabled: !nixManaged;
                            buttonIcon: "date_range"
                            text: Translation.tr("Show date")
                            checked: Config.options.background.widgets.clock.digital.showDate
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.showDate = checked }
                        }
                    }

                    GroupedList {
                        ConfigSwitch {
                            configKey: "background.widgets.clock.digital.animateChange";
                            enabled: !nixManaged;
                            buttonIcon: "animation"
                            text: Translation.tr("Animate time change")
                            checked: Config.options.background.widgets.clock.digital.animateChange
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.animateChange = checked }
                        }
                        ConfigSwitch {
                            configKey: "background.widgets.clock.digital.adaptiveAlignment";
                            enabled: !nixManaged;
                            buttonIcon: "activity_zone"
                            text: Translation.tr("Use adaptive alignment")
                            checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                            onCheckedChanged: { Config.options.background.widgets.clock.digital.adaptiveAlignment = checked }
                        }
                    }
                }

                GroupedList {
                    ConfigSwitch {
                        configKey: "background.widgets.clock.color";
                        enabled: !nixManaged;
                        id: autoColorSwitch
                        buttonIcon: "auto_awesome"
                        text: Translation.tr("Automatic colors")
                        checked: Config.options.background.widgets.clock.color === ""
                        onCheckedChanged: {
                            if (checked) {
                                Config.options.background.widgets.clock.color = ""
                            }
                        }
                    }

                    ColorSelectionArray {
                        configKey: "background.widgets.clock.color";
                        enabled: !nixManaged;
                        icon: "palette"
                        text: Translation.tr("Color")
                        currentValue: Config.options.background.widgets.clock.color
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.color = newValue
                            autoColorSwitch.checked = false
                        }
                    }
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Font family")
                    text: Config.options.background.widgets.clock.digital.font.family
                    wrapMode: TextEdit.Wrap

                    Timer {
                        id: debounceTimer
                        interval: 500
                        repeat: false
                        onTriggered: {
                            Config.options.background.widgets.clock.digital.font.family = parent.text
                        }
                    }

                    onTextChanged: {
                        debounceTimer.restart()
                    }
                }
                GroupedList {
                    Layout.topMargin: 10
                    ConfigSlider {
                        configKey: "background.widgets.clock.digital.font.weight";
                        enabled: !nixManaged;
                        text: Translation.tr("Font weight")
                        value: Config.options.background.widgets.clock.digital.font.weight
                        usePercentTooltip: false
                        buttonIcon: "format_bold"
                        from: 1
                        to: 1000
                        stopIndicatorValues: [350]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.weight = value;
                        }
                    }

                    ConfigSlider {
                        configKey: "background.widgets.clock.digital.font.size";
                        enabled: !nixManaged;
                        text: Translation.tr("Font size")
                        value: Config.options.background.widgets.clock.digital.font.size
                        usePercentTooltip: false
                        buttonIcon: "format_size"
                        from: 50
                        to: 700
                        stopIndicatorValues: [90]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.size = value;
                        }
                    }

                    ConfigSlider {
                        configKey: "background.widgets.clock.digital.font.width";
                        enabled: !nixManaged;
                        text: Translation.tr("Font width")
                        value: Config.options.background.widgets.clock.digital.font.width
                        usePercentTooltip: false
                        buttonIcon: "fit_width"
                        from: 25
                        to: 125
                        stopIndicatorValues: [100]
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.width = value;
                        }
                    }
                    ConfigSlider {
                        configKey: "background.widgets.clock.digital.font.roundness";
                        enabled: !nixManaged;
                        text: Translation.tr("Font roundness")
                        value: Config.options.background.widgets.clock.digital.font.roundness
                        usePercentTooltip: false
                        buttonIcon: "line_curve"
                        from: 0
                        to: 100
                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.roundness = value;
                        }
                    }
                }
            }

            ContentSubsection {
                shown: settingsClock.cookiePresent
                title: Translation.tr("Cookie clock settings")
                GroupedList {   
                    ConfigSwitch {  
                        configKey: "background.widgets.clock.cookie.aiStyling";
                        enabled: !nixManaged;
                        buttonIcon: "wand_stars"
                        text: Translation.tr("Auto styling with Gemini")
                        checked: Config.options.background.widgets.clock.cookie.aiStyling
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.aiStyling = checked;
                        }
                    }

                    ConfigSwitch {
                        configKey: "background.widgets.clock.cookie.useSineCookie";
                        enabled: !nixManaged;
                        buttonIcon: "airwave"
                        text: Translation.tr("Use old sine wave cookie implementation")
                        checked: Config.options.background.widgets.clock.cookie.useSineCookie
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.useSineCookie = checked;
                        }
                    }

                    ConfigSpinBox {
                        configKey: "background.widgets.clock.cookie.sides";
                        enabled: !nixManaged;
                        icon: "add_triangle"
                        text: Translation.tr("Sides")
                        value: Config.options.background.widgets.clock.cookie.sides
                        from: 0
                        to: 40
                        stepSize: 1
                        onValueChanged: {
                            Config.options.background.widgets.clock.cookie.sides = value;
                        }
                    }

                    ConfigSwitch {
                        configKey: "background.widgets.clock.cookie.constantlyRotate";
                        enabled: !nixManaged;
                        buttonIcon: "autoplay"
                        text: Translation.tr("Constantly rotate")
                        checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                        }
                    }

                    ConfigRow {

                        ConfigSwitch {
                            configKey: "background.widgets.clock.cookie.hourMarks";
                            enabled: (Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full") && !nixManaged
                            buttonIcon: "brightness_7"
                            text: Translation.tr("Hour marks")
                            checked: Config.options.background.widgets.clock.cookie.hourMarks
                            onEnabledChanged: {
                                checked = Config.options.background.widgets.clock.cookie.hourMarks;
                            }
                            onCheckedChanged: {
                                Config.options.background.widgets.clock.cookie.hourMarks = checked;
                            }
                        }

                        ConfigSwitch {
                            configKey: "background.widgets.clock.cookie.timeIndicators";
                            enabled: (Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers") && !nixManaged
                            buttonIcon: "timer_10"
                            text: Translation.tr("Digits in the middle")
                            checked: Config.options.background.widgets.clock.cookie.timeIndicators
                            onEnabledChanged: {
                                checked = Config.options.background.widgets.clock.cookie.timeIndicators;
                            }
                            onCheckedChanged: {
                                Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                            }
                        }
                    }
                }
            }

            GroupedList {
                Layout.topMargin: 10
                shown: settingsClock.cookiePresent
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.cookie.dialNumberStyle";
                    enabled: !nixManaged;
                    text: "Dial Style"
                    icon: "graph_6"
                    currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
                        if (newValue !== "dots" && newValue !== "full") {
                            Config.options.background.widgets.clock.cookie.hourMarks = false;
                        }
                        if (newValue === "numbers") {
                            Config.options.background.widgets.clock.cookie.timeIndicators = false;
                        }
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "none"
                        },
                        {
                            displayName: Translation.tr("Dots"),
                            icon: "graph_6",
                            value: "dots"
                        },
                        {
                            displayName: Translation.tr("Full"),
                            icon: "history_toggle_off",
                            value: "full"
                        },
                        {
                            displayName: Translation.tr("Numbers"),
                            icon: "counter_1",
                            value: "numbers"
                        }
                    ]
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.cookie.hourHandStyle";
                    enabled: !nixManaged;
                    icon: "highlighter_size_2"
                    text: Translation.tr("Hour hand")
                    currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hollow"),
                            icon: "circle",
                            value: "hollow"
                        },
                        {
                            displayName: Translation.tr("Fill"),
                            icon: "eraser_size_5",
                            value: "fill"
                        },
                    ]
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.cookie.minuteHandStyle";
                    enabled: !nixManaged;
                    text: Translation.tr("Minute hand")
                    icon: "eraser_size_1" 
                    currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Thin"),
                            icon: "line_end",
                            value: "thin"
                        },
                        {
                            displayName: Translation.tr("Medium"),
                            icon: "eraser_size_2",
                            value: "medium"
                        },
                        {
                            displayName: Translation.tr("Bold"),
                            icon: "eraser_size_4",
                            value: "bold"
                        },
                    ]
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.cookie.secondHandStyle";
                    enabled: !nixManaged;
                    text: Translation.tr("Second hand")
                    icon: "pen_size_1"
                    currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "radio",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Line"),
                            icon: "line_end",
                            value: "line"
                        },
                        {
                            displayName: Translation.tr("Dot"),
                            icon: "adjust",
                            value: "dot"
                        },
                    ]
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.clock.cookie.dateStyle";
                    enabled: !nixManaged;
                    text: Translation.tr("Date style")
                    icon: "date_range"
                    currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.dateStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Bubble"),
                            icon: "bubble_chart",
                            value: "bubble"
                        },
                        {
                            displayName: Translation.tr("Border"),
                            icon: "rotate_right",
                            value: "border"
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "rectangle",
                            value: "rect"
                        }
                    ]
                }
            }
            
            ContentSubsection {
                shown: Config.options.background.widgets.clock.style === "pixel"
                title: Translation.tr("Pixel Clock Settings")
                GroupedList {
                    shown: Config.options.background.widgets.clock.style === "pixel"
                    ConfigSelectionArray {
                        configKey: "background.widgets.clock.pixel.orientation";
                        enabled: !nixManaged;
                        text: Translation.tr("Pixel clock orientation")
                        shown: Config.options.background.widgets.clock.style === "pixel"
                        icon: "screen_rotation"
                        currentValue: Config.options.background.widgets.clock.pixel.orientation
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.pixel.orientation = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Horizontal"),
                                icon: "swap_horiz",
                                value: "horizontal"
                            },
                            {
                                displayName: Translation.tr("Vertical"),
                                icon: "swap_vert",
                                value: "vertical"
                            }
                        ]
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Quote")
                GroupedList {
                    ConfigSwitch {
                        configKey: "background.widgets.clock.quote.enable";
                        enabled: !nixManaged;
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.background.widgets.clock.quote.enable
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.quote.enable = checked;
                        }
                    }
                    ConfigSwitch {
                        configKey: "background.widgets.clock.quote.followClock";
                        buttonIcon: "font_download"
                        text: Translation.tr("Follow Clock Font")
                        enabled: (Config.options.background.widgets.clock.style !== "pixel") && !nixManaged
                        checked: Config.options.background.widgets.clock.quote.followClock
                        onCheckedChanged: {
                            Config.options.background.widgets.clock.quote.followClock = checked;
                        }
                    }
                    ConfigTextArea {
                        configKey: "background.widgets.clock.quote.text";
                        enabled: !nixManaged;
                        id: quoteField
                        Layout.fillWidth: true
                        fieldWidth: 300
                        buttonIcon: "format_quote"
                        text: Translation.tr("Quote")
                        placeholderText: Translation.tr("Quote")
                        value: Config.options.background.widgets.clock.quote.text
                        onValueChanged: {
                            quoteDebounceTimer.restart();
                        }

                        Timer {
                            id: quoteDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.background.widgets.clock.quote.text = quoteField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "panorama"
            shape: MaterialShape.Shape.SoftBoom 
            title: Translation.tr("Custom Image")
            GroupedList {
                ConfigSwitch {
                    configKey: "background.widgets.customImage.enable";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.customImage.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.customImage.enable = checked;
                    }
                }
                ConfigSelectionShapeArray {
                    configKey: "background.widgets.customImage.shape";
                    enabled: !nixManaged;
                    currentValue: Config.options.background.widgets.customImage.shape
                    shapeColor: Appearance.colors.colPrimary
                    backgroundColor: Appearance.colors.colPrimaryContainer
                    options: [
                        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                    ]
                    onSelected: newValue => {
                        Config.options.background.widgets.customImage.shape = newValue
                    }
                }
            }
        }

                ContentSection {
            id: settingsVisualizer
            icon: "graphic_eq"
            shape: MaterialShape.Shape.Burst
            title: Translation.tr("Visualizer")

            readonly property var entry: Config.options.background.widgets.visualizer
            readonly property bool bandStyle: ["mirror", "aurora", "dots"].includes(entry.style)

            GroupedList {
                ConfigSwitch {
                    configKey: "background.widgets.visualizer.enable"
                    Layout.fillWidth: true
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: settingsVisualizer.entry.enable
                    onCheckedChanged: {
                        settingsVisualizer.entry.enable = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "background.widgets.visualizer.pauseBehindWindows"
                    Layout.fillWidth: true
                    buttonIcon: "energy_savings_leaf"
                    text: Translation.tr("Pause while windows cover the desktop")
                    checked: settingsVisualizer.entry.pauseBehindWindows
                    onCheckedChanged: settingsVisualizer.entry.pauseBehindWindows = checked
                }
                ConfigSelectionArray {
                    configKey: "background.widgets.visualizer.style"
                    text: Translation.tr("Style")
                    icon: "style"
                    currentValue: settingsVisualizer.entry.style
                    onSelected: newValue => {
                        settingsVisualizer.entry.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "bar_chart",
                            value: "bars"
                        },
                        {
                            displayName: Translation.tr("Mirror"),
                            icon: "equalizer",
                            value: "mirror"
                        },
                        {
                            displayName: Translation.tr("Aurora"),
                            icon: "waves",
                            value: "aurora"
                        },
                        {
                            displayName: Translation.tr("Ring"),
                            icon: "album",
                            value: "ring"
                        },
                        {
                            displayName: Translation.tr("Dots"),
                            icon: "grid_on",
                            value: "dots"
                        }
                    ]
                }

                ConfigSelectionArray {

                    configKey: "background.widgets.visualizer.colorSource"
                    text: Translation.tr("Colors")
                    icon: "palette"
                    enabled: settingsVisualizer.entry.style !== "bars"
                    currentValue: settingsVisualizer.entry.colorSource
                    onSelected: newValue => {
                        settingsVisualizer.entry.colorSource = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Theme"),
                            icon: "palette",
                            value: "theme"
                        },
                        {
                            displayName: Translation.tr("Album cover"),
                            icon: "album",
                            value: "cover"
                        }
                    ]
                }
        
                ConfigSlider {
        
                    configKey: "background.widgets.visualizer.sensitivity"
                    text: Translation.tr("Sensitivity (%)")
                    buttonIcon: "tune"
                    usePercentTooltip: false
                    enabled: settingsVisualizer.entry.style !== "bars"
                    value: settingsVisualizer.entry.sensitivity * 100
                    from: 50
                    to: 300
                    stopIndicatorValues: [100]
                    onValueChanged: {
                        settingsVisualizer.entry.sensitivity = Math.round(value) / 100;
                    }
                }
                ConfigSlider {
                    configKey: "background.widgets.visualizer.height"
                    text: Translation.tr("Height")
                    buttonIcon: "height"
                    usePercentTooltip: false
                    enabled: settingsVisualizer.entry.style !== "bars" && settingsVisualizer.bandStyle
                    value: settingsVisualizer.entry.height
                    from: 120
                    to: 600
                    stopIndicatorValues: [260]
                    onValueChanged: {
                        settingsVisualizer.entry.height = Math.round(value);
                    }
                }
                ConfigSlider {
                    configKey: "background.widgets.visualizer.ringSize"
                    text: Translation.tr("Size")
                    buttonIcon: "aspect_ratio"
                    usePercentTooltip: false
                    enabled: settingsVisualizer.entry.style === "ring"
                    value: settingsVisualizer.entry.ringSize
                    from: 200
                    to: 900
                    stopIndicatorValues: [380]
                    onValueChanged: {
                        settingsVisualizer.entry.ringSize = Math.round(value);
                    }
                }
            }
        }

        ContentSection {
            id: settingsCustomText
            icon: "text_fields"
            shape: MaterialShape.Shape.Cookie4Sided
            title: Translation.tr("Text")

            readonly property var entry: Config.options.background.widgets.customText

            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: settingsCustomText.entry.enable
                    onCheckedChanged: {
                        settingsCustomText.entry.enable = checked;
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "shadow"
                    text: Translation.tr("Shadow")
                    checked: settingsCustomText.entry.shadow
                    onCheckedChanged: {
                        settingsCustomText.entry.shadow = checked;
                    }
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "touch_app"
                text: Translation.tr("Double-click the text on your desktop to edit it, drag its corner to resize it")
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Text to display")
                text: settingsCustomText.entry.content
                wrapMode: TextEdit.Wrap

                Timer {
                    id: customTextContentDebounce
                    interval: 500
                    repeat: false
                    onTriggered: {
                        settingsCustomText.entry.content = parent.text
                    }
                }

                onTextChanged: {
                    if (activeFocus) customTextContentDebounce.restart()
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: Translation.tr("Font")

                GroupedList {
                    ConfigComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "font_download"
                        fieldWidth: 50
                        text: Translation.tr("Font family")
                        textRole: "displayName"
                        model: Fonts.handwritingFamilies.map(family => ({
                            displayName: family,
                            value: family
                        }))
                        currentValue: settingsCustomText.entry.fontFamily
                        onSelected: newValue => { settingsCustomText.entry.fontFamily = newValue; }
                    }
                    ConfigTextArea {
                        id: settingsCustomFontField
                        buttonIcon: "custom_typography"
                        text: Translation.tr("Custom Font")
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        placeholderText: Translation.tr("Any installed font family")
                        value: Fonts.handwritingFamilies.includes(settingsCustomText.entry.fontFamily) ? "" : settingsCustomText.entry.fontFamily

                        onValueChanged: {
                            customTextFontDebounce.restart();
                        }

                        Timer {
                            id: customTextFontDebounce
                            interval: 500
                            repeat: false
                            onTriggered: {
                                if (settingsCustomFontField.value.trim() !== "")
                                    settingsCustomText.entry.fontFamily = settingsCustomFontField.value.trim()
                            }
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Font size")
                        value: settingsCustomText.entry.fontSize
                        usePercentTooltip: false
                        buttonIcon: "format_size"
                        from: 12
                        to: 400
                        stopIndicatorValues: [72]
                        onValueChanged: {
                            settingsCustomText.entry.fontSize = Math.round(value);
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Alignment")
                        icon: "format_align_center"
                        currentValue: settingsCustomText.entry.alignment
                        onSelected: newValue => {
                            settingsCustomText.entry.alignment = newValue;
                        }
                        options: [
                            {
                                displayName: Translation.tr("Left"),
                                icon: "format_align_left",
                                value: "left"
                            },
                            {
                                displayName: Translation.tr("Center"),
                                icon: "format_align_center",
                                value: "center"
                            },
                            {
                                displayName: Translation.tr("Right"),
                                icon: "format_align_right",
                                value: "right"
                            }
                        ]
                    }
                }
            }

            ContentSubsection {
                Layout.topMargin: 10
                title: Translation.tr("Colors")
                
                GroupedList {
                    ConfigSwitch {
                        id: customTextAutoColorSwitch
                        buttonIcon: "auto_awesome"
                        text: Translation.tr("Automatic colors")
                        checked: settingsCustomText.entry.color === ""
                        onCheckedChanged: {
                            if (checked) {
                                settingsCustomText.entry.color = ""
                            }
                        }
                    }

                    ColorSelectionArray {
                        icon: "palette"
                        text: Translation.tr("Color")
                        currentValue: settingsCustomText.entry.color
                        onSelected: newValue => {
                            settingsCustomText.entry.color = newValue
                            customTextAutoColorSwitch.checked = false
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "widgets"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Widgets")

            ContentSubsection {
                title: Translation.tr("Show widgets on")
                shown: Quickshell.screens.length > 1
                Layout.bottomMargin: 10

                WidgetsMonitorSelector {
                    configEntry: Config.options.background
                    configKey: "background.screenList"
                }
            }
            
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: [
                        {
                            icon: "weather_mix",
                            name: Translation.tr("Weather"),
                            key: "weather",
                            enabled: Config.options.background.widgets.weather.enable
                        },
                        {
                            icon: "image",
                            name: Translation.tr("Image converter"),
                            key: "images",
                            enabled: Config.options.background.widgets.images.enable
                        },
                        {
                            icon: "music_note",
                            name: Translation.tr("Media Player"),
                            key: "media",
                            enabled: Config.options.background.widgets.media.enable
                        },
                        {
                            icon: "memory",
                            name: Translation.tr("Resources"),
                            key: "resources",
                            enabled: Config.options.background.widgets.resources.enable
                        },
                        {
                            icon: "calendar_month",
                            name: Translation.tr("Calendar"),
                            key: "calendar",
                            enabled: Config.options.background.widgets.calendar.enable
                        },
                        {
                            icon: "event_upcoming",
                            name: Translation.tr("Next Event"),
                            key: "nextEvent",
                            enabled: Config.options.background.widgets.nextEvent.enable
                        },
                        {
                            icon: "public",
                            name: Translation.tr("World Clock"),
                            key: "worldClock",
                            enabled: Config.options.background.widgets.worldClock.enable
                        },
                        {
                            icon: "person",
                            name: Translation.tr("User Card"),
                            key: "userCard",
                            enabled: Config.options.background.widgets.userCard.enable
                        },
                        {
                            icon: "note_stack_add",
                            name: Translation.tr("Notes"),
                            key: "notes",
                            enabled: Config.options.background.widgets.notes.enable
                        },
                        {
                            icon: "add_task",
                            name: Translation.tr("To-Do"),
                            key: "todo",
                            enabled: Config.options.background.widgets.todo.enable
                        },
                        {
                            icon: "timer",
                            name: Translation.tr("Timers"),
                            key: "timers",
                            enabled: Config.options.background.widgets.timers.enable
                        },
                        {
                            icon: "sticker",
                            name: Translation.tr("Sticker"),
                            key: "sticker",
                            enabled: Config.options.background.widgets.sticker.enable
                        },
                        
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 105
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal + 5
                                    color: Appearance.colors.colPrimary
                                }
                                Item { Layout.fillWidth: true }
                                ConfigSwitch {
                                    configKey: `background.widgets.${modelData.key}.enable`;
                                    enabled: !nixManaged;
                                    Layout.fillWidth: false
                                    checked: modelData.enabled
                                    onCheckedChanged: Config.options.background.widgets[modelData.key].enable = checked
                                }
                            }
                            StyledText {
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: modelData.enabled ? Translation.tr("Enabled") : Translation.tr("Disabled")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Canvas")
                Layout.bottomMargin: 10

                GroupedList {
                    ConfigSwitch {
                        configKey: "background.showGrid";
                        enabled: !nixManaged;
                        Layout.fillWidth: true
                        buttonIcon: "grid_4x4"
                        text: Translation.tr("Show alignment grid while dragging")
                        checked: Config.options.background.showGrid
                        onCheckedChanged: {
                            Config.options.background.showGrid = checked;
                        }
                    }
                    ConfigSwitch {
                        configKey: "background.showSnapLines";
                        enabled: !nixManaged;
                        Layout.fillWidth: true
                        buttonIcon: "align_horizontal_center"
                        text: Translation.tr("Show snap lines when dropping")
                        checked: Config.options.background.showSnapLines
                        onCheckedChanged: {
                            Config.options.background.showSnapLines = checked;
                        }
                    }
                }
                ConfigSlider {
                    configKey: "background.widgets.cardOpacity";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    text: Translation.tr("Widget background opacity")
                    buttonIcon: "opacity"
                    value: Config.options.background.widgets.cardOpacity ?? 0.75
                    usePercentTooltip: true
                    from: 0.2
                    to: 1
                    stopIndicatorValues: [0.75]
                    onValueChanged: Config.options.background.widgets.cardOpacity = value
                }
            }
        }
    }
}
