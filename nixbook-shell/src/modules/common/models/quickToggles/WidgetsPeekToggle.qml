import QtQuick
import qs
import qs.services
import qs.modules.common

// A peek at the desktop widgets over the windows (WidgetsPeek): the right
// panel closes, the widgets come up until a click on the empty space,
// Escape or this toggle again.
QuickToggleModel {
    name: Translation.tr("Widgets")
    statusText: GlobalStates.desktopWidgetsPeek ? Translation.tr("Showing") : Translation.tr("Peek")
    toggled: GlobalStates.desktopWidgetsPeek
    icon: "widgets"
    mainAction: () => {
        GlobalStates.desktopWidgetsPeek = !GlobalStates.desktopWidgetsPeek
    }
    tooltipText: Translation.tr("Peek at the desktop widgets over the windows (Mod+Shift+D)")
}
