pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

/**
 * "Chiikawa" theme — Settings → Appearance → Theme, `appearance.theme:
 * "chiikawa"` (Themes.qml). Its palettes, rounder corners, rounded font and
 * bouncy motion are data in themes.json (`style`, applied by Appearance and
 * MaterialThemeLoader); this singleton adds what data can't: the character
 * (ChiikawaMascot: loading screen, sidebars) and the scattered stars and
 * hearts behind the sidebars (ChiikawaDecor).
 *
 * Variants: momonga (periwinkle), usagi (yellow), chiikawa (cream and pink).
 * The character is the same animated GIF for every variant
 * (assets/chiikawa/momonga.gif); where there is room (the loading screen,
 * the alert, the wallpapers) it is the three friends: Chiikawa
 * (chiikawa.gif), Momonga and Usagi (usagi.gif) side by side, each GIF as
 * is (friendsLayout); the rest of the art is drawn by
 * assets/chiikawa/generate.py, rasterised to PNG when the package is built
 * (qml.nix).
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.appearance?.chiikawa ?? ({})
    readonly property bool enabled: Themes.is("chiikawa")
    readonly property string variant: Themes.variantOf("chiikawa")
    readonly property bool mascot: root.enabled && (root.opts.mascot ?? true)

    readonly property var spec: Themes.variantsOf("chiikawa").find(v => v.id === root.variant)?.palette ?? ({})

    function mascotUrl() {
        return Quickshell.shellPath("assets/chiikawa/momonga.gif");
    }
    // The three friends in a 407x151 frame, feet on one line (y 143):
    // Momonga at his own size, his friends at 0.72 of theirs. Mirrored by
    // assets/chiikawa/generate.py for the wallpapers.
    readonly property size friendsSize: Qt.size(407, 151)
    readonly property var friendsLayout: [
        { file: "chiikawa.gif", x: 0, y: 18, width: 144, height: 132 },
        { file: "momonga.gif", x: 93, y: 0, width: 200, height: 151 },
        { file: "usagi.gif", x: 273, y: 2, width: 134, height: 144 },
    ]
    function friendUrl(file) {
        return Quickshell.shellPath(`assets/chiikawa/${file}`);
    }
    readonly property real friendsAspect: root.friendsSize.width / root.friendsSize.height
    function patternUrl(variant) {
        return Quickshell.shellPath(`assets/chiikawa/${variant ?? root.variant}-tall.png`);
    }

    // Keep the current variant's art decoded (served from the pixmap cache
    // when a sidebar opens), only while the theme is on.
    Instantiator {
        model: root.mascot ? [...root.friendsLayout.map(f => root.friendUrl(f.file)), root.patternUrl()] : []
        delegate: Image {
            required property string modelData
            source: modelData
            asynchronous: true
            cache: true
            visible: false
        }
    }
}
