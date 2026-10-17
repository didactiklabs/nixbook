import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The accounts (services/Accounts.qml) in the task widgets, as one round
 * button: "Add an account" until one is (Google's setup, then the browser
 * sign-in); afterwards it syncs the tasks now. Right click: the accounts
 * window.
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
            Todo.sync();
        else
            Accounts.connect();
    }
    altAction: () => Accounts.openWindow()

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: Accounts.connecting || Todo.syncing ? "hourglass_top"
            : Accounts.connected ? "sync" : "person_add"
        iconSize: Math.round(button.size * 0.55)
        horizontalAlignment: Text.AlignHCenter
        color: button.colIcon
    }

    StyledToolTip {
        text: Accounts.connecting ? Translation.tr("Finish signing in in your browser")
            : Accounts.connected ? Translation.tr("Sync your tasks now • right click: the accounts")
            : Translation.tr("Add an account to sync your tasks (Google Tasks…)")
    }
}
