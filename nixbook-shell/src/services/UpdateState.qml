pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * NixOS update state — port of the DMS nixos-update plugin singleton
 * (assets/dms/plugins/nixos-update/UpdateState.qml) to nixbook-shell.
 *
 * Nothing runs in the shell: it only starts the work and watches two small
 * files, so a slow network, a big changelog or a long colmena log can't
 * freeze it, and a shell restarted by the switch picks the state up again.
 *   - The check: `nixbook-update-check` (scripts/update-check.sh) in its own
 *     user unit (systemd-run), comparing the deployed revision
 *     (/etc/nixos/version) with the remote repository (updates.repoUrl; off
 *     while empty), with the changelog from the GitHub API; its answer in
 *     $XDG_STATE_HOME/nixbook-shell/update-check.json.
 *   - The update: the nixos-upgrade-manual systemd oneshot (osupdate,
 *     nixosModules/tools.nix), which writes /run/nixos-upgrade/status.json
 *     (running with its latest log line, then the outcome and the log's
 *     last lines). The whole log opens in a terminal (openLogs).
 * Used by the bar widget (modules/ii/bar/UpdatesCount.qml) and the Services
 * settings page.
 *
 * Automatic updates (updates.auto.enable, off by default): an available
 * update starts on its own once nothing holds it (autoWaiting says what
 * does): main's build of it done for this machine and pushed to the cache
 * (`ci` from the check, so it downloads instead of building, and never a
 * revision whose build failed; when GitHub can't tell, an hour after the
 * revision was first seen), on the charger (or a battery over half full
 * with updates.auto.onBattery), no fullscreen window (a game, a film), no
 * meeting, a system deployed from main without local changes, and not a
 * revision whose update already failed. The shell restarts in the
 * background during it (Preloader.quietStart). A notification when it
 * starts and when it ends.
 *
 * Replaces upstream services/Updates.qml, which relied on a distro package
 * manager and was inert on NixOS.
 */
Singleton {
    id: root

    property string localRev: "Unknown"
    // Deployed from a tree with uncommitted changes: localRev is the commit
    // they were made on (older builds wrote an all-zero rev instead).
    property bool localDirty: false
    property string localBranch: "Unknown"
    property string remoteRev: "Unknown"
    property bool updateAvailable: false
    property string repoUrl: Config.options.updates.repoUrl
    property string changelogText: ""
    property bool updating: false
    property bool checking: false
    // When the last check ended ("" before the first), and why it failed
    // ("" when it worked): a check that finds nothing new still shows it ran.
    property string lastCheckTime: ""
    property string checkError: ""
    // The running update's latest log line.
    property string step: ""
    // The last nixos-upgrade-manual run: "success", "failed" or "" (never
    // ran this boot), when it ended, and the end of its log.
    property string lastResult: ""
    property string lastRunTime: ""
    property string lastRunLog: ""
    // Main's build of remoteRev: "passed", "pending", "failed" or "" (unknown).
    property string ci: ""

    readonly property bool autoEnabled: Config.options.updates.auto.enable
    // Why an available update isn't installed on its own yet ("" when nothing
    // holds it, or automatic updates are off / nothing to install).
    property string autoWaiting: ""

    readonly property string checkPath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/update-check.json`
    // NIXBOOK_UPGRADE_STATUS: another file, for tests.
    readonly property string statusPath: Quickshell.env("NIXBOOK_UPGRADE_STATUS") || "/run/nixos-upgrade/status.json"

    property bool started: false

    // Called from shell.qml on startup; safe to call repeatedly and before
    // Config has finished loading (start() is gated on Config.ready).
    function load() {
        root.start()
    }

    function start() {
        if (root.started || !Config.ready) return
        root.started = true
        root.checkFile.reload()
        root.statusFile.reload()
        root.checkUpdate()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root.start()
        }
    }
    // The automatic run's result and its state are kept there.
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.ready || !root.started) return
            root.statusFile.reload()
            root.considerAuto()
        }
    }

    // Returns whether a check started (false: one is running, an update is,
    // or no repository is configured).
    function checkUpdate() {
        if (root.checking || root.updating || !root.repoUrl) return false
        root.checking = true
        root.checkWatchdog.restart()
        root.checkProcess.running = true
        return true
    }

    // The whole log of the running (or last) update, in a terminal.
    function openLogs() {
        AppLaunch.spawnInTerminal(["journalctl", "-u", "nixos-upgrade-manual", "-f", "-n", "300", "-o", "cat", "--no-pager"])
    }

    function startUpdate() {
        if (root.updating) return false
        root.updating = true
        root.step = ""
        root.startUpdateProcess.running = true
        return true
    }

    function errorText(code) {
        return code === "" ? ""
            : code === "no-repo" ? Translation.tr("no repository configured")
            : code === "no-version" ? Translation.tr("no /etc/nixos/version")
            : code === "bad-version" ? Translation.tr("unreadable /etc/nixos/version")
            : code === "timeout" ? Translation.tr("timed out")
            : code === "unreachable" ? Translation.tr("can't reach the repository")
            : code
    }

    // Its own unit: the shell only waits for it (--wait), then reads the file.
    property Process checkProcess: Process {
        command: ["systemd-run", "--user", "--wait", "--collect", "--quiet",
            "--unit=nixbook-update-check", "-p", "RuntimeMaxSec=60",
            "nixbook-update-check", root.repoUrl]
        onExited: root.checkFile.reload()
    }

    // The unit stops itself after 60 s; this only guarantees the button can
    // never stay stuck on "Checking...".
    property Timer checkWatchdog: Timer {
        interval: 75000
        onTriggered: {
            root.checking = false
            root.checkError = Translation.tr("timed out")
            root.lastCheckTime = Qt.formatTime(new Date(), "hh:mm")
        }
    }

    property FileView checkFile: FileView {
        path: root.checkPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let data
            try {
                data = JSON.parse(root.checkFile.text())
            } catch (e) {
                return // caught mid-write: the next change reads it whole
            }
            if (data.checking === true) return
            root.checkWatchdog.stop()
            root.checking = false
            root.checkError = root.errorText(data.error ?? "")
            root.lastCheckTime = data.time ?? ""
            if (data.localRev === undefined) {
                root.considerAuto()
                return // failed before knowing more
            }
            root.localRev = data.localRev
            root.localBranch = data.localBranch ?? "Unknown"
            root.localDirty = data.localDirty === true
            root.remoteRev = data.remoteRev ?? "Unknown"
            root.updateAvailable = data.available === true
            root.changelogText = (data.changelog ?? []).map(c => `- ${c}`).join("\n")
            root.ci = data.ci ?? ""
            root.considerAuto()
        }
    }

    property Process startUpdateProcess: Process {
        command: ["systemctl", "start", "--no-block", "nixos-upgrade-manual.service"]
        onExited: code => {
            if (code !== 0) {
                root.updating = false
                root.checkUpdate()
            }
            root.statusFile.reload()
        }
    }

    property FileView statusFile: FileView {
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let data
            try {
                data = JSON.parse(root.statusFile.text())
            } catch (e) {
                return
            }
            const wasUpdating = root.updating
            root.updating = data.state === "running"
            root.step = data.step ?? ""
            if (data.state === "success" || data.state === "failed") {
                root.lastResult = data.state
                root.lastRunTime = data.finished ? Qt.formatDateTime(new Date(data.finished * 1000), "MMM d hh:mm") : ""
                root.lastRunLog = data.tail ?? ""
                if (Persistent.ready) root.noteResult(data)
                if (wasUpdating) root.checkUpdate()
            }
        }
    }
    // While updating: the step, even where the file watch misses a change
    // (/run/nixos-upgrade created after the shell started).
    property Timer statusPoll: Timer {
        interval: 2000
        repeat: true
        running: root.updating
        onTriggered: root.statusFile.reload()
    }

    // Periodic check — driven by the same config as the old service, so the
    // Services settings page (enable switch + interval) keeps working.
    property Timer updateTimer: Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        running: Config.ready && (Config.options.updates.enableCheck || root.autoEnabled)
        repeat: true
        onTriggered: root.checkUpdate()
    }

    // ---- Automatic updates
    readonly property int unknownBuildWaitMs: 60 * 60 * 1000

    function autoHold() {
        if (!root.autoEnabled || !root.updateAvailable || root.updating || root.checking || root.remoteRev === "Unknown")
            return ""
        const p = Persistent.states.updates
        if (root.localDirty)
            return Translation.tr("deployed from a local tree with uncommitted changes")
        if (root.localBranch !== "Unknown" && root.localBranch !== "refs/heads/main")
            return Translation.tr("deployed from another branch (%1)").arg(root.localBranch.replace("refs/heads/", ""))
        if (p.failedRev === root.remoteRev)
            return Translation.tr("the last update to %1 failed; Execute retries it").arg(root.remoteRev.slice(0, 7))
        if (root.ci === "failed")
            return Translation.tr("main's build of %1 failed for this machine").arg(root.remoteRev.slice(0, 7))
        if (root.ci === "pending")
            return Translation.tr("waiting for main's build to finish")
        if (root.ci === "" && Date.now() - p.seenAt * 1000 < root.unknownBuildWaitMs)
            return Translation.tr("waiting an hour after it appeared (its build can't be checked)")
        if (Battery.available && (!Battery.isPluggedIn || Battery.chargerTooWeak)) {
            if (!Config.options.updates.auto.onBattery)
                return Translation.tr("waiting for the charger")
            if (Battery.percentage < 0.5)
                return Translation.tr("waiting for the charger (battery under 50%)")
        }
        if (Quickshell.screens.some(s => WM.fullscreenOnMonitor(s.name)))
            return Translation.tr("a fullscreen window is open")
        if (CalendarEvents.meetingNow(new Date()))
            return Translation.tr("in a meeting")
        return ""
    }

    // Looked at after each check and every minute while an update waits.
    function considerAuto() {
        if (!root.started || !Persistent.ready) return
        if (root.updateAvailable && root.remoteRev !== "Unknown" && Persistent.states.updates.seenRev !== root.remoteRev) {
            Persistent.states.updates.seenRev = root.remoteRev
            Persistent.states.updates.seenAt = Math.floor(Date.now() / 1000)
        }
        const hold = root.autoHold()
        root.autoWaiting = hold
        if (hold !== "" || !root.autoEnabled || !root.updateAvailable || root.updating || root.checking
                || root.remoteRev === "Unknown")
            return
        Persistent.states.updates.autoTarget = root.remoteRev
        Persistent.states.updates.autoStartedAt = Math.floor(Date.now() / 1000)
        if (!root.startUpdate()) return
        Quickshell.execDetached(["notify-send", "-a", Translation.tr("System updates"), "-u", "low",
            "--hint=int:transient:1",
            Translation.tr("Updating in the background"),
            Translation.tr("Installing %1. The shell restarts once on its own; you can keep working.").arg(root.remoteRev.slice(0, 7))])
    }

    // An automatic run's result (also when the shell was restarted by it).
    function noteResult(data) {
        const p = Persistent.states.updates
        const finished = data.finished ?? 0
        if (finished <= p.lastFinished) return
        p.lastFinished = finished
        const recent = Date.now() / 1000 - finished < 6 * 3600
        if (data.state === "failed" && recent && root.updateAvailable && root.remoteRev !== "Unknown")
            p.failedRev = p.autoTarget !== "" ? p.autoTarget : root.remoteRev
        if (p.autoTarget === "" || finished < p.autoStartedAt) return
        const target = p.autoTarget
        p.autoTarget = ""
        if (!recent) return
        if (data.state === "success")
            Quickshell.execDetached(["notify-send", "-a", Translation.tr("System updates"), "-u", "low",
                Translation.tr("System updated"),
                Translation.tr("Now on %1.").arg((data.rev ?? target).slice(0, 7))])
        else
            Quickshell.execDetached(["notify-send", "-a", Translation.tr("System updates"),
                Translation.tr("Automatic update failed"),
                Translation.tr("%1 wasn't installed; it won't be tried again on its own. The Updates widget has the log and Execute retries it.").arg(target.slice(0, 7))])
    }

    property Timer autoTimer: Timer {
        interval: 60 * 1000
        repeat: true
        running: root.autoEnabled && root.updateAvailable && !root.updating
        onTriggered: root.considerAuto()
    }
    // While main is still building the revision, look again sooner.
    property Timer ciRecheck: Timer {
        interval: 10 * 60 * 1000
        repeat: true
        running: root.autoEnabled && root.updateAvailable && root.ci === "pending" && !root.updating
        onTriggered: root.checkUpdate()
    }
    onAutoEnabledChanged: root.considerAuto()

    Component.onCompleted: root.start()
}
