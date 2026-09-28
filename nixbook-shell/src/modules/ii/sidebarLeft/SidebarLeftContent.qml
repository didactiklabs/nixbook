import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : [])
    ]
    property int tabCount: swipeView.count
    property bool preloadReady: false
    property bool neighboursReady: false

    // One page object per tab, reused whenever the contentChildren binding
    // re-evaluates (e.g. when Config finishes loading). Upstream called
    // createObject() inside the binding, leaking a fresh set of pages on every
    // re-evaluation.
    property var pageCache: ({})
    function pageFor(key, component, direct = false) {
        if (!pageCache[key])
            pageCache[key] = direct ? component.createObject() : lazyPage.createObject(null, { page: component });
        return pageCache[key];
    }

    // Give the current tab's input the keyboard (chat / translator field).
    // Going through the page wrapper's onFocusChanged doesn't work when it
    // already has focus, so the panel opened with keys going nowhere.
    function focusActiveItem() {
        const page = swipeView.currentItem;
        const item = page?.pageItem ?? page;
        if (item?.inputField) item.inputField.forceActiveFocus();
        else item?.forceActiveFocus();
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: verticalTabBar.expanded ? -2 : 0

        VerticalTabBar {
            id: verticalTabBar
            visible: tabButtonList.length > 0
            Layout.fillWidth: true
            tabButtonList: root.tabButtonList
            currentIndex: swipeView.currentIndex
            onCurrentIndexChanged: swipeView.currentIndex = currentIndex
        }

        // What the panel can do and its shortcuts, on screen: extend
        // (Ctrl+O), pin (Ctrl+P: stays open, part of the layout) and detach
        // (Ctrl+D: a window of its own). Same as the keys (GlobalStates.
        // sidebarLeftShortcut); extend and pin only while docked.
        RowLayout {
            id: panelToolbar
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 4
            readonly property bool detached: root.scopeRoot?.detach ?? false

            component PanelToolButton: RippleButton {
                id: toolButton
                property string symbol
                property string label
                property string keys
                property string hint
                Layout.fillWidth: true
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: toolButton.symbol
                        fill: toolButton.toggled ? 1 : 0
                        iconSize: Appearance.font.pixelSize.normal
                        color: toolButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: toolButton.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: toolButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                    Rectangle { // the key, as a keycap
                        implicitWidth: keyText.implicitWidth + 8
                        implicitHeight: keyText.implicitHeight + 2
                        radius: 4
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                        StyledText {
                            id: keyText
                            anchors.centerIn: parent
                            text: toolButton.keys
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                StyledToolTip {
                    text: toolButton.hint
                }
            }

            PanelToolButton {
                visible: !panelToolbar.detached
                symbol: root.scopeRoot?.extended ? "close_fullscreen" : "open_in_full"
                label: Translation.tr("Extend")
                keys: "Ctrl+O"
                hint: Translation.tr("Make the panel wider (Ctrl+O)")
                toggled: root.scopeRoot?.extended ?? false
                onClicked: GlobalStates.sidebarLeftShortcut(Qt.Key_O)
            }
            PanelToolButton {
                visible: !panelToolbar.detached
                symbol: "push_pin"
                label: Translation.tr("Pin")
                keys: "Ctrl+P"
                hint: Translation.tr("Keep the panel open beside your windows (Ctrl+P)")
                toggled: root.scopeRoot?.pin ?? false
                onClicked: GlobalStates.sidebarLeftShortcut(Qt.Key_P)
            }
            PanelToolButton {
                symbol: panelToolbar.detached ? "dock_to_left" : "open_in_new"
                label: panelToolbar.detached ? Translation.tr("Attach") : Translation.tr("Detach")
                keys: "Ctrl+D"
                hint: panelToolbar.detached ? Translation.tr("Put the chat back in the panel (Ctrl+D)")
                    : Translation.tr("Open the chat in a window of its own (Ctrl+D)")
                toggled: panelToolbar.detached
                onClicked: GlobalStates.sidebarLeftShortcut(Qt.Key_D)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            topLeftRadius: 0
            bottomLeftRadius: Appearance.rounding.normal
            topRightRadius: 0
            bottomRightRadius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    ...(root.aiChatEnabled ? [root.pageFor("aiChat", aiChat)] : []),
                    ...(root.translatorEnabled ? [root.pageFor("translator", translator)] : []),
                    ...(root.tabButtonList.length === 0 ? [root.pageFor("placeholder", placeholder, true)] : []),
                ]
            }
        }

        // Tab pages are no longer all built at shell startup. The current tab
        // is preloaded once the shell has settled (so the first open is still
        // instant); adjacent tabs (swipe peek) are built right after the first
        // open's entrance animation; any tab is built on the spot when it
        // becomes current. Built pages are kept alive. Loads are synchronous on
        // purpose (asynchronous incubation of Qt5Compat graphical
        // effects logged "ShaderEffect: 'source' does not have a matching
        // property").
        // While the shell boots behind the loading screen, the Preloader's
        // sidebarLeft stage builds the current tab and its neighbours up front
        // (the first open used to build them: ~0.5 s, then more on close).
        Connections {
            target: Preloader
            function onSidebarLeftChanged() {
                if (!Preloader.sidebarLeft) return;
                root.preloadReady = true;
                root.neighboursReady = true;
            }
        }
        Timer {
            id: preloadTimer
            interval: 2500
            running: true
            onTriggered: root.preloadReady = true
        }
        Timer {
            id: neighbourTimer
            interval: 600
            running: GlobalStates.sidebarLeftOpen && !root.neighboursReady
            onTriggered: root.neighboursReady = true
        }

        Component {
            id: lazyPage
            Item {
                id: pageRoot
                property Component page
                readonly property Item pageItem: pageLoader.item
                readonly property bool isCurrent: SwipeView.isCurrentItem
                readonly property bool isNeighbour: SwipeView.isNextItem || SwipeView.isPreviousItem
                readonly property bool wantedNow: (isCurrent && (root.preloadReady || GlobalStates.sidebarLeftOpen))
                    || (isNeighbour && root.neighboursReady)
                property bool loaded: false
                onWantedNowChanged: if (wantedNow) loaded = true
                Component.onCompleted: if (wantedNow) loaded = true

                implicitWidth: pageLoader.item?.implicitWidth ?? 0
                implicitHeight: pageLoader.item?.implicitHeight ?? 0

                // Pages forward their focus to their input field; keep that working.
                onFocusChanged: focus => {
                    if (focus && pageLoader.item)
                        pageLoader.item.forceActiveFocus();
                }

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    active: pageRoot.loaded
                    sourceComponent: pageRoot.page
                    onLoaded: {
                        if (pageRoot.activeFocus)
                            item.forceActiveFocus();
                    }
                }
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}