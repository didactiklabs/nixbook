import QtQuick
import QtQuick.Layouts
import qs.modules.common

RowLayout {
    id: root
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
