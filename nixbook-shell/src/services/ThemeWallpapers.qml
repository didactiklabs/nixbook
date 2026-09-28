pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A wallpaper per theme variant (appearance.wallpaperPerTheme): each theme
 * (and variant) remembers its wallpaper, and switching to it puts that
 * wallpaper back.
 *
 *   appearance.themeWallpapers   ["<theme>/<variant>=<path>" or "<theme>=<path>", …]
 *
 * - leaving a variant remembers the wallpaper it had;
 * - picking a wallpaper while in a variant makes it that variant's;
 * - entering a variant applies its wallpaper, else the variant's default
 *   from themes.json (`wallpaper`, copied out of the store first so the
 *   setting never points at a path a garbage collection removes), else
 *   leaves the wallpaper alone.
 *
 * Set in Nix, the map is only read (nothing is learnt from the menu).
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.appearance?.wallpaperPerTheme ?? true
    // appearance.themeWallpapers as { key: path }.
    readonly property var map: {
        const out = {};
        for (const e of Config.options?.appearance?.themeWallpapers ?? []) {
            const i = String(e).indexOf("=");
            if (i > 0 && i < String(e).length - 1) out[String(e).slice(0, i)] = String(e).slice(i + 1);
        }
        return out;
    }
    function store(map) {
        Config.options.appearance.themeWallpapers = Object.keys(map).sort().map(k => `${k}=${map[k]}`);
        Config.save();
    }
    readonly property bool pinned: NixManaged.isPinned("appearance.themeWallpapers")
    readonly property string key: Themes.current + (Themes.variant ? `/${Themes.variant}` : "")
    readonly property string wallpaper: Config.options?.background?.wallpaperPath ?? ""
    readonly property string copiesDir: `${FileUtils.trimFileProtocol(Directories.state)}/user/theme-wallpapers`

    // The key the current wallpaper belongs to ("" until the config is read).
    property string _lastKey: ""
    // A wallpaper we are applying: not "picked" by the user.
    property string _applying: ""

    function load() {}

    // What entering `key` shows: remembered, else the variant's default.
    function wallpaperFor(key) {
        const remembered = root.map?.[key] ?? "";
        if (remembered !== "")
            return { path: remembered, bundled: false };
        const [themeId, variantId] = key.split("/");
        const variant = Themes.variantsOf(themeId).find(v => v.id === variantId);
        const bundled = variant?.wallpaper ?? Themes.theme(themeId)?.wallpaper ?? "";
        return bundled !== "" ? { path: bundled, bundled: true } : null;
    }

    function remember(key, path) {
        if (root.pinned || !key || !path || root.map?.[key] === path)
            return;
        const next = Object.assign({}, root.map);
        next[key] = path;
        root.store(next);
    }

    // This variant's wallpaper: the current one (Settings button), or
    // back to its default (empty).
    function setForCurrent(path) {
        if (root.pinned)
            return;
        const next = Object.assign({}, root.map);
        if (path)
            next[root.key] = path;
        else
            delete next[root.key];
        root.store(next);
    }

    // Applied a moment later: switchwall.sh rewrites config.json from what
    // it read when it started, so the remembered wallpapers must be saved
    // (Config's 50 ms write delay) before it runs.
    function apply(path) {
        if (!path || path === root.wallpaper)
            return;
        root._applying = path;
        applyTimer.path = path;
        applyTimer.restart();
    }
    Timer {
        id: applyTimer
        property string path: ""
        interval: 300
        onTriggered: Wallpapers.apply(applyTimer.path)
    }

    function switchTo(fromKey, toKey) {
        root.remember(fromKey, root.wallpaper);
        const target = root.wallpaperFor(toKey);
        if (!target)
            return;
        if (!target.bundled) {
            root.apply(target.path);
            return;
        }
        // Bundled: copy it next to the state, then apply the copy.
        const src = Quickshell.shellPath(target.path);
        const dst = `${root.copiesDir}/${toKey.replace("/", "-")}${target.path.slice(target.path.lastIndexOf("."))}`;
        copyProc.target = dst;
        copyProc.command = ["bash", "-c", 'mkdir -p "$(dirname "$2")" && cp -f "$1" "$2" && chmod u+w "$2"', "_", src, dst];
        copyProc.running = true;
    }

    Process {
        id: copyProc
        property string target: ""
        onExited: code => {
            if (code === 0)
                root.apply(copyProc.target);
            else
                console.warn("[ThemeWallpapers] could not copy", copyProc.target);
        }
    }

    onKeyChanged: {
        if (!Config.ready || !root.enabled)
            return;
        if (root._lastKey === "" || root._lastKey === root.key) {
            root._lastKey = root.key;
            return;
        }
        const from = root._lastKey;
        root._lastKey = root.key;
        root.switchTo(from, root.key);
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root._lastKey === "")
                root._lastKey = root.key;
        }
    }
    Component.onCompleted: if (Config.ready) root._lastKey = root.key

    // A wallpaper picked while in a variant becomes that variant's.
    onWallpaperChanged: {
        if (!Config.ready || !root.enabled || root.wallpaper === "")
            return;
        if (root._applying !== "") {
            if (root.wallpaper === root._applying)
                root._applying = "";
            return;
        }
        root.remember(root.key, root.wallpaper);
    }
}
