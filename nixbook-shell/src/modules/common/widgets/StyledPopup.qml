import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0
    // Extra slack around the popup that still counts as hovering it (and
    // takes pointer input), capped at the window's own shadow padding.
    property real hoverMargin: 0
    readonly property bool hovered: root.item?.hovered ?? false
    active: root.hoverTarget && root.hoverTarget.containsMouse && Config.options.bar.tooltips.enable

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    component: PanelWindow {
        id: popupWindow

        // Bring contentItem reference into this scope
        property Item innerContent: root.contentItem

        color: "transparent"
        anchors.left: root.barEdge !== "right"
        anchors.right: root.barEdge === "right"
        anchors.top: root.barEdge !== "bottom"
        anchors.bottom: root.barEdge === "bottom"

        // Persona style: room for the slanted frame + hard shadow.
        readonly property real personaPad: Persona.shapes ? 16 : 0
        implicitWidth: popupBackground.implicitWidth + (Appearance.sizes.elevationMargin + personaPad) * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + (Appearance.sizes.elevationMargin + personaPad) * 2 + root.popupBackgroundMargin

        readonly property real centerOffsetX: {
            const base = root.QsWindow?.mapFromItem(
                root.hoverTarget,
                (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
            ).x ?? 0
            const margin = Appearance.sizes.elevationMargin
            const maxLeft = popupWindow.screen.width - popupBackground.implicitWidth - margin - 10
            return Math.max(margin, Math.min(base, maxLeft))
        }
        readonly property real centerOffsetY: {
            const base = root.QsWindow?.mapFromItem(
                root.hoverTarget,
                0, (root.hoverTarget.height - popupBackground.implicitHeight) / 2
            ).y ?? 0
            const margin = Appearance.sizes.elevationMargin
            const maxTop = popupWindow.screen.height - popupBackground.implicitHeight - margin - 15
            return Math.max(margin, Math.min(base, maxTop))
        }

        readonly property bool hovered: popupHover.hovered

        mask: Region {
            item: hoverArea
        }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        margins {
            left: {
                if (root.barEdge === "right") return 0
                if (root.barEdge === "left") return root.barThickness
                return centerOffsetX 
            }
            top: {
                if (root.barEdge === "bottom") return 0
                if (root.barEdge === "top") return root.barThickness
                return centerOffsetY
            }
            right: root.barEdge === "right" ? root.barThickness : 0
            bottom: root.barEdge === "bottom" ? root.barThickness : 0
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        // Persona style: the whole popup "slams" in (scale + tilt + slide,
        // overshooting curve) each time it opens; the window is created per
        // open by the LazyLoader, so onCompleted is the open moment.
        Item {
            id: slamLayer
            anchors.fill: parent
            property real t: Persona.motion ? 0 : 1
            // Input only arrives inside the mask, so this is hover over hoverArea.
            HoverHandler {
                id: popupHover
            }
            Component.onCompleted: if (Persona.motion) slamAnim.start()
            NumberAnimation {
                id: slamAnim
                target: slamLayer
                property: "t"
                from: 0
                to: 1
                duration: 340
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Persona.curves.slam
            }
            opacity: Math.min(1, slamLayer.t * 2.5)
            transform: [
                Scale {
                    origin.x: slamLayer.width / 2
                    origin.y: slamLayer.height / 2
                    xScale: 1.08 - 0.08 * slamLayer.t
                    yScale: 1.08 - 0.08 * slamLayer.t
                },
                Rotation {
                    origin.x: slamLayer.width / 2
                    origin.y: slamLayer.height / 2
                    angle: -4 * (1 - slamLayer.t)
                },
                Translate {
                    x: -18 * (1 - slamLayer.t)
                }
            ]

        Item {
            id: hoverArea
            anchors.fill: popupBackground
            anchors.margins: -Math.min(root.hoverMargin, Appearance.sizes.elevationMargin + popupWindow.personaPad)
        }

        StyledRectangularShadow {
            visible: !Persona.shapes
            target: popupBackground
        }

        PersonaFrame {
            visible: Persona.shapes
            anchors.fill: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: 8
            // The Persona frame leans (sheared about its vertical centre), so
            // tall popups need more room on the sides or text touches the edge.
            readonly property real hMargin: Persona.shapes ? 8 + 12 : 8 // PersonaFrame.maxLean

            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + popupWindow.personaPad + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + popupWindow.personaPad + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + popupWindow.personaPad + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + popupWindow.personaPad + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }

            // Use local reference instead of crossing LazyLoader scope boundary
            implicitWidth: (popupWindow.innerContent?.implicitWidth ?? 0) + hMargin * 2
            implicitHeight: (popupWindow.innerContent?.implicitHeight ?? 0) + margin * 2

            color: Persona.shapes ? "transparent" : Appearance.colors.colLayer1Base
            radius: Appearance.rounding.normal + 4
            border.width: Persona.shapes ? 0 : 1
            border.color: Appearance.colors.colLayer0Border

            // Reparent content here once the window is ready
            Component.onCompleted: {
                if (popupWindow.innerContent) {
                    popupWindow.innerContent.parent = popupBackground
                    popupWindow.innerContent.anchors.centerIn = popupBackground
                }
            }
        }
        } // slamLayer
    }
}