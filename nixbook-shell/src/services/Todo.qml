pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * The to-do list every task widget shows (sidebar, desktop, bar clock popup,
 * the launcher's "add task").
 *
 * Each item has "content", "done", "listId", "notes" and "due" (a Date, or
 * null; date-only, local midnight, when "allDay"). While DankCalendar has a
 * task list (CalendarEvents.taskLists: Google Tasks, CalDAV VTODO…), the
 * list is that account's tasks, and adding, editing, ticking and deleting go
 * through dcal, which syncs them: `synced` is true and items also carry
 * "id", "uid" and "parentUid" (subtasks). New tasks go to the list asked
 * for, else the first one (Google's "My Tasks"). Otherwise it is the local
 * list in Directories.todoPath, as before (one list, `localListId`); that
 * file is left alone while synced.
 *
 * The index functions (markDone, deleteItem…) address `list`; the task
 * functions (setTaskDone, updateTask, moveTask, deleteTask) take one of its
 * items, for views that show it filtered or regrouped (the tasks panel).
 */
Singleton {
    id: root

    function load() {}
    property var filePath: Directories.todoPath
    property var list: []

    readonly property bool synced: CalendarEvents.available && CalendarEvents.taskLists.length > 0
    readonly property string localListId: "local"
    // The lists tasks can go in: [{ id, name, color }].
    readonly property var lists: root.synced ? CalendarEvents.taskLists
        : [{ id: root.localListId, name: Translation.tr("My Tasks"), color: "" }]
    readonly property string defaultListId: root.lists[0]?.id ?? root.localListId
    // Completed tasks older than this stay in the account, not in the list.
    readonly property int keepDoneDays: 14

    property var _localList: []
    property var _remoteList: []

    onSyncedChanged: root._publish()

    function _publish() {
        root.list = (root.synced ? root._remoteList : root._localList).slice(0)
    }

    function _saveLocal() {
        root._publish()
        todoFileView.setText(JSON.stringify(root._localList))
    }

    // A list's name ("" when it is gone).
    function listName(listId) {
        return root.lists.find(l => l.id === listId)?.name ?? ""
    }

    // "Today", "Tomorrow", "Yesterday", "Wed, Oct 15" ("…, 2027" another
    // year); "" for none.
    function dueText(due) {
        if (!due) return ""
        const now = new Date()
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const days = Math.round((root._dayOnly(due) - today) / 86400000)
        if (days === 0) return Translation.tr("Today")
        if (days === 1) return Translation.tr("Tomorrow")
        if (days === -1) return Translation.tr("Yesterday")
        const fmt = due.getFullYear() === now.getFullYear() ? "ddd, MMM d" : "ddd, MMM d, yyyy"
        return Qt.locale().toString(due, fmt)
    }

    function _daysLeft(due) {
        const now = new Date()
        return Math.round((root._dayOnly(due) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000)
    }

    // "3 days overdue", "Due today", "Due tomorrow", "Due in 5 days"; "" for
    // none or a finished task.
    function deadlineText(task) {
        if (!task?.due || task.done) return ""
        const days = root._daysLeft(task.due)
        if (days < -1) return Translation.tr("%1 days overdue").arg(-days)
        if (days === -1) return Translation.tr("1 day overdue")
        if (days === 0) return Translation.tr("Due today")
        if (days === 1) return Translation.tr("Due tomorrow")
        return Translation.tr("Due in %1 days").arg(days)
    }

    // Deadline groups, in order: the tasks panel's "sort by deadline".
    readonly property var deadlineGroups: [
        { key: "overdue", name: Translation.tr("Overdue") },
        { key: "today", name: Translation.tr("Today") },
        { key: "tomorrow", name: Translation.tr("Tomorrow") },
        { key: "week", name: Translation.tr("Next 7 days") },
        { key: "later", name: Translation.tr("Later") },
        { key: "none", name: Translation.tr("No deadline") },
    ]
    function deadlineGroup(task) {
        if (!task?.due) return "none"
        const days = root._daysLeft(task.due)
        if (days < 0) return "overdue"
        if (days === 0) return "today"
        if (days === 1) return "tomorrow"
        return days <= 7 ? "week" : "later"
    }

    // Unfinished tasks due before today / by the end of today.
    readonly property int overdueCount: root.list.filter(t => root.isOverdue(t)).length
    readonly property int dueTodayCount: root.list.filter(t => !t.done && t.due && root._daysLeft(t.due) === 0).length

    // Unfinished and due before today.
    function isOverdue(task) {
        if (!task?.due || task.done) return false
        const now = new Date()
        return root._dayOnly(task.due) < new Date(now.getFullYear(), now.getMonth(), now.getDate())
    }

    // Google keeps a due date as that day's UTC midnight: send the local
    // date the same way.
    function _dueParam(due) {
        if (!due) return ""
        const pad = n => (n < 10 ? "0" : "") + n
        return `${due.getFullYear()}-${pad(due.getMonth() + 1)}-${pad(due.getDate())}T00:00:00Z`
    }

    function _dayOnly(date) {
        return date ? new Date(date.getFullYear(), date.getMonth(), date.getDate()) : null
    }

    function addItem(item) {
        const listId = root.lists.some(l => l.id === item.listId) ? item.listId : root.defaultListId
        const full = Object.assign({ notes: "", due: null, allDay: !!item.due }, item, { listId: listId })
        if (root.synced) {
            // Shown at once; the reload brings its id.
            root._remoteList.push(Object.assign({ id: "", uid: "", parentUid: "" }, full))
            root._publish()
            const params = { calendarId: listId, summary: full.content }
            if (full.notes) params.description = full.notes
            if (full.due) {
                params.due = root._dueParam(full.due)
                params.allDay = true
            }
            CalendarEvents.call("tasks.create", params, () => root.reloadRemote())
            return
        }
        root._localList.push(full)
        root._saveLocal()
    }

    // `options`: { listId, notes, due (Date) }, all optional.
    function addTask(desc, options) {
        const item = Object.assign({
            "content": desc,
            "done": false,
        }, options ?? {})
        item.due = root._dayOnly(item.due)
        addItem(item)
    }

    function setTaskDone(task, done) {
        if (!task) return
        if (root.synced) {
            if (!task.id) return
            task.done = done
            root._publish()
            CalendarEvents.call("tasks.complete", { id: task.id, completed: done }, () => root.reloadRemote())
            return
        }
        task.done = done
        root._saveLocal()
    }

    // `changes`: any of { content, notes, due (Date, or null to clear) }.
    function updateTask(task, changes) {
        if (!task || (root.synced && !task.id)) return
        const params = {}
        if (changes.content !== undefined && changes.content.trim().length > 0 && changes.content !== task.content) {
            task.content = changes.content
            params.summary = changes.content
        }
        if (changes.notes !== undefined && changes.notes !== (task.notes ?? "")) {
            task.notes = changes.notes
            params.description = changes.notes
        }
        if (changes.due !== undefined) {
            const due = root._dayOnly(changes.due)
            if ((due?.getTime() ?? null) !== (task.due?.getTime() ?? null)) {
                task.due = due
                task.allDay = !!due
                params.due = root._dueParam(due)
                if (due) params.allDay = true
            }
        }
        if (Object.keys(params).length === 0) return
        if (root.synced) {
            root._publish()
            params.id = task.id
            CalendarEvents.call("tasks.update", params, () => root.reloadRemote())
            return
        }
        root._saveLocal()
    }

    // dcal can't move a task between lists: it is created in the other one
    // (title, notes, due, done) and then deleted from this one.
    function moveTask(task, listId) {
        if (!task || task.listId === listId || !root.lists.some(l => l.id === listId)) return
        if (!root.synced) {
            task.listId = listId
            root._saveLocal()
            return
        }
        if (!task.id) return
        const params = { calendarId: listId, summary: task.content }
        if (task.notes) params.description = task.notes
        if (task.due) {
            params.due = root._dueParam(task.due)
            params.allDay = true
        }
        if (task.done) params.status = "completed"
        const oldId = task.id
        task.listId = listId
        task.id = ""
        root._publish()
        CalendarEvents.call("tasks.create", params, ok => {
            if (ok)
                CalendarEvents.call("tasks.delete", { id: oldId }, () => root.reloadRemote())
            else
                root.reloadRemote()
        })
    }

    function deleteTask(task) {
        if (!task) return
        if (root.synced) {
            if (!task.id) return
            root._remoteList.splice(root._remoteList.indexOf(task), 1)
            root._publish()
            CalendarEvents.call("tasks.delete", { id: task.id }, () => root.reloadRemote())
            return
        }
        const i = root._localList.indexOf(task)
        if (i < 0) return
        root._localList.splice(i, 1)
        root._saveLocal()
    }

    function markDone(index) {
        root.setTaskDone(root.list[index], true)
    }

    function markUnfinished(index) {
        root.setTaskDone(root.list[index], false)
    }

    function deleteItem(index) {
        root.deleteTask(root.list[index])
    }

    // The `count` unfinished tasks to show first: the soonest due when
    // synced, the newest added otherwise.
    function pending(count) {
        const open = root.list.filter(t => !t.done)
        return root.synced ? open.slice(0, count) : open.slice(-count).reverse()
    }

    function refresh() {
        todoFileView.reload()
        root.reloadRemote()
    }

    function reloadRemote() {
        if (!root.synced) return
        CalendarEvents.call("tasks.list", { includeCompleted: true }, (ok, result) => {
            if (ok && result) root._remoteList = root._fromDcal(result.tasks ?? [])
            root._publish()
        })
    }

    // Unfinished tasks first, soonest due first (none last), then the
    // recently finished ones.
    function _fromDcal(tasks) {
        const lists = {}
        for (const l of CalendarEvents.taskLists) lists[l.id] = l
        const cutoff = Date.now() - root.keepDoneDays * 24 * 3600 * 1000
        const items = []
        for (const t of tasks) {
            if (!lists[t.calendarId] || t.status === "cancelled") continue
            const done = t.status === "completed"
            if (done && t.completed && new Date(t.completed).getTime() < cutoff) continue
            // An all-day due date is that day's UTC midnight.
            const due = t.due ? new Date(t.due) : null
            items.push({
                content: t.summary || Translation.tr("(No title)"),
                done: done,
                id: t.id,
                uid: t.uid ?? "",
                parentUid: t.parentUid ?? "",
                listId: t.calendarId,
                notes: t.description ?? "",
                due: due && t.allDay ? new Date(due.getUTCFullYear(), due.getUTCMonth(), due.getUTCDate()) : due,
                allDay: !!t.allDay,
            })
        }
        const dueKey = item => item.due ? item.due.getTime() : Number.MAX_SAFE_INTEGER
        items.sort((a, b) => (a.done !== b.done) ? (a.done ? 1 : -1) : dueKey(a) - dueKey(b))
        return items
    }

    Component.onCompleted: {
        refresh()
    }

    Connections {
        target: CalendarEvents
        function onRefreshed() {
            root.reloadRemote()
        }
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text()
            // JSON keeps dates as strings; older files have no list or notes.
            root._localList = JSON.parse(fileContents).map(t => Object.assign(t, {
                listId: root.localListId,
                notes: t.notes ?? "",
                due: t.due ? new Date(t.due) : null,
                allDay: !!t.due,
            }))
            root._publish()
            console.log("[To Do] File loaded")
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root._localList = []
                root._saveLocal()
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }

    // `nixbook-shell ipc call todo list|add|done|undone|remove`: the task
    // list every to-do widget shows (synced with the calendar account when
    // there is one), for key bindings and the desktop MCP server. Tasks are
    // addressed by their index in `list`.
    function _ipcCheck(index) {
        if (!root.list[index])
            return `error: no task ${index}`;
        if (root.synced && !root.list[index].id)
            return "error: that task is still syncing, try again in a moment";
        return "";
    }

    IpcHandler {
        target: "todo"

        function list(): string {
            return JSON.stringify({
                synced: root.synced,
                tasks: root.list.map((t, i) => ({ index: i, content: t.content, done: t.done, due: t.due ?? null })),
            });
        }
        function add(content: string): string {
            if (content.length === 0)
                return "error: empty task";
            root.addTask(content);
            return "ok";
        }
        function done(index: int): string {
            const err = root._ipcCheck(index);
            if (err)
                return err;
            root.markDone(index);
            return `ok: ${root.list[index]?.content ?? index}`;
        }
        function undone(index: int): string {
            const err = root._ipcCheck(index);
            if (err)
                return err;
            root.markUnfinished(index);
            return `ok: ${root.list[index]?.content ?? index}`;
        }
        function remove(index: int): string {
            const err = root._ipcCheck(index);
            if (err)
                return err;
            const task = root.list[index];
            root.deleteItem(index);
            return `ok: ${task.content}`;
        }
    }
}
