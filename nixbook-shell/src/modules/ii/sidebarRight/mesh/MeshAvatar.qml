import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Widgets

// A mesh member's picture (services/Mesh.qml avatarOf: the account picture
// they share), else their initial in a circle.
Rectangle {
    id: root
    property string memberId
    property real size: 28
    // On a toggled (primary) chip.
    property bool onPrimary: false
    readonly property string source: Mesh.avatarOf(root.memberId)

    implicitWidth: root.size
    implicitHeight: root.size
    radius: root.size / 2
    color: root.onPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondaryContainer

    StyledText {
        anchors.centerIn: parent
        visible: photo.status !== Image.Ready
        text: Mesh.nameOf(root.memberId).charAt(0).toUpperCase()
        font.pixelSize: root.size * 0.45
        font.weight: Font.DemiBold
        color: root.onPrimary ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: photo.status === Image.Ready
        Image {
            id: photo
            anchors.fill: parent
            source: root.source
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
}
