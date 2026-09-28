import QtQuick
import QtQuick.Effects
import Quickshell
import qs.modules.common

/**
 * Persona-style panel frame, drawn *behind* content (content stays straight
 * and readable): slanted body (shear about the vertical center) with the
 * Persona cut — a large radius on the top-left and bottom-right corners, a
 * small one on the others — a soft accent glow for elevation, a thin tonal
 * outline, the accent slash along the top edge and the halftone art. Static:
 * no per-frame work.
 *
 * Fill the area the panel background would cover:
 *   PersonaFrame { anchors.fill: popupBackground }
 */
Item {
    id: root
    property color color: Persona.frameColor
    property color borderColor: Persona.outlineColor
    property color shadowColor: Persona.elevationColor
    property color accentColor: Persona.stripeColor
    // Lean is capped in pixels so a tall frame stays inside its window margin.
    property real maxLean: 12
    readonly property real skew: {
        const half = Math.max(1, root.height / 2);
        const k = Persona.skew;
        return Math.sign(k) * Math.min(Math.abs(k), root.maxLean / half);
    }
    property bool showShadow: true
    property bool showStripe: true
    property bool showHalftone: Persona.halftone
    // The cut, clamped for small frames.
    readonly property real bigCorner: Math.min(Persona.cornerLarge, root.height / 2, root.width / 2)
    readonly property real smallCorner: Math.min(Persona.corner, root.height / 2, root.width / 2)

    // Shear around the vertical center so the frame leans without drifting.
    transform: Matrix4x4 {
        matrix: Qt.matrix4x4(1, root.skew, 0, -root.skew * root.height / 2,
                             0, 1, 0, 0,
                             0, 0, 1, 0,
                             0, 0, 0, 1)
    }

    RectangularShadow {
        visible: root.showShadow
        anchors.fill: body
        offset: Qt.vector2d(Persona.shadowOffset, Persona.shadowOffset)
        blur: Persona.shadowBlur
        spread: 0
        radius: root.bigCorner
        color: root.shadowColor
        cached: true
    }

    Rectangle {
        id: body
        anchors.fill: parent
        topLeftRadius: root.bigCorner
        bottomRightRadius: root.bigCorner
        topRightRadius: root.smallCorner
        bottomLeftRadius: root.smallCorner
        color: root.color
        border.width: Persona.borderWidth
        border.color: root.borderColor
        clip: true

        PersonaTexture {
            anchors.fill: parent
            anchors.margins: Persona.borderWidth
        }
    }

    // Accent slash along the top edge: a rounded pill, clear of the cut.
    Rectangle {
        visible: root.showStripe
        anchors {
            top: parent.top
            left: parent.left
            topMargin: -height / 2
            leftMargin: Math.max(root.bigCorner, parent.width * 0.08)
        }
        width: Math.max(28, parent.width * 0.28)
        height: 4
        radius: height / 2
        color: root.accentColor
    }
}
