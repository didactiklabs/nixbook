import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

// Today / Tomorrow / Next week / a date from the month, and clearing it:
// the due date of a task being added or edited.
Flow {
    id: root
    property var due: null
    signal dueEdited(var due)
    spacing: 6

    function _inDays(n) {
        const now = new Date()
        return new Date(now.getFullYear(), now.getMonth(), now.getDate() + n)
    }
    function _same(a, b) {
        return !!a && !!b && a.getTime() === b.getTime()
    }
    // Next Monday (a week from today when today is one).
    readonly property int _toMonday: ((8 - new Date().getDay()) % 7) || 7

    PanelButton {
        compact: true
        icon: "today"
        text: Translation.tr("Today")
        toggled: root._same(root.due, root._inDays(0))
        onClicked: root.dueEdited(root._inDays(0))
    }
    PanelButton {
        compact: true
        icon: "event_upcoming"
        text: Translation.tr("Tomorrow")
        toggled: root._same(root.due, root._inDays(1))
        onClicked: root.dueEdited(root._inDays(1))
    }
    PanelButton {
        compact: true
        icon: "date_range"
        text: Translation.tr("Next week")
        toggled: root._same(root.due, root._inDays(root._toMonday))
        onClicked: root.dueEdited(root._inDays(root._toMonday))
    }
    PanelButton {
        id: pickButton
        readonly property bool other: !!root.due && ![0, 1, root._toMonday].some(n => root._same(root.due, root._inDays(n)))
        compact: true
        icon: "calendar_month"
        text: pickButton.other ? Todo.dueText(root.due) : Translation.tr("Pick date")
        toggled: pickButton.other
        onClicked: picker.open()

        DuePicker {
            id: picker
            y: pickButton.height + 4
            date: root.due
            onPicked: date => root.dueEdited(date)
        }
    }
    PanelButton {
        visible: !!root.due
        compact: true
        icon: "event_busy"
        text: Translation.tr("No date")
        onClicked: root.dueEdited(null)
    }
}
