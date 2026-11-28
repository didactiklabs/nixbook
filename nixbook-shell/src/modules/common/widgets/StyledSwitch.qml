import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// A macOS (Tahoe) switch: the accent track when on, a white lozenge knob
// that stretches while pressed.
Switch {
    id: root
    property real scale: 0.75
    implicitHeight: 30 * root.scale
    implicitWidth: 52 * root.scale

    property color activeColor: Appearance?.colors.colPrimary ?? "#cbc4cb"
    // Off: a neutral track the white knob stands out on, in light palettes too.
    property color inactiveColor: Appearance.m3colors.darkmode
        ? (Appearance?.m3colors.m3surfaceBright ?? "#3a3939")
        : ColorUtils.mix(Appearance.m3colors.m3outline, Appearance.m3colors.m3surfaceContainerHighest, 0.45)
    property color knobColor: "#ffffff"

    PointingHandInteraction {}

    background: Rectangle {
        width: parent.width
        height: parent.height
        radius: Appearance?.rounding.full ?? 9999
        color: root.checked ? root.activeColor : root.inactiveColor

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, Appearance.m3colors.darkmode ? 0.25 : 0.06)
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    indicator: Rectangle {
        readonly property real thumbHeight: 26 * root.scale
        readonly property real thumbWidth: 32 * root.scale
        readonly property real pad: 2 * root.scale
        readonly property real stretchExtra: 5 * root.scale

        width: (root.pressed || root.down)
            ? thumbWidth + stretchExtra
            : thumbWidth
        height: thumbHeight
        radius: Appearance.rounding.full

        color: root.knobColor

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.35)
            shadowVerticalOffset: 1
            shadowHorizontalOffset: 0
            shadowBlur: 0.35
        }

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.checked
            ? ((root.pressed || root.down)
                ? parent.width - width - pad
                : parent.width - width - pad)
            : pad

        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: 260
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: 140
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
    }
}
