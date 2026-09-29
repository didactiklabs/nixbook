pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Keeps niri's window open/close animation in the current theme's colours.
 *
 * A niri config that wants this (nixbook's homeManagerModules/niri) installs
 * a template, ~/.config/niri/nixbook-shell-animations.kdl.in, whose @ACCENT@
 * and @INK@ are GLSL vec3s, and includes nixbook-shell-animations.kdl next to
 * it (optional=true, last). This fills the template with the palette's
 * primary and ink (the theme's `ink`, else on-surface) and writes that file
 * whenever they change: a theme, variant or wallpaper palette picked in the
 * shell recolours the animation. niri watches included files and reloads it.
 *
 * Without the template (another compositor, or a niri config that doesn't
 * ship one) it does nothing.
 */
Singleton {
    id: root

    readonly property bool active: WM.compositor === "niri"
    readonly property string dir: `${FileUtils.trimFileProtocol(Directories.config)}/niri`
    readonly property color accent: Appearance.m3colors.m3primary
    readonly property color ink: Themes.palette?.ink ?? Appearance.m3colors.m3onSurface

    function load() {}

    function vec3(c) {
        return `vec3(${c.r.toFixed(4)}, ${c.g.toFixed(4)}, ${c.b.toFixed(4)})`;
    }

    function write() {
        if (!root.active)
            return;
        const template = templateFile.text();
        if (!template)
            return;
        const kdl = template.split("@ACCENT@").join(root.vec3(root.accent)).split("@INK@").join(root.vec3(root.ink));
        // Unchanged: don't make niri reload its config for nothing.
        if (kdl === outputFile.text())
            return;
        outputFile.setText(kdl);
    }

    // A palette is applied over a few frames (MaterialThemeLoader): write
    // once it has settled.
    onAccentChanged: settle.restart()
    onInkChanged: settle.restart()
    Timer {
        id: settle
        interval: 500
        onTriggered: root.write()
    }
    Component.onCompleted: settle.restart()

    FileView {
        id: templateFile
        path: root.active ? `${root.dir}/nixbook-shell-animations.kdl.in` : ""
        blockLoading: true
        watchChanges: true
        // A new generation re-links the template.
        onFileChanged: {
            reload();
            settle.restart();
        }
    }
    FileView {
        id: outputFile
        path: root.active ? `${root.dir}/nixbook-shell-animations.kdl` : ""
        blockLoading: true
        // Missing until the first write.
        printErrors: false
    }
}
