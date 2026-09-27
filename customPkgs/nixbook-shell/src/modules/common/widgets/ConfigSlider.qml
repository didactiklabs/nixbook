import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 120
    property bool showLabel: true
    property string configKey: ""
    readonly property bool nixManaged: configKey !== "" && NixManaged.isPinned(configKey)
    // Pinned by Nix: locked regardless of what the usage site binds to
    // `enabled` (NixManaged also reverts any write to a pinned key).
    Binding on enabled {
        when: root.nixManaged
        value: false
    }

    RowLayout {
        id: row
        visible: root.showLabel
        spacing: 10

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            // At least textWidth (keeps sliders aligned), but never narrower
            // than the text itself: a long label used to run under the slider.
            Layout.preferredWidth: Math.max(root.textWidth, labelWidget.implicitWidth)
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
        }
        NixManagedBadge { pinned: root.nixManaged }
    }
    StyledSlider {
        id: slider
        Layout.fillWidth: true
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
    }
}