import QtQuick
import qs.modules.common

/**
 * Chiikawa theme background for a tall panel (the sidebars): scattered stars,
 * hearts and dots, and the character peeking from the bottom corner. Drawn
 * under the panel's content; hidden unless the theme and its mascot are on.
 */
Item {
    id: root
    visible: Chiikawa.mascot
    clip: true

    Image {
        anchors.fill: parent
        source: root.visible ? Chiikawa.patternUrl() : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        opacity: 0.8
    }

    ChiikawaMascot {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Clear of the panel's rounded corner.
        anchors.rightMargin: 24
        // Sits a bit below the edge: peeking.
        anchors.bottomMargin: -height * 0.12
        width: Math.min(96, root.width * 0.28)
        height: width
        opacity: 0.9
        // Under the content: no hover hop (the content gets the pointer).
        hopOnHover: false
    }
}
