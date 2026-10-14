import QtQuick
import qs.modules.common

/**
 * The Chiikawa theme's character (Chiikawa.mascotUrl, an animated GIF):
 * breathes gently and spins where idle, hops (and spins) when clicked or
 * hovered. `friends`: Chiikawa, Momonga and Usagi side by side, each its own
 * GIF (Chiikawa.friendsLayout, wide: Chiikawa.friendsAspect). Hidden unless
 * the theme and its mascot are on.
 */
Item {
    id: root
    property bool hopOnHover: true
    // Idle "breathing" and spinning: only where the character is briefly on
    // screen (the loading screen, the alert); an endless animation keeps its
    // window repainting every frame.
    property bool idle: true
    property bool friends: false
    property bool asynchronous: true
    // Where not idle it stays on its first frame, spinning only during a hop.
    readonly property bool playing: visible && (idle || hopAnim.running)

    visible: Chiikawa.mascot
    transformOrigin: Item.Bottom

    function hop() {
        if (!hopAnim.running)
            hopAnim.start();
    }

    component Gif: AnimatedImage {
        playing: root.playing
        onPlayingChanged: if (!playing) currentFrame = 0
        fillMode: Image.PreserveAspectFit
        asynchronous: root.asynchronous
        cache: true
        smooth: true
    }

    Gif {
        anchors.fill: parent
        visible: !root.friends
        source: root.visible && !root.friends ? Chiikawa.mascotUrl() : ""
    }

    // The friends' frame, fitted and centred at the bottom like one image.
    Item {
        id: friendsFrame
        visible: root.friends
        readonly property real k: Math.min(root.width / Chiikawa.friendsSize.width, root.height / Chiikawa.friendsSize.height)
        width: Chiikawa.friendsSize.width * k
        height: Chiikawa.friendsSize.height * k
        anchors.centerIn: parent

        Repeater {
            model: root.visible && root.friends ? Chiikawa.friendsLayout : []
            delegate: Gif {
                required property var modelData
                x: modelData.x * friendsFrame.k
                y: modelData.y * friendsFrame.k
                width: modelData.width * friendsFrame.k
                height: modelData.height * friendsFrame.k
                source: Chiikawa.friendUrl(modelData.file)
            }
        }
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
