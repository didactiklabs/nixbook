.pragma library

var baseUrl = "http://localhost:11434"; // Default
var currentModel = "llama3";

function setBaseUrl(url) {
    if (url) {
        // Strip trailing slash if present
        if (url.endsWith("/")) {
            baseUrl = url.substring(0, url.length - 1);
        } else {
            baseUrl = url;
        }
    }
}

function setModel(model) {
    // Strip prefix if present (e.g. "ollama:llama3" -> "llama3")
    if (model.indexOf("ollama:") === 0) {
        currentModel = model.substring(7);
    } else {
        currentModel = model;
    }
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
                callback(null, "Ollama HTTP Error: " + xhr.status);
            }
        }
    };
    xhr.open(method, url);
    xhr.setRequestHeader("Content-Type", "application/json");
    if (data) {
        xhr.send(JSON.stringify(data));
    } else {
        xhr.send();
    }
}

function listModels(callback) {
    var url = baseUrl + "/api/tags";

    request("GET", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        var models = [];
        if (response.models) {
            for (var i = 0; i < response.models.length; i++) {
                var m = response.models[i];
                // Prefix with ollama: to distinguish
                var modelData = { 
                    "name": "ollama:" + m.name, 
                    "display_name": m.name,
                    "provider": "ollama"
                };
                models.push(modelData);
            }
        }
        callback(models, null);
    });
}

function sendChat(history, systemPrompt, callback) {
    var url = baseUrl + "/api/chat";
    
    // Map standard history [{role: 'user'|'model', content: ''}] to Ollama [{role: 'user'|'assistant', content: ''}]
    var messages = [];
    if (systemPrompt) {
        messages.push({ role: "system", content: systemPrompt });
    }
    
    for (var i = 0; i < history.length; i++) {
        var item = history[i];
        // Our internal 'model' role -> 'assistant' for ollama
        var r = (item.role === 'model') ? 'assistant' : item.role;
        messages.push({
            role: r,
            content: item.content
        });
    }
    
    var payload = {
        model: currentModel,
        messages: messages,
        stream: false 
    };
    
    request("POST", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        var responseText = "";
        
        if (response.message && response.message.content) {
            responseText = response.message.content;
            callback(responseText, null);
        } else {
            callback(null, "Empty response from Ollama");
        }
    }, payload);
}
