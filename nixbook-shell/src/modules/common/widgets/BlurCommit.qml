import QtQuick

// A blur region (BackgroundEffect.blurRegion) reaches niri only with the
// surface's next commit, and Qt draws (commits) a frame only when something
// in it changed: a panel closing with nothing new to draw (faded out for an
// agent's screenshot) left its last region blurring the windows under it
// until the next open. This pixel, all but transparent, changes with `blur`,
// so the frame that carries the new region is drawn.
Rectangle {
    property bool blur: false
    property bool flip: false
    onBlurChanged: flip = !flip
    width: 1
    height: 1
    color: Qt.rgba(0, 0, 0, flip ? 1 / 255 : 2 / 255)
}
