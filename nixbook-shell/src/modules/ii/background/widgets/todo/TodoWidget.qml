import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import qs.modules.ii.tasks

// The to-do list on the desktop: open tasks first, soonest deadline first
// (overdue in red, due today highlighted), then the recently finished ones.
// Resizable from its corner (per monitor: width/height); text grows with it.
// A click on a task, or on the title, opens the tasks panel; "+" adds a task
// to any list, with a deadline.
AbstractBackgroundWidget {
    id: root
    configEntryName: "todo"
    hoverEnabled: true

    readonly property real minWidth: 260
    readonly property real minHeight: 220
    // While the corner is dragged; then saved for this monitor.
    property real widthOverride: -1
    property real heightOverride: -1
    readonly property real cardWidth: root.widthOverride > 0 ? root.widthOverride : root.screenValue("width", 340)
    readonly property real cardHeight: root.heightOverride > 0 ? root.heightOverride : root.screenValue("height", 380)
    // Bigger widget, bigger text.
    readonly property real textScale: Math.min(1.4, Math.max(1, Math.min(root.cardWidth / 340, root.cardHeight / 380)))

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight

    property string mode: "list" // "list" | "edit"
    onModeChanged: GlobalStates.desktopWidgetKeyboardFocus = (mode === "edit")

    readonly property var openTasks: {
        const dueKey = t => t.due ? t.due.getTime() : Number.MAX_SAFE_INTEGER
        return Todo.list.filter(t => !t.done).sort((a, b) => dueKey(a) - dueKey(b))
    }
    readonly property var rows: root.openTasks.concat(Todo.list.filter(t => t.done))
    readonly property bool manyLists: Todo.lists.length > 1

    function toggleFlip() { flipAnim.start() }

    function openNewTask() {
        root.toggleFlip()
    }

    function saveAndBack() {
        const title = editTitle.text.trim()
        if (title.length > 0)
            Todo.addTask(title, { listId: editPage.listId, due: editPage.due })
        root.toggleFlip()
    }

    Item {
        id: cardWrapper
        anchors.fill: parent

        transform: Scale {
            id: flipScale
            origin.x: cardWrapper.width  / 2
            origin.y: cardWrapper.height / 2
            xScale: 1
        }

        SequentialAnimation {
            id: flipAnim
            NumberAnimation {
                target: flipScale; property: "xScale"
                to: 0; duration: 150; easing.type: Easing.InQuad
            }
            ScriptAction {
                script: {
                    root.mode = (root.mode === "list" ? "edit" : "list")
                    if (root.mode === "edit") editPage.start()
                }
            }
            NumberAnimation {
                target: flipScale; property: "xScale"
                to: 1; duration: 150; easing.type: Easing.OutQuad
            }
        }

        WidgetShadow {
            target: contentRect
            visible: Config.options.background.widgets.shadow
        }
        WidgetOutline {
            target: contentRect
        }

        Rectangle {
            id: contentRect
            anchors.fill: parent
            color: Appearance.colors.colWidgetCard
            radius: Appearance.rounding?.verylarge ?? 30

            FastBlurred {
                anchors.fill: parent
                blurSource: root.wallpaperItem
                cardRadius: contentRect.radius
                tint: Appearance.colors.colLayer1
                tintOpacity: 0.55
                trackX: root.x
                trackY: root.y
                visible: Config.options.background.widgets.blurWidgets
            }

            // List
            ColumnLayout {
                id: listPage
                anchors { fill: parent; margins: 14 }
                spacing: 10
                visible: root.mode === "list"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    // Title and summary: opens the tasks panel.
                    Item {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        implicitHeight: titleColumn.implicitHeight
                        ColumnLayout {
                            id: titleColumn
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.huge * root.textScale
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimaryContainer
                                text: "To-Do"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller * root.textScale
                                color: Todo.overdueCount > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
                                text: {
                                    const parts = [Translation.tr("%1 open").arg(root.openTasks.length)]
                                    if (Todo.overdueCount > 0) parts.push(Translation.tr("%1 overdue").arg(Todo.overdueCount))
                                    if (Todo.dueTodayCount > 0) parts.push(Translation.tr("%1 today").arg(Todo.dueTodayCount))
                                    return parts.join(" · ")
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.openTasksPanel("")
                        }
                    }

                    // Tasks synced through DankCalendar (Google Tasks…).
                    CalendarAccountButton {
                        Layout.alignment: Qt.AlignVCenter
                        size: 34
                        colIcon: Appearance.colors.colOnPrimaryContainer
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
                        color: expandMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "open_in_full"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            id: expandMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.openTasksPanel("")
                        }
                        PopupToolTip {
                            text: Translation.tr("Open tasks")
                            extraVisibleCondition: expandMouse.containsMouse
                        }
                    }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "add"
                        onClicked: root.openNewTask()
                    }
                }

                StyledListView {
                    id: todoListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: root.rows

                    delegate: SwipeDelegate {
                        id: taskCard
                        required property var modelData
                        required property int index

                        readonly property string group: Todo.deadlineGroup(modelData)
                        readonly property bool overdue: !modelData.done && group === "overdue"
                        readonly property bool dueToday: !modelData.done && group === "today"

                        width: todoListView.width
                        implicitHeight: cardRow.implicitHeight + 18
                        padding: 0
                        background: null
                        clip: true

                        property color bg: taskCard.overdue ? Appearance.colors.colErrorContainer
                            : taskCard.dueToday ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colSecondaryContainer
                        property color fg: taskCard.overdue ? Appearance.colors.colOnErrorContainer
                            : taskCard.dueToday ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnSecondaryContainer

                        // A click (not a swipe) opens the task in the panel.
                        onClicked: if (swipe.position === 0) GlobalStates.openTasksPanel(modelData.id ?? "")

                        contentItem: Rectangle {
                            radius: Appearance.rounding.normal
                            color: taskCard.bg
                            width: parent.width - Math.abs(taskCard.swipe.position) * 6
                            opacity: taskCard.modelData.done ? 0.55 : 1

                            RowLayout {
                                id: cardRow
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 4; rightMargin: 12
                                }
                                spacing: 8

                                Rectangle {
                                    Layout.leftMargin: 8
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 24 * root.textScale
                                    Layout.preferredHeight: 24 * root.textScale
                                    radius: Appearance.rounding.full
                                    color: taskCard.modelData.done
                                        ? ColorUtils.transparentize(taskCard.fg, 0.8)
                                        : "transparent"
                                    border.width: 2
                                    border.color: taskCard.fg

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: taskCard.modelData.done || checkMouse.containsMouse
                                        text: "check"
                                        iconSize: Appearance.font.pixelSize.normal * root.textScale
                                        color: taskCard.fg
                                    }

                                    MouseArea {
                                        id: checkMouse
                                        hoverEnabled: true
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Todo.setTaskDone(taskCard.modelData, !taskCard.modelData.done)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        color: taskCard.fg
                                        text: taskCard.modelData.content
                                        font.pixelSize: Appearance.font.pixelSize.normal * root.textScale
                                        wrapMode: Text.Wrap
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        font.strikeout: taskCard.modelData.done
                                    }
                                    // Deadline, and the list when there are several.
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller * root.textScale
                                        font.weight: taskCard.overdue || taskCard.dueToday ? Font.Medium : Font.Normal
                                        color: ColorUtils.transparentize(taskCard.fg, taskCard.overdue || taskCard.dueToday ? 0 : 0.25)
                                        text: {
                                            const parts = []
                                            const t = taskCard.modelData
                                            if (t.due && !t.done) {
                                                const rel = Todo.deadlineText(t)
                                                parts.push(["today", "tomorrow"].includes(taskCard.group) ? rel : `${Todo.dueText(t.due)} · ${rel}`)
                                            }
                                            if (root.manyLists) parts.push(Todo.listName(t.listId))
                                            return parts.join(" · ")
                                        }
                                    }
                                }
                            }
                        }

                        swipe.right: Rectangle {
                            width: 64
                            anchors.right: parent.right
                            height: parent.height
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colError

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnError
                            }

                            SwipeDelegate.onClicked: Todo.deleteTask(taskCard.modelData)
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 8
                    visible: root.rows.length === 0
                    text: Translation.tr("Nothing to do. Press + to add a task")
                    font.pixelSize: Appearance.font.pixelSize.small * root.textScale
                    color: Appearance.colors.colSubtext
                }
            }

            // Edit: a new task, its list and deadline.
            ColumnLayout {
                id: editPage
                anchors { fill: parent; margins: 14 }
                spacing: 10
                visible: root.mode === "edit"

                property string listId: Todo.defaultListId
                property var due: null

                function start() {
                    editTitle.text = ""
                    editPage.due = null
                    if (!Todo.lists.some(l => l.id === editPage.listId)) editPage.listId = Todo.defaultListId
                    editTitle.forceActiveFocus()
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Rectangle {
                        radius: Appearance.rounding.full
                        color: "transparent"
                        implicitWidth: 28; implicitHeight: 28
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "arrow_back"
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            hoverEnabled: true
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleFlip()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: Translation.tr("New task")
                        font.pixelSize: Appearance.font.pixelSize.large * root.textScale
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "save"
                        onClicked: root.saveAndBack()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: editTitle.implicitHeight + 12
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow

                    TextField {
                        id: editTitle
                        anchors.fill: parent
                        anchors.margins: 6
                        placeholderText: Translation.tr("Type your task…")
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.normal * root.textScale
                        background: null
                        onAccepted: root.saveAndBack()
                        Keys.onEscapePressed: root.toggleFlip()
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: editOptions.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    ColumnLayout {
                        id: editOptions
                        width: parent.width
                        spacing: 6

                        StyledText {
                            text: Translation.tr("Deadline")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        DueChips {
                            Layout.fillWidth: true
                            due: editPage.due
                            onDueEdited: due => editPage.due = due
                        }
                        StyledText {
                            visible: root.manyLists
                            Layout.topMargin: 4
                            text: Translation.tr("List")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        Flow {
                            visible: root.manyLists
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: Todo.lists
                                delegate: PanelButton {
                                    required property var modelData
                                    compact: true
                                    text: modelData.name
                                    toggled: editPage.listId === modelData.id
                                    onClicked: editPage.listId = modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ResizeHandler {
        anchorItem: root
        hoverActive: root.containsMouse
        locked: Config.options.background.widgetsLocked
        currentWidth: root.cardWidth
        resizeMode: "diagonal"
        property real startHeight: 0
        onResizedXY: (dx, dy, startWidth) => {
            if (root.heightOverride < 0) startHeight = root.cardHeight
            root.widthOverride = Math.round(Math.min(Math.max(startWidth + dx, root.minWidth), 900))
            root.heightOverride = Math.round(Math.min(Math.max(startHeight + dy, root.minHeight), 1100))
        }
        onResizeFinished: {
            if (root.widthOverride > 0)
                root.setScreenValues({ width: root.widthOverride, height: root.heightOverride })
            root.widthOverride = -1
            root.heightOverride = -1
        }
    }
}
