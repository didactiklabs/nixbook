import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import qs.modules.ii.contactsApp

// Google Contacts (services/Contacts.qml): the birthdays of the next two
// weeks, then the starred contacts. A contact opens the Contacts app on
// them; the header opens it, its button syncs (or connects the account).
AbstractBackgroundWidget {
    id: root
    configEntryName: "contacts"
    hoverEnabled: true

    implicitWidth: 300
    implicitHeight: Math.max(200, column.implicitHeight + 32)

    Component.onCompleted: Contacts.load()

    // Ticks so "Today" and "Tomorrow" follow the date.
    property var now: new Date()
    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property var birthdays: Contacts.upcomingBirthdays(14, root.now).slice(0, 4)
    readonly property var favourites: Contacts.starred.slice(0, 8)

    WidgetShadow {
        target: card
        visible: Config.options.background.widgets.shadow
    }
    WidgetOutline {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Appearance.colors.colWidgetCard
        radius: Appearance.rounding?.verylarge ?? 30

        FastBlurred {
            anchors.fill: parent
            blurSource: root.wallpaperItem
            cardRadius: card.radius
            tint: Appearance.colors.colLayer1
            tintOpacity: 0.55
            trackX: root.x
            trackY: root.y
            visible: Config.options.background.widgets.blurWidgets
        }

        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: "contacts"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Contacts")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimaryContainer
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.openContactsApp("")
                    }
                }
                // Sync, or open the app to connect.
                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    color: syncMouse.containsMouse ? ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4) : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: !Contacts.connected ? "person_add" : Contacts.syncing ? "hourglass_top" : "sync"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    MouseArea {
                        id: syncMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Contacts.connected ? Contacts.sync() : Accounts.connect()
                    }
                    PopupToolTip {
                        text: Contacts.connected ? Translation.tr("Sync now") : Translation.tr("Connect a Google account")
                        extraVisibleCondition: syncMouse.containsMouse
                    }
                }
            }

            // Birthdays
            Repeater {
                model: root.birthdays
                delegate: Rectangle {
                    id: birthday
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Appearance.rounding.normal
                    color: birthdayMouse.containsMouse ? ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
                        : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.65)
                    MouseArea {
                        id: birthdayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.openContactsApp(birthday.modelData.contact.id)
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
                        spacing: 10
                        ContactAvatar {
                            contact: birthday.modelData.contact
                            size: 32
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Contacts.displayName(birthday.modelData.contact)
                                elide: Text.ElideRight
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: birthday.modelData.age ? Translation.tr("Turns %1").arg(birthday.modelData.age) : Translation.tr("Birthday")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            visible: birthday.modelData.days === 0
                            text: "cake"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Contacts.birthdayText(birthday.modelData)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            // Starred
            StyledText {
                visible: root.favourites.length > 0
                Layout.topMargin: root.birthdays.length > 0 ? 4 : 0
                text: Translation.tr("Starred")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colOnPrimaryContainer
            }
            GridLayout {
                Layout.fillWidth: true
                visible: root.favourites.length > 0
                columns: 4
                columnSpacing: 6
                rowSpacing: 8
                Repeater {
                    model: root.favourites
                    delegate: Item {
                        id: favourite
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: favouriteColumn.implicitHeight
                        ColumnLayout {
                            id: favouriteColumn
                            anchors { left: parent.left; right: parent.right }
                            spacing: 4
                            ContactAvatar {
                                Layout.alignment: Qt.AlignHCenter
                                contact: favourite.modelData
                                size: 44
                                scale: favouriteMouse.containsMouse ? 1.08 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: 120 }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: favourite.modelData.givenName || Contacts.displayName(favourite.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                        MouseArea {
                            id: favouriteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.openContactsApp(favourite.modelData.id)
                        }
                    }
                }
            }

            // Nothing to show
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 12
                visible: root.birthdays.length === 0 && root.favourites.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: !Contacts.statusKnown ? ""
                    : !Contacts.connected ? Translation.tr("Connect your Google account with the button above")
                    : Translation.tr("No birthdays in the next two weeks. Star contacts to keep them here")
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.8
            }
        }
    }
}
