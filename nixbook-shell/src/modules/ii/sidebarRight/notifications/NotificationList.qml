import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    // History (NotificationHistory) instead of the live notifications.
    property bool showHistory: false
    // "Delete all" needs a second click within 3 s.
    property bool confirmClear: false
    Timer {
        id: confirmTimer
        interval: 3000
        onTriggered: root.confirmClear = false
    }

    NotificationHistoryView {
        visible: root.showHistory
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        anchors.bottomMargin: 5
    }

    NotificationListView { // Scrollable window
        id: listview
        visible: !root.showHistory
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        anchors.bottomMargin: 5

        clip: true
        // The mask only matters when rows scroll under the rounded corners:
        // without overflow the cards' own radius (the same) already rounds
        // them, and the list isn't redrawn offscreen on every hover/animation.
        // Applied a turn later (Qt.callLater): these depend on sizes, and switching
        // a layer on or off in the middle of a geometry change crashed Qt.
        readonly property bool layerWanted: listview.contentHeight > listview.height
        property bool layerOn: true
        function applyLayer() { listview.layerOn = listview.layerWanted; }
        onLayerWantedChanged: Qt.callLater(listview.applyLayer)
        Component.onCompleted: Qt.callLater(listview.applyLayer)
        layer.enabled: listview.layerOn
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: listview.width
                height: listview.height
                radius: Appearance.rounding.normal
            }
        }

        popup: false
    }

    // Placeholder when list is empty
    PagePlaceholder {
        shown: !root.showHistory && Notifications.list.length === 0
        icon: "notifications_active"
        description: Translation.tr("Nothing")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    ButtonGroup {
        id: statusRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        NotificationStatusButton {
            visible: !root.showHistory
            Layout.fillWidth: false
            buttonIcon: "notifications_paused"
            toggled: Notifications.silent
            onClicked: () => {
                Notifications.silent = !Notifications.silent;
            }
        }
        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "history"
            toggled: root.showHistory
            onClicked: () => {
                root.showHistory = !root.showHistory;
                root.confirmClear = false;
            }
            StyledToolTip {
                text: Translation.tr("Notification history")
            }
        }
        NotificationStatusButton {
            enabled: false
            Layout.fillWidth: true
            buttonText: root.showHistory
                ? Translation.tr("%1 in history").arg(NotificationHistory.entries.length)
                : Translation.tr("%1 notifications").arg(Notifications.list.length)
        }
        NotificationStatusButton {
            visible: !root.showHistory
            Layout.fillWidth: false
            buttonIcon: "delete_sweep"
            onClicked: () => {
                Notifications.discardAllNotifications()
            }
        }
        // History: delete older than 7 / 30 days, or everything.
        Repeater {
            model: root.showHistory ? [7, 30] : []
            delegate: NotificationStatusButton {
                required property int modelData
                Layout.fillWidth: false
                enabled: NotificationHistory.countOlderThan(modelData) > 0
                buttonText: Translation.tr("> %1 d").arg(modelData)
                onClicked: NotificationHistory.deleteOlderThan(modelData)
                StyledToolTip {
                    text: Translation.tr("Delete the %1 entries older than %2 days")
                        .arg(NotificationHistory.countOlderThan(modelData)).arg(modelData)
                }
            }
        }
        NotificationStatusButton {
            visible: root.showHistory
            Layout.fillWidth: false
            enabled: NotificationHistory.entries.length > 0
            buttonIcon: root.confirmClear ? "" : "delete_forever"
            buttonText: root.confirmClear ? Translation.tr("Delete all?") : ""
            toggled: root.confirmClear
            onClicked: () => {
                if (!root.confirmClear) {
                    root.confirmClear = true;
                    confirmTimer.restart();
                    return;
                }
                root.confirmClear = false;
                NotificationHistory.clear();
            }
            StyledToolTip {
                text: Translation.tr("Delete the whole history")
            }
        }
    }
}