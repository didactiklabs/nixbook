import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ⋮ on a task list: Rename, Delete (`action` "rename" | "delete").
Rectangle {
    id: root
    property color iconColor: Appearance.colors.colOnLayer1
    signal action(string action)

    implicitWidth: 32
    implicitHeight: 32
    radius: 16
    color: menuMouse.containsMouse || menu.opened ? Appearance.colors.colLayer1Hover : "transparent"

    MaterialSymbol {
        anchors.centerIn: parent
        text: "more_vert"
        iconSize: Appearance.font.pixelSize.larger
        color: root.iconColor
    }
    MouseArea {
        id: menuMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.open()
    }

    Popup {
        id: menu
        y: root.height + 4
        x: Math.min(0, -(width - root.width))
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3Base
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        contentItem: ColumnLayout {
            spacing: 2
            Repeater {
                model: [
                    { action: "rename", icon: "edit", text: Translation.tr("Rename list") },
                    { action: "delete", icon: "delete", text: Translation.tr("Delete list") },
                ]
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    Layout.fillWidth: true
                    implicitWidth: entryRow.implicitWidth + 32
                    implicitHeight: 40
                    radius: Appearance.rounding.small
                    color: entryMouse.containsMouse ? Appearance.colors.colLayer3Hover : "transparent"
                    RowLayout {
                        id: entryRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 10
                        MaterialSymbol {
                            text: entry.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: entry.modelData.action === "delete" ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            text: entry.modelData.text
                            color: entry.modelData.action === "delete" ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                        }
                    }
                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menu.close()
                            root.action(entry.modelData.action)
                        }
                    }
                }
            }
        }
    }
}
