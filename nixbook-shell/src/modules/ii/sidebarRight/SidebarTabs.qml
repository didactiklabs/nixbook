pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
// Quickshell only serves directories that are imported, Loader sources included.
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.jellyfin
import qs.modules.ii.sidebarRight.youtube
import qs.modules.ii.sidebarRight.youtubeMusic
import qs.modules.ii.sidebarRight.mesh
import qs.modules.ii.sidebarRight.notifications
import qs.modules.ii.sidebarRight.pomodoro
import qs.modules.ii.sidebarRight.todo
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The right sidebar's main area: one page at a time, filling what the header,
 * toggles and sliders leave. Each page gets the whole height, so notifications
 * aren't squeezed by a calendar that is always there.
 */
ColumnLayout {
    id: root
    spacing: 8

    readonly property var tabs: {
        const list = [{
            "type": "notifications",
            "name": Translation.tr("Notifications"),
            "icon": "notifications",
            "widget": "notifications/NotificationList.qml"
        }];
        // The mesh's conversations (services/Mesh.qml), once it is set up.
        if (Mesh.configured) {
            list.push({
                "type": "mesh",
                "name": Translation.tr("Mesh"),
                "icon": "hub",
                "widget": "mesh/MeshWidget.qml"
            });
        }
        // Jellyfin's up next and recently added: on by default, shown once
        // Jellyfin is signed in on this computer.
        if (Config.options.sidebar.jellyfinTab && Jellyfin.ready) {
            list.push({
                "type": "jellyfin",
                "name": Translation.tr("Jellyfin"),
                "icon": "live_tv",
                "widget": "jellyfin/JellyfinWidget.qml"
            });
        }
        // YouTube Music in the background: on by default, shown signed out
        // too (how to sign in).
        if (Config.options.sidebar.youtubeMusicTab) {
            list.push({
                "type": "youtubeMusic",
                "name": Translation.tr("YouTube Music"),
                "icon": "queue_music",
                "widget": "youtubeMusic/YouTubeMusicWidget.qml"
            });
        }
        // YouTube's videos (home, subscriptions, a search), played in mpv:
        // on by default, searchable signed out too.
        if (Config.options.sidebar.youtubeTab) {
            list.push({
                "type": "youtube",
                "name": Translation.tr("YouTube"),
                "icon": "smart_display",
                "widget": "youtube/YouTubeWidget.qml"
            });
        }
        if (Config.options.sidebar.bottomGroup) {
            list.push({
                "type": "calendar",
                "name": Translation.tr("Calendar"),
                "icon": "calendar_month",
                "widget": "calendar/CalendarWidget.qml"
            }, {
                "type": "todo",
                "name": Translation.tr("To Do"),
                "icon": "done_outline",
                "widget": "todo/TodoWidget.qml"
            }, {
                "type": "timer",
                "name": Translation.tr("Timer"),
                "icon": "schedule",
                "widget": "pomodoro/PomodoroWidget.qml"
            });
        }
        return list;
    }
    readonly property int selectedTab: Math.max(0, tabs.findIndex(tab => tab.type === Persistent.states.sidebar.tab))
    property int previousIndex: -1

    function selectTab(index) {
        const tab = root.tabs[Math.max(0, Math.min(index, root.tabs.length - 1))];
        Persistent.states.sidebar.tab = tab.type;
    }

    // Something arrived while the panel was closed: that's what it opens on.
    // Opening marks them read, so this has to be noted when they come in.
    property bool notifiedWhileClosed: false
    Connections {
        target: Notifications
        function onUnreadChanged() {
            if (Notifications.unread > 0 && !GlobalStates.sidebarRightOpen)
                root.notifiedWhileClosed = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen && root.notifiedWhileClosed)
                root.selectTab(0);
            root.notifiedWhileClosed = false;
        }
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            root.selectTab(root.selectedTab + (event.key === Qt.Key_PageDown ? 1 : -1));
            event.accepted = true;
        }
    }

    // Tab strip: the current tab shows its name, the others just their icon.
    Rectangle {
        id: tabStrip
        Layout.fillWidth: true
        visible: root.tabs.length > 1
        implicitHeight: 44
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1

        readonly property real padding: 4
        readonly property real spacing: 2
        readonly property real innerWidth: width - padding * 2 - spacing * (root.tabs.length - 1)
        // The open tab gets the room its icon and name need (the others
        // narrower, down to 36 px each, when there are many tabs); a name
        // still too long is elided in it rather than drawn over its
        // neighbours.
        readonly property real currentWanted: 22 + 6 + currentName.advanceWidth + 28
        readonly property real otherTabWidth: root.tabs.length < 2 ? 0 : Math.max(36, Math.min(innerWidth / (root.tabs.length + 1.4), (innerWidth - currentWanted) / (root.tabs.length - 1)))
        readonly property real currentTabWidth: innerWidth - otherTabWidth * (root.tabs.length - 1)

        TextMetrics {
            id: currentName
            text: root.tabs[root.selectedTab]?.name ?? ""
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
        }

        Row {
            anchors.fill: parent
            anchors.margins: tabStrip.padding
            spacing: tabStrip.spacing

            Repeater {
                model: root.tabs
                delegate: TabButton {}
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        clip: true

        // Each page is built on its first visit and kept, then only
        // shown/hidden (the calendar and the notifications straight away, see below):
        // swapping one Loader's source rebuilt it on every switch, mid-fade.
        Item {
            id: tabStack
            anchors.fill: parent
            anchors.rightMargin: -anchors.leftMargin
            // The page shown, by type: pages are kept when tabs come or go,
            // so an index would point at another one.
            property string shownType: ""
            property bool forward: true

            Component.onCompleted: {
                // From here on it changes halfway through the animation.
                tabStack.shownType = root.tabs[root.selectedTab]?.type ?? "";
                root.previousIndex = root.selectedTab;
            }

            Connections {
                target: root
                function onSelectedTabChanged() {
                    tabStack.forward = root.selectedTab > root.previousIndex;
                    root.previousIndex = root.selectedTab;
                    tabSwitch.restart();
                }
            }

            SequentialAnimation {
                id: tabSwitch
                ParallelAnimation {
                    PropertyAnimation {
                        target: tabStack
                        properties: "opacity"
                        to: 0
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                    PropertyAnimation {
                        target: tabStack.anchors
                        properties: "leftMargin"
                        to: tabStack.forward ? -10 : 10
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                // Read here, not bound in a PropertyAction: that kept the
                // value from before the switch.
                ScriptAction {
                    script: tabStack.shownType = root.tabs[root.selectedTab]?.type ?? ""
                }
                ParallelAnimation {
                    PropertyAnimation {
                        target: tabStack.anchors
                        properties: "leftMargin"
                        from: tabStack.forward ? 10 : -10
                        to: 0
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                    PropertyAnimation {
                        target: tabStack
                        properties: "opacity"
                        to: 1
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
            }

            // Keyed by type: the list is rebuilt whenever a tab comes or goes
            // (Mesh set up, Jellyfin signed in, a setting), and a plain array
            // made the Repeater destroy every page, built again on the next
            // visit (the notifications page: ~0.3 s).
            Repeater {
                model: ScriptModel {
                    values: root.tabs
                    objectProp: "type"
                }
                delegate: Loader {
                    required property var modelData
                    anchors.fill: parent
                    anchors.margins: 8
                    // Built up front: the calendar (heavy), and the
                    // notifications, the first tab and the one the panel opens
                    // on when something arrived. Built on its first click it
                    // froze the switch ~0.4 s, mid-fade; with the panel (kept
                    // loaded, built at startup) it costs nothing in view.
                    active: tabStack.shownType === modelData.type || item !== null || modelData.type === "calendar"
                        || modelData.type === "notifications"
                    visible: tabStack.shownType === modelData.type
                    source: modelData.widget
                }
            }
        }
    }

    component TabButton: RippleButton {
        id: tabButton
        required property int index
        required property var modelData
        readonly property bool current: root.selectedTab === index
        // The list says how many on its own page.
        readonly property int badge: !current && modelData.type === "notifications" ? Notifications.list.length : 0

        width: current ? tabStrip.currentTabWidth : tabStrip.otherTabWidth
        height: parent.height
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        buttonRadius: Appearance.rounding.full
        toggled: current
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        onClicked: root.selectTab(index)

        contentItem: Item {
            Row {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    id: tabIcon
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: 22
                    fill: tabButton.current ? 1 : 0
                    text: tabButton.modelData.icon
                    color: tabButton.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

                    Rectangle {
                        visible: tabButton.badge > 0
                        anchors {
                            horizontalCenter: parent.right
                            verticalCenter: parent.top
                            horizontalCenterOffset: -2
                            verticalCenterOffset: 3
                        }
                        width: Math.max(height, badgeText.implicitWidth + 7)
                        height: 16
                        radius: height / 2
                        color: Appearance.colors.colPrimary
                        StyledText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: tabButton.badge
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    // What's left beside the icon: elided past it.
                    width: Math.min(implicitWidth, tabButton.width - tabIcon.width - parent.spacing - 20)
                    visible: tabButton.current && width > 24
                    elide: Text.ElideRight
                    text: tabButton.modelData.name
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        StyledToolTip {
            extraVisibleCondition: !tabButton.current
            text: tabButton.modelData.name
        }
    }
}
