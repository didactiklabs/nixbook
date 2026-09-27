import QtQuick
import QtQuick.Shapes
import "shapes/morph.js" as Morph

/**
 * A Material shape (rounded polygon, morphable). Drawn by a GPU `Shape`
 * (CurveRenderer: anti-aliased curves in a shader) from an SVG path built from
 * the morph's cubics. It used to be a software `Canvas` repainted on the GUI
 * thread on every colour change — every palette change repainted every
 * shape in the shell. Now a colour change only updates the material; the
 * path is rebuilt only while morphing or when the size changes.
 */
Item {
    id: root
    property color color: "#685496"
    property var roundedPolygon: null
    property bool polygonIsNormalized: true
    property real borderWidth: 0
    property color borderColor: color
    property bool debug: false
    property real xOffset: 0
    property real yOffset: 0

    // Internals: size
    property var bounds: roundedPolygon.calculateBounds()
    implicitWidth: bounds[2] - bounds[0]
    implicitHeight: bounds[3] - bounds[1]

    // Internals: anim
    property var prevRoundedPolygon: null
    property double progress: 1
    property var morph: new Morph.Morph(roundedPolygon, roundedPolygon)
    property Animation animation: NumberAnimation {
        duration: 350
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] // Material 3 Expressive fast spatial (https://m3.material.io/styles/motion/overview/specs)
    }

    onRoundedPolygonChanged: {
        delete root.morph;
        root.morph = new Morph.Morph(root.prevRoundedPolygon ?? root.roundedPolygon, root.roundedPolygon);
        morphBehavior.enabled = false;
        root.progress = 0;
        morphBehavior.enabled = true;
        root.progress = 1;
        root.prevRoundedPolygon = root.roundedPolygon;
    }

    Behavior on progress {
        id: morphBehavior
        animation: root.animation
    }

    // SVG path of the current morph state, in item coordinates.
    readonly property string svgPath: {
        if (!root.morph || root.width <= 0 || root.height <= 0)
            return "";
        const cubics = root.morph.asCubics(root.progress);
        if (cubics.length === 0)
            return "";
        const k = root.polygonIsNormalized ? Math.min(root.width, root.height) : 1;
        const ox = root.xOffset, oy = root.yOffset;
        const f = v => (Math.round(v * 100) / 100);
        const X = x => f((x + ox) * k), Y = y => f((y + oy) * k);
        const parts = [`M${X(cubics[0].anchor0X)} ${Y(cubics[0].anchor0Y)}`];
        for (const c of cubics)
            parts.push(`C${X(c.control0X)} ${Y(c.control0Y)} ${X(c.control1X)} ${Y(c.control1Y)} ${X(c.anchor1X)} ${Y(c.anchor1Y)}`);
        parts.push("Z");
        return parts.join("");
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.color
            strokeColor: root.borderColor
            strokeWidth: root.borderWidth > 0 ? root.borderWidth : -1
            PathSvg { path: root.svgPath }
        }
    }
}
