import QtQuick
import qs.modules.common

/**
 * Hover / press feedback for bar widgets and dock buttons:
 *  - a spring "lift" while hovered and a "squish" while pressed (M3 Expressive
 *    fast spatial curve, so the release overshoots a little);
 *  - a state layer: a soft pill behind the widget while hovered, stronger while
 *    pressed, with a ripple spreading from the press point (Persona style: the
 *    accent colour, hard corners);
 *  - optionally a vertical lift on hover and `bounce()` (dock: launch/activate).
 *
 * Drop it inside a widget Loader (targets the loaded item) or any Item (targets
 * that item). It only adds passive pointer handlers on a transparent overlay,
 * so the widget's own MouseAreas, hover popups, wheel handling and drags keep
 * working untouched. The state layer is drawn *under* the widget (a sibling at
 * z -1), so the content stays crisp above it. Scale effects are sized in pixels
 * rather than as a fixed factor, so a wide media/title widget moves as little
 * as a small icon.
 */
Item {
    id: root
    anchors.fill: parent

    property Item target: parent?.item !== undefined ? parent.item : parent
    property real hoverGrowPx: 2.5
    property real pressShrinkPx: 4
    property real maxHoverScale: 1.08
    property real minPressScale: 0.88
    // Vertical lift while hovered, in px (negative = up). Dock icons use it.
    property real hoverLiftPx: 0

    // State layer. Skipped for targets that draw their own hover feedback:
    // RippleButtons (hover background + ripple) and widgets that declare
    // `property bool ownHoverFeedback: true` (e.g. Workspaces).
    property bool stateLayer: root.target?.rippleEnabled === undefined && root.target?.ownHoverFeedback !== true
    property real statePaddingX: 5
    property real statePaddingY: 2
    readonly property color stateColor: Persona.shapes ? Persona.stripeColor : Appearance.colors.colOnLayer1

    readonly property real extent: Math.max(1, Math.max(root.target?.width ?? 0, root.target?.height ?? 0))
    readonly property real hoverScale: Math.min(root.maxHoverScale, 1 + 2 * root.hoverGrowPx / root.extent)
    readonly property real pressScale: Math.max(root.minPressScale, 1 - 2 * root.pressShrinkPx / root.extent)

    readonly property bool active: root.target !== null && (root.target?.enabled ?? true) && (root.target?.visible ?? true)
    readonly property bool hovered: hover.hovered && root.active
    readonly property bool pressed: press.active && root.active
    property real fxScale: root.pressed ? root.pressScale : root.hovered ? root.hoverScale : 1

    Behavior on fxScale {
        NumberAnimation {
            duration: root.pressed ? 110 : 340
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.pressed ? Appearance.animationCurves.expressiveEffects : Appearance.animationCurves.expressiveFastSpatial
        }
    }

    Binding {
        target: root.target
        property: "scale"
        value: root.fxScale
        when: root.target !== null
        restoreMode: Binding.RestoreBindingOrValue
    }

    // Persona style: a small tilt on hover (and a snap back on press).
    property real fxRotation: (Persona.motion && root.hovered && !root.pressed) ? -3 : 0
    Behavior on fxRotation {
        NumberAnimation {
            duration: 260
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Persona.curves.slam
        }
    }
    Binding {
        target: root.target
        property: "rotation"
        value: root.fxRotation
        when: root.target !== null && Persona.motion
        restoreMode: Binding.RestoreBindingOrValue
    }

    // ---- lift + bounce (only when used: the target's transform is replaced)
    property real liftY: (root.hovered && !root.pressed) ? root.hoverLiftPx : 0
    Behavior on liftY {
        NumberAnimation {
            duration: 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    property real bounceY: 0
    Translate {
        id: liftTranslate
        y: root.liftY + root.bounceY
    }
    Binding {
        target: root.target
        property: "transform"
        value: [liftTranslate]
        when: root.target !== null && root.hoverLiftPx !== 0
        restoreMode: Binding.RestoreBindingOrValue
    }
    // Hop `times` times (dock: 2 when launching an app, 1 when activating it).
    function bounce(times = 1) {
        if (root.hoverLiftPx === 0) return;
        bounceAnim.loops = Math.max(1, times);
        bounceAnim.restart();
    }
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation {
            target: root; property: "bounceY"; to: -9
            duration: 170; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root; property: "bounceY"; to: 0
            duration: 260; easing.type: Easing.OutBounce
        }
    }

    // ---- state layer + ripple, under the widget
    Rectangle {
        id: stateLayerRect
        parent: root.parent
        z: -1
        visible: root.stateLayer && root.target !== null && opacity > 0
        x: (root.target?.x ?? 0) - root.statePaddingX
        y: (root.target?.y ?? 0) - root.statePaddingY
        width: (root.target?.width ?? 0) + root.statePaddingX * 2
        height: (root.target?.height ?? 0) + root.statePaddingY * 2
        radius: Persona.shapes ? Persona.corner : Math.min(height / 2, Appearance.rounding.full)
        color: root.stateColor
        // Persona's accent is darker (P5 red on black): a bit stronger there.
        opacity: (root.pressed ? 0.26 : root.hovered ? 0.14 : 0) + (Persona.shapes && root.hovered ? 0.08 : 0)
        Behavior on opacity {
            NumberAnimation {
                duration: root.pressed ? 90 : 220
                easing.type: Easing.OutCubic
            }
        }
        clip: true

        Rectangle {
            id: ripple
            property real cx: 0
            property real cy: 0
            property real size: 0
            x: cx - size / 2
            y: cy - size / 2
            width: size
            height: size
            radius: size / 2
            color: root.stateColor
            opacity: 0
        }
    }
    ParallelAnimation {
        id: rippleIn
        NumberAnimation {
            target: ripple; property: "size"; from: 0
            to: 2.4 * Math.max(stateLayerRect.width, stateLayerRect.height)
            duration: 420; easing.type: Easing.OutCubic
        }
        NumberAnimation { target: ripple; property: "opacity"; from: 0.45; to: 0.3; duration: 420 }
    }
    NumberAnimation {
        id: rippleOut
        target: ripple; property: "opacity"; to: 0
        duration: 360; easing.type: Easing.OutCubic
    }
    onPressedChanged: {
        if (!root.stateLayer) return;
        if (root.pressed) {
            // PointHandler position is in this item's coordinates, which match
            // the state layer's parent.
            ripple.cx = press.point.position.x - stateLayerRect.x;
            ripple.cy = press.point.position.y - stateLayerRect.y;
            rippleOut.stop();
            rippleIn.restart();
        } else {
            rippleOut.restart();
        }
    }

    HoverHandler {
        id: hover
        enabled: root.target?.enabled ?? true
    }
    PointHandler {
        id: press
        enabled: root.target?.enabled ?? true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    }
}
