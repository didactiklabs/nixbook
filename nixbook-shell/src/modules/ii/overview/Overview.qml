import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property bool barCenterOnly: Config.options.bar.layouts.leftLayout.length === 0
            && Config.options.bar.layouts.rightLayout.length === 0
            && !Config.options.bar.vertical

        readonly property bool barOverlapActive: panelWindow.barCenterOnly
            && Config.options.bar.centerOnlyReserveFrame
            && !Config.options.bar.bottom
            && !Config.options.bar.autoHide.enable
        // Stays mapped once opened or preloaded: hiding a Wayland window
        // destroys its surface and Qt rebuilt the window's GL context on every
        // open (≈100–200 ms). Closed = no input region, no keyboard focus,
        // transparent content. The window is a full-height strip as wide as
        // the launcher (clicks outside are caught by GlobalFocusGrab's
        // dismissCatcher), so staying mapped costs little.
        property bool keepMapped: false
        visible: keepMapped || GlobalStates.overviewOpen
        Connections {
            target: Preloader
            function onLauncherChanged() { if (Preloader.launcher) panelWindow.keepMapped = true; }
        }
        function followFocusedScreen() {
            const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name);
            if (s && panelWindow.screen !== s) panelWindow.screen = s;
        }

        WlrLayershell.namespace: "quickshell:overview"
        // Overlay so it stays above GlobalFocusGrab's click catcher (Top).
        WlrLayershell.layer: WlrLayer.Overlay
        // Open panels take the keyboard (see SidebarLeft): typing into the
        // launcher must never reach the window underneath.
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? columnLayout : null
        }

        anchors {
            top: true
            bottom: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    overviewScope.dontAutoCancelSearch = false;
                    // Only leave the dismissable set: dismiss() here also closed
                    // whichever popup had just replaced the launcher.
                    GlobalFocusGrab.removeDismissable(panelWindow);
                } else {
                    panelWindow.followFocusedScreen();
                    panelWindow.keepMapped = true;
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (GlobalFocusGrab.spares(panelWindow)) return;
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            // Hidden by opacity (not `visible`): toggling visibility re-laid
            // out the results on every open, and skipped the fade-out.
            opacity: GlobalStates.overviewOpen ? 1 : (Preloader.prerender ? 0.004 : 0)
            scale: GlobalStates.overviewOpen ? 1 : 0.85
            transformOrigin: Item.Top
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: panelWindow.barOverlapActive
                    ? Appearance.sizes.barHeight - Config.options.bar.frameThickness
                    : 0
            }
            spacing: -8

            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleSymbols() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.symbols);
        GlobalStates.overviewOpen = true;
    }

    // The launcher as a window layout picker (LauncherSearch, WindowLayouts).
    function toggleLayouts() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        WindowLayouts.refresh();
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.layouts);
        GlobalStates.overviewOpen = true;
    }

    function toggleThemes() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.themes);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
        function emojiToggle() {
            overviewScope.toggleEmojis();
        }
        function symbolsToggle() {
            overviewScope.toggleSymbols();
        }
        function themeToggle() {
            overviewScope.toggleThemes();
        }
        function layoutsToggle() {
            overviewScope.toggleLayouts();
        }
    }
}
