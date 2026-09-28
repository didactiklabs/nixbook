import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * Persona accents for desktop widget cards, drawn over a card, above its
 * content: no bold outline (it made every card loud), just a hairline edge,
 * a slanted accent bar down the left side and a cut accent corner at the top
 * right, in the variant's accent (Persona.stripeColor: P5 red, P3R cyan, P4
 * yellow). Pairs with WidgetShadow's short hard shadow; same placement as it
 * (a sibling of the card or a child of it). Rectangle targets only.
 */
Item {
    id: root
    required property Item target
    anchors.fill: target
    z: 10
    visible: Persona.shapes

    // Hairline edge.
    Rectangle {
        anchors.fill: parent
        radius: root.target.radius
        color: "transparent"
        border.width: 1
        border.color: ColorUtils.transparentize(Persona.frameBorderColor, 0.82)
    }

    // Slanted accent bar along the left edge (the Royal menus' tab).
    Rectangle {
        x: 5
        y: parent.height * 0.18
        width: 4
        height: Math.min(56, parent.height * 0.4)
        radius: 1
        color: Persona.stripeColor
        // Leans like the panels (about its own centre: stays in the card).
        rotation: -Persona.skewDeg
    }

    // Cut corner: a small accent triangle at the top right.
    Canvas {
        id: corner
        readonly property color accent: Persona.stripeColor
        anchors.top: parent.top
        anchors.right: parent.right
        width: 18
        height: 18
        onAccentChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = corner.accent;
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width, height);
            ctx.closePath();
            ctx.fill();
        }
    }
}
