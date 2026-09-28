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
    Binding on visible {
        when: NixManaged.allFiltered(root)
        value: false
    }
}
