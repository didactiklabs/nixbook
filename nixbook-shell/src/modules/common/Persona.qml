pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * "Persona" style (Atlus' modern Persona art direction) — opt-in via
 * Config.options.appearance.persona. Central tokens consumed by Appearance
 * (rounding, fonts, animation curves), MaterialThemeLoader (palette),
 * StyledRectangularShadow / StyledDropShadow / WidgetShadow (accent glow),
 * PersonaFrame (slanted frames, accent stripe, halftone) and StyledPopup
 * (slam-in entrance).
 *
 * Rendered with Material 3 manners: rounded corners with a Persona cut
 * (a large radius on two diagonal corners), soft tonal elevation with an
 * accent glow, thin tonal outlines, tonal accent containers and surfaces
 * tinted with the accent hue, subtle halftone, a moderate slant and springy
 * motion with a little overshoot.
 *
 * Variants:
 *   p5  — Persona 5 Royal: black / white / red, red glow, strongest slant
 *   p3r — Persona 3 Reload: navy / cyan / white, smoother slant
 *   p4  — Persona 4 Revival (2026 remake): warm near-black / dark amber
 *         panels with bright gold accents and metallic gold borders
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.appearance?.persona ?? ({})
    readonly property bool enabled: Config.ready && (root.opts.enable ?? false)
    readonly property string variant: ["p5", "p3r", "p4"].includes(root.opts.variant) ? root.opts.variant : "p5"

    readonly property bool palette: root.enabled && (root.opts.palette ?? true)
    readonly property bool motion: root.enabled && (root.opts.motion ?? true)
    readonly property bool shapes: root.enabled && (root.opts.shapes ?? true)
    readonly property bool halftone: root.enabled && (root.opts.halftone ?? true)
    readonly property bool fonts: root.enabled && (root.opts.fonts ?? true)

    // ------------------------------------------------------------- shapes
    // Slant of frames (degrees, negative leans right like P5 menus).
    readonly property real skewDeg: root.variant === "p5" ? -5 : root.variant === "p3r" ? -3 : -4
    readonly property real skew: Math.tan(root.skewDeg * Math.PI / 180)
    readonly property real shadowOffset: 4
    // Corner radius of controls and small surfaces; panels (PersonaFrame)
    // get the cut: cornerLarge on top-left and bottom-right, corner elsewhere.
    readonly property int corner: 6
    readonly property int cornerLarge: 18
    readonly property real borderWidth: 1
    // Elevation: a soft accent glow (blur radius, colour) under panels.
    readonly property real shadowBlur: 14
    readonly property color elevationColor: Qt.alpha(root.shadowColor, 0.5)
    // Outline of panels: the variant's border colour, tonal.
    // A variant with an `edge` colour (p5: Royal gold) outlines in it, a
    // little stronger; the others use their border colour, tonal.
    readonly property color outlineColor: root.spec.edge !== undefined ? Qt.alpha(root.spec.edge, 0.55) : Qt.alpha(root.frameBorderColor, 0.3)
    // Halftone/art opacity over panels.
    readonly property real textureOpacity: 0.45

    // --------------------------------------------------------------- colors
    // Spec per variant; MaterialThemeLoader expands it to every m3 role.
    readonly property var specs: ({
        "p5": {
            background: "#0a0a0a", surface1: "#171213", surface2: "#1f191a", surface3: "#2a2223", surface4: "#352b2c",
            onSurface: "#f4f4f4", onSurfaceVariant: "#cfcfcf", outline: "#9c8384", outlineVariant: "#4a3b3c",
            // Black dominates, white type, red as the accent (active
            // controls, slashes) and a touch of Royal gold (panel outlines,
            // tertiary, glints in the art); surfaces and containers are
            // tonal: near-black warmed by the red, deep red containers.
            primary: "#ff1f2d", onPrimary: "#ffffff", primaryContainer: "#5c0a13", onPrimaryContainer: "#ffdad8",
            secondary: "#ffffff", onSecondary: "#0a0a0a", secondaryContainer: "#3a2f30", onSecondaryContainer: "#f5dddd",
            // Tertiary: Royal gold (the key art's sparkles and bronze panels).
            tertiary: "#e8b64c", onTertiary: "#1a1204", tertiaryContainer: "#3d2c0c", onTertiaryContainer: "#ffe2a6",
            error: "#ff5449", onError: "#ffffff", errorContainer: "#93000a", onErrorContainer: "#ffdad6",
            frame: "#151112", frameBorder: "#ffffff", shadow: "#e60012", stripe: "#e60012", ink: "#ffffff",
            edge: "#d9a441",
            // Phone chat (notification popups): white bubbles, black type
            bubble: "#ffffff", bubbleText: "#0a0a0a", tag: "#0a0a0a", tagText: "#ffffff", mugBorder: "#d9a441"
        },
        "p3r": {
            background: "#050f26", surface1: "#0c1d42", surface2: "#112656", surface3: "#17316c", surface4: "#1d3c82",
            onSurface: "#eaf6ff", onSurfaceVariant: "#b8d4ee", outline: "#6f93b8", outlineVariant: "#23406e",
            primary: "#3fd4ff", onPrimary: "#00233a", primaryContainer: "#0f4a9e", onPrimaryContainer: "#d8e6ff",
            secondary: "#9fe8ff", onSecondary: "#00233a", secondaryContainer: "#16356f", onSecondaryContainer: "#dbeaff",
            tertiary: "#ffffff", onTertiary: "#050f26", tertiaryContainer: "#1f4aa8", onTertiaryContainer: "#ffffff",
            error: "#ff6b8b", onError: "#3a0012", errorContainer: "#7d1233", onErrorContainer: "#ffd9e0",
            frame: "#0a1a40", frameBorder: "#3fd4ff", shadow: "#0b1f5e", stripe: "#3fd4ff", ink: "#eaf6ff",
            bubble: "#dff6ff", bubbleText: "#07163a", tag: "#1450d8", tagText: "#ffffff", mugBorder: "#3fd4ff"
        },
        "p4": {
            // Warm near-black / dark amber panels (the dialogue box), bright
            // gold only as the accent (selected choice, stripes), metallic
            // gold borders and a deep-gold hard shadow.
            background: "#0d0a05", surface1: "#19130a", surface2: "#221a0d", surface3: "#2d2311", surface4: "#382c16",
            onSurface: "#fbf5e2", onSurfaceVariant: "#d9cca6", outline: "#9e8c4a", outlineVariant: "#3b3017",
            primary: "#ffe600", onPrimary: "#1a1300", primaryContainer: "#4d3d00", onPrimaryContainer: "#fff0a8",
            secondary: "#d9b12c", onSecondary: "#1a1300", secondaryContainer: "#43340f", onSecondaryContainer: "#ffe7a3",
            tertiary: "#fff4c0", onTertiary: "#15100a", tertiaryContainer: "#4a3a12", onTertiaryContainer: "#fff3c4",
            error: "#ff5449", onError: "#ffffff", errorContainer: "#93000a", onErrorContainer: "#ffdad6",
            frame: "#161008", frameBorder: "#d9b12c", shadow: "#7a5c00", stripe: "#ffe600", ink: "#fbf5e2",
            bubble: "#241a0b", bubbleText: "#fbf5e2", tag: "#120d06", tagText: "#ffe600", mugBorder: "#d9b12c"
        }
    })
    readonly property var spec: root.specs[root.variant]

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
    // Material 3 expressive springs, with a little overshoot left.
    readonly property var curves: ({
        "slam": [0.2, 1.22, 0.3, 1, 1, 1],
        "snap": [0.25, 1.1, 0.35, 1, 1, 1],
        "quick": [0.3, 1.02, 0.35, 1, 1, 1],
        "exit": [0.4, 0, 0.8, 0.4, 1, 1]
    })
}
