import QtQuick
import qs.modules.common

/**
 * The Ghibli theme's spirit for the current variant (Ghibli.spiritUrl):
 * the forest spirit, the masked spirit or a kodama. Sways gently where
 * idle, and when clicked or hovered it bobs, and a kodama shakes its head
 * (the rattle). Hidden unless the theme and its spirits are on.
 */
Image {
    id: root
    property bool wobbleOnHover: true
    // Idle sway: only where the spirit is briefly on screen (the loading
    // screen, the cut-in); an endless animation keeps its window repainting.
    property bool idle: true
    property string variant: Ghibli.variant

    visible: Ghibli.spirits
    source: visible ? Ghibli.spiritUrl(root.variant) : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    transformOrigin: Item.Bottom

    function wobble() {
        if (!wobbleAnim.running)
            wobbleAnim.start();
    }

    SequentialAnimation on rotation {
        running: root.visible && root.idle && !wobbleAnim.running
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 2.5; duration: 2200; easing.type: Easing.InOutSine }
        NumberAnimation { from: 2.5; to: -2.5; duration: 4400; easing.type: Easing.InOutSine }
        NumberAnimation { from: -2.5; to: 0; duration: 2200; easing.type: Easing.InOutSine }
    }

    Translate { id: lift }
    transform: lift
    SequentialAnimation {
        id: wobbleAnim
        ParallelAnimation {
            NumberAnimation { target: lift; property: "y"; to: -root.height * 0.08; duration: 260; easing.type: Easing.OutSine }
            // The kodama's head-shake; the others just lean.
            SequentialAnimation {
                loops: root.variant === "mononoke" ? 4 : 1
                NumberAnimation { target: root; property: "rotation"; to: root.variant === "mononoke" ? 9 : 5; duration: root.variant === "mononoke" ? 45 : 200 }
                NumberAnimation { target: root; property: "rotation"; to: root.variant === "mononoke" ? -9 : -4; duration: root.variant === "mononoke" ? 90 : 300 }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 520; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "rotation"; to: 0; duration: 520; easing.type: Easing.OutBack }
        }
    }

    HoverHandler {
        enabled: root.wobbleOnHover
        onHoveredChanged: if (hovered) root.wobble()
    }
    TapHandler {
        onTapped: root.wobble()
    }
}
