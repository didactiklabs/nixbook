pragma Singleton

import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    property string query: ""

    // Typing the layouts prefix reads the saved layouts again, like the
    // `layouts` key binding (Overview.toggleLayouts) does: the list loaded at
    // startup misses the ones saved since by agents (desktop MCP), and stays
    // empty if that first read failed.
    readonly property bool layoutsMode: root.query.startsWith(Config.options.search.prefix.layouts)
    onLayoutsModeChanged: {
        if (root.layoutsMode)
            WindowLayouts.refresh();
    }

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.themes, Config.options.search.prefix.layouts, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch,].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }
    
    Process {
        id: keywordHarvester
        property var pendingPages: []
        property string currentPageName: ""
        
        function startHarvesting() {
            root.settingsKeywordsCache = {}; 
            pendingPages = root.settingsIndex.slice();
            next();
        }

        function next() {
            if (pendingPages.length === 0) {
                return;
            }
            
            let currentPage = pendingPages.shift();
            let fullPath = FileUtils.trimFileProtocol(
                Quickshell.shellPath("modules/ii/settings/pages/" + currentPage.path)
            )

            let rawCommand = "grep -oP \"title:\\s*Translation.tr\\(['\\\"].*?['\\\"]\\)\" " + fullPath + " | sed -E \"s/title:\\s*Translation.tr\\(['\\\"](.*)['\\\"]\\)/\\1/g\" | tr '\\n' ' '";
            
            command = ["bash", "-c", rawCommand];
            
            keywordHarvester.currentPageName = currentPage.page;
            running = true;
        }

        onExited: (exitCode, exitStatus) => {
            keywordHarvester.next();
        }

        stdout: SplitParser {
            onRead: data => {
                let cache = root.settingsKeywordsCache;
                cache[keywordHarvester.currentPageName] = (cache[keywordHarvester.currentPageName] || "") + " " + data;
                root.settingsKeywordsCache = cache;
            }
        }
    }

    Component.onCompleted: {
        keywordHarvester.startHarvesting();
    }


    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    property var settingsKeywordsCache: ({})

    // Page names must match SettingsContent.qml's `pages` (GlobalStates.settingsPage
    // looks them up by name).
    property var settingsIndex: [
        { page: "Quick",       path: "QuickConfig.qml" },
        { page: "Appearance",  path: "AppearanceConfig.qml" },
        { page: "Desktop",     path: "BackgroundConfig.qml" },
        { page: "Bar",         path: "BarConfig.qml" },
        { page: "Panels",      path: "PanelsConfig.qml" },
        { page: "Lock screen", path: "LockScreenConfig.qml" },
        { page: "General",     path: "GeneralConfig.qml" },
        { page: "Services",    path: "ServicesConfig.qml" },
        { page: "Niri",        path: "NiriConfig.qml" },
        { page: "About",       path: "About.qml" },
    ]

    // Load user action scripts from ~/.config/nixbook-shell/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                if (Config.options.wallpaperSelector.useSystemFileDialog)
                    Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
                else
                    GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen;
            }
        },
        {
            action: "equalizer",
            execute: () => {
                Qt.callLater(() => GlobalStates.equalizerOpen = true);
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Quickshell.execDetached(["bash", "-c", "rm -f ~/.cache/cliphist/db"]);
            }
        },
        {
            action: "unsplash",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("Usage: /unsplash YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "unsplash"], args.trim());
                Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "wallhaven",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("Usage: /wallhaven YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "wallhaven"], args.trim());
                Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "pexels",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("Usage: /pexels YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "pexels"], args.trim());
                Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "openweather",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "OpenWeather", Translation.tr("Usage: /openweather YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "openweather"], args.trim());
                Quickshell.execDetached(["notify-send", "OpenWeather", Translation.tr("API key saved!"), "-a", "Shell"]);
                Weather.getData();
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    // The shell's own panels with no app of their own, found by name or by
    // what they're for (a word starting the query, or the query starting one).
    readonly property var shellTools: [
        {
            id: "equalizer",
            name: Translation.tr("Equalizer"),
            icon: "graphic_eq",
            comment: Translation.tr("Shape the sound: presets, 10 bands, or following the song's genre (EasyEffects)"),
            keywords: ["equalizer", "equaliser", "eq", "bass", "treble", "audio", "sound", "easyeffects"],
            open: () => GlobalStates.equalizerOpen = true,
        },
    ]

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    // qalc only runs for queries that look like maths (a digit, or the math
    // prefix): it used to be spawned 30 ms after every keystroke, whatever was
    // typed, and its answer re-ran the whole search below.
    function looksLikeMath(query) {
        return query.startsWith(Config.options.search.prefix.math) || /\d/.test(query);
    }
    onQueryChanged: {
        if (root.looksLikeMath(root.query)) {
            nonAppResultsTimer.restart();
        } else {
            nonAppResultsTimer.stop();
            root.mathResult = "";
        }
    }
    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    // One result object per desktop entry, reused across keystrokes. Upstream
    // created a fresh LauncherSearchResult (plus one per desktop action) for
    // every matching app on every keystroke and whenever the calculator result
    // arrived, which churned the JS heap while typing.
    // A plain JS object mutated in place (it's filled from inside the results
    // binding). Each object remembers the DesktopEntry it was built from
    // (appResultEntries): a rescan that replaces or edits an entry gets a
    // fresh object the next time the results binding asks for it. The cache
    // used to be dropped wholesale when DesktopEntries changed, but that ran
    // after the results binding had already re-read it: the launcher kept
    // the old objects, destroyed a second later (blank tiles launching
    // nothing until the next keystroke).
    readonly property var appResultCache: ({})
    readonly property var appResultEntries: ({})
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            // Once AppSearch.list and the results binding caught up.
            Qt.callLater(root.pruneAppResults);
        }
    }
    // Destroys the objects of apps that are gone, unless still listed.
    function pruneAppResults() {
        const current = new Set(AppSearch.list);
        for (const key in root.appResultCache) {
            if (current.has(root.appResultEntries[key]))
                continue;
            const obj = root.appResultCache[key];
            delete root.appResultCache[key];
            delete root.appResultEntries[key];
            if (!root.results.includes(obj))
                obj.destroy(1000);
        }
    }
    // Preloader "launcher" stage: build the search index and every app's result
    // object while idle, so the first keystroke doesn't pay for them.
    Connections {
        target: Preloader
        function onLauncherChanged() {
            if (!Preloader.launcher) return;
            AppSearch.searchIndex();
            prewarmTimer.pending = Array.from(AppSearch.list);
            prewarmTimer.start();
        }
    }
    // A few apps per tick: result object + one icon-theme lookup each (the
    // first result rows otherwise pay for both on the first keystroke).
    Timer {
        id: prewarmTimer
        property var pending: []
        interval: 16
        repeat: true
        onTriggered: {
            const start = Date.now();
            while (pending.length > 0 && Date.now() - start < 6) {
                const entry = pending.shift();
                root.appResultFor(entry);
                Quickshell.iconPath(entry.icon, true);
            }
            if (pending.length === 0) {
                stop();
                root.appsReady = true;
                root.prewarmed();
            }
        }
    }
    signal prewarmed()
    // Every app's result object is built (prewarmTimer): the empty query can
    // list them all without building them in one go inside the binding.
    property bool appsReady: false

    // Shown before anything is typed (like DankLauncher): every app, the most
    // used first (AppSearch frecency), then A-Z. Typing filters from there.
    function allAppResults() {
        AppSearch.usageRevision; // Re-sort after a launch
        return AppSearch.list
            .map(entry => ({ entry: entry, score: AppSearch.frecencyBonus(entry.id) }))
            .sort((a, b) => (b.score - a.score) || a.entry.name.localeCompare(b.entry.name))
            .map(item => root.appResultFor(item.entry));
    }

    function appResultFor(entry) {
        const key = entry.id || entry.name;
        const cached = root.appResultCache[key];
        if (cached && root.appResultEntries[key] === entry && cached.name === entry.name && cached.iconName === entry.icon)
            return cached;
        // Replaced while the results binding re-reads the apps: the new
        // results drop the old object long before it goes.
        if (cached)
            cached.destroy(2000);
        const obj = resultComp.createObject(root, {
            type: Translation.tr("App"),
            id: entry.id,
            name: entry.name,
            iconName: entry.icon,
            iconType: LauncherSearchResult.IconType.System,
            verb: Translation.tr("Open"),
            execute: () => {
                AppSearch.recordLaunch(entry.id);
                AppLaunch.launchEntry(entry);
            },
            comment: entry.comment,
            runInTerminal: entry.runInTerminal,
            genericName: entry.genericName,
            keywords: entry.keywords,
            actions: (entry.actions ?? []).map(action => resultComp.createObject(root, {
                name: action.name,
                iconName: action.icon,
                iconType: LauncherSearchResult.IconType.System,
                execute: () => {
                    AppSearch.recordLaunch(entry.id);
                    AppLaunch.launchEntry(action, entry);
                }
            }))
        });
        root.appResultCache[key] = obj;
        root.appResultEntries[key] = entry;
        return obj;
    }

    // The rows that are always there (maths, command, web search) are one
    // object each whose text follows the query, and the other rows are cached
    // per entry: the results binding used to create a fresh QObject for every
    // row on every keystroke (thousands with ":" for emojis), and fresh
    // objects also defeat the list's identity diff, so every row was rebuilt.
    LauncherSearchResult {
        id: mathResultObject
        name: root.mathResult
        verb: Translation.tr("Copy")
        type: Translation.tr("Math result")
        fontType: LauncherSearchResult.FontType.Monospace
        iconName: "calculate"
        iconType: LauncherSearchResult.IconType.Material
        execute: () => {
            Quickshell.clipboardText = root.mathResult;
        }
    }
    LauncherSearchResult {
        id: commandResultObject
        name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", "")
        verb: Translation.tr("Run")
        type: Translation.tr("Command")
        fontType: LauncherSearchResult.FontType.Monospace
        iconName: "terminal"
        iconType: LauncherSearchResult.IconType.Material
        execute: () => {
            let cleanedCommand = root.query.replace("file://", "");
            cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
            if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
            }
            AppLaunch.spawnShell(root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand);
        }
    }
    LauncherSearchResult {
        id: webSearchResultObject
        name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch)
        verb: Translation.tr("Search")
        type: Translation.tr("Web search")
        iconName: "travel_explore"
        iconType: LauncherSearchResult.IconType.Material
        execute: () => {
            let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
            let url = Config.options.search.engineBaseUrl + query;
            for (let site of Config.options.search.excludedSites) {
                url += ` -site:${site}`;
            }
            AppLaunch.openUrl(url);
        }
    }

    // Rows past a few screenfuls are never scrolled to; building them only
    // cost time on each keystroke.
    readonly property int maxListResults: 200
    // Cached result objects, keyed "<kind>\t<entry>", dropped wholesale when
    // too many (clipboard history changes, emoji/symbol browsing). A plain JS
    // object mutated in place, never reassigned: it's filled from inside the
    // results binding, and a notifying property would re-trigger it.
    readonly property var _entryCache: ({ objects: ({}), size: 0 })
    // Called before a search builds its rows, never in the middle of one.
    function trimEntryCache() {
        const cache = root._entryCache;
        if (cache.size < 3000)
            return;
        const old = cache.objects;
        cache.objects = ({});
        cache.size = 0;
        for (const id in old)
            old[id].destroy(1000);
    }
    function cachedResult(kind, key, props) {
        const cache = root._entryCache;
        const k = kind + "\t" + key;
        const cached = cache.objects[k];
        if (cached)
            return cached;
        const obj = resultComp.createObject(root, props);
        cache.objects[k] = obj;
        cache.size++;
        return obj;
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return root.appsReady ? root.allAppResults() : [];
        root.trimEntryCache();

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            const clipEntries = Cliphist.fuzzyQuery(searchString).slice(0, root.maxListResults);
            return clipEntries.map((entry, index, array) => {
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const obj = root.cachedResult("clip", entry, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`,
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [resultComp.createObject(root, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }), resultComp.createObject(root, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })]
                });
                // Depends on the neighbours, which change with the query.
                obj.blurImage = shouldBlurImage;
                return obj;
            });
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Emojis
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).slice(0, root.maxListResults).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return root.cachedResult("emoji", entry, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, "").split("\t")[0],
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                    }
                });
            });
        } else if (root.query.startsWith(Config.options.search.prefix.symbols)) {
            // Material Symbols
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.symbols);
            return MaterialSymbolsSearch.fuzzyQuery(searchString).slice(0, root.maxListResults).map(entry => {
                const tabIdx = entry.indexOf("\t");
                const symName = tabIdx >= 0 ? entry.slice(0, tabIdx) : entry;
                const symTags = tabIdx >= 0 ? entry.slice(tabIdx + 1) : "";
                return root.cachedResult("symbol", entry, {
                    rawValue: entry,
                    name: symName,
                    iconName: symName,
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Symbol"),
                    comment: symTags,
                    execute: () => {
                        Quickshell.clipboardText = symName;
                    }
                });
            });
        } else if (root.query.startsWith(Config.options.search.prefix.layouts)) {
            // Saved window layouts (WindowLayouts.qml): restore one, or save
            // the windows under the typed name.
            const typed = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.layouts).trim();
            const terms = typed.toLowerCase().split(/\s+/).filter(Boolean);
            const results = WindowLayouts.layouts.filter(l => {
                const haystack = `${l.name} ${(l.apps ?? []).join(" ")}`.toLowerCase();
                return terms.every(term => haystack.includes(term));
            }).map((l, i) => {
                // Row buttons (SearchItem): update it, delete it (also Shift+Delete).
                const obj = root.cachedResult("layout", l.name, {
                    name: l.name,
                    iconName: "view_quilt",
                    iconType: LauncherSearchResult.IconType.Material,
                    type: Translation.tr("Window layout"),
                    execute: () => WindowLayouts.restore(l.name),
                    actions: [resultComp.createObject(root, {
                            name: Translation.tr("Update with the windows as they are"),
                            iconName: "save",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => WindowLayouts.save(l.name)
                        }), resultComp.createObject(root, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => WindowLayouts.remove(l.name)
                        })]
                });
                // Changes with each save: not only when the row is first made.
                obj.comment = Translation.tr("%1 windows · %2").arg(l.windows).arg((l.apps ?? []).join(", "));
                obj.verb = WindowLayouts.current === l.name ? Translation.tr("Restore (current)") : Translation.tr("Restore");
                return obj;
            });
            // Save: under the typed name when it's a new one, else into the
            // current layout, and always as a new one (layout-N) when nothing
            // is typed: saving must not depend on knowing to type a name.
            // "my work" is saved as my-work: names have no spaces.
            const newName = typed.replace(/\s+/g, "-");
            const exists = WindowLayouts.layouts.some(l => l.name === newName);
            const isNew = newName.length > 0 && !exists;
            const saveRow = (key, saveName, label, comment) => {
                const save = root.cachedResult(key, saveName, {
                    iconName: "save",
                    iconType: LauncherSearchResult.IconType.Material,
                    type: Translation.tr("Window layout"),
                    execute: () => WindowLayouts.save(saveName)
                });
                // A cached row can be "new" one time and "update" the next.
                save.name = label;
                save.comment = comment;
                save.verb = Translation.tr("Save");
                return save;
            };
            if (isNew && WindowLayouts.validName(newName)) {
                results.unshift(saveRow("layout-save", newName, Translation.tr("Save the windows as “%1”").arg(newName),
                    Translation.tr("A new layout")));
            } else if (isNew) {
                const invalid = root.cachedResult("layout-invalid", typed, {
                    name: Translation.tr("Letters, digits, '.', '-' and '_' only"),
                    iconName: "error",
                    iconType: LauncherSearchResult.IconType.Material,
                    type: Translation.tr("Window layout"),
                    execute: () => {}
                });
                invalid.verb = "";
                results.push(invalid);
            } else {
                if (WindowLayouts.current.length > 0 && (typed.length === 0 || newName === WindowLayouts.current))
                    results.push(saveRow("layout-save", WindowLayouts.current,
                        Translation.tr("Update “%1” with the windows as they are").arg(WindowLayouts.current),
                        Translation.tr("The current layout")));
                if (typed.length === 0) {
                    const fresh = WindowLayouts.nextName();
                    results.push(saveRow("layout-save", fresh, Translation.tr("Save the windows as a new layout"),
                        Translation.tr("As “%1”, or type a name first").arg(fresh)));
                }
            }
            return results;
        } else if (root.query.startsWith(Config.options.search.prefix.themes)) {
            // Themes and their variants (Themes.qml): the ones Nix doesn't pin away
            const terms = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.themes).toLowerCase().split(/\s+/).filter(Boolean);
            const themePinned = NixManaged.isPinned("appearance.theme");
            return Themes.list.filter(t => !themePinned || t.id === Themes.current).reduce((acc, t) => {
                const variants = t.variants.length > 0 ? t.variants : [null];
                const variantPinned = variants[0] !== null && NixManaged.isPinned(Themes.variantKey(t.id));
                return acc.concat(variants.filter(v => !variantPinned || v.id === Themes.variantOf(t.id)).map(v => ({ theme: t, variant: v })));
            }, []).filter(({ theme, variant }) => {
                const haystack = `${theme.id} ${theme.name} ${variant?.id ?? ""} ${variant?.name ?? ""}`.toLowerCase();
                return terms.every(term => haystack.includes(term));
            }).map(({ theme, variant }) => {
                const obj = root.cachedResult("theme", `${theme.id}/${variant?.id ?? ""}`, {
                    name: variant ? `${Translation.tr(theme.name)} · ${Translation.tr(variant.name)}` : Translation.tr(theme.name),
                    iconName: variant?.icon ?? theme.icon,
                    iconType: LauncherSearchResult.IconType.Material,
                    type: Translation.tr("Theme"),
                    comment: Translation.tr(theme.description ?? ""),
                    execute: () => {
                        Themes.setTheme(theme.id);
                        if (variant)
                            Themes.setVariant(theme.id, variant.id);
                    }
                });
                const current = Themes.current === theme.id && (!variant || Themes.variant === variant.id);
                obj.verb = current ? Translation.tr("Current") : Translation.tr("Apply");
                return obj;
            });
        }

        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => root.appResultFor(entry));
        ////////////////// Settings search //////////////////
        const settingsQuery = root.query.toLowerCase().trim();
        const settingsResults = settingsQuery === "" ? [] : root.settingsIndex.reduce((acc, page) => {
            const dynamicKeywords = (root.settingsKeywordsCache[page.page] || "").toLowerCase();
            if (page.page.toLowerCase().includes(settingsQuery) || dynamicKeywords.includes(settingsQuery)) {
                const obj = root.cachedResult("settings", page.page, {
                    name: page.page,
                    verb: Translation.tr("Go"),
                    type: Translation.tr("Settings"),
                    iconName: "settings",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        const query = root.query.toLowerCase().trim();
                        GlobalStates.settingsOpen = true;
                        Qt.callLater(() => {
                            GlobalStates.settingsPage = page.page + ":" + query;
                        });
                        root.query = "";
                    }
                });
                obj.comment = dynamicKeywords.includes(settingsQuery) ? "Section: " + settingsQuery : "Settings for " + page.page;
                acc.push(obj);
            }
            return acc;
        }, []);
        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (actionString.startsWith(root.query) || root.query.startsWith(actionString)) {
                const obj = root.cachedResult("action", actionString, {
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material
                });
                obj.name = root.query.startsWith(actionString) ? root.query : actionString;
                // User action scripts are reloaded with the folder: run the current one.
                obj.execute = () => {
                    action.execute(root.query.split(" ").slice(1).join(" "));
                };
                return obj;
            }
            return null;
        }).filter(Boolean);

        //////// Prioritized by prefix /////////
        let result = [];
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        ///////////// Shell tools //////////////
        const toolQuery = root.query.toLowerCase().trim();
        result = result.concat(toolQuery.length < 2 ? [] : root.shellTools
            .filter(tool => tool.keywords.some(k => k.startsWith(toolQuery) || toolQuery.startsWith(k + " ")))
            .map(tool => root.cachedResult("shellTool", tool.id, {
                name: tool.name,
                verb: Translation.tr("Open"),
                type: Translation.tr("Shell"),
                comment: tool.comment,
                iconName: tool.icon,
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => Qt.callLater(tool.open),
            })));
        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);
        ////////////// Settings ////////////////
        result = result.concat(settingsResults);
        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix && root.looksLikeMath(root.query))
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
        }
        
        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
