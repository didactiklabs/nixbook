pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * "Persona" theme (Atlus' modern Persona art direction) — Settings →
 * Appearance → Theme, `appearance.theme: "persona"` (Themes.qml). Central
 * tokens consumed by Appearance (rounding, fonts, animation curves),
 * StyledRectangularShadow / StyledDropShadow (hard offset shadows),
 * PersonaFrame (slanted frames, accent stripe, halftone) and StyledPopup
 * (slam-in entrance). Its palettes are in themes.json (applied by
 * MaterialThemeLoader through Themes.palette).
 *
 * Variants (themes.json):
 *   p5  — Persona 5 Royal: black / white / red, hard red shadows, Royal gold
 *         outlines and glints, strong slant
 *   p3r — Persona 3 Reload: navy / cyan / white, smoother slant
 *   p4  — Persona 4 Revival (2026 remake): warm near-black / dark amber
 *         panels with bright gold accents and metallic gold borders
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.appearance?.persona ?? ({})
    readonly property bool enabled: Themes.is("persona")
    readonly property string variant: Themes.variantOf("persona")

    readonly property bool palette: root.enabled && (root.opts.palette ?? true)
    readonly property bool motion: root.enabled && (root.opts.motion ?? true)
    readonly property bool shapes: root.enabled && (root.opts.shapes ?? true)
    readonly property bool halftone: root.enabled && (root.opts.halftone ?? true)
    readonly property bool fonts: root.enabled && (root.opts.fonts ?? true)

    // ------------------------------------------------------------- shapes
    // Slant of frames (degrees, negative leans right like P5 menus).
    readonly property real skewDeg: root.variant === "p5" ? -7 : root.variant === "p3r" ? -4 : -5
    readonly property real skew: Math.tan(root.skewDeg * Math.PI / 180)
    readonly property real shadowOffset: root.variant === "p3r" ? 5 : 7
    readonly property int corner: root.variant === "p3r" ? 3 : 1
    readonly property int borderWidth: root.variant === "p3r" ? 2 : 3
    // Outline of panels: a variant with an `edge` colour (p5: Royal gold)
    // outlines in it, the others in their border colour.
    readonly property color outlineColor: root.spec.edge ?? root.frameBorderColor

    // --------------------------------------------------------------- colors
    // Palette per variant (themes.json); MaterialThemeLoader expands the
    // current one to every m3 role, the frames and chat bubbles read it here.
    readonly property var specs: {
        const specs = {};
        for (const v of Themes.variantsOf("persona"))
            specs[v.id] = v.palette;
        return specs;
    }
    readonly property var spec: root.specs[root.variant] ?? ({})

    // Frame colors (PersonaFrame / hard shadows)
    readonly property color frameColor: root.spec.frame
    readonly property color frameBorderColor: root.spec.frameBorder
    readonly property color shadowColor: root.spec.shadow
    readonly property color stripeColor: root.spec.stripe

    // ------------------------------------------------------------- textures
    // Background art (PersonaTexture): one texture per aspect bucket — tall
    // (sidebars), panel (popups), wide (OSD, search bar) — rasterised to PNG
    // when the package is built (customPkgs/nixbook-shell/shell.nix).
    readonly property var textureShapes: ["tall", "panel", "wide"]
    function textureShapeFor(w, h) {
        const aspect = w / Math.max(1, h);
        return aspect < 0.85 ? "tall" : aspect > 2.4 ? "wide" : "panel";
    }
    function textureUrl(shape) {
        return Quickshell.shellPath(`assets/persona/${root.variant}-${shape}.png`);
    }
    // Keep the current variant's textures decoded: PersonaTexture requests the
    // same url, so it's served from the pixmap cache at once on any screen.
    // Decoded off the GUI thread, only while the art is enabled.
    Instantiator {
        model: root.halftone ? root.textureShapes : []
        delegate: Image {
            required property string modelData
            source: root.textureUrl(modelData)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }
    }

    // ---------------------------------------------------------------- fonts
    // Condensed heavy display face for titles/numbers (Oswald, installed by
    // the nixbookShellConfig Nix module); body text stays on the regular UI font.
    readonly property string titleFont: "Oswald"

    // --------------------------------------------------------------- motion
    // Snappy, overshooting curves: things slam in and settle.
    readonly property var curves: ({
        "slam": [0.12, 1.45, 0.3, 1, 1, 1],
        "snap": [0.2, 1.18, 0.32, 1, 1, 1],
        "quick": [0.25, 1.05, 0.3, 1, 1, 1],
        "exit": [0.55, 0, 0.9, 0.3, 1, 1]
    })
}
