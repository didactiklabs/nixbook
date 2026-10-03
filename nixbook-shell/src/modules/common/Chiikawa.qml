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
 * the alert, the wallpapers) it is the three friends (friends.gif: Momonga
 * with Chiikawa and Usagi beside him, friends.py); the rest of the art is drawn by
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
    // Momonga with Chiikawa and Usagi: 460x177.
    function friendsUrl() {
        return Quickshell.shellPath("assets/chiikawa/friends.gif");
    }
    readonly property real friendsAspect: 460 / 177
    function patternUrl(variant) {
        return Quickshell.shellPath(`assets/chiikawa/${variant ?? root.variant}-tall.png`);
    }

    // Keep the current variant's art decoded (served from the pixmap cache
    // when a sidebar opens), only while the theme is on.
    Instantiator {
        model: root.mascot ? [root.mascotUrl(), root.friendsUrl(), root.patternUrl()] : []
        delegate: Image {
            required property string modelData
            source: modelData
            asynchronous: true
            cache: true
            visible: false
        }
    }
}
