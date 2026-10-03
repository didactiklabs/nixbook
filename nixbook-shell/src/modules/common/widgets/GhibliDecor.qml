import QtQuick
import qs.modules.common

/**
 * Ghibli theme background for a tall panel (the sidebars): the variant's
 * faint scatter (leaves, acorns and soot sprites; paper birds and lanterns;
 * kodama and fireflies) and its spirit in the bottom corner. Drawn under the
 * panel's content; hidden unless the theme and its spirits are on.
 */
Item {
    id: root
    visible: Ghibli.spirits
    clip: true

    Image {
        anchors.fill: parent
        source: root.visible ? Ghibli.patternUrl() : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        opacity: 0.9
    }

    GhibliSpirit {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Clear of the panel's rounded corner.
        anchors.rightMargin: 20
        // Sits a bit below the edge: peeking.
        anchors.bottomMargin: -height * 0.06
        width: Math.min(104, root.width * 0.3)
        height: width
        opacity: 0.92
        // Under the content: no hover wobble (the content gets the pointer).
        wobbleOnHover: false
        // Still: the sidebars stay mapped while closed (faded out), so an
        // endless animation here repainted them every frame. It wobbles
        // when clicked.
        idle: false
    }
}
