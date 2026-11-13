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

    // ----------------------------------------------------------- search
    // The sidebar's search box: every page's sections and settings
    // (SettingsSearchIndex); a result opens its page and scrolls to it.
    property string searchQuery: ""
    readonly property var searchResults: root.searchQuery.trim() === "" ? [] : searchIndex.search(root.searchQuery, 60).filter(e => root.pageAvailable(root.pages[e.page])).slice(0, 40)
    function focusSearch() {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    SettingsSearchIndex {
        id: searchIndex
        pages: root.pages
    }
    property var revealing: null
    function openSearchResult(entry) {
        if (!entry) return;
        root.showingProfile = false;
        root.currentPage = entry.page;
        root.revealing = entry;
        revealTimer.tries = 0;
        revealTimer.settling = false;
        revealTimer.interval = 120;
        revealTimer.restart();
    }
    // The page loads and lays out first: then scroll its setting into view,
    // again once the page has settled (some fill in asynchronously, moving
    // it), and flash it.
    Timer {
        id: revealTimer
        property int tries: 0
        property bool settling: false
        interval: 120
        onTriggered: {
            const entry = root.revealing;
            const page = root.pageItem(entry?.page ?? -1);
            const target = page ? root.findSettingItem(page, entry) : null;
            if (!target) {
                if (++tries < 12) restart();
                return;
            }
            const pos = target.mapToItem(page.contentItem, 0, 0);
            const maxY = Math.max(0, page.contentHeight - page.height);
            page.contentY = Math.max(0, Math.min(maxY, pos.y - 24));
            if (!settling) {
                settling = true;
                interval = 450;
                restart();
                return;
            }
            searchHighlight.createObject(page.contentItem, { x: pos.x - 6, y: pos.y - 4, width: target.width + 12, height: target.height + 8 });
        }
    }
    function findSettingItem(item, entry) {
        const label = Translation.tr(entry.label);
        // A section's title, or a settings control's label (Config*
        // controls have a configKey, RingtoneSetting a kind).
        const matches = it => it.visible && (entry.kind === "section"
            ? (it.title === label || it.title === entry.label)
            : ((it.configKey !== undefined || it.kind !== undefined) && (it.text === label || it.text === entry.label)));
        const walk = it => {
            if (!it) return null;
            if (it !== item && matches(it)) return it;
            for (const child of it.children ?? []) {
                const found = walk(child);
                if (found) return found;
            }
            return null;
        };
        return walk(item.contentItem ?? item);
    }
    Component {
        id: searchHighlight
        Rectangle {
            id: flash
            radius: Appearance.rounding.normal
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
            z: 100
            SequentialAnimation on opacity {
                running: true
                NumberAnimation { from: 0; to: 1; duration: 150 }
                PauseAnimation { duration: 900 }
                NumberAnimation { to: 0; duration: 500 }
                ScriptAction { script: flash.destroy() }
            }
        }
    }
    property bool isMinimal: Config.options.settings.style === "minimal"
    // Icon-only sidebar when the window is narrow (or in the minimal style).
    readonly property bool railExpanded: !isMinimal && root.width > 860

    Connections {
        target: GlobalStates
        function onSettingsPageChanged() {
            if (GlobalStates.settingsPage === "") return

            const parts = GlobalStates.settingsPage.split(":");
            const pageName = parts[0];
            const searchTerm = parts.slice(1).join(":");

            const idx = root.resolvePage(pageName, searchTerm);

            if (idx >= 0) {
                root.currentPage = idx;
                root.showingProfile = false;

                if (searchTerm !== "") {
                    const loader = pagesRepeater.itemAt(root.fileIndexOf(idx));
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
        const group = root.pages[currentPage]?.group ?? "";
        if (root.collapsedGroups[group]) {
            const next = Object.assign({}, root.collapsedGroups);
            delete next[group];
            root.collapsedGroups = next;
        }
        const pageName = root.pages[currentPage]?.name ?? ""
        if (pageName === Translation.tr("About")) {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            UpdateState.checkUpdate()
        }
    }

    // Sidebar groups, in display order. Pages without a group (About) sit at
    // the bottom of the sidebar. The order of `pages` is also the Tab order,
    // and the names are what LauncherSearch's settingsIndex refers to.
    // `GlobalStates.settingsPage` ("Page" or "Page:section") also takes a
    // page's `aliases` (its former names), and a section that moved to
    // another page is found there.
    readonly property var groups: [
        { id: "personalize", name: Translation.tr("Look & feel") },
        { id: "shell",       name: Translation.tr("Shell") },
        { id: "ai",          name: Translation.tr("AI assistant") },
        { id: "connected",   name: Translation.tr("Connected") },
        { id: "system",      name: Translation.tr("System") },
    ]

    // A page with a `tab` is that tab of a page file with several (the AI
    // pages, all in DesktopAgentsConfig.qml): one instance shows them all.
    readonly property var pages: [
        { group: "personalize", name: Translation.tr("Quick"),          icon: "instant_mix",    description: Translation.tr("Wallpaper, colors and the most used toggles"), component: Qt.resolvedUrl("pages/QuickConfig.qml") },
        { group: "personalize", name: Translation.tr("Appearance"),     icon: "palette",        description: Translation.tr("Color generation, transparency, fonts and this window"), component: Qt.resolvedUrl("pages/AppearanceConfig.qml") },
        { group: "personalize", name: Translation.tr("Themes"),         icon: "style",          description: Translation.tr("Shell theme, variants and each theme's style"), component: Qt.resolvedUrl("pages/ThemesConfig.qml") },
        { group: "personalize", name: Translation.tr("Wallpaper"),      icon: "wallpaper",      aliases: ["Desktop", "Background"], description: Translation.tr("Desktop, lock and login wallpapers, and the wallpaper selector"), component: Qt.resolvedUrl("pages/BackgroundConfig.qml") },
        { group: "personalize", name: Translation.tr("Desktop widgets"), icon: "widgets",       description: Translation.tr("Clock, visualizer, image, text and the other widgets on the desktop"), component: Qt.resolvedUrl("pages/DesktopWidgetsConfig.qml") },
        { group: "shell",       name: Translation.tr("Bar"),            icon: "toast",          iconRotation: 180, description: Translation.tr("Layout, style and the bar's widgets"), component: Qt.resolvedUrl("pages/BarConfig.qml") },
        { group: "shell",       name: Translation.tr("Notifications"),  icon: "notifications",  description: Translation.tr("Popups, cut-ins, quiet and keep-on-screen rules, history"), component: Qt.resolvedUrl("pages/NotificationsConfig.qml") },
        { group: "shell",       name: Translation.tr("Panels"),         icon: "bottom_app_bar", description: Translation.tr("Overview, sidebars, dock, on-screen display and overlays"), component: Qt.resolvedUrl("pages/PanelsConfig.qml") },
        { group: "shell",       name: Translation.tr("Lock screen"),    icon: "lock",           description: Translation.tr("Locking, security and lock screen style"), component: Qt.resolvedUrl("pages/LockScreenConfig.qml") },
        { group: "shell",       name: Translation.tr("Window layouts"), icon: "view_quilt",     description: Translation.tr("Save, restore and switch window arrangements and projects"), component: Qt.resolvedUrl("pages/WindowLayoutsConfig.qml") },
        { group: "ai",          name: Translation.tr("Assistant"),      icon: "smart_toy",      tab: "basics",  aliases: ["Desktop agents", "AI"], description: Translation.tr("AI features, DAI in the side panel, the chat and desktop control"), component: Qt.resolvedUrl("pages/DesktopAgentsConfig.qml") },
        { group: "ai",          name: Translation.tr("Privacy & trust"), icon: "verified_user", tab: "trust",   description: Translation.tr("What is masked before it is sent, and what it may do without asking"), component: Qt.resolvedUrl("pages/DesktopAgentsConfig.qml") },
        { group: "ai",          name: Translation.tr("On its own"),     icon: "auto_awesome",   tab: "own",     description: Translation.tr("Talking to you first, the smart clipboard and routines"), component: Qt.resolvedUrl("pages/DesktopAgentsConfig.qml") },
        { group: "ai",          name: Translation.tr("Memory"),         icon: "psychology",     tab: "memory",  description: Translation.tr("What agents remember: notes, habits and about you"), component: Qt.resolvedUrl("pages/DesktopAgentsConfig.qml") },
        { group: "ai",          name: Translation.tr("Self-improvement"), icon: "build",        tab: "improve", needs: "selfImprove", description: Translation.tr("The fixes and features it makes to nixbook itself"), component: Qt.resolvedUrl("pages/DesktopAgentsConfig.qml") },
        { group: "connected",   name: Translation.tr("Mesh"),           icon: "hub",            description: Translation.tr("Messages, status and listening along with other desktops"), component: Qt.resolvedUrl("pages/MeshConfig.qml") },
        { group: "connected",   name: Translation.tr("Apps & accounts"), icon: "account_tree",  description: Translation.tr("Google Keep, Jellyfin, YouTube Music and YouTube links"), component: Qt.resolvedUrl("pages/AccountsConfig.qml") },
        { group: "system",      name: Translation.tr("General"),        icon: "tune",           description: Translation.tr("Time, battery, language and work safety"), component: Qt.resolvedUrl("pages/GeneralConfig.qml") },
        { group: "system",      name: Translation.tr("Sound"),          icon: "volume_up",      description: Translation.tr("Volume protection, sounds, ringtones and echo cancellation"), component: Qt.resolvedUrl("pages/SoundConfig.qml") },
        { group: "system",      name: Translation.tr("Services"),       icon: "dns",            description: Translation.tr("Networking, launcher search, save paths, updates and weather"), component: Qt.resolvedUrl("pages/ServicesConfig.qml") },
        { group: "system",      name: Translation.tr("Niri"),           icon: "select_window_2", description: Translation.tr("Displays, input, layout and animations"), component: Qt.resolvedUrl("pages/NiriConfig.qml") },
        { group: "",            name: Translation.tr("About"),          icon: "info",           description: Translation.tr("System information and updates"), component: Qt.resolvedUrl("pages/About.qml") },
    ]

    // A page that only has something to show on some machines (`needs`):
    // left out of the sidebar elsewhere.
    function pageAvailable(p) {
        return p.needs !== "selfImprove" || SelfImprove.available;
    }

    // The page files, each loaded once (a file can back several pages).
    readonly property var pageFiles: root.pages.reduce((acc, p) => {
        const url = String(p.component);
        if (!acc.includes(url)) acc.push(url);
        return acc;
    }, [])
    function fileIndexOf(pageIndex) {
        return root.pageFiles.indexOf(String(root.pages[pageIndex]?.component ?? ""));
    }
    // The page's loaded instance (null until first shown).
    function pageItem(pageIndex) {
        return pagesRepeater.itemAt(root.fileIndexOf(pageIndex))?.item ?? null;
    }
    // A page file with tabs switched its own tab (a search or a link to a
    // section in another tab): follow it in the sidebar.
    function followTab(fileIndex, tab) {
        const current = root.pages[root.currentPage];
        if (!current || root.fileIndexOf(root.currentPage) !== fileIndex || current.tab === undefined || current.tab === tab) return;
        const idx = root.pages.findIndex(p => String(p.component) === root.pageFiles[fileIndex] && p.tab === tab);
        if (idx >= 0) root.currentPage = idx;
    }
    // "Page" or "Page:section" (GlobalStates.settingsPage): the page by its
    // name or one of its aliases; with a section, the page holding a
    // section of that name, that page first (sections moved between pages).
    function resolvePage(pageName, term) {
        const n = pageName.toLowerCase();
        const nt = Translation.tr(pageName).toLowerCase();
        const named = [];
        root.pages.forEach((p, i) => {
            if (p.name.toLowerCase() === n || p.name.toLowerCase() === nt || (p.aliases ?? []).some(a => a.toLowerCase() === n || Translation.tr(a).toLowerCase() === n))
                named.push(i);
        });
        if (term === "") return named.length > 0 ? named[0] : -1;
        // The pages holding a section of that name: exact, then starting
        // with it, then containing it.
        const t = term.toLowerCase();
        const rank = e => Math.min(...[e.label, Translation.tr(e.label)].map(l => {
            const s = l.toLowerCase();
            return s === t ? 0 : s.startsWith(t) ? 1 : s.includes(t) ? 2 : 3;
        }));
        const holding = searchIndex.entries.filter(e => e.kind === "section" && rank(e) < 3)
            .sort((a, b) => rank(a) - rank(b)).map(e => e.page);
        return named.find(i => holding.includes(i)) ?? holding[0] ?? named[0] ?? -1;
    }

    // Keeps the open page's sidebar entry in view (Tab, a search, a link,
    // or a group just unfolded), once the sidebar is laid out again.
    Timer {
        id: navRevealTimer
        property Item target: null
        interval: 60
        onTriggered: {
            const it = target;
            if (!it || !it.visible) return;
            const y = it.mapToItem(navColumn, 0, 0).y;
            const maxY = Math.max(0, navFlick.contentHeight - navFlick.height);
            if (y < navFlick.contentY)
                navFlick.contentY = Math.max(0, y - 8);
            else if (y + it.height > navFlick.contentY + navFlick.height)
                navFlick.contentY = Math.min(maxY, y + it.height - navFlick.height + 8);
        }
    }

    // Collapsed sidebar groups (a click on the heading); going to a page
    // (Tab, a search, a link) unfolds its group.
    property var collapsedGroups: ({})
    function groupShown(groupId) {
        return !root.railExpanded || !root.collapsedGroups[groupId];
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
            // Not on this page (another tab of the same file).
            if (item.shown === false) return;
            const kids = item.children;
            if (kids) for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(page.contentItem ?? page);
        return { total: total, pinned: pinned };
    }

    // Pages load when first shown and stay loaded (their Loader's `item !==
    // null`). Config writes keep the shell's debounce: a slider drag is one
    // write, not one per tick.

    // One sidebar entry: icon + label, pill-shaped highlight when selected.
    component NavItem: RippleButton {
        id: navItem
        property string navIcon
        property real navIconRotation: 0
        property string navLabel
        Layout.fillWidth: true
        implicitHeight: root.isMinimal ? 38 : 40
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

                // Search: Ctrl+F; Enter opens the first result, Escape clears.
                ToolbarTextField {
                    id: searchField
                    visible: root.railExpanded
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.topMargin: 6
                    implicitHeight: 38
                    leftPadding: 36
                    placeholderText: Translation.tr("Search settings")
                    text: root.searchQuery
                    onTextChanged: root.searchQuery = text
                    Keys.onReturnPressed: root.openSearchResult(root.searchResults[0])
                    Keys.onEnterPressed: root.openSearchResult(root.searchResults[0])
                    Keys.onEscapePressed: event => {
                        if (text !== "") {
                            text = "";
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                    MaterialSymbol {
                        anchors {
                            left: parent.left
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                }

                // Search results, instead of the pages while searching.
                StyledFlickable {
                    id: resultsFlick
                    visible: root.searchQuery.trim() !== ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    clip: true
                    contentHeight: resultsColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: resultsColumn
                        width: resultsFlick.width
                        spacing: 2

                        StyledText {
                            visible: root.searchResults.length === 0
                            Layout.fillWidth: true
                            Layout.margins: 12
                            wrapMode: Text.Wrap
                            text: Translation.tr("No setting matches")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        Repeater {
                            model: root.searchResults
                            delegate: RippleButton {
                                id: resultButton
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: resultText.implicitHeight + 16
                                buttonRadius: Appearance.rounding.normal
                                toggled: root.revealing?.page === modelData.page && root.revealing?.label === modelData.label
                                onClicked: root.openSearchResult(modelData)
                                contentItem: RowLayout {
                                    spacing: 10
                                    MaterialSymbol {
                                        Layout.leftMargin: 8
                                        text: resultButton.modelData.kind === "section" ? "segment" : (root.pages[resultButton.modelData.page]?.icon ?? "settings")
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: resultButton.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    ColumnLayout {
                                        id: resultText
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr(resultButton.modelData.label)
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: resultButton.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: [root.pages[resultButton.modelData.page]?.name, resultButton.modelData.section ? Translation.tr(resultButton.modelData.section) : ""].filter(Boolean).join(" › ")
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Page list, grouped. Scrolls when the window is short.
                StyledFlickable {
                    id: navFlick
                    visible: root.searchQuery.trim() === ""
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

                                // Group heading (a thin divider when the rail is
                                // collapsed): a click folds the group away.
                                Item {
                                    id: groupHeading
                                    readonly property bool folded: !root.groupShown(groupColumn.modelData.id)
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
                                        color: headingMouse.containsMouse ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                                    }
                                    MaterialSymbol {
                                        visible: root.railExpanded && (headingMouse.containsMouse || groupHeading.folded)
                                        anchors {
                                            right: parent.right
                                            rightMargin: 10
                                            verticalCenter: groupLabel.verticalCenter
                                        }
                                        text: groupHeading.folded ? "expand_more" : "expand_less"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                    }
                                    MouseArea {
                                        id: headingMouse
                                        anchors.fill: parent
                                        enabled: root.railExpanded
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const id = groupColumn.modelData.id;
                                            const next = Object.assign({}, root.collapsedGroups);
                                            next[id] = !groupHeading.folded;
                                            root.collapsedGroups = next;
                                        }
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
                                    model: root.pages.map((p, i) => ({ page: p, index: i })).filter(e => e.page.group === groupColumn.modelData.id && root.pageAvailable(e.page))
                                    NavItem {
                                        required property var modelData
                                        visible: !groupHeading.folded
                                        navIcon: modelData.page.icon
                                        navIconRotation: modelData.page.iconRotation ?? 0
                                        navLabel: modelData.page.name
                                        toggled: root.currentPage === modelData.index && !root.showingProfile
                                        onToggledChanged: if (toggled) {
                                            navRevealTimer.target = this;
                                            navRevealTimer.restart();
                                        }
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
                        Clipboard.copy(CF.FileUtils.trimFileProtocol(`${Directories.config}/nixbook-shell/config.json`));
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
                    model: root.pageFiles
                    Loader {
                        id: pageLoader
                        required property var modelData
                        required property var index
                        source: modelData

                        readonly property bool isCurrent: root.fileIndexOf(root.currentPage) === index
                        active: Config.ready && (isCurrent || item !== null)

                        anchors.fill: parent

                        property bool isActive: isCurrent && !root.showingProfile
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : 12

                        // A file shown as several pages (tabs): the open
                        // page's tab, and no tab bar of its own.
                        function applyTab() {
                            const entry = root.pages[root.currentPage];
                            if (!item || !isCurrent || entry?.tab === undefined) return;
                            item.tabsInSidebar = true;
                            if (item.tab !== entry.tab) item.tab = entry.tab;
                        }
                        Connections {
                            target: root
                            function onCurrentPageChanged() { pageLoader.applyTab(); }
                        }
                        Connections {
                            target: pageLoader.item
                            ignoreUnknownSignals: true
                            function onTabChanged() { root.followTab(pageLoader.index, pageLoader.item.tab); }
                        }

                        onLoaded: {
                            applyTab();
                            if (isCurrent) {
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
                    active: root.showingProfile || item !== null
                    anchors.fill: parent
                    source: Qt.resolvedUrl("pages/Profile.qml")

                    property bool isActive: root.showingProfile
                    opacity: isActive ? 1 : 0
                    enabled: isActive
                    visible: isActive
                    anchors.topMargin: isActive ? 0 : 12

                    onLoaded: {
                        if (isActive) GlobalStates.currentPageInstance = item;
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
        }
    }
}
