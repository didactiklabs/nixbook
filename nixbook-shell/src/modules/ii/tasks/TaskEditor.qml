pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A new task: title, details, due date, and (`showListPicker`) the list it
// goes to. Enter adds it; with `keepOpen` the form stays for the next one
// (as in a list column), Escape closes it.
ColumnLayout {
    id: root
    property string listId: Todo.defaultListId
    property bool showListPicker: false
    property bool keepOpen: false
    property var due: null
    signal saved(string listId)
    signal done()

    spacing: 10

    function start() {
        titleField.text = ""
        notesField.text = ""
        root.due = null
        if (!Todo.lists.some(l => l.id === root.listId)) root.listId = Todo.defaultListId
        titleField.forceActiveFocus()
    }

    function save() {
        const title = titleField.text.trim()
        if (title.length === 0) {
            root.done()
            return
        }
        Todo.addTask(title, { listId: root.listId, notes: notesField.text.trim(), due: root.due })
        root.saved(root.listId)
        if (root.keepOpen) root.start()
        else root.done()
    }

    StyledText {
        visible: root.showListPicker
        text: Translation.tr("New task")
        font.pixelSize: Appearance.font.pixelSize.huge
        color: Appearance.colors.colOnLayer3
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: fields.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2Base
        border.width: titleField.activeFocus || notesField.activeFocus ? 2 : 1
        border.color: titleField.activeFocus || notesField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

        ColumnLayout {
            id: fields
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
            }
            spacing: 0

            TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Title")
                placeholderTextColor: Appearance.colors.colSubtext
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.main
                background: null
                onAccepted: root.save()
                Keys.onEscapePressed: event => {
                    root.done()
                    event.accepted = true
                }
            }
            TextArea {
                id: notesField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Details")
                placeholderTextColor: Appearance.colors.colSubtext
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.family: Appearance.font.family.main
                wrapMode: TextEdit.Wrap
                background: null
                // Enter adds the task, Shift+Enter starts a new line.
                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) event.accepted = false
                    else root.save()
                }
                Keys.onEscapePressed: event => {
                    root.done()
                    event.accepted = true
                }
            }
        }
    }

    DueChips {
        Layout.fillWidth: true
        due: root.due
        onDueEdited: due => root.due = due
    }

    StyledText {
        visible: root.showListPicker
        Layout.topMargin: 4
        text: Translation.tr("List")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    Flow {
        visible: root.showListPicker
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: Todo.lists
            delegate: PanelButton {
                required property var modelData
                compact: true
                icon: "list"
                iconColor: modelData.color || foreground
                text: modelData.name
                toggled: root.listId === modelData.id
                onClicked: root.listId = modelData.id
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        PanelButton {
            compact: true
            text: root.keepOpen ? Translation.tr("Close") : Translation.tr("Cancel")
            onClicked: root.done()
        }
        PanelButton {
            compact: true
            filled: true
            icon: "add"
            text: Translation.tr("Add")
            opacity: titleField.text.trim().length > 0 ? 1 : 0.5
            onClicked: root.save()
        }
    }
}
