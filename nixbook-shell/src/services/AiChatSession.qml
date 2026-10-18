pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.ai

/**
 * One conversation of the side panel's chat, in a tab of its own (Ai.chats):
 * its messages, its Claude Code (kept running between messages, resuming its
 * session) and its own agent desktop when agents work on theirs, so tabs
 * work in parallel without fighting over one pointer and keyboard. Slot 1
 * uses the first agent desktop (nixbook-agent-desktop), slot N the
 * nixbook-agent-desktop@N one (NIXBOOK_AGENT_DESKTOP, given to the desktop
 * MCP server). The models, settings and history are Ai.qml's.
 */
Scope {
    id: chat

    required property int slot
    readonly property string desktopInstance: chat.slot > 1 ? String(chat.slot) : ""
    readonly property bool isCurrent: Ai.current === chat

    property var messageIDs: []
    property var messageByID: ({})
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }
    property string chatId: "" // its conversation in the history ("" until saved)
    property string claudeSessionId: ""
    property string pendingFilePath: ""
    // Answered while not looked at (another tab, or the panel closed).
    property bool unread: false
    readonly property bool responding: requester.turnActive || personalContext.running

    // The tab for what Claude says on its own (services/Initiative.qml): one,
    // reused, whatever the tab count.
    property bool fromClaude: false
    readonly property string title: {
        if (chat.fromClaude) return Translation.tr("From Claude");
        const saved = Ai.history.find(c => c.id === chat.chatId)?.title;
        if (saved) return saved;
        const first = chat.messageIDs.map(id => chat.messageByID[id]).find(m => m?.role === "user");
        return first ? (Ai.titleFor(first.rawContent) || Translation.tr("New chat")) : Translation.tr("New chat");
    }

    readonly property bool seen: chat.isCurrent && GlobalStates.sidebarLeftOpen
    onSeenChanged: if (seen) chat.unread = false

    property ClaudeCodeApiStrategy strategy: ClaudeCodeApiStrategy {}

    // Files of its own: the command line Claude Code runs with, and the task
    // for the desktop MCP server's memory (NIXBOOK_DESKTOP_MCP_QUERY_FILE):
    // written before each message, read by the running server on its next call.
    readonly property string requestScriptFilePath: `${Directories.aiTemp}/request-${chat.slot}.sh`
    readonly property string desktopTaskFilePath: `${Directories.aiTemp}/desktop-task-${chat.slot}.txt`
    FileView {
        id: desktopTaskFile
        blockWrites: true
    }
    FileView {
        id: requesterScriptFile
        blockWrites: true
    }

    function addMessage(message, role, unsent = false, learnHint = "") {
        if (message.length === 0) return;
        const aiMessage = Ai.aiMessageComponent.createObject(chat, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
            "unsent": unsent,
            "learnHint": learnHint,
        });
        const id = Ai.idForMessage(aiMessage);
        chat.messageIDs = [...chat.messageIDs, id];
        chat.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= chat.messageIDs.length) return;
        const id = chat.messageIDs[index];
        chat.messageIDs.splice(index, 1);
        chat.messageIDs = [...chat.messageIDs];
        delete chat.messageByID[id];
    }

    function clearMessages() {
        chat.runMemoryPass(); // the chat being left
        chat.memoryReadUpTo = 0;
        chat.claudeSessionId = "";
        chat.chatId = "";
        chat.messageIDs = [];
        chat.messageByID = ({});
        chat.tokenCount.input = -1;
        chat.tokenCount.output = -1;
        chat.tokenCount.total = -1;
    }

    function chatToJson() {
        return chat.messageIDs.map(id => {
            const message = chat.messageByID[id];
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            });
        });
    }

    // Replaces the messages with saved ones (the history, /load).
    function setMessages(saved) {
        chat.clearMessages();
        const ids = [];
        const byID = {};
        for (const message of saved) {
            const messageId = Ai.idForMessage();
            ids.push(messageId);
            byID[messageId] = Ai.aiMessageComponent.createObject(chat, Object.assign({}, message, {
                "content": message.rawContent ?? "",
                "thinking": false,
                "done": true,
            }));
        }
        chat.messageByID = byID;
        chat.messageIDs = ids;
        // A saved chat: the pass read it when it was left.
        chat.memoryReadUpTo = ids.length;
    }

    // A conversation of the history, opened here: Claude Code's session too
    // when Claude Code still has it (it deletes them after a while,
    // cleanupPeriodDays), else the next message sends the conversation so
    // far as context.
    function openSaved(id, saved) {
        // The answer being written stays with the conversation it is for.
        if (requester.turnActive) {
            chat.stopResponse();
            Ai.saveHistory(chat);
        }
        chat.setMessages(saved.messages ?? []);
        chat.chatId = id;
        const session = saved.claudeSessionId ?? "";
        if (/^[0-9a-f-]{36}$/.test(session)) {
            claudeSessionCheck.chat = id;
            claudeSessionCheck.session = session;
            claudeSessionCheck.running = true;
        }
    }
    Process {
        id: claudeSessionCheck
        property string chat
        property string session
        command: ["bash", "-c", `test -n "$(find "\${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -maxdepth 2 -name "$1.jsonl" -print -quit 2>/dev/null)"`,
            "claude-session", session]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && chat.chatId === claudeSessionCheck.chat && chat.claudeSessionId.length === 0)
                chat.claudeSessionId = claudeSessionCheck.session;
        }
    }

    function attachFile(filePath: string) {
        chat.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function sendUserMessage(message) {
        if (chat.fromClaude) Initiative.engaged();
        if (message.length === 0) return;
        chat.addMessage(message, "user");
        requester.makeRequest();
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= chat.messageIDs.length) return;
        const message = chat.messageByID[chat.messageIDs[messageIndex]];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = chat.messageIDs.length - 1; i >= messageIndex; i--) {
            chat.removeMessage(i);
        }
        // Claude Code's session still holds the removed answer: start a new
        // one, with the chat so far as context.
        chat.claudeSessionId = "";
        requester.makeRequest();
    }

    // Stops the answer being written (and, for Claude, what it is doing).
    function stopResponse() {
        if (!requester.turnActive) return;
        requester.restartPending = false;
        requester.interrupting = true;
        requester.write(JSON.stringify({ type: "control_request", request_id: `stop-${Date.now()}`,
            request: { subtype: "interrupt" } }) + "\n");
        stopFallback.restart();
    }

    // The tab closed: its Claude Code stopped, its agent desktop (not the
    // first, which other tools use too) closed, what it said remembered.
    function close() {
        chat.runMemoryPass();
        requester.pendingLine = "";
        requester.restartPending = false;
        if (requester.running) requester.signal(15);
        if (chat.desktopInstance.length > 0)
            Quickshell.execDetached(["systemctl", "--user", "stop", `nixbook-agent-desktop@${chat.desktopInstance}.service`]);
    }

    // The panel opened on this tab, on Claude: Claude Code started ahead, so
    // the first message doesn't wait for it.
    function prewarm() {
        if (requester.running || requester.turnActive) return;
        // Only a new chat or the session of this one, with no file attached.
        requester.pendingLine = "";
        requester.launch("", chat.claudeSessionId);
    }

    // The connectors listed again: a message waiting for that goes now; an
    // idle Claude Code that started with others starts again.
    function connectorsChecked(changed) {
        if (changed) requester.connectorsStale = true;
        requester.connectorsChecked();
    }

    // The personal memory entries sent with this Claude session's messages
    // (`nixbook-desktop-mcp personal context`), not to send twice.
    property var personalShown: []
    Process {
        id: personalContext
        property string prompt: ""
        property string attached: ""
        property bool sent: false
        function send(found) {
            if (sent) return;
            sent = true;
            requester.sendPrompt(found.length > 0 ? `${found}\n\n${prompt}` : prompt, attached);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let found = "";
                try {
                    const result = JSON.parse(text);
                    found = result.text ?? "";
                    chat.personalShown = [...chat.personalShown, ...(result.ids ?? [])];
                } catch (e) {
                    console.log("[Ai] Personal memory unavailable:", e);
                }
                personalContext.send(found);
            }
        }
        // Without it (an error) the message goes as it is.
        onExited: Qt.callLater(() => personalContext.send(""))
    }

    // The memory pass (`nixbook-desktop-mcp personal learn`): Claude is told
    // to save what matters about the user, but mid-task it often doesn't.
    // So once a chat with Claude goes quiet (ai.claudeCode.autoMemory), or
    // is left (cleared, another loaded, its tab closed), the turns the pass
    // hasn't read go to a small model that saves what is worth keeping.
    // Detached: it outlives the chat, and costs nothing while the chat goes on.
    property int memoryReadUpTo: 0 // the messages the pass has read
    FileView {
        id: memoryPassFile
        blockWrites: true
    }
    Timer {
        id: memoryPassTimer
        interval: 2 * 60 * 1000
        onTriggered: requester.turnActive ? restart() : chat.runMemoryPass()
    }
    function runMemoryPass() {
        memoryPassTimer.stop();
        const messages = chat.messageIDs.map(id => chat.messageByID[id]);
        const from = Math.min(chat.memoryReadUpTo, messages.length);
        chat.memoryReadUpTo = messages.length;
        if (!(Config.options?.ai?.claudeCode?.autoMemory ?? true) || Ai.claudeCodePath.length === 0) return;
        const isTurn = m => m && (m.role === "user" || m.role === "assistant") && !m.functionName && (m.rawContent ?? "").length > 0;
        const fresh = messages.slice(from).filter(isTurn);
        // Only what the user said to Claude (not the config assistant).
        if (!fresh.some(m => m.role === "user") || !fresh.some(m => m.role === "assistant" && m.model === "claude")) return;
        const line = m => m.role === "user" ? `User: ${m.rawContent}`
            : `Assistant: ${m.rawContent.length > 1200 ? m.rawContent.slice(0, 1200) + "…" : m.rawContent}`;
        const earlier = messages.slice(0, from).filter(isTurn).slice(-2);
        const transcript = (earlier.length > 0 ? `(Earlier, read already:)\n${earlier.map(line).join("\n\n")}\n\n(New:)\n` : "")
            + fresh.map(line).join("\n\n");
        const path = `${Directories.aiTemp}/memory-pass-${Date.now()}-${chat.slot}.txt`;
        memoryPassFile.path = Qt.resolvedUrl(path);
        memoryPassFile.setText(transcript);
        Quickshell.execDetached([Ai.desktopMcpCommand, "personal", "learn", "--claude", Ai.claudeCodePath,
            "--model", Config.options.ai.claudeCode.memoryModel || "haiku", "--delete", path]);
    }

    // Claude Code, kept running between messages: a message is one line on
    // its stdin, the answer ends with a "result" event. Started again
    // (resuming the session) when the command line it needs changes (the
    // settings, an attached file) or for another chat; started ahead when
    // the panel opens; closed after a while unused.
    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        stdinEnabled: true
        property AiMessageData message
        property AiMessageData activeMessage
        property bool restartPending: false
        // The command line it runs, without --resume, and the session it
        // goes on with ("" for a new one, until its first answer names it);
        // ready once started (stdin open).
        property string script: ""
        property string session: ""
        property bool ready: false
        // The line to send once it has started; the message being answered.
        property string pendingLine: ""
        property bool turnActive: false
        property bool interrupting: false
        // The connectors changed since it started; a message waiting for
        // them to be listed again (its attached file).
        property bool connectorsStale: false
        property bool connectorsHold: false
        property string heldAttached: ""
        // The message line sent and its attached file, to send again when
        // Claude Code started with a connector it wasn't allowed (once per
        // message).
        property string sentLine: ""
        property string sentAttached: ""
        property bool connectorRetried: false

        // Claude Code names the servers it loaded at the start of a turn.
        // A claude.ai connector missing from the allowed ones (added on
        // claude.ai since they were listed): allowed, and Claude Code started
        // again on the same message before the model answers. True if so.
        function restartForConnectors(ev) {
            if (!Ai.claudeConnectorsSetting || requester.connectorRetried) return false;
            // From its servers' names and, exactly, from its tools' names
            // (mcp__<server>__<tool>).
            const found = [...(ev.mcp_servers ?? []).filter(s => /^claude\.ai /.test(s.name ?? ""))
                    .map(s => Ai.connectorRule(s.name)),
                ...(ev.tools ?? []).map(t => /^(mcp__claude_ai_.+?)__/.exec(t)?.[1]).filter(r => r)];
            const missing = [...new Set(found)].filter(n => !Ai.claudeConnectors.includes(n));
            if (missing.length === 0) return false;
            Ai.claudeConnectors = [...Ai.claudeConnectors, ...missing];
            requester.connectorRetried = true;
            requester.pendingLine = requester.sentLine;
            // Not an answer: the message stays open for the new one.
            requester.activeMessage = null;
            requester.turnActive = false;
            requester.launch(requester.sentAttached, chat.claudeSessionId);
            return true;
        }

        function markDone() {
            const stopped = requester.interrupting;
            requester.turnActive = false;
            requester.interrupting = false;
            stopFallback.stop();
            idleClose.restart();
            if (!requester.activeMessage || requester.activeMessage.done) return;
            requester.activeMessage.done = true;
            requester.activeMessage.thinking = false;
            // Not when another conversation was opened here meanwhile.
            if (Object.values(chat.messageByID).includes(requester.activeMessage)) {
                if (chat.isCurrent) Ai.saveChat("lastSession");
                Ai.saveHistory(chat);
            }
            Ai.responseFinished();
            memoryPassTimer.restart();
            if (!chat.seen) chat.unread = true;
            // Stopped by the user: they're there already.
            if (!stopped) chat.notifyDone(requester.activeMessage);
        }

        function makeRequest() {
            // The config assistant: answered here from the configuration, no request.
            if (Ai.usingConfigAssistant) {
                const turns = chat.messageIDs.map(id => chat.messageByID[id]).filter(m => m?.role === "user");
                const question = turns[turns.length - 1]?.rawContent ?? "";
                const previous = turns[turns.length - 2]?.rawContent ?? "";
                let answer = Translation.tr("The configuration facts aren't loaded (~/.config/nixbook-shell/system-facts.json, generated by the Home Manager module).");
                try {
                    if (ConfigAssistant.ready) answer = ConfigAssistant.answer(question, previous);
                } catch (e) {
                    console.warn("[Ai] ConfigAssistant.answer failed:", e);
                }
                const reply = Ai.aiMessageComponent.createObject(chat, {
                    "role": "assistant", "model": Ai.currentModelId,
                    "content": answer, "rawContent": answer, "thinking": false, "done": true,
                });
                const replyId = Ai.idForMessage(reply);
                chat.messageIDs = [...chat.messageIDs, replyId];
                chat.messageByID[replyId] = reply;
                if (chat.isCurrent) Ai.saveChat("lastSession");
                Ai.saveHistory(chat);
                Ai.responseFinished();
                return;
            }

            const messageArray = chat.messageIDs.map(id => chat.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            chat.strategy.reset();

            /* Create local message object */
            requester.message = Ai.aiMessageComponent.createObject(chat, {
                "role": "assistant",
                "model": Ai.currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = Ai.idForMessage(requester.message);
            chat.messageIDs = [...chat.messageIDs, id];
            chat.messageByID[id] = requester.message;

            let attachedFile = chat.pendingFilePath;
            if (attachedFile && attachedFile.length > 0) {
                requester.message.localFilePath = attachedFile;
                chat.pendingFilePath = "";
            }
            const attached = attachedFile && attachedFile.length > 0 && attachedFile.startsWith("/") ? attachedFile : "";

            /* Send the request */
            const prompt = Ai.claudeCodePrompt(filteredMessageArray, attached, chat.claudeSessionId);
            for (const m of filteredMessageArray) {
                m.unsent = false;
                m.learnHint = "";
            }
            const turns = filteredMessageArray.filter(m => m.role === "user");
            desktopTaskFile.path = Qt.resolvedUrl(chat.desktopTaskFilePath);
            desktopTaskFile.setText((turns[turns.length - 1]?.rawContent ?? "").slice(0, 500));
            // What Claude remembers about the user that this message is
            // about goes with it (the personal memory, in the desktop MCP
            // server): no recall round trip.
            if (chat.claudeSessionId.length === 0) chat.personalShown = [];
            const desktop = Ai.currentTool !== "none" && Ai.desktopTools.some(t => t.name === "recall_about_user");
            if (desktop && !personalContext.running) {
                personalContext.prompt = prompt;
                personalContext.attached = attached;
                personalContext.sent = false;
                personalContext.command = [Ai.desktopMcpCommand, "personal", "context",
                    "--exclude", chat.personalShown.join(",") || ",", turns[turns.length - 1]?.rawContent ?? ""];
                personalContext.running = true;
                return;
            }
            requester.sendPrompt(prompt, attached);
        }

        function sendPrompt(prompt, attached) {
            requester.pendingLine = JSON.stringify({ type: "user", message: { role: "user", content: Ai.messageContext() + prompt } }) + "\n";
            requester.sentAttached = attached;
            requester.connectorRetried = false;
            // A connector needed signing in to: perhaps it's done now.
            if (Ai.claudeConnectorsSetting && Ai.claudeConnectorsNeedAuth
                    && Date.now() - Ai.claudeConnectorsCheckedAt > 20000) {
                requester.connectorsHold = true;
                requester.heldAttached = attached;
                if (Ai.checkClaudeConnectors()) return;
                requester.connectorsHold = false;
            }
            requester.start(attached);
        }

        function connectorsChecked() {
            if (requester.connectorsHold) {
                requester.connectorsHold = false;
                requester.start(requester.heldAttached);
            } else if (requester.connectorsStale && requester.running && !requester.turnActive) {
                // Idle: started again now, not on the next message.
                requester.pendingLine = "";
                requester.launch("", requester.session);
            }
        }

        // Sends the pending message: to the Claude Code running, when it
        // fits, else to one started for it.
        function start(attached) {
            if (requester.running && !requester.restartPending && !requester.turnActive && !requester.connectorsStale
                    && requester.script === Ai.claudeCodeScript(chat, attached, "")
                    && requester.session === chat.claudeSessionId) {
                if (requester.ready) requester.send(); // else once started
                return;
            }
            if (requester.activeMessage && requester.activeMessage !== requester.message && !requester.activeMessage.done) {
                requester.activeMessage.done = true;
                requester.activeMessage.thinking = false;
            }
            requester.launch(attached, chat.claudeSessionId);
        }

        // Starts Claude Code (after stopping the one running): resume, the
        // session to go on with.
        function launch(attached, resume) {
            requester.connectorsStale = false;
            requester.script = Ai.claudeCodeScript(chat, attached, "");
            requester.session = resume;
            requesterScriptFile.path = Qt.resolvedUrl(CF.FileUtils.trimFileProtocol(chat.requestScriptFilePath));
            requesterScriptFile.setText("#!/usr/bin/env bash\n" + Ai.claudeCodeScript(chat, attached, resume));
            if (requester.running) {
                requester.restartPending = true;
                requester.signal(15);
            } else {
                requester.spawn();
            }
        }

        function spawn() {
            requester.turnActive = false;
            requester.ready = false;
            requester.command = baseCommand.concat([CF.FileUtils.trimFileProtocol(chat.requestScriptFilePath)]);
            requester.running = true;
        }

        function send() {
            if (requester.pendingLine.length === 0) return;
            requester.activeMessage = requester.message;
            requester.turnActive = true;
            idleClose.stop();
            requester.sentLine = requester.pendingLine;
            requester.write(requester.pendingLine);
            requester.pendingLine = "";
        }

        onStarted: {
            requester.ready = true;
            requester.send();
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0 || !requester.activeMessage || !requester.turnActive) return;
                if (requester.activeMessage.thinking) requester.activeMessage.thinking = false;

                try {
                    // Stopped: the "result" that ends the answer is no error to show.
                    if (requester.interrupting && data.trim().startsWith("{") && JSON.parse(data).type === "result") {
                        chat.strategy.finished = true;
                        requester.markDone();
                        return;
                    }
                    if (data.includes('"subtype":"init"')) {
                        const ev = JSON.parse(data);
                        if (ev.type === "system" && ev.subtype === "init" && requester.restartForConnectors(ev)) return;
                    }
                    const result = chat.strategy.parseResponseLine(data, requester.activeMessage);

                    if (result.sessionId) {
                        chat.claudeSessionId = result.sessionId;
                        requester.session = result.sessionId;
                    }
                    if (result.tokenUsage) {
                        chat.tokenCount.input = result.tokenUsage.input;
                        chat.tokenCount.output = result.tokenUsage.output;
                        chat.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.activeMessage.rawContent += data;
                    requester.activeMessage.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (requester.turnActive && requester.activeMessage && !requester.activeMessage.done && !requester.interrupting)
                chat.strategy.onRequestFinished(requester.activeMessage);
            requester.markDone();
            requester.ready = false;
            idleClose.stop();
            if (requester.restartPending) {
                requester.restartPending = false;
                requester.spawn();
            }
        }
    }

    // Stop: Claude Code interrupts the answer and waits for the next
    // message; stopped if it doesn't.
    Timer {
        id: stopFallback
        interval: 5000
        onTriggered: if (requester.turnActive) { requester.restartPending = false; requester.signal(15); }
    }

    // Unused for a while: closed (a few hundred MB); the next message
    // resumes the session.
    Timer {
        id: idleClose
        interval: 15 * 60 * 1000
        onTriggered: if (requester.running && !requester.turnActive) { requester.restartPending = false; requester.signal(15); }
    }

    // Claude finished a turn while the panel is closed (ai.notifyWhenDone):
    // a notification says so, "waiting for you" when it ends on a question,
    // and its Open button opens the panel on this tab. Not in Do Not Disturb.
    function notifyDone(message) {
        if (!(Config.options?.ai?.notifyWhenDone ?? true) || GlobalStates.sidebarLeftOpen || Notifications.silent) return;
        const lines = (message?.rawContent ?? "").split("\n")
            .map(l => l.replace(/[*_`#>]+/g, "").replace(/\s+/g, " ").trim())
            .filter(l => l.length > 0);
        const last = lines.length > 0 ? lines[lines.length - 1] : "";
        const asks = /[?？]$/.test(last);
        const notice = last.length > 140 ? last.slice(0, 139) + "…" : last;
        const summary = asks ? Translation.tr("The assistant is waiting for you") : Translation.tr("The assistant is done");
        doneNotifier.command = ["notify-send", "-a", "Shell", "-A", "open=" + Translation.tr("Open"), "--",
            Ai.chats.length > 1 ? `${summary} · ${chat.title}` : summary, notice];
        doneNotifier.running = false;
        doneNotifier.running = true;
    }
    Process {
        id: doneNotifier
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "open") return;
                Ai.selectChat(chat);
                GlobalStates.sidebarLeftOpen = true;
            }
        }
    }
}
