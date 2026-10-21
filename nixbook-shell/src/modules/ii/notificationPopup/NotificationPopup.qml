import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

Scope {
    id: notificationPopup

    // Critical notifications (and the cut-in rules): the full-screen Persona
    // cut-in in the Persona theme, the character's speech bubble in the
    // Chiikawa theme, the incoming holocall in the Cyberpunk theme, the
    // frosted-glass card on the wind in the Ghibli theme (loaded only then).
    PersonaCutIn {}
    // Claude speaking first: its own bubble, on the left, in the theme's look.
    AgentSpeech {}
    LazyLoader {
        active: Chiikawa.enabled
        component: ChiikawaAlert {}
    }
    LazyLoader {
        active: Cyberpunk.enabled
        component: CyberpunkCutIn {}
    }
    LazyLoader {
        active: Ghibli.enabled
        component: GhibliCutIn {}
    }

    // Stays mapped while unlocked (hiding a Wayland window destroys its
    // surface, and Qt then rebuilt the GL context on the next notification:
    // 100–200 ms per popup). The window hugs the notification list instead of
    // covering the screen, so an empty list costs a 1 px transparent surface
    // with no input region.
    PanelWindow {
        id: root
        visible: !GlobalStates.screenLocked && !GlobalStates.dynamicIslandEnabled
        // Follows the focused monitor only while showing something: moving a
        // mapped surface recreates it.
        readonly property bool hasPopups: Notifications.popupList.length > 0
        onHasPopupsChanged: if (hasPopups) root.followFocusedScreen()
        Component.onCompleted: root.followFocusedScreen()
        function followFocusedScreen() {
            const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null;
            if (s && root.screen !== s) root.screen = s;
        }

        property string position: {
            const raw = Config.options.notifications.position ?? "top_right"
            if (raw === "top") return "top_right"
            if (raw === "bottom") return "bottom_right"
            return raw
        }
        property bool isTop: position.startsWith("top")
        property bool isBottom: position.startsWith("bottom")
        property bool isCenter: position.endsWith("center")
        property bool isLeft: position.endsWith("left")
        property bool isRight: position.endsWith("right")

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        // Typing an inline reply in a popup needs the keyboard.
        WlrLayershell.keyboardFocus: Notifications.replyingPopups > 0 && !MakeWay.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusiveZone: 0

        anchors {
            top: root.isTop
            bottom: root.isBottom
            left: root.isLeft
            right: root.isRight
        }

        // An agent working underneath (services/MakeWay.qml): clicks go
        // through, faded, gone from its screenshots.
        mask: MakeWay.active ? noInput : listRegion
        Region {
            id: listRegion
            item: listview.contentItem
        }
        Region { id: noInput }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth + 8
        // In 128 px steps: an expanding popup animates the content height, and
        // a surface resize per frame is a configure and new buffers each. The
        // slack is transparent and outside the input mask.
        implicitHeight: listview.contentHeight > 0 ? Math.ceil((listview.contentHeight + 8) / 128) * 128 : 1

        NotificationListView {
            id: listview
            anchors.fill: parent
            anchors.leftMargin: root.isLeft ? 4 : 0
            anchors.rightMargin: root.isRight ? 4 : 0
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            popup: true
            interactive: false
            opacity: MakeWay.fade(0.5, "notificationPopups")
            verticalLayoutDirection: root.isBottom ? ListView.BottomToTop : ListView.TopToBottom
        }
    }
}
