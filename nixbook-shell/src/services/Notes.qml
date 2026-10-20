pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple notes manager.
 * Each item is an object with "id", "content", "attachments" (array of file paths), "createdAt",
 * "updatedAt" (last edit; createdAt for older notes) and "pinned".
 * Shown by the notes desktop widget and the Notes app (modules/ii/notesApp).
 *
 * A note synced with Google Keep also carries "keepId" (the Keep note's id)
 * and "keepEdited" (when it was last synced): the sync of the notes with
 * Keep (services/KeepSync.qml) needs them to tell which side changed.
 *
 * The overlay's Notes widget (modules/ii/overlay/notes) is the editor of one
 * of these notes, the scratchpad: the note with "scratchpad": true (Keep
 * can't store the flag, but the sync hands every note back with its fields,
 * so it stays). It is created with the overlay's first text, and again after
 * it was deleted. Its older file (notes.txt, a single text) is imported once
 * as the scratchpad, then renamed notes.txt.migrated.
 */
Singleton {
    id: root

    function load() {}
    property var filePath: Directories.desktopNotesPath ?? (Directories.config + "/notes.json")
    property var list: []
    // Pinned first, then the most recently edited: what the widget and the
    // Notes app show. An emptied scratchpad stays (linked to its Keep note)
    // but isn't listed.
    readonly property var sorted: root.list.filter(n => !(n.scratchpad && n.content.trim() === "")).sort((a, b) =>
        (!!b.pinned - !!a.pinned) || ((b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0)))

    // Whether the notes file has been read: a change before that (an IPC call
    // right at start) would write the file with only that note, so it reads
    // the file first.
    property bool ready: false
    function ensureLoaded() {
        // text() blocks until the pending read is done (blockLoading), and
        // the read's onLoaded/onLoadFailed fills the list.
        if (!root.ready) notesFileView.text()
    }

    // `extra`: more fields for the new note (the scratchpad's flag).
    function addNote(content, attachments, extra) {
        root.ensureLoaded()
        const item = Object.assign({
            "id": Date.now().toString() + "-" + Math.floor(Math.random() * 10000),
            "content": content ?? "",
            "attachments": attachments ?? [],
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "pinned": false
        }, extra ?? {})
        list.push(item)
        root.list = list.slice(0)
        notesFileView.setText(JSON.stringify(root.list))
        return item.id
    }

    // A changed note is a new object (the others stay the same): the lists
    // showing the notes (a ScriptModel keyed by id) see which one changed.
    function updateNote(id, content, attachments) {
        root.ensureLoaded()
        const idx = list.findIndex(n => n.id === id)
        if (idx >= 0) {
            const changes = { "content": content, "updatedAt": Date.now() }
            if (attachments !== undefined)
                changes.attachments = attachments
            list[idx] = Object.assign({}, list[idx], changes)
            root.list = list.slice(0)
            notesFileView.setText(JSON.stringify(root.list))
        }
    }

    function setPinned(id, pinned) {
        root.ensureLoaded()
        const idx = list.findIndex(n => n.id === id)
        if (idx < 0) return
        list[idx] = Object.assign({}, list[idx], { "pinned": pinned })
        root.list = list.slice(0)
        notesFileView.setText(JSON.stringify(root.list))
    }

    // A deleted note back as it was (the Notes app's Undo). A scratchpad
    // restored after the overlay started a new one comes back as a plain
    // note: there is one scratchpad.
    function restoreNote(note) {
        root.ensureLoaded()
        if (!note || list.some(n => n.id === note.id)) return
        if (note.scratchpad && root.scratchpad)
            note = Object.assign({}, note, { "scratchpad": false })
        list.push(note)
        root.list = list.slice(0)
        notesFileView.setText(JSON.stringify(root.list))
    }

    function deleteNote(id) {
        root.ensureLoaded()
        const idx = list.findIndex(n => n.id === id)
        if (idx >= 0) {
            list.splice(idx, 1)
            root.list = list.slice(0)
            notesFileView.setText(JSON.stringify(root.list))
        }
    }

    // The sync's merged notes (services/KeepSync.qml): the whole list is
    // replaced and the file written once, like every other change.
    function applySynced(items) {
        root.ensureLoaded()
        root.list = (items ?? []).slice(0)
        notesFileView.setText(JSON.stringify(root.list))
    }

    // The overlay's scratchpad (see above), null until its first text.
    readonly property var scratchpad: root.list.find(n => n.scratchpad === true) ?? null

    // The scratchpad's new text: the note is updated, or created with its
    // first text (an emptied one stays, unlisted). `now`: written before
    // this returns (the overlay closing or the shell reloading).
    function setScratchpad(content, now) {
        root.ensureLoaded()
        const text = content ?? ""
        const note = root.list.find(n => n.scratchpad === true)
        if (note ? note.content === text : text.trim() === "") return
        if (now) notesFileView.blockWrites = true
        try {
            if (note) root.updateNote(note.id, text)
            else root.addNote(text, [], { "scratchpad": true })
        } finally {
            notesFileView.blockWrites = false
        }
    }

    // Once, after the first read: the overlay's older notes file (one
    // text, not in the Notes app nor synced) becomes the scratchpad, if
    // there isn't one yet, and is renamed notes.txt.migrated (an older
    // .migrated kept as .migrated.~1~): nothing is deleted.
    property bool _scratchpadMigrated: false
    function migrateScratchpad() {
        if (root._scratchpadMigrated) return
        root._scratchpadMigrated = true
        const path = Directories.legacyNotesPath
        legacyScratchpad.path = ""
        legacyScratchpad.path = path
        legacyScratchpad.reload()
        const text = legacyScratchpad.text()
        legacyScratchpad.path = ""
        if (text.trim() === "") return
        if (!root.scratchpad) {
            // Written before the rename.
            notesFileView.blockWrites = true
            try {
                root.addNote(text, [], { "scratchpad": true })
            } finally {
                notesFileView.blockWrites = false
            }
            console.log("[Notes] The overlay's notes.txt is now the scratchpad note")
        }
        Quickshell.execDetached(["mv", "--backup=numbered", "--", path, `${path}.migrated`])
    }
    FileView {
        id: legacyScratchpad
        blockLoading: true
        printErrors: false
    }

    function refresh() {
        notesFileView.reload()
    }

    // Long notes travel through files, not IPC arguments or replies (a large
    // IPC message can wedge Quickshell's IPC): the desktop MCP server writes
    // the text to a private file and passes its path, or gives a path for the
    // list. Only its own transfer files: notes-* directly in its private
    // runtime directory, so these can't read or write anything else.
    readonly property string transferDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-desktop-mcp/`
    function isTransferPath(path) {
        if (typeof path !== "string" || !path.startsWith(root.transferDir + "notes-"))
            return false
        const name = path.slice(root.transferDir.length)
        return /^notes-[A-Za-z0-9_-]{1,64}\.(txt|json)$/.test(name)
    }
    function readTransfer(path) {
        transferIn.path = ""
        transferIn.path = path
        transferIn.reload()
        return transferIn.text()
    }
    FileView {
        id: transferIn
        blockLoading: true
        printErrors: false
    }
    // Loads (nothing: the file doesn't exist yet) and writes synchronously:
    // a write right after an asynchronous path change can be lost.
    FileView {
        id: transferOut
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    Component.onCompleted: {
        refresh()
    }

    // A notes file that can't be read is copied aside (desktopnotes.txt.corrupt-<ms>)
    // before the notes start over: the next change rewrites the file.
    FileView {
        id: corruptBackup
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }
    function keepCorrupt(text) {
        const path = `${root.filePath}.corrupt-${Date.now()}`
        corruptBackup.path = ""
        corruptBackup.path = path
        corruptBackup.setText(text)
        console.warn(`[Notes] The notes file was not readable: it is kept as ${path}`)
    }

    // An entry of the file as a note the lists can show (a string id and
    // content); a bare string becomes a note, what is not a note is left out.
    function normalized(n, index) {
        if (typeof n === "string")
            n = { "content": n, "createdAt": 0, "pinned": false }
        if (!n || typeof n !== "object" || Array.isArray(n))
            return null
        if (typeof n.id === "string" && typeof n.content === "string")
            return n
        return Object.assign({}, n, {
            "id": (n.id !== undefined && n.id !== null && n.id !== "") ? String(n.id) : `${Date.now()}-${index}`,
            "content": typeof n.content === "string" ? n.content : String(n.content ?? "")
        })
    }

    FileView {
        id: notesFileView
        path: Qt.resolvedUrl(root.filePath)
        // A change made before the first read waits for it (ensureLoaded).
        blockLoading: true
        onLoaded: {
            const fileContents = notesFileView.text()
            let parsed = null
            try {
                parsed = fileContents.trim() === "" ? [] : JSON.parse(fileContents)
            } catch (e) {
                parsed = null
            }
            if (Array.isArray(parsed)) {
                root.list = parsed.map(root.normalized).filter(n => n !== null)
            } else {
                root.keepCorrupt(fileContents)
                root.list = []
            }
            root.ready = true
            console.log("[Notes] File loaded")
            Qt.callLater(root.migrateScratchpad)
        }
        onLoadFailed: (error) => {
            root.ready = true
            if (error == FileViewError.FileNotFound) {
                console.log("[Notes] File not found, creating new file.")
                root.list = []
                notesFileView.setText(JSON.stringify(root.list))
                Qt.callLater(root.migrateScratchpad)
            } else {
                console.log("[Notes] Error loading file: " + error)
            }
        }
    }

    // `nixbook-shell ipc call notes list|add|update|remove`: the desktop
    // notes widget's notes, for key bindings and the desktop MCP server
    // (its `widget` tool).
    IpcHandler {
        target: "notes"

        function list(): string {
            return JSON.stringify(root.list.map(n => ({ id: n.id, content: n.content, createdAt: n.createdAt })));
        }
        // The Notes app (its launcher entry).
        function launch(): string {
            GlobalStates.openNotesApp("");
            return "ok: opened the Notes app";
        }
        // The Notes app, on that note ("" for none).
        function open(id: string): string {
            if (id && !root.list.some(n => n.id === id))
                return `error: no note "${id}"`;
            GlobalStates.openNotesApp(id);
            return "ok: opened the Notes app";
        }
        function add(content: string): string {
            if (content.length === 0)
                return "error: empty note";
            return `ok: ${root.addNote(content)}`;
        }
        function update(id: string, content: string): string {
            if (!root.list.some(n => n.id === id))
                return `error: no note "${id}"`;
            if (content.length === 0)
                return "error: empty note (remove it instead)";
            root.updateNote(id, content);
            return `ok: ${id}`;
        }
        function addFromFile(path: string): string {
            if (!root.isTransferPath(path))
                return "error: not a transfer file";
            const content = root.readTransfer(path);
            if (content.length === 0)
                return "error: empty note";
            return `ok: ${root.addNote(content)}`;
        }
        function updateFromFile(id: string, path: string): string {
            if (!root.isTransferPath(path))
                return "error: not a transfer file";
            if (!root.list.some(n => n.id === id))
                return `error: no note "${id}"`;
            const content = root.readTransfer(path);
            if (content.length === 0)
                return "error: empty note (remove it instead)";
            root.updateNote(id, content);
            return `ok: ${id}`;
        }
        function listToFile(path: string): string {
            if (!root.isTransferPath(path))
                return "error: not a transfer file";
            transferOut.path = "";
            transferOut.path = path;
            transferOut.setText(JSON.stringify(root.list.map(n => Object.assign({ id: n.id, content: n.content, createdAt: n.createdAt, updatedAt: n.updatedAt ?? n.createdAt, pinned: !!n.pinned }, n.scratchpad ? { scratchpad: true } : {}))));
            return "ok";
        }
        function remove(id: string): string {
            if (!root.list.some(n => n.id === id))
                return `error: no note "${id}"`;
            root.deleteNote(id);
            return `ok: ${id}`;
        }
    }
}
