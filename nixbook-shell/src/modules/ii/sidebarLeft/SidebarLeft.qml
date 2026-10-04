import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland

Scope { // Scope
    id: root
    property bool detach: false
    property bool pin: false
    // Extended (Ctrl+O), for the toolbar's state (SidebarLeftContent).
    readonly property bool extended: sidebarLoader.item?.extend ?? false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical
    readonly property real barCenterOnlyOffset: (Config.options.bar.centerOnlyReserveFrame && root.centerOnly)
        ? Config.options.bar.frameThickness
        : Appearance.sizes.barHeight

    // Ctrl+O extend and Ctrl+P pin (docked), Ctrl+D detach/attach — from
    // the panel's key handler or its text fields (GlobalStates.sidebarLeftKey).
    Connections {
        target: GlobalStates
        function onSidebarLeftShortcut(key) {
            if (key === Qt.Key_D) root.toggleDetach();
            else if (root.detach) return;
            else if (key === Qt.Key_O && sidebarLoader.item) sidebarLoader.item.extend = !sidebarLoader.item.extend;
            else if (key === Qt.Key_P) root.togglePin();
        }
        function onSidebarLeftOpenChanged() {
            root.enforcePinnedOpen();
            if (Persistent.ready && root.pin) Persistent.states.sidebar.left.open = GlobalStates.sidebarLeftOpen;
        }
    }

    // Pinned and docked, the sidebar reserves its strip (exclusiveZone):
    // closed, it would leave a blank space. Every close (Escape, toggle/close
    // IPC, keybinds, links) is refused; unpin first.
    readonly property bool forcedOpen: root.pin && !root.detach
    function enforcePinnedOpen() {
        if (root.forcedOpen && !GlobalStates.sidebarLeftOpen) GlobalStates.sidebarLeftOpen = true;
    }
    onForcedOpenChanged: root.enforcePinnedOpen()

    // Pinned survives restarts and reboots (Persistent states.json); a
    // pinned sidebar is always open, on the monitor it was pinned on.
    property bool restoringPin: false
    function restorePin() {
        root.restoringPin = true; // keep the saved monitor (onPinChanged)
        root.pin = Persistent.states.sidebar.left.pinned;
        root.restoringPin = false;
        sidebarLoader.item?.restorePinnedScreen();
        root.enforcePinnedOpen();
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) root.restorePin();
        }
    }
    onPinChanged: {
        if (!Persistent.ready) return;
        Persistent.states.sidebar.left.pinned = root.pin;
        Persistent.states.sidebar.left.open = root.pin && GlobalStates.sidebarLeftOpen;
        if (root.pin && !root.restoringPin)
            Persistent.states.sidebar.left.screen = sidebarLoader.item?.screen?.name ?? WM.focusedMonitor?.name ?? "";
    }

    function toggleDetach() {
        root.detach = !root.detach;
    }

    function togglePin() {
        root.pin = !root.pin;
    }

    Component.onCompleted: {
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        root.sidebarContent.parent = sidebarLoader.item.contentParent; // append (keeps the Persona texture child)
        if (Persistent.ready) root.restorePin();
    }

    onDetachChanged: {
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            sidebarContent.parent = detachedSidebarLoader.item.contentParent; // append (keeps the Persona texture child)
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarContent.parent = sidebarLoader.item.contentParent; // append (keeps the Persona texture child)
        }
        // The content moved to another window: give its input the keyboard again.
        Qt.callLater(() => root.sidebarContent?.focusActiveItem());
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow

            // Open, or still playing the exit animation.
            property bool reallyVisible: false
            // Stays mapped once opened (see SidebarRight: hiding destroys the
            // surface and Qt rebuilt the GL context on every open). Closed =
            // no input region, no keyboard focus, transparent content.
            property bool keepMapped: false
            visible: reallyVisible || keepMapped
            Connections {
                target: Preloader
                function onSidebarLeftChanged() {
                    if (Preloader.sidebarLeft && !root.detach)
                        panelWindow.keepMapped = true;
                }
            }
            function followFocusedScreen() {
                const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name);
                if (s && panelWindow.screen !== s) panelWindow.screen = s;
            }
            // Pinned: back on the monitor it was pinned on. Not connected (yet:
            // a dock or external screen can show up after the shell starts),
            // it waits on the focused one and moves there once it appears.
            function restorePinnedScreen() {
                if (!root.pin || root.detach) return;
                const name = Persistent.states.sidebar.left.screen;
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

            Component.onCompleted: {
                panelWindow.restorePinnedScreen(); // re-attached (Ctrl+D) while pinned
                reallyVisible = GlobalStates.sidebarLeftOpen;
            }

            Connections {
                target: GlobalStates
                function onSidebarLeftOpenChanged() {
                    if (GlobalStates.sidebarLeftOpen) {
                        closeAnimTimer.stop();
                        if (root.pin) panelWindow.restorePinnedScreen();
                        else panelWindow.followFocusedScreen();
                        panelWindow.reallyVisible = true;
                        panelWindow.keepMapped = true;
                        // Focus the current tab (the chat's input): without an
                        // active focus item the panel got the keyboard but every
                        // key — typing, Ctrl+O/P/D — went nowhere until a click.
                        Qt.callLater(() => root.sidebarContent?.focusActiveItem());
                    } else {
                        closeAnimTimer.restart();
                    }
                }
            }

            Timer {
                id: closeAnimTimer
                interval: Appearance.animation.elementMoveExit.duration
                onTriggered: panelWindow.reallyVisible = false
            }

            property bool extend: false
            property real sidebarWidth: panelWindow.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.leftSidebarWidth
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.pin ? sidebarWidth : 0
            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Overlay so it stays above GlobalFocusGrab's click catcher (Top).
            WlrLayershell.layer: WlrLayer.Overlay
            // Open panels take the keyboard (Exclusive): these surfaces stay mapped
            // once built, so niri never sees them "open" and an OnDemand surface
            // only got the keyboard after a click — typing went to the window
            // underneath. Closing releases it.
            // A pinned sidebar is permanent: click-to-focus only.
            WlrLayershell.keyboardFocus: !panelWindow.reallyVisible ? WlrKeyboardFocus.None
                : root.pin ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            margins {
                top: {
                    if (Config.options.bar.bottom) return 0;
                    if (Config?.options.bar.autoHide.enable) return 0;
                    if (!centerOnly) return 0;
                    switch (Config.options.bar.cornerStyle) {
                    case 0: return -root.barCenterOnlyOffset;
                    case 1: return -root.barCenterOnlyOffset + Appearance.sizes.gapsOut;
                    case 2: return -root.barCenterOnlyOffset + Appearance.sizes.gapsOut;
                    case 3: return -root.barCenterOnlyOffset - Appearance.sizes.gapsOut;
                    default: return 0;
                    }
                }
                bottom: {
                    if (!Config.options.bar.bottom) return 0;
                    if (Config?.options.bar.autoHide.enable) return 0;
                    if (!centerOnly) return 0;
                    switch (Config.options.bar.cornerStyle) {
                    case 0: return -root.barCenterOnlyOffset;
                    case 1: return -root.barCenterOnlyOffset + Appearance.sizes.gapsOut;
                    case 2: return -root.barCenterOnlyOffset + Appearance.sizes.gapsOut;
                    case 3: return -root.barCenterOnlyOffset - Appearance.sizes.gapsOut;
                    default: return 0;
                    }
                }
            }

            // Pinned, only the panel's own reserved strip takes input: the
            // window is wider (extended width, shadow), and that transparent
            // rest lies over the windows beside it.
            mask: !panelWindow.reallyVisible ? noInput : root.pin ? pinnedMask : openMask
            Region {
                id: openMask
                item: fullMaskArea
            }
            Region {
                id: pinnedMask
                item: pinnedMaskArea
            }
            Region { id: noInput }

            // A pinned sidebar is part of the layout, not a popup: keep it out
            // of the dismissable set (it would also keep the click catcher up).
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

            // Content
            Item {
                id: fullMaskArea
                anchors.fill: parent
            }
            Item {
                id: pinnedMaskArea
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: panelWindow.sidebarWidth
            }

            // Beside the panel: closes it, unless pinned (part of the layout).
            MouseArea {
                hoverEnabled: true
                cursorShape: root.pin ? Qt.ArrowCursor : Qt.PointingHandCursor
                id: outsideClickArea
                anchors.fill: parent
                onClicked: if (!root.pin) panelWindow.hide()
            }

            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
                visible: !Persona.shapes // PersonaFrame draws its own hard shadow
            }
            Rectangle {
                id: sidebarLeftBackground
                anchors.top: parent.top
                anchors.topMargin: Appearance.sizes.gapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.gapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.gapsOut * 2
                // Persona style: the slanted comic-panel frame (same as the
                // popups) replaces the rounded body.
                color: Persona.shapes ? "transparent" : Appearance.colors.colLayer0
                border.width: Persona.shapes ? 0 : 1
                border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8)
                radius: Appearance.rounding.screenRounding - Appearance.sizes.gapsOut + 1

                PersonaFrame {
                    visible: Persona.shapes
                    anchors.fill: parent
                    z: -1
                    color: Appearance.colors.colLayer0
                    maxLean: 10
                }
                // Background art without the frame (shapes off, art on)
                PersonaTexture {
                    visible: Persona.halftone && !Persona.shapes
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                    opacity: 0.55
                }
                // Chiikawa theme: stars and hearts, the character in the corner
                ChiikawaDecor {
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                }
                // Ghibli theme: leaves, paper birds or fireflies, the spirit in the corner
                GhibliDecor {
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                }

                readonly property bool sidebarOpen: GlobalStates.sidebarLeftOpen
                // Nothing drawn while closed (the surface stays mapped).
                // (≈invisible while booting: draws once so textures are uploaded)
                opacity: panelWindow.reallyVisible ? 1 : (Preloader.prerender ? 0.004 : 0)
                x: Appearance.sizes.gapsOut - (!sidebarOpen ? width : 0)

                Behavior on x {
                    NumberAnimation {
                        duration: sidebarLeftBackground.sidebarOpen
                            ? Appearance.animation.elementMoveEnter.duration
                            : Appearance.animation.elementMoveExit.duration
                        easing.type: sidebarLeftBackground.sidebarOpen
                            ? Appearance.animation.elementMoveEnter.type
                            : Appearance.animation.elementMoveExit.type
                        easing.bezierCurve: sidebarLeftBackground.sidebarOpen
                            ? Appearance.animation.elementMoveEnter.bezierCurve
                            : Appearance.animation.elementMoveExit.bezierCurve
                    }
                }

                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                MouseArea {
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (GlobalStates.sidebarLeftKey(event)) event.accepted = true;
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0

                Keys.onPressed: (event) => {
                    if (GlobalStates.sidebarLeftKey(event)) event.accepted = true;
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }
}
