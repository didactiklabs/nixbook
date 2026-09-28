import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// Drop shadow following the target's alpha. Persona style: hard, offset,
// accent-colored (no blur).
DropShadow {
    required property var target
    readonly property bool persona: Persona.shapes
    source: target
    anchors.fill: source
    radius: persona ? 0 : 8
    samples: persona ? 1 : radius * 2 + 1
    horizontalOffset: persona ? Persona.shadowOffset : 0
    verticalOffset: persona ? Persona.shadowOffset : 0
    color: persona ? Persona.shadowColor : Appearance.colors.colShadow
    transparentBorder: true
}
