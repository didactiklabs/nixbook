.pragma library

var colors = {
    "keyword": "#cc7832", // Orange
    "string": "#6a8759", // Green
    "number": "#6897bb", // Blue
    "comment": "#808080", // Grey
    "type": "#a9b7c6", // White/Default
    "function": "#ffc66d" // Yellow
};

var keywords = [
    "function", "var", "let", "const", "if", "else", "for", "while", "return", 
    "import", "from", "class", "this", "new", "true", "false", "null", "undefined",
    "property", "signal", "Component", "id", "switch", "case", "break", "continue",
    "try", "catch", "finally", "async", "await", "export", "default", "def", "print", "enum", "struct"
];

function escapeHtml(unsafe) {
    if (!unsafe) return "";
    return unsafe
         .replace(/&/g, "&amp;")
         .replace(/</g, "&lt;")
         .replace(/>/g, "&gt;")
         .replace(/"/g, "&quot;")
         .replace(/'/g, "&#039;");
}

function highlight(code, language) {
    if (!code) return "";
    
    var output = "";
    var i = 0;
    var len = code.length;
    
    while (i < len) {
        // Comment //
        if (code.substr(i, 2) === "//") {
            var end = code.indexOf("\n", i);
            if (end === -1) end = len;
            output += "<span style='color:" + colors.comment + "'>" + escapeHtml(code.substring(i, end)) + "</span>";
            i = end;
            continue;
        }

         // Comment /* */
        if (code.substr(i, 2) === "/*") {
            var end = code.indexOf("*/", i + 2);
            if (end === -1) end = len;
            else end += 2;
            output += "<span style='color:" + colors.comment + "'>" + escapeHtml(code.substring(i, end)) + "</span>";
            i = end;
            continue;
        }

        // Python/Shell comment #
        // Only if language implies it or generic guess? 
        // Let's assume yes because it rarely conflicts with JS/C like syntax except for specialized macros, and it's useful.
        if (code[i] === '#') {
             var end = code.indexOf("\n", i);
            if (end === -1) end = len;
            output += "<span style='color:" + colors.comment + "'>" + escapeHtml(code.substring(i, end)) + "</span>";
            i = end;
            continue;
        }

        // String " or ' or `
        if (code[i] === '"' || code[i] === "'" || code[i] === '`') {
            var quote = code[i];
            var end = i + 1;
            while (end < len) {
                if (code[end] === '\\') { // escape
                    end += 2;
                    continue;
                }
                if (code[end] === quote) {
                     end++;
                     break;
                }
                end++;
            }
            output += "<span style='color:" + colors.string + "'>" + escapeHtml(code.substring(i, end)) + "</span>";
            i = end;
            continue;
        }
        
        // Word (Keywords)
        if (/[a-zA-Z_]/.test(code[i])) {
            var start = i;
            while (i < len && /[a-zA-Z0-9_]/.test(code[i])) {
                i++;
            }
            var word = code.substring(start, i);
            if (keywords.indexOf(word) !== -1) {
                output += "<span style='color:" + colors.keyword + "'>" + word + "</span>"; // No escape needed for alphanumeric
            } else {
                output += escapeHtml(word);
            }
            continue;
        }
        
        // Numbers
         if (/[0-9]/.test(code[i])) {
            var start = i;
            while (i < len && /[0-9\.]/.test(code[i])) {
                i++;
            }
            output += "<span style='color:" + colors.number + "'>" + code.substring(start, i) + "</span>";
            continue;
         }

        // Other chars
        output += escapeHtml(code[i]);
        i++;
    }
    
    // Wrap in pre tag to preserve whitespace and newlines
    // white-space: pre-wrap ensures wrapping fits within the container
    return "<pre style='white-space: pre-wrap; margin: 0;'>" + output + "</pre>";
}
