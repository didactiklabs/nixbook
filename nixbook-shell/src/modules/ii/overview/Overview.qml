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
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    // The workspace/overview widget is the expensive part (a full delegate
    // tree per window) - build it on first open and keep it, rather than
    // tearing it down every time the overview closes. Its timers are all
    // event-driven, so an idle cached instance costs nothing.
    property bool overviewEverOpened: false
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                overviewScope.overviewEverOpened = true;
        }
    }

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        readonly property bool barCenterOnly: Config.options.bar.layouts.leftLayout.length === 0
            && Config.options.bar.layouts.rightLayout.length === 0
            && !Config.options.bar.vertical

        readonly property bool barOverlapActive: panelWindow.barCenterOnly
            && Config.options.bar.centerOnlyReserveFrame
            && !Config.options.bar.bottom
            && !Config.options.bar.autoHide.enable
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
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
                } else if (event.key === Qt.Key_Left) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch("workspace r-1");
                } else if (event.key === Qt.Key_Right) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch("workspace r+1");
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                active: overviewScope.overviewEverOpened && (Config?.options.overview.enable ?? true)
                sourceComponent: (Config?.options.overview.style ?? "default") === "niri" ? niriComponent : defaultComponent

                Component {
                    id: defaultComponent
                    OverviewWidget {
                        screen: panelWindow.screen
                        visible: (panelWindow.searchingText == "")
                    }
                }

                Component {
                    id: niriComponent
                    NiriOverview {
                        screen: panelWindow.screen
                        panelWindow: panelWindow
                        visible: (panelWindow.searchingText == "")
                    }
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
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    CompositorGlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    CompositorGlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    CompositorGlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    CompositorGlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    CompositorGlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    CompositorGlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    CompositorGlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }

    CompositorGlobalShortcut {
        name: "overviewSymbolsToggle"
        description: "Toggle material symbols search on overview widget"

        onPressed: {
            overviewScope.toggleSymbols();
        }
    }
}