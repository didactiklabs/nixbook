import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Covers a lock or login screen while the machine shuts down or restarts:
 * closing the apps and then systemd's shutdown take several seconds, during
 * which the screen otherwise stayed as it was, as if the click did nothing.
 * `action`: "poweroff" or "reboot" (empty: hidden); `detail`: a second line.
 */
Rectangle {
    id: root
    property string action: ""
    property string detail: ""
    readonly property bool shown: action !== ""

    anchors.fill: parent
    color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.15)
    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Nothing under it takes clicks or hovers any more.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Column {
        anchors.centerIn: parent
        spacing: 18

        MaterialLoadingIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: 72
            loading: root.shown
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnLayer0
            text: root.action === "reboot" ? Translation.tr("Restarting…") : Translation.tr("Shutting down…")
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            color: Appearance.colors.colSubtext
            text: root.detail
        }
    }
}
