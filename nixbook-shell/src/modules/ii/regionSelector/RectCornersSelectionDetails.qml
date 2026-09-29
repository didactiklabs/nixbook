import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    required property color overlayColor
    property bool showAimLines: Config.options.regionSelector.rect.showAimLines
    // Shown before the size (the hovered window's title / screen name).
    property string label: ""
    readonly property bool hasRegion: root.regionWidth > 0 && root.regionHeight > 0

    property bool breathingBorderOnly: false

    // Overlay to darken screen
    // Base dark overlay around region
    Rectangle {
        id: darkenOverlay
        z: 1
        visible: !root.breathingBorderOnly
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX - darkenOverlay.border.width
            topMargin: root.regionY - darkenOverlay.border.width
        }
        width: root.regionWidth + darkenOverlay.border.width * 2
        height: root.regionHeight + darkenOverlay.border.width * 2
        color: "transparent"
        border.color: root.overlayColor
        border.width: Math.max(root.width, root.height)
    }

    DashedBorder {
        id: selectionBorder
        z: 9
        visible: root.hasRegion
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX) - borderWidth
            topMargin: Math.round(root.regionY) - borderWidth
        }
        width: Math.round(root.regionWidth) + borderWidth * 2
        height: Math.round(root.regionHeight) + borderWidth * 2

        color: root.color
        dashLength: 8
        gapLength: 4
        borderWidth: 1

        // Breathing
        opacity: 0.9
        SequentialAnimation on opacity {
            running: root.breathingBorderOnly
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 0.3; duration: 1200; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.3; to: 0.9; duration: 1200; easing.type: Easing.InOutQuad }
        }
    }

    Rectangle {
        id: sizeLabel
        z: 2
        visible: !root.breathingBorderOnly && root.hasRegion
        // Below the selection, or inside its bottom edge when that is off
        // screen (a whole-screen or bottom-hugging selection).
        readonly property real below: selectionBorder.y + selectionBorder.height + 8
        x: Math.max(8, selectionBorder.x + selectionBorder.width - width - 8)
        y: below + height + 8 <= root.height ? below : selectionBorder.y + selectionBorder.height - height - 8
        width: sizeText.width + 16
        height: sizeText.implicitHeight + 8
        radius: height / 2
        color: root.overlayColor

        StyledText {
            id: sizeText
            anchors.centerIn: parent
            color: root.color
            text: (root.label !== "" ? `${root.label}  ·  ` : "")
                + `${Math.round(root.regionWidth)} x ${Math.round(root.regionHeight)}`
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, Math.max(0, root.width - 32))
        }
    }

    // Coord lines
    Rectangle { // Vertical
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        x: root.mouseX
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: root.color
    }
    Rectangle { // Horizontal
        visible: root.showAimLines && !root.breathingBorderOnly
        opacity: 0.2
        z: 2
        y: root.mouseY
        anchors {
            left: parent.left
            right: parent.right
        }
        height: 1
        color: root.color
    }
}
