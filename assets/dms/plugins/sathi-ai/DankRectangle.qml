import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: root

    property color color: Theme.surfaceContainer
    property color borderColor: Theme.outlineMedium
    property real borderWidth: 1
    property real radius: Theme.cornerRadius
    property color overlayColor: "transparent"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: root.borderColor
            strokeWidth: root.borderWidth

            startX: root.radius
            startY: 0

            PathLine { x: root.width - root.radius; y: 0 }
            PathQuad { x: root.width; y: root.radius; controlX: root.width; controlY: 0 }
            PathLine { x: root.width; y: root.height - root.radius }
            PathQuad { x: root.width - root.radius; y: root.height; controlX: root.width; controlY: root.height }
            PathLine { x: root.radius; y: root.height }
            PathQuad { x: 0; y: root.height - root.radius; controlX: 0; controlY: root.height }
            PathLine { x: 0; y: root.radius }
            PathQuad { x: root.radius; y: 0; controlX: 0; controlY: 0 }
        }

        ShapePath {
            fillColor: root.overlayColor
            strokeColor: "transparent"
            strokeWidth: 0

            startX: root.radius
            startY: 0

            PathLine { x: root.width - root.radius; y: 0 }
            PathQuad { x: root.width; y: root.radius; controlX: root.width; controlY: 0 }
            PathLine { x: root.width; y: root.height - root.radius }
            PathQuad { x: root.width - root.radius; y: root.height; controlX: root.width; controlY: root.height }
            PathLine { x: root.radius; y: root.height }
            PathQuad { x: 0; y: root.height - root.radius; controlX: 0; controlY: root.height }
            PathLine { x: 0; y: root.radius }
            PathQuad { x: root.radius; y: 0; controlX: 0; controlY: 0 }
        }
    }
}
