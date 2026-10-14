import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A task in a list column: the round checkbox, its title, the start of its
// notes, its deadline (red once overdue, highlighted when due today), its
// list (`showList`). A click selects it; delete on hover.
Item {
    id: root
    required property var task
    property int depth: 0
    property bool selected: false
    property bool showList: false
    readonly property string group: Todo.deadlineGroup(root.task)
    readonly property bool overdue: !root.task.done && root.group === "overdue"
    readonly property bool dueToday: !root.task.done && root.group === "today"
    signal clicked()

    implicitHeight: content.implicitHeight + 20

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.selected ? Appearance.colors.colSecondaryContainer
            : rowMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    RowLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: 10
            leftMargin: 10 + root.depth * 32
            rightMargin: rowMouse.containsMouse || deleteMouse.containsMouse ? 48 : 12
        }
        spacing: 12

        // Checkbox
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 24
            implicitHeight: 24
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.task.done ? Appearance.colors.colPrimary : "transparent"
                border.width: 2
                border.color: root.task.done ? Appearance.colors.colPrimary
                    : checkMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.task.done || checkMouse.containsMouse
                text: "check"
                iconSize: Appearance.font.pixelSize.normal
                color: root.task.done ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
            }
            MouseArea {
                id: checkMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Todo.setTaskDone(root.task, !root.task.done)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.task.content
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.strikeout: root.task.done
                color: root.task.done ? Appearance.colors.colSubtext
                    : root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.task.done && (root.task.notes ?? "") !== ""
                text: root.task.notes ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            RowLayout {
                visible: !!root.task.due || root.showList
                spacing: 8
                Rectangle {
                    visible: !!root.task.due
                    implicitHeight: 24
                    implicitWidth: dueRow.implicitWidth + 16
                    radius: Appearance.rounding.full
                    color: root.overdue ? Appearance.colors.colErrorContainer
                        : root.dueToday ? Appearance.colors.colPrimaryContainer : "transparent"
                    border.width: root.overdue || root.dueToday ? 0 : 1
                    border.color: Appearance.colors.colOutlineVariant
                    RowLayout {
                        id: dueRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: root.overdue ? "alarm" : "event"
                            iconSize: Appearance.font.pixelSize.small
                            color: dueText.color
                        }
                        StyledText {
                            id: dueText
                            text: Todo.dueText(root.task.due)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.overdue ? Appearance.colors.colOnErrorContainer
                                : root.dueToday ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                }
                // "3 days overdue", "Due in 5 days" (today/tomorrow say it already).
                StyledText {
                    visible: text !== "" && !["today", "tomorrow"].includes(root.group)
                    text: Todo.deadlineText(root.task)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.overdue ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
                StyledText {
                    visible: root.showList
                    text: Todo.listName(root.task.listId)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    Rectangle {
        anchors {
            right: parent.right
            rightMargin: 8
            top: parent.top
            topMargin: 6
        }
        visible: rowMouse.containsMouse || deleteMouse.containsMouse
        implicitWidth: 34
        implicitHeight: 34
        radius: 17
        color: deleteMouse.containsMouse ? Appearance.colors.colErrorContainer : "transparent"
        MaterialSymbol {
            anchors.centerIn: parent
            text: "delete"
            iconSize: Appearance.font.pixelSize.larger
            color: deleteMouse.containsMouse ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
        }
        MouseArea {
            id: deleteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Todo.deleteTask(root.task)
        }
    }
}
