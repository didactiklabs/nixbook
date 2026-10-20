pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []

    // Prepared for fuzzy search the first time a search needs them, not on
    // every clipboard change (a binding re-prepared the whole history each
    // copy, launcher open or not). Kept in a plain object: written from
    // inside the launcher's results binding, a property would notify it.
    property int _entriesGeneration: 0
    onEntriesChanged: root._entriesGeneration++
    readonly property var _prepared: ({ generation: -1, entries: [] })
    function preparedEntries() {
        const generation = root._entriesGeneration;
        if (root._prepared.generation !== generation) {
            root._prepared.entries = root.entries.map(a => ({
                name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
                entry: a
            }));
            root._prepared.generation = generation;
        }
        return root._prepared.entries;
    }

    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results.map(item => item.entry)
        }

        return Fuzzy.go(search, root.preparedEntries(), {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        // While a run is in flight this queues one more (Process restarts it).
        readProc.running = true
    }

    // Entries go to the commands as arguments: as printf's format string a
    // `%` or `\` in the copied text broke the decode.
    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '%s' "$1" | ${root.cliphistBinary} decode | wl-copy`, "_", entry]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode "$1" | wl-copy`, "_", entryNumber]);
        }
    }

    function paste(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '%s' "$1" | ${root.cliphistBinary} decode | wl-copy && wl-paste`, "_", entry]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode "$1" | wl-copy; ${root.pressPasteCommand}`, "_", entryNumber]);
        }
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        // Act: oldest first, stopping at the first failure
        Quickshell.execDetached(["bash", "-c", `first=1; for e in "$@"; do `
            + `[ "$first" = 1 ] || sleep ${root.pasteDelay}; first=0; `
            + `printf '%s' "$e" | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand} || exit 1; done`,
            "_", ...[...targetEntries].reverse()]);
    }

    // Deletes requested while one runs are queued and sent together (cliphist
    // deletes every line it reads): the old single `entry` property was
    // cleared right after starting, so a second delete ran with nothing.
    Process {
        id: deleteProc
        property list<string> queue: []
        function deleteEntry(entry) {
            deleteProc.queue = [...deleteProc.queue, entry];
            if (!deleteProc.running) deleteProc.startNext();
        }
        function startNext() {
            const entries = deleteProc.queue;
            deleteProc.queue = [];
            deleteProc.exec(["bash", "-c", `printf '%s\\n' "$@" | ${root.cliphistBinary} delete`, "_", ...entries]);
        }
        onExited: (exitCode, exitStatus) => {
            if (deleteProc.queue.length > 0) deleteProc.startNext();
            else root.refresh();
        }
    }

    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: ["bash", "-c", `${root.cliphistBinary} wipe; rm -rf ~/.cache/cliphist/db`]
        onExited: (exitCode, exitStatus) => {
            root.entries = [];
            root.refresh();
        }
    }

    function wipe() {
        root.entries = [];
        wipeProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc

        command: [root.cliphistBinary, "list"]

        // The whole list at once: pushing each line onto a list property
        // rewrote it per line (O(n²)), and refresh() resetting it mid-run
        // duplicated the history.
        stdout: StdioCollector {
            id: readCollector
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                const text = readCollector.text;
                root.entries = text.length > 0 ? text.replace(/\n$/, "").split("\n") : []
            } else {
                root.entries = []
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}