import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    spacing: 10

    property string icon: "palette"
    property string text: "Color"
    property string currentValue: ""
    property var options: ["primary", "secondary", "tertiary", "primaryContainer", "secondaryContainer", "tertiaryContainer", "layer1", "layer0"]
    property bool showLabel: true
    property real itemSpacing: 10
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
    opacity: enabled ? 1 : 0.5
    signal selected(string newValue)

    MaterialSymbol {
        visible: root.showLabel
        text: root.icon
        iconSize: Appearance.font.pixelSize.normal + 5
        color: Appearance.colors.colOnLayer0
    }

    StyledText {
        visible: root.showLabel
        text: root.text
        color: Appearance.colors.colOnLayer0
    }
    NixManagedBadge { pinned: root.nixManaged }

    Item {
        visible: root.showLabel
        Layout.fillWidth: true
    }

    Flow {
        Layout.fillWidth: !root.showLabel
        Layout.preferredWidth: root.showLabel ? implicitWidth : -1
        spacing: root.itemSpacing

        Repeater {
            model: root.options
            delegate: Item {
                id: slot
                required property string modelData
                readonly property bool isSelected: root.currentValue === modelData

                implicitWidth: 40
                implicitHeight: 40

                Rectangle {
                    id: ring
                    anchors.centerIn: parent
                    width: slot.isSelected ? parent.width : parent.width - 8
                    height: slot.isSelected ? parent.height : parent.height - 8
                    radius: slot.isSelected ? Appearance.rounding.normal : width / 2
                    color: "transparent"
                    border.width: slot.isSelected ? 2 : 0
                    border.color: Appearance.colors.colOnLayer0

                    Behavior on radius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on height {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                Rectangle {
                    id: swatch
                    anchors.centerIn: parent
                    width: slot.isSelected ? parent.width - 8 : parent.width - 8
                    height: slot.isSelected ? parent.height - 8 : parent.height - 8
                    radius: slot.isSelected ? Appearance.rounding.normal - 4 : width / 2 
                    color: slot.modelData === "black"
                        ? "black"
                        : Appearance.colors["col" + slot.modelData.charAt(0).toUpperCase() + slot.modelData.slice(1)]

                    Behavior on radius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                MouseArea {
                    hoverEnabled: true
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(slot.modelData)
                }
            }
        }
    }
}