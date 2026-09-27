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

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
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