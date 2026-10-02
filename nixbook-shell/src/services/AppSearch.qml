pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    // The caches live in a plain JS object mutated in place: they are filled
    // lazily from inside bindings (dock, taskbar, media chips…), and assigning
    // a notifying property there would re-trigger the very binding that is
    // reading it (a binding loop). `_generation` is the only notifying part:
    // bumping it re-evaluates dependent bindings when the entries change.
    readonly property var _caches: ({ index: null, icons: ({}) })
    property int _generation: 0
    onListChanged: {
        root._caches.index = null;
        root._caches.icons = ({});
        // Entries arrive one by one at startup: re-evaluate dependents once
        // per burst, not once per entry.
        Qt.callLater(root._bumpGeneration);
    }
    function _bumpGeneration() {
        root._generation++;
    }

    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    // ------------------------------------------------------------ search
    // Tiered scoring modelled on DankMaterialShell's AppSearchService: exact /
    // prefix / word-boundary / substring on the name, then generic name ("Web
    // Browser"), desktop id, keywords, comment/description and the executable,
    // then typo-tolerant (Levenshtein) and subsequence (fuzzysort) fallbacks.
    // Frecency (launch count + recency) breaks ties and lifts habitual apps.
    // The per-app lowercase index is built once per desktop-entry change
    // instead of per keystroke.
    readonly property int maxResults: 50

    function tokenize(text) {
        return (text || "").toLowerCase().trim().split(/[\s\-_.]+/).filter(w => w.length > 0);
    }

    function searchIndex() {
        root._generation; // dependency only
        if (root._caches.index !== null)
            return root._caches.index;
        root._caches.index = root.list.map(app => {
            const exec = (app.command && app.command.length > 0) ? app.command[0].split("/").pop().toLowerCase() : "";
            return {
                app: app,
                name: (app.name || "").toLowerCase(),
                nameWords: root.tokenize(app.name),
                genericName: (app.genericName || "").toLowerCase(),
                genericWords: root.tokenize(app.genericName),
                comment: (app.comment || "").toLowerCase(),
                id: (app.id || "").toLowerCase(),
                exec: exec,
                keywords: (app.keywords || []).map(k => k.toLowerCase()),
                prepared: root.preppedNames.find(p => p.entry === app)?.name
            };
        });
        return root._caches.index;
    }

    function wordsStartWith(textWords, queryWords) {
        if (queryWords.length === 0 || queryWords.length > textWords.length)
            return false;
        for (let i = 0; i <= textWords.length - queryWords.length; i++) {
            let ok = true;
            for (let j = 0; j < queryWords.length; j++) {
                if (!textWords[i + j].startsWith(queryWords[j])) {
                    ok = false;
                    break;
                }
            }
            if (ok)
                return true;
        }
        return false;
    }

    function levenshtein(a, b) {
        const m = a.length, n = b.length;
        let prev = new Array(n + 1);
        for (let j = 0; j <= n; j++) prev[j] = j;
        for (let i = 1; i <= m; i++) {
            const cur = [i];
            for (let j = 1; j <= n; j++)
                cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
            prev = cur;
        }
        return prev[n];
    }

    function typoScore(words, q) {
        const maxDistance = q.length <= 3 ? 0 : q.length <= 5 ? 1 : 2;
        if (maxDistance === 0)
            return 0;
        let best = 0;
        for (const w of words) {
            if (Math.abs(w.length - q.length) > maxDistance)
                continue;
            const d = root.levenshtein(w, q);
            if (d <= maxDistance)
                best = Math.max(best, 1 - d / Math.max(w.length, q.length));
        }
        return best;
    }

    function textScore(e, q, qWords) {
        if (e.name === q) return 10000;
        if (e.name.startsWith(q)) return 6000;
        if (root.wordsStartWith(e.nameWords, qWords)) return 4000;
        if (e.exec === q) return 3500;
        if (e.name.includes(q)) return 1500;
        if (e.exec.startsWith(q)) return 1200;
        if (e.genericName.startsWith(q) || root.wordsStartWith(e.genericWords, qWords)) return 1000;
        if (e.keywords.some(k => k === q)) return 900;
        if (e.keywords.some(k => k.startsWith(q))) return 700;
        if (e.genericName.includes(q)) return 500;
        if (e.id.includes(q)) return 400;
        if (e.keywords.some(k => k.includes(q))) return 300;
        if (qWords.length > 1 && qWords.every(w => e.comment.includes(w))) return 250;
        if (e.comment.includes(q)) return 200;
        const typo = root.typoScore(e.nameWords.concat(e.genericWords, e.keywords), q);
        if (typo > 0) return 100 + typo * 100;
        return 0;
    }

    function search(query: string): var {
        const q = (query || "").toLowerCase().trim();
        if (q.length === 0)
            return [];
        const qWords = root.tokenize(q);
        const scored = [];
        const seen = new Set();
        for (const e of root.searchIndex()) {
            const t = root.textScore(e, q, qWords);
            if (t > 0) {
                scored.push({ app: e.app, score: t + root.frecencyBonus(e.app.id) });
                seen.add(e.app);
            }
        }
        // Subsequence fallback ("frfx" -> Firefox), only for apps not matched above.
        const fuzzy = Fuzzy.go(q, root.preppedNames, { key: "name", limit: root.maxResults, threshold: 0.35 });
        for (const r of fuzzy) {
            const app = r.obj.entry;
            if (seen.has(app))
                continue;
            scored.push({ app: app, score: 50 + r.score * 50 + root.frecencyBonus(app.id) / 4 });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.slice(0, root.maxResults).map(s => s.app);
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }
        return root.search(search);
    }

    // ---------------------------------------------------------- frecency
    property var usage: ({})   // desktop id -> { count, last }
    // Bumped whenever `usage` changes (it's mutated in place, so it doesn't
    // notify): the launcher's app list re-sorts on it.
    property int usageRevision: 0
    function frecencyBonus(id) {
        const u = root.usage[id];
        if (!u)
            return 0;
        const days = (Date.now() - (u.last || 0)) / 86400000;
        const recency = days < 1 ? 1200 : days < 7 ? 800 : days < 30 ? 400 : 100;
        return recency + Math.min(u.count || 0, 50) * 20;
    }
    function recordLaunch(id) {
        if (!id)
            return;
        const u = root.usage[id] ?? { count: 0, last: 0 };
        u.count = (u.count || 0) + 1;
        u.last = Date.now();
        root.usage[id] = u;
        root.usageRevision++;
        usageSaveTimer.restart();
    }
    FileView {
        id: usageFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/app-usage.json`)
        onLoaded: {
            try {
                root.usage = JSON.parse(usageFile.text()) || {};
            } catch (e) {
                root.usage = {};
            }
            root.usageRevision++;
        }
        onLoadFailed: root.usage = {}
    }
    Timer {
        id: usageSaveTimer
        interval: 2000
        onTriggered: usageFile.setText(JSON.stringify(root.usage))
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    // guessIcon() runs from bindings in the taskbar, dock, notifications...
    // and the fallbacks walk the icon theme (Quickshell.iconPath) repeatedly;
    // memoize per class name until the desktop entries change.
    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";
        root._generation; // dependency only
        const cached = root._caches.icons[str];
        if (cached !== undefined) return cached;
        const icon = root.guessIconUncached(str);
        root._caches.icons[str] = icon;
        return icon;
    }

    function guessIconUncached(str) {

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
