import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A round icon button of the Contacts app, with its tooltip; `toggled`
// fills it (a starred contact's star).
Rectangle {
    id: button
    property string icon
    property string tip
    property bool toggled: false
    signal clicked()
    implicitWidth: 40
    implicitHeight: 40
    radius: 20
    color: button.toggled ? Appearance.colors.colSecondaryContainer
        : buttonMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
    MaterialSymbol {
        anchors.centerIn: parent
        text: button.icon
        iconSize: Appearance.font.pixelSize.larger
        fill: button.toggled ? 1 : 0
        color: button.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
    }
    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    PopupToolTip {
        text: button.tip
        extraVisibleCondition: buttonMouse.containsMouse
    }
}
