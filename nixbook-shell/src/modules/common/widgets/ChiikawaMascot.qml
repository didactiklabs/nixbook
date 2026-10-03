import QtQuick
import qs.modules.common

/**
 * The Chiikawa theme's character (Chiikawa.mascotUrl, an animated GIF):
 * breathes gently and spins where idle, hops (and spins) when clicked or
 * hovered. `friends`: Momonga with Chiikawa and Usagi beside him
 * (Chiikawa.friendsUrl, wide: Chiikawa.friendsAspect). Hidden unless the
 * theme and its mascot are on.
 */
AnimatedImage {
    id: root
    property bool hopOnHover: true
    // Idle "breathing" and spinning: only where the character is briefly on
    // screen (the loading screen, the alert); an endless animation keeps its
    // window repainting every frame.
    property bool idle: true
    property bool friends: false

    visible: Chiikawa.mascot
    source: visible ? (root.friends ? Chiikawa.friendsUrl() : Chiikawa.mascotUrl()) : ""
    // Where not idle it stays on its first frame, spinning only during a hop.
    playing: visible && (idle || hopAnim.running)
    onPlayingChanged: if (!playing) currentFrame = 0
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    smooth: true
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
