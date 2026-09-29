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
    // A real binding for the Binding below to restore: without one it
    // restores the value it read on activation, the *effective* visibility,
    // i.e. false when the filter was turned on from another page (pages stay
    // loaded but hidden), and the item stayed hidden after turning it off.
    visible: !NixManaged.allFiltered(root)
    Binding on visible {
        when: NixManaged.allFiltered(root)
        value: false
    }
}
