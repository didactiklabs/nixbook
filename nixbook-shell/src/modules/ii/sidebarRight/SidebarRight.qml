import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical
    readonly property real barCenterOnlyOffset: (Config.options.bar.centerOnlyReserveFrame && root.centerOnly)
        ? Config.options.bar.frameThickness
        : Appearance.sizes.barHeight
    // The margin on the bar's edge (top or bottom): with only a center
    // section, over the strip the bar leaves free.
    readonly property real barEdgeMargin: {
        if (Config?.options.bar.autoHide.enable) return 0;
        if (!root.centerOnly) return 0;
        switch (Config.options.bar.cornerStyle) {
        case 0: return -root.barCenterOnlyOffset;
        case 1:
        case 2: return -root.barCenterOnlyOffset + Appearance.sizes.gapsOut;
        case 3: return -root.barCenterOnlyOffset - Appearance.sizes.gapsOut;
        default: return 0;
        }
    }

    // Pinned (the header's pin, Ctrl+P, IPC `sidebarRight pin`): the sidebar
    // stays open beside the windows and reserves its strip (exclusiveZone),
    // like the left one pinned. Every close (Escape, Mod+N, a click outside,
    // links, toggles) is refused; unpin first. It survives restarts and
    // reboots (Persistent states.json), on the monitor it was pinned on.
    readonly property bool pin: GlobalStates.sidebarRightPinned
    function togglePin() {
        GlobalStates.sidebarRightPinned = !GlobalStates.sidebarRightPinned;
    }
    function enforcePinnedOpen() {
        if (root.pin && !GlobalStates.sidebarRightOpen) GlobalStates.sidebarRightOpen = true;
    }
    property bool restoringPin: false
    function restorePin() {
        root.restoringPin = true; // keep the saved monitor (onPinChanged)
        GlobalStates.sidebarRightPinned = Persistent.states.sidebar.right.pinned;
        root.restoringPin = false;
        panelWindow.restorePinnedScreen();
        root.enforcePinnedOpen();
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) root.restorePin();
        }
    }
    Component.onCompleted: if (Persistent.ready) root.restorePin()
    onPinChanged: {
        root.enforcePinnedOpen();
        if (!Persistent.ready) return;
        Persistent.states.sidebar.right.pinned = root.pin;
        if (root.pin && !root.restoringPin)
            Persistent.states.sidebar.right.screen = panelWindow.screen?.name ?? WM.focusedMonitor?.name ?? "";
        // Kept mapped since before the bar was created, it would squeeze the
        // bar once it reserves its strip.
        if (root.pin) panelWindow.checkBarOrder();
    }

    // Opening the sidebar marks the notifications read (GlobalStates); pinned,
    // it doesn't open again, so going to its Notifications page does.
    Connections {
        target: Persistent.states.sidebar
        function onTabChanged() {
            if (GlobalStates.sidebarRightOpen && Persistent.states.sidebar.tab === "notifications")
                Notifications.markAllRead();
        }
    }

    // Click outside to close: its own transparent
    // full-screen window, input everywhere but over the sidebar. It used to be
    // part of the sidebar window, widened to the full screen while open, so
    // every animation, hover or tick in the sidebar re-rendered a full-screen
    // buffer. This one is drawn once when shown and then stays idle. Overlay,
    // like the sidebar, so it also covers the bar (a bar click closes the
    // sidebar, as before). Not while pinned: the sidebar is part of the layout.
    PanelWindow {
        id: outsideClickWindow
        screen: panelWindow.screen
        visible: panelWindow.reallyVisible && !root.pin
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:sidebarRightOutside"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        mask: Region {
            item: outsideClickArea
            Region {
                intersection: Intersection.Subtract
                x: outsideClickWindow.width - root.sidebarWidth
                y: 0
                width: root.sidebarWidth
                height: outsideClickWindow.height
            }
        }

        MouseArea {
            id: outsideClickArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panelWindow.hide()
        }
    }

    PanelWindow {
        id: panelWindow

        // Open, or still playing the exit animation.
        property bool reallyVisible: false

        // Kept mapped once built. Hiding a Wayland
        // window destroys its surface, and Qt's threaded renderer then throws
        // away the window's GL context; every open used to recreate it
        // (eglCreateContext + shader/glyph caches: 130–230 ms per open,
        // measured). While closed the surface stays mapped as a sidebar-wide
        // strip with no input region, no keyboard focus and invisible content
        // (opacity 0 → nothing drawn); opening only gives it input back. It
        // keeps its size, so nothing is re-laid-out either.
        property bool keepMapped: false
        visible: (reallyVisible || keepMapped) && !remapping
        Region { id: noInput }

        // Pinned, it is open from the start, and on the Overlay layer a
        // surface mapped later is drawn on top: it would show over the
        // loading screen. While the shell boots it stays mapped (its strip
        // reserved) but draws nothing and takes no input; it fades in with
        // the loading screen's fade-out (see SidebarLeft).
        readonly property bool bootHidden: Preloader.booting
        property real bootFade: Preloader.booting ? 0 : 1
        Behavior on bootFade {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic } // BootSplash's fade-out
        }

        // Niri's blur behind the body (NiriConfig.panelBlur), while open.
        // It slides with a transform, which a region isn't told about: x
        // (unused with an item) follows the slide so the region is
        // recomputed (from the item's place on screen, transform included).
        readonly property bool blurred: NiriConfig.panelBlur && panelWindow.reallyVisible && !panelWindow.bootHidden
        BackgroundEffect.blurRegion: panelWindow.blurred ? blurArea : null
        BlurCommit { blur: panelWindow.blurred }
        Region {
            id: blurArea
            item: sidebarContentLoader
            radius: Appearance.rounding.screenRounding - Appearance.sizes.gapsOut + 5 // SidebarRightContent's
            x: slide.x
        }
        mask: reallyVisible && !bootHidden ? null : noInput
        Connections {
            target: Preloader
            function onSidebarRightChanged() {
                if (Preloader.sidebarRight)
                    panelWindow.keepMapped = true;
            }
        }
        // A mapped layer surface stays on its output: follow the focused
        // monitor on open (re-creates the surface only when it changes).
        screen: null
        function followFocusedScreen() {
            const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name);
            if (s && panelWindow.screen !== s) panelWindow.screen = s;
        }
        // Pinned: back on the monitor it was pinned on. Not connected (yet),
        // it waits on the focused one and moves there once it appears.
        function restorePinnedScreen() {
            if (!root.pin) return;
            const name = Persistent.states.sidebar.right.screen;
            const s = Quickshell.screens.find(s => s.name === name);
            if (s) {
                if (panelWindow.screen !== s) panelWindow.screen = s;
            } else if (!panelWindow.screen) {
                panelWindow.followFocusedScreen();
            }
        }
        Connections {
            target: Quickshell
            function onScreensChanged() { panelWindow.restorePinnedScreen() }
        }

        // Pinned, it reserves its strip, and niri places the surfaces that
        // reserve space in the order they were mapped: mapped before the bar,
        // it squeezed the bar into the space beside it (every unlock destroys
        // the bar, startup, a screen plugged in). So when a bar is created on
        // its screen, or it gets pinned, the order is read back from niri and,
        // when it comes first, the sidebar is mapped again: behind the bar.
        property bool remapping: false
        function checkBarOrder() {
            if (!root.pin) return;
            barOrderCheck.tries = 0;
            barOrderCheck.restart();
        }
        Connections {
            target: GlobalStates
            function onBarCreated(screenName) {
                if (screenName === panelWindow.screen?.name) panelWindow.checkBarOrder();
            }
        }
        Timer {
            id: barOrderCheck
            property int tries: 0
            interval: 300 // the bar maps once it has drawn its first frame
            onTriggered: barOrderProc.running = true
        }
        Process {
            id: barOrderProc
            command: ["niri", "msg", "--json", "layers"]
            stdout: StdioCollector {
                onStreamFinished: panelWindow.applyBarOrder(text)
            }
        }
        function applyBarOrder(text) {
            if (!root.pin) return;
            let layers;
            try {
                layers = JSON.parse(text);
            } catch (e) {
                return;
            }
            const here = layers.filter(l => l.output === panelWindow.screen?.name).map(l => l.namespace);
            const sidebar = here.indexOf("quickshell:sidebarRight");
            const bar = here.findIndex(n => n === "quickshell:bar" || n === "quickshell:verticalBar");
            if (sidebar < 0) return;
            if (bar < 0) {
                if (++barOrderCheck.tries < 10) barOrderCheck.restart();
                return;
            }
            if (sidebar > bar) return;
            console.log("[SidebarRight] mapped before the bar on", panelWindow.screen?.name, "- mapping it again behind it");
            panelWindow.remapping = true;
            Qt.callLater(() => {
                panelWindow.remapping = false;
                if (++barOrderCheck.tries < 10) barOrderCheck.restart(); // confirm
            });
        }

        Component.onCompleted: reallyVisible = GlobalStates.sidebarRightOpen

        Connections {
            target: GlobalStates
            function onSidebarRightOpenChanged() {
                if (GlobalStates.sidebarRightOpen) {
                    closeAnimTimer.stop();
                    if (root.pin) panelWindow.restorePinnedScreen();
                    else panelWindow.followFocusedScreen();
                    panelWindow.reallyVisible = true;
                    panelWindow.keepMapped = true;
                } else if (root.pin) {
                    // Pinned: no closing (unpin first).
                    root.enforcePinnedOpen();
                } else {
                    GlobalStates.sidebarRightPeek = false;
                    panelWindow.peekUsed = false;
                    closeAnimTimer.restart();
                }
            }
        }

        // A peek (edge handle hover) is a glance until it is used: the pointer
        // stays inside it, away from the edge it came from, or clicks it. Until
        // then the keyboard stays with the window underneath, and leaving
        // closes it at once.
        property bool peekUsed: false
        readonly property bool glancing: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightPeek && !panelWindow.peekUsed
            && !root.pin
        Timer {
            interval: 400
            running: panelWindow.glancing && slide.x === 0 && peekHover.hovered
                && peekHover.point.position.x < entranceWrapper.width - 48
            onTriggered: panelWindow.peekUsed = true
        }

        // Close once the pointer has been outside it a moment.
        Timer {
            interval: panelWindow.glancing ? 100 : 350
            running: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightPeek && !root.pin
                && outsideClickArea.containsMouse
            onTriggered: panelWindow.hide()
        }

        Timer {
            id: closeAnimTimer
            interval: 150
            onTriggered: panelWindow.reallyVisible = false
        }

        function hide() {
            if (root.pin) return;
            GlobalStates.sidebarRightOpen = false;
        }

        // A pinned sidebar is part of the layout, not a popup: out of the
        // dismissable set (it would also keep the click catcher up).
        onReallyVisibleChanged: panelWindow.syncDismissable()
        function syncDismissable() {
            if (panelWindow.reallyVisible && !root.pin)
                GlobalFocusGrab.addDismissable(panelWindow);
            else
                GlobalFocusGrab.removeDismissable(panelWindow);
        }
        Connections {
            target: root
            function onPinChanged() { panelWindow.syncDismissable() }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (GlobalFocusGrab.spares(panelWindow) || root.pin) return;
                panelWindow.hide();
            }
        }

        exclusionMode: ExclusionMode.Normal
        exclusiveZone: root.pin ? sidebarWidth : 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        // Overlay so it stays above GlobalFocusGrab's click catcher (Top).
        WlrLayershell.layer: WlrLayer.Overlay
        // Open panels take the keyboard (see SidebarLeft): OnDemand only got it
        // after a click on this kept-mapped surface. Pinned, it is permanent:
        // click-to-focus only.
        WlrLayershell.keyboardFocus: !GlobalStates.sidebarRightOpen || panelWindow.glancing || panelWindow.bootHidden
            ? WlrKeyboardFocus.None
            : root.pin ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        margins {
            top: Config.options.bar.bottom ? 0 : root.barEdgeMargin
            bottom: Config.options.bar.bottom ? root.barEdgeMargin : 0
        }

        Item {
            anchors.fill: parent

            Item {
                id: entranceWrapper
                // Nothing drawn while closed (the surface stays mapped).
                // (≈invisible while booting: draws once so textures are uploaded)
                opacity: panelWindow.reallyVisible
                    ? Math.max(panelWindow.bootFade, Preloader.prerender ? 0.004 : 0)
                    : (Preloader.prerender ? 0.004 : 0)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: sidebarWidth
                clip: true

                readonly property bool open: GlobalStates.sidebarRightOpen
                // On the panel itself, not on the item on top below: hover goes
                // to the topmost item under the pointer and its ancestors, so a
                // HoverHandler on a covering item took it from every HoverHandler
                // inside (the Mesh tab's message buttons never showed).
                HoverHandler { id: peekHover }
                // On top of everything inside: a widget's own MouseArea would keep the
                // press from a handler on the panel itself.
                Item {
                    anchors.fill: parent
                    z: 1000
                    PointHandler {
                        acceptedButtons: Qt.AllButtons
                        onActiveChanged: if (active) panelWindow.peekUsed = true
                    }
                }
                // A peek (edge handle hover) slides in at the dock's pace.
                readonly property var enterAnim: GlobalStates.sidebarRightPeek
                    ? Appearance.animation.elementMoveFast
                    : Appearance.animation.sidebarSlideEnter
                // Right-anchored and slid with a transform (no re-layout while
                // it slides).
                anchors.right: parent.right
                transform: Translate {
                    id: slide
                    x: !entranceWrapper.open ? entranceWrapper.width : 0
                    Behavior on x {
                        NumberAnimation {
                            duration: entranceWrapper.open
                                ? entranceWrapper.enterAnim.duration
                                : Appearance.animation.sidebarSlideExit.duration
                            easing.type: entranceWrapper.open
                                ? entranceWrapper.enterAnim.type
                                : Appearance.animation.sidebarSlideExit.type
                            easing.bezierCurve: entranceWrapper.open
                                ? entranceWrapper.enterAnim.bezierCurve
                                : Appearance.animation.sidebarSlideExit.bezierCurve
                        }
                    }
                }

                MouseArea {
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                    z: -1
                }

                Loader {
                    id: sidebarContentLoader
                    active: panelWindow.reallyVisible || Config?.options.sidebar.keepRightSidebarLoaded
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.gapsOut
                        leftMargin: Appearance.sizes.elevationMargin
                    }
                    width: sidebarWidth - Appearance.sizes.gapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.gapsOut * 2

                    focus: GlobalStates.sidebarRightOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                            root.togglePin();
                            event.accepted = true;
                        }
                    }

                    sourceComponent: SidebarRightContent {}
                }
            }
        }

        IpcHandler {
            target: "sidebarRight"

            function toggle(): void {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }

            function close(): void {
                GlobalStates.sidebarRightOpen = false;
            }

            function open(): void {
                GlobalStates.sidebarRightOpen = true;
            }

            // Pinned: open beside the windows, its strip reserved.
            function pin(): void {
                GlobalStates.sidebarRightPinned = true;
            }

            function unpin(): void {
                GlobalStates.sidebarRightPinned = false;
            }

            function togglePin(): void {
                root.togglePin();
            }
        }
    }
}
