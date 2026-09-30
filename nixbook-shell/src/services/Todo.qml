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
 * Each item has "content" and "done". While DankCalendar has a task list
 * (CalendarEvents.taskLists: Google Tasks, CalDAV VTODO…), the list is that
 * account's tasks, and adding, ticking and deleting go through dcal, which
 * syncs them: `synced` is true and items also carry "id", "listId" and
 * "due". New tasks go to the first list (Google's "My Tasks"). Otherwise it
 * is the local list in Directories.todoPath, as before; that file is left
 * alone while synced.
 */
Singleton {
    id: root

    function load() {}
    property var filePath: Directories.todoPath
    property var list: []

    readonly property bool synced: CalendarEvents.available && CalendarEvents.taskLists.length > 0
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

    function addItem(item) {
        if (root.synced) {
            const listId = CalendarEvents.taskLists[0].id
            // Shown at once; the reload brings its id.
            root._remoteList.push(Object.assign({ id: "", listId: listId, due: null }, item))
            root._publish()
            CalendarEvents.call("tasks.create", { calendarId: listId, summary: item.content }, () => root.reloadRemote())
            return
        }
        root._localList.push(item)
        root._saveLocal()
    }

    function addTask(desc) {
        const item = {
            "content": desc,
            "done": false,
        }
        addItem(item)
    }

    function _setDone(index, done) {
        const current = root.list[index]
        if (!current) return
        if (root.synced) {
            if (!current.id) return
            current.done = done
            root._publish()
            CalendarEvents.call("tasks.complete", { id: current.id, completed: done }, () => root.reloadRemote())
            return
        }
        root._localList[index].done = done
        root._saveLocal()
    }

    function markDone(index) {
        root._setDone(index, true)
    }

    function markUnfinished(index) {
        root._setDone(index, false)
    }

    function deleteItem(index) {
        const current = root.list[index]
        if (!current) return
        if (root.synced) {
            if (!current.id) return
            root._remoteList.splice(root._remoteList.indexOf(current), 1)
            root._publish()
            CalendarEvents.call("tasks.delete", { id: current.id }, () => root.reloadRemote())
            return
        }
        root._localList.splice(index, 1)
        root._saveLocal()
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
            items.push({
                content: t.summary || Translation.tr("(No title)"),
                done: done,
                id: t.id,
                listId: t.calendarId,
                due: t.due ? new Date(t.due) : null,
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
            root._localList = JSON.parse(fileContents)
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
