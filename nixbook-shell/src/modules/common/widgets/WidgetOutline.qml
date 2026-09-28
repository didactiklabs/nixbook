import QtQuick
import qs.modules.common

/**
 * Persona outline for desktop widget cards: the panels' bold border
 * (Persona.outlineColor, Royal gold in p5) drawn over a card, above its
 * content. Pairs with WidgetShadow's hard accent shadow; same placement as
 * it (a sibling of the card or a child of it). Rectangle targets only.
 */
Rectangle {
    required property Item target
    anchors.fill: target
    z: 10
    visible: Persona.shapes
    radius: target.radius
    color: "transparent"
    border.width: Persona.borderWidth
    border.color: Persona.outlineColor
}
