import QtQuick
import QtQuick.Effects
import qs.modules.common

// Elevation shadow. In the Persona style it becomes a hard, unblurred shadow
// in the variant's accent color, offset down-right (comic-panel look).
RectangularShadow {
    required property var target
    readonly property bool persona: Persona.shapes
    anchors.fill: target
    radius: target.radius
    blur: persona ? 0 : 0.9 * Appearance.sizes.elevationMargin
    offset: persona ? Qt.vector2d(Persona.shadowOffset, Persona.shadowOffset) : Qt.vector2d(0.0, 1.0)
    spread: persona ? 0 : 1
    color: persona ? Persona.shadowColor : Appearance.colors.colShadow
    cached: true

    // Tonal elevation (Appearance.tonal): never drawn, whatever the call
    // site's own `visible` says.
    Binding on visible {
        when: Appearance.tonal
        value: false
    }
}
