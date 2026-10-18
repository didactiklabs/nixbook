pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick

/**
 * The user's routines ("whenever the music ends, play something I like":
 * the desktop memory's `routines`, written by the `routine` tool of
 * nixbook-desktop-mcp), watched in plain code: when a routine's cue comes,
 * `nixbook-desktop-mcp routine run ID EVENT` does its action. Off with
 * ai.routines.enable (on by default: routines exist only when the user
 * asked for them).
 *
 * It never fights the user:
 *   - music_ended only for music that ended on its own (the track played to
 *     its end, the queue ran out) and stayed quiet for 45 s: a pause or a
 *     stop mid-track is the user's, and holds music routines for 10 minutes;
 *   - what a routine did and the user undid within 3 minutes (paused the
 *     music it started, closed the app it opened) is told (`routine
 *     undone`): twice, and the routine turns itself off.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.ai?.routines?.enable ?? true
    readonly property string memoryPath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/desktop-memory.json`
    property var routines: []
    readonly property var active: root.routines.filter(r => r.on !== false)

    // routine id -> {time, music: bool, app}: what it just did, to see it undone.
    property var _fired: ({})
    property real _userPausedAt: 0
    property var _timeFired: ({})
    property var _eventsFired: ({})

    function load() {
        memoryFile.reload()
    }

    function _matches(when, ev) {
        const lower = s => String(s ?? "").toLowerCase()
        if (when.app && !lower(ev.app).includes(when.app)) return false
        if (when.words && !lower(ev.text).includes(when.words)) return false
        if (when.name && !lower(ev.name).includes(when.name)) return false
        if (when.ext && lower(ev.ext) !== when.ext.replace(/^\./, "")) return false
        if (when.event === "back" && (ev.away ?? 0) < (when.minutes ?? 30)) return false
        if (when.event === "battery_low") {
            const th = (when.percent ?? 20)
            if (!(ev.prev > th && ev.percent <= th)) return false
        }
        if (when.days?.length) {
            const day = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][new Date().getDay()]
            if (!when.days.includes(day)) return false
        }
        return true
    }

    // Learning routines from the habits (ai.routines.learn: off, suggest,
    // auto): the cues are counted with them, and once a day `routine learn`.
    readonly property string learn: Config.options?.ai?.routines?.learn ?? "off"
    readonly property var cueEvents: ["audio_output", "wifi_connected", "monitor_connected", "plugged", "unplugged", "unlocked"]
    Timer {
        interval: 3600000
        running: root.enabled && root.learn !== "off"
        repeat: true
        triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["nixbook-desktop-mcp", "routine", "learn", root.learn])
    }

    // Something happened: the routines it is the cue of.
    function happen(ev) {
        if (root.enabled && root.learn !== "off" && root.cueEvents.includes(ev.event))
            Quickshell.execDetached(["nixbook-desktop-mcp", "habits", "cue", ev.event, ev.name ?? ""])
        if (!root.enabled || root.active.length === 0) return
        const music = ev.event.startsWith("music") || ev.event === "track_changed"
        // Music the user just stopped stays stopped.
        if (music && ev.event !== "music_ended" && Date.now() - root._userPausedAt < 600000) return
        for (const r of root.active) {
            if (r.when?.event !== ev.event || !root._matches(r.when, ev)) continue
            root._run(r, ev)
        }
    }

    function _touchesMusic(r) {
        const d = r.do ?? {}
        const what = `${r.when?.event ?? ""} ${d.server ?? ""} ${d.tool ?? ""} ${d.agent ?? ""}`.toLowerCase()
        return /music|spotify|play|song|track|playlist/.test(what)
    }

    function _run(r, ev) {
        const event = Object.assign({}, ev)
        if (Ai.claudeCodePath.length > 0) event.claude = Ai.claudeCodePath
        root._fired = Object.assign({}, root._fired, { [r.id]: { time: Date.now(), music: root._touchesMusic(r),
            app: r.do?.tool === "launch_app" ? String(r.do?.args?.app ?? "").toLowerCase() : "" } })
        runner.createObject(root, { command: ["nixbook-desktop-mcp", "routine", "run", r.id, JSON.stringify(event)], running: true })
    }

    // The user undid what a routine just did (within 3 minutes).
    function _undone(test) {
        const now = Date.now()
        for (const id in root._fired) {
            const f = root._fired[id]
            if (now - f.time < 180000 && test(f)) {
                const rest = Object.assign({}, root._fired)
                delete rest[id]
                root._fired = rest
                Quickshell.execDetached(["nixbook-desktop-mcp", "routine", "undone", id])
            }
        }
    }

    Component {
        id: runner
        Process {
            id: proc
            onExited: proc.destroy()
        }
    }

    FileView {
        id: memoryFile
        path: root.memoryPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(memoryFile.text())
                root.routines = Array.isArray(data.routines) ? data.routines : []
            } catch (e) {
                root.routines = []
            }
        }
    }

    // -- music: ended on its own, or stopped by the user --------------------
    readonly property bool anyPlaying: Mpris.players.values.some(p => p.isPlaying)
    property bool _wasPlaying: false
    onAnyPlayingChanged: {
        if (root.anyPlaying) {
            quietTimer.stop()
            if (!root._wasPlaying) root.happen({ event: "music_started", app: MprisController.activePlayer?.identity ?? "",
                                                 text: `${MprisController.activeTrack?.artist ?? ""} ${MprisController.activeTrack?.title ?? ""}` })
        }
        root._wasPlaying = root.anyPlaying
    }
    Variants {
        model: Mpris.players.values
        delegate: QtObject {
            id: watched
            required property MprisPlayer modelData
            // Where the track was, read while it plays (a stop resets it).
            property real lastPos: 0
            property real lastLen: 0
            property bool playing: watched.modelData?.isPlaying ?? false
            onPlayingChanged: {
                if (watched.playing) return
                const len = watched.modelData?.length ?? watched.lastLen
                const pos = Math.max(watched.modelData?.position ?? 0, watched.lastPos)
                // At its end (or a queue that ran out): on its own; else the user.
                const ended = len > 0 ? pos >= len - 20 : watched.modelData?.playbackState === MprisPlaybackState.Stopped
                if (ended) {
                    if (!root.anyPlaying) quietTimer.restart()
                } else {
                    root._userPausedAt = Date.now()
                    root._undone(f => f.music)
                }
            }
            property Timer sampler: Timer {
                interval: 5000
                repeat: true
                running: watched.playing && root.active.length > 0
                onTriggered: {
                    watched.lastPos = watched.modelData?.position ?? watched.lastPos
                    watched.lastLen = watched.modelData?.length ?? watched.lastLen
                }
            }
        }
    }
    Timer {
        id: quietTimer
        interval: 45000
        onTriggered: if (!root.anyPlaying) root.happen({ event: "music_ended", app: MprisController.activePlayer?.identity ?? "",
                                                         text: `${MprisController.activeTrack?.artist ?? ""} ${MprisController.activeTrack?.title ?? ""}` })
    }
    Connections {
        target: MprisController
        function onTrackChanged() {
            if (!root.anyPlaying) return
            root.happen({ event: "track_changed", app: MprisController.activePlayer?.identity ?? "",
                          text: `${MprisController.activeTrack?.artist ?? ""} ${MprisController.activeTrack?.title ?? ""}` })
        }
    }

    // -- apps and windows ---------------------------------------------------
    property var _apps: []
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            const now = [...new Set(ToplevelManager.toplevels.values.map(t => (t.appId ?? "").toLowerCase()).filter(a => a))]
            for (const a of now.filter(a => !root._apps.includes(a))) root.happen({ event: "app_opened", app: a })
            for (const a of root._apps.filter(a => !now.includes(a))) {
                root.happen({ event: "app_closed", app: a })
                root._undone(f => f.app && a.includes(f.app))
            }
            root._apps = now
        }
    }
    Connections {
        target: ToplevelManager.activeToplevel
        ignoreUnknownSignals: true
        function onTitleChanged() {
            root.happen({ event: "window_title", app: ToplevelManager.activeToplevel?.appId ?? "",
                          text: ToplevelManager.activeToplevel?.title ?? "" })
        }
    }

    // -- notifications, coming back, the lock --------------------------------
    Connections {
        target: Notifications
        function onNotify(n) {
            root.happen({ event: "notification", app: n.appName, text: `${n.summary} ${n.body}` })
        }
    }
    property real _awaySince: 0
    Connections {
        target: Idle
        function onScreensOffChanged() {
            if (Idle.screensOff) root._awaySince = Date.now()
            else if (root._awaySince > 0 && !GlobalStates.screenLocked) {
                root.happen({ event: "back", away: Math.round((Date.now() - root._awaySince) / 60000) })
                root._awaySince = 0
            }
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                root.happen({ event: "locked" })
                if (root._awaySince === 0) root._awaySince = Date.now()
            } else {
                root.happen({ event: "unlocked" })
                if (root._awaySince > 0) {
                    root.happen({ event: "back", away: Math.round((Date.now() - root._awaySince) / 60000) })
                    root._awaySince = 0
                }
            }
        }
    }

    // -- power, network, audio, monitors -------------------------------------
    property real _lastPercent: 100
    property string _network: ""
    Component.onCompleted: {
        root._lastPercent = Math.round(Battery.percentage * 100)
        root._network = Network.networkName
    }
    Connections {
        target: Battery
        function onPercentageChanged() {
            const now = Math.round(Battery.percentage * 100)
            if (!Battery.isPluggedIn) root.happen({ event: "battery_low", percent: now, prev: root._lastPercent })
            root._lastPercent = now
        }
        function onIsPluggedInChanged() {
            root.happen({ event: Battery.isPluggedIn ? "plugged" : "unplugged" })
        }
    }
    Connections {
        target: Network
        function onNetworkNameChanged() {
            if (Network.networkName && Network.networkName !== root._network)
                root.happen({ event: "wifi_connected", name: Network.networkName })
            else if (!Network.networkName && root._network)
                root.happen({ event: "wifi_disconnected", name: root._network })
            root._network = Network.networkName
        }
    }
    readonly property bool vpnUp: VpnState.tsConnected || VpnState.nbConnected
    onVpnUpChanged: root.happen({ event: root.vpnUp ? "vpn_connected" : "vpn_disconnected" })
    readonly property string audioOutput: Audio.sink?.description || Audio.sink?.nickname || Audio.sink?.name || ""
    onAudioOutputChanged: if (root.audioOutput) root.happen({ event: "audio_output", name: root.audioOutput })
    property var _monitors: []
    readonly property var monitorNames: WM.monitors.map(m => m.name)
    onMonitorNamesChanged: {
        for (const m of root.monitorNames.filter(m => !root._monitors.includes(m)))
            if (root._monitors.length > 0) root.happen({ event: "monitor_connected", name: m })
        for (const m of root._monitors.filter(m => !root.monitorNames.includes(m)))
            root.happen({ event: "monitor_disconnected", name: m })
        root._monitors = root.monitorNames
    }

    // -- Downloads ------------------------------------------------------------
    property var _downloads: null
    FolderListModel {
        id: downloads
        folder: `file://${Quickshell.env("XDG_DOWNLOAD_DIR") || `${Quickshell.env("HOME")}/Downloads`}`
        showDirs: false
        showHidden: false
        onCountChanged: downloadTimer.restart()
    }
    // A finished file only: partial ones are renamed when done.
    Timer {
        id: downloadTimer
        interval: 2000
        onTriggered: {
            const names = []
            for (let i = 0; i < downloads.count; i++) names.push(downloads.get(i, "fileName"))
            if (root._downloads !== null)
                for (const n of names.filter(n => !root._downloads.includes(n) && !/\.(part|crdownload|tmp|download)$/i.test(n)))
                    root.happen({ event: "download", name: n, ext: (n.match(/\.([^.]+)$/)?.[1] ?? "").toLowerCase() })
            root._downloads = names
        }
    }

    // -- times and calendar events --------------------------------------------
    Timer {
        interval: 30000
        repeat: true
        running: root.enabled && root.active.some(r => r.when?.event === "time" || r.when?.event === "calendar_event")
        onTriggered: {
            const now = new Date()
            const hm = Qt.formatTime(now, "hh:mm")
            const day = now.toDateString()
            for (const r of root.active) {
                if (r.when?.event === "time" && r.when.at === hm && root._timeFired[r.id] !== day && root._matches(r.when, {})) {
                    root._timeFired = Object.assign({}, root._timeFired, { [r.id]: day })
                    root._run(r, { event: "time", at: hm })
                }
                if (r.when?.event !== "calendar_event") continue
                for (const e of CalendarEvents.upcoming(6, now, true)) {
                    const inMin = (e.start - now) / 60000
                    const key = `${r.id}@${e.id}@${e.start.getTime()}`
                    if (Math.abs(inMin - (r.when.minutes ?? 0)) <= 0.5 && !root._eventsFired[key]
                        && root._matches(r.when, { text: e.summary })) {
                        root._eventsFired = Object.assign({}, root._eventsFired, { [key]: true })
                        root._run(r, { event: "calendar_event", text: e.summary, inMinutes: Math.round(inMin) })
                    }
                }
            }
        }
    }
}
