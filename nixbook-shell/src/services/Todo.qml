pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * The to-do list every task widget shows (sidebar, desktop, bar clock popup,
 * the launcher's "add task").
 *
 * Each item has "content", "done", "listId", "notes" and "due" (a Date, or
 * null; date-only, local midnight, when "allDay"). Once an account with
 * tasks is added (services/Accounts.qml) and has its task lists, the list is
 * every account's tasks (Google Tasks…), merged by nixbook-accounts in its
 * local copy ($XDG_STATE_HOME/nixbook-accounts/tasks.json, watched: an
 * agent's or a sync's changes show at once); adding, editing, ticking,
 * moving and deleting go to the task's account through it: `synced` is true
 * and items also carry "uid" and "parentUid" (subtasks) and "account";
 * every item has an "id" (the account's, "<account>:…", or a local one; ""
 * while a new synced task waits for its account's answer). New tasks go to
 * the list asked for, else the first one (the first account's "My Tasks").
 * Otherwise (nixbook-accounts not answering) it is the local list in
 * Directories.todoPath, as before; with the built-in local account ("This
 * computer"), that list is moved into it once (`_migrateLocal`: its lists
 * and tasks created there, the files kept as .bak, then emptied). Synced on first use, every 10 minutes,
 * when the Tasks window opens, and on demand (`sync`).
 *
 * The lists themselves can be created (in an account), renamed and deleted
 * (createList, renameList, deleteList): the accounts' (all `manageable`;
 * their names say their account when there are several), the local ones in
 * todo-lists.json next to the tasks (the first, `localListId`, always
 * stays). A failure lands in `lastError`.
 *
 * The index functions (markDone, deleteItem…) address `list`; the task
 * functions (setTaskDone, updateTask, moveTask, deleteTask) take one of its
 * items, for views that show it filtered or regrouped (the tasks panel).
 */
Singleton {
    id: root

    property bool _started: false
    function load() {
        if (root._started) return
        root._started = true
        Accounts.load()
    }
    property var filePath: Directories.todoPath
    property var list: []

    readonly property bool synced: Accounts.connected && root._googleLists.length > 0
    readonly property string localListId: "local"
    // The lists tasks can go in: [{ id, name, color, manageable, account }].
    readonly property var lists: root.synced
        ? root._googleLists.map(l => {
            const name = root._pendingNames[l.id] ?? l.name
            return { id: l.id, name: root._severalAccounts ? `${name} · ${Accounts.shortName(l.account)}` : name,
                color: "", manageable: true, account: l.account }
        })
        : root._localLists
    readonly property bool _severalAccounts: new Set(root._googleLists.map(l => l.account)).size > 1
    // Google renames shown at once, until the copy carries them.
    property var _pendingNames: ({})
    // nixbook-accounts' copy: [{ id, account, name }] and its tasks.
    property var _googleLists: []
    property var _googleTasks: []
    property bool syncing: false
    property real syncedAt: 0
    readonly property string cachePath: {
        const state = Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
        return `${state}/nixbook-accounts/tasks.json`
    }
    // Lists can be added (Google's or the local ones).
    readonly property bool canCreateLists: true
    // The last list operation that failed ({ message, at }), for the Tasks
    // app's message bar; null when none.
    property var lastError: null
    readonly property string defaultListId: root.lists[0]?.id ?? root.localListId
    // Completed tasks older than this stay in the account, not in the list.
    readonly property int keepDoneDays: 14

    property var _localList: []
    property var _localLists: [{ id: root.localListId, name: Translation.tr("My Tasks"), color: "", manageable: true }]
    property var _remoteList: []

    onSyncedChanged: root._publish()

    function _publish() {
        root.list = (root.synced ? root._remoteList : root._localList).slice(0)
    }

    function _saveLocal() {
        root._publish()
        todoFileView.setText(JSON.stringify(root._localList))
    }

    function _fail(message) {
        let text = String(message || Translation.tr("it didn't work")).split("\n")[0]
        // Google answered with a rate limit: said plainly.
        if (/rate ?limit|quota|too many requests/i.test(text))
            text = Translation.tr("Google is limiting requests right now: nothing changed, try again in a minute")
        root.lastError = { message: text, at: Date.now() }
    }

    // Changes to Google's tasks, in order: onDone(results) with
    // [{ ok, result | error }]. A failure is said (the copy, read again,
    // puts the task back as the account has it, which alone looked like the
    // click didn't take).
    function _apply(ops, onDone) {
        const request = Array.isArray(ops) ? { ops: ops } : ops
        Accounts.call(["tasks", "apply", JSON.stringify(request)], (ok, result, error) => {
            const results = ok && Array.isArray(result) ? result : [{ ok: false, error: error }]
            const failed = results.find(r => !r.ok)
            if (failed) root._fail(failed.error)
            root.reloadRemote()
            if (onDone) onDone(results)
        }, "tasks")
    }

    // -- The lists themselves ------------------------------------------------
    // onDone(ok, listId | error) when given. The account answers after a
    // moment: the lists reload once it did. `account`: where (an account's
    // id; default: the first with tasks).
    function createList(name, onDone, account) {
        name = (name ?? "").trim()
        if (!name) return
        if (!root.synced) {
            const id = `local-list-${Date.now().toString(36)}`
            root._localLists = root._localLists.concat([{ id: id, name: name, color: "", manageable: true }])
            root._saveLocalLists()
            if (onDone) onDone(true, id)
            return
        }
        root._apply(account ? { op: "create_list", name: name, account: account } : { op: "create_list", name: name }, results => {
            if (onDone) onDone(results[0].ok, results[0].ok ? results[0].result.id : results[0].error)
        })
    }

    function renameList(listId, name) {
        name = (name ?? "").trim()
        const list = root.lists.find(l => l.id === listId)
        if (!list || !name || name === list.name) return
        if (!root.synced) {
            root._localLists = root._localLists.map(l => l.id === listId ? Object.assign({}, l, { name: name }) : l)
            root._saveLocalLists()
            return
        }
        root._pendingNames = Object.assign({}, root._pendingNames, { [listId]: name })
        root._apply({ op: "rename_list", list: listId, name: name }, () => {
            const pending = Object.assign({}, root._pendingNames)
            delete pending[listId]
            root._pendingNames = pending
        })
    }

    // The list and every task in it.
    function deleteList(listId) {
        const list = root.lists.find(l => l.id === listId)
        if (!list) return
        if (!root.synced) {
            if (listId === root.localListId) {
                root._fail(Translation.tr("the first list can't be deleted"))
                return
            }
            root._localLists = root._localLists.filter(l => l.id !== listId)
            root._localList = root._localList.filter(t => t.listId !== listId)
            root._saveLocalLists()
            root._saveLocal()
            return
        }
        // Gone at once here; back if Google refuses.
        root._remoteList = root._remoteList.filter(t => t.listId !== listId)
        root._publish()
        root._apply({ op: "delete_list", list: listId })
    }

    // A task in a list that isn't there (the lists file lost) goes to the
    // first one; only once both files are read, whichever comes first.
    property bool _listsRead: false
    property bool _tasksRead: false
    function _fixLocalListIds() {
        if (!root._listsRead || !root._tasksRead) return
        let changed = false
        for (const t of root._localList) {
            if (!root._localLists.some(l => l.id === t.listId)) {
                t.listId = root.localListId
                changed = true
            }
        }
        if (changed) root._saveLocal()
        else root._publish()
        root._migrateLocal()
    }

    function _saveLocalLists() {
        listsFileView.setText(JSON.stringify(root._localLists.map(l => ({ id: l.id, name: l.name }))))
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

    // A due date for nixbook-accounts: the local day, YYYY-MM-DD ("" none).
    function _dueParam(due) {
        return due ? root._dayKey(due) : ""
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
            const op = { op: "create", list: listId, title: full.content }
            if (full.notes) op.notes = full.notes
            if (full.due) op.due = root._dueParam(full.due)
            root._apply(op)
            return
        }
        full.id = root._newLocalId()
        root._localList.push(full)
        root._saveLocal()
    }

    function _newLocalId() {
        return `local-${Date.now().toString(36)}-${Math.floor(Math.random() * 1e6).toString(36)}`
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
            root._apply({ op: done ? "done" : "undone", id: task.id })
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
            params.title = changes.content
        }
        if (changes.notes !== undefined && changes.notes !== (task.notes ?? "")) {
            task.notes = changes.notes
            params.notes = changes.notes
        }
        if (changes.due !== undefined) {
            const due = root._dayOnly(changes.due)
            if ((due?.getTime() ?? null) !== (task.due?.getTime() ?? null)) {
                task.due = due
                task.allDay = !!due
                params.due = root._dueParam(due)
            }
        }
        if (Object.keys(params).length === 0) return
        if (root.synced) {
            root._publish()
            root._apply(Object.assign({ op: "update", id: task.id }, params))
            return
        }
        root._saveLocal()
    }

    // Google moves it (its subtasks with it); it keeps its id.
    function moveTask(task, listId) {
        if (!task || task.listId === listId || !root.lists.some(l => l.id === listId)) return
        if (!root.synced) {
            task.listId = listId
            root._saveLocal()
            return
        }
        if (!task.id) return
        task.listId = listId
        root._publish()
        root._apply({ op: "move", id: task.id, list: listId })
    }

    function deleteTask(task) {
        if (!task) return
        if (root.synced) {
            if (!task.id) return
            root._remoteList.splice(root._remoteList.indexOf(task), 1)
            root._publish()
            root._apply({ op: "delete", id: task.id })
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

    // The local list read again, Google's synced.
    function refresh() {
        todoFileView.reload()
        root.sync()
    }

    // Google's changes now.
    function sync() {
        if (!Accounts.connected || root.syncing) return
        root.syncing = true
        Accounts.call(["tasks", "sync"], () => {
            root.syncing = false
            root.reloadRemote()
        }, "tasks")
    }

    // nixbook-accounts' copy read again (a watch misses a new file).
    function reloadRemote() {
        tasksFile.reload()
    }

    // Unfinished tasks first, soonest due first (none last), then the
    // recently finished ones.
    function _fromGoogle(tasks) {
        const lists = {}
        for (const l of root._googleLists) lists[l.id] = l
        const cutoff = Date.now() - root.keepDoneDays * 24 * 3600 * 1000
        const items = []
        for (const t of tasks) {
            if (!lists[t.listId]) continue
            if (t.done && t.completed && new Date(t.completed).getTime() < cutoff) continue
            const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(t.due ?? "")
            items.push({
                content: t.title || Translation.tr("(No title)"),
                done: !!t.done,
                id: t.id,
                uid: t.id,
                parentUid: t.parent ?? "",
                listId: t.listId,
                account: t.account ?? "",
                notes: t.notes ?? "",
                due: m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null,
                allDay: !!m,
            })
        }
        const dueKey = item => item.due ? item.due.getTime() : Number.MAX_SAFE_INTEGER
        items.sort((a, b) => (a.done !== b.done) ? (a.done ? 1 : -1) : dueKey(a) - dueKey(b))
        return items
    }

    Component.onCompleted: {
        todoFileView.reload()
    }

    // Accounts known (at start): sync. An account added synced already, one
    // removed is gone from the copy: read it.
    Connections {
        target: Accounts
        function onConnectedChanged() {
            if (Accounts.connected) root.sync()
            else root._publish()
        }
        function onAdded() {
            root.reloadRemote()
        }
        function onAccountsChanged() {
            root.reloadRemote()
        }
    }

    Timer {
        interval: 10 * 60 * 1000
        running: Accounts.connected
        repeat: true
        onTriggered: root.sync()
    }

    FileView {
        id: tasksFile
        path: root.cachePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(tasksFile.text())
                root._googleLists = Array.isArray(data.lists) ? data.lists : []
                root._googleTasks = Array.isArray(data.tasks) ? data.tasks : []
                root.syncedAt = data.syncedAt ?? 0
            } catch (e) {
                console.warn("[To Do] unreadable tasks copy: " + e)
            }
            root._remoteList = root._fromGoogle(root._googleTasks)
            root._publish()
            root._migrateLocal()
        }
    }

    // The old local list (todo.json, todo-lists.json) moved into the local
    // account, once: its lists (the first one is the account's "Tasks"),
    // then its tasks; the files kept as .bak, then emptied.
    property bool _migrating: false
    function _migrateLocal() {
        if (root._migrating || !root._tasksRead || !root._listsRead || root._localList.length === 0) return
        const target = root._googleLists.filter(l => l.account === "local")
        if (target.length === 0) return
        root._migrating = true
        const newLists = root._localLists.slice(1).filter(l => !target.some(t => t.name === l.name))
        const afterLists = results => {
            const ids = {}
            ids[root.localListId] = target[0].id
            for (const l of root._localLists.slice(1)) {
                const found = target.find(t => t.name === l.name)
                if (found) ids[l.id] = found.id
            }
            newLists.forEach((l, i) => { if (results[i]?.ok) ids[l.id] = results[i].result.id })
            const ops = root._localList.map(t => {
                const op = { op: "create", list: ids[t.listId] ?? target[0].id, title: t.content || Translation.tr("(No title)") }
                if (t.notes) op.notes = t.notes
                if (t.due) op.due = root._dayKey(t.due)
                if (t.done) op.done = true
                return op
            })
            // Up to 50 changes a call.
            const batches = []
            for (let i = 0; i < ops.length; i += 50) batches.push(ops.slice(i, i + 50))
            const next = () => {
                const batch = batches.shift()
                if (!batch) {
                    const path = String(root.filePath)
                    Quickshell.execDetached(["cp", "-f", path, path + ".bak"])
                    Quickshell.execDetached(["cp", "-f", path.replace(/todo\.json$/, "todo-lists.json"), path.replace(/todo\.json$/, "todo-lists.json.bak")])
                    // After the copies (detached: a moment later).
                    migrateDone.start()
                    return
                }
                root._apply(batch, results => {
                    if (results.some(r => !r.ok)) {
                        // Kept as it is: tried again at the next start.
                        console.warn("[To Do] moving the local list into the local account failed: " + results.find(r => !r.ok).error)
                        return
                    }
                    next()
                })
            }
            next()
        }
        if (newLists.length > 0)
            root._apply(newLists.map(l => ({ op: "create_list", name: l.name, account: "local" })), afterLists)
        else
            afterLists([])
    }
    Timer {
        id: migrateDone
        interval: 1500
        onTriggered: {
            root._localList = []
            root._localLists = root._localLists.slice(0, 1)
            todoFileView.setText("[]")
            root._saveLocalLists()
            console.log("[To Do] the local list moved into the local account (files kept as .bak)")
        }
    }

    // The local lists (read at once, before the tasks that refer to them).
    FileView {
        id: listsFileView
        path: Qt.resolvedUrl(String(root.filePath).replace(/todo\.json$/, "todo-lists.json"))
        blockLoading: true
        // Written at once, in order: a batch of changes (an agent's) writes
        // several times in a row, and a slower earlier write could land last.
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(listsFileView.text())
                const rest = saved.filter(l => l.id && l.id !== root.localListId && l.name)
                const first = saved.find(l => l.id === root.localListId)
                root._localLists = [{ id: root.localListId, name: first?.name || Translation.tr("My Tasks"), color: "", manageable: true }]
                    .concat(rest.map(l => ({ id: l.id, name: l.name, color: "", manageable: true })))
            } catch (e) {
                console.log("[To Do] Bad lists file: " + e)
            }
            root._listsRead = true
            root._fixLocalListIds()
        }
        onLoadFailed: {
            root._listsRead = true
            root._fixLocalListIds()
        }
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        // As the lists': written at once and in order.
        blockWrites: true
        atomicWrites: true
        onLoaded: {
            const fileContents = todoFileView.text()
            // JSON keeps dates as strings; older files have no list or notes.
            root._localList = JSON.parse(fileContents).map(t => Object.assign(t, {
                id: t.id || root._newLocalId(),
                // Older files have no list.
                listId: t.listId || root.localListId,
                notes: t.notes ?? "",
                due: t.due ? new Date(t.due) : null,
                allDay: !!t.due,
            }))
            root._tasksRead = true
            root._fixLocalListIds()
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

    // -- Agents (the desktop MCP server's `tasks` tool) ------------------
    // Requests and replies travel through files (a large IPC message can
    // wedge Quickshell's IPC), like the notes': only tasks-*.json directly in
    // the MCP server's private runtime directory.
    readonly property string transferDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-desktop-mcp/`
    function _isTransferPath(path) {
        if (typeof path !== "string" || !path.startsWith(root.transferDir + "tasks-"))
            return false
        return /^tasks-[A-Za-z0-9_-]{1,64}\.json$/.test(path.slice(root.transferDir.length))
    }

    function _dayKey(date) {
        const pad = n => (n < 10 ? "0" : "") + n
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
    }

    // Everything an agent needs to organize the tasks: the lists (with
    // their counts) and every task, by id.
    function agentState() {
        const byUid = {}
        for (const t of root.list) if (t.uid) byUid[t.uid] = t
        return {
            synced: root.synced,
            today: root._dayKey(new Date()),
            canCreateLists: root.canCreateLists,
            accounts: Accounts.accounts.map(a => ({ id: a.id, name: a.name })),
            lists: root.lists.map(l => ({
                id: l.id,
                name: l.name,
                account: l.account ?? "",
                manageable: !!l.manageable,
                open: root.list.filter(t => t.listId === l.id && !t.done).length,
                completed: root.list.filter(t => t.listId === l.id && t.done).length,
            })),
            tasks: root.list.map(t => {
                const out = {
                    id: t.id || null,
                    title: t.content,
                    list: root.listName(t.listId),
                    listId: t.listId,
                    done: t.done,
                    notes: t.notes ?? "",
                    due: t.due ? root._dayKey(t.due) : null,
                    deadline: t.done ? null : root.deadlineGroup(t),
                }
                const parent = t.parentUid ? byUid[t.parentUid] : null
                if (parent) out.parent = parent.id
                if (!t.id) out.syncing = true
                return out
            }),
        }
    }

    function _findList(ref) {
        if (ref === undefined || ref === null || ref === "") return null
        const want = String(ref).toLowerCase()
        const found = root.lists.find(l => l.id === ref) ?? root.lists.find(l => l.name.toLowerCase() === want)
        if (found) return found
        // The list's own name, without its account: when only one has it.
        const bare = root._googleLists.filter(l => l.name.toLowerCase() === want)
        if (bare.length > 1) throw `"${ref}" is a list in several accounts: give its id`
        return bare.length === 1 ? root.lists.find(l => l.id === bare[0].id) : null
    }
    // "YYYY-MM-DD", "today", "tomorrow", "+N" (days from today); null or ""
    // clears. undefined: not given.
    function _parseDue(value) {
        if (value === undefined) return undefined
        if (value === null || value === "") return null
        const v = String(value).trim().toLowerCase()
        const now = new Date()
        const inDays = n => new Date(now.getFullYear(), now.getMonth(), now.getDate() + n)
        if (v === "today") return inDays(0)
        if (v === "tomorrow") return inDays(1)
        let m = /^\+(\d{1,4})$/.exec(v)
        if (m) return inDays(Number(m[1]))
        m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v)
        if (m) {
            const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
            if (d.getMonth() === Number(m[2]) - 1) return d
        }
        throw `bad due date "${value}": YYYY-MM-DD, today, tomorrow, +N, or "" to clear`
    }
    function _findTask(ref) {
        if (!ref) throw "which task? give its id (from list)"
        const t = root.list.find(t => t.id === ref)
        if (!t) throw `no task "${ref}" (list again: ids change once a moved or new task syncs)`
        return t
    }
    function _text(value, what, max) {
        if (typeof value !== "string") throw `${what} must be text`
        const v = value.trim()
        if (v.length > max) throw `${what}: at most ${max} characters`
        return v
    }

    // One operation: { op: create | update | done | undone | delete | move
    // | clear_completed | open, … }. Returns what it did; throws an error.
    function agentOp(o) {
        switch (o?.op) {
        case "create": {
            const title = root._text(o.title ?? "", "title", 1000)
            if (!title) throw "create: needs a title"
            const list = o.list !== undefined ? root._findList(o.list) : null
            if (o.list !== undefined && !list) throw `no list "${o.list}": ${root.lists.map(l => l.name).join(", ")}`
            const listId = list?.id ?? root.defaultListId
            root.addTask(title, {
                listId: listId,
                notes: o.notes !== undefined ? root._text(o.notes, "notes", 8000) : "",
                due: root._parseDue(o.due) ?? null,
            })
            return `created "${title}" in ${root.listName(listId)}`
        }
        case "update": {
            const t = root._findTask(o.task)
            if (root.synced && !t.id) throw "that task is still syncing, try again in a moment"
            const changes = {}
            if (o.title !== undefined) {
                changes.content = root._text(o.title, "title", 1000)
                if (!changes.content) throw "update: the title can't be empty"
            }
            if (o.notes !== undefined) changes.notes = root._text(o.notes ?? "", "notes", 8000)
            const due = root._parseDue(o.due)
            if (due !== undefined) changes.due = due
            if (Object.keys(changes).length === 0) throw "update: give title, notes or due"
            root.updateTask(t, changes)
            return `updated "${t.content}"`
        }
        case "done":
        case "undone": {
            const t = root._findTask(o.task)
            root.setTaskDone(t, o.op === "done")
            return `${o.op === "done" ? "completed" : "reopened"} "${t.content}"`
        }
        case "delete": {
            const t = root._findTask(o.task)
            root.deleteTask(t)
            return `deleted "${t.content}"`
        }
        case "move": {
            const t = root._findTask(o.task)
            const list = root._findList(o.list)
            if (!list) throw `no list "${o.list}": ${root.lists.map(l => l.name).join(", ")}`
            if (t.listId === list.id) return `"${t.content}" is already in ${list.name}`
            root.moveTask(t, list.id)
            return `moved "${t.content}" to ${list.name}`
        }
        case "clear_completed": {
            const list = o.list !== undefined ? root._findList(o.list) : null
            if (o.list !== undefined && !list) throw `no list "${o.list}": ${root.lists.map(l => l.name).join(", ")}`
            const done = root.list.filter(t => t.done && (!list || t.listId === list.id))
            for (const t of done) root.deleteTask(t)
            return `deleted ${done.length} completed task${done.length === 1 ? "" : "s"}`
        }
        case "create_list": {
            const name = root._text(o.name ?? "", "name", 200)
            if (!name) throw "create_list: needs a name"
            if (root.lists.some(l => l.name.toLowerCase() === name.toLowerCase())) throw `there is already a list "${name}"`
            if (o.account !== undefined && o.account !== null && !Accounts.accounts.some(a => a.id === o.account || a.name === o.account))
                throw `no account "${o.account}": ${Accounts.accounts.map(a => a.id).join(", ")}`
            const account = Accounts.accounts.find(a => a.id === o.account || a.name === o.account)?.id
            root.createList(name, null, account)
            return root.synced ? `creating list "${name}" (list again in a moment for its id)` : `created list "${name}"`
        }
        case "rename_list": {
            const list = root._findList(o.list)
            if (!list) throw `no list "${o.list}": ${root.lists.map(l => l.name).join(", ")}`
            const name = root._text(o.name ?? "", "name", 200)
            if (!name) throw "rename_list: needs a name"
            if (!list.manageable) throw `"${list.name}" can't be renamed from here`
            root.renameList(list.id, name)
            return `renamed "${list.name}" to "${name}"`
        }
        case "delete_list": {
            const list = root._findList(o.list)
            if (!list) throw `no list "${o.list}": ${root.lists.map(l => l.name).join(", ")}`
            if (!list.manageable) throw `"${list.name}" can't be deleted from here`
            if (!root.synced && list.id === root.localListId) throw "the first list can't be deleted"
            const count = root.list.filter(t => t.listId === list.id).length
            root.deleteList(list.id)
            const tasks = `${count} task${count === 1 ? "" : "s"}`
            return root.synced
                ? `asked Google to delete list "${list.name}" and its ${tasks} (Google refuses its default list: list again to check)`
                : `deleted list "${list.name}" and its ${tasks}`
        }
        case "open": {
            if (o.task) root._findTask(o.task)
            GlobalStates.openTasksPanel(o.task ?? "")
            return "opened the Tasks window"
        }
        default:
            throw `unknown op "${o?.op}": create, update, done, undone, delete, move, clear_completed, open, create_list, rename_list, delete_list`
        }
    }

    FileView {
        id: agentIn
        blockLoading: true
        printErrors: false
    }
    // Loads (nothing: the file doesn't exist yet) and writes synchronously.
    FileView {
        id: agentOut
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    IpcHandler {
        target: "todo"

        // The lists and tasks (agentState), written to a transfer file.
        function query(path: string): string {
            if (!root._isTransferPath(path))
                return "error: not a transfer file";
            agentOut.path = "";
            agentOut.path = path;
            agentOut.setText(JSON.stringify(root.agentState()));
            return "ok";
        }
        // Runs the operations in a transfer file ({op…} or {ops: […]}, in
        // order, each on its own) and writes back [{ ok, result | error }].
        function apply(path: string): string {
            if (!root._isTransferPath(path))
                return "error: not a transfer file";
            agentIn.path = "";
            agentIn.path = path;
            agentIn.reload();
            let request;
            try {
                request = JSON.parse(agentIn.text());
            } catch (e) {
                return "error: the request isn't JSON";
            }
            const ops = Array.isArray(request?.ops) ? request.ops : [request];
            const results = ops.map(o => {
                try {
                    return { ok: true, result: root.agentOp(o) };
                } catch (e) {
                    return { ok: false, error: String(e) };
                }
            });
            agentOut.path = "";
            agentOut.path = path;
            agentOut.setText(JSON.stringify(results));
            return "ok";
        }

        function list(): string {
            return JSON.stringify({
                synced: root.synced,
                tasks: root.list.map((t, i) => ({ index: i, id: t.id || null, content: t.content, done: t.done, due: t.due ? root._dayKey(t.due) : null, list: root.listName(t.listId) })),
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
