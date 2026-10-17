import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The calendars' state in the calendar widgets, as one round button: "Add
 * an account" (services/Accounts.qml: Google's setup and sign-in, or a
 * CalDAV server) while none is added; afterwards it opens the Calendar
 * window, and right click syncs now.
 */
RippleButton {
    id: button
    property real size: 30
    property color colIcon: Appearance.colors.colOnLayer1

    implicitWidth: size
    implicitHeight: size
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    Component.onCompleted: Accounts.load()

    downAction: () => {
        if (Accounts.connected)
            CalendarEvents.openApp();
        else
            Accounts.connect();
    }
    altAction: () => {
        if (Accounts.connected)
            CalendarEvents.sync();
        else
            Accounts.openWindow();
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: Accounts.connecting || CalendarEvents.syncing ? "hourglass_top"
            : Accounts.connected ? "edit_calendar" : "person_add"
        iconSize: Math.round(button.size * 0.55)
        horizontalAlignment: Text.AlignHCenter
        color: button.colIcon
    }

    StyledToolTip {
        text: Accounts.connecting ? Translation.tr("Finish signing in in your browser")
            : Accounts.connected ? Translation.tr("Open the calendar • right click: sync now")
            : Translation.tr("Add an account (Google, iCloud, Fastmail, Nextcloud…)")
    }
}
