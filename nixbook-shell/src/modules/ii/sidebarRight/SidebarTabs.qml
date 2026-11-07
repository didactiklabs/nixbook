pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
// Quickshell only serves directories that are imported, Loader sources included.
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.notifications
import qs.modules.ii.sidebarRight.pomodoro
import qs.modules.ii.sidebarRight.todo
import QtQuick
import QtQuick.Layouts

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
        readonly property real otherTabWidth: Math.max(44, innerWidth / (root.tabs.length + 1.4))
        readonly property real currentTabWidth: innerWidth - otherTabWidth * (root.tabs.length - 1)

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
        // shown/hidden (the calendar straight away, it's the heavy one):
        // swapping one Loader's source rebuilt it on every switch, mid-fade.
        Item {
            id: tabStack
            anchors.fill: parent
            anchors.rightMargin: -anchors.leftMargin
            property int shownTab: -1
            property bool forward: true

            Component.onCompleted: {
                // From here on it changes halfway through the animation.
                tabStack.shownTab = root.selectedTab;
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
                    script: tabStack.shownTab = root.selectedTab
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

            Repeater {
                model: root.tabs
                delegate: Loader {
                    required property var modelData
                    required property int index
                    anchors.fill: parent
                    anchors.margins: 8
                    active: tabStack.shownTab === index || item !== null || modelData.type === "calendar"
                    visible: tabStack.shownTab === index
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
                    visible: tabButton.current
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
