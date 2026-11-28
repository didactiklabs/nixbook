import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The bell: opens the right panel on its notifications (again: closes it;
// a pinned panel just shows them), right click turns Do not disturb on or
// off. The unread count on it (bar.indicators.notifications.showUnreadCount).
RippleButton {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property bool onNotifications: (Persistent.states.sidebar?.tab ?? "") === "notifications"

    implicitWidth: 32
    implicitHeight: 32

    buttonRadius: Appearance.rounding.full
    colBackground: isMaterial ? Appearance.colors.colPrimaryContainer : "transparent"
    colBackgroundHover: isMaterial ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarRightOpen

    // For the hover card (StyledPopup reads containsMouse).
    HoverHandler { id: hover }
    readonly property bool containsMouse: hover.hovered

    onClicked: {
        // Already on the notifications: closes the panel (a pinned one stays).
        if (GlobalStates.sidebarRightOpen && root.onNotifications && GlobalStates.sidebarRightDialogShown === "") {
            if (!GlobalStates.sidebarRightPinned) GlobalStates.sidebarRightOpen = false;
            return;
        }
        Persistent.states.sidebar.tab = "notifications";
        if (GlobalStates.sidebarRightDialogShown !== "") GlobalStates.sidebarRightDialog = "none";
        GlobalStates.sidebarRightOpen = true;
    }
    altAction: () => {
        Notifications.silent = !Notifications.silent;
    }

    NotificationUnreadCount {
        anchors.centerIn: parent
    }

    StyledPopup {
        hoverTarget: root
        ColumnLayout {
            spacing: 2
            StyledText {
                text: Notifications.silent ? Translation.tr("Do not disturb")
                    : Notifications.unread > 0 ? Translation.tr("%1 unread notification(s)").arg(Notifications.unread)
                    : Translation.tr("Notifications")
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                text: Notifications.silent
                    ? Translation.tr("Click: the right panel · right click: Do not disturb off")
                    : Translation.tr("Click: the right panel · right click: Do not disturb")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.italic: true
                color: Appearance.colors.colSubtext
            }
        }
    }
}
