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
    }
}
