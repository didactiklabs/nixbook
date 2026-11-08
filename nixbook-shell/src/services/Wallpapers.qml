import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
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
    property string _playTarget: ""
    property bool _started: false
    function syncPlayback() {
        if (!root._started) return; // the first look is ensureVideoWallpaper()
        const path = root.configuredPath;
        if (root.isVideo(path)) {
            if (path === root.playingPath && !playDelay.running) return;
            root._playTarget = path;
            playDelay.restart();
        } else {
            root._playTarget = "";
            playDelay.stop();
            if (root.playingPath !== "" || restackWait.running) {
                // Background drops the video at once and shows the old still
                // frame then the new image over it: stop it a moment later.
                root.playingPath = "";
                restackWait.running = false;
                stopDelay.restart();
            }
        }
    }
    // Played once the transition to its still frame is over: the video
    // starts on that frame, so the picture just comes alive. Until then the
    // previous video keeps playing under the transition.
    Timer {
        id: playDelay
        interval: 200
        onTriggered: {
            if (GlobalStates.wallpaperTransitionsBusy > 0 && playWaited.elapsed < 4000) {
                playWaited.elapsed += interval;
                playDelay.restart();
                return;
            }
            playWaited.elapsed = 0;
            if (root._playTarget === "" || root._playTarget !== root.configuredPath) return;
            root.playingPath = "";
            Quickshell.execDetached([root.liveScript, "play", root._playTarget]);
            root.restackOverVideo(root._playTarget);
        }
    }
    QtObject { id: playWaited; property int elapsed: 0 }
    Timer {
        id: stopDelay
        interval: 600
        onTriggered: {
            if (!root.isVideo(root.configuredPath))
                Quickshell.execDetached([root.liveScript, "stop"]);
        }
    }
    property bool videoChecked: false
    function ensureVideoWallpaper() {
        if (root.videoChecked || !Config.ready) return;
        root.videoChecked = true;
        root._started = true;
        const path = root.configuredPath;
        if (!root.isVideo(path)) {
            // One left over from before a restart (it lives in the service).
            Quickshell.execDetached([root.liveScript, "stop"]);
            return;
        }
        Quickshell.execDetached([root.liveScript, "ensure", path]);
        root.restackOverVideo(path);
    }
    // Under niri the video is on the Bottom layer, like the desktop widgets
    // (Background.qml), and a surface mapped later stacks on top: once every
    // output has its mpvpaper surface, re-map the desktop layer above it,
    // then let Background show the video.
    function restackOverVideo(path) {
        restackWait.running = false;
        restackWait.video = path;
        restackWait.running = true;
    }
    Process {
        id: restackWait
        property string video: ""
        command: ["bash", "-c", 'sleep 0.3; for _ in $(seq 60); do '
            + 'n=$(niri msg --json layers | jq \'[.[] | select(.namespace == "mpvpaper" and .layer == "Bottom")] | length\'); '
            + '[ "$n" -ge "$(niri msg --json outputs | jq \'[.[] | select(.current_mode != null)] | length\')" ] && exit 0; sleep 0.25; done; exit 1']
        onExited: (code) => {
            if (code !== 0 || restackWait.video !== root.configuredPath) return;
            GlobalStates.backgroundRestack += 1;
            root.playingPath = restackWait.video;
        }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.ensureVideoWallpaper() }
    }
    Component.onCompleted: root.ensureVideoWallpaper()

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

    // The selector on the live wallpaper folder (Settings → Background →
    // Live Wallpaper Folder; else where it was), or the system file dialog
    // when the selector is set to use it.
    readonly property string liveFolder: FileUtils.expandHome((Config.options.wallpaperSelector?.liveWallpapersPath ?? "").trim())
    function openLiveWallpapers() {
        if (Config.options.wallpaperSelector.useSystemFileDialog) {
            root.openFallbackPicker(Appearance.m3colors.darkmode, root.liveFolder);
            return;
        }
        if (root.liveFolder.length > 0) root.setDirectory(root.liveFolder);
        GlobalStates.wallpaperSelectorTarget = "wallpaper";
        GlobalStates.wallpaperSelectorOpen = true;
    }

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

        function openLive(): void {
            root.openLiveWallpapers();
        }

        function setSortMode(mode: string): void {
            root.setSortMode(mode);
        }

        function moveWallpaper(fromIndex: int, toIndex: int): void {
            root.moveWallpaper(fromIndex, toIndex);
        }
    }
}