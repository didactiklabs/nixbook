pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Bluetooth
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

    // routine id -> {time, music: bool, app}: what it just did, to see it undone
    // (set once its run is over, and for the music only when the music changed).
    property var _fired: ({})
    // Routine runs going on: a pause then is theirs (switching tracks), not the user's.
    property int _running: 0
    property real _userPausedAt: 0
    property var _timeFired: ({})
    property var _eventsFired: ({})

    function load() {
        memoryFile.reload()
    }

    function _has(event) {
        return root.active.some(r => r.when?.event === event)
    }

    function _matches(when, ev) {
        const lower = s => String(s ?? "").toLowerCase()
        if (when.app && !lower(ev.app).includes(when.app)) return false
        if (when.words && !lower(ev.text).includes(when.words)) return false
        if (when.name && !lower(ev.name).includes(when.name)) return false
        if (when.ext && lower(ev.ext) !== when.ext.replace(/^\./, "")) return false
        if (when.event === "back" && (ev.away ?? 0) < (when.minutes ?? 30)) return false
        if (when.event === "music_silent" && (ev.minutes ?? 0) < (when.minutes ?? 2)) return false
        if (when.event === "music_repeating" && (ev.times ?? 0) < (when.times ?? 3) && (ev.minutes ?? 0) < (when.minutes ?? 30)) return false
        if (when.event === "charged" && (ev.percent ?? 0) !== (when.percent ?? 100)) return false
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

    // What it saw lately and what came of it (Settings > Routines): newest last.
    property var recent: []
    function note(what, outcome) {
        root.recent = [...root.recent, { time: Date.now(), what: what, outcome: outcome }].slice(-12)
    }

    // Something happened: the routines it is the cue of.
    function happen(ev) {
        if (ev.event === "back") {
            root._sittingSince = Date.now()
            root._longFired = []
            root._userPausedAt = 0
            root._silentSince = root.anyPlaying ? 0 : Date.now()
            root._silentFired = []
        }
        if (root.enabled && root.learn !== "off" && root.cueEvents.includes(ev.event))
            Quickshell.execDetached(["nixbook-desktop-mcp", "habits", "cue", ev.event, ev.name ?? ""])
        if (!root.enabled || root.active.length === 0) return
        const music = ev.event.startsWith("music") || ev.event === "track_changed"
        // Music the user just stopped stays stopped.
        if (music && ev.event !== "music_ended" && Date.now() - root._userPausedAt < 600000) {
            if (root._has(ev.event)) root.note(ev.event, Translation.tr("held: you stopped the music lately"))
            return
        }
        for (const r of root.active) {
            if (r.when?.event !== ev.event || !root._matches(r.when, ev)) continue
            root._run(r, ev)
        }
    }

    function _outcome(r, text, before) {
        root._running = Math.max(0, root._running - 1)
        try {
            const out = JSON.parse(text)
            const music = root._touchesMusic(r)
            // A run that left the music as it was did nothing to undo.
            if (out.ran && (!music || root._musicNow() !== before))
                root._fired = Object.assign({}, root._fired, { [r.id]: { time: Date.now(), music: music,
                    app: r.do?.tool === "launch_app" ? String(r.do?.args?.app ?? "").toLowerCase() : "" } })
            const said = out.said && !out.said.endsWith(": done.") ? out.said : ""
            root.note(r.text, out.ran ? (said ? Translation.tr("ran: %1").arg(said) : Translation.tr("ran")) : out.why)
        } catch (e) {
            root.note(r.text, Translation.tr("didn't run"))
        }
    }

    function _musicNow() {
        return `${root.anyPlaying} ${MprisController.activeTrack?.artist ?? ""} ${MprisController.activeTrack?.title ?? ""}`
    }

    function _touchesMusic(r) {
        const d = r.do ?? {}
        const what = `${r.when?.event ?? ""} ${d.server ?? ""} ${d.tool ?? ""} ${d.agent ?? ""}`.toLowerCase()
        return /music|spotify|play|song|track|playlist/.test(what)
    }

    function _run(r, ev) {
        const event = Object.assign({}, ev)
        if (Ai.claudeCodePath.length > 0) event.claude = Ai.claudeCodePath
        root._running += 1
        runner.createObject(root, { routine: r, before: root._musicNow(), command: ["nixbook-desktop-mcp", "routine", "run", r.id, JSON.stringify(event)], running: true })
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
            property var routine
            property string before
            stdout: StdioCollector {
                onStreamFinished: {
                    root._outcome(proc.routine, text, proc.before)
                    proc.destroy()
                }
            }
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
        // Silence counted from when the music stops (music_silent).
        root._silentSince = root.anyPlaying ? 0 : Date.now()
        root._silentFired = []
        if (root.anyPlaying) {
            root._userPausedAt = 0
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
            // The track as it was last seen playing (sampled: when it stops,
            // the position may be reset, the length the next track's or gone).
            property real lastPos: 0
            property real lastLen: 0
            property string lastTrack: ""
            readonly property string track: `${watched.modelData?.trackArtist ?? ""} ${watched.modelData?.trackTitle ?? ""}`
            property bool playing: watched.modelData?.isPlaying ?? false
            function sample() {
                if (watched.playing && watched.track.trim() !== "")
                    root._heard(watched.track, watched.modelData?.trackArtist ?? "", watched.modelData?.identity ?? "",
                                watched.lastTrack, watched.lastPos, watched.modelData?.position ?? 0, watched.lastLen)
                watched.lastPos = watched.modelData?.position ?? 0
                watched.lastLen = watched.modelData?.length ?? 0
                watched.lastTrack = watched.track
            }
            onPlayingChanged: {
                if (watched.playing) {
                    watched.sample()
                    return
                }
                const name = watched.modelData?.identity ?? ""
                // On its own: it was a few seconds from the end, or the player
                // moved on to the next track and stopped there (the queue ran
                // out), or it stopped with no position to tell. Else the user.
                const nearEnd = watched.lastLen > 0 && watched.lastLen - watched.lastPos <= 8
                const movedOn = watched.lastTrack !== "" && watched.track !== watched.lastTrack
                const unknown = watched.lastLen <= 0 && watched.modelData?.playbackState === MprisPlaybackState.Stopped
                if (nearEnd || movedOn || unknown) {
                    // `anyPlaying` still counts this player here (it updates
                    // after): the timer checks for other music when it runs out.
                    root.note("music", `${name}: ended on its own, waiting 20 s`)
                    quietTimer.restart()
                } else if (root._running > 0) {
                    root.note("music", `${name}: paused while a routine ran (not counted as yours)`)
                } else {
                    root._userPausedAt = Date.now()
                    root.note("music", `${name}: paused by you (holding music routines until you play music or come back)`)
                    root._undone(f => f.music)
                }
            }
            // Every 2 s while it plays: the end is seen within a few seconds.
            property Timer sampler: Timer {
                interval: 2000
                repeat: true
                running: watched.playing && root.active.length > 0
                onTriggered: watched.sample()
            }
        }
    }
    // The same song on and on (music_repeating): its plays in a row, a loop
    // seen as the position jumping back to the start, and how long the same
    // artist has played (a track with no artist, a browser's video, counts no
    // minutes). Once per streak and routine: again for another song in a row,
    // not for the same artist's next track. A stop of 5 minutes or more ends
    // the streak: an artist played this morning and again now isn't on repeat.
    property string _repeatTrack: ""
    property int _repeatTimes: 0
    property string _repeatArtist: ""
    property real _artistSecs: 0
    property real _heardAt: 0
    property var _repeatFired: []
    property var _artistFired: []
    function _heard(track, artist, app, lastTrack, lastPos, pos, lastLen) {
        const now = Date.now()
        if (root._heardAt > 0 && now - root._heardAt > 300000) {
            root._repeatTrack = ""
            root._repeatArtist = ""
        }
        const secs = root._heardAt > 0 ? Math.min(10, (now - root._heardAt) / 1000) : 0
        root._heardAt = now
        if (track !== root._repeatTrack) {
            root._repeatTrack = track
            root._repeatTimes = 1
            root._repeatFired = []
        } else if (track === lastTrack && lastLen > 0 && lastPos > lastLen * 0.6 && pos < 15) {
            root._repeatTimes += 1
        }
        if (artist !== root._repeatArtist) {
            root._repeatArtist = artist
            root._artistSecs = 0
            root._artistFired = []
        }
        if (artist.trim() !== "") root._artistSecs += secs
        if (!root._has("music_repeating")) return
        const minutes = Math.floor(root._artistSecs / 60)
        for (const r of root.active.filter(r => r.when?.event === "music_repeating")) {
            const fresh = (root._repeatTimes >= (r.when.times ?? 3) && !root._repeatFired.includes(r.id))
                || (minutes >= (r.when.minutes ?? 30) && !root._artistFired.includes(r.id))
            if (!fresh) continue
            const ev = { event: "music_repeating", app: app, text: track, times: root._repeatTimes, minutes: minutes }
            if (!root._matches(r.when, ev)) continue
            root._repeatFired = [...root._repeatFired, r.id]
            root._artistFired = [...root._artistFired, r.id]
            root.note("music", Translation.tr("on repeat: %1 times, %2 min of the artist").arg(root._repeatTimes).arg(minutes))
            root._run(r, ev)
        }
    }

    // No music for a while, while the user is here (music_silent: "whenever
    // there's no music…"): from the shell's start, a stop, coming back. Once
    // per silence and routine; held while the user stopped it themselves,
    // until music plays again, they come back from a break, or an hour.
    property real _silentSince: Date.now()
    property var _silentFired: []
    Timer {
        interval: 20000
        repeat: true
        running: root.enabled && root._has("music_silent")
        onTriggered: {
            if (root.anyPlaying || root._silentSince === 0 || GlobalStates.screenLocked || Idle.screensOff) return
            const minutes = Math.floor((Date.now() - root._silentSince) / 60000)
            if (root._userPausedAt > 0 && Date.now() - root._userPausedAt < 3600000) return
            for (const r of root.active.filter(r => r.when?.event === "music_silent")) {
                if (root._silentFired.includes(r.id) || minutes < (r.when.minutes ?? 2)) continue
                root._silentFired = [...root._silentFired, r.id]
                root.note("music", Translation.tr("no music for %1 min").arg(minutes))
                root._run(r, { event: "music_silent", minutes: minutes })
            }
        }
    }
    // An app comes to the front (app_focused), the same one once in a row.
    property string _focusedApp: ""
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const app = (ToplevelManager.activeToplevel?.appId ?? "").toLowerCase()
            if (!app || app === root._focusedApp) return
            root._focusedApp = app
            focusSettle.restart()
        }
    }
    Timer {
        id: focusSettle
        interval: 1500
        onTriggered: if (root._has("app_focused")) root.happen({ event: "app_focused", app: root._focusedApp })
    }
    Timer {
        id: quietTimer
        interval: 20000
        onTriggered: {
            if (root.anyPlaying) {
                root.note("music", Translation.tr("other music plays: nothing to do"))
                return
            }
            if (!root._has("music_ended")) root.note("music", Translation.tr("quiet for 20 s, no routine for it"))
            root.happen({ event: "music_ended", app: MprisController.activePlayer?.identity ?? "",
                          text: `${MprisController.activeTrack?.artist ?? ""} ${MprisController.activeTrack?.title ?? ""}` })
        }
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

    // -- the day, the sitting -------------------------------------------------
    // day_start: the first time at the computer today (here at start, back,
    // unlocked; nixbook-desktop-mcp runs such a routine once a day). away:
    // the screens go off. long_session: at it `minutes` (90) without a break,
    // once a sitting.
    property real _sittingSince: Date.now()
    property var _longFired: []
    Timer {
        interval: 20000
        running: root.enabled
        onTriggered: root.happen({ event: "day_start" })
    }
    Connections {
        target: Idle
        function onScreensOffChanged() {
            if (Idle.screensOff) root.happen({ event: "away" })
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.enabled && root._has("long_session")
        onTriggered: {
            if (GlobalStates.screenLocked || Idle.screensOff) return
            const minutes = Math.floor((Date.now() - root._sittingSince) / 60000)
            for (const r of root.active.filter(r => r.when?.event === "long_session")) {
                if (root._longFired.includes(r.id) || minutes < (r.when.minutes ?? 90)) continue
                root._longFired = [...root._longFired, r.id]
                root._run(r, { event: "long_session", minutes: minutes })
            }
        }
    }

    // -- modes: fullscreen, Do Not Disturb ----------------------------------------
    readonly property bool _fullscreen: WM.fullscreenOnMonitor(WM.focusedMonitor?.name ?? "")
    on_FullscreenChanged: root.happen({ event: root._fullscreen ? "fullscreen_started" : "fullscreen_ended",
                                        app: ToplevelManager.activeToplevel?.appId ?? "" })
    Connections {
        target: Notifications
        function onSilentChanged() {
            root.happen({ event: Notifications.silent ? "dnd_on" : "dnd_off" })
        }
    }

    // -- devices: charge, Bluetooth, the phone, drives ----------------------------
    Connections {
        target: Battery
        function onPercentageChanged() {
            if (Battery.isCharging) root.happen({ event: "charged", percent: Math.round(Battery.percentage * 100) })
        }
    }
    property var _bluetooth: null
    readonly property var _bluetoothNow: Bluetooth.devices.values.filter(d => d.connected).map(d => d.name ?? "")
    on_BluetoothNowChanged: {
        const now = root._bluetoothNow
        if (root._bluetooth !== null) {
            for (const n of now.filter(n => !root._bluetooth.includes(n))) root.happen({ event: "bluetooth_connected", name: n })
            for (const n of root._bluetooth.filter(n => !now.includes(n))) root.happen({ event: "bluetooth_disconnected", name: n })
        }
        root._bluetooth = now
    }
    property var _phones: null
    readonly property var _phonesNow: KdeConnect.reachableDevices.map(d => d.name ?? "")
    on_PhonesNowChanged: {
        const now = root._phonesNow
        if (root._phones !== null) {
            for (const n of now.filter(n => !root._phones.includes(n))) root.happen({ event: "phone_connected", name: n })
            for (const n of root._phones.filter(n => !now.includes(n))) root.happen({ event: "phone_disconnected", name: n })
        }
        root._phones = now
    }
    property var _drives: null
    FolderListModel {
        id: drives
        folder: `file:///run/media/${Quickshell.env("USER")}`
        showFiles: false
        onCountChanged: drivesTimer.restart()
    }
    Timer {
        id: drivesTimer
        interval: 2000
        onTriggered: {
            const now = []
            for (let i = 0; i < drives.count; i++) now.push(drives.get(i, "fileName"))
            if (root._drives !== null) {
                for (const n of now.filter(n => !root._drives.includes(n))) root.happen({ event: "drive_connected", name: n })
                for (const n of root._drives.filter(n => !now.includes(n))) root.happen({ event: "drive_disconnected", name: n })
            }
            root._drives = now
        }
    }

    // -- the disk, the weather, screenshots -------------------------------------
    property bool _diskWasLow: false
    Connections {
        target: ResourceUsage
        function onDiskUsedPercentageChanged() {
            const used = Math.round(ResourceUsage.diskUsedPercentage * 100)
            const low = root.active.some(r => r.when?.event === "disk_low" && used >= (r.when.percent ?? 90))
            if (low && !root._diskWasLow) root.happen({ event: "disk_low", percent: used })
            root._diskWasLow = low
        }
    }
    // OpenWeather condition ids: 2xx storms, 3xx drizzle, 5xx rain, 6xx snow.
    readonly property bool _raining: (Weather.data?.wCode ?? 0) >= 200 && (Weather.data?.wCode ?? 0) < 700
    on_RainingChanged: if (root._raining) root.happen({ event: "rain", text: Weather.data?.description ?? "" })
    property var _shots: null
    FolderListModel {
        id: shots
        folder: `file://${FileUtils.expandHome(Config.options?.screenSnip?.savePath || "~/Pictures/Screenshots")}`
        showDirs: false
        onCountChanged: shotsTimer.restart()
    }
    Timer {
        id: shotsTimer
        interval: 1500
        onTriggered: {
            const now = []
            for (let i = 0; i < shots.count; i++) now.push(shots.get(i, "fileName"))
            if (root._shots !== null)
                for (const n of now.filter(n => !root._shots.includes(n))) root.happen({ event: "screenshot", name: n })
            root._shots = now
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
