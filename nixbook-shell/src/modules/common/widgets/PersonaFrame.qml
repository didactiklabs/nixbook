import QtQuick
import Quickshell
import qs.modules.common

/**
 * Persona-style panel frame, drawn *behind* content (content stays straight
 * and readable): slanted body (shear about the vertical center), hard
 * accent-colored offset shadow, bold border (Royal gold in p5), accent slash
 * along the top edge and a halftone corner. Only rectangles + one tiled
 * image, all static — no per-frame work.
 *
 * Fill the area the panel background would cover:
 *   PersonaFrame { anchors.fill: popupBackground }
 */
Item {
    id: root
    property color color: Persona.frameColor
    property color borderColor: Persona.outlineColor
    property color shadowColor: Persona.shadowColor
    property color accentColor: Persona.stripeColor
    // Lean is capped in pixels so a tall frame stays inside its window margin.
    property real maxLean: 12
    readonly property real skew: {
        const half = Math.max(1, root.height / 2);
        const k = Persona.skew;
        return Math.sign(k) * Math.min(Math.abs(k), root.maxLean / half);
    }
    property bool showShadow: true
    property real shadowOffset: Persona.shadowOffset
    property real shadowOpacity: 1
    property real borderWidth: Persona.borderWidth
    property bool showStripe: true
    property bool showHalftone: Persona.halftone

    // Shear around the vertical center so the frame leans without drifting.
    transform: Matrix4x4 {
        matrix: Qt.matrix4x4(1, root.skew, 0, -root.skew * root.height / 2,
                             0, 1, 0, 0,
                             0, 0, 1, 0,
                             0, 0, 0, 1)
    }

    Rectangle {
        visible: root.showShadow
        x: root.shadowOffset
        y: root.shadowOffset
        width: parent.width
        height: parent.height
        radius: Persona.corner
        color: root.shadowColor
        opacity: root.shadowOpacity
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Persona.corner
        color: root.color
        border.width: root.borderWidth
        border.color: root.borderColor

        // No `clip`: the art already fills the body exactly (a cropped
        // Image), and a clip under the shear is a stencil pass every frame.
        PersonaTexture {
            anchors.fill: parent
            anchors.margins: root.borderWidth
        }
    }

    // Accent slash along the top edge.
    Rectangle {
        visible: root.showStripe
        anchors {
            top: parent.top
            left: parent.left
            topMargin: -Math.max(root.borderWidth, 1)
            leftMargin: parent.width * 0.08
        }
        width: Math.max(28, parent.width * 0.28)
        height: Math.max(root.borderWidth, 1) * 2 + 2
        color: root.accentColor
    }
}
