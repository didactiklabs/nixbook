import QtQuick
import qs.modules.common

/**
 * The Chiikawa theme's character (the current variant's, Chiikawa.mascotUrl):
 * breathes gently, hops when clicked or hovered. Hidden unless the theme and
 * its mascot are on.
 */
Image {
    id: root
    property bool hopOnHover: true
    // Idle "breathing" (off for a still picture, e.g. in a screenshot).
    property bool idle: true

    visible: Chiikawa.mascot
    source: visible ? Chiikawa.mascotUrl() : ""
    sourceSize.width: 400
    sourceSize.height: 400
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    transformOrigin: Item.Bottom

    function hop() {
        if (!hopAnim.running)
            hopAnim.start();
    }

    SequentialAnimation on scale {
        running: root.visible && root.idle
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 1.035; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.035; to: 1; duration: 1400; easing.type: Easing.InOutSine }
    }

    Translate { id: lift }
    transform: lift
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: lift; property: "y"; to: -root.height * 0.18; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: lift; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBounce }
    }

    HoverHandler {
        enabled: root.hopOnHover
        onHoveredChanged: if (hovered) root.hop()
    }
    TapHandler {
        onTapped: root.hop()
    }
}
