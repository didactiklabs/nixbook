pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import qs.modules.ii.accounts
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// The Contacts window's content: the contacts on the left (search, labels,
// starred first, then A–Z), the selected one on the right, read or edited.
// Ctrl+N new contact, Ctrl+F search, Ctrl+E edit, F5 sync. Narrow (tiled
// in a slim column): the list, then the contact full width with a back
// arrow. Before an account is added: the accounts (AccountsContent).
Rectangle {
    id: root
    color: Appearance.colors.colLayer0Base
    clip: true

    property string selectedId: ""
    // "view", "edit" or "new".
    property string mode: "view"
    readonly property var selected: root.selectedId ? Contacts.find(root.selectedId) : null
    readonly property bool narrow: root.width < 760
    // Narrow: the contact instead of the list.
    property bool detailPage: false
    property string query: ""
    // "" all, "starred", "account:<id>", or a label id.
    property string filter: ""
    readonly property var shown: {
        const q = root.query
        const f = root.filter
        const account = f.startsWith("account:") ? f.slice(8) : ""
        return Contacts.sorted.filter(c => (f === "" || (f === "starred" ? c.starred : account ? c.account === account : c.labels.includes(f)))
            && Contacts.matches(c, q))
    }
    // The filter chips: all, starred, each account (several), the labels
    // (their account said when several).
    readonly property var chips: [{ id: "", name: Translation.tr("All"), count: Contacts.contacts.length },
            { id: "starred", name: Translation.tr("Starred"), count: Contacts.starred.length, icon: "star" }]
        .concat(Accounts.several ? Accounts.accounts.map(a => ({ id: `account:${a.id}`, name: Accounts.shortName(a.id), icon: "account_circle",
            count: Contacts.contacts.filter(c => c.account === a.id).length })) : [])
        .concat(Contacts.labels.map(l => ({ id: l.id, name: Accounts.several ? `${l.name} · ${Accounts.shortName(l.account)}` : l.name, count: l.count })))
    readonly property bool ready: Contacts.connected || Contacts.contacts.length > 0

    function opened(contactId) {
        if (contactId && Contacts.find(contactId)) root.select(contactId)
        else if (!root.selectedId && root.shown.length > 0 && !root.narrow) root.select(root.shown[0].id)
        root.forceActiveFocus()
    }

    function select(contactId) {
        root.selectedId = contactId
        root.mode = "view"
        root.detailPage = true
    }

    function newContact() {
        root.mode = "new"
        root.detailPage = true
    }

    // The heading a contact goes under: Starred, else its initial.
    function sectionOf(c) {
        if (c.starred && root.filter !== "starred") return Translation.tr("Starred")
        const first = Contacts.fold(Contacts.displayName(c))[0] ?? "#"
        return /[a-z]/.test(first) ? first.toUpperCase() : "#"
    }

    // "just now", "5 min ago", "14:32", "Oct 3".
    function syncedText(ms) {
        if (!ms) return Translation.tr("Not synced yet")
        const minutes = Math.floor((Date.now() - ms) / 60000)
        if (minutes < 1) return Translation.tr("Synced just now")
        if (minutes < 60) return Translation.tr("Synced %1 min ago").arg(minutes)
        const d = new Date(ms)
        const today = new Date().toDateString() === d.toDateString()
        return Translation.tr("Synced %1").arg(Qt.locale().toString(d, today ? (Config.options?.time.format ?? "hh:mm") : "MMM d"))
    }
    // Ticks so "5 min ago" follows the clock.
    property real now: Date.now()
    Timer {
        interval: 30000
        // The window stays loaded once opened: tick only while it's shown.
        running: GlobalStates.contactsAppOpen
        triggeredOnStart: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // The selected contact deleted (here, in Google, by an agent): back to
    // the list.
    Connections {
        target: Contacts
        function onContactsChanged() {
            if (root.selectedId && root.mode === "view" && !Contacts.find(root.selectedId)) {
                root.selectedId = ""
                root.detailPage = false
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_F5) {
            Contacts.sync()
            event.accepted = true
            return
        }
        if (!(event.modifiers & Qt.ControlModifier) || !root.ready) return
        if (event.key === Qt.Key_N) {
            root.newContact()
            event.accepted = true
        } else if (event.key === Qt.Key_F) {
            if (root.narrow) root.detailPage = false
            searchField.forceActiveFocus()
            event.accepted = true
        } else if (event.key === Qt.Key_E && root.selected && root.mode === "view") {
            root.mode = "edit"
            event.accepted = true
        }
    }

    AccountsContent {
        anchors.fill: parent
        visible: Contacts.statusKnown && !root.ready
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        visible: root.ready

        // The contacts
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: root.narrow
            Layout.preferredWidth: root.narrow ? -1 : 360
            visible: !root.narrow || !root.detailPage
            color: Appearance.colors.colLayer1Base

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 10
                    MaterialSymbol {
                        text: "contacts"
                        iconSize: 28
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Contacts")
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnLayer1
                    }
                    PanelButton {
                        icon: "person_add"
                        text: Translation.tr("New")
                        filled: true
                        onClicked: root.newContact()
                    }
                }

                // Search
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2Base
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 8
                        MaterialSymbol {
                            text: "search"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Search names, emails, phones")
                            placeholderTextColor: Appearance.colors.colSubtext
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.main
                            background: null
                            onTextChanged: root.query = text
                            Keys.onEscapePressed: event => {
                                text = ""
                                root.forceActiveFocus()
                                event.accepted = true
                            }
                            // Enter opens the first match.
                            onAccepted: if (root.shown.length > 0) root.select(root.shown[0].id)
                        }
                        MaterialSymbol {
                            visible: searchField.text !== ""
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: searchField.text = ""
                            }
                        }
                    }
                }

                // All, starred, the labels
                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: chips.implicitHeight
                    contentWidth: chips.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    Row {
                        id: chips
                        spacing: 6
                        Repeater {
                            model: root.chips
                            delegate: PanelButton {
                                required property var modelData
                                compact: true
                                toggled: root.filter === modelData.id
                                icon: modelData.icon ?? ""
                                text: modelData.name
                                trailingText: String(modelData.count)
                                onClicked: root.filter = modelData.id
                            }
                        }
                    }
                }

                StyledListView {
                    id: contactsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.shown

                    delegate: ColumnLayout {
                        id: contactItem
                        required property var modelData
                        required property int index
                        readonly property bool current: root.mode !== "new" && root.selectedId === modelData.id
                        readonly property string section: root.sectionOf(modelData)
                        readonly property bool firstOfSection: index === 0 || root.sectionOf(root.shown[index - 1]) !== section
                        width: contactsList.width
                        spacing: 2

                        StyledText {
                            visible: contactItem.firstOfSection
                            Layout.leftMargin: 14
                            Layout.topMargin: contactItem.index === 0 ? 0 : 8
                            text: contactItem.section
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 60
                            radius: Appearance.rounding.normal
                            color: contactItem.current ? Appearance.colors.colSecondaryContainer
                                : itemMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.select(contactItem.modelData.id)
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
                                spacing: 12
                                ContactAvatar {
                                    contact: contactItem.modelData
                                    size: 40
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Contacts.displayName(contactItem.modelData)
                                        elide: Text.ElideRight
                                        font.weight: Font.Medium
                                        color: contactItem.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: {
                                            const c = contactItem.modelData
                                            return (c.name ? [c.organization] : []).concat([c.emails[0]?.value, c.phones[0]?.value]).filter(s => !!s)[0] ?? ""
                                        }
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 20
                    visible: root.shown.length === 0
                    text: root.query.trim() ? Translation.tr("No contact matches \"%1\"").arg(root.query.trim())
                        : Contacts.syncing ? Translation.tr("Syncing your contacts…")
                        : Translation.tr("No contacts here yet. Ctrl+N adds one")
                    color: Appearance.colors.colSubtext
                }

                // Sync state, account
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            root.now
                            return Contacts.syncing ? Translation.tr("Syncing…") : root.syncedText(Contacts.syncedAt)
                        }
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        PopupToolTip {
                            text: Accounts.accounts.map(a => a.name).join("\n")
                            extraVisibleCondition: syncedMouse.containsMouse && Accounts.connected
                        }
                        MouseArea {
                            id: syncedMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                    ContactButton {
                        icon: "sync"
                        tip: Translation.tr("Sync now (F5)")
                        onClicked: Contacts.sync()
                    }
                    ContactButton {
                        icon: "manage_accounts"
                        tip: Translation.tr("Accounts")
                        onClicked: Accounts.openWindow()
                    }
                }
            }
        }

        Rectangle {
            visible: !root.narrow
            Layout.fillHeight: true
            implicitWidth: 1
            color: Appearance.colors.colOutlineVariant
        }

        // The contact
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.narrow || root.detailPage
            spacing: 0

            // Google's last answer, when it was a failure.
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 12
                visible: messageText.text !== ""
                implicitHeight: messageRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer
                RowLayout {
                    id: messageRow
                    anchors { fill: parent; margins: 8; leftMargin: 14 }
                    MaterialSymbol {
                        text: "error"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        id: messageText
                        Layout.fillWidth: true
                        text: root.mode === "view" ? (Contacts.lastError || Contacts.error) : ""
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnErrorContainer
                    }
                    // An account signed out: its contacts stay, sign in again.
                    PanelButton {
                        visible: Accounts.accounts.some(a => !a.connected)
                        compact: true
                        icon: "login"
                        text: Accounts.connecting ? Translation.tr("Waiting for the browser…") : Translation.tr("Sign in again")
                        onClicked: Accounts.connect()
                    }
                    ContactButton {
                        icon: "close"
                        tip: Translation.tr("Dismiss")
                        onClicked: {
                            Contacts.lastError = ""
                            Contacts.error = ""
                        }
                    }
                }
            }

            ContactDetails {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.mode === "view" && root.selected !== null
                contact: root.selected
                narrow: root.narrow
                onEditRequested: root.mode = "edit"
                onBackRequested: root.detailPage = false
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.mode !== "view"
                visible: active
                sourceComponent: ContactEditor {
                    contact: root.mode === "edit" ? root.selected : null
                    narrow: root.narrow
                    focus: true
                    onDone: contactId => {
                        root.select(contactId)
                        root.forceActiveFocus()
                    }
                    onCancelled: {
                        root.mode = "view"
                        if (!root.selected) root.detailPage = false
                        root.forceActiveFocus()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.mode === "view" && root.selected === null
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "contacts"
                        iconSize: 64
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Pick a contact, or add one")
                        color: Appearance.colors.colSubtext
                    }
                    PanelButton {
                        Layout.alignment: Qt.AlignHCenter
                        icon: "person_add"
                        text: Translation.tr("New contact")
                        filled: true
                        onClicked: root.newContact()
                    }
                }
            }
        }
    }
}
