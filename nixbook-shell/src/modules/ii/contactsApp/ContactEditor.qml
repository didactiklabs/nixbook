pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A contact being edited (or a new one, `contact` null): names, job,
// emails, phones, addresses, birthday, links, labels, notes. Save sends
// Google only what changed (Ctrl+S); Escape or Cancel drops the edits.
Item {
    id: root
    property var contact: null
    property bool narrow: false
    signal done(string contactId)
    signal cancelled()

    readonly property bool isNew: root.contact === null
    // The account it is in (a new one: the one picked, the first by default).
    property string account: ""
    readonly property var accountLabels: Contacts.labels.filter(l => l.account === root.account)
    property bool saving: false
    property string error: ""

    // The form's state: plain copies, edited in place, re-assigned to
    // refresh the lists.
    property var emails: []
    property var phones: []
    property var addresses: []
    property var urls: []
    property var labels: []
    property bool starred: false

    readonly property var emailTypes: ["home", "work", "other"]
    readonly property var phoneTypes: ["mobile", "home", "work", "main", "other"]
    readonly property var addressTypes: ["home", "work", "other"]
    readonly property var urlTypes: ["homePage", "work", "blog", "profile", "other"]

    function load() {
        const c = root.contact
        root.error = ""
        root.saving = false
        givenField.text = c?.givenName ?? ""
        familyField.text = c?.familyName ?? ""
        // A name Google couldn't split (or a company only) in the first field.
        if (c && !c.givenName && !c.familyName) givenField.text = c.name ?? ""
        nicknameField.text = c?.nickname ?? ""
        orgField.text = c?.organization ?? ""
        titleField.text = c?.title ?? ""
        birthdayField.text = (c?.birthday ?? "").replace(/^--/, "")
        notesField.text = c?.notes ?? ""
        root.emails = (c?.emails ?? []).map(e => ({ value: e.value, type: e.type }))
        root.phones = (c?.phones ?? []).map(e => ({ value: e.value, type: e.type }))
        root.urls = (c?.urls ?? []).map(e => ({ value: e.value, type: e.type }))
        root.addresses = (c?.addresses ?? []).map(a => ({ type: a.type,
            street: a.street || (a.city || a.postalCode || a.country ? "" : a.value), city: a.city,
            postalCode: a.postalCode, region: a.region, country: a.country }))
        if (root.isNew) {
            root.emails = [{ value: "", type: "" }]
            root.phones = [{ value: "", type: "mobile" }]
        }
        root.labels = (c?.labels ?? []).slice(0)
        root.account = c?.account ?? Accounts.accounts[0]?.id ?? ""
        root.starred = !!c?.starred
        givenField.forceActiveFocus()
    }
    onContactChanged: root.load()
    Component.onCompleted: root.load()

    function clean(list, keys) {
        return list.filter(e => keys.some(k => (e[k] ?? "").trim() !== ""))
            .map(e => { const o = {}; for (const k in e) o[k] = (e[k] ?? "").trim(); return o })
    }
    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b)
    }

    // Only what changed, for an update; everything filled in, for a new one.
    function fields() {
        const c = root.contact
        const f = {}
        const given = givenField.text.trim(), family = familyField.text.trim()
        if (root.isNew || given !== (c.givenName || (c.familyName ? "" : c.name)) || family !== (c.familyName ?? "")) {
            f.givenName = given
            f.familyName = family
        }
        const text = { nickname: nicknameField.text.trim(), organization: orgField.text.trim(), title: titleField.text.trim(),
            birthday: birthdayField.text.trim(), notes: notesField.text }
        for (const k in text) {
            const before = k === "birthday" ? (c?.birthday ?? "").replace(/^--/, "") : (c?.[k] ?? "")
            if (root.isNew ? text[k] !== "" : text[k] !== before) f[k] = text[k]
        }
        const lists = {
            emails: [root.clean(root.emails, ["value"]), (c?.emails ?? []).map(e => ({ value: e.value, type: e.type }))],
            phones: [root.clean(root.phones, ["value"]), (c?.phones ?? []).map(e => ({ value: e.value, type: e.type }))],
            urls: [root.clean(root.urls, ["value"]), (c?.urls ?? []).map(e => ({ value: e.value, type: e.type }))],
        }
        for (const k in lists) {
            if (root.isNew ? lists[k][0].length > 0 : !root.same(lists[k][0], lists[k][1])) f[k] = lists[k][0]
        }
        const addresses = root.clean(root.addresses, ["street", "city", "postalCode", "region", "country"])
        const before = (c?.addresses ?? []).map(a => ({ type: a.type,
            street: a.street || (a.city || a.postalCode || a.country ? "" : a.value), city: a.city,
            postalCode: a.postalCode, region: a.region, country: a.country }))
        if (root.isNew ? addresses.length > 0 : !root.same(addresses, root.clean(before, ["street", "city", "postalCode", "region", "country"])))
            f.addresses = addresses
        if (root.isNew ? root.labels.length > 0 : !root.same(root.labels.slice().sort(), (c.labels ?? []).slice().sort()))
            f.labels = root.labels
        if (root.isNew ? root.starred : root.starred !== !!c.starred) f.starred = root.starred
        return f
    }

    function save() {
        if (root.saving) return
        const f = root.fields()
        if (!root.isNew && Object.keys(f).length === 0) {
            root.done(root.contact.id)
            return
        }
        if (root.isNew && !f.givenName && !f.familyName && !f.organization && !f.emails && !f.phones) {
            root.error = Translation.tr("Give a name, a company, an email or a phone number")
            return
        }
        root.saving = true
        root.error = ""
        const finish = r => {
            root.saving = false
            if (r?.ok) root.done(r.result.id)
            else root.error = r?.error ?? Translation.tr("Couldn't save")
        }
        if (root.isNew) Contacts.create(Object.assign({ account: root.account }, f), finish)
        else Contacts.update(root.contact.id, f, finish)
    }

    function nextType(types, current) {
        const i = types.indexOf(current)
        return types[(i + 1) % types.length]
    }

    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
            root.save()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            root.cancelled()
            event.accepted = true
        }
    }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top }
        contentHeight: form.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: form
            width: Math.min(parent.width - 40, 680)
            x: (parent.width - width) / 2
            y: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ContactAvatar {
                    contact: root.contact
                    size: 48
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.isNew ? Translation.tr("New contact") : Translation.tr("Edit contact")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }
                ContactButton {
                    icon: "star"
                    toggled: root.starred
                    tip: root.starred ? Translation.tr("Starred") : Translation.tr("Star")
                    onClicked: root.starred = !root.starred
                }
            }

            // A new contact's account, when there are several.
            Flow {
                Layout.fillWidth: true
                visible: root.isNew && Accounts.several
                spacing: 6
                StyledText {
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("In")
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: Accounts.accounts
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        toggled: root.account === modelData.id
                        icon: toggled ? "check" : ""
                        text: modelData.name
                        onClicked: {
                            root.account = modelData.id
                            // Labels are per account.
                            root.labels = root.labels.filter(l => !l.includes(":"))
                        }
                    }
                }
            }

            Section { icon: "person"; title: Translation.tr("Name") }
            GridLayout {
                Layout.fillWidth: true
                columns: root.narrow ? 1 : 2
                columnSpacing: 10
                rowSpacing: 10
                MaterialTextField {
                    id: givenField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("First name")
                    KeyNavigation.tab: familyField
                }
                MaterialTextField {
                    id: familyField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Last name")
                }
                MaterialTextField {
                    id: orgField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Company")
                }
                MaterialTextField {
                    id: titleField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Job title")
                }
                MaterialTextField {
                    id: nicknameField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Nickname")
                }
                MaterialTextField {
                    id: birthdayField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Birthday: YYYY-MM-DD or MM-DD")
                    inputMethodHints: Qt.ImhDate
                }
            }

            Section { icon: "mail"; title: Translation.tr("Email") }
            Repeater {
                model: root.emails
                delegate: ValueRow {
                    required property var modelData
                    required property int index
                    entries: root.emails
                    entryIndex: index
                    types: root.emailTypes
                    placeholder: Translation.tr("Email")
                    onEdited: list => root.emails = list
                }
            }
            AddButton {
                text: Translation.tr("Add an email")
                onClicked: root.emails = root.emails.concat([{ value: "", type: "" }])
            }

            Section { icon: "call"; title: Translation.tr("Phone") }
            Repeater {
                model: root.phones
                delegate: ValueRow {
                    required property var modelData
                    required property int index
                    entries: root.phones
                    entryIndex: index
                    types: root.phoneTypes
                    placeholder: Translation.tr("Phone")
                    onEdited: list => root.phones = list
                }
            }
            AddButton {
                text: Translation.tr("Add a phone")
                onClicked: root.phones = root.phones.concat([{ value: "", type: "mobile" }])
            }

            Section { icon: "location_on"; title: Translation.tr("Address") }
            Repeater {
                model: root.addresses
                delegate: ColumnLayout {
                    id: addressItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 8
                    function set(key, value) {
                        root.addresses[addressItem.index][key] = value
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Street")
                            text: addressItem.modelData.street ?? ""
                            onTextEdited: addressItem.set("street", text)
                        }
                        TypeChip {
                            type: addressItem.modelData.type ?? ""
                            onClicked: {
                                root.addresses[addressItem.index].type = root.nextType(root.addressTypes, addressItem.modelData.type)
                                root.addresses = root.addresses.slice(0)
                            }
                        }
                        ContactButton {
                            icon: "close"
                            tip: Translation.tr("Remove")
                            onClicked: root.addresses = root.addresses.filter((_, i) => i !== addressItem.index)
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.rightMargin: 48
                        columns: root.narrow ? 2 : 4
                        columnSpacing: 8
                        rowSpacing: 8
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Postal code")
                            text: addressItem.modelData.postalCode ?? ""
                            onTextEdited: addressItem.set("postalCode", text)
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("City")
                            text: addressItem.modelData.city ?? ""
                            onTextEdited: addressItem.set("city", text)
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Region")
                            text: addressItem.modelData.region ?? ""
                            onTextEdited: addressItem.set("region", text)
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Country")
                            text: addressItem.modelData.country ?? ""
                            onTextEdited: addressItem.set("country", text)
                        }
                    }
                }
            }
            AddButton {
                text: Translation.tr("Add an address")
                onClicked: root.addresses = root.addresses.concat([{ street: "", city: "", postalCode: "", region: "", country: "", type: "home" }])
            }

            Section { icon: "link"; title: Translation.tr("Website") }
            Repeater {
                model: root.urls
                delegate: ValueRow {
                    required property var modelData
                    required property int index
                    entries: root.urls
                    entryIndex: index
                    types: root.urlTypes
                    placeholder: Translation.tr("Website")
                    onEdited: list => root.urls = list
                }
            }
            AddButton {
                text: Translation.tr("Add a website")
                onClicked: root.urls = root.urls.concat([{ value: "", type: "" }])
            }

            Section { icon: "label"; title: Translation.tr("Labels") }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.accountLabels
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        toggled: root.labels.includes(modelData.id)
                        icon: toggled ? "check" : ""
                        text: modelData.name
                        onClicked: root.labels = toggled ? root.labels.filter(l => l !== modelData.id) : root.labels.concat([modelData.id])
                    }
                }
                // A new label, made on save (by name).
                Repeater {
                    model: root.labels.filter(l => !root.accountLabels.some(x => x.id === l))
                    delegate: PanelButton {
                        required property string modelData
                        compact: true
                        toggled: true
                        icon: "new_label"
                        text: modelData
                        onClicked: root.labels = root.labels.filter(l => l !== modelData)
                    }
                }
                MaterialTextField {
                    id: newLabelField
                    width: 180
                    placeholderText: Translation.tr("New label")
                    onAccepted: {
                        const name = text.trim()
                        if (name && !root.labels.includes(name)) root.labels = root.labels.concat([name])
                        text = ""
                    }
                }
            }

            Section { icon: "notes"; title: Translation.tr("Notes") }
            MaterialTextArea {
                id: notesField
                Layout.fillWidth: true
                Layout.minimumHeight: 100
                placeholderText: Translation.tr("Notes")
                wrapMode: TextEdit.Wrap
            }
        }
    }

    // Save / Cancel
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        implicitHeight: footerRow.implicitHeight + 24
        color: Appearance.colors.colLayer0Base
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Appearance.colors.colOutlineVariant
        }
        RowLayout {
            id: footerRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 20 }
            spacing: 10
            StyledText {
                Layout.fillWidth: true
                text: root.error
                wrapMode: Text.Wrap
                color: Appearance.colors.colError
            }
            PanelButton {
                text: Translation.tr("Cancel")
                onClicked: root.cancelled()
            }
            PanelButton {
                filled: true
                icon: root.saving ? "progress_activity" : "check"
                text: root.saving ? Translation.tr("Saving…") : Translation.tr("Save")
                onClicked: root.save()
            }
        }
    }

    component Section: RowLayout {
        property string icon
        property string title
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 8
        MaterialSymbol {
            text: parent.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colPrimary
        }
        StyledText {
            text: parent.title
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer0
        }
    }

    component AddButton: PanelButton {
        compact: true
        icon: "add"
        Layout.alignment: Qt.AlignLeft
    }

    // Google's type of an entry; a click picks the next one.
    component TypeChip: PanelButton {
        property string type
        compact: true
        text: Contacts.typeText(type) || Translation.tr("Type")
        implicitWidth: 104
    }

    // An email, phone or link: its value, type and remove button.
    component ValueRow: RowLayout {
        id: valueRow
        property var entries
        property int entryIndex
        property var types
        property string placeholder
        signal edited(var list)
        Layout.fillWidth: true
        spacing: 8
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: valueRow.placeholder
            text: valueRow.entries[valueRow.entryIndex]?.value ?? ""
            // In place: re-assigning the list would rebuild this field.
            onTextEdited: valueRow.entries[valueRow.entryIndex].value = text
        }
        TypeChip {
            type: valueRow.entries[valueRow.entryIndex]?.type ?? ""
            onClicked: {
                const list = valueRow.entries.slice(0)
                list[valueRow.entryIndex] = Object.assign({}, list[valueRow.entryIndex], {
                    type: root.nextType(valueRow.types, list[valueRow.entryIndex].type) })
                valueRow.edited(list)
            }
        }
        ContactButton {
            icon: "close"
            tip: Translation.tr("Remove")
            onClicked: valueRow.edited(valueRow.entries.filter((_, i) => i !== valueRow.entryIndex))
        }
    }
}
