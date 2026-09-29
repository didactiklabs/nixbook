pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on this
    property var action
    // Shared by every screen: shown here, changed through selectionModeSelected
    property var selectionMode
    // Signals
    signal dismiss()
    signal selectionModeSelected(var mode)

    // Tab index = RegionSelection.SelectionMode value
    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")},
            {"icon": "select_window", "name": Translation.tr("Window")},
            {"icon": "monitor", "name": Translation.tr("Screen")}
        ]
        currentIndex: root.selectionMode
        onCurrentIndexChanged: {
            if (currentIndex !== root.selectionMode)
                root.selectionModeSelected(currentIndex);
        }
    }
}
