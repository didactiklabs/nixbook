import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property alias iconSize: iconWidget.iconSize
    property string configKey: ""
    readonly property bool nixManaged: configKey !== "" && NixManaged.isPinned(configKey)
    // Settings menu "Editable only" filter: locked settings drop out of the
    // list (containers hide once empty, see NixManaged.allFiltered).
    readonly property bool filteredOut: nixManaged && NixManaged.hideLocked
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
    colBackgroundHover: "transparent"

    Layout.fillWidth: true
    Layout.bottomMargin: 6 //Visually it works and I don't know why this should be handled by the parent.
    implicitHeight: contentItem.implicitHeight + 8 
    font.pixelSize: Appearance.font.pixelSize.small
    
    onClicked: checked = !checked

    contentItem: RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            opacity: root.enabled ? 1 : 0.4
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            // The shell's font (the theme's: Nunito in Chiikawa…), not the
            // Controls default family `root.font` carries.
            font.family: Appearance.font.family.main
            font.pixelSize: root.font.pixelSize
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
        NixManagedBadge { pinned: root.nixManaged }
        StyledSwitch {
            id: switchWidget
            down: root.down
            Layout.fillWidth: false
            checked: root.checked
            onClicked: root.clicked()
        }
    }
}

