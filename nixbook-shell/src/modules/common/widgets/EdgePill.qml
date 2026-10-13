import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * The pill an edge handle draws (dock and sidebar handles): a thin capsule
 * at rest that, hovered, swells into an accent-coloured tab with a chevron
 * pointing to where the panel comes from, Noctalia-style. A shine runs along
 * it once each time it (re)appears. Square and slanted under Persona.
 * Purely visual: the owner places it and gives it `shown` and `hovered`.
 */
Item {
    id: root
    property bool vertical: false
    property bool shown: true
    property bool hovered: false
    // Material symbol shown on the hovered tab, e.g. "keyboard_arrow_up".
    property string icon: ""

    property real restLength: 48
    property real restThickness: 5
    property real hoverLength: 72
    property real hoverThickness: 14

    readonly property real length: hovered ? hoverLength : restLength
    readonly property real thickness: hovered ? hoverThickness : restThickness

    implicitWidth: vertical ? hoverThickness : hoverLength
    implicitHeight: vertical ? hoverLength : hoverThickness

    onShownChanged: if (shown) shine.restart()

    Item {
        id: body
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.length
        height: root.vertical ? root.length : root.thickness
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.4
        transform: Matrix4x4 {
            readonly property real k: Persona.shapes && !root.vertical ? Persona.skew * 2 : 0
            matrix: Qt.matrix4x4(1, k, 0, -k * body.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        }

        Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on height { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        // Outline outside the fill, so the pill reads on light and dark
        // wallpapers alike; an accent halo while hovered.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + (root.hovered ? 10 : 3)
            height: parent.height + (root.hovered ? 10 : 3)
            radius: Persona.shapes ? 0 : Math.min(width, height) / 2
            color: root.hovered
                ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        Rectangle {
            id: pill
            anchors.fill: parent
            radius: Persona.shapes ? 0 : Math.min(width, height) / 2
            clip: true
            color: root.hovered
                ? Appearance.colors.colPrimary
                : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.3)
            Behavior on color { ColorAnimation { duration: 180 } }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.icon.length > 0
                text: root.icon
                iconSize: root.hoverThickness - 2
                color: Appearance.m3colors.m3onPrimary
                opacity: root.hovered && pill.width >= root.hoverThickness - 1 && pill.height >= root.hoverThickness - 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            // Shine that runs along the pill once as it appears
            Rectangle {
                id: shineBar
                width: root.vertical ? pill.width : pill.width * 0.45
                height: root.vertical ? pill.height * 0.45 : pill.height
                x: root.vertical ? 0 : -width
                y: root.vertical ? -height : 0
                opacity: 0
                gradient: Gradient {
                    orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Appearance.colors.colPrimary }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            SequentialAnimation {
                id: shine
                PauseAnimation { duration: 200 }
                PropertyAction { target: shineBar; property: "opacity"; value: 1 }
                NumberAnimation {
                    target: shineBar; property: root.vertical ? "y" : "x"
                    from: root.vertical ? -shineBar.height : -shineBar.width
                    to: root.vertical ? pill.height : pill.width
                    duration: 650; easing.type: Easing.InOutQuad
                }
                PropertyAction { target: shineBar; property: "opacity"; value: 0 }
            }
        }
    }
}
