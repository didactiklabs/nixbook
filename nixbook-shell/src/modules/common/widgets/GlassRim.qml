import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * The Liquid Glass edge of a surface (macOS Tahoe): a dark hairline outside,
 * a light inner edge, a brighter glint along the top and a faint sheen
 * fading down from it. Laid over a rounded Rectangle (`anchors.fill` it,
 * same `radius`); tuned by Appearance.glass (themes.json style.glass).
 *
 * Plain Rectangles only, drawn with the surface and never animated: no
 * layer, no blur, no extra frames. StyledRectangularShadow adds one to its
 * target by itself; put one by hand on surfaces without a shadow.
 */
Item {
    id: root
    property real radius: 0
    // The surface's own corners when they differ (per-corner radii).
    property real topLeftRadius: root.radius
    property real topRightRadius: root.radius
    property real bottomLeftRadius: root.radius
    property real bottomRightRadius: root.radius
    property bool sheen: true
    // The dark outer hairline: for a surface floating over something else;
    // off for a capsule lying on its own panel (the bar's groups).
    property bool outline: true

    readonly property var glass: Appearance.glass
    visible: root.glass.enabled && root.width > 4 && root.height > 4
    z: 1000

    // Outer hairline.
    Rectangle {
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: "transparent"
        border.width: 1
        border.color: ColorUtils.transparentize("#000000", 1 - root.glass.hairline)
        visible: root.outline && root.glass.hairline > 0
    }

    // Light inner edge, all around.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        topLeftRadius: Math.max(0, root.topLeftRadius - 1)
        topRightRadius: Math.max(0, root.topRightRadius - 1)
        bottomLeftRadius: Math.max(0, root.bottomLeftRadius - 1)
        bottomRightRadius: Math.max(0, root.bottomRightRadius - 1)
        color: "transparent"
        border.width: 1
        border.color: ColorUtils.transparentize(root.glass.rimColor, 1 - root.glass.edge)
        visible: root.glass.edge > 0
    }

    // Sheen: light falling on the top of the glass.
    Rectangle {
        visible: root.sheen && root.glass.sheen > 0
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 1
        }
        height: Math.min(parent.height * 0.4, 56)
        topLeftRadius: Math.max(0, root.topLeftRadius - 1)
        topRightRadius: Math.max(0, root.topRightRadius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: ColorUtils.transparentize(root.glass.rimColor, 1 - root.glass.sheen) }
            GradientStop { position: 1; color: ColorUtils.transparentize(root.glass.rimColor, 1) }
        }
    }

    // Glint along the top edge, brightest in the middle.
    Rectangle {
        visible: root.glass.rim > 0
        x: Math.min(Math.max(root.topLeftRadius, root.topRightRadius), root.height / 2, root.width / 4) * 0.6
        width: parent.width - 2 * x
        y: 1
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ColorUtils.transparentize(root.glass.rimColor, 1) }
            GradientStop { position: 0.3; color: ColorUtils.transparentize(root.glass.rimColor, 1 - root.glass.rim) }
            GradientStop { position: 0.7; color: ColorUtils.transparentize(root.glass.rimColor, 1 - root.glass.rim) }
            GradientStop { position: 1; color: ColorUtils.transparentize(root.glass.rimColor, 1) }
        }
    }
}
