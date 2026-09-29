pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Emojis, read from assets/emojis.txt (generated at build time by
 * scripts/emojis.py from Unicode and CLDR data): after a "### DATA ###"
 * line, one "<emoji> <name>\t<keywords>" per line. Searches match name and
 * keywords; the launcher shows the name.
 */
Singleton {
    id: root
    property string emojiScriptPath: `${Directories.assetsPath}/emojis.txt`
	property string lineBeforeData: "### DATA ###"
    property list<var> list
    // Per entry: the name's words and the keywords, lowercased, for ranking.
    readonly property var indexed: list.map(entry => {
        const tab = entry.indexOf("\t");
        const head = tab < 0 ? entry : entry.slice(0, tab);
        const name = head.replace(/^\s*\S+\s+/, "").toLowerCase();
        return {
            entry: entry,
            name: name,
            nameWords: name.split(/[\s:,.-]+/).filter(w => w !== ""),
            keywords: tab < 0 ? [] : entry.slice(tab + 1).toLowerCase().split(" "),
            fuzzy: Fuzzy.prepare(name)
        };
    })

    // Every query word must hit the name or a keyword; the best hit per word
    // counts: the whole name, a name word, a keyword ("lol" -> 😂), the start
    // of a name word, the start of a keyword. Ties keep Unicode's order. Nothing
    // hits: fall back to fuzzy matching on the names (typos).
    function score(item, words) {
        let total = 0;
        for (const w of words) {
            let best = 0;
            if (item.nameWords.includes(w)) best = 50;
            else if (item.keywords.includes(w)) best = 40;
            else if (item.nameWords.some(n => n.startsWith(w))) best = 30;
            else if (item.keywords.some(k => k.startsWith(w))) best = 10;
            if (best === 0)
                return -Infinity;
            total += best;
        }
        if (item.name === words.join(" "))
            total += 100;
        // Shorter names first among equals ("heart": ❤️ red heart before
        // 😍 smiling face with heart-eyes).
        return total - item.nameWords.length;
    }

    function fuzzyQuery(search: string): var {
        // The service is created by the first query: read the list now
        // (blockLoading) rather than answer that query empty.
        if (root.list.length === 0)
            root.updateEmojis(emojiFileView.text());
        const words = search.toLowerCase().split(/\s+/).filter(w => w !== "");
        if (words.length === 0)
            return root.list;
        const hits = [];
        root.indexed.forEach((item, i) => {
            const s = root.score(item, words);
            if (s > -Infinity)
                hits.push({ entry: item.entry, score: s, i: i });
        });
        if (hits.length > 0)
            return hits.sort((a, b) => b.score - a.score || a.i - b.i).map(h => h.entry);
        return Fuzzy.go(search, root.indexed, { all: true, key: "fuzzy" }).map(r => r.obj.entry);
    }

    function load() {
        emojiFileView.reload()
    }

    function updateEmojis(fileContent) {
        const lines = fileContent.split("\n")
        const dataIndex = lines.indexOf(root.lineBeforeData)
        if (dataIndex === -1) {
            console.warn("No data section found in emoji script file.")
            return
        }
        const emojis = lines.slice(dataIndex + 1).filter(line => line.trim() !== "")
        root.list = emojis.map(line => line.trim())
    }

    FileView { 
        id: emojiFileView
        path: root.emojiScriptPath
        // The first emoji query reads it: have the list ready for it.
        blockLoading: true
        onLoadedChanged: {
            const fileContent = emojiFileView.text()
            root.updateEmojis(fileContent)
        }
    }
}
