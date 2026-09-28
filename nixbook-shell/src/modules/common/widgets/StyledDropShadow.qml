import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// Drop shadow following the target's alpha. Persona style: a soft accent
// glow, offset down-right.
DropShadow {
    required property var target
    readonly property bool persona: Persona.shapes
    source: target
    anchors.fill: source
    radius: persona ? Persona.shadowBlur : 8
    samples: radius * 2 + 1
    horizontalOffset: persona ? Persona.shadowOffset : 0
    verticalOffset: persona ? Persona.shadowOffset : 0
    color: persona ? Persona.elevationColor : Appearance.colors.colShadow
    transparentBorder: true
}
