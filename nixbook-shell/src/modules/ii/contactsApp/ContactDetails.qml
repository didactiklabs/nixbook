pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// One contact, read: photo, name, job; then each way to reach them (a click
// writes, calls or opens the map; the copy button copies), birthday,
// labels and notes. Star, edit and delete at the top.
Item {
    id: root
    property var contact: null
    property bool narrow: false
    signal editRequested()
    signal backRequested()

    // Delete asks first (Google keeps it 30 days in its Trash; others don't).
    property bool confirmDelete: false
    onContactChanged: root.confirmDelete = false

    readonly property var birthday: Contacts.nextBirthday(root.contact)
    readonly property var labelNames: (root.contact?.labels ?? []).map(id => Contacts.labelName(id)).filter(n => n !== "")

    function copy(text) {
        Quickshell.clipboardText = text
        copiedToast.restart()
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: column
            width: Math.min(parent.width - 40, 720)
            x: (parent.width - width) / 2
            y: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                ContactButton {
                    visible: root.narrow
                    icon: "arrow_back"
                    tip: Translation.tr("All contacts")
                    onClicked: root.backRequested()
                }
                Item { Layout.fillWidth: true }
                ContactButton {
                    icon: "star"
                    toggled: !!root.contact?.starred
                    tip: root.contact?.starred ? Translation.tr("Unstar") : Translation.tr("Star")
                    onClicked: Contacts.setStarred(root.contact.id, !root.contact.starred)
                }
                ContactButton {
                    icon: "edit"
                    tip: Translation.tr("Edit (Ctrl+E)")
                    onClicked: root.editRequested()
                }
                ContactButton {
                    icon: "delete"
                    tip: Translation.tr("Delete")
                    onClicked: root.confirmDelete = true
                }
            }

            // Delete?
            Rectangle {
                Layout.fillWidth: true
                visible: root.confirmDelete
                implicitHeight: confirmRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer
                RowLayout {
                    id: confirmRow
                    anchors { fill: parent; margins: 10; leftMargin: 16 }
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: Accounts.find(root.contact?.account ?? "")?.provider === "google"
                            ? Translation.tr("Delete %1 from your Google contacts? Google keeps it in its Trash for 30 days.").arg(Contacts.displayName(root.contact))
                            : Translation.tr("Delete %1 from %2? It is deleted on the server.").arg(Contacts.displayName(root.contact)).arg(Accounts.nameOf(root.contact?.account ?? ""))
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnErrorContainer
                    }
                    PanelButton {
                        compact: true
                        text: Translation.tr("Cancel")
                        onClicked: root.confirmDelete = false
                    }
                    PanelButton {
                        compact: true
                        filled: true
                        icon: "delete"
                        text: Translation.tr("Delete")
                        onClicked: {
                            root.confirmDelete = false
                            Contacts.remove(root.contact.id)
                            root.backRequested()
                        }
                    }
                }
            }

            ContactAvatar {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                contact: root.contact
                size: 112
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 8
                horizontalAlignment: Text.AlignHCenter
                text: Contacts.displayName(root.contact)
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                horizontalAlignment: Text.AlignHCenter
                text: [root.contact?.title, root.contact?.organization].filter(s => !!s).join(" · ")
                    + (root.contact?.nickname ? `${root.contact?.title || root.contact?.organization ? " · " : ""}“${root.contact.nickname}”` : "")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }
            // Which account, when there are several.
            StyledText {
                Layout.fillWidth: true
                visible: Accounts.several
                horizontalAlignment: Text.AlignHCenter
                text: Accounts.nameOf(root.contact?.account ?? "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // Labels
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                visible: root.labelNames.length > 0
                spacing: 6
                Repeater {
                    model: root.labelNames
                    delegate: Rectangle {
                        required property string modelData
                        implicitWidth: labelText.implicitWidth + 20
                        implicitHeight: 26
                        radius: 13
                        color: Appearance.colors.colSecondaryContainer
                        StyledText {
                            id: labelText
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }

            // Quick actions
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10
                Layout.bottomMargin: 6
                spacing: 10
                PanelButton {
                    visible: (root.contact?.emails?.length ?? 0) > 0
                    icon: "mail"
                    text: Translation.tr("Email")
                    onClicked: Qt.openUrlExternally(`mailto:${root.contact.emails[0].value}`)
                }
                PanelButton {
                    visible: (root.contact?.phones?.length ?? 0) > 0
                    icon: "call"
                    text: Translation.tr("Call")
                    onClicked: Qt.openUrlExternally(`tel:${root.contact.phones[0].value.replace(/\s/g, "")}`)
                }
                PanelButton {
                    visible: (root.contact?.phones?.length ?? 0) > 0
                    icon: "sms"
                    text: Translation.tr("Message")
                    onClicked: Qt.openUrlExternally(`sms:${root.contact.phones[0].value.replace(/\s/g, "")}`)
                }
            }

            // How to reach them
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: detailsColumn.implicitHeight + 16
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1Base
                visible: (root.contact?.emails?.length ?? 0) + (root.contact?.phones?.length ?? 0)
                    + (root.contact?.addresses?.length ?? 0) + (root.contact?.urls?.length ?? 0) > 0 || root.birthday !== null

                ColumnLayout {
                    id: detailsColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 0

                    Repeater {
                        model: root.contact?.emails ?? []
                        delegate: DetailRow {
                            required property var modelData
                            icon: "mail"
                            value: modelData.value
                            caption: Contacts.typeText(modelData.type)
                            onActivated: Qt.openUrlExternally(`mailto:${modelData.value}`)
                        }
                    }
                    Repeater {
                        model: root.contact?.phones ?? []
                        delegate: DetailRow {
                            required property var modelData
                            icon: "call"
                            value: modelData.value
                            caption: Contacts.typeText(modelData.type)
                            onActivated: Qt.openUrlExternally(`tel:${modelData.value.replace(/\s/g, "")}`)
                        }
                    }
                    Repeater {
                        model: root.contact?.addresses ?? []
                        delegate: DetailRow {
                            required property var modelData
                            icon: "location_on"
                            value: modelData.value
                            caption: Contacts.typeText(modelData.type)
                            onActivated: Qt.openUrlExternally(`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(modelData.value.replace(/\n/g, ", "))}`)
                        }
                    }
                    DetailRow {
                        visible: root.birthday !== null
                        icon: "cake"
                        value: {
                            const b = root.contact?.birthday ?? ""
                            const m = /^(\d{4}|-)-?(\d{2})-(\d{2})$/.exec(b)
                            if (!m) return b
                            const d = new Date(m[1].length === 4 ? Number(m[1]) : 2000, Number(m[2]) - 1, Number(m[3]))
                            return Qt.locale().toString(d, m[1].length === 4 ? "MMMM d, yyyy" : "MMMM d")
                        }
                        caption: !root.birthday ? ""
                            : root.birthday.days === 0 ? (root.birthday.age ? Translation.tr("Today! Turns %1").arg(root.birthday.age) : Translation.tr("Today!"))
                            : root.birthday.days === 1 ? (root.birthday.age ? Translation.tr("Turns %1 tomorrow").arg(root.birthday.age) : Translation.tr("Tomorrow"))
                            : root.birthday.age ? Translation.tr("Turns %1 in %2 days").arg(root.birthday.age).arg(root.birthday.days)
                            : Translation.tr("In %1 days").arg(root.birthday.days)
                    }
                    Repeater {
                        model: root.contact?.urls ?? []
                        delegate: DetailRow {
                            required property var modelData
                            icon: "link"
                            value: modelData.value
                            caption: Contacts.typeText(modelData.type)
                            // A web page only (a shared address book's card could point at a local file).
                            onActivated: {
                                if (/^https?:/i.test(modelData.value)) Qt.openUrlExternally(modelData.value)
                                else if (!/^[a-z][a-z0-9+.-]*:/i.test(modelData.value)) Qt.openUrlExternally(`https://${modelData.value}`)
                            }
                        }
                    }
                }
            }

            // Notes
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: (root.contact?.notes ?? "") !== ""
                implicitHeight: notesText.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1Base
                StyledText {
                    id: notesText
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    text: root.contact?.notes ?? ""
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 10
                horizontalAlignment: Text.AlignHCenter
                visible: (root.contact?.updated ?? "") !== ""
                text: Translation.tr("Changed %1").arg(Qt.locale().toString(new Date(root.contact?.updated ?? 0), "MMM d, yyyy"))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    // "Copied"
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
        visible: copiedToast.running
        implicitWidth: copiedText.implicitWidth + 32
        implicitHeight: 40
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3inverseSurface
        StyledText {
            id: copiedText
            anchors.centerIn: parent
            text: Translation.tr("Copied")
            color: Appearance.m3colors.m3inverseOnSurface
        }
        Timer {
            id: copiedToast
            interval: 1500
        }
    }

    // A way to reach them: icon, value, its type; a click uses it, the
    // button copies it.
    component DetailRow: Rectangle {
        id: row
        property string icon
        property string value
        property string caption
        signal activated()
        Layout.fillWidth: true
        implicitHeight: Math.max(52, rowLayout.implicitHeight + 16)
        radius: Appearance.rounding.normal
        color: rowMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.activated()
        }
        RowLayout {
            id: rowLayout
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 6 }
            spacing: 14
            MaterialSymbol {
                text: row.icon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.value
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    visible: text !== ""
                    text: row.caption
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            ContactButton {
                icon: "content_copy"
                tip: Translation.tr("Copy")
                onClicked: root.copy(row.value)
            }
        }
    }
}
