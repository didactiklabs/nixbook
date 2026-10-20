import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
// Qualified: this directory's own Notes.qml (the overlay widget) would hide
// the notes store.
import qs.services as Services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

// The overlay's Notes: the scratchpad, one note of the notes store
// (services/Notes.qml), so it is also in the Notes app and the desktop notes
// widget, and synced with Google Keep. Saved as you type; changes made
// elsewhere show while nothing typed here waits to be saved.
OverlayBackground {
    id: root

    property alias content: textInput.text
    property var copyListEntries: []
    property string lastParsedCopylistText: ""
    property var parsedCopylistLines: []
    property bool isClickthrough: false
    property real maxCopyButtonSize: 20

    Component.onCompleted: {
        Services.Notes.ensureLoaded();
        root.loadContent();
    }
    // Closing the widget (or reloading the shell) right after typing: what
    // waits for the save debounce is written now, synchronously.
    Component.onDestruction: {
        if (saveDebounce.running) {
            saveDebounce.stop();
            root.saveContent(true);
        }
    }

    // Set while the text comes from the store, so it isn't saved back.
    property bool loading: false
    // The scratchpad's text into the editor (empty when there is none: a
    // deleted scratchpad isn't brought back, the next text starts a new one),
    // the cursor kept where it was.
    function loadContent() {
        if (!textInput)
            return;
        const text = Services.Notes.scratchpad?.content ?? "";
        if (text !== root.content) {
            const cursor = textInput.cursorPosition;
            root.loading = true;
            root.content = text;
            root.loading = false;
            textInput.cursorPosition = Math.min(cursor, text.length);
        }
        Qt.callLater(root.updateCopyListEntries);
    }

    function saveContent(now = false) {
        if (!textInput)
            return;
        Services.Notes.setScratchpad(root.content, now);
    }

    // The Notes app, the desktop widget, agents and Keep edit it too.
    Connections {
        target: Services.Notes
        function onListChanged() {
            if (!saveDebounce.running)
                root.loadContent();
        }
    }

    function scheduleCopylistUpdate(immediate = false) {
        if (!textInput)
            return;
        if (immediate) {
            copyListDebounce?.stop();
            updateCopyListEntries();
        } else {
            copyListDebounce.restart();
        }
    }

    function updateCopyListEntries() {
        if (!textInput)
            return;
        const textValue = root.content;
        if (!textValue || textValue.length === 0) {
            lastParsedCopylistText = "";
            parsedCopylistLines = [];
            root.copyListEntries = [];
            return;
        }

        if (textValue !== lastParsedCopylistText) {
            const lineRegex = /(.*?)(\r?\n|$)/g;
            let match = null;
            const parsed = [];
            while ((match = lineRegex.exec(textValue)) !== null) {
                const lineText = match[1];
                const newlineText = match[2];
                const lineStart = match.index;
                const lineEnd = lineStart + lineText.length;
                const bulletMatch = lineText.match(/^\s*-\s+(.*\S)\s*$/);
                if (bulletMatch) {
                    parsed.push({
                        content: bulletMatch[1].trim(),
                        start: lineStart,
                        end: lineEnd
                    });
                }
                if (newlineText === "")
                    break;
            }
            lastParsedCopylistText = textValue;
            parsedCopylistLines = parsed;
            if (parsed.length === 0) {
                root.copyListEntries = [];
                return;
            }
        }

        updateCopylistPositions();
    }

    function updateCopylistPositions() {
        if (!textInput || parsedCopylistLines.length === 0)
            return;
        const rawSelectionStart = textInput.selectionStart;
        const rawSelectionEnd = textInput.selectionEnd;
        const selectionStart = rawSelectionStart === -1 ? textInput.cursorPosition : rawSelectionStart;
        const selectionEnd = rawSelectionEnd === -1 ? textInput.cursorPosition : rawSelectionEnd;
        const rangeStart = Math.min(selectionStart, selectionEnd);
        const rangeEnd = Math.max(selectionStart, selectionEnd);

        const entries = parsedCopylistLines.map(line => {
            // Don't show copy button if line is (partially) selected
            const caretIntersects = rangeEnd > line.start && rangeStart <= line.end;
            if (caretIntersects)
                return null;
            const startRect = textInput.positionToRectangle(line.start);
            let endRect = textInput.positionToRectangle(line.end);
            if (!isFinite(startRect.y))
                return null;
            if (!isFinite(endRect.y))
                endRect = startRect;
            const lineBottom = endRect.y + endRect.height;
            const rectHeight = Math.max(lineBottom - startRect.y, textInput.font.pixelSize + 8);
            return {
                content: line.content,
                y: startRect.y,
                height: rectHeight
            };
        }).filter(entry => entry !== null);

        root.copyListEntries = entries;
    }

    implicitWidth: 300
    implicitHeight: 200

    ColumnLayout {
        id: contentItem
        anchors.fill: parent
        spacing: -16

        ScrollView {
            id: editorScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            onWidthChanged: root.scheduleCopylistUpdate(true)

            StyledTextArea { // This has to be a direct child of ScrollView for proper scrolling
                id: textInput
                anchors {
                    left: parent.left
                    right: parent.right
                }
                wrapMode: TextEdit.Wrap
                placeholderText: Translation.tr("Write something here...\nUse '-' to create copyable bullet points, like this:\n\nSheep fricker\n- 4x Slab\n- 1x Boat\n- 4x Redstone Dust\n- 1x Sticky Piston\n- 1x End Rod\n- 4x Redstone Repeater\n- 1x Redstone Torch\n- 1x Sheep")
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                background: null
                padding: 24

                onTextChanged: {
                    if (textInput.activeFocus && !root.loading) {
                        saveDebounce.restart();
                    }
                    root.scheduleCopylistUpdate(true);
                }
                
                onHeightChanged: root.scheduleCopylistUpdate(true)
                onContentHeightChanged: root.scheduleCopylistUpdate(true)
                onCursorPositionChanged: root.scheduleCopylistUpdate()
                onSelectionStartChanged: root.scheduleCopylistUpdate()
                onSelectionEndChanged: root.scheduleCopylistUpdate()
            }

            Item {
                anchors.fill: parent
                visible: root.copyListEntries.length > 0
                clip: true

                Repeater {
                    model: ScriptModel {
                        values: root.copyListEntries
                    }
                    delegate: RippleButton {
                        id: copyButton
                        required property var modelData
                        readonly property real lineHeight: Math.min(Math.max(modelData.height, Appearance.font.pixelSize.normal + 6), root.maxCopyButtonSize)
                        readonly property real iconSizeLocal: Appearance.font.pixelSize.normal
                        readonly property real hitPadding: 6
                        property bool justCopied: false

                        implicitHeight: lineHeight
                        implicitWidth: lineHeight
                        buttonRadius: height / 2
                        y: modelData.y
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        z: 5

                        Timer {
                            id: resetState
                            interval: 700
                            onTriggered: {
                                copyButton.justCopied = false;
                            }
                        }

                        onClicked: {
                            Quickshell.clipboardText = copyButton.modelData.content;
                            justCopied = true;
                            resetState.start();
                        }

                        contentItem: Item {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                id: iconItem
                                anchors.centerIn: parent
                                text: copyButton.justCopied ? "check" : "content_copy"
                                iconSize: copyButton.iconSizeLocal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            id: statusLabel
            Layout.fillWidth: true
            Layout.margins: 16
            horizontalAlignment: Text.AlignRight
            text: saveDebounce.running ? Translation.tr("Saving...") : Translation.tr("Saved    ")
            color: Appearance.colors.colSubtext
        }
    }

    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: saveContent()
    }

    Timer {
        id: copyListDebounce
        interval: 100
        repeat: false
        onTriggered: updateCopylistPositions()
    }
}
