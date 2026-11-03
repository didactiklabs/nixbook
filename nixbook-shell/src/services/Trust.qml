pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import QtQuick

/**
 * The trust ladder: each kind of action DAI takes in the side panel or the
 * bubble (a tool, its action, the app: `close_window@firefox`,
 * `seerr__cancel_request`) is asked first (Allow / Always / No), done and
 * told after ("Did: …"), or done silently. The gate is the helper's /trust
 * hook (desktop-mcp.py trust_gate, Claude Code's PreToolUse, Ai.agentHooks):
 * its events come through DesktopHelper and land on the chat whose Claude
 * session asked (`approval`, `toldSteps`, `trustSuggestion` on
 * AiChatSession). Only the user's clicks set a level (`setTrust`: Always,
 * "Stop asking", Settings > Desktop agents > Trust), never an agent.
 */
Singleton {
    id: root

    readonly property bool enabled: (Config.options?.ai?.trust?.enable ?? true) && (Config.options?.policies?.ai ?? 1) !== 0

    // [{class, level, maxLevel, streak, last, summary, neverPromote, …}], as `trust list`.
    property var list: []
    property bool loaded: false
    function refresh() {
        DesktopHelper.run(["trust", "list"], "", (code, out) => {
            let data = null;
            try {
                data = code === 0 ? JSON.parse(out) : null;
            } catch (e) {}
            root.list = (Array.isArray(data) ? data : []).filter(c => typeof c?.class === "string")
                .sort((a, b) => String(a.class).localeCompare(String(b.class)));
            root.loaded = data !== null;
        });
    }
    // The user's own choice (a click): done(ok, why).
    function setTrust(cls, level, done) {
        if (!["ask", "tell", "silent"].includes(level) || !/^[\w.:@+-]{1,200}$/.test(String(cls ?? ""))) {
            if (done) done(false, "");
            return;
        }
        DesktopHelper.run(["trust", "set", String(cls), level], "", (code, out) => {
            // A refusal is JSON too ({"error": …}, exit 1).
            let r = null;
            try {
                r = JSON.parse(out);
            } catch (e) {}
            const ok = code === 0 && !(r?.error);
            root.refresh();
            if (done) done(ok, ok ? "" : String(r?.error ?? "").replace(/^refused:\s*/i, "").trim());
        });
    }

    // The chat whose Claude asked: by its session, else the one answering.
    function _chatFor(session) {
        const chats = Ai.chats ?? [];
        const bySession = chats.find(c => session && c.claudeSessionId === session);
        if (bySession) return bySession;
        const busy = chats.filter(c => c.responding);
        return busy.length === 1 ? busy[0] : (Ai.current ?? null);
    }

    Connections {
        target: DesktopHelper
        function onApprovalAsked(a) {
            const chat = root._chatFor(String(a?.session ?? ""));
            // Nowhere to ask: not done.
            if (!chat) {
                DesktopHelper.answerApproval(a?.id, false);
                return;
            }
            chat.approval = { id: String(a.id), tool: String(a.tool ?? ""), server: String(a.server ?? ""),
                summary: String(a.summary ?? ""), class: String(a.class ?? "") };
        }
        function onApprovalExpired(id) {
            for (const chat of Ai.chats ?? [])
                if (chat.approval?.id === id) chat.approval = null;
        }
        function onStepTold(t) {
            const chat = root._chatFor(String(t?.session ?? ""));
            if (chat) chat.toldSteps = [...chat.toldSteps, { class: String(t.class ?? ""), summary: String(t.summary ?? "") }].slice(-6);
        }
        function onTrustSuggested(s) {
            const chat = root._chatFor(String(s?.session ?? ""));
            if (chat) chat.trustSuggestion = { class: String(s.class ?? ""), summary: String(s.summary ?? "") };
        }
    }
}
