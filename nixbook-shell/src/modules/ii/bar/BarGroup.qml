import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property int currentIndex: 0
    property int totalCount: 0
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool paintMaterialPill: false
    property bool paintBackground: true
    property real padding: (root.isMaterial && !root.paintMaterialPill) ? 0 : 5
    property color bgColor: Appearance.colors.colPrimaryContainer

    readonly property color resolvedGroupColor: {
        const name = Config.options.bar.groupColor
        const key = `col${name.charAt(0).toUpperCase()}${name.slice(1)}`
        const base = Appearance.colors[key] ?? Appearance.colors.colLayer1
        // Liquid Glass: a capsule lying on the bar's own background is one
        // clear tonal step above it (layer 1 is nearly the bar's layer 0, so
        // the groups read as muddy boxes); a floating one keeps its colour.
        return Appearance.glass.enabled && root.onBarBackground
            ? ColorUtils.mix(base, Appearance.colors.colOnLayer0, 0.92)
            : base
    }
    // The bar draws a background of its own behind the groups (not Islands,
    // M3, or the background switched off).
    readonly property bool onBarBackground: Config.options.bar.showBackground
        && Config.options.bar.cornerStyle !== 2 && !root.isMaterial

    // A widget with nothing to show (hidden, or no width: Phone Connect
    // with no phone, the VPN while off…) leaves no empty capsule behind: the
    // group collapses and gives back the layout's spacing. The group itself
    // stays visible (hiding it would hide the widget too, and it could
    // never say it has something to show again).
    readonly property Item widget: {
        const first = gridLayout.children[0];
        return first?.item !== undefined ? first.item : (first ?? null);
    }
    readonly property bool empty: root.widget !== null && (!root.widget.visible
        || (root.vertical ? root.widget.implicitHeight : root.widget.implicitWidth) < 1)
    readonly property real layoutSpacing: root.parent?.spacing ?? 0
    Layout.leftMargin: root.empty && !root.vertical ? -root.layoutSpacing : 0
    Layout.topMargin: root.empty && root.vertical ? -root.layoutSpacing : 0

    readonly property bool isSegmented: Config.options?.bar.borderless === "segmented"
    readonly property bool isPanel: Config.options.bar.cornerStyle === 4
    readonly property real panelRadius: Appearance.rounding.unsharpenmore + 4

    readonly property real fullRadius: root.isPanel ? root.panelRadius : height / 2
    readonly property real midRadius: root.isPanel
        ? root.panelRadius
        : root.isSegmented
            ? 0
            : (Config.options.bar.cornerStyle === 2 ? Appearance.rounding.unsharpenmore + 2 : Appearance.rounding.unsharpenmore)

    property real startRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === 0) return fullRadius;
        return midRadius;
    }
    property real endRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === totalCount - 1) return fullRadius;
        return midRadius;
    }

    implicitWidth: root.empty && !vertical ? 0 : vertical && root.isMaterial ? Appearance.sizes.baseVerticalBarWidth - 6 : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: root.empty && vertical ? 0 : vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    default property alias items: gridLayout.children

    // The box the group paints, and its slant: InteractionFx keeps its
    // hover/press state layer inside it, slanted the same way.
    readonly property Item interactionBounds: background
    readonly property real interactionSkew: background.personaSkew

    Rectangle {
        id: background
        // Persona style: slanted group background (P5 HUD); widgets stay
        // straight. Horizontal bars only.
        readonly property real personaSkew: (Persona.shapes && !root.vertical) ? Math.tan(-15 * Math.PI / 180) : 0
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, background.personaSkew, 0, -background.personaSkew * background.height / 2,
                                 0, 1, 0, 0,
                                 0, 0, 1, 0,
                                 0, 0, 0, 1)
        }
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        visible: !root.empty
        color: !root.paintBackground
            ? "transparent"
            : (root.isMaterial && !root.paintMaterialPill)
                ? "transparent"
                : (root.isMaterial && root.paintMaterialPill)
                    ? root.bgColor
                    : (Config.options?.bar.borderless === "transparent"
                        ? "transparent"
                        : Config.options.bar.cornerStyle === 2 || (Config.options?.bar.borderless === "segmented" && !Config.options.bar.showBackground)
                            ? Appearance.colors.colLayer0
                            : root.resolvedGroupColor)

        border.width: root.paintBackground && root.isSegmented && !root.isMaterial ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        topLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.startRadius)
        bottomLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.vertical ? root.endRadius : root.startRadius)
        topRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.vertical ? root.startRadius : root.endRadius)
        bottomRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.endRadius)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Liquid Glass capsule edge (static: the bar draws nothing more).
        GlassRim {
            anchors.fill: parent
            outline: !root.onBarBackground
            visible: Appearance.glass.enabled && background.color.a > 0.02 && width > 4 && height > 4
            topLeftRadius: background.topLeftRadius
            topRightRadius: background.topRightRadius
            bottomLeftRadius: background.bottomLeftRadius
            bottomRightRadius: background.bottomRightRadius
            radius: background.topLeftRadius
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
    }
}