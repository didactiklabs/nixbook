pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * "Studio Ghibli" theme — Settings → Appearance → Theme, `appearance.theme:
 * "ghibli"` (Themes.qml). Its watercolour palettes, soft corners, storybook
 * fonts (Zen Maru Gothic, Klee One titles) and unhurried motion are data in
 * themes.json (`style`, applied by Appearance and MaterialThemeLoader); this
 * singleton adds what data can't: the variant's spirit (GhibliSpirit: the
 * sidebars' corner, the loading screen, the cut-in), the scatter behind the
 * sidebars (GhibliDecor) and the tokens of its cut-in (GhibliCutIn.qml, a
 * painted card drifting in on the wind).
 *
 * Variants: totoro (summer greens; the forest spirit, leaves and soot
 * sprites), spirited (the bathhouse at night; the masked spirit, paper birds,
 * lanterns), mononoke (the ancient forest; a kodama, fireflies). Art:
 * assets/ghibli/generate.py, rasterised when the package is built (qml.nix),
 * like its synthesized sounds (assets/ghibli/sounds.py).
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.appearance?.ghibli ?? ({})
    readonly property bool enabled: Themes.is("ghibli")
    readonly property string variant: Themes.variantOf("ghibli")
    readonly property bool spirits: root.enabled && (root.opts.spirits ?? true)

    readonly property var spec: Themes.variantsOf("ghibli").find(v => v.id === root.variant)?.palette ?? ({})

    // The cut-in's colours: the paper card, its ink, the accent (seal,
    // buttons), the warm glow, and what drifts across (leaves, paper birds,
    // fireflies).
    readonly property color paper: root.spec.background ?? "#f6f4e8"
    readonly property color ink: root.spec.ink ?? "#26322a"
    readonly property color accent: root.spec.primary ?? "#3c7a3f"
    readonly property color seal: root.spec.accent ?? "#e8a33d"
    readonly property color glow: root.spec.glow ?? "#ffe9a8"
    readonly property color drift: root.variant === "spirited" ? "#f6f1e4" : (root.variant === "mononoke" ? (root.spec.glow ?? "#c8f5ff") : (root.spec.leaf ?? "#4f8a3c"))
    // Night variants: the card is lit from inside (a glow), not shaded.
    readonly property bool night: root.variant !== "totoro"
    readonly property string titleFont: Appearance.font.family.title

    function spiritUrl(variant) {
        return Quickshell.shellPath(`assets/ghibli/${variant ?? root.variant}-spirit.png`);
    }
    function patternUrl(variant) {
        return Quickshell.shellPath(`assets/ghibli/${variant ?? root.variant}-tall.png`);
    }

    // Keep the current variant's art decoded (served from the pixmap cache
    // when a sidebar opens), only while the theme is on.
    Instantiator {
        model: root.spirits ? [root.spiritUrl(), root.patternUrl()] : []
        delegate: Image {
            required property string modelData
            source: modelData
            asynchronous: true
            cache: true
            visible: false
        }
    }
}
