pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * "Persona" style (Atlus' modern Persona art direction) — opt-in via
 * Config.options.appearance.persona. Central tokens consumed by Appearance
 * (rounding, fonts, animation curves), MaterialThemeLoader (palette),
 * StyledRectangularShadow / StyledDropShadow (hard offset shadows),
 * PersonaFrame (slanted frames, accent stripe, halftone) and StyledPopup
 * (slam-in entrance).
 *
 * Variants:
 *   p5  — Persona 5 Royal: black / white / red, hard red shadows, strong slant
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
    readonly property real skewDeg: root.variant === "p5" ? -7 : root.variant === "p3r" ? -4 : -5
    readonly property real skew: Math.tan(root.skewDeg * Math.PI / 180)
    readonly property real shadowOffset: root.variant === "p3r" ? 5 : 7
    readonly property int corner: root.variant === "p3r" ? 3 : 1
    readonly property int borderWidth: root.variant === "p3r" ? 2 : 3

    // --------------------------------------------------------------- colors
    // Spec per variant; MaterialThemeLoader expands it to every m3 role.
    readonly property var specs: ({
        "p5": {
            background: "#0a0a0a", surface1: "#141414", surface2: "#1c1c1c", surface3: "#262626", surface4: "#303030",
            onSurface: "#f4f4f4", onSurfaceVariant: "#cfcfcf", outline: "#8a8a8a", outlineVariant: "#3a3a3a",
            // Black dominates, white type, red only as the accent (active
            // controls, slashes) and the hard offset shadow: containers (widget
            // cards, filled buttons) are black, not red.
            primary: "#ff1f2d", onPrimary: "#ffffff", primaryContainer: "#111111", onPrimaryContainer: "#ffffff",
            secondary: "#ffffff", onSecondary: "#0a0a0a", secondaryContainer: "#2a2a2a", onSecondaryContainer: "#ffffff",
            tertiary: "#ffe14d", onTertiary: "#0a0a0a", tertiaryContainer: "#3b3200", onTertiaryContainer: "#fff3b0",
            error: "#ff5449", onError: "#ffffff", errorContainer: "#93000a", onErrorContainer: "#ffdad6",
            frame: "#0a0a0a", frameBorder: "#ffffff", shadow: "#e60012", stripe: "#e60012", ink: "#ffffff",
            // Phone chat (notification popups): white bubbles, black type
            bubble: "#ffffff", bubbleText: "#0a0a0a", tag: "#0a0a0a", tagText: "#ffffff", mugBorder: "#ffffff"
        },
        "p3r": {
            background: "#050f26", surface1: "#0a1a3c", surface2: "#0f2350", surface3: "#152e66", surface4: "#1b397c",
            onSurface: "#eaf6ff", onSurfaceVariant: "#b8d4ee", outline: "#6f93b8", outlineVariant: "#23406e",
            primary: "#3fd4ff", onPrimary: "#00233a", primaryContainer: "#1450d8", onPrimaryContainer: "#ffffff",
            secondary: "#9fe8ff", onSecondary: "#00233a", secondaryContainer: "#123c8c", onSecondaryContainer: "#e2f6ff",
            tertiary: "#ffffff", onTertiary: "#050f26", tertiaryContainer: "#1f4aa8", onTertiaryContainer: "#ffffff",
            error: "#ff6b8b", onError: "#3a0012", errorContainer: "#7d1233", onErrorContainer: "#ffd9e0",
            frame: "#07163a", frameBorder: "#3fd4ff", shadow: "#0b1f5e", stripe: "#3fd4ff", ink: "#eaf6ff",
            bubble: "#dff6ff", bubbleText: "#07163a", tag: "#1450d8", tagText: "#ffffff", mugBorder: "#3fd4ff"
        },
        "p4": {
            // Warm near-black / dark amber panels (the dialogue box), bright
            // gold only as the accent (selected choice, stripes), metallic
            // gold borders and a deep-gold hard shadow.
            background: "#0d0a05", surface1: "#16110a", surface2: "#1e170c", surface3: "#281f10", surface4: "#332814",
            onSurface: "#fbf5e2", onSurfaceVariant: "#d9cca6", outline: "#9e8c4a", outlineVariant: "#3b3017",
            primary: "#ffe600", onPrimary: "#1a1300", primaryContainer: "#2b200b", onPrimaryContainer: "#ffe98c",
            secondary: "#d9b12c", onSecondary: "#1a1300", secondaryContainer: "#3d2e0f", onSecondaryContainer: "#ffe7a3",
            tertiary: "#fff4c0", onTertiary: "#15100a", tertiaryContainer: "#4a3a12", onTertiaryContainer: "#fff3c4",
            error: "#ff5449", onError: "#ffffff", errorContainer: "#93000a", onErrorContainer: "#ffdad6",
            frame: "#120d06", frameBorder: "#d9b12c", shadow: "#7a5c00", stripe: "#ffe600", ink: "#fbf5e2",
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
    readonly property var curves: ({
        "slam": [0.12, 1.45, 0.3, 1, 1, 1],
        "snap": [0.2, 1.18, 0.32, 1, 1, 1],
        "quick": [0.25, 1.05, 0.3, 1, 1, 1],
        "exit": [0.55, 0, 0.9, 0.3, 1, 1]
    })
}
