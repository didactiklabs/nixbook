pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    hoverEnabled: true

    // configEntryName: "customImage", or "customImage:<id>" for an extra
    // image (WidgetsLoader); always read and write through entry/setEntry.
    readonly property var entry: root.configEntry
    property string imagePath: entry.path ?? ""
    property bool dropHover: false
    property real widgetSize: entry.size ?? 200
    property real widgetRotation: entry.rotation ?? 0

    // Framing: the image covers the shape (scaled up by `zoom`); offsetX/Y
    // (-1..1) pick which part of the overflow shows, 0 = centred.
    readonly property real zoom: Math.max(1, entry.zoom ?? 1)
    readonly property real offsetX: Math.max(-1, Math.min(1, entry.offsetX ?? 0))
    readonly property real offsetY: Math.max(-1, Math.min(1, entry.offsetY ?? 0))
    // Natural aspect ratio, from a thumbnail-sized decode (see aspectProbe).
    readonly property real imageAspect: (aspectProbe.status === Image.Ready && aspectProbe.implicitHeight > 0)
        ? aspectProbe.implicitWidth / aspectProbe.implicitHeight : 1

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    function getShape(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie4Sided
        }
    }

    Image {
        id: aspectProbe
        visible: false
        asynchronous: true
        cache: false
        source: root.imagePath
        sourceSize: Qt.size(256, 256)
    }

    Item {
        id: contentItem
        implicitWidth: root.widgetSize
        implicitHeight: root.widgetSize

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        MaterialShape {
            id: shadowShape
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            shape: getShape(root.entry.shape ?? "Cookie4Sided")
            rotation: root.widgetRotation
            visible: false
        }

        StyledDropShadow {
            target: shadowShape
            z: -1
            // The effect draws its source unrotated.
            rotation: root.widgetRotation
            opacity: imageShape.opacity
            visible: Config.options.background.widgets.shadow
        }

        MaterialShape {
            id: imageShape
            anchors.fill: parent
            z: 0
            color: Appearance.colors.colPrimaryContainer
            shape: getShape(root.entry.shape ?? "Cookie4Sided")
            rotation: root.widgetRotation
            opacity: root.entry.opacity ?? 1

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: MaterialShape {
                    width: imageShape.width
                    height: imageShape.height
                    shape: getShape(root.entry.shape ?? "Cookie4Sided")
                }
            }

            StyledImage {
                id: image
                // Smallest size covering the shape, times the zoom.
                readonly property real coverScale: Math.max(parent.width / root.imageAspect, parent.height) * root.zoom
                width: coverScale * root.imageAspect
                height: coverScale
                // (parent - size) / 2 is the centred position; offset ±1 slides
                // to an edge.
                x: (parent.width - width) / 2 * (1 + root.offsetX)
                y: (parent.height - height) / 2 * (1 + root.offsetY)
                source: root.imagePath
                // Crops away the probe's rounding instead of stretching it.
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                mirror: root.entry.mirror ?? false
                // Rounded up in steps so resizing or zooming doesn't reload the
                // image on every pixel.
                sourceSize.width: Math.ceil(width / 64) * 64
                sourceSize.height: Math.ceil(height / 64) * 64
                visible: root.imagePath !== ""

                layer.enabled: root.entry.grayscale ?? false
                layer.effect: MultiEffect {
                    saturation: -1
                }
            }

            // Placeholder + hover hint
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: contentItem.implicitWidth / 3
                text: root.dropHover ? "download" : "image"
                fill: root.dropHover ? 1 : 0
                color: root.dropHover
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnPrimaryContainer
                visible: root.imagePath === ""
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: (drag) => {
                    drag.accept(Qt.CopyAction)
                    root.dropHover = true
                }
                onExited: {
                    root.dropHover = false
                }
                onDropped: (drop) => {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        var cleanPath = drop.urls[0].toString().replace(/^file:\/\//, "")
                        var ext = cleanPath.split(".").pop().toLowerCase()
                        var accepted = ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]
                        if (accepted.indexOf(ext) !== -1) {
                            root.setEntry({ path: cleanPath, zoom: 1, offsetX: 0, offsetY: 0 })
                        }
                    }
                    root.dropHover = false
                }
            }
        }

        ResizeHandler{
            anchorItem: imageShape
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.widgetSize
            resizeMode: "diagonal"
            rotatable: true
            currentRotation: root.widgetRotation
            z: 1
            onResized: (newValue) => {
                root.widgetSize = Math.max(80, newValue)
            }
            onResizeFinished: {
                root.setEntry({ size: root.widgetSize })
                root.widgetSize = Qt.binding(() => root.entry.size ?? 200)
            }
            onRotated: (newAngle) => {
                root.widgetRotation = newAngle
            }
            onRotateFinished: {
                root.setEntry({ rotation: root.widgetRotation })
                root.widgetRotation = Qt.binding(() => root.entry.rotation ?? 0)
            }
        }
    }
}
