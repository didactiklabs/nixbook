import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common 
import qs.Widgets
import "ThinkingPhrases.js" as ThinkingPhrases


DankRectangle {
    id: root
    property string text: ""
    property bool isUser: false
    property bool shouldAnimate: false
    property bool isThinking: false 
    property string displayedText: ""
    property string currentThinkingPhrase: "Thinking..."
    property var contentBlocks: []
    property bool useRichView: !typeWriterTimer.running && !root.isThinking && root.displayedText.length > 0
    property real thinkingStartTime: 0

    onUseRichViewChanged: updateContentBlocks()
    onDisplayedTextChanged: if (useRichView) updateContentBlocks()

    function updateContentBlocks() {
        if (!useRichView) return;
        
        var rawText = root.displayedText;
        var parts = rawText.split("```");
        var newBlocks = [];
        
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i];
            if (i % 2 === 0) {
                // For now this preserves newlines but doens't deal with multiple new lines well.
                // Complicating this block to further handle new lines seems not worth the effort of just
                // much it mucks up the code. So we just replace single newlines with markdown line breaks.
                if (part.length > 0) newBlocks.push({ type: "text", content: part.replace(/\n/g, "  \n") });
            } else {
                // Code block
                var newlineIndex = part.indexOf("\n");
                var lang = "";
                var code = part;
                if (newlineIndex !== -1) {
                    lang = part.substring(0, newlineIndex).trim();
                    code = part.substring(newlineIndex + 1);
                }
                if (code.endsWith("\n")) code = code.substring(0, code.length - 1);
                
                newBlocks.push({ type: "code", content: code, language: lang });
            }
        }
        root.contentBlocks = newBlocks;
    }
    
    signal animationCompleted()

    function updateThinkingPhrase() {
        root.currentThinkingPhrase = ThinkingPhrases.getRandomPhrase() + "...";
    }

    Timer {
        id: thinkingTimer
        interval: 3000
        repeat: true
        running: root.isThinking
        onTriggered: root.updateThinkingPhrase()
    }

    Timer {
        id: typeWriterTimer
        interval: 15
        repeat: true
        running: false
        property int currentIndex: 0
        
        onTriggered: {
            if (currentIndex < root.text.length) {
                var step = 1;
                // Speed up for longer texts
                if (root.text.length > 500) step = 5;
                else if (root.text.length > 200) step = 2;

                currentIndex += step;
                if (currentIndex > root.text.length) currentIndex = root.text.length;
                
                root.displayedText = root.text.substring(0, currentIndex);
            } else {
                running = false;
                root.animationCompleted();
            }
        }
    }


    Component.onCompleted: {
        if (root.isThinking) {
             updateThinkingPhrase();
             return;
        }

        if (root.isUser || !root.shouldAnimate) {
            root.displayedText = root.text;
        } else {
            typeWriterTimer.currentIndex = 0;
            typeWriterTimer.running = true;
        }
    }

    // @todo we want to address the bubble width so that its the total width of the child + padding 
    // unfortunately my attempts at this didn't work yet. So we'll keep the width fixed to its parent.
    width: parent.width 
    height: contentLayout.height + (Theme.spacingL * 2)

    // Alignment in the Column
    anchors.right: root.isUser ? parent.right : undefined
    anchors.left: root.isUser ? undefined : parent.left
    
    color: root.isUser ?  Theme.primaryContainer : Theme.surfaceContainerHigh
    radius: Theme.cornerRadius

    RowLayout {
        id: contentLayout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        BusyIndicator {
            id: thinkingAnim
            visible: root.isThinking
            running: root.isThinking
            Layout.preferredWidth: Theme.spacingXL 
            Layout.preferredHeight: Theme.spacingXL 
            Layout.alignment: Qt.AlignTop
            
            // Attempt to colorize based on style
            palette.dark: Theme.primary 
            palette.text: Theme.primary
        }

        TextEdit {
            id: msgText
            visible: !root.useRichView
            text: root.isThinking ? root.currentThinkingPhrase : root.displayedText.replace(/\n/g, "  \n")
            textFormat: TextEdit.MarkdownText
            readOnly: true
            selectByMouse: true
            tabStopDistance: 5
            onLinkActivated: link => Qt.openUrlExternally(link)
            
            Layout.fillWidth: true 
            wrapMode: TextEdit.Wrap
            
            color: root.isThinking ? Theme.primary : (root.isUser ? Theme.surfaceVariantText : Theme.surfaceText)
            opacity: root.isThinking ? 0.5 : 1.0
            font.pixelSize: Theme.fontSizeMedium
            font.italic: root.isThinking
            Layout.alignment: Qt.AlignTop

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: parent.linkAt(mouseX, mouseY) ? Qt.PointingHandCursor : Qt.IBeamCursor
            }
        }

        ColumnLayout {
            visible: root.useRichView && !root.isThinking
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Repeater {
                model: root.contentBlocks
                
                delegate: Loader {
                    Layout.fillWidth: true
                    sourceComponent: modelData.type === "code" ? codeComp : textComp
                    
                    Component {
                        id: textComp
                        TextEdit {
                            // width: parent.width // TextEdit inside Layout needs careful width handling if wrapping
                            Layout.fillWidth: true
                            text: modelData.content
                            textFormat: TextEdit.MarkdownText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            color: root.isUser ? Theme.surfaceVariantText : Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            onLinkActivated: link => Qt.openUrlExternally(link)

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                cursorShape: parent.linkAt(mouseX, mouseY) ? Qt.PointingHandCursor : Qt.IBeamCursor
                            }
                        }
                    }
                    
                    Component {
                         id: codeComp
                         CodeBlock {
                             code: modelData.content
                             language: modelData.language
                             Layout.fillWidth: true
                         }
                    }
                }
            }
        }
    }

    Timer {
        id: responseTimer
        interval: 100
        running: root.isThinking
        repeat: true
        property real currentTime: 0
        onTriggered: currentTime = Date.now()
    }

    Text {
        visible: root.isThinking
        text: {
            if (root.thinkingStartTime > 0 && responseTimer.currentTime > 0) {
                return ((responseTimer.currentTime - root.thinkingStartTime) / 1000).toFixed(1) + "s";
            }
            return "0.0s";
        }
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingS
        font.italic: true
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    // An invisible TextEdit to help with copying text to clipboard
    // By updating its contents and using the selectAll + copy methods we can
    // copy text to clipboard easily..
    TextEdit {
        id: copyHelper
        visible: false
    }

    HoverHandler {
        id: bubbleHover
    }

    DankActionButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingXS
        
        visible: bubbleHover.hovered && !root.isThinking
        
        iconName: "content_copy"
        buttonSize: 32
        iconSize: 18
        
        // Yes, this seems a bit hacky but the alternative recommended way
        // seems to be to run a shell command to copy to clipboard which IMO seems just as convoluted.
        // The text copied retains the general markdown formatting (like new lines) when pasted into rich text fields.
        // Also seems to let QT deal with platform differences internally..
        //
        // It still appears in our clipboard history so this works well enough.
        // https://danklinux.com/docs/dankmaterialshell/plugin-development#copying-to-clipboard
        onClicked: {
            copyHelper.text = root.text
            copyHelper.selectAll()
            copyHelper.copy()
        }
    }
}
