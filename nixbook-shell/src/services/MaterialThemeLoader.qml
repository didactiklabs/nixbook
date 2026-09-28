pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function reapplyTheme() {
        themeFileView.reload()
    }

    // Palette updates are the most expensive thing the shell does at runtime:
    // every m3 role fans out to hundreds of bindings and colour Behaviors
    // (~75 ms of GUI-thread work for a full palette). So:
    //  - roles whose value didn't change are skipped,
    //  - the first palette (startup) is applied in one go so nothing flashes,
    //  - later palettes wait while a wallpaper transition is running and are
    //    then applied in small time-boxed slices across frames, so neither the
    //    transition shader nor the colour animations drop frames.
    property bool firstApplyDone: false
    property var pendingPalette: null   // [[m3Key, value], ...] still to apply

    // A theme's fixed palette (Themes.palette, from themes.json) replaces the
    // wallpaper-generated one (kept in lastFileContent so switching back to a
    // theme without one restores it).
    property string lastFileContent: ""
    function themePalette() {
        const c = Themes.palette;
        return {
            background: c.background, on_background: c.onSurface,
            surface: c.background, surface_dim: c.background, surface_bright: c.surface4,
            surface_container_lowest: c.background, surface_container_low: c.surface1,
            surface_container: c.surface2, surface_container_high: c.surface3, surface_container_highest: c.surface4,
            surface_variant: c.surface3, on_surface: c.onSurface, on_surface_variant: c.onSurfaceVariant,
            inverse_surface: c.onSurface, inverse_on_surface: c.background, inverse_primary: c.primaryContainer,
            outline: c.outline, outline_variant: c.outlineVariant, shadow: "#000000", scrim: "#000000",
            surface_tint: c.primary,
            primary: c.primary, on_primary: c.onPrimary, primary_container: c.primaryContainer, on_primary_container: c.onPrimaryContainer,
            primary_fixed: c.primary, primary_fixed_dim: c.primaryContainer, on_primary_fixed: c.onPrimary, on_primary_fixed_variant: c.onPrimaryContainer,
            secondary: c.secondary, on_secondary: c.onSecondary, secondary_container: c.secondaryContainer, on_secondary_container: c.onSecondaryContainer,
            secondary_fixed: c.secondary, secondary_fixed_dim: c.secondaryContainer, on_secondary_fixed: c.onSecondary, on_secondary_fixed_variant: c.onSecondaryContainer,
            tertiary: c.tertiary, on_tertiary: c.onTertiary, tertiary_container: c.tertiaryContainer, on_tertiary_container: c.onTertiaryContainer,
            tertiary_fixed: c.tertiary, tertiary_fixed_dim: c.tertiaryContainer, on_tertiary_fixed: c.onTertiary, on_tertiary_fixed_variant: c.onTertiaryContainer,
            error: c.error, on_error: c.onError, error_container: c.errorContainer, on_error_container: c.onErrorContainer
        };
    }
    function reapplyCurrent() {
        if (Themes.palette)
            root.applyColors(JSON.stringify(Object.assign({ __theme: true }, root.themePalette())));
        else if (root.lastFileContent !== "")
            root.applyColors(root.lastFileContent);
    }
    Connections {
        target: Themes
        function onPaletteChanged() { root.reapplyCurrent() }
    }

    function applyColors(fileContent) {
        let json;
        try {
            json = JSON.parse(fileContent);
        } catch (e) {
            console.warn("[MaterialThemeLoader] invalid palette:", e);
            return;
        }
        // Wallpaper palettes are remembered; while a theme owns the palette
        // they don't override it.
        if (!json.__theme) {
            root.lastFileContent = fileContent;
            if (Themes.palette) {
                json = root.themePalette();
            }
        }
        const entries = [];
        for (const key in json) {
            if (!json.hasOwnProperty(key) || key === "__theme")
                continue;
            // Convert snake_case to CamelCase
            const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase());
            const m3Key = `m3${camelCaseKey}`;
            const current = Appearance.m3colors[m3Key];
            if (current !== undefined && Qt.colorEqual(current, json[key]))
                continue;
            entries.push([m3Key, json[key]]);
        }
        if (!root.firstApplyDone) {
            root.firstApplyDone = true;
            root.pendingPalette = entries;
            root.flushPalette();
            return;
        }
        // Newer palette replaces whatever was still queued.
        root.pendingPalette = entries;
        root.schedulePalette();
    }

    function schedulePalette() {
        if (!root.pendingPalette)
            return;
        if (GlobalStates.wallpaperTransitionsBusy > 0 && !transitionWaitTimeout.expired) {
            if (!transitionWaitTimeout.running)
                transitionWaitTimeout.restart();
            return;
        }
        transitionWaitTimeout.stop();
        transitionWaitTimeout.expired = false;
        root.flushPalette();
    }

    // Swaps in a complete new palette object in one assignment: every
    // binding on Appearance.m3colors re-evaluates once, instead of once per
    // changed role (setting ~60 roles one by one — even sliced across frames —
    // cost 0.6–0.9 s of stalls per palette change).
    function flushPalette() {
        const entries = root.pendingPalette;
        if (!entries)
            return;
        root.pendingPalette = null;
        const current = Appearance.m3colors;
        const values = {};
        for (const key in current) {
            // for…in also lists the change signals (m3errorChanged, …)
            if ((key.startsWith("m3") || key.startsWith("term") || key === "transparent")
                    && typeof current[key] !== "function")
                values[key] = current[key];
        }
        let changed = false;
        for (const [key, value] of entries) {
            if (!(key in values)) continue; // not a role this shell knows
            values[key] = value;
            changed = true;
        }
        if (!changed)
            return;
        values.darkmode = Qt.color(values.m3background).hslLightness < 0.5;
        Appearance.m3colors = Appearance.newPalette(values);
        if (current.dynamicInstance)
            Qt.callLater(() => current.destroy());
        // Custom window border colors are stored as palette roles, so they
        // have to be pushed to Hyprland again whenever the palette changes.
        HyprlandConfig.applyBorderColors();
    }

    // Never hold a palette hostage to a stuck transition.
    Timer {
        id: transitionWaitTimeout
        property bool expired: false
        interval: 2500
        onTriggered: {
            expired = true;
            root.schedulePalette();
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperTransitionsBusyChanged() {
            if (GlobalStates.wallpaperTransitionsBusy === 0)
                root.schedulePalette();
        }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    function useLockTheme() {
        root.filePath = ""
        root.filePath = Directories.generatedLockMaterialThemePath
    }

    function useLiveTheme() {
        root.filePath = ""
        root.filePath = Directories.generatedMaterialThemePath
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

    FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }
}
