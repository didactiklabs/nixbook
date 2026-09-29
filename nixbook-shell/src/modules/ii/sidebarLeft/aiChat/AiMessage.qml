import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell

Rectangle {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    property real messagePadding: 7
    property real contentSpacing: 3

    // Answers are selectable: drag to select, Ctrl+C (or the copy button) to copy.
    property bool enableMouseSelection: true
    property bool renderMarkdown: true
    property bool editing: false

    // Streaming appends to the content once per received line, often several
    // times per frame: re-split and re-lay out the markdown at most once per
    // event-loop turn (Qt.callLater runs the same function once).
    property string shownContent: ""
    function syncContent() {
        root.shownContent = root.messageData?.content ?? "";
    }
    onMessageDataChanged: root.syncContent()
    Component.onCompleted: root.syncContent()
    Connections {
        target: root.messageData
        function onContentChanged() {
            Qt.callLater(root.syncContent);
        }
    }
    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.shownContent)

    // Persona style (shapes on): the in-game chat — a tilted mugshot in a bold
    // frame and a black, skewed speech bubble with a white border and a
    // jagged tail pointing at it. The user speaks from the right.
    readonly property bool persona: Persona.shapes
    readonly property bool fromUser: root.messageData?.role === "user"
    readonly property real mugSize: 60
    readonly property real mugGap: 32 // room for the tail
    readonly property color mugColor: root.fromUser ? "#2f55d4"
        : root.messageData?.role === "assistant" ? "#58d51c" : "#9b59d0"

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: root.persona
        ? Math.max(columnLayout.implicitHeight + root.messagePadding * 2 + 12, root.mugSize + 14)
        : columnLayout.implicitHeight + root.messagePadding * 2

    radius: root.persona ? 0 : Appearance.rounding.normal
    color: root.persona ? "transparent" : Appearance.colors.colLayer1

    // ---- Persona: mugshot
    Item {
        id: mugshot
        visible: root.persona
        width: root.mugSize
        height: root.mugSize
        x: root.fromUser ? root.width - width - 6 : 6
        y: 6
        rotation: root.fromUser ? 5 : -5
        Rectangle { // black rim
            anchors.fill: parent
            anchors.margins: -3
            color: "black"
        }
        Rectangle { // white frame, colour field
            id: mugFrame
            anchors.fill: parent
            color: root.mugColor
            border.width: 3
            border.color: "white"
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: 3
                visible: root.fromUser && UserAvatar.source !== "" && status === Image.Ready
                source: root.fromUser ? UserAvatar.source : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(128, 128)
                asynchronous: true
            }
            CustomIcon { // the model as a black silhouette on its colour
                anchors.centerIn: parent
                visible: !root.fromUser && root.messageData?.role === "assistant" && (Ai.models[root.messageData?.model]?.icon ?? "") !== ""
                width: root.mugSize * 0.62
                height: width
                source: Ai.models[root.messageData?.model]?.icon ?? ""
                colorize: true
                color: "black"
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: (root.fromUser && (UserAvatar.source === "")) || root.messageData?.role === "interface"
                    || (root.messageData?.role === "assistant" && (Ai.models[root.messageData?.model]?.icon ?? "") === "")
                text: root.fromUser ? "person" : root.messageData?.role === "interface" ? "settings" : "neurology"
                iconSize: root.mugSize * 0.6
                color: "black"
            }
        }
    }

    // ---- Persona: speech bubble (tail + skewed box), under the content
    Item {
        id: bubble
        visible: root.persona
        z: -1
        x: columnLayout.x - 12
        y: columnLayout.y - 8
        width: columnLayout.width + 24
        height: columnLayout.height + 16
        // Drawn for a mugshot on the left; mirrored for the user.
        transform: Scale {
            origin.x: bubble.width / 2
            xScale: root.fromUser ? -1 : 1
        }
        readonly property real w: width
        readonly property real h: height
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // Jagged lightning tail from the mugshot to the box.
            ShapePath {
                strokeColor: "white"
                strokeWidth: 3
                fillColor: "black"
                joinStyle: ShapePath.MiterJoin
                // Spans the gap to the mugshot's edge (it would hide under it).
                startX: 10; startY: 10
                PathLine { x: -12; y: 3 }
                PathLine { x: -3; y: 17 }
                PathLine { x: -19; y: 22 }
                PathLine { x: -6; y: 28 }
                PathLine { x: -17; y: 43 }
                PathLine { x: 10; y: 33 }
                PathLine { x: 10; y: 10 }
            }
            // Black rim, then the box with its white border (slightly skewed).
            ShapePath {
                strokeColor: "black"
                strokeWidth: 8
                fillColor: "black"
                joinStyle: ShapePath.MiterJoin
                startX: 8; startY: 0
                PathLine { x: bubble.w; y: 5 }
                PathLine { x: bubble.w - 7; y: bubble.h }
                PathLine { x: 0; y: bubble.h - 5 }
                PathLine { x: 8; y: 0 }
            }
            ShapePath {
                strokeColor: "white"
                strokeWidth: 3
                fillColor: "black"
                joinStyle: ShapePath.MiterJoin
                startX: 8; startY: 0
                PathLine { x: bubble.w; y: 5 }
                PathLine { x: bubble.w - 7; y: bubble.h }
                PathLine { x: 0; y: bubble.h - 5 }
                PathLine { x: 8; y: 0 }
            }
        }
    }

    function saveMessage() {
        if (!root.editing) return;
        // Get all Loader children (each represents a segment)
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));

        // Reconstruct markdown
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                // Remove trailing newlines
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");

        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control || 
            event.key == Qt.Key_Shift || 
            event.key == Qt.Key_Alt || 
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
            return;
        }
        // Typing after selecting text in an answer goes back to the input
        // field (a read-only answer doesn't take text, so the key was lost).
        const field = root.messageInputField;
        if (field && !root.editing && event.text.length > 0 && event.text >= " "
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            field.forceActiveFocus();
            field.insert(field.cursorPosition, event.text);
            event.accepted = true;
        }
    }

    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        // Persona: leave room for the mugshot and the tail, inside the bubble.
        anchors.leftMargin: root.persona && !root.fromUser ? root.mugSize + root.mugGap : messagePadding + (root.persona ? 12 : 0)
        anchors.rightMargin: root.persona && root.fromUser ? root.mugSize + root.mugGap : messagePadding + (root.persona ? 12 : 0)
        anchors.topMargin: messagePadding + (root.persona ? 8 : 0)
        spacing: root.contentSpacing

        Rectangle {
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth + 4 * 2
            implicitHeight: headerRowLayout.implicitHeight + 4 * 2
            color: root.persona ? "transparent" : Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small
        
            RowLayout { // Header
                id: headerRowLayout
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: 18

                Item { // Name
                    id: nameWrapper
                    implicitHeight: Math.max(nameRowLayout.implicitHeight + 5 * 2, 30)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: nameRowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        Item {
                            visible: !root.persona // the mugshot shows who speaks
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            implicitWidth: messageData?.role == 'assistant' ? modelIcon.width : roleIcon.implicitWidth
                            implicitHeight: messageData?.role == 'assistant' ? modelIcon.height : roleIcon.implicitHeight

                            CustomIcon {
                                id: modelIcon
                                anchors.centerIn: parent
                                visible: messageData?.role == 'assistant' && Ai.models[messageData?.model]?.icon
                                width: Appearance.font.pixelSize.large
                                height: Appearance.font.pixelSize.large
                                source: messageData?.role == 'assistant' ? Ai.models[messageData?.model]?.icon :
                                    messageData?.role == 'user' ? SystemInfo.distroIcon : 'desktop-symbolic'

                                colorize: true
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            MaterialSymbol {
                                id: roleIcon
                                anchors.centerIn: parent
                                visible: !modelIcon.visible
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.m3colors.m3onSecondaryContainer
                                text: messageData?.role == 'user' ? 'person' : 
                                    messageData?.role == 'interface' ? 'settings' : 
                                    messageData?.role == 'assistant' ? 'neurology' : 
                                    'computer'
                            }
                        }

                        StyledText {
                            id: providerName
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: root.persona && Persona.fonts ? Persona.titleFont : Appearance.font.family.main
                            font.weight: root.persona ? Font.Bold : Font.Normal
                            color: root.persona ? "white" : Appearance.m3colors.m3onSecondaryContainer
                            text: messageData?.role == 'assistant' ? (Ai.models[messageData?.model]?.name ?? messageData?.model ?? "") :
                                (messageData?.role == 'user' && SystemInfo.username) ? SystemInfo.username :
                                Translation.tr("Interface")
                        }
                    }
                }

                Button { // Not visible to model
                    id: modelVisibilityIndicator
                    visible: messageData?.role == 'interface'
                    implicitWidth: 16
                    implicitHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    background: Item

                    MaterialSymbol {
                        id: notVisibleToModelText
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: "visibility_off"
                    }
                    StyledToolTip {
                        text: Translation.tr("Not visible to model")
                    }
                }

                ButtonGroup {
                    spacing: 5

                    AiMessageControlButton {
                        id: regenButton
                        buttonIcon: "refresh"
                        visible: messageData?.role === 'assistant'

                        onClicked: {
                            Ai.regenerate(root.messageIndex)
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Regenerate")
                        }
                    }

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content
                            copyButton.activated = true
                            copyIconTimer.restart()
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            repeat: false
                            onTriggered: {
                                copyButton.activated = false
                            }
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }
                    AiMessageControlButton {
                        id: editButton
                        activated: root.editing
                        enabled: root.messageData?.done ?? false
                        buttonIcon: "edit"
                        onClicked: {
                            root.editing = !root.editing
                            if (!root.editing) { // Save changes
                                root.saveMessage()
                            }
                        }
                        StyledToolTip {
                            text: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                        }
                    }
                    AiMessageControlButton {
                        id: toggleMarkdownButton
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: {
                            root.renderMarkdown = !root.renderMarkdown
                        }
                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }
                    AiMessageControlButton {
                        id: deleteButton
                        buttonIcon: "close"
                        onClicked: {
                            Ai.removeMessage(root.messageIndex)
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete")
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.messageData?.localFilePath && root.messageData?.localFilePath.length > 0
            sourceComponent: AttachedFileIndicator {
                filePath: root.messageData?.localFilePath
                canRemove: false
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                implicitWidth: loadingIndicatorLoader.implicitWidth
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                FadeLoader {
                    id: loadingIndicatorLoader
                    anchors.centerIn: parent
                    shown: (root.messageBlocks.length < 1) && (!root.messageData.done)
                    sourceComponent: MaterialLoadingIndicator {
                        loading: true
                    }
                }
            }
            Repeater {
                // Keyed by position + type, not by the block objects: the
                // content is re-split on every streamed chunk, and objects
                // compared by identity rebuilt every block of the message each
                // time (the flicker on long answers). A block now updates in
                // place and is only rebuilt when its type changes.
                model: ScriptModel {
                    values: root.messageBlocks.map((block, i) => `${i}:${block.type}`)
                }
                delegate: Loader {
                    id: blockLoader
                    required property int index
                    readonly property var block: root.messageBlocks[index] ?? ({ type: "text", content: "" })
                    Layout.fillWidth: true
                    sourceComponent: block.type === "code" ? codeBlock : block.type === "think" ? thinkBlock : textBlock

                    Component { id: codeBlock; MessageCodeBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: blockLoader.block.content
                        segmentLang: blockLoader.block.lang ?? ""
                        messageData: root.messageData
                    } }
                    Component { id: thinkBlock; MessageThinkBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: blockLoader.block.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: blockLoader.block.completed ?? false
                    } }
                    Component { id: textBlock; MessageTextBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: blockLoader.block.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                    } }
                }
            }
        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                }
            }
        }

    }
}

