import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A pill button of the tasks panel: icon, text, an optional count on the
// right. `filled`: the primary "Create" look; `toggled`: a selected chip.
Rectangle {
    id: root
    property string icon: ""
    property color iconColor: root.foreground
    property string text: ""
    property string trailingText: ""
    property bool filled: false
    property bool toggled: false
    property bool compact: false
    readonly property color foreground: root.filled ? Appearance.colors.colOnPrimaryContainer
        : root.toggled ? Appearance.colors.colOnSecondaryContainer
        : Appearance.colors.colOnLayer1
    signal clicked()

    implicitHeight: root.compact ? 32 : 42
    implicitWidth: row.implicitWidth + (root.compact ? 24 : 32)
    radius: Appearance.rounding.full
    color: {
        if (root.filled) return mouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
        if (root.toggled) return mouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
        return mouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
    }
    border.width: root.compact && !root.toggled ? 1 : 0
    border.color: Appearance.colors.colOutlineVariant
    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.compact ? 12 : 16
            rightMargin: root.compact ? 12 : 16
        }
        spacing: root.compact ? 6 : 12

        MaterialSymbol {
            visible: root.icon !== ""
            text: root.icon
            iconSize: root.compact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
            color: root.iconColor
        }
        StyledText {
            Layout.fillWidth: true
            text: root.text
            elide: Text.ElideRight
            font.pixelSize: root.compact ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.small
            font.weight: root.filled ? Font.Medium : Font.Normal
            color: root.foreground
        }
        StyledText {
            visible: root.trailingText !== ""
            text: root.trailingText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
