import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

// Per-screen toggle for a `screenList` config entry ([] = all screens).
// Compositor-agnostic (Quickshell.screens; upstream listed Hyprland monitors,
// so it was empty under niri) and aware of Nix pinning: when `configKey` is
// pinned the buttons are disabled and a red lock is shown.
Flow {
    id: root
    required property var configEntry
    property string configKey: ""
    readonly property bool nixManaged: configKey !== "" && NixManaged.isPinned(configKey)
    // Settings menu "Editable only" filter: locked settings drop out of the
    // list (containers hide once empty, see NixManaged.allFiltered).
    readonly property bool filteredOut: nixManaged && NixManaged.hideLocked
    Binding on visible {
        when: root.filteredOut
        value: false
    }
    readonly property var screenNames: Quickshell.screens.map(s => s.name)
    Layout.fillWidth: true
    spacing: 2

    SelectionGroupButton {
        leftmost: true
        rightmost: root.screenNames.length === 0
        enabled: !root.nixManaged
        buttonIcon: "tv_displays"
        buttonText: Translation.tr("All")
        toggled: root.configEntry.screenList.length === 0
        onClicked: root.configEntry.screenList = []
    }

    Repeater {
        model: root.screenNames
        delegate: SelectionGroupButton {
            required property string modelData
            required property int index
            leftmost: false
            rightmost: index === root.screenNames.length - 1
            enabled: !root.nixManaged
            buttonIcon: "monitor"
            buttonText: modelData
            toggled: root.configEntry.screenList.includes(modelData)
            onClicked: {
                const allNames = root.screenNames.slice();
                let list = root.configEntry.screenList.length === 0 ? allNames.slice() : root.configEntry.screenList.slice();
                if (toggled) list = list.filter(s => s !== modelData);
                else list.push(modelData);
                root.configEntry.screenList = list.length === allNames.length ? [] : list;
            }
        }
    }

    NixManagedBadge {
        pinned: root.nixManaged
    }
}
