import QtQuick
import QtQuick.Effects
import qs.modules.common

// Elevation of a floating surface. Liquid Glass (Appearance.glass): a soft
// shadow and the surface's specular rim (GlassRim, put on the target). In
// the Persona style: a hard, unblurred shadow in the variant's accent colour,
// offset down-right (comic-panel look).
//
// The shadow is RectangularShadow's signed-distance shader, uncached: it is
// drawn only when its window redraws anyway, and holds no texture.
// `elevated: false` keeps the old tonal look (no shadow, no rim) for many
// small items in a grid (wallpaper thumbnails).
RectangularShadow {
    id: root
    required property var target
    property bool elevated: true
    // The rim on the target (false: the target draws its own edge).
    property bool rim: true
    readonly property bool persona: Persona.shapes
    readonly property bool soft: !root.persona && Appearance.glass.enabled && root.elevated
    anchors.fill: target
    // A pill's 9999 clamped: the shader wants a real radius.
    radius: Math.min(target.radius ?? 0, Math.min(width, height) / 2)
    blur: root.persona ? 0 : 1.2 * Appearance.sizes.elevationMargin
    offset: root.persona ? Qt.vector2d(Persona.shadowOffset, Persona.shadowOffset) : Qt.vector2d(0.0, 3.0)
    spread: root.persona ? 0 : -3
    color: root.persona ? Persona.shadowColor : Qt.rgba(Appearance.glass.shadowColor.r, Appearance.glass.shadowColor.g, Appearance.glass.shadowColor.b, Appearance.glass.shadowAlpha)
    cached: root.persona

    // Neither style: tonal elevation, never drawn whatever the call site's
    // own `visible` says.
    Binding on visible {
        when: !root.persona && !root.soft
        value: false
    }

    GlassRim {
        parent: root.target
        anchors.fill: parent
        radius: root.radius
        topLeftRadius: Math.max(0, Math.min(root.target?.topLeftRadius ?? root.radius, root.radius))
        topRightRadius: Math.max(0, Math.min(root.target?.topRightRadius ?? root.radius, root.radius))
        bottomLeftRadius: Math.max(0, Math.min(root.target?.bottomLeftRadius ?? root.radius, root.radius))
        bottomRightRadius: Math.max(0, Math.min(root.target?.bottomRightRadius ?? root.radius, root.radius))
        visible: root.visible && root.soft && root.rim && width > 4 && height > 4
    }
}
