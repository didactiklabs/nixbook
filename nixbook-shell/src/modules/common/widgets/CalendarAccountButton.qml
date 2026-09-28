import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * DankCalendar's state in the calendar and task widgets, as one round
 * button: "Connect a Google account" (the browser sign-in, dcal's built-in
 * OAuth client) while no account is connected; afterwards it opens dcal's
 * window (events, tasks, accounts), and right click syncs now.
 */
RippleButton {
    id: button
    property real size: 30
    property color colIcon: Appearance.colors.colOnLayer1

    visible: CalendarEvents.available
    implicitWidth: size
    implicitHeight: size
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    downAction: () => {
        if (CalendarEvents.hasAccounts)
            CalendarEvents.openApp();
        else
            CalendarEvents.connectGoogle();
    }
    altAction: () => {
        if (CalendarEvents.hasAccounts)
            CalendarEvents.sync();
        else
            CalendarEvents.openApp();
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: CalendarEvents.connecting ? "hourglass_top"
            : CalendarEvents.hasAccounts ? "edit_calendar" : "person_add"
        iconSize: Math.round(button.size * 0.55)
        horizontalAlignment: Text.AlignHCenter
        color: button.colIcon
    }

    StyledToolTip {
        text: CalendarEvents.connecting ? Translation.tr("Finish signing in in your browser")
            : CalendarEvents.hasAccounts ? Translation.tr("Open DankCalendar (events, tasks, accounts) • right click: sync now")
            : Translation.tr("Connect a Google account • right click: other accounts (DankCalendar)")
    }
}
