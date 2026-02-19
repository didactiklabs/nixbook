.pragma library

var baseUrl = "http://localhost:1234";
var currentModel = "";

function setBaseUrl(url) {
    if (url) {
        if (url.endsWith("/")) {
            baseUrl = url.substring(0, url.length - 1);
        } else {
            baseUrl = url;
        }
    }
}

function setModel(model) {
    // Strip prefix if present (e.g. "lmstudio:model-name" -> "model-name")
    if (model.indexOf("lmstudio:") === 0) {
        currentModel = model.substring(9);
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
    // LM Studio uses "lm-studio" as the API key by convention
    xhr.setRequestHeader("Authorization", "Bearer lm-studio");
    xhr.setRequestHeader("Content-Type", "application/json");
    if (data) {
        xhr.send(JSON.stringify(data));
    } else {
        xhr.send();
    }
}

function listModels(callback) {
    var url = baseUrl + "/v1/models";

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
                    "name": "lmstudio:" + m.id,
                    "display_name": m.id,
                    "provider": "lmstudio"
                };
                models.push(modelData);
            }
        }
        callback(models, null);
    });
}

function sendChat(history, systemPrompt, callback) {
    var url = baseUrl + "/v1/chat/completions";

    // Map standard history to OpenAI-compatible format
    var messages = [];
    if (systemPrompt) {
        messages.push({
            role: "system",
            content: systemPrompt
        });
    }

    for (var i = 0; i < history.length; i++) {
        var item = history[i];
        // Our internal 'model' role -> 'assistant' for OpenAI-compatible API
        var r = (item.role === 'model') ? 'assistant' : item.role;

        messages.push({
            role: r,
            content: item.content
        });
    }

    var data = {
        model: currentModel,
        messages: messages,
        stream: false
    };

    request("POST", url, function(response, error) {
        if (error) {
            callback(null, error);
            return;
        }

        if (response.choices && response.choices.length > 0) {
            var content = response.choices[0].message.content;
            callback(content, null);
        } else {
            callback(null, "No response content from LM Studio");
        }
    }, data);
}
