pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Apps coloured like the shell (programs.nixbook-shell.appTheming: Qt/KDE,
 * Vesktop, YouTube Music, Zen): whenever the palette the shell shows changes
 * (a new wallpaper palette, light/dark, a theme variant with its own
 * palette), it goes to scripts/colors/apply-app-colors.sh, which renders the
 * apps' templates from it and has them reload. Main shell only (loaded from
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

    function apply() {
        // Not before the first real palette, nor the lock screen's own one
        // (the live palette comes back when it unlocks).
        if (!MaterialThemeLoader.firstApplyDone
                || MaterialThemeLoader.filePath === Directories.generatedLockMaterialThemePath)
            return;
        Quickshell.execDetached([root.script, JSON.stringify(root.palette())]);
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
}
