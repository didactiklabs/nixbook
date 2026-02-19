.pragma library
.import "gemini.js" as Gemini
.import "ollama.js" as Ollama
.import "openai.js" as OpenAI
.import "lmstudio.js" as LMStudio
.import "anthropic.js" as Anthropic

var ollamaUrl = "";
var geminiKey = "";
var openaiKey = "";
var lmstudioUrl = "";
var anthropicKey = "";
var loadedModels = {};
var modelKey = "";

// Centralized History
var masterHistory = []; 
var systemPrompt = "";
var maxHistory = 20;
var persistChatHistory = false;

// Required for saving and loading data.
var pluginId = "";
var pluginService = null;

function setMaxHistory(max) {
    console.log("Setting max history to: " + max);
    maxHistory = max;
}

function setPersistChatHistory(enabled) {
    console.log("Setting persistChatHistory to: " + enabled);

    persistChatHistory = enabled;
    
    // We should clear our messages if we've been turned off and save them if we've been turned on.
    enabled ? saveChatHistory() : clearSavedChatHistory();
}

function clearSavedChatHistory() {
    if (!pluginService || !pluginId) {
        return;
    }
    
    console.log("Clearing saved chat history.");
    pluginService.savePluginData(pluginId, "chatHistory", null);
}

function clearChatHistory() {
    console.debug("Clearing in-memory chat history.");

    masterHistory = [];
    clearSavedChatHistory();
}

function setGeminiApiKey(key) {
    geminiKey = key;
    Gemini.setApiKey(key);
}

function setOpenaiApiKey(key) {
    openaiKey = key;
    OpenAI.setApiKey(key);
}

function setOllamaUrl(url) {
    ollamaUrl = url;
    Ollama.setBaseUrl(url);
}

function setLMStudioUrl(url) {
    lmstudioUrl = url;
    LMStudio.setBaseUrl(url);
}

function setAnthropicApiKey(key) {
    anthropicKey = key;
    Anthropic.setApiKey(key);
}

function getOllamaModels(callback) {
    console.log("Fetching Ollama models from URL: " + ollamaUrl);
    Ollama.listModels((models, error) => {
        processModels(models, callback, error);
    });
}

function getGeminiModels(callback) {
    console.log("Fetching Gemini models...");
    Gemini.listModels((models, error) => {
        processModels(models, callback, error);
    });
}

function getOpenaiModels(callback) {
    console.log("Fetching OpenAI models...");
    OpenAI.listModels((models, error) => {
        processModels(models, callback, error);
    });
}

function getLMStudioModels(callback) {
    console.log("Fetching LM Studio models from URL: " + lmstudioUrl);
    LMStudio.listModels((models, error) => {
        processModels(models, callback, error);
    });
}

function getAnthropicModels(callback) {
    console.log("Fetching Anthropic models...");
    Anthropic.listModels((models, error) => {
        processModels(models, callback, error);
    });
}

function setModel(model) {
    console.log("Setting current model to: " + model);
    modelKey = model;
}

function currentModel() {
    return loadedModels[modelKey];
}

function processModels(models, callback, error) {
    if (error) {
        callback(null, error);
        return;
    }

    if (models && models.length > 0) {
        // Set default model to first available if none selected
        if (modelKey === "") {
            setModel(models[0].name);
        }

        for (var i = 0; i < models.length; i++) {
            loadedModels[models[i].name] = models[i];
        }


        callback(models, null);
    } else {
        callback([], null);
    }
}

function setUseGrounding(enabled) {
    Gemini.setUseGrounding(enabled);
}

function setSystemPrompt(prompt) {
    systemPrompt = prompt;
    // Clearing history when prompt changes? 
    // Usually yes, if we change persona we start new chat.
    masterHistory = [];
}

function listModels(callback) {
    var modelsList = [];
    for (var key in loadedModels) {
        modelsList.push(loadedModels[key]);
    }
    callback(modelsList);
}

function getProvider() {
    var model = currentModel();
    if (!model) {
        throw new Error("No model selected");
    }

    if (model.provider === "ollama") {
        return Ollama
    } else if (model.provider === "gemini") {
        return Gemini
    } else if (model.provider === "openai") {
        return OpenAI
    } else if (model.provider === "lmstudio") {
        return LMStudio
    } else if (model.provider === "anthropic") {
        return Anthropic
    }

    throw new Error("Unknown provider: " + model.provider);
}

function pruneHistory() {
    // If history exceeds maxHistory, remove oldest messages
    // BUT preserve the first message? "leave the prompt as the first message and to not remove it"
    // Usually the prompt is systemPrompt (handled separately now).
    // If user meant the first *user* message, we can try to preserve index 0.
    
    // Let's assume user meant "system prompt" when they said "prompt".
    // Since I moved systemPrompt to a separate variable, simply pruning the array is safe.
    // If they strictly meant the first message in the array (e.g. user's first query),
    // then:
    
    if (masterHistory.length > maxHistory) {
         // Keep the first message (index 0)
         var first = masterHistory[0];
         // Keep the recent (maxHistory - 1) messages
         var recent = masterHistory.slice(-(maxHistory - 1));
         
         masterHistory = [first].concat(recent);
         console.log("History pruned. New length: " + masterHistory.length);
    }
}

function sendMessage(text, callback) {
    if (!currentModel()) {
        console.log("ModelKey: " + modelKey);
        callback(null, "No model selected");
        return;
    }
    
    // Add to history
    masterHistory.push({ role: "user", content: text });
    
    // Enforce limit
    pruneHistory();
    
    // Save history
    saveChatHistory();

    console.log("Sending chat. History length: " + masterHistory.length + ". Provider " + currentModel().provider);

    getProvider().setModel(currentModel().name);

    var fullSystemPrompt = systemPrompt;
    var dateTimeContext = "For context the current date is " + (new Date()).toDateString() + ".";
    if (fullSystemPrompt) {
        fullSystemPrompt += "\n\n" + dateTimeContext;
    } else {
        fullSystemPrompt = dateTimeContext;
    }

    // Updated signature: sendChat(history, systemPrompt, callback)
    getProvider().sendChat(masterHistory, fullSystemPrompt, function(response, error){
        if (response) {
            masterHistory.push({ role: "model", content: response });
            pruneHistory();
            saveChatHistory();
            console.log("Chat response received. Total history: " + masterHistory.length);
        }
        callback(response, error);
    });
}

/**
 * Saves the current chat history to persistent storage.
 * 
 * This function serializes the masterHistory array to JSON and saves it using the
 * plugin service. The save operation only occurs if chat history persistence is
 * enabled (persistChatHistory is true) and the plugin service is available.
 * 
 * @returns {void}
 */
function saveChatHistory() {
    if (!persistChatHistory || !pluginService || !pluginId) {
        return;
    }

    console.log("Saving chat history. Length: " + masterHistory.length);
    var chatHistory = JSON.stringify(masterHistory);

    // Save chat history
    pluginService.savePluginData(pluginId, "chatHistory", chatHistory);
}

/**
 * Loads previously saved chat history from persistent storage.
 * 
 * This function retrieves chat history from the plugin service and deserializes it
 * from JSON into the masterHistory array. The function includes safeguards to:
 * - Return an empty array if persistence is disabled or plugin service is unavailable
 * - Skip reloading if masterHistory already contains messages (returns existing masterHistory)
 * - Handle JSON parsing errors gracefully by resetting to an empty array
 * 
 * @returns {Array} The loaded chat history array. Returns an empty array if:
 *   - Chat history persistence is disabled (persistChatHistory is false)
 *   - Plugin service is not available
 *   - No saved history exists
 *   - JSON parsing fails
 *   Returns existing masterHistory if it's already loaded (length > 0).
 */
function loadChatHistory() {
    console.debug("Attempting to load chat history.");
    if (!persistChatHistory || !pluginService || !pluginId) {
        return [];
    }

    if (masterHistory.length > 0) {
        console.warn("Chat history already loaded, skipping reload.");
        return masterHistory;
    }

    var chatHistory = pluginService.loadPluginData(pluginId, "chatHistory");
    
    if (chatHistory) {
        try {
            masterHistory = JSON.parse(chatHistory);
            console.debug("Chat history loaded. Length: " + masterHistory.length);
        } catch (e) {
            console.error("Error parsing chat history: " + e);
            masterHistory = [];
        }
    }

    return masterHistory;
}

function setPluginId(id) {
    pluginId = id;
}

function setPluginService(service) {
    pluginService = service;
}

function isModelLoaded(modelName) {
    return loadedModels.hasOwnProperty(modelName);
}