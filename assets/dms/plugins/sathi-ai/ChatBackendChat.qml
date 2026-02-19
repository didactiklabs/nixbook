import QtQuick

import "providers.js" as Providers

Item {
    id: root

    property string geminiApiKey: ""
    property string openaiApiKey: ""
    property string ollamaUrl: ""
    property string lmstudioUrl: ""
    property string anthropicApiKey: ""
    property int maxHistory: 20

    property bool running: false
    property string model: ""
    property bool useGrounding: false
    property string systemPrompt: ""

    property bool persistChatHistory: false
    property string pluginId
    property var pluginService

    signal newMessage(string text, bool isError)
    signal chatHistoryLoaded(var chatHistory)

    // We only ever want to try and load chat once.
    QtObject {
        id: internal
        property bool tryToLoadChat: true
    }

    onGeminiApiKeyChanged: {
        Providers.setGeminiApiKey(geminiApiKey);
    }

    onOpenaiApiKeyChanged: {
        Providers.setOpenaiApiKey(openaiApiKey);
    }

    onOllamaUrlChanged: {
        Providers.setOllamaUrl(ollamaUrl);
    }

    onLmstudioUrlChanged: {
        Providers.setLMStudioUrl(lmstudioUrl);
    }

    onAnthropicApiKeyChanged: {
        Providers.setAnthropicApiKey(anthropicApiKey);
    }
    
    onMaxHistoryChanged: {
        Providers.setMaxHistory(maxHistory);
    }

    onPersistChatHistoryChanged: {
        Providers.setPersistChatHistory(persistChatHistory);
        tryToLoadChatHistory();       
    }

    onModelChanged: {
        console.debug("Model changed: " + model);
        Providers.setModel(model);
    }

    onUseGroundingChanged: {
        Providers.setUseGrounding(useGrounding);
    }

    onSystemPromptChanged: {
        console.log("System prompt changed: " + systemPrompt);
        Providers.setSystemPrompt(systemPrompt);
    }

    function sendMessage(text) {
        Providers.sendMessage(text, function(response, error) {
            if (error) {
                newMessage("Error: " + error, true);
            } else {
                newMessage(response, false);
            }
        });
    }

    onPluginIdChanged: {
        Providers.setPluginId(pluginId);
        tryToLoadChatHistory()
    }

    onPluginServiceChanged: {
        Providers.setPluginService(pluginService);
        tryToLoadChatHistory()
    }

    /**
     * Attempt to load chat history if we have access to:
     *  - pluginId is set.
     *  - pluginService is set
     *  - persistChatHistory is enabled
     *  - and we haven't attempted to already load chat history previously.
     **/
    
    function tryToLoadChatHistory() {
        console.debug("Trying to load chat history...", pluginId, pluginService, persistChatHistory, internal.tryToLoadChat);

        if (!pluginId || !pluginService || !persistChatHistory || !internal.tryToLoadChat) {
            return;
        }

        try {
            chatHistoryLoaded(Providers.loadChatHistory());
        } catch (e) {
            console.error("Error loading chat history: " + e);
        }

        // Regardless of if we loaded or not based on the persistChatHistory setting,
        // we only want to try it the once at load which is the only time
        // these variables should get set.
        internal.tryToLoadChat = false;
    }

    function clearChat() {
        console.debug("Clearing chat history as requested.");
        Providers.clearChatHistory();
        chatModel.clear();
    }
}
