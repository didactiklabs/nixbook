import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Contacts: every account's contacts (services/Contacts.qml, merged by
 * nixbook-accounts) as an app. The contacts on the left (search, accounts,
 * labels, starred first), the selected one on the right: call, write, copy,
 * edit.
 *
 * A normal application window (xdg-toplevel, title "Contacts"), tiled like
 * any app: its layout follows the width it gets. Opened from the contacts
 * widget (GlobalStates.openContactsApp), its launcher entry or
 * `nixbook-shell ipc call contacts launch|open <id>`.
 */
Scope {
    id: root

    property bool everOpened: false

    Connections {
        target: GlobalStates
        function onContactsAppOpenChanged() {
            if (!GlobalStates.contactsAppOpen) return
            root.everOpened = true
            Contacts.load()
            Contacts.sync()
        }
    }

    Loader {
        active: root.everOpened

        sourceComponent: FloatingWindow {
            id: contactsWindow
            title: Translation.tr("Contacts")
            visible: GlobalStates.contactsAppOpen
            implicitWidth: 1100
            implicitHeight: 760
            minimumSize: Qt.size(360, 420)
            color: Appearance.colors.colLayer0Base

            // The compositor closing it (Mod+Q…) closes the app.
            onClosed: GlobalStates.contactsAppOpen = false
            onVisibleChanged: {
                if (!visible && GlobalStates.contactsAppOpen)
                    GlobalStates.contactsAppOpen = false
                if (visible) content.opened(GlobalStates.contactsAppContactId)
            }
            Component.onCompleted: content.opened(GlobalStates.contactsAppContactId)

            // Another contact clicked in the widget while it is open.
            Connections {
                target: GlobalStates
                function onContactsAppContactIdChanged() {
                    if (contactsWindow.visible && GlobalStates.contactsAppContactId)
                        content.opened(GlobalStates.contactsAppContactId)
                }
            }

            ContactsAppContent {
                id: content
                anchors.fill: parent
                focus: true
            }
        }
    }
}
