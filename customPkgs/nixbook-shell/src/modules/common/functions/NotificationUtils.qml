pragma Singleton
import Quickshell

Singleton {
    id: root
    /**
     * @param { string } summary 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "") {
        const defaultType = 'chat';
        if (summary.length === 0) return defaultType;

        const keywordsToTypes = {
            'reboot': 'restart_alt',
            'record': 'screen_record',
            'battery': 'power',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'scheduleb',
            'installed': 'download',
            'configuration reloaded': 'reset_wrench',
            'unable': 'question_mark',
            "couldn't": 'question_mark',
            'config': 'reset_wrench',
            'update': 'update',
            'ai response': 'neurology',
            'control': 'settings',
            'upsca': 'compare',
            'music': 'queue_music',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'startswith:file': 'folder_copy', // Declarative startsWith check
        };

        const lowerSummary = summary.toLowerCase();

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (lowerSummary.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (lowerSummary.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const now = new Date();
        const diffMs = now.getTime() - messageTime.getTime();

        // Less than 1 minute
        if (diffMs < 60000)
            return 'Now';

        // Same day - show relative time
        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return `${diffHours}h`;
            } else {
                return `${diffMinutes}m`;
            }
        }

        // Yesterday
        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return 'Yesterday';

        // Older dates
        return Qt.formatDateTime(messageTime, "MMMM dd");
    }

    function processNotificationBody(body, appName) {
        let processedBody = body
        
        // Clean Chromium-based browsers notifications - remove first line
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n')

                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }

        processedBody = processedBody.replace(/<img/gi, '\n\n<img');

        return processedBody
    }

    /**
     * A body as plain text: markup stripped and entities decoded (KDE Connect
     * sends `&quot;`, `&#39;`… that only a rich-text view would render).
     */
    function plainText(text) {
        const named = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };
        return `${text ?? ""}`.replace(/<[^>]*>/g, "")
            .replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (m, e) => {
                if (e[0] !== "#") return named[e.toLowerCase()] ?? m;
                const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
                return code > 0 && code <= 0x10FFFF ? String.fromCodePoint(code) : m;
            });
    }

    /**
     * The last message of a chat notification. Phones (KDE Connect) re-post a
     * conversation with every new message appended: the first line is
     * "sender: text" or "conversation: sender:", then each sender change is a
     * line "sender:" alone, the messages on the next lines. A later
     * "x: text" line is a message ("Liked your message: …", "Note: …"), not
     * a sender. { sender, text, block } for the last one — block = its lines
     * as they appear, from the sender's. Without a sender line: no sender,
     * the whole text.
     */
    function lastMessage(text) {
        const lines = `${text ?? ""}`.split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            const m = lines[i].match(/^([^:]{1,40}):(?: (.*))?$/);
            if (!m || (i > 0 && (m[2] ?? "").trim() !== "")) continue;
            // "conversation: sender:" — the sender is the second name.
            const inner = i === 0 ? (m[2] ?? "").match(/^([^:]{1,40}):$/) : null;
            const first = inner ? "" : m[2] ?? "";
            const text = [first, ...lines.slice(i + 1)].join("\n").trim();
            return { sender: (inner ? inner[1] : m[1]).trim(), text: text, block: lines.slice(i).join("\n") };
        }
        return { sender: "", text: `${text ?? ""}`, block: `${text ?? ""}` };
    }

    /**
     * Notification filter rules (Settings → Notifications → Persona cut-in).
     * One rule = terms joined by "+", all of which must hold:
     *   Victor                 "victor" anywhere (case-insensitive)
     *   Victor + Instagram     both present
     *   Victor + !newsletter   "victor" present, "newsletter" absent
     *   app:Instagram          only look in one field — app, title, body,
     *                          last (the body's last chat message, with its
     *                          sender), line (the body's last line: the newest
     *                          message of a re-posted thread) or hint (string
     *                          hints); no prefix = all
     *   "Diệu"                 whole word only (not inside a longer word)
     *   last:^You:             the field starts with it (a chat's sender)
     * Prefixes combine: !title:^"re". A term can't contain "+" or ",".
     */
    function ruleFields(n) {
        const hints = n?.hints ?? {};
        const f = {
            app: `${n?.appName ?? ""}`,
            title: root.plainText(n?.summary),
            body: root.plainText(n?.body),
            hint: Object.keys(hints).map(k => typeof hints[k] === "string" ? hints[k] : "").join(" "),
        };
        f.last = root.lastMessage(f.body).block;
        f.line = f.body.trim().split("\n").pop();
        f.any = `${f.app} ${f.title} ${f.body} ${f.hint}`;
        for (const k in f) f[k] = f[k].toLowerCase();
        return f;
    }
    function isWordChar(c) {
        return c !== undefined && (c.toLowerCase() !== c.toUpperCase() || /[0-9_]/.test(c));
    }
    function containsWord(text, word) {
        for (let i = text.indexOf(word); i !== -1; i = text.indexOf(word, i + 1))
            if (!root.isWordChar(text[i - 1]) && !root.isWordChar(text[i + word.length])) return true;
        return false;
    }
    // One "+"-term against the fields; null = empty term (ignored).
    function termHolds(fields, term) {
        let t = term.trim();
        let negate = false;
        if (t.startsWith("!")) { negate = true; t = t.slice(1).trim(); }
        let field = "any";
        const m = t.match(/^(app|title|body|last|line|hint):/i);
        if (m) { field = m[1].toLowerCase(); t = t.slice(m[0].length).trim(); }
        let start = false;
        if (t.startsWith("^")) { start = true; t = t.slice(1).trim(); }
        let whole = false;
        if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) { whole = true; t = t.slice(1, -1).trim(); }
        t = t.toLowerCase();
        if (t.length === 0) return null;
        const text = start ? fields[field].replace(/^\s+/, "") : fields[field];
        const found = start ? text.startsWith(t) && !(whole && root.isWordChar(text[t.length]))
            : whole ? root.containsWord(text, t) : text.includes(t);
        return found !== negate;
    }
    function ruleMatches(fields, rule) {
        const results = `${rule ?? ""}`.split("+").map(t => root.termHolds(fields, t)).filter(r => r !== null);
        // Only negative terms ("!x") is allowed: it matches whatever lacks x.
        return results.length > 0 && results.every(r => r);
    }
    // The first of `rules` that `n` matches, or "" if none.
    function firstMatchingRule(n, rules) {
        if (!n) return "";
        const fields = root.ruleFields(n);
        return (rules ?? []).find(r => root.ruleMatches(fields, r)) ?? "";
    }

    /**
     * Duplicate detection (services/Notifications.qml duplicateVerdict).
     * Text as compared: markup and entities gone, lower case, and every run
     * of whitespace, ASCII/Latin-1/general punctuation (bidi isolates
     * included — Discord wraps names in them) and CJK punctuation folded to
     * one space. Letters of any script, digits and emoji are kept.
     */
    function matchText(text) {
        return root.plainText(text).normalize("NFKC").toLowerCase()
            .replace(/[\s!-\/:-@\[-`{-~ -¿ -⁯⸀-⹿　-〿︀-️﻿]+/g, " ")
            .trim();
    }

    // Is `n` mirrored from another device (appName in `relayApps`)?
    function isRelayed(n, relayApps) {
        const app = `${n?.appName ?? ""}`.toLowerCase();
        return app !== "" && (relayApps ?? []).some(a => `${a}`.toLowerCase() === app);
    }

    /**
     * Is `relay` (a phone's copy, e.g. KDE Connect: title = the phone app,
     * body = "conversation: sender:\nmessage…") the same message as `local`
     * (the desktop app's own notification)? Strict on purpose:
     *  - the relayed text must END with the local message (a phone re-posting
     *    a whole thread only matches on its newest message), whole words;
     *  - and share a word of 3+ characters with the local title (the sender,
     *    channel or server), so a short "ok" from someone else never matches.
     *    A local notification without a usable title needs a 24+ character
     *    message instead.
     */
    function isRelayOf(local, relay) {
        const body = root.matchText(local?.body);
        const message = body !== "" ? body : root.matchText(local?.summary);
        if (message.length < 2) return false;
        const relayText = root.matchText(`${relay?.summary ?? ""}\n${relay?.body ?? ""}`);
        if (relayText !== message && !relayText.endsWith(` ${message}`)) return false;
        const relayWords = new Set(relayText.split(" "));
        const titleWords = body === "" ? []
            : root.matchText(local?.summary).split(" ").filter(w => w.length >= 3);
        return titleWords.length > 0 ? titleWords.some(w => relayWords.has(w)) : message.length >= 24;
    }

    // Same app, title and text.
    function isRepeatOf(n, older) {
        return `${n?.appName}` === `${older?.appName}`
            && root.matchText(n?.summary) === root.matchText(older?.summary)
            && root.matchText(n?.body) === root.matchText(older?.body);
    }

    /**
     * Does `n` re-post `older` with more lines appended (same app and title,
     * the old text followed by a new line)? Phones mirror a chat this way,
     * the whole thread each time a message arrives.
     */
    function isThreadUpdateOf(n, older) {
        const body = root.plainText(n?.body).trim();
        const old = root.plainText(older?.body).trim();
        return `${n?.appName}` === `${older?.appName}`
            && root.matchText(n?.summary) === root.matchText(older?.summary)
            && old !== "" && body.startsWith(`${old}\n`);
    }
}
