import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * The accounts (services/Accounts.qml) as a small window: the accounts,
 * sign in again, remove, add one (Google's one-time OAuth client setup
 * first). Opened by the apps and widgets that need an account (Contacts,
 * Tasks, the to-do widgets) or `nixbook-shell ipc call accounts launch`.
 */
Scope {
    id: root

    property bool everOpened: false

    Connections {
        target: GlobalStates
        function onAccountsOpenChanged() {
            if (!GlobalStates.accountsOpen) return
            root.everOpened = true
            Accounts.refreshStatus()
        }
    }

    Loader {
        active: root.everOpened

        sourceComponent: FloatingWindow {
            title: Translation.tr("Accounts")
            visible: GlobalStates.accountsOpen
            implicitWidth: 720
            implicitHeight: 780
            minimumSize: Qt.size(360, 420)
            color: Appearance.colors.colLayer0Base

            onClosed: GlobalStates.accountsOpen = false
            onVisibleChanged: {
                if (!visible && GlobalStates.accountsOpen)
                    GlobalStates.accountsOpen = false
            }

            AccountsContent {
                anchors.fill: parent
            }
        }
    }
}
