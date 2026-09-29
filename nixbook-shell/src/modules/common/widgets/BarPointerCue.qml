import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * What the pointer can do on a bar widget, shown while it hovers it — the
 * bar's pointer language:
 *   accent notch (on the side the popup opens from)  hovering shows a popup
 *   hand cursor + soft state layer                     clicking does something
 *   neither                                            nothing happens
 * StyledPopup puts one on its hoverTarget; a clickable widget without a
 * popup and without a hover state of its own adds one itself:
 *   BarPointerCue { target: mouseArea }
 * Two plain rectangles, hidden (not just transparent) at rest.
 */
Item {
    id: root
    // A MouseArea (containsMouse, cursorShape).
    required property Item target
    // The notch: a popup opens from this widget.
    property bool popup: false
    // The state layer: shown on a target with the hand cursor, unless it
    // already shows its own hover state.
    property bool tint: root.target?.cursorShape === Qt.PointingHandCursor
    property bool active: true
    readonly property bool shown: root.active && (root.target?.containsMouse ?? false)

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }

    parent: root.target
    anchors.fill: parent
    z: 100
    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        visible: root.tint
        anchors.fill: parent
        anchors.margins: root.barVertical ? 2 : 0
        anchors.topMargin: root.barVertical ? 2 : 4
        anchors.bottomMargin: root.barVertical ? 2 : 4
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.92)
    }

    Rectangle {
        visible: root.popup
        property real length: root.shown ? 16 : 6
        Behavior on length {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        width: root.barVertical ? 3 : length
        height: root.barVertical ? length : 3
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
        anchors {
            horizontalCenter: root.barVertical ? undefined : parent.horizontalCenter
            verticalCenter: root.barVertical ? parent.verticalCenter : undefined
            top: root.barEdge === "bottom" ? parent.top : undefined
            bottom: root.barEdge === "top" ? parent.bottom : undefined
            left: root.barEdge === "right" ? parent.left : undefined
            right: root.barEdge === "left" ? parent.right : undefined
            margins: 1
        }
    }
}
