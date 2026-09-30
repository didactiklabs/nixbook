pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Apps coloured like the shell (Settings > Appearance > Color generation >
 * Apps: Qt/KDE, Vesktop, Zen, each with its own switch):
 * whenever the palette the shell shows changes (a new wallpaper palette,
 * light/dark, a theme variant with its own palette) or a switch is flipped,
 * the palette and the apps switched on go to
 * scripts/colors/apply-app-colors.sh, which renders the apps' templates,
 * has the running apps pick them up (live where the app allows it) and
 * undoes the setup of the apps switched off. Main shell only (loaded from
 * shell.qml): the greeter and the splash screens have no say.
 */
Singleton {
    id: root

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/apply-app-colors.sh`

    function load() {
        // Singletons are lazy: this instantiates it; the first palette
        // arrives through onM3colorsChanged.
    }

    // The current palette as Material roles in snake_case ("m3surfaceContainerLow"
    // -> "surface_container_low"), the names the templates use.
    function palette() {
        const colors = Appearance.m3colors;
        const out = {};
        for (const key in colors) {
            if (!key.startsWith("m3") || typeof colors[key] === "function")
                continue;
            const role = key.slice(2).replace(/[A-Z]/g, c => "_" + c.toLowerCase());
            out[role] = colors[key].toString();
        }
        return out;
    }

    // The apps switched on, as apply-app-colors.sh names them: none while the
    // "Apps" switch is off.
    function apps() {
        const theming = Config.options.appearance.wallpaperTheming;
        if (!theming.enableQtApps)
            return [];
        const names = { qt: "qt", vesktop: "vesktop", zen: "zen" };
        return Object.keys(names).filter(key => theming.apps[key]).map(key => names[key]);
    }

    function apply() {
        // Not before the first real palette, nor the lock screen's own one
        // (the live palette comes back when it unlocks).
        if (!MaterialThemeLoader.firstApplyDone
                || MaterialThemeLoader.filePath === Directories.generatedLockMaterialThemePath)
            return;
        Quickshell.execDetached([root.script, JSON.stringify(root.palette()), root.apps().join(",")]);
    }

    // A palette swap can come in slices and in quick succession (wallpaper
    // then light/dark): one render once it has settled.
    Timer {
        id: applyTimer
        interval: 500
        onTriggered: root.apply()
    }

    Connections {
        target: Appearance
        function onM3colorsChanged() { applyTimer.restart() }
    }
    Connections {
        target: Config.options.appearance.wallpaperTheming
        function onEnableQtAppsChanged() { applyTimer.restart() }
    }
    Connections {
        target: Config.options.appearance.wallpaperTheming.apps
        function onQtChanged() { applyTimer.restart() }
        function onVesktopChanged() { applyTimer.restart() }
        function onZenChanged() { applyTimer.restart() }
    }
}
