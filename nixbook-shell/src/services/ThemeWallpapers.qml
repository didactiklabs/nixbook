pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wallpapers per theme variant (appearance.wallpaperPerTheme): each theme
 * (and variant) remembers its desktop, lock screen and login screen
 * wallpapers, and switching to it puts them back.
 *
 *   appearance.themeWallpapers        desktop  (background.wallpaperPath)
 *   appearance.themeLockWallpapers    lock     (background.lockWall)
 *   appearance.themeLoginWallpapers   login    (background.greeterWall)
 *
 * each a list of "<theme>/<variant>=<path>" (or "<theme>=<path>") entries.
 *
 * - leaving a variant remembers the wallpapers it had;
 * - picking a wallpaper while in a variant makes it that variant's;
 * - entering a variant: its desktop wallpaper, else the variant's default
 *   from themes.json (`wallpaper`, copied out of the store first so the
 *   setting never points at a path a garbage collection removes), else the
 *   current one stays; its lock and login wallpapers, else none: the lock
 *   screen then uses the desktop wallpaper and the login screen the lock
 *   screen's, so both follow the variant;
 * - unset (Settings → Appearance → Theme): the desktop back to the variant's
 *   default, the lock screen to the desktop's, the login screen to the lock
 *   screen's.
 *
 * A list set in Nix is only read (nothing learnt from the menu), and a
 * lock/login wallpaper set in Nix is never changed.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.appearance?.wallpaperPerTheme ?? true
    readonly property string key: Themes.current + (Themes.variant ? `/${Themes.variant}` : "")
    readonly property string copiesDir: `${FileUtils.trimFileProtocol(Directories.state)}/user/theme-wallpapers`

    // The three slots: their per-variant list and the setting they drive.
    readonly property var slots: ({
        "main": { list: "themeWallpapers", setting: "wallpaperPath" },
        "lock": { list: "themeLockWallpapers", setting: "lockWall" },
        "login": { list: "themeLoginWallpapers", setting: "greeterWall" }
    })

    function parse(entries) {
        const out = {};
        for (const e of entries ?? []) {
            const s = String(e);
            const i = s.indexOf("=");
            if (i > 0 && i < s.length - 1) out[s.slice(0, i)] = s.slice(i + 1);
        }
        return out;
    }
    readonly property var map: root.parse(Config.options?.appearance?.themeWallpapers)
    readonly property var lockMap: root.parse(Config.options?.appearance?.themeLockWallpapers)
    readonly property var loginMap: root.parse(Config.options?.appearance?.themeLoginWallpapers)
    function mapOf(slot) {
        return slot === "lock" ? root.lockMap : slot === "login" ? root.loginMap : root.map;
    }
    function listPinned(slot) {
        return NixManaged.isPinned(`appearance.${root.slots[slot].list}`);
    }
    function settingPinned(slot) {
        return NixManaged.isPinned(`background.${root.slots[slot].setting}`);
    }
    // For the Settings row (the desktop list).
    readonly property bool pinned: root.listPinned("main")

    function store(slot, map) {
        Config.options.appearance[root.slots[slot].list] = Object.keys(map).sort().map(k => `${k}=${map[k]}`);
        Config.save();
    }
    // `path` "" forgets the entry.
    function remember(slot, key, path) {
        if (root.listPinned(slot) || !key)
            return;
        const current = root.mapOf(slot);
        if ((current[key] ?? "") === (path ?? ""))
            return;
        const next = Object.assign({}, current);
        if (path)
            next[key] = path;
        else
            delete next[key];
        root.store(slot, next);
    }

    readonly property string wallpaper: Config.options?.background?.wallpaperPath ?? ""
    readonly property string lockWall: Config.options?.background?.lockWall ?? ""
    readonly property string greeterWall: Config.options?.background?.greeterWall ?? ""

    // The key the current wallpapers belong to ("" until the config is read).
    property string _lastKey: ""
    // The variant changed, switchTo() not run yet.
    property bool _switchPending: false
    // The key whose desktop wallpaper is showing: "" while a switch's is on
    // its way (switchwall.sh takes a moment), so leaving a variant before its
    // wallpaper arrived doesn't hand it the previous variant's.
    property string _wallKey: ""
    // A desktop wallpaper we are applying: not "picked" by the user.
    property string _applying: ""
    // Lock/login wallpapers being put back by a switch: not "picked" either.
    property bool _switching: false

    function load() {}

    // What entering `key` shows on the desktop: remembered, else the
    // variant's default.
    function wallpaperFor(key) {
        const remembered = root.map?.[key] ?? "";
        if (remembered !== "")
            return { path: remembered, bundled: false };
        const [themeId, variantId] = key.split("/");
        const variant = Themes.variantsOf(themeId).find(v => v.id === variantId);
        const bundled = variant?.wallpaper ?? Themes.theme(themeId)?.wallpaper ?? "";
        return bundled !== "" ? { path: bundled, bundled: true } : null;
    }

    // Settings buttons, for the current variant: the desktop "use the current
    // one" / reset to its default (path ""); the lock and login screens
    // unset (they follow the desktop / the lock screen again).
    function setForCurrent(path) {
        root.remember("main", root.key, path ?? "");
        // Unset: the variant's own default right away (none: stays).
        if (!path)
            root.applyFor(root.key);
    }
    // Settings table: `slot` ("main", "lock", "login") of `key` set to `path`
    // ("" unsets it); applied right away when `key` is the current variant.
    function setFor(slot, key, path) {
        root.remember(slot, key, path ?? "");
        if (key !== root.key)
            return;
        if (slot === "main") {
            if (path)
                root.apply(path);
            else
                root.applyFor(key);
        } else if (!root.settingPinned(slot)) {
            root.setSetting(slot, path ?? "");
        }
    }
    // Every key of the table: "<theme>" or "<theme>/<variant>".
    readonly property var allKeys: {
        const out = [];
        for (const t of Themes.list) {
            if ((t.variants ?? []).length === 0)
                out.push({ key: t.id, name: t.name, icon: t.icon });
            else
                for (const v of t.variants)
                    out.push({ key: `${t.id}/${v.id}`, name: v.name, icon: v.icon });
        }
        return out;
    }

    function unsetLock() {
        root.remember("lock", root.key, "");
        if (!root.settingPinned("lock"))
            root.setSetting("lock", "");
    }
    function unsetLogin() {
        root.remember("login", root.key, "");
        if (!root.settingPinned("login"))
            root.setSetting("login", "");
    }
    function setSetting(slot, value) {
        root._switching = true;
        Config.options.background[root.slots[slot].setting] = value;
        root._switching = false;
    }

    // Applied a moment later: switchwall.sh rewrites config.json from what
    // it read when it started, so the remembered wallpapers must be saved
    // (Config's 50 ms write delay) before it runs. One run at a time, the
    // latest wallpaper queued behind it: switching variants quickly would
    // otherwise race runs that land in any order. `src`: a bundled
    // wallpaper, copied to `path` first.
    function apply(path, src = "") {
        if (!path)
            return;
        if (!root._busy && path === root.wallpaper) {
            root._settle();
            return;
        }
        root._applying = path;
        root._wallKey = "";
        settleTimer.stop();
        applyTimer.job = { path: path, src: src };
        applyTimer.restart();
    }
    readonly property bool _busy: applyTimer.running || switchProc.running
    Timer {
        id: applyTimer
        property var job: null
        interval: 300
        onTriggered: root._run()
    }
    function _run() {
        const job = applyTimer.job;
        if (!job || switchProc.running)
            return; // run once the current one is done
        applyTimer.job = null;
        const cmd = Wallpapers.switchCommand(job.path);
        switchProc.command = job.src === "" ? cmd
            : ["bash", "-c", 'mkdir -p "$(dirname "$2")" && cp -f "$1" "$2" && chmod u+w "$2" && shift 2 && exec "$@"', "_", job.src, job.path, ...cmd];
        switchProc.running = true;
        Wallpapers.confirmedPath = job.path;
        Wallpapers.changed();
    }
    Process {
        id: switchProc
        onExited: code => {
            if (code !== 0)
                console.warn("[ThemeWallpapers] could not apply", root._applying);
            if (applyTimer.running)
                return;
            if (applyTimer.job) {
                root._run();
                return;
            }
            // Done: settled once config.json is read back (not at all when
            // switchwall.sh swapped in a -dark/-light file or failed).
            if (root.wallpaper === root._applying)
                root._settle();
            else
                settleTimer.restart();
        }
    }
    Timer {
        id: settleTimer
        interval: 2000
        onTriggered: root._settle()
    }
    // Whatever the desktop shows now is the current variant's (the one
    // applied, or one picked while it was on its way).
    function _settle() {
        if (root._switchPending)
            return; // switchTo() decides
        settleTimer.stop();
        root._applying = "";
        root._wallKey = root.key;
        root.remember("main", root.key, root.wallpaper);
    }

    function switchTo(fromKey, toKey) {
        // Remember what the variant we leave had (lock/login "" = following;
        // the desktop only once its wallpaper arrived).
        if (root._wallKey === fromKey)
            root.remember("main", fromKey, root.wallpaper);
        root.remember("lock", fromKey, root.lockWall);
        root.remember("login", fromKey, root.greeterWall);

        // The lock and login screens of the variant we enter (none: follow).
        for (const slot of ["lock", "login"]) {
            if (root.settingPinned(slot))
                continue;
            const target = root.mapOf(slot)[toKey] ?? "";
            if ((Config.options.background[root.slots[slot].setting] ?? "") !== target)
                root.setSetting(slot, target);
        }

        // No wallpaper of its own: whatever is showing (or on its way) stays.
        root._switchPending = false;
        if (!root._busy) {
            settleTimer.stop();
            root._applying = "";
            root._wallKey = toKey;
        }
        root.applyFor(toKey);
    }

    // The desktop wallpaper of `toKey` (remembered, else its default: copied
    // next to the state first).
    function applyFor(toKey) {
        const target = root.wallpaperFor(toKey);
        if (!target)
            return;
        if (!target.bundled) {
            root.apply(target.path);
            return;
        }
        const dst = `${root.copiesDir}/${toKey.replace("/", "-")}${target.path.slice(target.path.lastIndexOf("."))}`;
        root.apply(dst, Quickshell.shellPath(target.path));
    }

    onKeyChanged: {
        if (!Config.ready || !root.enabled)
            return;
        if (root._lastKey === "" || root._lastKey === root.key) {
            root._lastKey = root._wallKey = root.key;
            return;
        }
        const from = root._lastKey;
        root._lastKey = root.key;
        // Once the settings have settled: when config.json is reloaded (an
        // edit, a Home Manager activation) the variant can change before the
        // file's other values are read back.
        const to = root.key;
        root._switchPending = true;
        Qt.callLater(() => root.switchTo(from, to));
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root._lastKey === "")
                root._lastKey = root._wallKey = root.key;
        }
    }
    Component.onCompleted: if (Config.ready) root._lastKey = root._wallKey = root.key

    // Wallpapers picked while in a variant become that variant's.
    onWallpaperChanged: {
        if (!Config.ready || !root.enabled || root.wallpaper === "")
            return;
        if (root._applying !== "") {
            if (!root._busy && root.wallpaper === root._applying)
                root._settle();
            return;
        }
        root.remember("main", root.key, root.wallpaper);
    }
    // Learnt once the settings have settled (not mid-reload, not while a
    // switch is putting a variant's wallpapers back).
    onLockWallChanged: {
        if (Config.ready && root.enabled && !root._switching) {
            const key = root.key;
            Qt.callLater(() => { if (root.key === key) root.remember("lock", key, root.lockWall); });
        }
    }
    onGreeterWallChanged: {
        if (Config.ready && root.enabled && !root._switching) {
            const key = root.key;
            Qt.callLater(() => { if (root.key === key) root.remember("login", key, root.greeterWall); });
        }
    }
}
