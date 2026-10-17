import QtQuick
import qs.modules.common
import qs.services
import qs.modules.common.functions

/**
 * Clickable links in a plain-text TextArea (the notes): declared inside it,
 * textArea its parent. Links (StringUtils.findUrls) are underlined and
 * highlighted under the pointer, which turns into a hand; a click opens one
 * in the browser (AppLaunch.openUrl) and emits opened(url). A drag still
 * selects, and typing goes on as before.
 */
Item {
    id: root
    required property Item textArea
    signal opened(string url)

    // Under the text: the highlights are drawn behind the letters.
    anchors.fill: parent
    z: -1

    property var segments: layout(textArea.text, textArea.width, textArea.contentHeight,
        textArea.leftPadding, textArea.topPadding)
    property int hovered: -1

    // For each link, one rectangle per line it spans:
    // [{link, url, x, y, width, height}]
    function layout() {
        const segs = []
        StringUtils.findUrls(textArea.text).forEach((link, n) => {
            let seg = null
            for (let i = link.start; i < link.end; i++) {
                const r = textArea.positionToRectangle(i)
                const next = textArea.positionToRectangle(i + 1)
                const right = next.y === r.y && next.x > r.x ? next.x
                    : r.x + metrics.advanceWidth(textArea.text[i])
                if (seg && seg.y === r.y) {
                    seg.width = right - seg.x
                } else {
                    seg = { link: n, url: link.url, x: r.x, y: r.y, width: right - r.x, height: r.height }
                    segs.push(seg)
                }
            }
        })
        return segs
    }
    function segmentAt(x, y) {
        return segments.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) ?? null
    }

    FontMetrics {
        id: metrics
        font: root.textArea.font
    }
    Repeater {
        model: root.segments
        delegate: Rectangle {
            required property var modelData
            readonly property bool hovered: modelData.link === root.hovered
            x: modelData.x - 2
            y: modelData.y
            width: modelData.width + 4
            height: modelData.height
            radius: 4
            color: hovered ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8) : "transparent"
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2; bottomMargin: 1 }
                height: parent.hovered ? 2 : 1
                color: Appearance.colors.colPrimary
            }
        }
    }
    // On the TextArea itself: this item lies under it (z), where the
    // TextArea would take the pointer first.
    HoverHandler {
        parent: root.textArea
        cursorShape: root.hovered >= 0 ? Qt.PointingHandCursor : Qt.IBeamCursor
        onPointChanged: root.hovered = hovered ? (root.segmentAt(point.position.x, point.position.y)?.link ?? -1) : -1
        onHoveredChanged: if (!hovered) root.hovered = -1
    }
    TapHandler {
        parent: root.textArea
        onTapped: (eventPoint) => {
            const seg = root.segmentAt(eventPoint.position.x, eventPoint.position.y)
            if (!seg) return
            AppLaunch.openUrl(seg.url)
            root.opened(seg.url)
        }
    }
}
