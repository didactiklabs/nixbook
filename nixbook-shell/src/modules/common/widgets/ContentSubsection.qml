import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    default property alias data: sectionContent.data

    Layout.fillWidth: true
    Layout.topMargin: 4
    spacing: 2

    // Hidden when the settings menu's "Editable only" filter hides every
    // setting inside (see NixManaged.allFiltered).
    // Set `shown` (not `visible`) to hide this conditionally from a page: an
    // instance's `visible:` would replace the filter binding below.
    property bool shown: true
    visible: root.shown && !NixManaged.allFiltered(root)

    RowLayout {
        ContentSubsectionLabel {
            visible: root.title && root.title.length > 0
            text: root.title
        }
        MaterialSymbol {
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.large
            
            color: Appearance.colors.colSubtext
            MouseArea {
                id: infoMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: infoMouseArea.containsMouse
                    text: root.tooltip
                }
            }
        }
        Item { Layout.fillWidth: true }
    }
    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: 2
    }
}
