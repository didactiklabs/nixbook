import QtQuick
import QtQuick.Effects
import qs.modules.common

/**
 * Shadow for desktop widget cards, drawn only *outside* the card's shape.
 * The cards are translucent (background.widgets.cardOpacity), so a filled
 * shadow underneath shows through them: StyledRectangularShadow darkens the
 * card (in the Persona style it tints it with the accent glow), and
 * Qt5Compat's DropShadow also re-draws its source, doubling the card's
 * opacity. Here the shadow is cut out by the card's own shape.
 *
 * A Rectangle target is mirrored by a hidden Rectangle, so the textures only
 * re-render on resize; any other target (the cookie clock's shape) is sampled
 * live. Same placement rules as the other shadows: a sibling below the target,
 * or a child with a negative z.
 */
Item {
    id: root
    required property Item target
    readonly property bool persona: Persona.shapes
    readonly property bool rectTarget: root.target.radius !== undefined
    // Room for the blur and offset around the card.
    readonly property real pad: 24

    anchors.fill: target
    anchors.margins: -pad

    // The target's shape, in this item's coordinates.
    Item {
        id: rectShape
        width: root.width
        height: root.height
        visible: false
        layer.enabled: root.rectTarget
        Rectangle {
            x: root.pad
            y: root.pad
            width: root.target.width
            height: root.target.height
            radius: root.rectTarget ? root.target.radius : 0
            color: "black"
        }
    }
    ShaderEffectSource {
        id: liveShape
        width: root.width
        height: root.height
        visible: false
        sourceItem: root.rectTarget ? null : root.target
        sourceRect: Qt.rect(-root.pad, -root.pad, root.width, root.height)
    }
    readonly property Item shape: root.rectTarget ? rectShape : liveShape

    layer.enabled: true
    layer.effect: MultiEffect {
        maskEnabled: true
        maskInverted: true
        maskSource: root.shape
        // The mirrored rectangle is opaque, so 0.5 keeps the shadow under
        // the card's anti-aliased edge (no seam); a live shape carries the
        // card's own (translucent) alpha, so it needs a low threshold.
        maskThresholdMin: root.rectTarget ? 0.5 : 0.01
        maskSpreadAtMin: 0
    }

    MultiEffect {
        anchors.fill: parent
        source: root.shape
        autoPaddingEnabled: false
        shadowEnabled: true
        blurMax: 16
        shadowBlur: 1
        shadowColor: root.persona ? Persona.elevationColor : Appearance.colors.colShadow
        shadowHorizontalOffset: root.persona ? Persona.shadowOffset : 0
        shadowVerticalOffset: root.persona ? Persona.shadowOffset : 1
        shadowOpacity: 1
    }
}
