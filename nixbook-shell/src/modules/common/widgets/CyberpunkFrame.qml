import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.functions

/**
 * Cyberpunk 2077 panel frame, drawn *behind* content (Cyberpunk.frames):
 * the in-world screens of the game's UI art (Anna Kuźmińska's device panels
 * and HUD) — a chamfered body (top left and bottom right cut) with a
 * hairline outline in the accent, small notches hanging from the top edge
 * (the jagged edge of its pages), an accent bar on the left under the cut,
 * and a solid marker in the bottom right cut.
 *
 * `full` (the sidebars) adds the screen furniture: a tick ruler down the
 * left edge, a thin rail in the secondary colour along the bottom with a
 * segmented gauge, faint 45° hairlines across the body, and a chamfered tag
 * on the bottom edge (`label`, small caps).
 *
 * All static shapes (GPU, no per-frame work: the sidebars stay mapped).
 *
 *   CyberpunkFrame { anchors.fill: parent; z: -1; color: Appearance.colors.colLayer0 }
 */
Item {
    id: root
    property color color: Appearance.colors.colLayer0
    property color lineColor: Cyberpunk.line
    property color railColor: Cyberpunk.rail
    property real cut: 14
    property real lineOpacity: 0.55
    property bool full: false
    property string label: ""
    property bool showNotches: true

    readonly property color hairline: ColorUtils.transparentize(root.lineColor, 1 - root.lineOpacity)
    readonly property real w: root.width
    readonly property real h: root.height

    // Body + outline.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.color
            strokeColor: root.hairline
            strokeWidth: 1
            joinStyle: ShapePath.MiterJoin
            startX: root.cut; startY: 0.5
            PathLine { x: root.w - 0.5; y: 0.5 }
            PathLine { x: root.w - 0.5; y: root.h - root.cut }
            PathLine { x: root.w - root.cut; y: root.h - 0.5 }
            PathLine { x: 0.5; y: root.h - 0.5 }
            PathLine { x: 0.5; y: root.cut }
            PathLine { x: root.cut; y: 0.5 }
        }
    }

    // Faint 45° hairlines across the body (the pages' background), clipped
    // to the frame's box.
    Item {
        visible: root.full
        anchors.fill: parent
        clip: true
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: ColorUtils.transparentize(root.lineColor, 0.93)
                strokeWidth: 1
                PathMultiline {
                    paths: [
                        [Qt.point(root.w * 0.15, root.h), Qt.point(root.w * 0.15 + root.h, 0)],
                        [Qt.point(-root.w * 0.4, root.h * 0.7), Qt.point(-root.w * 0.4 + root.h * 0.7, 0)],
                    ]
                }
            }
        }
    }

    // Notches hanging from the top edge (and one from the bottom): small
    // trapezoids in the accent.
    Shape {
        visible: root.showNotches && root.w > 120
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.lineColor
            strokeColor: "transparent"
            PathMultiline {
                // Closed by the fill: each path is one notch.
                paths: {
                    const notch = (x, len, depth, down) => {
                        const y0 = down ? 0 : root.h;
                        const y1 = down ? depth : root.h - depth;
                        return [Qt.point(x, y0), Qt.point(x + len, y0), Qt.point(x + len - depth, y1), Qt.point(x + depth, y1), Qt.point(x, y0)];
                    };
                    const w = root.w;
                    const out = [
                        notch(root.cut + w * 0.06, Math.min(46, w * 0.12), 4, true),
                        notch(w * 0.52, Math.min(22, w * 0.06), 3, true),
                        notch(w - root.cut - Math.min(70, w * 0.18) - 10, Math.min(70, w * 0.18), 5, true),
                    ];
                    if (root.full)
                        out.push(notch(w * 0.34, Math.min(30, w * 0.08), 3, false));
                    return out;
                }
            }
        }
    }

    // The accent bar under the top-left cut and the marker in the bottom
    // right cut.
    Rectangle {
        x: 0; y: root.cut + 8
        width: 3
        height: Math.min(34, root.h * 0.3)
        color: root.lineColor
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.lineColor
            strokeColor: "transparent"
            startX: root.w - 3; startY: root.h - root.cut + 3
            PathLine { x: root.w - 3; y: root.h - 3 }
            PathLine { x: root.w - root.cut + 3; y: root.h - 3 }
            PathLine { x: root.w - 3; y: root.h - root.cut + 3 }
        }
    }

    // ---------------------------------------------------------------- full
    // Tick ruler down the left edge.
    Shape {
        visible: root.full
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: ColorUtils.transparentize(root.lineColor, 0.62)
            strokeWidth: 1
            PathMultiline {
                paths: {
                    const out = [];
                    const top = root.cut + 56;
                    const bottom = Math.max(top, root.h * 0.62);
                    for (let y = top, k = 0; y <= bottom; y += 8, k++) {
                        const len = k % 5 === 0 ? 7 : 3;
                        out.push([Qt.point(1, Math.round(y) + 0.5), Qt.point(1 + len, Math.round(y) + 0.5)]);
                    }
                    return out;
                }
            }
        }
    }

    // A rail in the secondary colour along the bottom, a segmented gauge on it.
    Item {
        visible: root.full && root.w > 200
        x: root.w * 0.46
        y: root.h - 6
        width: root.w - root.cut - 10 - x
        height: 3
        Rectangle {
            width: parent.width
            height: 1
            color: ColorUtils.transparentize(root.railColor, 0.35)
        }
        Row {
            y: -3
            spacing: 2
            Repeater {
                model: 9
                delegate: Rectangle {
                    required property int index
                    width: 5
                    height: 3
                    color: index < 6 ? root.lineColor : ColorUtils.transparentize(root.lineColor, 0.7)
                }
            }
        }
    }

    // The tag on the bottom edge: a chamfered outline, small caps.
    Item {
        visible: root.full && root.label !== "" && root.w > 160
        x: 14
        y: root.h - height
        width: tagText.implicitWidth + 20
        height: 12
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root.color
                strokeColor: ColorUtils.transparentize(root.railColor, 0.3)
                strokeWidth: 1
                joinStyle: ShapePath.MiterJoin
                startX: 0.5; startY: 12
                PathLine { x: 0.5; y: 0.5 }
                PathLine { x: tagText.implicitWidth + 14; y: 0.5 }
                PathLine { x: tagText.implicitWidth + 19.5; y: 6 }
                PathLine { x: tagText.implicitWidth + 19.5; y: 12 }
            }
        }
        Text {
            id: tagText
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 0.5
            text: root.label.toUpperCase()
            font.family: Cyberpunk.font
            font.pixelSize: 8
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: root.railColor
            renderType: Text.NativeRendering
        }
    }
}
