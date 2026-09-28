pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false

    spacing: 3

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    // Popups and the notification centre use the Persona phone-chat look
    // while the Persona style is on.
    readonly property bool personaStyle: Persona.shapes
    delegate: root.personaStyle ? personaDelegate : groupDelegate

    Component {
        id: groupDelegate
        NotificationGroup {
            required property int index
            required property var modelData
            popup: root.popup
            width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
            notificationGroup: popup ?
                Notifications.popupGroupsByAppName[modelData] :
                Notifications.groupsByAppName[modelData]
        }
    }
    Component {
        id: personaDelegate
        PersonaMessage {
            required property int index
            required property var modelData
            width: ListView.view.width
            popup: root.popup
            notificationGroup: root.popup ?
                Notifications.popupGroupsByAppName[modelData] :
                Notifications.groupsByAppName[modelData]
        }
    }
}
