pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The shell's themes (Settings → Appearance → Theme, the desktop menu's
 * Theme submenu). The registry is modules/common/themes.json, also read by
 * the Nix options (lib.nix) and the login screen, so a theme is declared once.
 *
 * Settings:
 *   appearance.theme            the theme's id ("material", "persona", …)
 *   appearance.<id>.variant     that theme's variant (each theme keeps its own)
 *   appearance.<id>.palette     false: keep the wallpaper palette under the
 *                               theme (default true, for variants with one)
 *
 * A theme's own look is a singleton gated on `Themes.current` (Persona.qml),
 * its palette is applied by MaterialThemeLoader from `Themes.palette`.
 *
 * Before `appearance.theme` existed the Persona style was the switch
 * `appearance.persona.enable`: a config.json still holding it true is
 * migrated to `theme: "persona"` by `migrate()` (Config.qml, on load).
 */
Singleton {
    id: root

    FileView {
        id: registryFile
        path: Quickshell.shellPath("modules/common/themes.json")
        blockLoading: true
    }
    readonly property var registry: {
        try {
            const r = JSON.parse(registryFile.text());
            if (Array.isArray(r.themes) && r.themes.length > 0)
                return r;
        } catch (e) {
            console.warn("[Themes] can't read themes.json:", e);
        }
        return { default: "material", themes: [{ id: "material", name: "Material", icon: "palette", variants: [] }] };
    }

    // [{ id, name, icon, description, variants: [{ id, name, icon, palette? }] }]
    readonly property var list: root.registry.themes
    readonly property string defaultTheme: root.theme(root.registry.default) ? root.registry.default : root.list[0].id

    function theme(id) {
        return root.list.find(t => t.id === id) ?? null;
    }
    function variantsOf(id) {
        return root.theme(id)?.variants ?? [];
    }
    function options(id) {
        return Config.options?.appearance?.[id] ?? null;
    }
    // The chosen variant of a theme: its setting when valid, else its
    // `defaultVariant`, else its first.
    function variantOf(id) {
        const variants = root.variantsOf(id);
        if (variants.length === 0)
            return "";
        const chosen = root.options(id)?.variant;
        if (variants.some(v => v.id === chosen))
            return chosen;
        const fallback = root.theme(id).defaultVariant;
        return variants.some(v => v.id === fallback) ? fallback : variants[0].id;
    }
    function variantKey(id) {
        return `appearance.${id}.variant`;
    }

    // ---------------------------------------------------------- current
    readonly property var appearanceOpts: Config.options?.appearance ?? ({})
    readonly property string current: {
        if (!Config.ready)
            return root.defaultTheme;
        // Legacy switch, until migrate() has cleared it.
        if (root.appearanceOpts.persona?.enable === true && root.theme("persona"))
            return "persona";
        const id = root.appearanceOpts.theme;
        return root.theme(id) ? id : root.defaultTheme;
    }
    readonly property var currentTheme: root.theme(root.current)
    readonly property var currentVariants: root.currentTheme?.variants ?? []
    readonly property string variant: root.variantOf(root.current)
    readonly property var currentVariant: root.currentVariants.find(v => v.id === root.variant) ?? null

    // The palette replacing the wallpaper's (null: the wallpaper's).
    readonly property var palette: {
        const p = root.currentVariant?.palette;
        if (!p || root.options(root.current)?.palette === false)
            return null;
        return p;
    }

    function is(id) {
        return root.current === id;
    }

    // ----------------------------------------------------------- sounds
    // The current theme's sound for `kind` ("notification": the chime,
    // "critical": critical notifications / the Persona cut-in): the
    // variant's, else the theme's, else the registry's default. A file set
    // in the settings (sounds.notificationFile, cutIn.soundFile) wins.
    function sound(kind) {
        const rel = root.currentVariant?.sounds?.[kind] ?? root.currentTheme?.sounds?.[kind] ?? root.registry.sounds?.[kind] ?? "";
        return rel !== "" ? Quickshell.shellPath(rel) : "";
    }

    // ------------------------------------------------------------ style
    // A theme's look as data (themes.json `style`, a variant's own `style`
    // overriding its theme's), applied by Appearance; each part can be
    // turned off in the theme's settings (appearance.<id>.shapes / fonts /
    // motion, default true):
    //   rounding  scale of the Material corner radii
    //   fonts     { main, title, numbers } font families
    //   motion    { slam, snap, quick, exit } bezier curves (enter, small
    //             moves, effects, exit), with the Material durations
    // Anything a style can't express is a singleton of the theme's own
    // (Persona.qml, Chiikawa.qml).
    function styleOn(key) {
        return root.options(root.current)?.[key] ?? true;
    }
    readonly property var style: Object.assign({}, root.currentTheme?.style ?? {}, root.currentVariant?.style ?? {})
    readonly property real roundingScale: root.style.rounding && root.styleOn("shapes") ? root.style.rounding : 1
    readonly property var fonts: root.styleOn("fonts") ? (root.style.fonts ?? {}) : {}
    readonly property var curves: root.styleOn("motion") ? (root.style.motion ?? null) : null
    function rounded(radius) {
        return Math.round(radius * root.roundingScale);
    }

    // ---------------------------------------------------------- setters
    function setTheme(id) {
        if (!root.theme(id))
            return;
        const a = Config.options.appearance;
        if (a.persona?.enable === true)
            a.persona.enable = false;
        a.theme = id;
    }
    function setVariant(id, variant) {
        const o = root.options(id);
        if (!o || !root.variantsOf(id).some(v => v.id === variant)) {
            console.warn(`[Themes] no variant "${variant}" of "${id}" (or no appearance.${id} in Config.qml)`);
            return;
        }
        o.variant = variant;
    }

    // Config.qml calls this whenever config.json is loaded.
    function migrate() {
        const a = Config.options.appearance;
        if (a.persona?.enable !== true)
            return;
        if (!NixManaged.isPinned("appearance.theme"))
            a.theme = "persona";
        a.persona.enable = false;
    }
}
