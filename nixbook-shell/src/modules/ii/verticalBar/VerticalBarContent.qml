import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar

Item {
    id: root
    implicitWidth: Appearance.sizes.verticalBarWidth
    height: parent.height

    readonly property real barPadding: 0
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property bool trayHasItems: SystemTray.items.values.length > 0
    readonly property bool isPanel: Config.options.bar.cornerStyle === 4
    // Space between the widget groups (as BarContent.groupSpacing).
    readonly property real groupSpacing: {
        const style = Config.options?.bar.borderless;
        if (style === "transparent") return -4;
        if (style === "segmented") return root.isPanel ? 3 : -2;
        if (style === "separated") return Appearance.glass.enabled ? 4 : (root.isPanel ? 4 : 2);
        return root.isPanel ? 4 : (Appearance.glass.enabled ? 3 : 2);
    }

    function filterLayout(layout) {
        if (trayHasItems) return layout
        return layout.filter(name => name !== "sysTray")
    }

    readonly property var effectiveLeftLayout:   filterLayout(Config.options.bar.layouts.leftLayout)
    readonly property var effectiveMiddleLayout: filterLayout(Config.options.bar.layouts.middleLayout)
    readonly property var effectiveRightLayout:  filterLayout(Config.options.bar.layouts.rightLayout)

    // bar.verticalReversed (default on): the whole bar read bottom-up — the
    // end of the layout (right: power, battery, tray…) on top, its start
    // (left: launcher, workspaces) at the bottom, every column's order
    // flipped; each widget's own content stays as it is.
    readonly property bool reversed: Config.options.bar.verticalReversed ?? false
    function flipped(layout) {
        return Array.from(layout).reverse();
    }
    readonly property var topLayout: root.reversed ? root.flipped(root.effectiveRightLayout) : root.effectiveLeftLayout
    readonly property var centerLayout: root.reversed ? root.flipped(root.effectiveMiddleLayout) : root.effectiveMiddleLayout
    readonly property var bottomLayout: root.reversed ? root.flipped(root.effectiveLeftLayout) : root.effectiveRightLayout

    readonly property bool centerOnly: !root.isMaterial
        && root.effectiveLeftLayout.length === 0
        && root.effectiveRightLayout.length === 0
    readonly property real centerPillY: centerPill.y
    readonly property real centerPillHeight: centerPill.height

    function shouldPaintMaterialPill(name) {
        if (Config.options.bar.cornerStyle !== 3) return false;
        const blacklist = ["workspaces", "divisor", "powerButton", "media", "docktoPanel", "leftSidebarButton", "dynamicIsland"];
        if (blacklist.includes(name)) {
            return false;
        }
        return true;
    }

    function getMaterialPillColor(name) {
        if (Config.options.bar.cornerStyle !== 3) return Appearance.colors.colPrimaryContainer;
        switch(name) {
            case "media":
            case "sysTray":
                return Appearance.colors.colSecondaryContainer;
            case "resources":
                return Appearance.colors.colTertiaryContainer;
            case "systemIcons":
                return Appearance.colors.colPrimary; 
            default:
                return Appearance.colors.colPrimaryContainer;
        }
    }

    function getWidgetUrl(name) {
        if (!name) return "";
        let formattedName = name.charAt(0).toUpperCase() + name.slice(1);
        return Qt.resolvedUrl("../bar/" + formattedName + ".qml");
    }

    function getMirroredForIndex(layout, idx) {
        const prevCount = layout.slice(0, idx).filter(w => w === "visualizer").length
        return prevCount % 2 === 1
    }

    property var screen: root.QsWindow.window?.screen

    // Float: a floating Liquid Glass slab (soft shadow + GlassRim).
    StyledRectangularShadow {
        target: barBackground
        visible: Config.options.bar.cornerStyle === 1 && barBackground.color.a > 0 && !Cyberpunk.frames
    }
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.gapsOut : 0
        }
        color: (!centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2 && !root.isMaterial)
            ? (Config.options.bar.followFrameColor
                ? Appearance.getColorFromName(Config.options.bar.frameColor)
                : Appearance.colors.colLayer0)
            : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: (!root.centerOnly && Config.options.bar.cornerStyle === 1 && !Appearance.glass.enabled) ? 1 : 0
        border.color: Config.options.bar.showBackground ? Appearance.colors.colLayer0Border : "transparent"
    }

    // centerOnly
    Rectangle {
        id: centerPill
        visible: root.centerOnly && Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: middleCol.implicitHeight + 7
        width: parent.width - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.gapsOut * 2 : 0)
        color: Config.options.bar.followFrameColor
            ? Appearance.getColorFromName(Config.options.bar.frameColor)
            : Appearance.colors.colLayer0
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        bottomRightRadius: Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        topRightRadius:    Config.options.bar.cornerStyle === 0 && !Config.options.bar.bottom ? Appearance.rounding.screenRounding : radius
        bottomLeftRadius:  Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
        topLeftRadius:     Config.options.bar.cornerStyle === 0 && Config.options.bar.bottom  ? Appearance.rounding.screenRounding : radius
    }

    Item {
        id: contentContainer
        anchors.fill: barBackground
        anchors.margins: root.barPadding

        // Top
        Item {
            id: topSection
            anchors.top: parent.top
            anchors.topMargin: root.isMaterial ? (Appearance.sizes.gapsOut || 5) : Config.options.bar.cornerStyle === 1 ? 4 : Config.options.bar.cornerStyle === 4 ? 4 : 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial ? topMaterialPill.implicitHeight : topCol.implicitHeight

            Rectangle {
                id: topMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: topMaterialCol.implicitWidth
                implicitHeight: topMaterialCol.implicitHeight + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0
                // M3 islands float over the wallpaper: Liquid Glass edge.
                GlassRim { anchors.fill: parent; radius: Math.min(parent.radius, parent.width / 2) }

                ColumnLayout {
                    id: topMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        // Diffing model: a changed layout (e.g. sysTray shown once the tray has
                        // items) only adds/removes that delegate instead of rebuilding them all.
                        model: ScriptModel { values: root.topLayout }
                        delegate: topMaterialGroupDelegate
                    }

                    Component {
                        id: topMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.topLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                id: barWidget10
                                Layout.fillWidth: true
                                active: root.isMaterial
                                source: root.getWidgetUrl(modelData)
                                InteractionFx {} // hover lift / press squish
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                }
                                Binding {
                                    target: barWidget10.item
                                    property: "barMirrored"
                                    value: root.getMirroredForIndex(root.topLayout, index)
                                    when: barWidget10.item?.barMirrored !== undefined
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: topCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: root.groupSpacing

                Repeater {
                    // Diffing model: a changed layout (e.g. sysTray shown once the tray has
                    // items) only adds/removes that delegate instead of rebuilding them all.
                    model: ScriptModel { values: root.topLayout }
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.topLayout.length
                        Loader {
                            id: barWidget11
                            Layout.fillWidth: true
                            active: !root.isMaterial
                            source: root.getWidgetUrl(modelData)
                            InteractionFx {} // hover lift / press squish
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                            }
                            Binding {
                                target: barWidget11.item
                                property: "barMirrored"
                                value: root.getMirroredForIndex(root.topLayout, index)
                                when: barWidget11.item?.barMirrored !== undefined
                            }
                        }
                    }
                }
            }
        }

        // Center
        Item {
            id: absoluteCenter
            // Centred on the screen while it fits, else kept between the top
            // and bottom columns: on a short screen (totoro: 1125 logical px)
            // the centred column used to be drawn over the bottom one (the
            // tray, util buttons…). If even that doesn't fit, it stays
            // under the top column.
            readonly property real gap: 8
            readonly property real centred: (parent.height - height) / 2
            readonly property real minY: topSection.y + topSection.height + gap
            readonly property real maxY: bottomSection.y - height - gap
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(Math.max(minY, Math.min(centred, maxY)))
            width: parent.width
            height: root.isMaterial ? centerMaterialPill.implicitHeight : middleCol.implicitHeight

            Rectangle {
                id: centerMaterialPill
                visible: root.isMaterial && !GlobalStates.dynamicIslandEnabled
                anchors.centerIn: parent
                implicitWidth: centerMaterialCol.implicitWidth 
                implicitHeight: centerMaterialCol.implicitHeight + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0
                // M3 islands float over the wallpaper: Liquid Glass edge.
                GlassRim { anchors.fill: parent; radius: Math.min(parent.radius, parent.width / 2) }

                ColumnLayout {
                    id: centerMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        // Diffing model: a changed layout (e.g. sysTray shown once the tray has
                        // items) only adds/removes that delegate instead of rebuilding them all.
                        model: ScriptModel { values: root.centerLayout }
                        delegate: centerMaterialGroupDelegate
                    }

                    Component {
                        id: centerMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            paintBackground: modelData !== "dynamicIsland"
                            totalCount: root.centerLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                id: barWidget12
                                Layout.fillWidth: true
                                active: root.isMaterial
                                source: root.getWidgetUrl(modelData)
                                InteractionFx {} // hover lift / press squish
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                }
                                Binding {
                                    target: barWidget12.item
                                    property: "barMirrored"
                                    value: root.getMirroredForIndex(root.centerLayout, index)
                                    when: barWidget12.item?.barMirrored !== undefined
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: middleCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: root.groupSpacing

                Repeater {
                    // Diffing model: a changed layout (e.g. sysTray shown once the tray has
                    // items) only adds/removes that delegate instead of rebuilding them all.
                    model: ScriptModel { values: root.centerLayout }
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        paintBackground: modelData !== "dynamicIsland"
                        totalCount: root.centerLayout.length
                        Loader {
                            id: barWidget13
                            Layout.fillWidth: true
                            active: !root.isMaterial
                            source: root.getWidgetUrl(modelData)
                            InteractionFx {} // hover lift / press squish
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                            }
                            Binding {
                                target: barWidget13.item
                                property: "barMirrored"
                                value: root.getMirroredForIndex(root.centerLayout, index)
                                when: barWidget13.item?.barMirrored !== undefined
                            }
                        }
                    }
                }
            }
        }

        // Bottom
        Item {
            id: bottomSection
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.isMaterial ? (Appearance.sizes.gapsOut || 5) : Config.options.bar.cornerStyle === 1 ? 4 : Config.options.bar.cornerStyle === 4 ? 4 : 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.isMaterial ? bottomMaterialPill.implicitHeight : bottomCol.implicitHeight

            Rectangle {
                id: bottomMaterialPill
                visible: root.isMaterial
                anchors.centerIn: parent
                implicitWidth: bottomMaterialCol.implicitWidth
                implicitHeight: bottomMaterialCol.implicitHeight + 10 
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0
                // M3 islands float over the wallpaper: Liquid Glass edge.
                GlassRim { anchors.fill: parent; radius: Math.min(parent.radius, parent.width / 2) }

                ColumnLayout {
                    id: bottomMaterialCol
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        // Diffing model: a changed layout (e.g. sysTray shown once the tray has
                        // items) only adds/removes that delegate instead of rebuilding them all.
                        model: ScriptModel { values: root.bottomLayout }
                        delegate: bottomMaterialGroupDelegate
                    }

                    Component {
                        id: bottomMaterialGroupDelegate
                        Bar.BarGroup {
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: root.bottomLayout.length
                            paintMaterialPill: root.shouldPaintMaterialPill(modelData)
                            bgColor: root.getMaterialPillColor(modelData)
                            Loader {
                                id: barWidget14
                                Layout.fillWidth: true
                                active: root.isMaterial
                                source: root.getWidgetUrl(modelData)
                                InteractionFx {} // hover lift / press squish
                                onLoaded: {
                                    if (item && "vertical" in item) item.vertical = true
                                }
                                Binding {
                                    target: barWidget14.item
                                    property: "barMirrored"
                                    value: root.getMirroredForIndex(root.bottomLayout, index)
                                    when: barWidget14.item?.barMirrored !== undefined
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: bottomCol
                anchors.fill: parent
                visible: !root.isMaterial
                spacing: root.groupSpacing

                Repeater {
                    // Diffing model: a changed layout (e.g. sysTray shown once the tray has
                    // items) only adds/removes that delegate instead of rebuilding them all.
                    model: ScriptModel { values: root.bottomLayout }
                    delegate: Bar.BarGroup {
                        Layout.fillWidth: true
                        vertical: true
                        currentIndex: index
                        totalCount: root.bottomLayout.length
                        Loader {
                            id: barWidget15
                            Layout.fillWidth: true
                            active: !root.isMaterial
                            source: root.getWidgetUrl(modelData)
                            InteractionFx {} // hover lift / press squish
                            onLoaded: {
                                if (item && "vertical" in item) item.vertical = true
                            }
                            Binding {
                                target: barWidget15.item
                                property: "barMirrored"
                                value: root.getMirroredForIndex(root.bottomLayout, index)
                                when: barWidget15.item?.barMirrored !== undefined
                            }
                        }
                    }
                }
            }
        }
    }
}