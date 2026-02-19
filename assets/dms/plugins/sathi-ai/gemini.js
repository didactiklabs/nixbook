.pragma library

var apiKey = "";
var currentModel = "";
var useGrounding = false;

function setApiKey(key) {
    apiKey = key;
}

function setModel(model) {
    currentModel = model;
}

function setUseGrounding(enabled) {
    useGrounding = enabled;
}

function request(method, url, callback, data) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    callback(response, null);
                } catch (e) {
                    callback(null, "Failed to parse response: " + e.message);
                }
            } else {
                var errorMsg = "HTTP Error: " + xhr.status;
                try {
                     var errJson = JSON.parse(xhr.responseText);
                     if (errJson.error && errJson.error.message) {
                         errorMsg += " - " + errJson.error.message;
                     }
                } catch(e) {}
                callback(null, errorMsg);
            }
        }
    };
    xhr.open(method, url);
    if (apiKey) {
        xhr.setRequestHeader("x-goog-api-key", apiKey);
    }
    xhr.setRequestHeader("Content-Type", "application/json");
    if (data) {
        xhr.send(JSON.stringify(data));
    } else {
        xhr.send();
    }
}

function listModels(callback) {
    var url = "https://generativelanguage.googleapis.com/v1beta/models?key=" + apiKey;
    
    request("GET", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        var models = [];
        if (response.models) {
            for (var i = 0; i < response.models.length; i++) {
                var m = response.models[i];
                var name = m.name;
                if (name.startsWith("models/")) {
                    name = name.substring(7);
                }
                var modelData = { "name": name };
                if (m.displayName) {
                    modelData["display_name"] = m.displayName;
                }

                modelData["provider"] = "gemini";
                models.push(modelData);
            }
        }
        callback(models, null);
    });
}

function sendChat(history, systemPrompt, callback) {
    if (!apiKey) {
        callback(null, "API Key not set");
        return;
    }
    
    // Map standard history [{role: 'user'|'model', content: ''}] to Gemini format
    var contents = [];
    
    // Pass system prompt ?? Gemini doesn't have a strict system role in generateContent usually unless using beta features or putting it in first user message?
    // Actually typically we put system prompt as the first message from 'user' or system_instruction in 1.5
    // Let's use system_instruction if available or fallback to prepending.
    // For simplicity in this plugin let's just use the previous strategy: first message is user with prompt.
    // However, if we receive a separate systemPrompt, we should use it.
    
    // Note: Gemini 1.5 supports system_instruction.
    
    for(var i=0; i<history.length; i++) {
        var item = history[i];
        contents.push({
            role: item.role,
            parts: [{ text: item.content }]
        });
    }

    var url = "https://generativelanguage.googleapis.com/v1beta/models/" + currentModel + 
        (useGrounding ? ":generateContent" : "");
    
    var payload = {
        contents: contents
    };
    
    if (systemPrompt) {
         payload.system_instruction = {
            parts: [{ text: systemPrompt }]
        };
    }

    request("POST", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        // Extract text from response
        // Structure: candidates[0].content.parts[0].text
        var responseText = "";
        if (response.candidates && response.candidates.length > 0 &&
            response.candidates[0].content && 
            response.candidates[0].content.parts &&
            response.candidates[0].content.parts.length > 0) {
            
            responseText = response.candidates[0].content.parts[0].text;
            
            callback(responseText, null);
        } else {
            callback(null, "Empty response from API");
        }
    }, payload);
}
