import QtQuick

MouseArea {
    hoverEnabled: true
    anchors.fill: parent
    onPressed: (mouse) => mouse.accepted = false
    cursorShape: Qt.PointingHandCursor
}