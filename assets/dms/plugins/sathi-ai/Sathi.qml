import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io

import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import qs.Modals.Common

PluginComponent {
    id: root

    layerNamespacePlugin: "dank:sathi-ai"

    property var displayText: "✨"
    property bool isLoading: false
    property string aiModel: pluginData.aiModel || ""
    property string geminiApiKeyFile: pluginData.geminiApiKeyFile || ""
    property string _fileGeminiApiKey: ""
    property bool useGrounding: true
    property string systemPrompt: pluginData.systemPrompt || "You are a helpful assistant. Answer concisely. The chat client you are running in is small so keep answers brief." 
    property string pendingInputText: ""
    property string resizeCorner: pluginData.resizeCorner || "right"
    property bool popoutSticky: false
    // Hack to find the PluginPopout instance since it's an internal child of PluginComponent
    // and we cannot modify PluginComponent source code.
    property Item _popoutInstance: null
    
    Timer {
        running: true
        repeat: false
        interval: 100
        onTriggered: {
            root.findPopoutInstance()
            if (root.geminiApiKeyFile !== "") {
                geminiApiKeyFileReadProcess.running = true
            }
        }
    }

    onPopoutStickyChanged: {
        if (root._popoutInstance) {
            // Setting backgroundInteractive to false disables the mouse area in the background window,
            // effectively making the popout 'sticky' because background clicks are not caught.
            root._popoutInstance.backgroundInteractive = !root.popoutSticky
            
            // Should release exclusive focus so we can interact with other windows
            if (root.popoutSticky) {
                root._popoutInstance.customKeyboardFocus = WlrKeyboardFocus.OnDemand;
            } else {
                root._popoutInstance.customKeyboardFocus = null;
            }
        }
    }

    Process {
        id: geminiApiKeyFileReadProcess
        command: ["cat", root.geminiApiKeyFile]
        stdout: SplitParser {
            onRead: line => {
                var key = line.trim()
                if (key !== "") {
                    root._fileGeminiApiKey = key
                    console.debug("SathiAI: Gemini API Key loaded from file: " + root.geminiApiKeyFile)
                }
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                console.error("SathiAI: Failed to read API key file: " + root.geminiApiKeyFile + " (Exit code: " + code + ")")
            }
        }
        running: false
    }

    onGeminiApiKeyFileChanged: {
        if (root.geminiApiKeyFile !== "") {
            geminiApiKeyFileReadProcess.running = true
        }
    }

    function findPopoutInstance() {
        if (root._popoutInstance) return;
        
        // Search through children for an object that looks like the PluginPopout
        // It should have properties like 'shouldBeVisible', 'backgroundInteractive', 'pluginContent'
        for (var i = 0; i < root.data.length; i++) {
            var child = root.data[i];
            if (child && 
                child.toString().indexOf("PluginPopout") !== -1 ||
                (child.hasOwnProperty("shouldBeVisible") && child.hasOwnProperty("backgroundInteractive"))
               ) {
                root._popoutInstance = child;

                // Prevents the popout from losing its content when hidden, which seems to be an issue with nested popouts or something related to the way PluginComponent manages its children.
                if (root._popoutInstance.contentLoader) {
                    try {
                        root._popoutInstance.contentLoader.active = true;
                        console.debug("Sathi: Forced popout content to stay active (nested)");
                    } catch (e) { console.warn(e) }
                }

                console.debug("Sathi: Found popout instance via hack");
                break;
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            StyledText {
                text: root.displayText
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            StyledText {
                text: root.displayText
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
        }
    }

    property ListModel chatModel: ListModel { }
    property ListModel availableAisModel: ListModel { }
    property bool isModelAvailable: true

    // When trying to access the visibility of the popout from within other functions
    // chatPopout.visible always returned false or something weird, not sure if thats a bug
    // or intended but this workaround seems to do the trick.
    QtObject {
        id: internalProps
        property bool isPopoutVisible: chatPopout.visible
    }

    Process {
        id: hiddenNotificationProcess
        property string message: ""
        command: ["notify-send", 
            "-i", Qt.resolvedUrl('./assets/star.png').toString().replace("file://", ""), 
            "SathiAI",
            message.substring(0, 100) + (message.length > 100 ? "..." : "")
        ]
        running: falsed
    }

    onAvailableAisModelChanged: {
        root.checkModelAvailability();
    }

    function checkModelAvailability() {
        if (!root.aiModel) {
            root.isModelAvailable = false; // Or false if strict, but if empty usually means not set/default
            return;
        }

        root.isModelAvailable = backendSettings.isModelAvailable(root.aiModel);
        console.debug("Model availability for " + root.aiModel + ": " + root.isModelAvailable);
    }

    function showMessageAlertIfHidden(message) {
        if (!pluginData.showMessageAlerts) {
            return;
        }
        
        // For some reason we can't just check chatPopout.visible directly here?
        // So we're using internalProps as a workaround..
        if (internalProps.isPopoutVisible && !hiddenNotificationProcess.running) {
            return
        }

        console.debug("Showing hidden message notification:", message)
        hiddenNotificationProcess.message = message
        hiddenNotificationProcess.running = true
    }

    ChatBackendChat {
        id: backendChat
        geminiApiKey: root._fileGeminiApiKey !== "" ? root._fileGeminiApiKey : (pluginData.geminiApiKey || "")
        openaiApiKey: pluginData.openaiApiKey || ""
        anthropicApiKey: pluginData.anthropicApiKey || ""
        ollamaUrl: pluginData.ollamaUrl || ""
        lmstudioUrl: pluginData.lmstudioUrl || ""
        persistChatHistory: pluginData.persistChatHistory

        model: root.aiModel
        useGrounding: root.useGrounding
        systemPrompt: root.systemPrompt
        maxHistory: pluginData.maxMessageHistory || 20

        pluginId: root.pluginId
        pluginService: root.pluginService

        onNewMessage: (text, isError) => {
            root.isLoading = false;
            // Remove the thinking bubble if it exists
            if (chatModel.count > 0) {
                 var last = chatModel.get(chatModel.count - 1);
                 if (last.isThinking === true) {
                     chatModel.remove(chatModel.count - 1);
                 }
            }
            chatModel.append(createChatEntry(text, false, true, false));

            root.pruneUiHistory();
            
            root.showMessageAlertIfHidden(text);
        }

        onChatHistoryLoaded: (chatHistory) => {
            console.debug("Chat history loaded:", chatHistory);
            for (var i = 0; i < chatHistory.length; i++) {
                var message = chatHistory[i];
                chatModel.append(createChatEntry(
                    message.content,
                    message.role === "user",
                    false,
                    false
                ));
            }
            root.pruneUiHistory();
        }
    }

    ChatBackendSettings {
        id: backendSettings
        geminiApiKey: root._fileGeminiApiKey !== "" ? root._fileGeminiApiKey : (pluginData.geminiApiKey || "")
        openaiApiKey: pluginData.openaiApiKey || ""
        anthropicApiKey: pluginData.anthropicApiKey || ""
        ollamaUrl: pluginData.ollamaUrl || ""
        lmstudioUrl: pluginData.lmstudioUrl || ""

        onNewModels: (models, isError) => {
            try {
                var data = JSON.parse(models);
                for (var i = 0; i < data.length; i++) {
                    availableAisModel.append(data[i]); // Append each item to the ListModel
                }
                root.checkModelAvailability();
            } catch (err) {
                console.error('failed to set models:', err)
            }
        }
    }

    function pruneUiHistory() {
        while (chatModel.count > 500) {
            chatModel.remove(0);
        }
    }

    function createChatEntry(text, isUser, shouldAnimate, isThinking) {
        return {
            "text": text,
            "isUser": isUser,
            "shouldAnimate": shouldAnimate,
            "isThinking": isThinking,
            "thinkingStartTime": isThinking ? Date.now() : 0
        };
    }

    function processMessage(message) {
        if (message === "") return;

        chatModel.append(createChatEntry(message, true, false, false));
        root.pruneUiHistory();
        root.isLoading = true;
        
        chatModel.append(createChatEntry("", false, true, true));
        backendChat.sendMessage(message);
    }

    popoutContent: chatPopout

    Component {
        id: chatPopout
        PopoutComponent {
            id: popoutColumn
            showCloseButton: false

            onVisibleChanged: {
                if (visible) {
                    chatInput.forceActiveFocus();
                    chatInput.cursorPosition = chatInput.length;
                }

                internalProps.isPopoutVisible = visible;
            }            

            Item {
                width: parent.width
                height: root.popoutHeight - popoutColumn.headerHeight -
                               popoutColumn.detailsHeight - Theme.spacingL


                Column {
                    anchors.centerIn: parent
                    width: parent.width - (Theme.spacingL * 2)
                    spacing: Theme.spacingM
                    visible: availableAisModel.count === 0

                    StyledText {
                        text: "No AI Models Available"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.surfaceText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        text: "Please add your API keys in the settings screen to start chatting."
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.surfaceText
                        opacity: 0.7
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    DankButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Configure in Settings"
                        onClicked: Quickshell.execDetached(["dms", "ipc", "call", "settings", "openWith", "plugins"])                    
                    }
                }

                Flickable { 
                    id: flickable
                    visible: availableAisModel.count > 0
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: columnBottomSection.top
                    anchors.bottomMargin: Theme.spacingL
                    anchors.margins: Theme.spacingL
                    
                    contentWidth: width
                    contentHeight: chatColumn.height
                    clip: true
                    flickableDirection: Flickable.VerticalFlick

                    function scrollToBottom() {
                        if (contentHeight > height)
                            contentY = contentHeight - height;
                    }

                    Column {
                        id: chatColumn
                        width: parent.width
                        spacing: Theme.spacingL
                        padding: Theme.spacingL
                        
                        onHeightChanged: flickable.scrollToBottom()
                        
                        
                        Repeater {
                            model: root.chatModel
                            delegate: ChatBubble {
                                text: model.text
                                isUser: model.isUser
                                shouldAnimate: model.shouldAnimate
                                isThinking: model.isThinking !== undefined ? model.isThinking : false
                                thinkingStartTime: model.thinkingStartTime !== undefined ? model.thinkingStartTime : 0
                                width: chatColumn.width - (chatColumn.padding * 2)
                                onAnimationCompleted: model.shouldAnimate = false
                            }
                        }

                    }
                }

                Column { 
                    id: columnBottomSection
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spacingL
                    visible: availableAisModel.count > 0

                    spacing: Theme.spacingXS
                    
                    width: parent.width
                    // height: 75

                    // Dank Textfield at the bottom for user input
                    ChatInput {
                        id: chatInput
                        width: parent.width
                        text: root.pendingInputText
                        onTextChanged: root.pendingInputText = text

                        // anchors.bottomMargin: Theme.spacingL
                        // anchors.margins: Theme.spacingL
                        onAccepted: {
                            // Handle the input text here
                            console.debug("User input:", text); 
                            root.processMessage(text);
                            
                            text = ""; // Clear input after processing
                             // Explicitly clear parent property just to be safe, 
                             // though the binding above should verify it via onTextChanged
                             root.pendingInputText = ""
                            text = ""; // Clear input after processing
                        }
                    }

                    // Display a small combo box at the bottom to change the model dynamically.
                    Row {
                        id: bottomModelSelectorRow
                        width: parent.width
                        height: cbModelSelector.implicitHeight + Theme.spacingXL
                        spacing: Theme.spacingS
                        anchors.bottomMargin: Theme.spacingXL

                        AiSelector {
                            id: cbModelSelector
                            model: availableAisModel
                            maxPopupHeight: popoutColumn.height * 0.6

                            width: parent.width - rowBottomRowActions.width - Theme.spacingS
                            textRole: "display_name"
                            valueRole: "name"
                            displayText: currentIndex === -1 ? "Select an AI Model..." : currentText

                            function updateIndex() {
                                for (var i = 0; i < availableAisModel.count; i++) {
                                    if (availableAisModel.get(i).name === root.aiModel) {
                                        currentIndex = i;
                                        return;
                                    }
                                }
                                currentIndex = -1;
                            }

                            Component.onCompleted: updateIndex()

                            Connections {
                                target: availableAisModel
                                function onCountChanged() { cbModelSelector.updateIndex() }
                            }

                            onActivated: {
                                if (pluginService) {
                                    root.aiModel = currentValue
                                    pluginService.savePluginData(pluginId, "aiModel", currentValue)
                                    root.checkModelAvailability()
                                }
                            }
                        }
                        
                        Row {
                            id: rowBottomRowActions
                            width: Theme.fontSizeLarge * 4 + Theme.spacingS
                            height: cbModelSelector.implicitHeight

                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS
                            anchors.top: parent.top

 
                            DankActionButton {
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingXS
                                
                                visible: trueprimary
                                
                                iconName: "history_off"
                                buttonSize: 32
                                iconSize: 18
                                
                                ConfirmModal {
                                    id: clearChatConfirm
                                }                                

                                // Yes, this seems a bit hacky but the alternative recommended way
                                // seems to be to run a shell command to copy to clipboard which IMO seems just as convoluted.
                                // The text copied retains the general markdown formatting (like new lines) when pasted into rich text fields.
                                // Also seems to let QT deal with platform differences internally..
                                //
                                // It still appears in our clipboard history so this works well enough.
                                // https://danklinux.com/docs/dankmaterialshell/plugin-development#copying-to-clipboard
                                onClicked: () => {
                                    clearChatConfirm.showWithOptions({
                                        title: "Clear Chat",
                                        message: "Are you sure you want to clear the current chat history? This action cannot be undone.",
                                        confirmText: "Clear",
                                        confirmColor: Theme.error,
                                        onConfirm: () => backendChat.clearChat()
                                    });
                                }
                            }

                            DankActionButton {
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingXS
                                
                                visible: true
                                
                                iconName: "push_pin"
                                buttonSize: 32
                                iconSize: 18

                                iconColor: root.popoutSticky ? Theme.surfaceVariantText : Theme.surfaceText
                                backgroundColor: root.popoutSticky ? Theme.surfaceVariant : "transparent"
                                
                                onClicked: () => {
                                    root.popoutSticky = !root.popoutSticky;
                                }
                            }


                        }
                    }

                    StyledText {
                        visible: !root.isModelAvailable && root.aiModel !== "" && availableAisModel.count > 0
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmasurfaceVariantll
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        anchors.bottomMargin: Theme.spacingM

                        function getText() {
                            if (availableAisModel.count === 0) {
                                return "⚠️ No models are currently available. Please check your API keys and connection.";
                            } else {
                                return "⚠️ Selected model \"" + root.aiModel + "\" is currently not available";
                            }
                        }
                        
                        text: getText()}
                }

                MouseArea {
                    id: resizeHandle
                    // Dynamic anchoring based on resizeCorner setting
                    anchors.right: (root.resizeCorner === "left") ? undefined : parent.right
                    anchors.left: (root.resizeCorner === "left") ? parent.left : undefined
                    anchors.bottom: parent.bottom
                    
                    width: 25
                    height: 25
                    // Switch cursor shape depending on side
                    cursorShape: (root.resizeCorner === "left") ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor
                    
                    property point startGlobalPos
                    property real startWidth
                    property real startHeight

                    onPressed: (mouse) => {
                        startGlobalPos = mapToGlobal(mouse.x, mouse.y)
                        startWidth = root.popoutWidth
                        startHeight = root.popoutHeight
                    }

                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            var currentGlobal = mapToGlobal(mouse.x, mouse.y)
                            var dx = currentGlobal.x - startGlobalPos.x
                            var dy = currentGlobal.y - startGlobalPos.y
                            
                            if (root.resizeCorner === "left") {
                                // For left-side resize, moving mouse LEFT (negative dx) should INCREASE width
                                root.popoutWidth = Math.max(350, startWidth - dx)
                            } else {
                                // For right-side resize, moving mouse RIGHT (positive dx) should INCREASE width
                                root.popoutWidth = Math.max(350, startWidth + dx)
                            }
                            
                            // Height always increases when moving DOWN (positive dy)
                            root.popoutHeight = Math.max(400, startHeight + dy)
                        }
                    }
                    
                    onReleased: {
                         if (pluginService) {
                             pluginService.savePluginData(pluginId, "windowWidth", root.popoutWidth)
                             pluginService.savePluginData(pluginId, "windowHeight", root.popoutHeight)
                         }
                    }

                    Canvas {
                        anchors.fill: parent
                        anchors.margins: 4
                        // Redraw when the corner changes
                        property string corner: root.resizeCorner
                        onCornerChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.strokeStyle = Theme.surfaceText;
                            ctx.lineCap = "round";
                            ctx.lineWidth = 2;
                            ctx.beginPath();
                            
                            // Diagonal lines
                            var w = width;
                            var h = height;
                            
                            if (root.resizeCorner === "left") {
                                // Draw lines in bottom-left corner / /
                                ctx.moveTo(0, h - 10);
                                ctx.lineTo(10, h);
                                
                                ctx.moveTo(0, h - 5);
                                ctx.lineTo(5, h);
                            } else {
                                // Draw lines in bottom-right corner \ \ (or rather, the standard resize grip)
                                ctx.moveTo(w, h - 10);
                                ctx.lineTo(w - 10, h);
                                
                                ctx.moveTo(w, h - 5);
                                ctx.lineTo(w - 5, h);
                            }
                            
                            ctx.stroke();
                        }
                    }
                }
            }
        }
    }

    popoutWidth: pluginData.windowWidth || 400
    popoutHeight: pluginData.windowHeight || 500
}
