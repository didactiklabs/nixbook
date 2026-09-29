pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * "Cyberpunk 2077" theme — Settings → Appearance → Theme, `appearance.theme:
 * "cyberpunk"` (Themes.qml). Its neon-on-black palettes, near-square
 * corners, condensed tech face (Rajdhani) and snappy motion are data in
 * themes.json (`style`, applied by Appearance and MaterialThemeLoader); this
 * singleton adds what data can't: the tokens of its cut-in
 * (CyberpunkCutIn.qml, an incoming holocall with an RGB-split glitch).
 *
 * Variants: yellow (the key art: yellow / cyan / red-pink), red (the in-game
 * HUD: salmon red / cyan / yellow). Wallpapers: assets/cyberpunk/generate.py,
 * rasterised when the package is built (qml.nix), like its synthesized
 * sounds (assets/cyberpunk/sounds.py).
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.appearance?.cyberpunk ?? ({})
    readonly property bool enabled: Themes.is("cyberpunk")
    readonly property string variant: Themes.variantOf("cyberpunk")
    readonly property bool glitch: root.enabled && (root.opts.glitch ?? true)

    readonly property var spec: Themes.variantsOf("cyberpunk").find(v => v.id === root.variant)?.palette ?? ({})

    // The cut-in's colours: the accent (frame, header), the glitch offset
    // (the other RGB channel), the alert tag, the ink and the panel.
    readonly property color accent: root.spec.primary ?? "#fcee0a"
    readonly property color glitchColor: root.spec.glitch ?? "#02d7f2"
    readonly property color alertColor: root.spec.alert ?? "#ff2a6d"
    readonly property color ink: root.spec.ink ?? "#f2f0e3"
    readonly property color panel: root.spec.frame ?? "#0b0b0d"
    // The theme's title face (themes.json style.fonts, via Appearance: the
    // user's own when appearance.cyberpunk.fonts is off).
    readonly property string font: Appearance.font.family.title

    // Size of the cut corners (the chamfer on the frame's top left and
    // bottom right).
    readonly property int chamfer: 26
}
