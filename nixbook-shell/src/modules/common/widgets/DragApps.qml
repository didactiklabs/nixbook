import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Item {
    id: root

    property real btnSize: 46
    property real btnSpacing: 2
    property real buttonPadding: 5
    property var pinnedApps: Config.options?.dock.pinnedApps ?? []
    signal orderChanged(var newOrder)
    property var  _workOrder: pinnedApps.slice()
    property int  activeDragVisualIndex: -1
    property bool _dragging: false

    onPinnedAppsChanged: {
        if (!_dragging) {
            _workOrder = pinnedApps.slice()
        }
    }

    implicitWidth:  _workOrder.length * btnSize + Math.max(0, _workOrder.length - 1) * btnSpacing
    implicitHeight: parent?.height ?? btnSize

    function swapSlots(fromPos, toPos) {
        if (fromPos === toPos) return
        if (fromPos < 0 || fromPos >= _workOrder.length) return
        if (toPos   < 0 || toPos   >= _workOrder.length) return
        let arr = _workOrder.slice()
        let tmp = arr[fromPos]
        arr[fromPos] = arr[toPos]
        arr[toPos]   = tmp
        _workOrder = arr
    }

    function commitOrder() {
        const newOrder = _workOrder.slice()
        Config.options.dock.pinnedApps = newOrder
        orderChanged(newOrder)
    }

    Repeater {
        id: slotRepeater
        model: root._workOrder.length

        delegate: Item {
            id: slotItem
            required property int index

            property string appId:     root._workOrder[index] ?? ""
            property var    appEntry:  TaskbarApps.apps.find(a => a.appId === appId) ?? null
            property var    deskEntry: DesktopEntries.heuristicLookup(appId)
            property bool   appActive: appEntry?.toplevels?.find(t => t.activated) !== undefined
            property int    _lastFocused: -1

            Connections {
                target: DesktopEntries
                function onApplicationsChanged() {
                    slotItem.deskEntry = DesktopEntries.heuristicLookup(slotItem.appId)
                }
            }

            width:  root.btnSize
            height: root.implicitHeight
            x:      index * (root.btnSize + root.btnSpacing)

            Behavior on x {
                enabled: root.activeDragVisualIndex !== slotItem.index
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            opacity: (root.activeDragVisualIndex === index) ? 0.0 : 1.0
            scale:   (root.activeDragVisualIndex === index) ? 0.7 : 1.0
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            Item {
                visible: dragHandler.active
                z: 1000
                width:  root.btnSize
                height: root.btnSize
                anchors.verticalCenter: parent.verticalCenter

                x: {
                    if (!dragHandler.active) return 0
                    var lp = slotItem.mapFromItem(null,
                        dragHandler.centroid.scenePosition.x,
                        dragHandler.centroid.scenePosition.y)
                    return lp.x - width / 2
                }

                scale: dragHandler.active ? 1.15 : 0.9
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }

                IconImage {
                    id: ghostIcon
                    anchors.centerIn: parent
                    source: Quickshell.iconPath(
                        AppSearch.guessIcon(root._workOrder[root.activeDragVisualIndex] ?? ""),
                        "image-missing")
                    implicitSize: root.btnSize * 0.65
                    opacity: 0.85

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowVerticalOffset: dragHandler.active ? 7 : 4
                        shadowBlur: dragHandler.active ? 0.85 : 0.65
                        shadowColor: "#80000000"

                        Behavior on shadowVerticalOffset { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on shadowBlur { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                }
            }

            DockButton {
                id: dockBtn
                anchors.fill: parent

                property var appToplevel: slotItem.appEntry

                topInset:    Appearance.sizes.gapsOut + 8
                bottomInset: Appearance.sizes.gapsOut + 8

                implicitWidth: implicitHeight - topInset - bottomInset

                hoverEnabled: true

                onClicked: {
                    const entry = slotItem.appEntry
                    if (!entry || entry.toplevels.length === 0) {
                        AppLaunch.launchEntry(slotItem.deskEntry)
                        return
                    }
                    const next = (slotItem._lastFocused + 1) % entry.toplevels.length
                    slotItem._lastFocused = next
                    entry.toplevels[next].activate()
                }

                middleClickAction: () => { AppLaunch.launchEntry(slotItem.deskEntry) }
                altAction:         () => { TaskbarApps.togglePin(slotItem.appId) }

                contentItem: Item {
                    anchors.centerIn: parent

                    IconImage {
                        id: appIcon
                        anchors.centerIn: parent
                        source: Quickshell.iconPath(
                            AppSearch.guessIcon(slotItem.appId),
                            "image-missing")
                        implicitSize: 33
                    }

                    Loader {
                        active: Config.options.dock.monochromeIcons
                        anchors.fill: appIcon
                        sourceComponent: Item {
                            Desaturate {
                                id: desaturatedIcon
                                visible: false
                                anchors.fill: parent
                                source: appIcon
                                desaturation: 0.8
                            }
                            ColorOverlay {
                                anchors.fill: desaturatedIcon
                                source: desaturatedIcon
                                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                            }
                        }
                    }

                    RowLayout {
                        spacing: 3
                        anchors {
                            top: appIcon.bottom
                            topMargin: 2
                            horizontalCenter: parent.horizontalCenter
                        }
                        Repeater {
                            model: Math.min(slotItem.appEntry?.toplevels?.length ?? 0, 3)
                            delegate: Rectangle {
                                required property int index
                                radius:         Appearance.rounding.full
                                implicitWidth:  (slotItem.appEntry?.toplevels?.length ?? 0) <= 3
                                                ? 10 : 4
                                implicitHeight: 4
                                color: slotItem.appActive
                                       ? Appearance.colors.colPrimary
                                       : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                            }
                        }
                    }
                }
            }

            DragHandler {
                id: dragHandler
                target: null
                grabPermissions: PointerHandler.CanTakeOverFromAnything

                onActiveChanged: {
                    if (active) {
                        root._dragging = true
                        root.activeDragVisualIndex = index
                        return
                    }
                    root.activeDragVisualIndex = -1
                    root._dragging = false
                    root.commitOrder()
                }

                onCentroidChanged: {
                    if (!active) return
                    const currentVisualIdx = root.activeDragVisualIndex
                    if (currentVisualIdx < 0) return

                    const dragX = dragHandler.centroid.scenePosition.x
                    let minDist    = Infinity
                    let nearestIdx = currentVisualIdx

                    for (let i = 0; i < slotRepeater.count; i++) {
                        if (i === currentVisualIdx) continue
                        const child = slotRepeater.itemAt(i)
                        if (!child) continue
                        const cc   = child.mapToItem(null, child.width / 2, child.height / 2)
                        const dist = Math.abs(dragX - cc.x)
                        if (dist < minDist) { minDist = dist; nearestIdx = i }
                    }

                    if (nearestIdx !== currentVisualIdx) {
                        const neighbor = slotRepeater.itemAt(nearestIdx)
                        if (!neighbor) return
                        const nc = neighbor.mapToItem(null, neighbor.width / 2, neighbor.height / 2)
                        const shouldSwap = (nearestIdx > currentVisualIdx)
                            ? (dragX >= nc.x)
                            : (dragX <= nc.x)

                        if (shouldSwap) {
                            root.swapSlots(currentVisualIdx, nearestIdx)
                            root.activeDragVisualIndex = nearestIdx
                        }
                    }
                }
            }
        }
    }
}
