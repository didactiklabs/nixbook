import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Widgets

// A contact's photo, else their initials in a circle.
Rectangle {
    id: root
    property var contact: null
    property real size: 40

    implicitWidth: root.size
    implicitHeight: root.size
    radius: root.size / 2
    color: Appearance.colors.colSecondaryContainer

    StyledText {
        anchors.centerIn: parent
        visible: photo.status !== Image.Ready
        text: Contacts.initials(root.contact)
        font.pixelSize: root.size * 0.4
        font.weight: Font.Medium
        color: Appearance.colors.colOnSecondaryContainer
    }
    // Only the photo is clipped round: the initials show without it.
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: photo.status === Image.Ready
        Image {
            id: photo
            anchors.fill: parent
            // Google serves the size asked for (=sNN); other photos (a
            // server's link, a file) as they are.
            source: {
                const url = root.contact?.photo ?? "";
                if (!/^https:\/\/[^/]*googleusercontent\.com\//.test(url))
                    return url;
                return url.replace(/=s\d+(-c)?$/, "") + `=s${Math.round(root.size * 2)}`;
            }
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
    }
}
