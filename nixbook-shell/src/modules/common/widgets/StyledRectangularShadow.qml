import QtQuick
import QtQuick.Effects
import qs.modules.common

// Elevation shadow. In the Persona style: a soft glow in the variant's
// accent colour, offset down-right.
RectangularShadow {
    required property var target
    readonly property bool persona: Persona.shapes
    anchors.fill: target
    radius: target.radius
    blur: persona ? Persona.shadowBlur : 0.9 * Appearance.sizes.elevationMargin
    offset: persona ? Qt.vector2d(Persona.shadowOffset, Persona.shadowOffset) : Qt.vector2d(0.0, 1.0)
    spread: persona ? 0 : 1
    color: persona ? Persona.elevationColor : Appearance.colors.colShadow
    cached: true
}
