import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

// The notes on the desktop, pinned first then the latest edited. "+" jots
// one down in a quick floating editor; a note, the title or ⤢ opens the
// Notes app (modules/ii/notesApp), which shows the same notes.
AbstractBackgroundWidget {
    id: root
    configEntryName: "notes"
    hoverEnabled: true

    implicitWidth: 276
    implicitHeight: 252

    // The note open in the floating editor: {} for a new note, null when closed
    property var editingNote: null

    function openNewNote() { root.editingNote = {} }

    LazyLoader {
        active: root.editingNote !== null
        component: NoteEditorWindow {
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            noteId: root.editingNote?.id ?? null
            initialText: root.editingNote?.content ?? ""
            createdAt: root.editingNote?.createdAt ?? 0
            onDismissed: root.editingNote = null
        }
    }

    Item {
        id: cardWrapper
        anchors.fill: parent

        WidgetShadow { 
            target: contentRect
            visible: Config.options.background.widgets.shadow
        }
        WidgetOutline {
            target: contentRect
        }

        Rectangle {
            id: contentRect
            anchors.fill: parent
            color: Appearance.colors.colWidgetCard
            radius: Appearance.rounding?.verylarge ?? 30

            FastBlurred {
                anchors.fill: parent
                blurSource: root.wallpaperItem
                cardRadius: contentRect.radius
                tint: Appearance.colors.colLayer1
                tintOpacity: 0.55
                trackX: root.x  
                trackY: root.y
                visible: Config.options.background.widgets.blurWidgets 
            }

            // List
            ColumnLayout {
                id: listPage
                anchors { fill: parent; margins: 12 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.topMargin: -4
                        Layout.leftMargin: 8
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                        text: "Notes"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.openNotesApp("")
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
                        color: expandMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "open_in_full"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            id: expandMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.openNotesApp("")
                        }
                        PopupToolTip {
                            text: Translation.tr("Open Notes")
                            extraVisibleCondition: expandMouse.containsMouse
                        }
                    }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "add"
                        onClicked: root.openNewNote()
                    }
                }

                StyledListView {
                    id: notesListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    // Keyed by the note's id, so a save elsewhere (the Notes
                    // app autosaves as you type) doesn't rebuild the list and
                    // scroll it back to the top.
                    model: ScriptModel {
                        values: Notes.sorted
                        objectProp: "id"
                    }

                    delegate: SwipeDelegate {
                        id: noteCard
                        required property var modelData
                        required property int index

                        width: notesListView.width
                        // Up to three lines of the note; the editor shows the rest.
                        implicitHeight: Math.max(55, preview.implicitHeight + 24)
                        padding: 0
                        background: null
                        clip: true

                        property color bg: {
                            const cyclePos = index % 3
                            if (cyclePos === 0) return Appearance.colors.colPrimary
                            if (cyclePos === 1) return Appearance.colors.colSecondary
                            return Appearance.colors.colTertiary
                        }
                        property color fg: {
                            const cyclePos = index % 3
                            if (cyclePos === 0) return Appearance.colors.colOnPrimary
                            if (cyclePos === 1) return Appearance.colors.colOnSecondary
                            return Appearance.colors.colOnTertiary
                        }

                        // A click (not a swipe) opens the note in the Notes app.
                        onClicked: if (swipe.position === 0) GlobalStates.openNotesApp(noteCard.modelData.id)

                        contentItem: Rectangle {
                            radius: Appearance.rounding.normal
                            color: noteCard.bg
                            width: parent.width - Math.abs(noteCard.swipe.position) * 6

                            StyledText {
                                id: preview
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 12; rightMargin: noteCard.modelData.pinned ? 30 : 12
                                }
                                color: noteCard.fg
                                linkColor: noteCard.fg
                                // Links open in the browser; a click anywhere
                                // else opens the note.
                                textFormat: Text.StyledText
                                text: StringUtils.linkify(noteCard.modelData.content.trim(), preview.hoveredUrl,
                                    ColorUtils.mix(noteCard.fg, noteCard.bg, 0.6))
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                maximumLineCount: 3
                                onLinkActivated: (link) => AppLaunch.openUrl(link)

                                // The link under the pointer (hoveredLink reads
                                // the global cursor position, unknown on Wayland).
                                readonly property string hoveredUrl: previewHover.hovered
                                    ? preview.linkAt(previewHover.point.position.x, previewHover.point.position.y) : ""
                                HoverHandler {
                                    id: previewHover
                                    cursorShape: preview.hoveredUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }
                        }

                        MaterialSymbol {
                            anchors { right: parent.right; top: parent.top; margins: 8 }
                            visible: !!noteCard.modelData.pinned
                            text: "push_pin"
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            color: noteCard.fg
                        }

                        swipe.right: Rectangle {
                            width: 64
                            anchors.right: parent.right
                            height: parent.height
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colError

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnError
                            }

                            SwipeDelegate.onClicked: Notes.deleteNote(noteCard.modelData.id)
                        }
                    }
                }
            }
        }
    }
}