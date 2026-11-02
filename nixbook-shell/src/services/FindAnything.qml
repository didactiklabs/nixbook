pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import QtQuick

/**
 * "Find it": the launcher's find prefix (search.prefix.find, `~` by
 * default) searches what the user saw or kept on this computer — recent
 * files (Downloads, Documents, Desktop, screenshots: names and the text of
 * small text files and PDFs), Zen's history and bookmarks, the clipboard
 * history, the notification history and the conversations with DAI —
 * with the time words of the request ("the PDF
 * from Monday", "le lien d'hier") as a range. The search is desktop-mcp's
 * find_anything (`nixbook-desktop-mcp find … --json`, through the helper:
 * no model, nothing leaves the computer); DAI uses the same tool. Never a
 * secret, nor a hidden folder; nothing with policies.ai 0.
 * `search(text)` (debounced), `results` [{kind, title, when, where,
 * snippet, action: {open, copy, cliphist, chat}}], `open(r)`,
 * `copy(r)`, `showInFolder(r)`.
 */
Singleton {
    id: root

    property string query: ""
    property var results: []
    property bool busy: false
    property bool off: false
    property string rangeLabel: ""
    property int _generation: 0

    function search(text) {
        const q = String(text ?? "").trim();
        if (q === root.query)
            return;
        root.query = q;
        root._generation++;
        if (q.length === 0) {
            root.results = [];
            root.rangeLabel = "";
            root.busy = false;
            debounce.stop();
            return;
        }
        root.busy = true;
        debounce.restart();
    }

    function _run() {
        const generation = root._generation;
        DesktopHelper.run(["find", root.query, "--max", "20", "--json"], "", (code, out) => {
            if (generation !== root._generation)
                return; // a later search replaced it
            root.busy = false;
            let r = null;
            try {
                r = JSON.parse(String(out ?? "").trim() || "null");
            } catch (e) {
                r = null;
            }
            root.off = !!r?.off;
            root.rangeLabel = r?.range?.label ?? "";
            root.results = (code === 0 && Array.isArray(r?.results)) ? r.results : [];
        });
    }

    Timer {
        id: debounce
        interval: 250
        onTriggered: root._run()
    }

    function icon(kind) {
        switch (kind) {
        case "file": return "description";
        case "page": return "public";
        case "bookmark": return "bookmark";
        case "clipboard": return "content_paste";
        case "notification": return "notifications";
        case "chat": return "forum";
        default: return "search";
        }
    }

    function kindLabel(kind) {
        switch (kind) {
        case "file": return Translation.tr("File");
        case "page": return Translation.tr("Visited page");
        case "bookmark": return Translation.tr("Bookmark");
        case "clipboard": return Translation.tr("Copied");
        case "notification": return Translation.tr("Notification");
        case "chat": return Translation.tr("Conversation with DAI");
        default: return Translation.tr("Found");
        }
    }

    function whenText(r) {
        return r.when ? Qt.formatDateTime(new Date(r.when * 1000), "ddd d MMM, hh:mm") : "";
    }

    // The row's main action: open what was found (a file with its app, a
    // link in the browser, a conversation in the side panel), else copy it.
    function verb(r) {
        const a = r.action ?? {};
        if (a.chat) return Translation.tr("Open");
        if (a.open) return Translation.tr("Open");
        return Translation.tr("Copy");
    }

    function open(r) {
        const a = r.action ?? {};
        if (a.chat) {
            GlobalStates.sidebarLeftOpen = true;
            Ai.openChatInNewTab(a.chat);
        } else if (a.open && /^https?:\/\//i.test(a.open)) {
            AppLaunch.openUrl(a.open);
        } else if (a.open) {
            AppLaunch.spawn(["xdg-open", a.open]);
        } else {
            root.copy(r);
        }
    }

    function copy(r) {
        const a = r.action ?? {};
        if (a.cliphist)
            Cliphist.copy(a.cliphist);
        else
            Quickshell.clipboardText = a.copy ?? a.open ?? r.title;
    }

    function showInFolder(r) {
        const path = r.action?.open ?? "";
        if (r.kind === "file" && path.length > 0)
            AppLaunch.spawn(["xdg-open", path.replace(/\/[^\/]*$/, "")]);
    }
}
