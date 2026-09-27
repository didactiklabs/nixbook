import QtQuick
import qs.modules.common

MaterialSymbol {
    property bool pinned: false
    visible: pinned
    text: "lock"
    fill: 0
    iconSize: Appearance.font.pixelSize.small
    color: Appearance.m3colors.m3error
}
