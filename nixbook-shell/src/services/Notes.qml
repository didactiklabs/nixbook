pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple notes manager.
 * Each item is an object with "id", "content", "attachments" (array of file paths), "createdAt".
 */
Singleton {
    id: root

    function load() {}
    property var filePath: Directories.desktopNotesPath ?? (Directories.config + "/notes.json")
    property var list: []

    function addNote(content, attachments) {
        const item = {
            "id": Date.now().toString() + "-" + Math.floor(Math.random() * 10000),
            "content": content ?? "",
            "attachments": attachments ?? [],
            "createdAt": Date.now()
        }
        list.push(item)
        root.list = list.slice(0)
        notesFileView.setText(JSON.stringify(root.list))
        return item.id
    }

    function updateNote(id, content, attachments) {
        const idx = list.findIndex(n => n.id === id)
        if (idx >= 0) {
            list[idx].content = content
            if (attachments !== undefined)
                list[idx].attachments = attachments
            root.list = list.slice(0)
            notesFileView.setText(JSON.stringify(root.list))
        }
    }

    function deleteNote(id) {
        const idx = list.findIndex(n => n.id === id)
        if (idx >= 0) {
            list.splice(idx, 1)
            root.list = list.slice(0)
            notesFileView.setText(JSON.stringify(root.list))
        }
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

    FileView {
        id: notesFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = notesFileView.text()
            try {
                const parsed = JSON.parse(fileContents)
                root.list = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                console.log("[Notes] Corrupt or empty file, resetting to empty list. Error: " + e)
                root.list = []
                notesFileView.setText(JSON.stringify(root.list))
            }
            console.log("[Notes] File loaded")
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Notes] File not found, creating new file.")
                root.list = []
                notesFileView.setText(JSON.stringify(root.list))
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
            transferOut.setText(JSON.stringify(root.list.map(n => ({ id: n.id, content: n.content, createdAt: n.createdAt }))));
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
