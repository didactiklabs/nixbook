pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Floating editor for one note, opened from the notes desktop widget.
 * Changes are kept when it closes (Escape, the close button, a click outside
 * the card); Ctrl+S saves without closing. A long note scrolls.
 */
PanelWindow {
    id: root

    // null for a new note
    property var noteId: null
    property string initialText: ""
    property real createdAt: 0
    // Emitted once the close animation has run: the loader drops the window.
    signal dismissed()

    property bool closing: false
    readonly property bool dirty: textArea.text !== root.initialText

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:noteEditor"
    WlrLayershell.layer: WlrLayer.Overlay
    // Takes the keyboard while open so typing works right away.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function save() {
        const text = textArea.text
        if (!root.dirty || text.trim().length === 0) return
        if (root.noteId) {
            Notes.updateNote(root.noteId, text)
        } else {
            root.noteId = Notes.addNote(text)
            root.createdAt = Date.now()
        }
        root.initialText = text
    }

    function close() {
        if (root.closing) return
        root.save()
        root.closing = true
        closeAnim.start()
    }

    function deleteNote() {
        root.closing = true
        if (root.noteId) Notes.deleteNote(root.noteId)
        root.initialText = textArea.text // nothing left to save
        closeAnim.start()
    }

    // Desktop agents edit the notes too (the `notes` IPC target). While
    // nothing is unsaved here, follow their changes; if they remove the note,
    // close, or keep unsaved text to save it as a new note.
    Connections {
        target: Notes
        function onListChanged() {
            if (root.closing || !root.noteId) return
            const note = Notes.list.find(n => n.id === root.noteId)
            if (!note) {
                if (root.dirty) {
                    root.noteId = null
                    root.createdAt = 0
                    root.initialText = ""
                } else {
                    root.closing = true
                    closeAnim.start()
                }
                return
            }
            if (!root.dirty && note.content !== root.initialText) {
                const cursor = textArea.cursorPosition
                root.initialText = note.content
                textArea.text = note.content
                textArea.cursorPosition = Math.min(cursor, textArea.length)
            }
        }
    }

    Component.onCompleted: {
        textArea.text = root.initialText
        textArea.cursorPosition = textArea.length
        textArea.forceActiveFocus()
        openAnim.start()
    }

    // Scrim: a click outside the card closes (and saves).
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.close()
        }
    }

    Item {
        id: card
        width: Math.min(640, root.width - 64)
        height: Math.min(Math.max(360, root.height * 0.6), root.height - 64)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        scale: 0.9
        opacity: 0

        StyledRectangularShadow {
            target: cardBg
        }

        Rectangle {
            id: cardBg
            anchors.fill: parent
            radius: Appearance.rounding.verylarge
            // Opaque: the layer colours are translucent in some themes, and the
            // windows behind made the text hard to read.
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        // Swallow clicks so they don't reach the scrim.
        MouseArea {
            anchors.fill: parent
            onClicked: textArea.forceActiveFocus()
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 12

            // Header, also the handle to move the card
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Item {
                    Layout.fillWidth: true
                    implicitHeight: headerCol.implicitHeight

                    ColumnLayout {
                        id: headerCol
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 8
                        }
                        spacing: 0

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            text: root.noteId ? "Note" : "New note"
                        }
                        StyledText {
                            visible: root.createdAt > 0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Qt.formatDateTime(new Date(root.createdAt), Qt.locale().dateTimeFormat(Locale.ShortFormat))
                        }
                    }

                    DragHandler {
                        target: card
                        cursorShape: Qt.ClosedHandCursor
                        xAxis.minimum: 0
                        xAxis.maximum: root.width - card.width
                        yAxis.minimum: 0
                        yAxis.maximum: root.height - card.height
                    }
                }

                NoteEditorButton {
                    visible: root.noteId !== null
                    iconText: "delete"
                    tooltip: "Delete note"
                    onClicked: root.deleteNote()
                }
                NoteEditorButton {
                    iconText: "content_copy"
                    tooltip: "Copy to clipboard"
                    enabled: textArea.text.length > 0
                    onClicked: Quickshell.clipboardText = textArea.text
                }
                NoteEditorButton {
                    iconText: "close"
                    tooltip: "Close (Esc)"
                    onClicked: root.close()
                }
            }

            // Body: scrolls once the note is taller than the card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerLow
                clip: true

                StyledFlickable {
                    id: flickable
                    anchors.fill: parent
                    anchors.margins: 4
                    ScrollBar.vertical: StyledScrollBar {
                        policy: flickable.contentHeight > flickable.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                    }

                    TextArea.flickable: StyledTextArea {
                        id: textArea
                        wrapMode: TextArea.Wrap
                        placeholderText: "Type your note..."
                        font.pixelSize: Appearance.font.pixelSize.normal
                        padding: 12
                        rightPadding: 16 // room for the scrollbar
                        background: null
                        selectByMouse: true
                        Keys.onEscapePressed: root.close()

                        // Links: underlined, highlighted under the pointer;
                        // a click opens one in the browser and closes the
                        // editor (it would cover the browser). A drag still
                        // selects.
                        property var linkSegments: linkLayout(text, width, contentHeight)
                        property int hoveredLink: -1

                        // For each link, one rectangle per line it spans:
                        // [{link, url, x, y, width, height}]
                        function linkLayout() {
                            const segs = []
                            StringUtils.findUrls(textArea.text).forEach((link, n) => {
                                let seg = null
                                for (let i = link.start; i < link.end; i++) {
                                    const r = textArea.positionToRectangle(i)
                                    const next = textArea.positionToRectangle(i + 1)
                                    const right = next.y === r.y && next.x > r.x ? next.x
                                        : r.x + linkMetrics.advanceWidth(textArea.text[i])
                                    if (seg && seg.y === r.y) {
                                        seg.width = right - seg.x
                                    } else {
                                        seg = { link: n, url: link.url, x: r.x, y: r.y, width: right - r.x, height: r.height }
                                        segs.push(seg)
                                    }
                                }
                            })
                            return segs
                        }
                        function linkSegmentAt(x, y) {
                            return linkSegments.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) ?? null
                        }

                        FontMetrics {
                            id: linkMetrics
                            font: textArea.font
                        }
                        Repeater {
                            model: textArea.linkSegments
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool hovered: modelData.link === textArea.hoveredLink
                                z: -1 // under the text
                                x: modelData.x - 2
                                y: modelData.y
                                width: modelData.width + 4
                                height: modelData.height
                                radius: 4
                                color: hovered ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8) : "transparent"
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2; bottomMargin: 1 }
                                    height: parent.hovered ? 2 : 1
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                        HoverHandler {
                            id: linkHover
                            cursorShape: textArea.hoveredLink >= 0 ? Qt.PointingHandCursor : Qt.IBeamCursor
                            onPointChanged: textArea.hoveredLink = hovered ? (textArea.linkSegmentAt(point.position.x, point.position.y)?.link ?? -1) : -1
                            onHoveredChanged: if (!hovered) textArea.hoveredLink = -1
                        }
                        TapHandler {
                            onTapped: (eventPoint) => {
                                const seg = textArea.linkSegmentAt(eventPoint.position.x, eventPoint.position.y)
                                if (!seg) return
                                AppLaunch.openUrl(seg.url)
                                root.close()
                            }
                        }
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                                root.save()
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: {
                        const text = textArea.text
                        const words = text.trim().length > 0 ? text.trim().split(/\s+/).length : 0
                        const status = root.dirty ? " · unsaved" : ""
                        const links = StringUtils.findUrls(text).length > 0 ? " · click a link to open it" : ""
                        return `${words} ${words === 1 ? "word" : "words"} · ${text.length} characters${status}${links}`
                    }
                }

                DialogButton {
                    buttonText: "Save"
                    enabled: root.dirty && textArea.text.trim().length > 0
                    onClicked: root.close()
                }
            }
        }
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: scrim; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            NumberAnimation { target: scrim; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: card; property: "scale"; to: 0.92; duration: 140; easing.type: Easing.InQuad }
        }
        ScriptAction { script: root.dismissed() }
    }

    component NoteEditorButton: RippleButton {
        id: btn
        property string iconText
        property string tooltip
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        opacity: enabled ? 1 : 0.4
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: Appearance.font.pixelSize.larger
            text: btn.iconText
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: btn.tooltip
        }
    }
}
