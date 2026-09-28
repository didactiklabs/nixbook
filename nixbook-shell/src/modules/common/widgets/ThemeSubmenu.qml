pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Desktop right-click menu → Theme: every theme, then the current theme's
// variants (Themes.qml, themes.json). Same choices as Settings → Appearance →
// Theme.
Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    component Header: RowLayout {
        id: header
        property string text
        property bool pinned
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        StyledText {
            Layout.fillWidth: true
            text: header.text
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        NixManagedBadge { pinned: header.pinned }
    }

    component Choice: RippleButton {
        id: choice
        property string symbol
        property string label
        property bool selected
        property bool locked
        Layout.fillWidth: true
        implicitHeight: 40
        enabled: !choice.locked
        opacity: enabled ? 1 : 0.5
        colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: Appearance.colors.colLayer2
        contentItem: RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12
            MaterialSymbol {
                text: choice.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: choice.label
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            MaterialSymbol {
                visible: choice.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }
        }
    }

    readonly property bool themePinned: NixManaged.isPinned("appearance.theme")
    readonly property bool variantPinned: NixManaged.isPinned(Themes.variantKey(Themes.current))

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        Header {
            text: Translation.tr("Theme")
            pinned: root.themePinned
        }
        Repeater {
            model: Themes.list
            delegate: Choice {
                required property var modelData
                symbol: modelData.icon
                label: Translation.tr(modelData.name)
                selected: Themes.current === modelData.id
                locked: root.themePinned
                onClicked: Themes.setTheme(modelData.id)
            }
        }

        Header {
            visible: Themes.currentVariants.length > 0
            Layout.topMargin: 8
            text: Translation.tr("%1 variant").arg(Translation.tr(Themes.currentTheme?.name ?? ""))
            pinned: root.variantPinned
        }
        Repeater {
            model: Themes.currentVariants
            delegate: Choice {
                required property var modelData
                symbol: modelData.icon
                label: Translation.tr(modelData.name)
                selected: Themes.variant === modelData.id
                locked: root.variantPinned
                onClicked: Themes.setVariant(Themes.current, modelData.id)
            }
        }
    }
}
