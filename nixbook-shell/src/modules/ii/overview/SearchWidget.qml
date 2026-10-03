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
    // Apps are listed before anything is typed (LauncherSearch.allAppResults).
    property bool showResults: searchingText != "" || LauncherSearch.results.length > 0
    // The query without its mode prefix, for the rows' match highlighting:
    // worked out once here instead of in every row.
    readonly property string highlightQuery: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.themes, Config.options.search.prefix.layouts, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])
    // Apps (and the default search) are a grid of tiles, like DankLauncher;
    // the prefix modes (clipboard, emojis, themes…) keep the list rows.
    readonly property bool gridMode: ![Config.options.search.prefix.action, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.themes, Config.options.search.prefix.layouts, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch].some(prefix => prefix !== "" && root.searchingText.startsWith(prefix))
    readonly property int gridColumns: 5
    // The view showing the results: the keyboard moves its selection.
    readonly property var resultView: root.gridMode ? appGrid : appResults
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        for (const view of [appResults, appGrid]) {
            view.currentIndex = 0;
            view.positionViewAtBeginning();
        }
    }

    function selectIndex(index) {
        const view = root.resultView;
        if (view.count === 0)
            return;
        view.currentIndex = Math.max(0, Math.min(view.count - 1, index));
        view.positionViewAtIndex(view.currentIndex, ListView.Contain);
    }

    // One result to the next or previous, wrapping around at either end.
    function moveItem(delta) {
        const view = root.resultView;
        if (view.count === 0)
            return;
        root.selectIndex((view.currentIndex + delta + view.count) % view.count);
    }

    // Up/Down: a row of the list, or of the grid (stopping at its edges).
    function moveSelection(delta) {
        if (!root.gridMode) {
            root.moveItem(delta);
            return;
        }
        // Down from a row above a shorter last one lands on its last tile.
        const target = appGrid.currentIndex + delta * root.gridColumns;
        const lastRow = Math.floor((appGrid.count - 1) / root.gridColumns);
        if (target >= 0 && Math.floor(target / root.gridColumns) <= lastRow)
            root.selectIndex(target);
    }

    function pageSelection(direction) {
        const view = root.resultView;
        const rowHeight = root.gridMode ? appGrid.cellHeight : Appearance.sizes.searchResultHeight;
        const rows = Math.max(1, Math.floor(view.height / rowHeight) - 1);
        root.selectIndex(view.currentIndex + direction * rows * (root.gridMode ? root.gridColumns : 1));
    }

    function acceptSelection() {
        const view = root.resultView;
        const item = view.currentItem ?? view.itemAtIndex(0);
        if (item && item.clicked)
            item.clicked();
    }

    // Tab in the list: put the selected result's name in the box.
    function completeSelection() {
        const item = appResults.currentItem;
        if (!item || !item.modelData)
            return;
        root.setSearchingText(item.modelData.name);
    }

    // Shift+Delete in the box: what SearchItem does with the row focused.
    function deleteSelection() {
        const item = appResults.currentItem;
        const remove = (item?.modelData?.actions ?? []).find(action => action.name == Translation.tr("Delete"));
        if (remove)
            remove.execute();
    }

    // The pointer selects the result under it, but only when it really moves:
    // Qt re-sends a hover at the same place when the view scrolls under a
    // resting pointer (keyboard paging), which would steal the keyboard's
    // selection.
    component SelectOnHover: HoverHandler {
        required property var view
        property point lastScenePosition: Qt.point(-1, -1)
        onPointChanged: {
            const p = point.scenePosition;
            if (p.x === lastScenePosition.x && p.y === lastScenePosition.y)
                return;
            lastScenePosition = p;
            const index = view.indexAt(point.position.x + view.contentX, point.position.y + view.contentY);
            if (index !== -1)
                view.currentIndex = index;
        }
    }

    // Diff by object identity: app results are cached per desktop entry
    // (LauncherSearch.appResultFor), so results that survive a keystroke keep
    // their delegate. `objectProp: "key"` named a property
    // LauncherSearchResult doesn't have. Only the shown view gets it.
    ScriptModel {
        id: resultModel
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

    onSearchingTextChanged: root.focusFirstItem()

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function cancelSearch() {
        searchBar.searchInput.text = ""; 
        LauncherSearch.query = "";
        // Back to the top of the app list on each open.
        root.focusFirstItem();
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
                onMoveSelection: delta => root.moveSelection(delta)
                onPageSelection: direction => root.pageSelection(direction)
                onAcceptSelection: root.acceptSelection()
                onCompleteSelection: root.completeSelection()
                onDeleteSelection: root.deleteSelection()
                onMoveItem: delta => root.moveItem(delta)
                gridMode: root.gridMode
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

            ListView { // Prefix mode results (clipboard, emojis, themes…)
                id: appResults
                visible: root.showResults && !root.gridMode
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
                // every keystroke.
                reuseItems: true

                SelectOnHover {
                    view: appResults
                }

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                model: root.gridMode ? null : resultModel

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
                            root.setSearchingText(searchItem.modelData.name);
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }

            GridView { // Apps and the default search, as tiles
                id: appGrid
                visible: root.showResults && root.gridMode
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                // Same fixed height as the list: no resize on each keystroke.
                Layout.preferredHeight: Appearance.sizes.searchResultsHeight - Layout.bottomMargin
                Layout.bottomMargin: 8
                clip: true
                topMargin: 8
                bottomMargin: 2
                cellWidth: Math.floor(width / root.gridColumns)
                cellHeight: 116
                cacheBuffer: cellHeight * 2
                highlightMoveDuration: 100
                reuseItems: true
                model: root.gridMode ? resultModel : null

                SelectOnHover {
                    view: appGrid
                }

                delegate: SearchTile {
                    required property var modelData
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    // Gaps between the tiles
                    topInset: 3
                    bottomInset: 3
                    leftInset: 3
                    rightInset: 3
                    entry: modelData
                }
            }
        }
    }
}
