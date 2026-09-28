import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.settings.pages
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Item {
    id: root
    property real contentPadding: 10
    property int currentPage: 0
    property bool showingProfile: false
    property bool isMinimal: Config.options.settings.style === "minimal"
    // Icon-only sidebar when the window is narrow (or in the minimal style).
    readonly property bool railExpanded: !isMinimal && root.width > 860

    Connections {
        target: GlobalStates
        function onSettingsPageChanged() {
            if (GlobalStates.settingsPage === "") return

            let parts = GlobalStates.settingsPage.split(":");
            let pageName = parts[0];
            let searchTerm = parts.length > 1 ? parts[1] : "";

            const idx = root.pages.findIndex(p => p.name.toLowerCase() === pageName.toLowerCase());

            if (idx >= 0) {
                root.currentPage = idx;
                root.showingProfile = false;

                if (searchTerm !== "") {
                    let loader = pagesRepeater.itemAt(idx);
                    if (loader && loader.item && typeof loader.item.goTo === "function") {
                        loader.item.goTo(searchTerm);
                    } else if (loader) {
                        loader.onLoaded.connect(function() {
                            if (loader.item && typeof loader.item.goTo === "function") {
                                loader.item.goTo(searchTerm);
                            }
                        });
                    }
                }
            }
            GlobalStates.settingsPage = "";
        }
    }

    onCurrentPageChanged: {
        const pageName = root.pages[currentPage]?.name ?? ""
        if (pageName === Translation.tr("About")) {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            UpdateState.checkUpdate()
        }
    }

    // Sidebar groups, in display order. Pages without a group (About) sit at
    // the bottom of the sidebar. The order of `pages` is also the Tab order,
    // and the names are what LauncherSearch's settingsIndex refers to.
    readonly property var groups: [
        { id: "personalize", name: Translation.tr("Personalize") },
        { id: "shell",       name: Translation.tr("Shell") },
        { id: "system",      name: Translation.tr("System") },
    ]

    property var pages: {
        let list = [
            { group: "personalize", name: Translation.tr("Quick"),       icon: "instant_mix",    description: Translation.tr("Wallpaper, colors and the most used toggles"), component: Qt.resolvedUrl("pages/QuickConfig.qml") },
            { group: "personalize", name: Translation.tr("Appearance"),  icon: "palette",        description: Translation.tr("Color generation, transparency, fonts and style"), component: Qt.resolvedUrl("pages/AppearanceConfig.qml") },
            { group: "personalize", name: Translation.tr("Desktop"),     icon: "texture",        description: Translation.tr("Wallpaper, clock and desktop widgets"), component: Qt.resolvedUrl("pages/BackgroundConfig.qml") },
            { group: "personalize", name: Translation.tr("Bar"),         icon: "toast",          iconRotation: 180, description: Translation.tr("Layout, bar widgets and notifications"), component: Qt.resolvedUrl("pages/BarConfig.qml") },
            { group: "shell",       name: Translation.tr("Panels"),      icon: "bottom_app_bar", description: Translation.tr("Overview, sidebars, dock, on-screen display and overlays"), component: Qt.resolvedUrl("pages/PanelsConfig.qml") },
            { group: "shell",       name: Translation.tr("Lock screen"), icon: "lock",           description: Translation.tr("Locking, security and lock screen style"), component: Qt.resolvedUrl("pages/LockScreenConfig.qml") },
            { group: "system",      name: Translation.tr("General"),     icon: "tune",           description: Translation.tr("Time, battery, audio, sounds and language"), component: Qt.resolvedUrl("pages/GeneralConfig.qml") },
            { group: "system",      name: Translation.tr("Services"),    icon: "hub",            description: Translation.tr("AI, networking, search, updates and weather"), component: Qt.resolvedUrl("pages/ServicesConfig.qml") },
        ]
        if (WM.compositor === "hyprland") {
            list.push({ group: "system", name: Translation.tr("Hyprland"), icon: "select_window_2", description: Translation.tr("Displays, input, idle and animations"), component: Qt.resolvedUrl("pages/HyprlandConfig.qml") })
        }
        if (WM.compositor === "niri") {
            list.push({ group: "system", name: Translation.tr("Niri"), icon: "select_window_2", description: Translation.tr("Displays, input, layout and animations"), component: Qt.resolvedUrl("pages/NiriConfig.qml") })
        }
        list.push({ group: "", name: Translation.tr("About"), icon: "info", description: Translation.tr("System information and updates"), component: Qt.resolvedUrl("pages/About.qml") })
        return list
    }

    readonly property var currentEntry: root.showingProfile
        ? { name: Translation.tr("Profile"), icon: "account_circle", description: Translation.tr("Avatar, identity and presets") }
        : (root.pages[root.currentPage] ?? { name: "", icon: "", description: "" })

    // Settings on the visible page, and how many of them are locked (managed
    // outside the shell, see NixManaged) — hidden by the "Editable only" filter.
    readonly property var pinnedTally: {
        const page = GlobalStates.currentPageInstance;
        if (!page || NixManaged.pinned.length === 0) return { total: 0, pinned: 0 };
        let total = 0, pinned = 0;
        const walk = item => {
            if (!item) return;
            if (item.nixManaged !== undefined && item.filteredOut !== undefined) {
                total++;
                if (item.nixManaged) pinned++;
                return;
            }
            const kids = item.children;
            if (kids) for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(page.contentItem ?? page);
        return { total: total, pinned: pinned };
    }

    Component.onCompleted: {
        Config.readWriteDelay = 0
        Qt.callLater(() => {
            for (let i = 0; i < root.pages.length; i++) {
                let loader = pagesRepeater.itemAt(i)
                if (loader) loader.active = true
            }
            if (profileLoader) profileLoader.active = true
        })
    }

    // One sidebar entry: icon + label, pill-shaped highlight when selected.
    component NavItem: RippleButton {
        id: navItem
        property string navIcon
        property real navIconRotation: 0
        property string navLabel
        Layout.fillWidth: true
        implicitHeight: root.isMinimal ? 42 : 46
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colLayer1Active
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: RowLayout {
            spacing: 12
            MaterialSymbol {
                Layout.leftMargin: root.railExpanded ? 14 : 0
                Layout.alignment: root.railExpanded ? Qt.AlignVCenter : Qt.AlignCenter
                Layout.fillWidth: !root.railExpanded
                horizontalAlignment: Text.AlignHCenter
                text: navItem.navIcon
                rotation: navItem.navIconRotation
                iconSize: 22
                fill: navItem.toggled ? 1 : 0
                color: navItem.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: root.railExpanded
                Layout.fillWidth: true
                text: navItem.navLabel
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: navItem.toggled ? Font.DemiBold : Font.Normal
                color: navItem.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
            }
        }

        StyledToolTip {
            extraVisibleCondition: !root.railExpanded
            text: navItem.navLabel
        }
    }

    RowLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        // ------------------------------------------------------------ sidebar
        Rectangle {
            id: sidebar
            Layout.fillHeight: true
            implicitWidth: root.railExpanded ? 236 : 68
            color: root.isMinimal ? "transparent" : Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            clip: true

            Behavior on implicitWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 10
                }
                spacing: 4

                // Profile card: opens the profile page (avatar, identity, presets)
                RippleButton {
                    id: profileCard
                    Layout.fillWidth: true
                    implicitHeight: 60
                    buttonRadius: Appearance.rounding.normal
                    toggled: root.showingProfile
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colLayer1Active
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.showingProfile = !root.showingProfile

                    contentItem: RowLayout {
                        spacing: 10

                        Rectangle {
                            id: avatarRect
                            Layout.leftMargin: root.railExpanded ? 6 : 0
                            Layout.alignment: root.railExpanded ? Qt.AlignVCenter : Qt.AlignCenter
                            Layout.fillWidth: false
                            implicitWidth: root.railExpanded ? 44 : 40
                            implicitHeight: implicitWidth
                            radius: width / 2
                            color: Appearance.colors.colPrimaryContainer

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: UserAvatar.source // AccountsService account picture (services/UserAvatar.qml)
                                sourceSize.width: avatarImage.width * 2
                                sourceSize.height: avatarImage.height * 2
                                fillMode: Image.PreserveAspectCrop
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: avatarRect.width
                                        height: avatarRect.height
                                        radius: avatarRect.radius
                                    }
                                }
                                onStatusChanged: {
                                    if (status === Image.Error)
                                        visible = false
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "account_circle"
                                iconSize: 30
                                color: Appearance.colors.colOnPrimaryContainer
                                visible: avatarImage.status === Image.Error
                            }
                        }

                        ColumnLayout {
                            visible: root.railExpanded
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: root.showingProfile ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                text: {
                                    const d = Config.options.profile.descriptionText
                                    if (d === "::uptime::") return Translation.tr("Up • %1").arg(DateTime.uptime)
                                    return SystemInfo.distroName
                                }
                            }
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: !root.railExpanded
                        text: Translation.tr("Profile")
                    }
                }

                // Page list, grouped. Scrolls when the window is short.
                StyledFlickable {
                    id: navFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    clip: true
                    contentHeight: navColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: navColumn
                        width: navFlick.width
                        spacing: 2

                        Repeater {
                            model: root.groups
                            ColumnLayout {
                                id: groupColumn
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 2

                                // Group heading (a thin divider when collapsed)
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: root.railExpanded ? groupLabel.implicitHeight + (groupColumn.index === 0 ? 6 : 16) : 13
                                    StyledText {
                                        id: groupLabel
                                        visible: root.railExpanded
                                        anchors {
                                            left: parent.left
                                            leftMargin: 16
                                            bottom: parent.bottom
                                            bottomMargin: 4
                                        }
                                        text: groupColumn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colSubtext
                                    }
                                    Rectangle {
                                        visible: !root.railExpanded && groupColumn.index > 0
                                        anchors.centerIn: parent
                                        width: parent.width - 16
                                        height: 1
                                        color: Appearance.colors.colOutlineVariant
                                    }
                                }

                                Repeater {
                                    model: root.pages.map((p, i) => ({ page: p, index: i })).filter(e => e.page.group === groupColumn.modelData.id)
                                    NavItem {
                                        required property var modelData
                                        navIcon: modelData.page.icon
                                        navIconRotation: modelData.page.iconRotation ?? 0
                                        navLabel: modelData.page.name
                                        toggled: root.currentPage === modelData.index && !root.showingProfile
                                        onClicked: {
                                            root.currentPage = modelData.index
                                            root.showingProfile = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom: ungrouped pages (About) and the config file shortcut
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 4
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                Repeater {
                    model: root.pages.map((p, i) => ({ page: p, index: i })).filter(e => e.page.group === "")
                    NavItem {
                        required property var modelData
                        navIcon: modelData.page.icon
                        navLabel: modelData.page.name
                        toggled: root.currentPage === modelData.index && !root.showingProfile
                        onClicked: {
                            root.currentPage = modelData.index
                            root.showingProfile = false
                        }
                    }
                }

                NavItem {
                    id: configFileButton
                    property bool justCopied: false
                    navIcon: justCopied ? "check" : "edit_note"
                    navLabel: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                    downAction: () => {
                        AppLaunch.openUrl(`${Directories.config}/nixbook-shell/config.json`);
                    }
                    altAction: () => {
                        Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/nixbook-shell/config.json`);
                        configFileButton.justCopied = true;
                        revertTextTimer.restart()
                    }
                    Timer {
                        id: revertTextTimer
                        interval: 1500
                        onTriggered: configFileButton.justCopied = false
                    }
                    StyledToolTip {
                        text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                    }
                }
            }
        }

        // ------------------------------------------------------------ content
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Page header: title, description and the "Editable only" filter
            RowLayout {
                id: pageHeader
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 8
                Layout.topMargin: 8
                Layout.bottomMargin: 10
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    visible: !root.isMinimal
                    text: root.currentEntry.icon
                    rotation: root.currentEntry.iconRotation ?? 0
                    iconSize: 22
                    padding: 9
                    wrappedShape: MaterialShape.Shape.Cookie7Sided
                    color: Appearance.colors.colSecondaryContainer
                    colSymbol: Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.currentEntry.name
                        font.pixelSize: Appearance.font.pixelSize.title
                        font.family: Appearance.font.family.title
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: {
                            const hidden = NixManaged.hideLocked ? root.pinnedTally.pinned : 0;
                            const desc = root.currentEntry.description ?? "";
                            if (hidden === 0) return desc;
                            return desc + "  ·  " + Translation.tr("%1 locked hidden").arg(hidden);
                        }
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                // Only offered when some settings are actually locked.
                RippleButton {
                    id: editableOnlyButton
                    visible: NixManaged.pinned.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    implicitWidth: editableOnlyRow.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    toggled: NixManaged.hideLocked
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colLayer1Active
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: Config.options.settings.hideLocked = !Config.options.settings.hideLocked

                    contentItem: RowLayout {
                        id: editableOnlyRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: editableOnlyButton.toggled ? "lock_open" : "lock"
                            iconSize: Appearance.font.pixelSize.larger
                            fill: editableOnlyButton.toggled ? 1 : 0
                            color: editableOnlyButton.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            visible: root.width > 720
                            text: Translation.tr("Editable only")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: editableOnlyButton.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                        StyledSwitch {
                            scale: 0.6
                            checked: editableOnlyButton.toggled
                            onClicked: editableOnlyButton.clicked()
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Hide locked settings (marked with a lock icon).\nThey are managed outside the shell, e.g. by your Nix configuration,\nand can only be changed there.")
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Repeater {
                    id: pagesRepeater
                    model: root.pages
                    Loader {
                        id: pageLoader
                        required property var modelData
                        required property var index
                        source: modelData.component

                        active: Config.ready && (root.currentPage === index || item !== null)

                        anchors.fill: parent

                        property bool isActive: root.currentPage === index && !root.showingProfile
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : 12

                        onLoaded: {
                            if (root.currentPage === index) {
                                GlobalStates.currentPageInstance = item;
                            }
                        }

                        onIsActiveChanged: {
                            if (isActive && item) {
                                GlobalStates.currentPageInstance = item;
                            } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                GlobalStates.currentPageInstance = null;
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on anchors.topMargin {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Loader {
                    id: profileLoader
                    active: false
                    anchors.fill: parent
                    source: Qt.resolvedUrl("pages/Profile.qml")

                    property bool isActive: root.showingProfile
                    opacity: isActive ? 1 : 0
                    enabled: isActive
                    visible: isActive
                    anchors.topMargin: isActive ? 0 : 12

                    onIsActiveChanged: {
                        if (isActive && item) {
                            GlobalStates.currentPageInstance = item;
                        } else if (!isActive && GlobalStates.currentPageInstance === item) {
                            GlobalStates.currentPageInstance = null;
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on anchors.topMargin {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
