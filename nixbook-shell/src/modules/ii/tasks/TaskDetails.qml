pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The selected task, editable: title, details, due date, list; mark it
// done, delete it. Text is saved as you type (after a pause) and when it
// loses focus.
Rectangle {
    id: root
    property var task: null
    signal closeRequested()

    color: Appearance.colors.colLayer0Base
    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: Appearance.colors.colOutlineVariant
    }

    // What is shown of it: a copy made on every change of the list (edits
    // change the task object in place, which bindings on it don't see).
    readonly property var info: {
        Todo.list
        return root.task ? Object.assign({}, root.task) : null
    }

    // Another task: reload the fields (not when a sync hands back the same
    // task, so what is being typed stays).
    readonly property string taskKey: root.task ? (root.task.id || `local:${Todo.list.indexOf(root.task)}`) : ""
    onTaskKeyChanged: {
        saveTimer.stop()
        titleField.text = root.task?.content ?? ""
        notesField.text = root.task?.notes ?? ""
    }

    function save() {
        saveTimer.stop()
        if (!root.task) return
        Todo.updateTask(root.task, { content: titleField.text.trim(), notes: notesField.text })
    }

    Timer {
        id: saveTimer
        interval: 900
        onTriggered: root.save()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Task details")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
            Repeater {
                model: [
                    { icon: "delete", tip: Translation.tr("Delete") },
                    { icon: "close", tip: Translation.tr("Close") },
                ]
                delegate: Rectangle {
                    id: headerButton
                    required property var modelData
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 18
                    color: headerMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: headerButton.modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: headerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (headerButton.modelData.icon === "delete") {
                                saveTimer.stop()
                                Todo.deleteTask(root.task)
                            } else {
                                root.save()
                            }
                            root.closeRequested()
                        }
                    }
                    PopupToolTip {
                        text: headerButton.modelData.tip
                        extraVisibleCondition: headerMouse.containsMouse
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Item {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 8
                implicitWidth: 26
                implicitHeight: 26
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: root.info?.done ? Appearance.colors.colPrimary : "transparent"
                    border.width: 2
                    border.color: root.info?.done || doneMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.info?.done || doneMouse.containsMouse
                    text: "check"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.info?.done ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                }
                MouseArea {
                    id: doneMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Todo.setTaskDone(root.task, !root.task.done)
                }
            }
            TextArea {
                id: titleField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Title")
                placeholderTextColor: Appearance.colors.colSubtext
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.hugeass
                font.family: Appearance.font.family.main
                font.strikeout: root.info?.done ?? false
                wrapMode: TextEdit.Wrap
                background: null
                onTextChanged: if (activeFocus) saveTimer.restart()
                onActiveFocusChanged: if (!activeFocus) root.save()
                // A title is one line: Enter moves on to the details.
                Keys.onReturnPressed: notesField.forceActiveFocus()
            }
        }

        // Details
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 10
                text: "notes"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(96, notesField.implicitHeight + 8)
                radius: Appearance.rounding.small
                color: notesField.activeFocus ? Appearance.colors.colLayer1Base : "transparent"
                border.width: 1
                border.color: notesField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                TextArea {
                    id: notesField
                    anchors.fill: parent
                    anchors.margins: 4
                    placeholderText: Translation.tr("Add details")
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    wrapMode: TextEdit.Wrap
                    background: null
                    onTextChanged: if (activeFocus) saveTimer.restart()
                    onActiveFocusChanged: if (!activeFocus) root.save()
                }
            }
        }

        // Due date
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
                text: "event"
                iconSize: Appearance.font.pixelSize.larger
                color: Todo.isOverdue(root.info) ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    text: root.info?.due ? Translation.tr("Deadline: %1").arg(Todo.dueText(root.info.due)) : Translation.tr("No deadline")
                    font.weight: Font.Medium
                    color: Todo.isOverdue(root.info) ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                }
                StyledText {
                    visible: text !== ""
                    text: Todo.deadlineText(root.info)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Todo.isOverdue(root.info) ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
                DueChips {
                    Layout.fillWidth: true
                    due: root.info?.due ?? null
                    onDueEdited: due => Todo.updateTask(root.task, { due: due })
                }
            }
        }

        // List
        RowLayout {
            Layout.fillWidth: true
            visible: Todo.lists.length > 1
            spacing: 12
            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
                text: "list"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Todo.lists
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        text: modelData.name
                        toggled: root.info?.listId === modelData.id
                        onClicked: {
                            root.save()
                            Todo.moveTask(root.task, modelData.id)
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            visible: Todo.synced && !(root.info?.id)
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Syncing…")
        }

        PanelButton {
            Layout.fillWidth: true
            filled: !(root.info?.done ?? false)
            icon: root.info?.done ? "undo" : "check"
            text: root.info?.done ? Translation.tr("Mark uncompleted") : Translation.tr("Mark completed")
            onClicked: {
                root.save()
                Todo.setTaskDone(root.task, !root.task.done)
            }
        }
    }
}
