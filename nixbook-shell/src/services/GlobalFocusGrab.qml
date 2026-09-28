pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars.
 **/
 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    // Consistent popup dismissal:
    //  - opening a dismissable popup closes the other ones (popups sharing a
    //    non-empty `group`, e.g. media controls + equalizer, may coexist);
    //  - clicking outside every popup closes them (Hyprland: the focus grab
    //    below; other compositors: the click catcher at the bottom of this
    //    file, since hyprland_focus_grab_v1 doesn't exist there);
    //  - switching workspace closes them.
    // onDismissed handlers skip themselves via `spares(window)` when they
    // belong to the popup (group) that is being opened.
    property var groupOf: new Map()
    property var sparedWindow: null
    property string sparedGroup: ""

    function spares(window) {
        if (!root.sparedWindow)
            return false;
        return window === root.sparedWindow
            || (root.sparedGroup !== "" && root.groupOf.get(window) === root.sparedGroup);
    }

    function dismiss() {
        root.sparedWindow = null;
        root.sparedGroup = "";
        root.dismissable = [];
        root.dismissed();
    }

    function dismissExcept(window, group) {
        root.sparedWindow = window;
        root.sparedGroup = group;
        root.dismissed();
        root.dismissable = root.dismissable.filter(w => root.spares(w));
        root.sparedWindow = null;
        root.sparedGroup = "";
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized" + (WM.compositor !== "hyprland" ? " (inactive, non-Hyprland compositor)" : ""));
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            root.persistent.push(window);
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            root.persistent.splice(index, 1);
        }
    }

    function addDismissable(window, group = "") {
        root.groupOf.set(window, group);
        const others = root.dismissable.some(w => w !== window && !(group !== "" && root.groupOf.get(w) === group));
        if (others)
            root.dismissExcept(window, group);
        if (root.dismissable.indexOf(window) === -1) {
            root.dismissable.push(window);
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            root.dismissable.splice(index, 1);
        }
    }

    function hasActive(element) {
        return element?.activeFocus || Array.from(
            element?.children ?? []
        ).some(
            (child) => hasActive(child)
        );
    }

    // Workspace switches close popups too (compared by id: the backend
    // republishes the workspace objects on unrelated updates).
    property var lastWorkspaceId: undefined
    Connections {
        target: WM
        function onActiveWorkspaceChanged() {
            const id = WM.activeWorkspace?.id;
            if (id === undefined)
                return;
            if (root.lastWorkspaceId !== undefined && id !== root.lastWorkspaceId && root.dismissable.length > 0)
                root.dismiss();
            root.lastWorkspaceId = id;
        }
    }

    // Non-Hyprland click-outside: a transparent catcher on every screen, on the
    // Top layer (dismissable popups live on Overlay, so they stay above it),
    // with the bar cut out so bar widgets keep working in one click.
    readonly property bool catcherActive: WM.compositor !== "hyprland" && root.dismissable.length > 0
    readonly property bool barVertical: Config.options?.bar?.vertical ?? false
    readonly property bool barBottom: Config.options?.bar?.bottom ?? false
    readonly property real barThickness: (root.barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) + (Appearance.sizes.hyprlandGapsOut ?? 0)

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: catcher
            required property var modelData
            screen: modelData
            visible: root.catcherActive
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:dismissCatcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            mask: Region {
                item: catchArea
                Region {
                    intersection: Intersection.Subtract
                    x: (root.barVertical && root.barBottom) ? catcher.width - root.barThickness : 0
                    y: (!root.barVertical && root.barBottom) ? catcher.height - root.barThickness : 0
                    width: root.barVertical ? root.barThickness : catcher.width
                    height: root.barVertical ? catcher.height : root.barThickness
                }
            }

            MouseArea {
                id: catchArea
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.dismiss()
            }
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: root.dismissable.every(w => !w?.focusable) || root.dismissable.some(w => root.hasActive(w?.contentItem)) ? [...root.dismissable, ...root.persistent] : [...root.dismissable]
        active: WM.compositor === "hyprland" && root.dismissable.length > 0
        onCleared: () => {
            root.dismiss();
        }
    }
}