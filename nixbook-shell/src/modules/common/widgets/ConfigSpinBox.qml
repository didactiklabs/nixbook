import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string text: ""
    property string icon
    property string configKey: ""
    readonly property bool nixManaged: configKey !== "" && NixManaged.isPinned(configKey)
    // Settings menu "Editable only" filter: locked settings drop out of the
    // list (containers hide once empty, see NixManaged.allFiltered).
    readonly property bool filteredOut: nixManaged && NixManaged.hideLocked
    // A real binding for the Binding below to restore: without one it
    // restores the value it read on activation, the *effective* visibility,
    // i.e. false when the filter was turned on from another page (pages stay
    // loaded but hidden), and the item stayed hidden after turning it off.
    visible: !root.filteredOut
    Binding on visible {
        when: root.filteredOut
        value: false
    }
    // Pinned by Nix: locked regardless of what the usage site binds to
    // `enabled` (NixManaged also reverts any write to a pinned key).
    Binding on enabled {
        when: root.nixManaged
        value: false
    }
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
    }

    NixManagedBadge { pinned: root.nixManaged }
    StyledSpinBox {
        id: spinBoxWidget
        Layout.fillWidth: false
        value: root.value
    }
}
