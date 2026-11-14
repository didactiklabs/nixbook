pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

// Synced lyrics from lrclib, per song. Each Lyrics view asks for the song of
// its own player (need()) and reads that song's entry: several views showing
// different players (the YouTube Music tab, the media popup, the desktop
// widget) no longer share one answer — it used to be one state for the whole
// shell, the song of whichever view asked last, so a view could show another
// player's lyrics, or "No song playing", or nothing. Songs are fetched one at
// a time, the latest asked first, and kept (the last `keep`).
Singleton {
    id: root

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7
    readonly property int keep: 40

    // key → { status: "loading" | "ok" | "not_found", lines: [{time, text}] }
    // A plain object changed in place; `revision` tells the views.
    property var _entries: ({})
    property var _order: [] // keys, oldest first (for trimming)
    property int revision: 0

    // Waiting to be fetched: [{key, title, artist, length}], the next first.
    property var _queue: []
    property var _current: null // the request lyricsProc is running for
    property bool _answered: false

    function keyOf(player) {
        const title = player?.trackTitle ?? ""
        const artist = player?.trackArtist ?? ""
        if (!title || !artist) return ""
        return `${title}\u0001${artist}`
    }

    function entry(key) {
        return key !== "" ? (root._entries[key] ?? null) : null
    }

    // A shown view wants this song's lyrics.
    function need(key, player) {
        if (key === "" || root._entries[key]) return
        root._set(key, { status: "loading", lines: [], retries: 0 })
        root._enqueue(key, player)
    }

    // Fetched again (a click on the spinner, or after "no lyrics").
    function refetch(key, player) {
        if (key === "") return
        if (root._current?.key === key) return
        root._set(key, { status: "loading", lines: [], retries: 0 })
        root._enqueue(key, player)
    }

    // Lines around `idx` for the seven slots of a view.
    function slotsFor(lines, idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            const lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < lines.length)
                result.push(lines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    function lineAt(lines, pos) {
        let idx = -1
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].time <= pos) idx = i
            else break
        }
        return idx
    }

    function _set(key, value) {
        if (!root._entries[key]) root._order.push(key)
        root._entries[key] = value
        while (root._order.length > root.keep) {
            const old = root._order.shift()
            if (root._current?.key !== old) delete root._entries[old]
        }
        root.revision++
    }

    function _enqueue(key, player) {
        const request = {
            key: key,
            title: player?.trackTitle ?? "",
            artist: player?.trackArtist ?? "",
            length: Math.floor(player?.length ?? 0)
        }
        root._queue = [request].concat(root._queue.filter(r => r.key !== key))
        root._next()
    }

    function _next() {
        if (root._current !== null || root._queue.length === 0) return
        const request = root._queue[0]
        root._queue = root._queue.slice(1)
        root._current = request
        root._answered = false
        lyricsProc.exec([
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            request.title, request.artist, String(request.length)
        ])
    }

    function _answer(trimmed) {
        const request = root._current
        if (!request) return
        const old = root._entries[request.key]
        if (!old) return // trimmed meanwhile
        root._answered = true

        if (trimmed === "error") {
            // lrclib couldn't be reached: asked again a little later.
            if ((old.retries ?? 0) < 2) {
                root._entries[request.key] = { status: "loading", lines: [], retries: (old.retries ?? 0) + 1 }
                retryTimer.pending.push(request)
                retryTimer.restart()
            } else {
                root._entries[request.key] = { status: "not_found", lines: [] }
            }
            root.revision++
            return
        }
        if (trimmed === "not_found" || trimmed === "no_info") {
            root._entries[request.key] = { status: "not_found", lines: [] }
            root.revision++
            return
        }

        const parts = trimmed.split("§")
        if (parts.length < 3 || parts[parts.length - 1].trim() !== "ok") {
            root._answered = false
            return
        }
        let lines = []
        for (let i = 0; i < parts.length - 1; i += 2) {
            const t = parseFloat(parts[i])
            if (!isNaN(t)) lines.push({ time: t, text: parts[i + 1] || "" })
        }
        root._entries[request.key] = lines.length > 0
            ? { status: "ok", lines: lines }
            : { status: "not_found", lines: [] }
        root.revision++
    }

    Process {
        id: lyricsProc
        stdout: SplitParser {
            onRead: data => root._answer(data.trim())
        }
        onExited: {
            // Ended without a usable answer (Python failed): not left spinning.
            const request = root._current
            if (request && !root._answered && root._entries[request.key]?.status === "loading") {
                root._entries[request.key] = { status: "not_found", lines: [] }
                root.revision++
            }
            root._current = null
            root._next()
        }
    }

    Timer {
        id: retryTimer
        property var pending: []
        interval: 6000
        onTriggered: {
            const due = pending
            pending = []
            for (const request of due) {
                if (root._entries[request.key]?.status !== "loading") continue
                root._queue = root._queue.filter(r => r.key !== request.key).concat([request])
            }
            root._next()
        }
    }
}
