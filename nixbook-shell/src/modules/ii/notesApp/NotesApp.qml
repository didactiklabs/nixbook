import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Notes: the desktop notes widget's notes (services/Notes.qml) as an app.
 * The notes on the left (search, pinned first, then the latest edited), the
 * selected one in a full editor on the right, saved as you type.
 *
 * A normal application window (xdg-toplevel, title "Notes"), tiled like any
 * app: its layout follows the width it gets. Opened from the notes widget
 * (a note, its title or ⤢: GlobalStates.openNotesApp), its launcher entry
 * or `nixbook-shell ipc call notes open [id]`.
 */
Scope {
    id: root

    property bool everOpened: false

    Connections {
        target: GlobalStates
        function onNotesAppOpenChanged() {
            if (GlobalStates.notesAppOpen) root.everOpened = true
        }
    }

    Loader {
        active: root.everOpened

        sourceComponent: FloatingWindow {
            id: notesWindow
            title: Translation.tr("Notes")
            visible: GlobalStates.notesAppOpen
            implicitWidth: 1100
            implicitHeight: 760
            minimumSize: Qt.size(360, 400)
            color: Appearance.colors.colLayer0Base

            // The compositor closing it (Mod+Q…) closes the app; what is
            // being typed is saved first.
            onClosed: {
                content.flush()
                GlobalStates.notesAppOpen = false
            }
            onVisibleChanged: {
                if (!visible) {
                    content.flush()
                    if (GlobalStates.notesAppOpen) GlobalStates.notesAppOpen = false
                } else {
                    content.opened(GlobalStates.notesAppNoteId)
                }
            }
            Component.onCompleted: content.opened(GlobalStates.notesAppNoteId)

            // Another note clicked in the widget while it is open.
            Connections {
                target: GlobalStates
                function onNotesAppNoteIdChanged() {
                    if (notesWindow.visible && GlobalStates.notesAppNoteId)
                        content.opened(GlobalStates.notesAppNoteId)
                }
            }

            NotesAppContent {
                id: content
                anchors.fill: parent
                focus: true
            }
        }
    }
}
