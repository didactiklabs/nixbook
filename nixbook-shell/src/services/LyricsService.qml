pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // The player whose lyrics are shown: the one the last shown Lyrics view
    // asked for (the YouTube Music tab shows its own player's song, whatever
    // the shell's current player is), else the shell's current player.
    property var _requests: [] // [{view, player}], the latest last
    readonly property MprisPlayer activePlayer: root._requests.length > 0
        ? (root._requests[root._requests.length - 1].player ?? MprisController.activePlayer)
        : MprisController.activePlayer

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "loading"
    property var slots: ["", "", "", "", "", "", ""]

    // Shown Lyrics views (Lyrics.qml asks with want() and lets go with
    // release()): fetched and synced only for them, a track change marking
    // the lyrics stale otherwise (lyrics are off by default, and each fetch
    // is a Python + lrclib call).
    readonly property bool wanted: root._requests.length > 0
    function want(view, player) {
        root._requests = root._requests.filter(r => r.view !== view).concat([{ view: view, player: player ?? null }])
    }
    function release(view) {
        root._requests = root._requests.filter(r => r.view !== view)
    }
    property bool _stale: true
    onWantedChanged: if (root.wanted && root._stale) root.restartLyrics()

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    // The line follows the song to a tenth of a second (300 ms let a line
    // come up to a third of a second late); it runs only while lyrics are
    // shown, and each tick is a scan of a few dozen times.
    Timer {
        id: syncTimer
        interval: 100
        repeat: true
        running: root.wanted && root.status === "ok" && root.lyricsLines.length > 0 && !Idle.screensOff
        onTriggered: {
            const pos = root.activePlayer?.position ?? 0
            let idx = -1
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i
                else break
            }
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
        }
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info")   { root.status = "no_info";   return }
                // lrclib couldn't be reached: asked again a little later
                // (it used to say "no lyrics" until the next song).
                if (trimmed === "error") {
                    if (root._retries < 2) { root._retries++; retryTimer.restart() }
                    else root.status = "not_found"
                    return
                }

                const parts = trimmed.split("§")
                if (parts.length < 3) return
                if (parts[parts.length - 1].trim() !== "ok") return

                let lines = []
                for (let i = 0; i < parts.length - 1; i += 2) {
                    const t = parseFloat(parts[i])
                    const txt = parts[i + 1] || ""
                    if (!isNaN(t)) lines.push({ time: t, text: txt })
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                root.lyricsLines = lines
                root.activeIndex = -1
                root.slots = root.buildSlots(-1)
                root.status = "ok"
            }
        }
    }

    property int _retries: 0
    Timer {
        id: retryTimer
        interval: 6000
        onTriggered: if (root.wanted && root.status === "loading") root._fetch()
    }

    function restartLyrics() {
        root._retries = 0
        retryTimer.stop()
        root._stale = false
        lyricsProc.running = false
        root.lyricsLines = []
        root.activeIndex = -1
        root.slots = ["", "", "", "", "", "", ""]
        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0

        if (!title || !artist) { root.status = "no_info"; return }
        root._fetch()
    }
    function _fetch() {
        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0
        if (!title || !artist) { root.status = "no_info"; return }
        lyricsProc.exec([
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration))
        ])
    }

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() {
            if (root.wanted) root.restartLyrics()
            else root._stale = true
        }
    }
    // Re-evaluated on every want()/release(): only a different player counts.
    property MprisPlayer _lastPlayer: null
    onActivePlayerChanged: {
        if (root.activePlayer === root._lastPlayer) return
        root._lastPlayer = root.activePlayer
        if (root.wanted) root.restartLyrics()
        else root._stale = true
    }
}