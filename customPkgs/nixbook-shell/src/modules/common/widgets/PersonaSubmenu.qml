pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Desktop right-click menu → Persona variant (shown while the Persona style
// is enabled). Same choices as Settings → Interface → Persona style.
Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    readonly property bool nixManaged: NixManaged.isPinned("appearance.persona.variant")
    readonly property var variants: [
        { value: "p5",  icon: "local_fire_department", name: Translation.tr("Persona 5 Royal") },
        { value: "p3r", icon: "water_drop",            name: Translation.tr("Persona 3 Reload") },
        { value: "p4",  icon: "tv",                    name: Translation.tr("Persona 4 Revival") },
    ]

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Persona variant")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            NixManagedBadge { pinned: root.nixManaged }
        }

        Repeater {
            model: root.variants
            delegate: RippleButton {
                id: variantRow
                required property var modelData
                readonly property bool selected: Persona.variant === modelData.value
                Layout.fillWidth: true
                implicitHeight: 40
                enabled: !root.nixManaged
                opacity: enabled ? 1 : 0.5
                colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
                colBackgroundHover: Appearance.colors.colLayer2
                contentItem: RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 12
                    MaterialSymbol {
                        text: variantRow.modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: variantRow.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                    }
                    MaterialSymbol {
                        visible: variantRow.selected
                        text: "check"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                    }
                }
                onClicked: Config.options.appearance.persona.variant = modelData.value
            }
        }
    }
}
