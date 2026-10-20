pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// The Notes window's content: the notes (search, pinned first) on the left,
// the selected one's editor on the right, saved as you type; an emptied
// note is dropped when you leave it. Deleting offers Undo for a few seconds.
// Ctrl+N new note, Ctrl+F search, Ctrl+P pin. Narrow (tiled in a slim
// column): the list, then the note full width with a back arrow.
Rectangle {
    id: root
    color: Appearance.colors.colLayer0Base
    clip: true

    // The note in the editor ("" for none, or a new one not saved yet).
    property string selectedId: ""
    // A new note being written: saved (added) with its first character.
    property bool draft: false
    readonly property var selected: root.selectedId ? (Notes.list.find(n => n.id === root.selectedId) ?? null) : null
    // Its pin and dates, a new object on every change (the note object
    // itself stays the same when edited, so bindings on it wouldn't update).
    readonly property var meta: {
        const n = Notes.list.find(n => n.id === root.selectedId)
        return n ? { pinned: !!n.pinned, createdAt: n.createdAt, updatedAt: n.updatedAt || n.createdAt } : null
    }
    readonly property bool editing: root.draft || root.selected !== null
    readonly property bool narrow: root.width < 760
    // Narrow: the editor page instead of the list.
    property bool editorPage: false
    property string query: ""
    readonly property var shown: {
        const q = root.query.trim().toLowerCase()
        return q ? Notes.sorted.filter(n => n.content.toLowerCase().includes(q)) : Notes.sorted
    }
    // The last deleted note, for Undo.
    property var deleted: null
    // The Google Keep panel (the sync of the notes with Keep).
    property bool keepOpen: false

    function opened(noteId) {
        if (noteId && Notes.list.some(n => n.id === noteId)) root.select(noteId)
        else if (!root.editing && Notes.sorted.length > 0 && !root.narrow) root.select(Notes.sorted[0].id)
        root.forceActiveFocus()
    }

    function select(noteId) {
        root.leave()
        root.draft = false
        root.selectedId = noteId
        editor.load()
        root.editorPage = true
    }

    function newNote() {
        root.leave()
        root.selectedId = ""
        root.draft = true
        editor.load()
        root.editorPage = true
        editor.focusText()
    }

    // Saves what is pending; drops the note being left if it is empty.
    function leave() {
        root.flush()
        const note = root.selected
        if (note && note.content.trim() === "") Notes.deleteNote(note.id)
    }

    function flush() {
        if (saveTimer.running) root.save()
    }

    function save() {
        saveTimer.stop()
        const text = editor.text
        if (root.draft) {
            if (text.trim() === "") return
            root.draft = false
            root.selectedId = Notes.addNote(text)
        } else if (root.selected && text !== root.selected.content) {
            Notes.updateNote(root.selectedId, text)
        }
    }

    function deleteSelected() {
        saveTimer.stop()
        if (root.draft) {
            root.draft = false
        } else if (root.selected) {
            root.deleted = Object.assign({}, root.selected, { content: editor.text })
            Notes.deleteNote(root.selectedId)
            undoTimer.restart()
        }
        root.selectedId = ""
        root.editorPage = false
        editor.load()
    }

    function undoDelete() {
        if (!root.deleted) return
        undoTimer.stop()
        Notes.restoreNote(root.deleted)
        const id = root.deleted.id
        root.deleted = null
        root.select(id)
    }

    // "14:32" today, "Mon 14:32" this week, "Oct 3", "Oct 3, 2025".
    function when(ms) {
        if (!ms) return ""
        const d = new Date(ms)
        const now = new Date()
        const fmt = Config.options?.time.format ?? "hh:mm"
        const days = Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        if (days === 0) return Qt.locale().toString(d, fmt)
        if (days < 7) return `${Qt.locale().toString(d, "ddd")} ${Qt.locale().toString(d, fmt)}`
        return Qt.locale().toString(d, d.getFullYear() === now.getFullYear() ? "MMM d" : "MMM d, yyyy")
    }
    function titleOf(content) {
        return content.split("\n").map(l => l.trim()).find(l => l !== "") ?? ""
    }
    function previewOf(content) {
        // List markers dropped: "- milk" reads "milk" between the dots.
        const lines = content.split("\n").map(l => l.trim().replace(/^([-*•]|\[[ x]\])\s+/, "")).filter(l => l !== "")
        return lines.slice(1).join(" · ")
    }

    Timer {
        id: saveTimer
        interval: 600
        onTriggered: root.save()
    }
    // The shell reloading right after typing: what is pending is saved.
    Component.onDestruction: root.flush()
    Timer {
        id: undoTimer
        interval: 6000
        onTriggered: root.deleted = null
    }

    // Agents and the widget edit notes too: follow their changes while
    // nothing typed here waits to be saved.
    Connections {
        target: Notes
        function onListChanged() {
            if (root.draft || !root.selectedId) return
            const note = root.selected
            if (!note) {
                // Removed elsewhere: what is typed here becomes a new note.
                if (saveTimer.running) {
                    root.draft = true
                    root.selectedId = ""
                } else {
                    root.selectedId = ""
                    root.editorPage = false
                    editor.load()
                }
                return
            }
            if (!saveTimer.running && note.content !== editor.text) editor.load()
        }
    }

    Keys.onPressed: event => {
        if (!(event.modifiers & Qt.ControlModifier)) return
        if (event.key === Qt.Key_N) {
            root.newNote()
            event.accepted = true
        } else if (event.key === Qt.Key_F) {
            if (root.narrow) root.editorPage = false
            searchField.forceActiveFocus()
            event.accepted = true
        } else if (event.key === Qt.Key_P && root.meta) {
            Notes.setPinned(root.selectedId, !root.meta.pinned)
            event.accepted = true
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // The notes
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: root.narrow
            Layout.preferredWidth: root.narrow ? -1 : 340
            visible: !root.narrow || !root.editorPage
            color: Appearance.colors.colLayer1Base

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 10
                    MaterialSymbol {
                        text: "sticky_note_2"
                        iconSize: 28
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Notes")
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnLayer1
                    }
                    PanelButton {
                        icon: "cloud_sync"
                        text: Translation.tr("Keep")
                        toggled: root.keepOpen
                        onClicked: root.keepOpen = !root.keepOpen
                    }
                    PanelButton {
                        icon: "edit_note"
                        text: Translation.tr("New")
                        filled: true
                        onClicked: root.newNote()
                    }
                }

                // Search
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2Base
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 8
                        MaterialSymbol {
                            text: "search"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Search notes")
                            placeholderTextColor: Appearance.colors.colSubtext
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.main
                            background: null
                            onTextChanged: root.query = text
                            Keys.onEscapePressed: event => {
                                text = ""
                                root.forceActiveFocus()
                                event.accepted = true
                            }
                            // Enter opens the first match.
                            onAccepted: if (root.shown.length > 0) root.select(root.shown[0].id)
                        }
                        MaterialSymbol {
                            visible: searchField.text !== ""
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: searchField.text = ""
                            }
                        }
                    }
                }

                // The Google Keep sync (services/KeepSync.qml).
                KeepPanel {
                    Layout.fillWidth: true
                    visible: root.keepOpen
                    onSyncRequested: {
                        // What is being typed is saved first: the sync sends
                        // the notes as they are.
                        root.flush()
                        KeepSync.sync()
                    }
                }

                StyledListView {
                    id: notesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    // Keyed by the note's id: a save changes that note's row
                    // (or moves it) instead of rebuilding the list, which
                    // jumped back to the top on every autosave.
                    model: ScriptModel {
                        values: root.shown
                        objectProp: "id"
                    }

                    delegate: Rectangle {
                        id: noteItem
                        required property var modelData
                        readonly property bool current: !root.draft && root.selectedId === modelData.id
                        width: notesList.width
                        implicitHeight: itemColumn.implicitHeight + 22
                        radius: Appearance.rounding.normal
                        color: noteItem.current ? Appearance.colors.colSecondaryContainer
                            : itemMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.select(noteItem.modelData.id)
                        }

                        ColumnLayout {
                            id: itemColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 14
                                rightMargin: 12
                            }
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                MaterialSymbol {
                                    visible: !!noteItem.modelData.pinned
                                    text: "push_pin"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colPrimary
                                }
                                // The overlay's Notes scratchpad.
                                MaterialSymbol {
                                    visible: !!noteItem.modelData.scratchpad
                                    text: "note_stack"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.titleOf(noteItem.modelData.content) || Translation.tr("Empty note")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: noteItem.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    text: root.when(noteItem.modelData.updatedAt || noteItem.modelData.createdAt)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: root.previewOf(noteItem.modelData.content)
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 20
                    visible: root.shown.length === 0
                    text: root.query ? Translation.tr("No note matches \"%1\"").arg(root.query.trim()) : Translation.tr("No notes yet. Ctrl+N starts one")
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            visible: !root.narrow
            Layout.fillHeight: true
            implicitWidth: 1
            color: Appearance.colors.colOutlineVariant
        }

        // The note
        Item {
            id: editor
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.narrow || root.editorPage

            property alias text: noteText.text
            function load() {
                saveTimer.stop()
                const cursor = noteText.cursorPosition
                noteText.text = root.selected?.content ?? ""
                noteText.cursorPosition = Math.min(cursor, noteText.length)
            }
            function focusText() {
                noteText.forceActiveFocus()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6
                visible: root.editing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    NoteButton {
                        visible: root.narrow
                        icon: "arrow_back"
                        tip: Translation.tr("All notes")
                        onClicked: {
                            root.leave()
                            root.editorPage = false
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            const n = root.meta
                            if (!n) return Translation.tr("New note")
                            const edited = n.updatedAt && n.updatedAt - n.createdAt > 60000
                            return edited ? Translation.tr("Edited %1 · created %2").arg(root.when(n.updatedAt)).arg(root.when(n.createdAt))
                                : Translation.tr("Created %1").arg(root.when(n.createdAt))
                        }
                    }
                    NoteButton {
                        visible: root.selected !== null
                        icon: "push_pin"
                        toggled: !!root.meta?.pinned
                        tip: root.meta?.pinned ? Translation.tr("Unpin (Ctrl+P)") : Translation.tr("Pin to the top (Ctrl+P)")
                        onClicked: Notes.setPinned(root.selectedId, !root.meta.pinned)
                    }
                    NoteButton {
                        icon: "content_copy"
                        tip: Translation.tr("Copy the note")
                        onClicked: Quickshell.clipboardText = noteText.text
                    }
                    NoteButton {
                        icon: "delete"
                        tip: Translation.tr("Delete")
                        onClicked: root.deleteSelected()
                    }
                }

                Flickable {
                    id: textFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: noteText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    ScrollBar.vertical: StyledScrollBar {}

                    TextArea.flickable: TextArea {
                        id: noteText
                        // A comfortable reading width, centred.
                        leftPadding: Math.max(16, (textFlick.width - 760) / 2)
                        rightPadding: leftPadding
                        topPadding: 12
                        bottomPadding: 40
                        placeholderText: Translation.tr("Write something… the first line is its title")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer0
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.main
                        wrapMode: TextEdit.Wrap
                        background: null
                        onTextChanged: if (activeFocus) saveTimer.restart()
                        onActiveFocusChanged: if (!activeFocus) root.flush()
                        selectByMouse: true

                        // Links: a click opens one in the browser.
                        TextLinks {
                            textArea: noteText
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignRight
                    Layout.rightMargin: 8
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: {
                        const t = noteText.text.trim()
                        const words = t ? t.split(/\s+/).length : 0
                        return Translation.tr("%1 words · %2 characters").arg(words).arg(noteText.length)
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.editing
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "sticky_note_2"
                    iconSize: 64
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Notes.list.length > 0 ? Translation.tr("Pick a note, or start a new one") : Translation.tr("Your notes will show here")
                    color: Appearance.colors.colSubtext
                }
                PanelButton {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "edit_note"
                    text: Translation.tr("New note")
                    filled: true
                    onClicked: root.newNote()
                }
            }
        }
    }

    // Undo after a delete
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        visible: root.deleted !== null
        implicitWidth: undoRow.implicitWidth + 32
        implicitHeight: 48
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3inverseSurface
        RowLayout {
            id: undoRow
            anchors.centerIn: parent
            spacing: 16
            StyledText {
                text: Translation.tr("Note deleted")
                color: Appearance.m3colors.m3inverseOnSurface
            }
            StyledText {
                text: Translation.tr("Undo")
                font.weight: Font.Medium
                color: Appearance.m3colors.m3inversePrimary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.undoDelete()
                }
            }
        }
    }

    component NoteButton: Rectangle {
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
}
