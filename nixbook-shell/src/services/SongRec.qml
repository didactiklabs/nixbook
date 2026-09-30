pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    function load() {}

    enum MonitorSource { Monitor, Input }

    property var monitorSource: SongRec.MonitorSource.Monitor
    property int timeoutInterval: Config.options.musicRecognition.interval
    property int timeoutDuration: Config.options.musicRecognition.timeout
    readonly property bool running: recognizeMusicProc.running

    function toggleRunning(running) {
        if (recognizeMusicProc.running && !running === true) root.manuallyStopped = true;
        if (running != undefined) {
            recognizeMusicProc.running = running
        } else {
            recognizeMusicProc.running = !root.running
        }
        musicReconizedProc.running = false
    }

    function toggleMonitorSource(source) {
        if (source !== undefined) {
            root.monitorSource = source
            return
        }
        root.monitorSource = (root.monitorSource === SongRec.MonitorSource.Monitor) ? SongRec.MonitorSource.Input : SongRec.MonitorSource.Monitor
    }
    function monitorSourceToString(source) {
        if (source === SongRec.MonitorSource.Monitor) {
            return "monitor"
        } else {
            return "input"
        }
    }
    readonly property string monitorSourceString: monitorSourceToString(monitorSource)
    property var recognizedTrack: ({ title:"", subtitle:"", url:"", cover:"" })
    // When the last song was found (ms), and the ones before it (newest
    // first, at most 5): the bar and desktop widgets show them.
    property real recognizedAt: 0
    property var history: []
    // When the last try found nothing (ms), for the widgets' "No match".
    property real failedAt: 0
    property bool manuallyStopped: false

    function openShazam(track) {
        const t = track ?? root.recognizedTrack
        if ((t?.url ?? "").length > 0) AppLaunch.openUrl(t.url)
    }
    function openYouTube(track) {
        const t = track ?? root.recognizedTrack
        if ((t?.title ?? "").length === 0) return
        AppLaunch.openUrl("https://www.youtube.com/results?search_query=" + encodeURIComponent(t.title + " - " + t.subtitle))
    }

    function handleRecognition(jsonText) {
        try {
            var obj = JSON.parse(jsonText)
            root.recognizedTrack = {
                title: obj.track.title,
                subtitle: obj.track.subtitle,
                url: obj.track.url,
                cover: obj.track.images?.coverart ?? ""
            }
            root.recognizedAt = Date.now()
            root.history = [root.recognizedTrack].concat(root.history.filter(t => t.url !== root.recognizedTrack.url)).slice(0, 5)
            musicReconizedProc.running = true
        } catch(e) {
            root.failedAt = Date.now()
            Quickshell.execDetached(["notify-send", Translation.tr("Couldn't recognize music"), Translation.tr("Perhaps what you're listening to is too niche"), "-a", "Shell"])
        }
    }

    Process {
        id: recognizeMusicProc
        running: false
        command: [`${Directories.scriptPath}/musicRecognition/recognize-music.sh`, "-i", root.timeoutInterval, "-t", root.timeoutDuration, "-s", root.monitorSourceString]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.manuallyStopped) {
                    root.manuallyStopped = false
                    return
                }
                handleRecognition(this.text)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                Quickshell.execDetached(["notify-send", Translation.tr("Couldn't recognize music"), Translation.tr("Make sure you have songrec installed"), "-a", "Shell"])
            }
        }
    }

    Process {
        id: musicReconizedProc
        running: false
        command: [
            "notify-send",
            Translation.tr("Music Recognized"), 
            root.recognizedTrack.title + " - " + root.recognizedTrack.subtitle, 
            "-A", "Shazam",
            "-A", "YouTube",
            "-a", "Shell"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text === "") return
                if (this.text == 0) {
                    root.openShazam();
                } else {
                    root.openYouTube();
                }
            }
        }
    }

    // `nixbook-shell ipc call musicRecognition listen|stop|status|useSystemSound|useMicrophone`:
    // for key bindings and the desktop MCP server. A song found comes in
    // `status` (and the usual notification) once songrec answers.
    IpcHandler {
        target: "musicRecognition"

        function listen(): string {
            if (!root.running)
                root.toggleRunning(true);
            return `ok: listening to the ${root.monitorSource === SongRec.MonitorSource.Monitor ? "system sound" : "microphone"} for up to ${root.timeoutDuration} s`;
        }
        function stop(): string {
            if (root.running)
                root.toggleRunning(false);
            return "ok: stopped";
        }
        function status(): string {
            const iso = ms => ms > 0 ? new Date(ms).toISOString() : null;
            return JSON.stringify({
                listening: root.running,
                source: root.monitorSource === SongRec.MonitorSource.Monitor ? "system sound" : "microphone",
                timeoutSeconds: root.timeoutDuration,
                last: (root.recognizedTrack.title ?? "").length > 0 ? root.recognizedTrack : null,
                foundAt: iso(root.recognizedAt),
                lastNoMatchAt: iso(root.failedAt),
                history: root.history,
            });
        }
        function useSystemSound(): string {
            root.toggleMonitorSource(SongRec.MonitorSource.Monitor);
            return "ok: system sound";
        }
        function useMicrophone(): string {
            root.toggleMonitorSource(SongRec.MonitorSource.Input);
            return "ok: microphone";
        }
    }
}
