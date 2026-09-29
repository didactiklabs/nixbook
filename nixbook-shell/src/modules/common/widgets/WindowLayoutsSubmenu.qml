pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Desktop right-click menu → Window layouts (services/WindowLayouts.qml):
// the saved layouts (click one to put every window back as it had them),
// save the current windows as a new layout or into the current one, and the
// Settings page to rename and delete them.
Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    Component.onCompleted: WindowLayouts.refresh()

    function closeMenu() {
        GlobalStates.desktopMenuOpen = false;
    }

    component Header: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    component Choice: RippleButton {
        id: choice
        property string symbol
        property string label
        property string detail
        property bool selected
        Layout.fillWidth: true
        implicitHeight: 40
        enabled: !WindowLayouts.busy
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
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: choice.detail.length > 0
                text: choice.detail
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                opacity: 0.6
            }
            MaterialSymbol {
                visible: choice.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }
        }
    }

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
            text: WindowLayouts.layouts.length > 0 ? Translation.tr("Restore a layout")
                : Translation.tr("No saved layout yet")
        }
        Repeater {
            model: WindowLayouts.layouts
            delegate: Choice {
                required property var modelData
                symbol: "view_quilt"
                label: modelData.name
                detail: Translation.tr("%1 windows").arg(modelData.windows)
                selected: WindowLayouts.current === modelData.name
                onClicked: {
                    root.closeMenu();
                    WindowLayouts.restore(modelData.name);
                }
            }
        }

        Header {
            Layout.topMargin: 8
            text: Translation.tr("Save the windows as they are")
        }
        Choice {
            visible: WindowLayouts.current.length > 0
            symbol: "save"
            label: Translation.tr("Update “%1”").arg(WindowLayouts.current)
            onClicked: {
                root.closeMenu();
                WindowLayouts.save(WindowLayouts.current);
            }
        }
        Choice {
            symbol: "add"
            label: Translation.tr("Save as a new layout")
            detail: WindowLayouts.nextName()
            onClicked: {
                root.closeMenu();
                WindowLayouts.save(WindowLayouts.nextName());
            }
        }
        Choice {
            symbol: "settings"
            label: Translation.tr("Rename, delete, shortcuts…")
            onClicked: {
                root.closeMenu();
                GlobalStates.settingsOpen = true;
                Qt.callLater(() => {
                    GlobalStates.settingsPage = Translation.tr("Window layouts");
                });
            }
        }
    }
}
