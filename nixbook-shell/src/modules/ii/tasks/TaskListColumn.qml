pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// One task list as a card: "Add a task", the open tasks (subtasks under
// their parent, or grouped by deadline: Overdue, Today…), "Completed (n)"
// folded at the bottom. `deadlines`: every list's open tasks that have a
// deadline, grouped by it (no add, no completed).
Rectangle {
    id: root
    required property var list
    property var selected: null
    property bool showCompleted: false
    property bool deadlines: false
    property bool sortByDeadline: root.deadlines
    signal taskClicked(var task)

    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer0Base
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    readonly property var tasks: root.deadlines
        ? Todo.list.filter(t => !t.done && t.due)
        : Todo.list.filter(t => t.listId === root.list.id)
    readonly property var doneTasks: root.deadlines ? [] : root.tasks.filter(t => t.done)
    // [{ task, depth, section }]: each open task, then its open subtasks;
    // or by deadline, `section` naming the group its first task starts.
    readonly property var openRows: {
        const open = root.tasks.filter(t => !t.done)
        const rows = []
        if (root.sortByDeadline) {
            const dueKey = t => t.due ? t.due.getTime() : Number.MAX_SAFE_INTEGER
            for (const g of Todo.deadlineGroups) {
                const tasks = open.filter(t => Todo.deadlineGroup(t) === g.key).sort((a, b) => dueKey(a) - dueKey(b))
                tasks.forEach((t, i) => rows.push({ task: t, depth: 0, section: i === 0 ? g.name : "", sectionKey: g.key }))
            }
            return rows
        }
        const uids = open.map(t => t.uid).filter(u => u)
        for (const t of open) {
            if (t.parentUid && uids.includes(t.parentUid)) continue
            rows.push({ task: t, depth: 0, section: "" })
            if (!t.uid) continue
            for (const c of open)
                if (c.parentUid === t.uid) rows.push({ task: c, depth: 1, section: "" })
        }
        return rows
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            Layout.bottomMargin: 4
            spacing: 8
            MaterialSymbol {
                visible: root.deadlines
                text: "alarm"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }
            Rectangle {
                visible: !root.deadlines && (root.list.color ?? "") !== ""
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: root.list.color ?? "transparent"
            }
            StyledText {
                Layout.fillWidth: true
                text: root.list.name
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: root.openRows.length > 0 ? Translation.tr("%1 open").arg(root.openRows.length) : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            // My order / by deadline
            Rectangle {
                visible: !root.deadlines
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: root.sortByDeadline ? Appearance.colors.colSecondaryContainer
                    : sortMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.sortByDeadline ? "alarm" : "sort"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.sortByDeadline ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                }
                MouseArea {
                    id: sortMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortByDeadline = !root.sortByDeadline
                }
                PopupToolTip {
                    text: root.sortByDeadline ? Translation.tr("Sorted by deadline (click: my order)") : Translation.tr("Sort by deadline")
                    extraVisibleCondition: sortMouse.containsMouse
                }
            }
        }

        // Add a task
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            visible: !editor.visible && !root.deadlines
            radius: Appearance.rounding.full
            color: addMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                spacing: 14
                MaterialSymbol {
                    text: "add_task"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add a task")
                    color: Appearance.colors.colPrimary
                }
            }
            MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    editor.visible = true
                    editor.start()
                }
            }
        }

        TaskEditor {
            id: editor
            Layout.fillWidth: true
            Layout.margins: 8
            visible: false
            listId: root.list.id
            keepOpen: true
            onDone: editor.visible = false
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: body
                width: flick.width
                spacing: 0

                Repeater {
                    model: root.openRows
                    delegate: ColumnLayout {
                        id: rowItem
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            visible: rowItem.modelData.section !== ""
                            Layout.leftMargin: 12
                            Layout.topMargin: 10
                            Layout.bottomMargin: 2
                            text: rowItem.modelData.section
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: rowItem.modelData.sectionKey === "overdue" ? Appearance.colors.colError : Appearance.colors.colPrimary
                        }
                        TaskRow {
                            Layout.fillWidth: true
                            task: rowItem.modelData.task
                            depth: rowItem.modelData.depth
                            showList: root.deadlines
                            selected: root.selected === rowItem.modelData.task
                            onClicked: root.taskClicked(rowItem.modelData.task)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 32
                    visible: root.openRows.length === 0 && !editor.visible
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "done_all"
                        iconSize: 44
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.deadlines ? Translation.tr("No deadlines coming up")
                            : root.doneTasks.length > 0 ? Translation.tr("All tasks complete") : Translation.tr("No tasks yet")
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.deadlines ? Translation.tr("Give a task a date and it shows up here")
                            : root.doneTasks.length > 0 ? Translation.tr("Nice work!") : Translation.tr("Add your to-dos and keep track of them")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                // Completed (n)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    implicitHeight: 42
                    visible: root.doneTasks.length > 0
                    radius: Appearance.rounding.full
                    color: completedMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10
                        MaterialSymbol {
                            text: root.showCompleted ? "expand_more" : "chevron_right"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Completed (%1)").arg(root.doneTasks.length)
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    MouseArea {
                        id: completedMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showCompleted = !root.showCompleted
                    }
                }

                Repeater {
                    model: root.showCompleted ? root.doneTasks : []
                    delegate: TaskRow {
                        required property var modelData
                        Layout.fillWidth: true
                        task: modelData
                        selected: root.selected === modelData
                        onClicked: root.taskClicked(modelData)
                    }
                }
            }
        }
    }
}
