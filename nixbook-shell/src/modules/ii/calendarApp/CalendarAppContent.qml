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

// The Calendar window's content: the month (each day's events, the
// selected day marked) and, beside it, the selected day's events, the
// event editor or the calendars (each turned on or off). Ctrl+N new event,
// T today, Page Up/Down months, F5 sync, Escape closes the editor or the
// calendars. Narrow: the month, then the day or the editor
// full width with a back arrow. Before an account is added: the accounts
// (AccountsContent).
Rectangle {
    id: root
    color: Appearance.colors.colLayer0Base
    clip: true

    property var month: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property var selectedDay: root._today()
    // The event in the editor (an item of CalendarEvents), or null; a new
    // one starts at `newStart`.
    property var editing: null
    property bool creating: false
    property var newStart: null
    // The calendars, each with its switch, in place of the day.
    property bool showingCalendars: false
    readonly property bool narrow: root.width < 900
    // Narrow: the side (day or editor) instead of the month.
    property bool sidePage: false
    readonly property bool ready: Accounts.connected
    // Ticks so "today" and the agenda's "now" follow the clock.
    property var now: new Date()
    Timer {
        interval: 60000
        running: root.visible
        repeat: true
        onTriggered: root.now = new Date()
    }

    function _today() {
        const d = new Date()
        return new Date(d.getFullYear(), d.getMonth(), d.getDate())
    }

    function opened(date, mode) {
        const d = date ?? root._today()
        root.selectDay(new Date(d.getFullYear(), d.getMonth(), d.getDate()))
        if (mode === "new") root.newEvent(date)
        root.forceActiveFocus()
    }

    function selectDay(day) {
        root.selectedDay = day
        root.month = new Date(day.getFullYear(), day.getMonth(), 1)
        CalendarEvents.ensureMonth(root.month)
        root.editing = null
        root.creating = false
        root.showingCalendars = false
        root.sidePage = true
    }

    function showMonth(delta) {
        root.month = new Date(root.month.getFullYear(), root.month.getMonth() + delta, 1)
        CalendarEvents.ensureMonth(root.month)
    }

    function openEvent(event) {
        root.editing = event
        root.creating = false
        root.showingCalendars = false
        root.sidePage = true
    }

    // A new event at `date`: its time when it has one, else 9:00 on that
    // day (the next half hour today).
    function newEvent(date) {
        let start = date ? new Date(date) : new Date(root.selectedDay)
        if (!date || (start.getHours() === 0 && start.getMinutes() === 0)) {
            const now = new Date()
            if (CalendarEvents.dayKey(start) === CalendarEvents.dayKey(now)) {
                start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours(), now.getMinutes() < 30 ? 30 : 60)
            } else {
                start.setHours(9, 0, 0, 0)
            }
        }
        root.newStart = start
        root.editing = null
        root.creating = true
        root.showingCalendars = false
        root.sidePage = true
    }

    // The 42 days the month grid shows (weeks start on the locale's day).
    readonly property var days: {
        const first = root.month
        const shift = (first.getDay() - Qt.locale().firstDayOfWeek % 7 + 7) % 7
        const out = []
        for (let i = 0; i < 42; i++)
            out.push(new Date(first.getFullYear(), first.getMonth(), 1 - shift + i))
        return out
    }

    function timeText(e) {
        const fmt = Config.options?.time.format ?? "hh:mm"
        if (e.allDay) return Translation.tr("All day")
        return `${Qt.locale().toString(e.start, fmt)} – ${Qt.locale().toString(e.end, fmt)}`
    }

    Keys.onPressed: event => {
        if (!root.ready) return
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N) {
            root.newEvent(null)
        } else if (event.key === Qt.Key_F5) {
            CalendarEvents.sync()
        } else if (event.key === Qt.Key_PageUp) {
            root.showMonth(-1)
        } else if (event.key === Qt.Key_PageDown) {
            root.showMonth(1)
        } else if (event.key === Qt.Key_T && !(event.modifiers & Qt.ControlModifier)) {
            root.selectDay(root._today())
        } else if (event.key === Qt.Key_Escape && (root.editing || root.creating || root.showingCalendars)) {
            root.editing = null
            root.creating = false
            root.showingCalendars = false
        } else {
            return
        }
        event.accepted = true
    }

    AccountsContent {
        anchors.fill: parent
        visible: Accounts.statusKnown && !root.ready
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        visible: root.ready

        // The month
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            visible: !root.narrow || !root.sidePage
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    Layout.leftMargin: 6
                    text: "calendar_month"
                    iconSize: 28
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Qt.locale().toString(root.month, "MMMM yyyy")
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                PanelButton {
                    compact: true
                    text: Translation.tr("Today")
                    onClicked: root.selectDay(root._today())
                }
                CalButton {
                    icon: "chevron_left"
                    tip: Translation.tr("Previous month (Page Up)")
                    onClicked: root.showMonth(-1)
                }
                CalButton {
                    icon: "chevron_right"
                    tip: Translation.tr("Next month (Page Down)")
                    onClicked: root.showMonth(1)
                }
                CalButton {
                    icon: CalendarEvents.syncing ? "hourglass_top" : "sync"
                    tip: Translation.tr("Sync now (F5)")
                    onClicked: CalendarEvents.sync()
                }
                CalButton {
                    icon: "visibility"
                    tip: Translation.tr("Calendars shown")
                    onClicked: {
                        root.editing = null
                        root.creating = false
                        root.showingCalendars = !root.showingCalendars
                        root.sidePage = root.showingCalendars || !root.narrow
                    }
                }
                CalButton {
                    icon: "manage_accounts"
                    tip: Translation.tr("Accounts")
                    onClicked: Accounts.openWindow()
                }
                PanelButton {
                    filled: true
                    icon: "add"
                    text: Translation.tr("New")
                    onClicked: root.newEvent(null)
                }
            }

            // Week days
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: root.days.slice(0, 7)
                    delegate: StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().toString(modelData, "ddd")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            GridLayout {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 4
                columnSpacing: 4

                Repeater {
                    model: root.days
                    delegate: Rectangle {
                        id: cell
                        required property var modelData
                        readonly property bool inMonth: modelData.getMonth() === root.month.getMonth()
                        readonly property bool isToday: CalendarEvents.dayKey(modelData) === CalendarEvents.dayKey(root.now)
                        readonly property bool selected: CalendarEvents.dayKey(modelData) === CalendarEvents.dayKey(root.selectedDay)
                        readonly property var events: CalendarEvents.eventsOn(modelData)
                        // As many events as fit, then "+N more".
                        readonly property int fits: Math.max(0, Math.floor((height - 30) / 20))
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 1
                        radius: Appearance.rounding.small
                        color: cell.selected ? Appearance.colors.colSecondaryContainer
                            : cellMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1Base
                        opacity: cell.inMonth ? 1 : 0.55
                        clip: true

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectDay(cell.modelData)
                            onDoubleClicked: root.newEvent(cell.modelData)
                        }

                        ColumnLayout {
                            anchors { fill: parent; margins: 4 }
                            spacing: 2
                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: 24
                                radius: 12
                                color: cell.isToday ? Appearance.colors.colPrimary : "transparent"
                                StyledText {
                                    anchors.centerIn: parent
                                    text: cell.modelData.getDate()
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: cell.isToday ? Font.Bold : Font.Normal
                                    color: cell.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                }
                            }
                            Repeater {
                                model: cell.events.length > cell.fits ? cell.events.slice(0, Math.max(0, cell.fits - 1)) : cell.events
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 18
                                    radius: 4
                                    color: chip.modelData.allDay ? (chip.modelData.color || Appearance.colors.colPrimary)
                                        : chipMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                                        spacing: 4
                                        Rectangle {
                                            visible: !chip.modelData.allDay
                                            implicitWidth: 6
                                            implicitHeight: 6
                                            radius: 3
                                            color: chip.modelData.color || Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: (chip.modelData.allDay ? "" : Qt.locale().toString(chip.modelData.start, Config.options?.time.format ?? "hh:mm") + " ")
                                                + chip.modelData.summary
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: chip.modelData.allDay ? "white" : Appearance.colors.colOnLayer1
                                        }
                                    }
                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectDay(cell.modelData)
                                            root.openEvent(chip.modelData)
                                        }
                                    }
                                }
                            }
                            StyledText {
                                visible: cell.events.length > cell.fits && cell.fits > 0
                                Layout.leftMargin: 4
                                text: Translation.tr("+%1 more").arg(cell.events.length - Math.max(0, cell.fits - 1))
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            Item { Layout.fillHeight: true }
                        }
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

        // The day, or the editor
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: root.narrow
            Layout.preferredWidth: root.narrow ? -1 : 400
            visible: !root.narrow || root.sidePage
            color: Appearance.colors.colLayer1Base

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // A failed change, or the last sync's failure.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    visible: messageText.text !== ""
                    implicitHeight: messageRow.implicitHeight + 16
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colErrorContainer
                    RowLayout {
                        id: messageRow
                        anchors { fill: parent; margins: 8; leftMargin: 12 }
                        StyledText {
                            id: messageText
                            Layout.fillWidth: true
                            text: CalendarEvents.lastError?.message ?? CalendarEvents.error
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnErrorContainer
                        }
                        CalButton {
                            icon: "close"
                            tip: Translation.tr("Dismiss")
                            onClicked: {
                                CalendarEvents.lastError = null
                                CalendarEvents.error = ""
                            }
                        }
                    }
                }

                EventEditor {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.editing !== null || root.creating
                    event: root.editing
                    creating: root.creating
                    newStart: root.newStart
                    narrow: root.narrow
                    onClosed: {
                        root.editing = null
                        root.creating = false
                        root.forceActiveFocus()
                    }
                }

                // The calendars, each turned on or off
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 14
                    visible: root.showingCalendars && root.editing === null && !root.creating
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        CalButton {
                            visible: root.narrow
                            icon: "arrow_back"
                            tip: Translation.tr("The month")
                            onClicked: {
                                root.showingCalendars = false
                                root.sidePage = false
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            text: Translation.tr("Calendars")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        CalButton {
                            visible: !root.narrow
                            icon: "close"
                            tip: Translation.tr("Back to the day (Escape)")
                            onClicked: root.showingCalendars = false
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        text: Translation.tr("Turned off, a calendar's events aren't shown or reminded.")
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledListView {
                        id: calendarList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        // Each account's name, then its calendars.
                        model: {
                            const rows = []
                            for (const c of CalendarEvents.calendars) {
                                if (rows.length === 0 || rows[rows.length - 1].account !== c.account)
                                    rows.push({ header: Accounts.nameOf(c.account) || c.account, account: c.account })
                                rows.push(c)
                            }
                            return rows
                        }
                        delegate: Rectangle {
                            id: calRow
                            required property var modelData
                            readonly property bool header: calRow.modelData.header !== undefined
                            width: calendarList.width
                            implicitHeight: calRow.header ? 34 : 44
                            StyledText {
                                visible: calRow.header
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 6; bottomMargin: 4 }
                                text: calRow.modelData.header ?? ""
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                                elide: Text.ElideRight
                            }
                            radius: Appearance.rounding.normal
                            color: calMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                            MouseArea {
                                id: calMouse
                                anchors.fill: parent
                                visible: !calRow.header
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: CalendarEvents.setShown(calRow.modelData.id, calRow.modelData.hidden)
                            }
                            RowLayout {
                                visible: !calRow.header
                                anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                spacing: 10
                                Rectangle {
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    radius: 4
                                    color: calRow.modelData.color || Appearance.colors.colPrimary
                                    opacity: calRow.modelData.hidden ? 0.35 : 1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: calRow.modelData.name ?? ""
                                    elide: Text.ElideRight
                                    color: calRow.modelData.hidden ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                                }
                                MaterialSymbol {
                                    visible: calRow.modelData.readOnly ?? false
                                    text: "lock"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                                StyledSwitch {
                                    checked: !calRow.modelData.hidden
                                    onToggled: CalendarEvents.setShown(calRow.modelData.id, checked)
                                }
                            }
                        }
                    }
                }

                // The day's events
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 14
                    visible: root.editing === null && !root.creating && !root.showingCalendars
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        CalButton {
                            visible: root.narrow
                            icon: "arrow_back"
                            tip: Translation.tr("The month")
                            onClicked: root.sidePage = false
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            text: Qt.locale().toString(root.selectedDay, "dddd d MMMM")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        CalButton {
                            icon: "add"
                            tip: Translation.tr("New event this day")
                            onClicked: root.newEvent(root.selectedDay)
                        }
                    }

                    StyledListView {
                        id: dayList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: CalendarEvents.eventsOn(root.selectedDay)
                        delegate: Rectangle {
                            id: item
                            required property var modelData
                            readonly property bool past: item.modelData.end <= root.now
                            width: dayList.width
                            implicitHeight: itemColumn.implicitHeight + 20
                            radius: Appearance.rounding.normal
                            color: itemMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2Base
                            opacity: item.past ? 0.6 : 1
                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openEvent(item.modelData)
                            }
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 }
                                width: 4
                                radius: 2
                                color: item.modelData.color || Appearance.colors.colPrimary
                            }
                            ColumnLayout {
                                id: itemColumn
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 10 }
                                spacing: 2
                                StyledText {
                                    text: root.timeText(item.modelData) + (item.modelData.recurring ? "  ↻" : "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: item.modelData.summary
                                    wrapMode: Text.Wrap
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: [item.modelData.location, item.modelData.calendarName].filter(s => !!s).join(" · ")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                PanelButton {
                                    visible: item.modelData.meetingUrl !== "" && !item.past
                                    Layout.topMargin: 4
                                    compact: true
                                    filled: true
                                    icon: "videocam"
                                    text: Translation.tr("Join")
                                    onClicked: Qt.openUrlExternally(item.modelData.meetingUrl)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 40
                        visible: dayList.count === 0
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "event_available"
                            iconSize: 48
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: CalendarEvents.loading ? Translation.tr("Loading…") : Translation.tr("Nothing this day")
                            color: Appearance.colors.colSubtext
                        }
                        PanelButton {
                            Layout.alignment: Qt.AlignHCenter
                            icon: "add"
                            text: Translation.tr("New event")
                            onClicked: root.newEvent(root.selectedDay)
                        }
                    }
                }
            }
        }
    }

    // A round icon button of the Calendar window, with its tooltip.
    component CalButton: Rectangle {
        id: button
        property string icon
        property string tip
        signal clicked()
        implicitWidth: 38
        implicitHeight: 38
        radius: 19
        color: buttonMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
        MaterialSymbol {
            anchors.centerIn: parent
            text: button.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
        PopupToolTip {
            text: button.tip
            extraVisibleCondition: buttonMouse.containsMouse
        }
    }
}
