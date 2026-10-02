import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * What the settings window's search finds: every page's sections
 * (ContentSection / ContentSubsection titles) and settings (the labels of
 * its Config* controls), read from the pages' QML files, each with its page
 * and the section it sits in. Labels are the source (English) strings: they
 * are matched both as written and translated.
 */
Item {
    id: root

    // SettingsContent's `pages`: {name, icon, component}.
    required property var pages
    // [{page: index, kind: "section" | "setting", label, section}]
    property var entries: []

    // The controls whose `text` is a setting's label, and those whose
    // `title` is a section's.
    readonly property var settingControls: /^(Config\w+|RingtoneSetting)$/
    readonly property var sectionControls: /^(ContentSection|ContentSubsection)$/

    function parse(source, pageIndex) {
        const found = [];
        let component = "";
        let section = "";
        for (const line of source.split("\n")) {
            const open = /^\s*([A-Z]\w*)\s*\{/.exec(line);
            if (open) {
                component = open[1];
                continue;
            }
            const m = /^\s*(title|text):\s*Translation\.tr\("((?:[^"\\]|\\.)+)"\)/.exec(line);
            if (!m) continue;
            const label = m[2].replace(/\\"/g, '"');
            if (m[1] === "title" && root.sectionControls.test(component)) {
                section = label;
                found.push({ page: pageIndex, kind: "section", label: label, section: "" });
            } else if (m[1] === "text" && root.settingControls.test(component) && label.length <= 80) {
                found.push({ page: pageIndex, kind: "setting", label: label, section: section });
            }
        }
        return found;
    }

    Instantiator {
        id: pageFiles
        model: root.pages
        delegate: FileView {
            required property var modelData
            // `component` is a qs:@/ URL inside Quickshell: the file in the shell tree.
            path: FileUtils.trimFileProtocol(Quickshell.shellPath(`modules/ii/settings/${String(modelData.component).split("/settings/").pop()}`))
            onLoaded: rebuildTimer.restart()
        }
    }
    Timer {
        id: rebuildTimer
        interval: 100
        onTriggered: {
            let all = [];
            for (let i = 0; i < pageFiles.count; i++) {
                const view = pageFiles.objectAt(i);
                if (view && view.loaded)
                    all = all.concat(root.parse(view.text(), i));
            }
            root.entries = all;
        }
    }

    // The entries matching every word of `query` (in the label, its
    // translation, its section or its page's name); labels starting with
    // the query first, then settings before sections.
    function search(query, limit) {
        const words = query.toLowerCase().split(/\s+/).filter(w => w !== "");
        if (words.length === 0) return [];
        const q = words.join(" ");
        const scored = [];
        for (const e of root.entries) {
            const label = Translation.tr(e.label).toLowerCase();
            const haystack = `${label} ${e.label.toLowerCase()} ${Translation.tr(e.section).toLowerCase()} ${(root.pages[e.page]?.name ?? "").toLowerCase()}`;
            if (!words.every(w => haystack.includes(w))) continue;
            const score = (label.startsWith(q) ? 0 : label.includes(q) ? 1 : 2) + (e.kind === "section" ? 0.5 : 0);
            scored.push({ entry: e, score: score });
        }
        scored.sort((a, b) => a.score - b.score || a.entry.label.length - b.entry.label.length);
        return scored.slice(0, limit ?? 40).map(s => s.entry);
    }
}
