import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            property var monitor: WM.monitorFor(modelData)
            property bool fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)

            property bool reveal: {
                if (fullscreenOnThisMonitor)
                    return Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse
                return root.pinned
                    || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse)
                    || peekHandle.hovered
                    || activeAppsArea.requestDockShow
                    || GlobalStates.dockPopupsOpen > 0
                    || (!ToplevelManager.activeToplevel?.activated)
            }

            exclusiveZone: (root.pinned && !fullscreenOnThisMonitor)
                ? implicitHeight - Appearance.sizes.gapsOut
                  - (Appearance.sizes.elevationMargin - Appearance.sizes.gapsOut)
                : 0

            anchors { bottom: true; left: true; right: true }
            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            implicitHeight: (Config.options?.dock.height ?? 70)
                + Appearance.sizes.elevationMargin
                + Appearance.sizes.gapsOut

            mask: Region {
                item: dockMouseArea
                Region { item: peekHandle.active ? peekHandle : null }
            }

            // Peek handle: while the dock is hidden, a small pill at the
            // bottom edge shows where to hover. It lights up and stretches
            // under the cursor, sweeps a shine across when the dock tucks
            // away, and its own hit area (taller than the edge strip) also
            // reveals the dock. Declared before dockMouseArea so the dock
            // takes the hover over once it has slid up.
            Item {
                id: peekHandle
                readonly property bool active: (Config.options?.dock.showHandle ?? true)
                    && (Config.options?.dock.hoverToReveal ?? true)
                    && !root.pinned
                    && !dockRoot.fullscreenOnThisMonitor
                readonly property bool shown: active && !dockRoot.reveal
                readonly property bool hovered: active && peekArea.containsMouse

                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(dockMouseArea.width, Math.max(140, dockBackground.implicitWidth * 0.4))
                height: 12

                MouseArea {
                    id: peekArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: peekHandle.active
                    cursorShape: Qt.PointingHandCursor
                }

                onShownChanged: if (shown) shine.restart()

                Item {
                    id: pillHolder
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    width: peekHandle.hovered ? 76 : 44
                    height: peekHandle.hovered ? 5 : 4
                    opacity: peekHandle.shown ? 1 : 0
                    scale: peekHandle.shown ? 1 : 0.4
                    transform: Matrix4x4 {
                        readonly property real k: Persona.shapes ? Persona.skew * 2 : 0
                        matrix: Qt.matrix4x4(1, k, 0, -k * pillHolder.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                    }

                    Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    Behavior on height { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

                    // Soft halo in the accent colour while hovered
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 14
                        height: parent.height + 8
                        radius: Persona.shapes ? 0 : height / 2
                        color: Appearance.colors.colPrimary
                        opacity: peekHandle.hovered ? 0.22 : 0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    Rectangle {
                        id: pill
                        anchors.fill: parent
                        radius: Persona.shapes ? 0 : height / 2
                        clip: true
                        color: peekHandle.hovered
                            ? Appearance.colors.colPrimary
                            : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.55)
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
                        Behavior on color { ColorAnimation { duration: 180 } }

                        // Shine that runs across the pill once as it appears
                        Rectangle {
                            id: shineBar
                            width: pill.width * 0.45
                            height: pill.height
                            x: -width
                            opacity: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
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
                                target: shineBar; property: "x"
                                from: -shineBar.width; to: pill.width
                                duration: 650; easing.type: Easing.InOutQuad
                            }
                            PropertyAction { target: shineBar; property: "opacity"; value: 0 }
                        }
                    }
                }
            }

            MouseArea {
                cursorShape: Qt.PointingHandCursor
                id: dockMouseArea
                height: parent.height
                anchors {
                    top: parent.top
                    topMargin: dockRoot.reveal
                        ? 0
                        : Config.options?.dock.hoverToReveal
                            ? (dockRoot.implicitHeight - Config.options.dock.hoverRegionHeight)
                            : (dockRoot.implicitHeight + 1)
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth

                    Item {
                        id: dockBackground
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                        }
                        implicitWidth: dockRow.implicitWidth + 5 * 2
                        height: parent.height
                            - Appearance.sizes.elevationMargin
                            - Appearance.sizes.gapsOut

                        StyledRectangularShadow {
                            target: dockVisualBackground
                            visible: false
                        }

                        Rectangle {
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin:    Appearance.sizes.elevationMargin
                            anchors.bottomMargin: Appearance.sizes.gapsOut
                            color: Config.options.dock.showBackground && !Persona.shapes
                                   ? Appearance.colors.colLayer0 : "transparent"
                            border.width: Config.options.dock.showBackground && !Persona.shapes ? 1 : 0
                            border.color: Appearance.colors.colLayer0Border
                            radius: Appearance.rounding.normal + 6

                            // Persona style: slanted comic-panel frame
                            PersonaFrame {
                                visible: Persona.shapes && Config.options.dock.showBackground
                                anchors.fill: parent
                                z: -1
                                color: Appearance.colors.colLayer0
                                // Quieter than the panels: a hairline, not the
                                // bold (P5: gold) outline, and a short soft shadow.
                                borderWidth: 1
                                borderColor: ColorUtils.transparentize(Persona.frameBorderColor, 0.82)
                                shadowOffset: Math.round(Persona.shadowOffset * 0.5)
                                shadowOpacity: 0.55
                            }
                        }

                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            property real padding: 5
                            property bool hasPinnedApps: (Config.options?.dock.pinnedApps?.length ?? 0) > 0

                            VerticalButtonGroup {
                                Layout.topMargin: 3
                                Layout.leftMargin:  root.pinned
                                    ? Appearance.sizes.gapsOut + 4
                                    : Appearance.sizes.gapsOut
                                Layout.rightMargin: root.pinned
                                    ? Appearance.sizes.gapsOut + 4
                                    : Appearance.sizes.gapsOut

                                GroupButton {
                                    baseWidth: 35; baseHeight: 35
                                    visible: Config.options.dock.showPinButton
                                    clickedWidth: baseWidth; clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned
                                               ? Appearance.m3colors.m3onPrimary
                                               : Appearance.colors.colOnLayer0
                                    }
                                }
                            }

                            DockSeparator {
                                visible: Config.options.dock.showPinButton
                                    && (dockRow.hasPinnedApps
                                        || !(Config.options.dock.showMedia && dockMedia.hasTrack))
                            }

                            DragApps {
                                id: dragSlots
                                visible: dockRow.hasPinnedApps
                                Layout.fillHeight: false
                                Layout.topMargin: 2
                                Layout.leftMargin: Config.options.dock.showPinButton ? 0 : -18
                                pinnedApps:    Config.options?.dock.pinnedApps ?? []
                                buttonPadding: dockRow.padding
                                btnSize:       46
                                btnSpacing:    1
                            }

                            DockSeparator {
                                visible: dockRow.hasPinnedApps && (activeAppsArea.activeUnpinned.length > 0 || (Config.options.dock.showMedia && MprisController.activePlayer !== null))
                            }

                            Item {
                                id: activeAppsArea
                                Layout.fillHeight: true
                                Layout.topMargin: 0
                                property bool requestDockShow: false

                                property var activeUnpinned: {
                                    return TaskbarApps.apps.filter(
                                        a => !a.pinned
                                          && a.appId !== "SEPARATOR"
                                          && a.toplevels.length > 0
                                    )
                                }
                                property bool hasActiveUnpinned: activeUnpinned.length > 0 || dockMedia.visible

                                implicitWidth:  activeRow.implicitWidth
                                implicitHeight: parent.height

                                Behavior on implicitWidth {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }

                                RowLayout {
                                    id: activeRow
                                    anchors.fill: parent
                                    Layout.rightMargin: 10
                                    spacing: -4

                                    DockMedia {
                                        id: dockMedia
                                        visible: Config.options.dock.showMedia
                                        Layout.fillHeight: true
                                        Layout.topMargin: 12
                                        Layout.bottomMargin: 8
                                        Layout.leftMargin: 0
                                        buttonPadding: dockRow.padding
                                    }

                                    Repeater {
                                        model: activeAppsArea.activeUnpinned
                                        delegate: DockAppButton {
                                            required property var modelData
                                            appToplevel: modelData
                                            Layout.fillHeight: true
                                            Layout.topMargin: 2
                                            appListRoot: appListBridge
                                            topInset:    dockRow.padding + 8
                                            bottomInset: dockRow.padding + 8
                                        }
                                    }
                                }

                                QtObject {
                                    id: appListBridge
                                    property Item lastHoveredButton: null
                                    property bool buttonHovered: false
                                }
                            }

                            DockSeparator {
                                visible: Config.options.dock.showAppsButton
                                Layout.leftMargin: Config.options.dock.showAppsButton ? 0 : -3
                            }

                            DockButton {
                                Layout.fillHeight: true
                                Layout.topMargin: 0
                                visible: Config.options.dock.showAppsButton
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                topInset:    dockRow.padding + 10
                                bottomInset: dockRow.padding + 7
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: parent.width / 2
                                    text: "apps"
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
