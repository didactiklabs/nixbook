import QtQuick

// Claude through Claude Code (`claude -p … --output-format stream-json`), on
// the user's own Claude login: no API key. Claude Code runs the tools itself
// (the desktop MCP server, web search, reading files), so this only turns its
// event stream into the chat message: text as it streams, thinking and each
// tool call with its result in one collapsible <think> block, the session id
// (the next message resumes it) and the token usage. The command line is
// built by Ai.qml (claudeCodeScript).
QtObject {
    // Tool calls of the current answer, by id: "name input", shown with
    // their result in one block.
    property var toolCalls: ({})
    // The turn's tool calls, in order: {id, tool (its short name), summary,
    // status run|ok|error} — what Full AI's mascot thinks out loud (a new
    // list each change: bindings see it).
    property var steps: []
    property bool finished: false
    // The privacy mask: placeholders (⟦Person 2⟧) shown as the real values.
    // A placeholder cut between two pieces of the stream waits for its end.
    property var unmask: text => text
    property string held: ""

    function reset() {
        toolCalls = ({});
        steps = [];
        finished = false;
        held = "";
    }

    // A placeholder or a pseudonym split between two chunks ("⟦Person" +
    // " 7 first⟧", "Bri" + "sa"): held back until whole, so the real name
    // is shown, never the fake one (the last word waits for the next chunk).
    function append(message, text) {
        let s = held + text;
        const open = s.lastIndexOf("⟦");
        held = open >= 0 && s.indexOf("⟧", open) < 0 && s.length - open < 40 ? s.slice(open) : "";
        if (held.length > 0) s = s.slice(0, open);
        else {
            const tail = /[A-Za-z\u00C0-\u024F\u1E00-\u1EFF][A-Za-z\u00C0-\u024F\u1E00-\u1EFF0-9_'’-]*$/.exec(s);
            if (tail && tail[0].length < 40) {
                held = tail[0];
                s = s.slice(0, tail.index);
            }
        }
        s = unmask(s);
        message.rawContent += s;
        message.content += s;
    }

    function flush(message) {
        if (held.length === 0) return;
        const s = unmask(held);
        held = "";
        message.rawContent += s;
        message.content += s;
    }

    // One line of JSON, short enough to read in the chat.
    function brief(value, max) {
        let s = typeof value === "string" ? value : JSON.stringify(value);
        s = (s ?? "").replace(/\s+/g, " ").trim();
        return s.length > max ? s.slice(0, max) + "…" : s;
    }

    function toolLabel(name) {
        // mcp__desktop__click -> desktop: click
        const m = /^mcp__([^_]+(?:_[^_]+)*)__(.+)$/.exec(name ?? "");
        return m ? `${m[1]}: ${m[2]}` : name;
    }

    function resultText(content) {
        if (typeof content === "string") return content;
        if (!Array.isArray(content)) return "";
        return content.map(c => c.type === "text" ? c.text : c.type === "image" ? "[image]" : "").join(" ");
    }

    function parseResponseLine(line, message) {
        const data = line.trim();
        if (data.length === 0 || data[0] !== "{") return {};
        const ev = JSON.parse(data);
        const out = {};
        if (ev.session_id) out.sessionId = ev.session_id;

        if (ev.type === "stream_event") {
            // Text and thinking as they come (--include-partial-messages).
            const e = ev.event ?? {};
            if (e.type === "content_block_start" && e.content_block?.type === "thinking")
                append(message, "\n\n<think>\n");
            else if (e.type === "content_block_delta" && e.delta?.type === "text_delta")
                append(message, e.delta.text);
            else if (e.type === "content_block_delta" && e.delta?.type === "thinking_delta")
                append(message, e.delta.thinking);
            else if (e.type === "content_block_stop" && message.rawContent.lastIndexOf("<think>") > message.rawContent.lastIndexOf("</think>"))
                append(message, "\n</think>\n\n");
            // A text block's end: its last word, held back (append), shown.
            else if (e.type === "content_block_stop")
                flush(message);
        } else if (ev.type === "assistant") {
            // Whole messages repeat the streamed text: only the tool calls.
            for (const block of (ev.message?.content ?? [])) {
                if (block.type !== "tool_use") continue;
                toolCalls[block.id] = `**${toolLabel(block.name)}** ${brief(block.input, 300)}`;
                steps = [...steps, { id: block.id, tool: String(block.name ?? "").replace(/^mcp__[^_]+__/, ""),
                                     // Shown (the bubble's step line): the real names, the
                                     // mask is for the model provider only. Unmasked before
                                     // it is cut, so no name is left half a stand-in.
                                     summary: brief(unmask(JSON.stringify(block.input ?? {})), 80), status: "run" }];
            }
        } else if (ev.type === "user") {
            for (const block of (ev.message?.content ?? [])) {
                if (block.type !== "tool_result") continue;
                steps = steps.map(x => x.id === block.tool_use_id ? Object.assign({}, x, { status: block.is_error ? "error" : "ok" }) : x);
                const call = toolCalls[block.tool_use_id] ?? "**tool**";
                const text = brief(resultText(block.content), 400);
                append(message, `\n\n<think>\n${call}\n\n${block.is_error ? "⚠ " : "→ "}${text}\n</think>\n\n`);
            }
        } else if (ev.type === "result") {
            flush(message);
            finished = true;
            out.finished = true;
            if (ev.is_error) {
                const why = ev.result || (ev.errors ?? []).join("; ") || ev.subtype;
                append(message, `\n\n**Error**: ${why}`);
            }
            const u = ev.usage ?? {};
            const input = (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
            out.tokenUsage = { input: input, output: u.output_tokens ?? 0, total: input + (u.output_tokens ?? 0) };
        }
        return out;
    }

    function onRequestFinished(message) {
        flush(message);
        // Claude Code exited without a result: say so (not logged in, crashed…).
        if (!finished && message.rawContent.trim().length === 0)
            append(message, "**Error**: Claude Code stopped without an answer. Is it installed and logged in (`claude`, then /login)?");
    }
}
