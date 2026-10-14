import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Tasks: the to-do list (services/Todo.qml) as an app, laid out like Google
 * Tasks. Every task list is a column (shown or hidden from the side bar),
 * with its open tasks, subtasks under their parent, and the completed ones
 * folded at the bottom; "Deadlines" gathers every list's dated tasks by
 * deadline (Overdue, Today…). A task opens its details (title, notes,
 * deadline, list); "Create" adds a task to any list.
 *
 * A normal application window (xdg-toplevel, title "Tasks"), tiled like any
 * app (no floating rule): its layout follows the column width it gets. Opened by the
 * desktop to-do widget (GlobalStates.openTasksPanel), its launcher entry or
 * `nixbook-shell ipc call tasks open|toggle|close`.
 */
Scope {
    id: root

    property bool everOpened: false

    Connections {
        target: GlobalStates
        function onTasksPanelOpenChanged() {
            if (!GlobalStates.tasksPanelOpen) return
            root.everOpened = true
            Todo.refresh()
        }
    }

    Loader {
        active: root.everOpened

        sourceComponent: FloatingWindow {
            id: tasksWindow
            title: Translation.tr("Tasks")
            visible: GlobalStates.tasksPanelOpen
            implicitWidth: 1240
            implicitHeight: 800
            minimumSize: Qt.size(360, 400)
            color: Appearance.colors.colLayer0Base

            // The compositor closing it (Mod+Q…) closes the app.
            onClosed: GlobalStates.tasksPanelOpen = false
            onVisibleChanged: {
                if (!visible && GlobalStates.tasksPanelOpen)
                    GlobalStates.tasksPanelOpen = false
                if (visible) content.opened(GlobalStates.tasksPanelTaskId)
            }
            Component.onCompleted: content.opened(GlobalStates.tasksPanelTaskId)

            // Opened again while shown (another task clicked in the widget).
            Connections {
                target: GlobalStates
                function onTasksPanelTaskIdChanged() {
                    if (tasksWindow.visible && GlobalStates.tasksPanelTaskId)
                        content.opened(GlobalStates.tasksPanelTaskId)
                }
            }

            TasksPanelContent {
                id: content
                anchors.fill: parent
                focus: true
            }
        }
    }

    IpcHandler {
        target: "tasks"

        function toggle(): void {
            if (GlobalStates.tasksPanelOpen) GlobalStates.tasksPanelOpen = false
            else GlobalStates.openTasksPanel("")
        }
        function open(): void {
            GlobalStates.openTasksPanel("")
        }
        function close(): void {
            GlobalStates.tasksPanelOpen = false
        }
    }
}
