import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property string thumbgenScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/thumbgen-venv.sh`
    property string generateThumbnailsMagickScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-thumbnails-magick.sh`
    function getCleanDirPath(path) {
        if (!path) return "";
        return FileUtils.trimFileProtocol(path.toString()).replace(/\/+$/, "");
    }

    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: getCleanDirPath(folderModel.folder)
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property alias wallpaperModel: wallpaperModel
    property string sortMode: Config.options.wallpaperSelector?.sortMode || "custom"
    onSortModeChanged: debounceRebuildTimer.restart()
    property var orderMap: ({})
    property bool orderLoaded: false
    property string searchQuery: ""
    // Images and videos (live wallpapers) are listed side by side.
    readonly property list<string> videoExtensions: ["mp4", "webm", "mkv", "avi", "mov"]
    readonly property list<string> extensions: [
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg"
    ].concat(root.videoExtensions)
    property list<string> wallpapers: [] // List of absolute file paths (without file://)
    property bool thumbnailGenerationActive: false
    property bool thumbnailGenerationPending: false
    property string pendingThumbnailSize: ""
    property string pendingThumbnailDirectory: ""
    readonly property bool thumbnailGenerationRunning: thumbgenProc.running || root.thumbnailGenerationActive
    property real thumbnailGenerationProgress: 0
    property string previewPath: ""  // Set during arrow navigation; empty by default
    property string confirmedPath: ""  // Holds confirmed path until config catches up

    signal changed()
    signal thumbnailGenerated(directory: string)
    signal thumbnailGeneratedFile(filePath: string)

    function load () {} // For forcing initialization

    // The config is the truth once it changes: the wallpaper was applied (or
    // set from elsewhere — the desktop menu's file picker runs switchwall.sh
    // directly, which used to be hidden behind a stale confirmedPath).
    readonly property string configuredPath: Config.options?.background?.wallpaperPath ?? ""
    onConfiguredPathChanged: {
        root.confirmedPath = "";
        root.syncPlayback();
    }

    // Live (video) wallpapers. A video is shown like an image — its still
    // frame (its first frame, `live-wallpaper.sh poster`) in the transition,
    // the preview, the blur and the colours — and played over it once the
    // transition is over (Background.qml shows the video only while
    // `playingPath` is the wallpaper it shows). mpvpaper runs in the shell's
    // service, so a restart or a new login leaves none: started again here.
    function isVideo(path) {
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path ?? "");
    }
    readonly property string liveScript: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/live-wallpaper.sh`
    // Video path → its still frame, once known.
    property var posters: ({})
    function posterFor(path) {
        const clean = FileUtils.trimFileProtocol(path ?? "");
        if (!root.isVideo(clean)) return clean;
        if (root.posters[clean]) return root.posters[clean];
        // The configured video's frame, recorded with it by switchwall.sh.
        if (clean === root.configuredPath) return Config.options.background.thumbnailPath;
        // Any other (a lock-screen video): made now, shown once it is there.
        if (!root._posterAsked[clean]) {
            root._posterAsked[clean] = true;
            Qt.callLater(() => root.withPoster(clean, () => {}));
        }
        return "";
    }
    property var _posterAsked: ({})
    function rememberPoster(video, poster) {
        const next = Object.assign({}, root.posters);
        next[video] = poster;
        root.posters = next;
    }
    // Makes (or finds) a video's still frame, then calls back; the newest
    // request wins (hovering through a folder of videos).
    Process {
        id: posterProc
        property string video: ""
        property var callbacks: []
        stdout: StdioCollector {
            onStreamFinished: {
                const poster = text.trim();
                const video = posterProc.video;
                // A run replaced by a newer request can still end here: its
                // file (named after the video's path) tells them apart.
                if (!poster.endsWith(`/${Qt.md5(video)}.jpg`)) return;
                const callbacks = posterProc.callbacks;
                posterProc.callbacks = [];
                root.rememberPoster(video, poster);
                for (const cb of callbacks) cb(poster);
            }
        }
    }
    function withPoster(video, callback) {
        const clean = FileUtils.trimFileProtocol(video);
        if (root.posters[clean]) { callback(root.posters[clean]); return; }
        if (posterProc.running && posterProc.video === clean) {
            posterProc.callbacks = posterProc.callbacks.concat([callback]);
            return;
        }
        posterProc.running = false;
        posterProc.video = clean;
        posterProc.callbacks = [callback];
        posterProc.exec([root.liveScript, "poster", clean]);
    }

    // The video mpvpaper plays and the shell has re-stacked its desktop
    // layer over ("" = none).
    property string playingPath: ""
    property bool _started: false
    function syncPlayback() {
        if (!root._started) return; // the first look is ensureVideoWallpaper()
        const path = root.configuredPath;
        if (root.isVideo(path)) {
            if (path === root.playingPath && !liveProc.running) return;
            // At once, under the transition to its still frame (Background
            // draws it over the players): the players switch to it paused on
            // that frame, and it is resumed once the transition is over (see
            // `shows` below), so the picture just comes alive. A switch inside
            // the running players is instant; the copies were prepared ahead.
            stopDelay.stop();
            root.playingPath = "";
            root.liveRun("play", path);
            root.prepareLibrary(30000); // a video new to the folders
        } else if (root.playingPath !== "" || liveProc.running || root._livePending !== null) {
            // Background drops the video at once and shows the old still
            // frame then the new image over it: stop it a moment later.
            root.playingPath = "";
            stopDelay.restart();
        }
    }
    Timer {
        id: stopDelay
        interval: 600
        onTriggered: {
            if (!root.isVideo(root.configuredPath))
                root.liveRun("stop", "");
        }
    }
    property bool videoChecked: false
    function ensureVideoWallpaper() {
        if (root.videoChecked || !Config.ready) return;
        root.videoChecked = true;
        root._started = true;
        const path = root.configuredPath;
        // A video: started unless already playing. Else one left over from
        // before a restart (it lives in the service) goes.
        root.liveRun(root.isVideo(path) ? "ensure" : "stop", root.isVideo(path) ? path : "");
        root.prepareLibrary(90000);
    }
    // live-wallpaper.sh play/ensure/stop, one at a time: a newer request
    // waits for the one running to be stopped (they would fight over the
    // players). `play` returns once the new players are on screen; under
    // niri they are on the Bottom layer, like the desktop widgets
    // (Background.qml), and a surface mapped later stacks on top, so the
    // desktop layer is re-mapped above them then, and Background shows the
    // video. (Polling niri for "a player surface" from here instead raced the
    // old player's surface: the widgets were lifted before the new one came
    // and ended up under it.)
    property var _livePending: null
    function liveRun(cmd, video) {
        const run = { cmd: cmd, video: video };
        if (liveProc.running) {
            root._livePending = run;
            liveProc.running = false;
            return;
        }
        root.liveStart(run);
    }
    function liveStart(run) {
        root._livePending = null;
        liveProc.run = run;
        liveProc.exec(run.video ? [root.liveScript, run.cmd, run.video] : [root.liveScript, run.cmd]);
    }
    Process {
        id: liveProc
        property var run: null
        onExited: (code) => {
            if (root._livePending !== null) {
                const next = root._livePending;
                Qt.callLater(() => root.liveStart(next));
                return;
            }
            const run = liveProc.run;
            if (!run || !run.video || run.video !== root.configuredPath) return;
            // 0: new players started and shown (lift the widgets above them);
            // 11: switched inside the running players; 10: (ensure) already
            // playing.
            if (code === 0) {
                GlobalStates.backgroundRestack += 1;
                root.playerGeneration += 1; // new players: tell them to play
            }
            if (code === 0 || code === 10 || code === 11) root.playingPath = run.video;
        }
    }
    // New players started (they start paused): the pause state is sent again.
    property int playerGeneration: 0
    // A player that ended on its own (it happened once, nothing logged; its
    // messages now go to $XDG_RUNTIME_DIR/nixbook-shell/live-wallpaper-<output>.log)
    // is started again: `ensure` is a cheap check while it runs.
    Timer {
        interval: 30000
        repeat: true
        running: root._started && root.isVideo(root.configuredPath) && !Idle.screensOff
        onTriggered: {
            if (!liveProc.running && root._livePending === null)
                root.liveRun("ensure", root.configuredPath);
        }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.ensureVideoWallpaper() }
    }
    Component.onCompleted: root.ensureVideoWallpaper()

    // The library, prepared ahead of time (live-wallpaper.sh prepare, in a
    // systemd unit of its own, idle priority): every video of the wallpaper
    // folders gets its still frame and, on AC power, its copy for each
    // screen size, sharp and at 60 fps. Never while switching: a switch only
    // picks the copy (or the video, not prepared yet). Started a while after
    // the shell, when AC power comes back, when screens change and after a
    // video is applied (one new to the folders); one run at a time, and it
    // skips what is done.
    function prepareLibrary(delay) {
        if (!root._started) return;
        if (prepareTimer.running && prepareTimer.interval <= delay) return;
        prepareTimer.interval = delay;
        prepareTimer.restart();
    }
    Timer {
        id: prepareTimer
        onTriggered: {
            if (Battery.runningOnBattery) return; // the script only checks the charger is plugged in
            const folders = [FileUtils.trimFileProtocol(root.defaultFolder.toString())];
            if (root.liveFolder.length > 0) folders.push(root.liveFolder);
            const current = root.isVideo(root.configuredPath) ? root.configuredPath : "-";
            if (current !== "-") folders.push(FileUtils.parentDirectory(current));
            Quickshell.execDetached([root.liveScript, "prepare-start", current].concat(folders));
        }
    }
    // Unplugged, or on a charger that can't keep up (the battery emptying
    // while "charging": the conversion ran 1.5 h of CPU on a weak charger and
    // drained it from 45 % to 0): the conversion stops at once (systemd stops
    // its whole unit, every ffmpeg of it) instead of finishing a video; it
    // resumes, skipping what is done, once on proper power again.
    Connections {
        target: Battery
        function onRunningOnBatteryChanged() {
            if (!Battery.runningOnBattery) {
                root.prepareLibrary(5000);
            } else {
                prepareTimer.stop();
                Quickshell.execDetached(["systemctl", "--user", "stop", "nixbook-live-wallpapers-prepare"]);
            }
        }
    }
    // Saving power — the power-saver profile, a low battery, or a charger
    // that can't keep up — the video pauses (the picture stays as it is;
    // nothing is decoded or drawn).
    readonly property bool savingPower: PowerProfiles.profile === PowerProfile.PowerSaver
        || Battery.isLowAndNotCharging || Battery.chargerTooWeak
    Connections {
        target: Quickshell
        function onScreensChanged() { root.prepareLibrary(30000) }
    }

    // Whether nothing of an output's desktop can be seen: the tiled columns
    // of its active workspace span its width (the gaps between them aside),
    // or a floating (or fullscreen) window covers most of it. Windows show
    // the video's blurred still frame (NiriBackdrop), never the video itself.
    function desktopCovered(screen) {
        const niri = WM.backend;
        if (!niri || !screen) return false;
        niri.tiledLayoutRevision; // a column resized (sizes updated in place)
        niri.floatingLayoutRevision;
        const ws = niri.activeWorkspaceForMonitor(screen.name);
        if (!ws) return false;
        const columns = {};
        for (const w of niri.windowList) {
            if (w.workspaceId !== ws.id) continue;
            const width = w.tileWidth || w.width;
            if (w.floating) {
                if (width * (w.tileHeight || w.height) >= 0.9 * screen.width * screen.height) return true;
                continue;
            }
            columns[w.column ?? 0] = Math.max(columns[w.column ?? 0] ?? 0, width);
        }
        let span = 0;
        for (const c in columns) span += columns[c];
        return span >= 0.9 * screen.width;
    }
    // Each output's video plays only while its desktop can be seen and no
    // power is being saved: paused behind windows, while locked, with the
    // screens off and in power-saver mode or on a low battery (mpvpaper's own
    // -p only sees a surface that isn't drawn at all; under translucent
    // windows it always is). Measured: mpvpaper's GPU time ~0 instead of
    // ~13-55%, niri's 33% → 11%.
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: output
            required property var modelData
            // (Not during a wallpaper transition: the new video waits on its
            // first frame, which the transition ends on.)
            readonly property bool shows: root.playingPath !== "" && !GlobalStates.screenLocked
                && GlobalStates.wallpaperTransitionsBusy === 0 && !root.savingPower
                && !Idle.screensOff && !root.desktopCovered(output.modelData)
            // Sent again for a new player (it starts playing).
            readonly property string want: root.playingPath === "" ? "" : `${root.playingPath}|${output.shows}|${root.playerGeneration}`
            onWantChanged: if (output.want !== "") sendPause.restart()
            // Settled first: a workspace switch or a window opening goes
            // through several layouts.
            Timer {
                id: sendPause
                interval: 150
                onTriggered: {
                    if (root.playingPath === "") return;
                    Quickshell.execDetached([root.liveScript, "pause", output.modelData.name, output.shows ? "no" : "yes"]);
                }
            }
        }
    }

    // Previewing a video shows its still frame (made first, if needed).
    property string _previewWanted: ""
    function startPreview(path) {
        if (!path || path.length === 0) return;
        root._previewWanted = path;
        if (!root.isVideo(path)) {
            root.previewPath = path;
            return;
        }
        root.withPoster(path, () => {
            if (root._previewWanted === path) root.previewPath = path;
        });
    }

    function stopPreview() {
        root._previewWanted = "";
        root.previewPath = "";
    }

    // Executions
    Process {
        id: applyProc
    }
    
    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode, startDir = "") {
        const args = [Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light"];
        if (startDir !== "") {
            args.push("--start-dir", startDir);
        }
        Quickshell.execDetached(args);
    }

    // The selector's Live quick folder (Settings → Background → Live
    // Wallpaper Folder), like its Custom one.
    readonly property string liveFolder: FileUtils.expandHome((Config.options.wallpaperSelector?.liveWallpapersPath ?? "").trim())

    function switchCommand(path, darkMode = Appearance.m3colors.darkmode) {
        return [Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light", "--image", path];
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode) {
        if (!path || path.length === 0) return;
        if (root.isVideo(path) && !root.posters[FileUtils.trimFileProtocol(path)]) {
            // Its still frame first, so the transition goes to it at once.
            root.withPoster(path, () => root.apply(path, darkMode));
            return;
        }
        root.confirmedPath = path;
        Quickshell.execDetached(root.switchCommand(path, darkMode));
        root.changed()
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        property var onFileSelected: null
        function select(filePath, darkMode = Appearance.m3colors.darkmode, onFileSelected = null) {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.onFileSelected = onFileSelected
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            if (selectProc.onFileSelected) {
                selectProc.onFileSelected(selectProc.filePath);
            } else {
                root.apply(selectProc.filePath, selectProc.darkMode);
            }
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode, onFileSelected = null) {
        selectProc.select(filePath, darkMode, onFileSelected);
    }

    function randomFromCurrentFolder(darkMode = Appearance.m3colors.darkmode) {
        const count = wallpaperModel.count > 0 ? wallpaperModel.count : folderModel.count;
        if (count === 0) return;
        const randomIndex = Math.floor(Math.random() * count);
        const item = wallpaperModel.count > 0 ? wallpaperModel.get(randomIndex) : null;
        const filePath = item ? item.filePath : folderModel.get(randomIndex, "filePath");
        print("Randomly selected wallpaper:", filePath);
        if (filePath) root.select(filePath, darkMode);
    }

    function getRandomWallpaperPath(excludePath = "") {
        const count = wallpaperModel.count > 0 ? wallpaperModel.count : folderModel.count;
        if (count === 0) return "";
        const excludeClean = FileUtils.trimFileProtocol(excludePath);
        const candidates = [];
        for (let i = 0; i < count; i++) {
            const item = wallpaperModel.count > 0 ? wallpaperModel.get(i) : null;
            const path = item ? item.filePath : (folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL")));
            if (path && path.length && FileUtils.trimFileProtocol(path) !== excludeClean) {
                candidates.push(path);
            }
        }
        if (candidates.length === 0) return "";
        return candidates[Math.floor(Math.random() * candidates.length)];
    }

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            // The path is an argument, never part of the script (folder names
            // can hold quotes, `$(` or backticks).
            validateDirProc.exec([
                "bash", "-c",
                'if [ -d "$1" ]; then echo dir; elif [ -f "$1" ]; then echo file; else echo invalid; fi',
                "_", validateDirProc.nicePath
            ])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim()
                if (result === "dir") {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // Ignore
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    // A folder to go back to (the selector's back button).
    readonly property bool canNavigateBack: folderModel.currentFolderHistoryIndex > 0
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        sortReversed: false
        onCountChanged: debounceRebuildTimer.restart()
        onStatusChanged: {
            if (status === FolderListModel.Ready) debounceRebuildTimer.restart();
        }
    }

    onEffectiveDirectoryChanged: debounceRebuildTimer.restart()
    onSearchQueryChanged: debounceRebuildTimer.restart()

    ListModel {
        id: wallpaperModel
    }

    FileView {
        id: orderFileView
        path: `${Directories.shellConfig}/wallpaper_order.json`
        watchChanges: false
        onLoaded: {
            try {
                const txt = orderFileView.text();
                if (txt && txt.trim().length > 0) {
                    root.orderMap = JSON.parse(txt);
                } else {
                    root.orderMap = {};
                }
            } catch (e) {
                console.log("[Wallpapers] Error parsing wallpaper_order.json:", e);
                root.orderMap = {};
            }
            root.orderLoaded = true;
            debounceRebuildTimer.restart();
        }
        onLoadFailed: (error) => {
            root.orderMap = {};
            root.orderLoaded = true;
            debounceRebuildTimer.restart();
        }
    }

    Connections {
        target: Config.options.wallpaperSelector ?? null
        function onSortModeChanged() {
            if (Config.options.wallpaperSelector?.sortMode && root.sortMode !== Config.options.wallpaperSelector.sortMode) {
                root.sortMode = Config.options.wallpaperSelector.sortMode;
                debounceRebuildTimer.restart();
            }
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                if (Config.options.wallpaperSelector?.sortMode) {
                    root.sortMode = Config.options.wallpaperSelector.sortMode;
                }
                debounceRebuildTimer.restart();
            }
        }
    }

    function saveCustomOrder() {
        const jsonStr = JSON.stringify(root.orderMap, null, 2);
        if (orderFileView) {
            try {
                orderFileView.setText(jsonStr);
            } catch (e) {
                console.log("[Wallpapers] Failed to save wallpaper_order.json:", e);
            }
        }
        const filePath = `${Directories.shellConfig}/wallpaper_order.json`;
        // Path and JSON (wallpaper file names) go in as arguments: in the
        // script, a quote in either broke it.
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf \'%s\\n\' "$2" > "$1.tmp" && mv "$1.tmp" "$1"',
            "_", filePath, jsonStr]);
    }

    function moveWallpaper(fromIndex, toIndex) {
        if (fromIndex < 0 || toIndex < 0 || fromIndex >= wallpaperModel.count || toIndex >= wallpaperModel.count || fromIndex === toIndex)
            return;

        wallpaperModel.move(fromIndex, toIndex, 1);
        root.sortMode = "custom";
        if (Config.options.wallpaperSelector) {
            Config.options.wallpaperSelector.sortMode = "custom";
        }
        Config.setNestedValue("wallpaperSelector.sortMode", "custom");

        const list = [];
        const paths = [];
        for (let i = 0; i < wallpaperModel.count; i++) {
            const it = wallpaperModel.get(i);
            list.push(it.fileName);
            if (it.filePath) paths.push(it.filePath);
        }
        const cleanDir = getCleanDirPath(folderModel.folder);
        root.orderMap[cleanDir] = list;
        root.wallpapers = paths;
        root.saveCustomOrder();
    }

    function moveToTop(index) {
        moveWallpaper(index, 0);
    }

    function moveToBottom(index) {
        moveWallpaper(index, wallpaperModel.count - 1);
    }

    function setSortMode(mode) {
        root.sortMode = mode;
        if (Config.options.wallpaperSelector) {
            Config.options.wallpaperSelector.sortMode = mode;
        }
        Config.setNestedValue("wallpaperSelector.sortMode", mode);
        rebuildWallpaperModel();
    }

    Timer {
        id: debounceRebuildTimer
        interval: 20
        repeat: false
        onTriggered: root.rebuildWallpaperModel()
    }

    function sortItems(items, mode, customList) {
        if (mode === "custom") {
            if (!customList || customList.length === 0) {
                return items.slice().sort((a, b) => {
                    if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                    return new Date(b.fileModified) - new Date(a.fileModified);
                });
            }
            const orderLookup = {};
            for (let i = 0; i < customList.length; i++) {
                orderLookup[customList[i]] = i;
            }
            const dirs = [];
            const orderedFiles = [];
            const remainingFiles = [];
            for (let i = 0; i < items.length; i++) {
                const it = items[i];
                if (it.fileIsDir) {
                    dirs.push(it);
                } else if (typeof orderLookup[it.fileName] !== "undefined") {
                    orderedFiles.push(it);
                } else {
                    remainingFiles.push(it);
                }
            }
            dirs.sort((a, b) => a.fileName.localeCompare(b.fileName, undefined, { numeric: true, sensitivity: "base" }));
            orderedFiles.sort((a, b) => orderLookup[a.fileName] - orderLookup[b.fileName]);
            remainingFiles.sort((a, b) => new Date(b.fileModified) - new Date(a.fileModified));
            return dirs.concat(orderedFiles, remainingFiles);
        } else if (mode === "name") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return a.fileName.localeCompare(b.fileName, undefined, { numeric: true, sensitivity: "base" });
            });
        } else if (mode === "name_rev") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return b.fileName.localeCompare(a.fileName, undefined, { numeric: true, sensitivity: "base" });
            });
        } else if (mode === "time") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return new Date(b.fileModified) - new Date(a.fileModified);
            });
        } else if (mode === "time_rev") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return new Date(a.fileModified) - new Date(b.fileModified);
            });
        } else if (mode === "size") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return (b.fileSize || 0) - (a.fileSize || 0);
            });
        } else if (mode === "size_rev") {
            return items.slice().sort((a, b) => {
                if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                return (a.fileSize || 0) - (b.fileSize || 0);
            });
        }
        return items;
    }

    function rebuildWallpaperModel() {
        const count = folderModel.count;
        if (count === 0) {
            wallpaperModel.clear();
            root.wallpapers = [];
            return;
        }

        const items = [];
        for (let i = 0; i < count; i++) {
            const fn = folderModel.get(i, "fileName") || "";
            const fp = folderModel.get(i, "filePath") || "";
            const fu = (fp && fp.length) ? ("file://" + fp) : (folderModel.get(i, "fileUrl") || "");
            const isDir = Boolean(folderModel.get(i, "fileIsDir"));
            const sz = folderModel.get(i, "fileSize") || 0;
            const mod = folderModel.get(i, "fileModified") ? folderModel.get(i, "fileModified").toString() : "";
            items.push({
                fileName: fn,
                filePath: fp,
                fileUrl: fu,
                fileURL: fu,
                fileIsDir: isDir,
                fileSize: sz,
                fileModified: mod
            });
        }

        const cleanDir = getCleanDirPath(folderModel.folder);
        const savedOrder = root.orderMap[cleanDir] || root.orderMap[cleanDir + "/"] || [];
        const effectiveMode = (root.sortMode === "custom" || (!root.sortMode && savedOrder.length > 0)) ? "custom" : root.sortMode;
        const sorted = sortItems(items, effectiveMode, savedOrder);

        wallpaperModel.clear();
        root._missingThumbTried = ({}); // re-listed: allow one more attempt
        const paths = [];
        for (let i = 0; i < sorted.length; i++) {
            wallpaperModel.append(sorted[i]);
            if (sorted[i].filePath && sorted[i].filePath.length) {
                paths.push(sorted[i].filePath);
            }
        }
        root.wallpapers = paths;
    }

    // Missing thumbnails: a grid item whose thumbnail fails to load reports it
    // here; reports are batched (400 ms) and the folder is regenerated once per
    // folder + size each time it is listed (thumbgen skips existing thumbnails,
    // and a file that can't be thumbnailed doesn't loop).
    property var _missingThumbTried: ({})
    property var _missingThumbPending: ({})
    function requestMissingThumbnail(size: string, filePath: string) {
        if (!filePath || !["normal", "large", "x-large", "xx-large"].includes(size)) return;
        const dir = FileUtils.parentDirectory(FileUtils.trimFileProtocol(filePath));
        const key = `${size}|${dir}`;
        if (root._missingThumbTried[key]) return;
        root._missingThumbTried[key] = true;
        root._missingThumbPending[key] = { size: size, dir: dir };
        missingThumbTimer.restart();
    }
    Timer {
        id: missingThumbTimer
        interval: 400
        onTriggered: {
            const pending = root._missingThumbPending;
            root._missingThumbPending = ({});
            for (const key in pending)
                root.generateThumbnail(pending[key].size, pending[key].dir);
        }
    }

    // Thumbnail generation
    function generateThumbnail(size: string, dir = root.directory) {
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        // thumbgenProc.running only flips once the process has actually spawned,
        // so an in-flight run has to be tracked synchronously here — otherwise a
        // second request would rewrite `command` mid-start.
        if (root.thumbnailGenerationActive) {
            // Never kill a run in flight: the shell script writes thumbnails as
            // it goes, so aborting only loses progress and fires thumbnailGenerated
            // against the directory of the run being replaced. Coalesce onto the
            // newest request instead and start it when the current run ends.
            root.pendingThumbnailSize = size;
            root.pendingThumbnailDirectory = dir;
            root.thumbnailGenerationPending = true;
            return;
        }
        root.thumbnailGenerationActive = true;
        startThumbgen(size, dir);
    }

    function startThumbgen(size, dir) {
        thumbgenProc.directory = dir
        thumbgenProc.command = [
            "bash", "-c",
            // Arguments, not interpolated: folders with spaces or quotes got no thumbnails.
            '"$1" --size "$3" --machine_progress -d "$4" || "$2" --size "$3" -d "$4"',
            "_", thumbgenScriptPath, generateThumbnailsMagickScriptPath, String(size), FileUtils.trimFileProtocol(dir),
        ]
        // console.log("[Wallpapers] Updating thumbnails with command ", thumbgenProc.command.join(" "))
        root.thumbnailGenerationProgress = 0
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        stdout: SplitParser {
            onRead: data => {
                // print("thumb gen proc:", data)
                let match = data.match(/PROGRESS (\d+)\/(\d+)/)
                if (match) {
                    const completed = parseInt(match[1])
                    const total = parseInt(match[2])
                    root.thumbnailGenerationProgress = completed / total
                }
                match = data.match(/FILE (.+)/)
                if (match) {
                    const filePath = match[1]
                    root.thumbnailGeneratedFile(filePath)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // print("[Wallpapers] Thumbnail generation completed with exit code", exitCode)
            root.thumbnailGenerated(thumbgenProc.directory)
            if (root.thumbnailGenerationPending) {
                const size = root.pendingThumbnailSize;
                const dir = root.pendingThumbnailDirectory;
                root.pendingThumbnailSize = "";
                root.pendingThumbnailDirectory = "";
                root.thumbnailGenerationPending = false;
                Qt.callLater(() => root.startThumbgen(size, dir));
            } else {
                root.thumbnailGenerationActive = false;
            }
        }
    }

    // Colour generation settings (scheme, Settings > Appearance > Color
    // generation) take effect live: any change regenerates the palette from
    // the current wallpaper, once the value has settled (spin boxes step).
    Timer {
        id: regenerateColorsTimer
        interval: 700
        onTriggered: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"])
    }
    function regenerateColors() {
        if (Config.ready)
            regenerateColorsTimer.restart();
    }
    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() { root.regenerateColors() }
    }
    Connections {
        target: Config.options.appearance.wallpaperTheming
        function onEnableAppsAndShellChanged() { root.regenerateColors() }
        function onEnableTerminalChanged() {
            // Turned off: hand the open terminals their own colours back
            // (new ones start with them anyway).
            if (Config.ready && !Config.options.appearance.wallpaperTheming.enableTerminal)
                Quickshell.execDetached([`${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/applycolor.sh`, "--reset-terminal"]);
            root.regenerateColors();
        }
    }
    Connections {
        target: Config.options.appearance.wallpaperTheming.terminalGenerationProps
        function onForceDarkModeChanged() { root.regenerateColors() }
        function onHarmonyChanged() { root.regenerateColors() }
        function onHarmonizeThresholdChanged() { root.regenerateColors() }
        function onTermFgBoostChanged() { root.regenerateColors() }
    }

    IpcHandler {
        target: "wallpapers"

        function apply(path: string): void {
            root.apply(path);
        }

        function setSortMode(mode: string): void {
            root.setSortMode(mode);
        }

        function moveWallpaper(fromIndex: int, toIndex: int): void {
            root.moveWallpaper(fromIndex, toIndex);
        }
    }
}