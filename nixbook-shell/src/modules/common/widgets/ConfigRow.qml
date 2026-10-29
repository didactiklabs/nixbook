import QtQuick
import QtQuick.Layouts
import qs.modules.common

RowLayout {
    id: root
    // A StyledToolTip inside shows while this is hovered (without a
    // `hovered` it took the row for always hovered: stuck on screen).
    readonly property alias hovered: rowHover.hovered
    HoverHandler {
        id: rowHover
    }
    property bool uniform: false
    spacing: 4
    uniformCellSizes: uniform

    // Hidden when the settings menu's "Editable only" filter hides every
    // setting in the row.
    // Set `shown` (not `visible`) to hide this conditionally from a page: an
    // instance's `visible:` would replace the filter binding below.
    property bool shown: true
    visible: root.shown && !NixManaged.allFiltered(root)
}
