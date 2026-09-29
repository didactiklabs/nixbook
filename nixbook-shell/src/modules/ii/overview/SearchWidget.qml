pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15 // Should be enough to cover the whole view

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    // The query without its mode prefix, for the rows' match highlighting:
    // worked out once here instead of in every row.
    readonly property string highlightQuery: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.themes, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function cancelSearch() {
        searchBar.searchInput.text = ""; 
        LauncherSearch.query = "";
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }
    Rectangle { // Background
        id: searchWidgetContent
        // Persona style background art
        PersonaTexture {
            anchors.fill: parent
            opacity: 0.5
        }
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin
        }
        clip: true
        implicitWidth: Appearance.sizes.searchWidth
        implicitHeight: columnLayout.implicitHeight
        radius: searchBar.height / 2 + searchBar.verticalPadding
        color: Appearance.colors.colBackgroundSurfaceContainer
        // Tonal elevation: an outline instead of the shadow.
        border.width: Appearance.tonal ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        // No OpacityMask layer for the rounded corners: it re-rendered the
        // whole launcher offscreen on every change (each keystroke, cursor
        // blink, hover and scroll step). Nothing reaches the corners: the list
        // stops short of the bottom ones (its Layout.bottomMargin) and its
        // rows are inset.
        ColumnLayout {
            id: columnLayout
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            spacing: 0

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                // Same column as the result rows' icon and text (SearchItem's
                // iconCenterX and textX), in the bar's own coordinates.
                iconCenterX: 10 + 10 + 36 / 2 - Layout.leftMargin
                textX: 10 + 10 + 36 + 12 - Layout.leftMargin
                Layout.bottomMargin: verticalPadding
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
            }

            Rectangle {
                // Separator
                visible: root.showResults
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            ListView { // App results
                id: appResults
                visible: root.showResults
                Layout.fillWidth: true
                // Always the same height, however many rows match: the box
                // doesn't resize on each keystroke.
                Layout.preferredHeight: Appearance.sizes.searchResultsHeight - Layout.bottomMargin
                Layout.bottomMargin: 8
                clip: true
                topMargin: 8
                bottomMargin: 2
                spacing: 2
                // A few rows past the edge ready, for smooth scrolling.
                cacheBuffer: Appearance.sizes.searchResultHeight * 4
                KeyNavigation.up: searchBar
                highlightMoveDuration: 100
                // Recycle result rows instead of destroying/recreating them on
                // every keystroke; the pool is pre-filled while idle (below).
                reuseItems: true

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                Connections {
                    target: root
                    function onSearchingTextChanged() {
                        if (appResults.count > 0)
                            appResults.currentIndex = 0;
                    }
                }

                Timer {
                    id: debounceTimer
                    interval: root.typingDebounceInterval
                    onTriggered: {
                        resultModel.values = LauncherSearch.results ?? [];
                    }
                }

                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        resultModel.values = LauncherSearch.results.slice(0, root.typingResultLimit);
                        root.focusFirstItem();
                        debounceTimer.restart();
                    }
                }

                // Diff by object identity: app results are cached per desktop
                // entry (LauncherSearch.appResultFor), so rows that survive a
                // keystroke keep their delegate. `objectProp: "key"` named a
                // property LauncherSearchResult doesn't have.
                model: ScriptModel {
                    id: resultModel
                }

                // After the Preloader warmed the launcher, build one screenful
                // of rows while hidden and release them into the reuse pool, so
                // the first real query only rebinds them.
                Connections {
                    target: LauncherSearch
                    function onPrewarmed() {
                        if (root.showResults || AppSearch.list.length === 0) return;
                        appResults.poolWarmup = true;
                        resultModel.values = AppSearch.list.slice(0, root.typingResultLimit).map(e => LauncherSearch.appResultFor(e));
                        Qt.callLater(() => {
                            if (!root.showResults) resultModel.values = [];
                            appResults.poolWarmup = false;
                        });
                    }
                }
                property bool poolWarmup: false

                delegate: SearchItem {
                    id: searchItem
                    // The selectable item for each search result
                    required property var modelData
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    query: root.highlightQuery

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (LauncherSearch.results.length === 0)
                                return;
                            const tabbedText = searchItem.modelData.name;
                            LauncherSearch.query = tabbedText;
                            searchBar.searchInput.text = tabbedText;
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }
        }
    }
}
