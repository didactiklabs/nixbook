pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// An event, editable (a new one with `creating`, starting at `newStart`):
// title, all day, start and end, calendar, repeat, reminders, place,
// notes; Join for a meeting. An occurrence of a series asks which to
// change or delete: this one or all of them. A read-only calendar's event
// is shown, not edited. Save (Ctrl+S) sends only what changed.
Item {
    id: root
    property var event: null
    property bool creating: false
    property var newStart: null
    property bool narrow: false
    signal closed()

    readonly property bool readOnly: !root.creating && !!root.event?.readOnly
    property bool saving: false
    property string error: ""
    // An occurrence of a series: "this" or "all".
    property string scope: "this"
    property bool confirmDelete: false

    // The form's state.
    property bool allDay: false
    property var startDay: new Date()
    property var endDay: new Date()
    property string calendarId: ""
    property string repeat: "none"
    // null: the calendar's own reminders.
    property var reminders: null

    readonly property var repeats: [
        { key: "none", name: Translation.tr("Doesn't repeat") }, { key: "daily", name: Translation.tr("Daily") },
        { key: "weekdays", name: Translation.tr("Weekdays") }, { key: "weekly", name: Translation.tr("Weekly") },
        { key: "monthly", name: Translation.tr("Monthly") }, { key: "yearly", name: Translation.tr("Yearly") },
    ]
    readonly property var reminderChoices: [0, 5, 10, 30, 60, 1440]
    function reminderText(m) {
        if (m === 0) return Translation.tr("At the start")
        if (m < 60) return Translation.tr("%1 min").arg(m)
        if (m < 1440) return Translation.tr("%1 h").arg(m / 60)
        return Translation.tr("%1 day").arg(m / 1440)
    }
    // The calendars it can go in: any writable one for a new event, its
    // account's for an existing one.
    readonly property var calendars: CalendarEvents.writableCalendars.filter(c => root.creating || c.account === root.event?.account)

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function hhmm(d) { return `${root.pad(d.getHours())}:${root.pad(d.getMinutes())}` }

    function load() {
        root.error = ""
        root.saving = false
        root.confirmDelete = false
        root.scope = "this"
        const e = root.event
        if (root.creating) {
            const s = root.newStart ?? new Date()
            titleField.text = ""
            root.allDay = false
            root.startDay = new Date(s.getFullYear(), s.getMonth(), s.getDate())
            root.endDay = root.startDay
            startTime.text = root.hhmm(s)
            endTime.text = root.hhmm(new Date(s.getTime() + 3600000))
            root.calendarId = (CalendarEvents.writableCalendars.find(c => c.primary) ?? CalendarEvents.writableCalendars[0])?.id ?? ""
            root.repeat = "none"
            root.reminders = null
            locationField.text = ""
            notesField.text = ""
            titleField.forceActiveFocus()
            return
        }
        if (!e) return
        titleField.text = e.summary === Translation.tr("(No title)") ? "" : e.summary
        root.allDay = e.allDay
        root.startDay = new Date(e.start.getFullYear(), e.start.getMonth(), e.start.getDate())
        // An all-day end is exclusive: its last day shown.
        const last = e.allDay ? new Date(e.end.getFullYear(), e.end.getMonth(), e.end.getDate() - 1) : e.end
        root.endDay = new Date(last.getFullYear(), last.getMonth(), last.getDate())
        startTime.text = root.hhmm(e.start)
        endTime.text = root.hhmm(e.end)
        root.calendarId = e.calendarId
        root.repeat = e.recurring ? "keep" : "none"
        root.reminders = null
        locationField.text = e.location
        notesField.text = e.description
    }
    onEventChanged: root.load()
    onCreatingChanged: if (root.creating) root.load()
    onNewStartChanged: if (root.creating) root.load()

    // The start and end the form says, as nixbook-accounts takes them.
    function times() {
        const day = d => CalendarEvents.dayKey(d)
        if (root.allDay) return { start: day(root.startDay), end: day(root.endDay < root.startDay ? root.startDay : root.endDay), allDay: true }
        const re = /^(\d{1,2})[:h.](\d{2})$/
        const s = re.exec(startTime.text.trim()), e = re.exec(endTime.text.trim())
        if (!s || !e) return null
        return { start: `${day(root.startDay)}T${root.pad(Number(s[1]))}:${s[2]}`, end: `${day(root.endDay)}T${root.pad(Number(e[1]))}:${e[2]}`, allDay: false }
    }

    function save() {
        if (root.saving || root.readOnly) return
        const t = root.times()
        if (!t) {
            root.error = Translation.tr("Times are HH:MM")
            return
        }
        const op = { summary: titleField.text.trim(), start: t.start, end: t.end, allDay: t.allDay,
            location: locationField.text.trim(), description: notesField.text }
        if (!op.summary) {
            root.error = Translation.tr("Give it a title")
            return
        }
        if (root.reminders !== null) op.reminders = root.reminders
        if (root.creating) {
            op.op = "create"
            op.calendar = root.calendarId
            if (root.repeat !== "none") op.recurrence = root.repeat
        } else {
            op.op = "update"
            op.id = root.event.id
            const occurrence = root.event.recurring && root.scope === "this" && root.event.occurrence
            if (occurrence) {
                op.occurrence = root.event.occurrence
            } else if (root.event.recurring) {
                // The whole series, from this occurrence: its times move as
                // this one's do.
                op.all = true
                op.occurrence = root.event.occurrence
                if (root.repeat !== "keep") op.recurrence = root.repeat
            } else if (root.repeat !== "none") {
                op.recurrence = root.repeat
            }
            if (root.calendarId !== root.event.calendarId) op.calendar = root.calendarId
        }
        root.saving = true
        CalendarEvents.apply(op, results => {
            root.saving = false
            if (results[0].ok) root.closed()
            else root.error = results[0].error
        })
    }

    function remove() {
        if (root.readOnly) return
        const op = { op: "delete", id: root.event.id }
        if (root.event.recurring && root.scope === "this" && root.event.occurrence) op.occurrence = root.event.occurrence
        root.saving = true
        CalendarEvents.apply(op, results => {
            root.saving = false
            if (results[0].ok) root.closed()
            else root.error = results[0].error
        })
    }

    Keys.onPressed: e => {
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_S) {
            root.save()
            e.accepted = true
        } else if (e.key === Qt.Key_Escape) {
            root.closed()
            e.accepted = true
        }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top }
        contentHeight: form.implicitHeight + 30
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: form
            x: 14
            y: 10
            width: parent.width - 28
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: root.creating ? Translation.tr("New event") : root.readOnly ? Translation.tr("Event (read-only)") : Translation.tr("Edit event")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                PanelButton {
                    visible: !root.creating && (root.event?.meetingUrl ?? "") !== ""
                    compact: true
                    filled: true
                    icon: "videocam"
                    text: Translation.tr("Join")
                    onClicked: Qt.openUrlExternally(root.event.meetingUrl)
                }
            }

            // This occurrence, or the series
            Flow {
                Layout.fillWidth: true
                visible: !root.creating && !!root.event?.recurring && !root.readOnly
                spacing: 6
                Repeater {
                    model: [{ key: "this", name: Translation.tr("This event") }, { key: "all", name: Translation.tr("All events") }]
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        toggled: root.scope === modelData.key
                        icon: toggled ? "check" : ""
                        text: modelData.name
                        onClicked: root.scope = modelData.key
                    }
                }
            }

            MaterialTextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Title")
                enabled: !root.readOnly
                onAccepted: root.save()
            }

            PanelButton {
                compact: true
                enabled: !root.readOnly
                toggled: root.allDay
                icon: root.allDay ? "check" : ""
                text: Translation.tr("All day")
                onClicked: root.allDay = !root.allDay
            }

            // Start, end
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 8
                rowSpacing: 8
                StyledText {
                    text: Translation.tr("Starts")
                    color: Appearance.colors.colSubtext
                }
                PanelButton {
                    compact: true
                    enabled: !root.readOnly
                    icon: "event"
                    text: Qt.locale().toString(root.startDay, "ddd d MMM yyyy")
                    onClicked: startPicker.open()
                    DuePicker {
                        id: startPicker
                        date: root.startDay
                        onPicked: date => {
                            const span = root.endDay - root.startDay
                            root.startDay = date
                            root.endDay = new Date(date.getTime() + Math.max(0, span))
                            startPicker.close()
                        }
                    }
                }
                MaterialTextField {
                    id: startTime
                    visible: !root.allDay
                    enabled: !root.readOnly
                    Layout.preferredWidth: 90
                    placeholderText: "09:00"
                    inputMask: ""
                }
                Item { visible: root.allDay }
                StyledText {
                    text: Translation.tr("Ends")
                    color: Appearance.colors.colSubtext
                }
                PanelButton {
                    compact: true
                    enabled: !root.readOnly
                    icon: "event"
                    text: Qt.locale().toString(root.endDay, "ddd d MMM yyyy")
                    onClicked: endPicker.open()
                    DuePicker {
                        id: endPicker
                        date: root.endDay
                        onPicked: date => {
                            root.endDay = date < root.startDay ? root.startDay : date
                            endPicker.close()
                        }
                    }
                }
                MaterialTextField {
                    id: endTime
                    visible: !root.allDay
                    enabled: !root.readOnly
                    Layout.preferredWidth: 90
                    placeholderText: "10:00"
                }
                Item { visible: root.allDay }
            }

            // Calendar
            StyledText {
                visible: root.calendars.length > 1 || root.readOnly
                text: Translation.tr("Calendar")
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                visible: root.calendars.length > 1 && !root.readOnly
                spacing: 6
                Repeater {
                    model: root.calendars
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        toggled: root.calendarId === modelData.id
                        icon: "circle"
                        iconColor: modelData.color || Appearance.colors.colPrimary
                        text: Accounts.several ? `${modelData.name} · ${Accounts.shortName(modelData.account)}` : modelData.name
                        onClicked: root.calendarId = modelData.id
                    }
                }
            }
            StyledText {
                visible: root.readOnly
                text: root.event?.calendarName ?? ""
                color: Appearance.colors.colOnLayer1
            }

            // Repeat (a new event, or the whole series)
            StyledText {
                visible: !root.readOnly && (root.creating || !root.event?.recurring || root.scope === "all")
                text: Translation.tr("Repeat")
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                visible: !root.readOnly && (root.creating || !root.event?.recurring || root.scope === "all")
                spacing: 6
                PanelButton {
                    visible: root.repeat === "keep"
                    compact: true
                    toggled: true
                    icon: "check"
                    text: Translation.tr("As it is")
                }
                Repeater {
                    model: root.repeats
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        toggled: root.repeat === modelData.key
                        text: modelData.name
                        onClicked: root.repeat = modelData.key
                    }
                }
            }

            // Reminders
            StyledText {
                visible: !root.readOnly
                text: Translation.tr("Reminders")
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                visible: !root.readOnly
                spacing: 6
                PanelButton {
                    compact: true
                    toggled: root.reminders === null
                    icon: toggled ? "check" : ""
                    text: root.creating ? Translation.tr("The calendar's")
                        : Translation.tr("As it is (%1)").arg((root.event?.reminders ?? []).map(m => root.reminderText(m)).join(", ") || Translation.tr("none"))
                    onClicked: root.reminders = null
                }
                PanelButton {
                    compact: true
                    toggled: root.reminders !== null && root.reminders.length === 0
                    text: Translation.tr("None")
                    onClicked: root.reminders = []
                }
                Repeater {
                    model: root.reminderChoices
                    delegate: PanelButton {
                        required property int modelData
                        compact: true
                        toggled: root.reminders !== null && root.reminders.includes(modelData)
                        icon: toggled ? "notifications" : ""
                        text: root.reminderText(modelData)
                        onClicked: {
                            const current = root.reminders ?? []
                            root.reminders = toggled ? current.filter(m => m !== modelData) : current.concat([modelData]).sort((a, b) => a - b)
                        }
                    }
                }
            }

            MaterialTextField {
                id: locationField
                Layout.fillWidth: true
                enabled: !root.readOnly
                placeholderText: Translation.tr("Place or meeting link")
            }
            MaterialTextArea {
                id: notesField
                Layout.fillWidth: true
                Layout.minimumHeight: 100
                enabled: !root.readOnly
                placeholderText: Translation.tr("Notes")
                wrapMode: TextEdit.Wrap
            }

            // Delete?
            Rectangle {
                Layout.fillWidth: true
                visible: root.confirmDelete
                implicitHeight: confirmColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer
                ColumnLayout {
                    id: confirmColumn
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnErrorContainer
                        text: root.event?.recurring && root.scope === "this"
                            ? Translation.tr("Delete this occurrence of \"%1\"?").arg(root.event?.summary ?? "")
                            : root.event?.recurring ? Translation.tr("Delete every occurrence of \"%1\"?").arg(root.event?.summary ?? "")
                            : Translation.tr("Delete \"%1\"?").arg(root.event?.summary ?? "")
                    }
                    RowLayout {
                        spacing: 8
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
                            onClicked: root.remove()
                        }
                    }
                }
            }
        }
    }

    // Save / Delete / Close
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        implicitHeight: footerColumn.implicitHeight + 20
        color: Appearance.colors.colLayer1Base
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Appearance.colors.colOutlineVariant
        }
        ColumnLayout {
            id: footerColumn
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                visible: root.error !== ""
                text: root.error
                wrapMode: Text.Wrap
                color: Appearance.colors.colError
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PanelButton {
                    visible: !root.creating && !root.readOnly
                    icon: "delete"
                    text: Translation.tr("Delete")
                    onClicked: root.confirmDelete = true
                }
                Item { Layout.fillWidth: true }
                PanelButton {
                    text: root.readOnly ? Translation.tr("Close") : Translation.tr("Cancel")
                    onClicked: root.closed()
                }
                PanelButton {
                    visible: !root.readOnly
                    filled: true
                    icon: root.saving ? "hourglass_top" : "check"
                    text: root.saving ? Translation.tr("Saving…") : Translation.tr("Save")
                    onClicked: root.save()
                }
            }
        }
    }
}
