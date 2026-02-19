.pragma library

var apiKey = "";
var currentModel = "";

function setApiKey(key) {
    apiKey = key;
}

function setModel(model) {
    currentModel = model;
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
        xhr.setRequestHeader("x-api-key", apiKey);
    }
    xhr.setRequestHeader("anthropic-version", "2023-06-01");
    xhr.setRequestHeader("Content-Type", "application/json");
    if (data) {
        xhr.send(JSON.stringify(data));
    } else {
        xhr.send();
    }
}

function listModels(callback) {
    var url = "https://api.anthropic.com/v1/models";
    
    request("GET", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        var models = [];
        if (response.data) {
            for (var i = 0; i < response.data.length; i++) {
                var m = response.data[i];
                var modelData = { 
                    "name": m.id, 
                    "display_name": m.display_name || m.id,
                    "provider": "anthropic" 
                };
                models.push(modelData);
            }
        }
        callback(models, null);
    });
}

function sendChat(history, systemPrompt, callback) {
    var url = "https://api.anthropic.com/v1/messages";
    
    // Map standard history to Anthropic format
    var messages = [];
    
    for (var i = 0; i < history.length; i++) {
        var item = history[i];
        // Our internal 'model' role -> 'assistant' for anthropic
        var r = (item.role === 'model') ? 'assistant' : item.role;
        
        messages.push({
            role: r,
            content: item.content
        });
    }

    var data = {
        model: currentModel,
        max_tokens: 4096,
        messages: messages
    };
    
    // Add system prompt if provided
    if (systemPrompt) {
        data.system = systemPrompt;
    }

    request("POST", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        if (response.content && response.content.length > 0) {
            var content = response.content[0].text;
            callback(content, null);
        } else {
            callback(null, "No response content");
        }
    }, data);
}
