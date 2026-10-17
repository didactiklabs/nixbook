pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The Tasks window's content: the side bar (Create, Deadlines, the lists to
// show), a column per shown list, the selected task's details on the right,
// the Create dialog. Ctrl+N creates a task; Escape closes the dialog, then
// the details, then the side bar drawer.
//
// Tiled, the window can be narrow: below `wideWidth` the side bar is a
// drawer (☰ in a top bar), below `detailsSideWidth` the details slide over
// the columns instead of taking room from them, and a column never gets
// wider than the window.
Rectangle {
    id: root
    color: Appearance.colors.colLayer0Base
    clip: true

    // The selected task (one of Todo.list's items), its details shown.
    property var selected: null
    // Lists hidden from the columns (ids), for this session.
    property var hiddenListIds: []
    readonly property var shownLists: Todo.lists.filter(l => !root.hiddenListIds.includes(l.id))
    property bool creating: false
    // The list dialog: { mode: "create" | "rename" | "delete", listId }.
    property var listDialog: null
    function askList(mode, listId) {
        root.sideOpen = false
        root.listDialog = { mode: mode, listId: listId ?? "" }
    }
    // A list operation that failed (Todo.lastError), shown a few seconds.
    property string errorText: ""
    Connections {
        target: Todo
        function onLastErrorChanged() {
            if (!Todo.lastError) return
            root.errorText = Todo.lastError.message
            errorTimer.restart()
        }
    }
    Timer {
        id: errorTimer
        interval: 7000
        onTriggered: root.errorText = ""
    }

    // The Deadlines column (every list's tasks with a date, by deadline).
    property bool showDeadlines: true

    readonly property real wideWidth: 900
    readonly property real detailsSideWidth: 1200
    readonly property bool compact: root.width < root.wideWidth
    readonly property bool detailsOver: root.width < root.detailsSideWidth
    // The drawer, while compact.
    property bool sideOpen: false
    onCompactChanged: root.sideOpen = false
    readonly property real columnWidth: Math.min(360, columnsFlick.width)

    function opened(taskId) {
        root.creating = false
        root.selected = taskId ? (Todo.list.find(t => t.id === taskId) ?? null) : null
        root.forceActiveFocus()
    }

    function toggleList(listId) {
        root.hiddenListIds = root.hiddenListIds.includes(listId)
            ? root.hiddenListIds.filter(id => id !== listId)
            : root.hiddenListIds.concat([listId])
    }

    // Todo.list is rebuilt on every change (a sync brings new objects):
    // follow the selected task by its id.
    Connections {
        target: Todo
        function onListChanged() {
            const s = root.selected
            if (!s || Todo.list.includes(s)) return
            root.selected = s.id ? (Todo.list.find(t => t.id === s.id) ?? null) : null
        }
    }

    Keys.onEscapePressed: {
        if (root.listDialog) root.listDialog = null
        else if (root.creating) root.creating = false
        else if (root.selected) root.selected = null
        else if (root.sideOpen) root.sideOpen = false
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
            root.creating = true
            event.accepted = true
        }
    }

    // The lists, side by side (with a top bar while compact)
    Rectangle {
        id: mainArea
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            leftMargin: root.compact ? 0 : sideBar.width
            rightMargin: root.selected && !root.detailsOver ? details.width : 0
        }
        color: Appearance.colors.colLayer1Base

        RowLayout {
            id: topBar
            visible: root.compact
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 8
            }
            height: root.compact ? 48 : 0
            spacing: 8
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: 22
                color: menuMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "menu"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                MouseArea {
                    id: menuMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sideOpen = !root.sideOpen
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Tasks")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: Todo.overdueCount > 0
                text: Translation.tr("%1 overdue").arg(Todo.overdueCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }
            PanelButton {
                icon: "add_task"
                text: Translation.tr("Create")
                filled: true
                onClicked: root.creating = true
            }
        }

        Flickable {
            id: columnsFlick
            anchors {
                top: topBar.bottom
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: root.compact ? 8 : 16
            }
            contentWidth: columnsRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: columnsRow
                height: columnsFlick.height
                spacing: root.compact ? 8 : 16

                TaskListColumn {
                    visible: root.showDeadlines
                    height: columnsRow.height
                    width: root.columnWidth
                    deadlines: true
                    list: ({ id: "", name: Translation.tr("Deadlines") })
                    selected: root.selected
                    onTaskClicked: task => root.selected = (root.selected === task ? null : task)
                }

                Repeater {
                    model: root.shownLists
                    delegate: TaskListColumn {
                        required property var modelData
                        height: columnsRow.height
                        width: root.shownLists.length === 1 && !root.showDeadlines ? Math.min(columnsFlick.width, 640) : root.columnWidth
                        list: modelData
                        selected: root.selected
                        onTaskClicked: task => root.selected = (root.selected === task ? null : task)
                        onListAction: action => root.askList(action, modelData.id)
                    }
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: columnsFlick
            visible: root.shownLists.length === 0 && !root.showDeadlines
            spacing: 8
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "checklist"
                iconSize: 56
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: root.compact ? Translation.tr("Pick a list in the ☰ menu to show it") : Translation.tr("Pick a list on the left to show it")
                color: Appearance.colors.colSubtext
            }
        }
    }

    // The drawer's scrim, while compact.
    Rectangle {
        anchors.fill: parent
        visible: root.compact && root.sideOpen
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea {
            anchors.fill: parent
            onClicked: root.sideOpen = false
        }
    }

    // Side bar: a column on the left, or a drawer while compact.
    Rectangle {
        id: sideBar
        width: Math.min(280, root.width - 48)
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        x: !root.compact || root.sideOpen ? 0 : -width
        visible: !root.compact || x > -width
        color: Appearance.colors.colLayer0Base
        Behavior on x {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        // Swallows clicks meant for nothing (not the scrim behind).
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6

            RowLayout {
                Layout.leftMargin: 8
                Layout.bottomMargin: 10
                spacing: 10
                MaterialSymbol {
                    text: "task_alt"
                    iconSize: 28
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Tasks")
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colOnLayer0
                }
            }

            PanelButton {
                Layout.bottomMargin: 14
                icon: "add_task"
                text: Translation.tr("Create")
                filled: true
                implicitHeight: 52
                onClicked: {
                    root.sideOpen = false
                    root.creating = true
                }
            }

            PanelButton {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                icon: "alarm"
                iconColor: Todo.overdueCount > 0 ? Appearance.colors.colError : Appearance.colors.colPrimary
                text: Translation.tr("Deadlines")
                toggled: root.showDeadlines
                trailingText: Todo.overdueCount > 0 ? Translation.tr("%1 overdue").arg(Todo.overdueCount)
                    : Todo.dueTodayCount > 0 ? Translation.tr("%1 today").arg(Todo.dueTodayCount) : ""
                onClicked: root.showDeadlines = !root.showDeadlines
            }

            StyledText {
                Layout.leftMargin: 12
                Layout.bottomMargin: 4
                text: Translation.tr("Lists")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: Todo.lists
                delegate: RowLayout {
                    id: listRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    PanelButton {
                        id: listButton
                        Layout.fillWidth: true
                        icon: root.hiddenListIds.includes(listRow.modelData.id) ? "check_box_outline_blank" : "check_box"
                        iconColor: listRow.modelData.color || Appearance.colors.colPrimary
                        text: listRow.modelData.name
                        trailingText: String(Todo.list.filter(t => t.listId === listRow.modelData.id && !t.done).length || "")
                        onClicked: root.toggleList(listRow.modelData.id)
                    }
                    ListMenuButton {
                        visible: !!listRow.modelData.manageable
                        onAction: action => root.askList(action, listRow.modelData.id)
                    }
                }
            }

            PanelButton {
                Layout.fillWidth: true
                visible: Todo.canCreateLists
                icon: "playlist_add"
                iconColor: Appearance.colors.colPrimary
                text: Translation.tr("New list")
                onClicked: root.askList("create", "")
            }

            Item { Layout.fillHeight: true }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                visible: !Accounts.syncing
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Kept on this computer. Add an account to sync your tasks and their lists (Google Tasks, iCloud, Nextcloud…).")
            }
            PanelButton {
                visible: !Accounts.syncing
                icon: "account_circle"
                text: Translation.tr("Add an account")
                onClicked: Accounts.openWindow()
            }
            PanelButton {
                visible: Accounts.syncing
                icon: "sync"
                text: Todo.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
                onClicked: Todo.sync()
            }
            PanelButton {
                visible: Accounts.syncing
                icon: "manage_accounts"
                text: Translation.tr("Accounts")
                onClicked: Accounts.openWindow()
            }
        }
    }

    // Details: on the right, over the columns when the window is narrow.
    StyledRectangularShadow {
        target: details
        visible: details.visible && root.detailsOver
    }
    TaskDetails {
        id: details
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
        }
        width: Math.min(380, root.width)
        visible: root.selected !== null
        task: root.selected
        onCloseRequested: root.selected = null
    }

    // Create: a new task in any list.
    Rectangle {
        anchors.fill: parent
        visible: root.creating
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea {
            anchors.fill: parent
            onClicked: root.creating = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 520)
            height: createEditor.implicitHeight + 40
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer3Base
            MouseArea {
                anchors.fill: parent
            }

            TaskEditor {
                id: createEditor
                anchors {
                    fill: parent
                    margins: 20
                }
                showListPicker: true
                listId: Todo.defaultListId
                onDone: root.creating = false
                onSaved: (listId) => {
                    // Show the list the task went to.
                    if (root.hiddenListIds.includes(listId)) root.toggleList(listId)
                    root.creating = false
                }
            }
        }
        onVisibleChanged: if (visible) createEditor.start()
    }

    // New list / rename / delete
    Rectangle {
        id: listDialogScrim
        anchors.fill: parent
        visible: root.listDialog !== null
        color: Qt.rgba(0, 0, 0, 0.35)
        readonly property string mode: root.listDialog?.mode ?? ""
        readonly property var list: Todo.lists.find(l => l.id === root.listDialog?.listId) ?? null
        readonly property int taskCount: Todo.list.filter(t => t.listId === root.listDialog?.listId).length

        function confirm() {
            const name = nameField.text.trim()
            if (mode === "create" && name) Todo.createList(name)
            else if (mode === "rename" && name && list) Todo.renameList(list.id, name)
            else if (mode === "delete" && list) {
                if (root.selected?.listId === list.id) root.selected = null
                Todo.deleteList(list.id)
            } else return
            root.listDialog = null
        }
        onVisibleChanged: {
            if (!visible) return
            nameField.text = mode === "rename" ? (list?.name ?? "") : ""
            if (mode !== "delete") {
                nameField.forceActiveFocus()
                nameField.selectAll()
            } else {
                root.forceActiveFocus()
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.listDialog = null
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 440)
            height: dialogColumn.implicitHeight + 40
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer3Base
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: dialogColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 20
                }
                spacing: 14

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer3
                    text: listDialogScrim.mode === "create" ? Translation.tr("New list")
                        : listDialogScrim.mode === "rename" ? Translation.tr("Rename list")
                        : Translation.tr("Delete \u201c%1\u201d?").arg(listDialogScrim.list?.name ?? "")
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: listDialogScrim.mode === "delete"
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer3
                    text: (listDialogScrim.taskCount === 0 ? Translation.tr("The list is empty.")
                        : listDialogScrim.taskCount === 1 ? Translation.tr("Its task is deleted with it.")
                        : Translation.tr("Its %1 tasks are deleted with it.").arg(listDialogScrim.taskCount))
                        + (listDialogScrim.list?.account && listDialogScrim.list.account !== "local"
                            ? " " + Translation.tr("This deletes it in %1 too.").arg(Accounts.nameOf(listDialogScrim.list.account)) : "")
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: listDialogScrim.mode !== "delete"
                    implicitHeight: 48
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2Base
                    border.width: nameField.activeFocus ? 2 : 1
                    border.color: nameField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    TextField {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        placeholderText: Translation.tr("List name")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.family: Appearance.font.family.main
                        background: null
                        maximumLength: 200
                        onAccepted: listDialogScrim.confirm()
                        Keys.onEscapePressed: event => {
                            root.listDialog = null
                            event.accepted = true
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PanelButton {
                        compact: true
                        text: Translation.tr("Cancel")
                        onClicked: root.listDialog = null
                    }
                    Rectangle {
                        visible: listDialogScrim.mode === "delete"
                        implicitWidth: deleteLabel.implicitWidth + 32
                        implicitHeight: 32
                        radius: Appearance.rounding.full
                        color: deleteMouse.containsMouse ? Appearance.colors.colErrorHover : Appearance.colors.colError
                        StyledText {
                            id: deleteLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Delete")
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnError
                        }
                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: listDialogScrim.confirm()
                        }
                    }
                    PanelButton {
                        visible: listDialogScrim.mode !== "delete"
                        compact: true
                        filled: true
                        text: listDialogScrim.mode === "create" ? Translation.tr("Create") : Translation.tr("Rename")
                        opacity: nameField.text.trim().length > 0 ? 1 : 0.5
                        onClicked: listDialogScrim.confirm()
                    }
                }
            }
        }
    }

    // What Google refused (e.g. deleting its default list)
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        visible: root.errorText !== ""
        width: Math.min(parent.width - 32, errorRow.implicitWidth + 32)
        implicitHeight: 48
        radius: Appearance.rounding.normal
        color: Appearance.colors.colErrorContainer
        RowLayout {
            id: errorRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 32)
            spacing: 10
            MaterialSymbol {
                text: "error"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnErrorContainer
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.errorText
                color: Appearance.colors.colOnErrorContainer
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.errorText = ""
        }
    }
}
