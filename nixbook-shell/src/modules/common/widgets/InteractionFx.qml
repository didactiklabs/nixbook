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
 * z -1), so the content stays crisp above it. Inside a container that declares
 * `interactionBounds` (the box it paints, e.g. BarGroup's background) and
 * `interactionSkew`, the state layer is kept within that box (2 px in) and
 * slanted like it, so it never spills past the box's edges. Scale effects are sized in pixels
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

    // The enclosing container's box (see header), looked up a few levels up.
    readonly property Item boundsHost: {
        let p = root.parent;
        for (let i = 0; p && i < 5; i++, p = p.parent) {
            if (p.interactionBounds !== undefined)
                return p;
        }
        return null;
    }
    readonly property real boundsInset: 2
    // That box in the state layer's coordinates (its unslanted geometry),
    // refreshed when the pointer arrives: layouts move widgets around.
    property rect bounds: Qt.rect(0, 0, 0, 0)
    function updateBounds() {
        const host = root.boundsHost;
        const box = host?.interactionBounds;
        const layerParent = stateLayerRect.parent;
        if (!box || !layerParent) {
            root.bounds = Qt.rect(0, 0, 0, 0);
            return;
        }
        const r = host.mapToItem(layerParent, box.x, box.y, box.width, box.height);
        const i = root.boundsInset;
        root.bounds = Qt.rect(r.x + i, r.y + i, Math.max(0, r.width - 2 * i), Math.max(0, r.height - 2 * i));
    }
    onHoveredChanged: if (root.hovered) root.updateBounds()

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
        // The widget plus padding, clipped to the container's box.
        readonly property bool bounded: root.bounds.width > 0 && root.bounds.height > 0
        readonly property real wantLeft: (root.target?.x ?? 0) - root.statePaddingX
        readonly property real wantTop: (root.target?.y ?? 0) - root.statePaddingY
        readonly property real wantRight: (root.target?.x ?? 0) + (root.target?.width ?? 0) + root.statePaddingX
        readonly property real wantBottom: (root.target?.y ?? 0) + (root.target?.height ?? 0) + root.statePaddingY
        x: bounded ? Math.max(wantLeft, root.bounds.x) : wantLeft
        y: bounded ? Math.max(wantTop, root.bounds.y) : wantTop
        width: Math.max(0, (bounded ? Math.min(wantRight, root.bounds.x + root.bounds.width) : wantRight) - x)
        height: Math.max(0, (bounded ? Math.min(wantBottom, root.bounds.y + root.bounds.height) : wantBottom) - y)
        radius: Math.min(height / 2, Persona.shapes ? Persona.corner : Appearance.rounding.full)
        // Slanted like the container (same shear, about the vertical center).
        readonly property real skew: root.boundsHost?.interactionSkew ?? 0
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, stateLayerRect.skew, 0, -stateLayerRect.skew * stateLayerRect.height / 2,
                                 0, 1, 0, 0,
                                 0, 0, 1, 0,
                                 0, 0, 0, 1)
        }
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
