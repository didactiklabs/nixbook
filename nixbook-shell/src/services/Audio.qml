pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio?.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node?.nickname || node?.description || Translation.tr("Unknown"));
    }
    // A mixer entry's binding still runs once its stream is gone (node null).
    function appNodeDisplayName(node) {
        return (node?.properties?.["application.name"] || node?.description || node?.name || "")
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        if (!Audio.sink?.audio) return;
        Audio.sink.audio.muted = !Audio.sink.audio.muted;
    }

    // The microphone is muted as a whole: every input (the devices, and the
    // echo canceller's), not only the default one. An app recording another
    // mic than the default (a call app's own input setting), or the real mic
    // under the echo canceller, used to go on hearing. Quickshell only knows
    // Audio/Source nodes: EasyEffects' Audio/Source/Virtual one can't be
    // muted from here, but it only carries the (muted) real mics. Muted =
    // every mic muted (so the state isn't read from a default the shell
    // can't see); a mic that comes while muted (a headset connecting) is
    // muted too, until it is unmuted.
    readonly property bool micMuted: root.inputDevices.length > 0
        ? root.inputDevices.every(n => n.audio?.muted ?? false)
        : (root.source?.audio?.muted ?? false)
    property bool _allMuted: false
    property var _seenMics: ({})
    function setMicMuted(muted) {
        root._allMuted = muted;
        const seen = {};
        for (const n of root.inputDevices) {
            seen[n.id] = true;
            if (n.audio) n.audio.muted = muted;
        }
        root._seenMics = seen;
    }
    function toggleMicMute() {
        root.setMicMuted(!root.micMuted);
    }
    onInputDevicesChanged: if (root._allMuted) newMicTimer.restart()
    // A new node's audio is there once it is bound: a moment later.
    Timer {
        id: newMicTimer
        interval: 600
        onTriggered: {
            if (!root._allMuted) return;
            const seen = Object.assign({}, root._seenMics);
            let waiting = false;
            for (const n of root.inputDevices) {
                if (seen[n.id]) continue;
                if (!n.ready || !n.audio) { waiting = true; continue; }
                n.audio.muted = true;
                seen[n.id] = true;
            }
            root._seenMics = seen;
            if (waiting) newMicTimer.restart();
        }
    }
    // Unmuted elsewhere (wpctl, pavucontrol): no longer held muted.
    Connections {
        target: root.source?.audio ?? null
        function onMutedChanged() {
            if (root._allMuted && !root.source.audio.muted) root._allMuted = false;
        }
    }

    IpcHandler {
        target: "audio"
        function micToggle(): string {
            const muted = !root.micMuted;
            root.setMicMuted(muted);
            return muted ? "muted" : "unmuted";
        }
        function micMute(): void { root.setMicMuted(true); }
        function micUnmute(): void { root.setMicMuted(false); }
        function micStatus(): string { return root.micMuted ? "muted" : "unmuted"; }
        function toggleMute(): void { root.toggleMute(); }
        // The output and the microphones, for the desktop agents' `sound`
        // tool (this target is denied to their generic shell_ipc: it could
        // unmute the microphone; the tool asks the user first).
        function status(): string {
            return JSON.stringify({
                output: { name: root.friendlyDeviceName(root.sink), volume: Math.round((root.sink?.audio?.volume ?? 0) * 100),
                    muted: root.sink?.audio?.muted ?? false },
                microphone: { muted: root.micMuted, default: root.friendlyDeviceName(root.source),
                    devices: root.inputDevices.map(n => ({ name: root.friendlyDeviceName(n), muted: n.audio?.muted ?? false })) }
            });
        }
        // 0-100 (audio.protection still applies: no sudden jump).
        function setVolume(percent: int): string {
            if (!root.sink?.audio) return "error: no output device";
            root.sink.audio.volume = Math.max(0, Math.min(100, percent)) / 100;
            return `ok: volume ${Math.round(root.sink.audio.volume * 100)}%`;
        }
        function outputMute(muted: bool): string {
            if (!root.sink?.audio) return "error: no output device";
            root.sink.audio.muted = muted;
            return muted ? "ok: muted" : "ok: unmuted";
        }
    }

    function incrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.min(1, Math.round((currentVolume + step) * 100) / 100);
    }
    
    function decrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.max(0, Math.round((currentVolume - step) * 100) / 100);
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // EasyEffects' sink (easyeffects_sink, a null sink EasyEffects reads
    // through its monitor) is the default output while EasyEffects runs, so
    // the volume slider, the volume keys and wpctl all set its volume, which
    // a null sink doesn't apply to its monitor (monitor.channel-volumes is
    // off): the volume did nothing (at 0, the sound still reached the
    // earbuds at full level). Turned on whenever that sink appears
    // (EasyEffects makes a new one each time it starts); measured on a null
    // sink: volume 0 silent, 0.5 the cube's eighth, as on a device.
    readonly property var eeSink: Pipewire.nodes.values.find(n => n.name === "easyeffects_sink" && !n.isStream) ?? null
    property int _eeVolumesFor: -1
    onEeSinkChanged: {
        if (!root.eeSink || root.eeSink.id === root._eeVolumesFor) return;
        root._eeVolumesFor = root.eeSink.id;
        Quickshell.execDetached(["pw-cli", "set-param", String(root.eeSink.id), "Props", '{ params = [ "monitor.channel-volumes" true ] }']);
    }

    // An app's output connected to nothing: after EasyEffects restarts (its
    // sink goes and comes back with another id), a stream it had moved there
    // can keep that sink as its target and stay unlinked: no sound until
    // the output is switched by hand. A stream with no link for 5 s gets its
    // stale target cleared, so WirePlumber connects it to the default output
    // (at most once a minute per stream; one that doesn't want to connect,
    // node.autoconnect false, is left alone).
    readonly property var linkedSources: {
        const ids = {};
        for (const g of Pipewire.linkGroups.values) if (g.source) ids[g.source.id] = true;
        return ids;
    }
    property var _unlinkedSince: ({})
    property var _relinkedAt: ({})
    Timer {
        interval: 2500
        repeat: true
        running: root.outputAppNodes.length > 0
        onTriggered: {
            const now = Date.now();
            const since = {};
            for (const n of root.outputAppNodes) {
                if (root.linkedSources[n.id] || n.properties?.["node.autoconnect"] === "false") continue;
                since[n.id] = root._unlinkedSince[n.id] ?? now;
                if (now - since[n.id] < 5000 || now - (root._relinkedAt[n.id] ?? 0) < 60000) continue;
                root._relinkedAt[n.id] = now;
                console.log(`[Audio] ${n.name} (${n.id}) is connected to nothing: its target cleared, back to the default output`);
                Quickshell.execDetached(["sh", "-c", 'pw-metadata -d "$1" target.object; pw-metadata -d "$1" target.node', "sh", String(n.id)]);
            }
            root._unlinkedSince = since;
        }
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }
    // Every input, so each can be muted (setMicMuted).
    PwObjectTracker {
        objects: root.inputDevices
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    // Plays an audio file once with pw-play (PipeWire's own client: starts in
    // a few ms, little memory) when libsndfile reads the format, else ffplay.
    // Always exec'd: stopping a ringtone (TimerService) kills the player.
    readonly property string playScript: 'case "$1" in *.wav|*.ogg|*.oga|*.flac|*.opus|*.mp3|*.WAV|*.OGG|*.FLAC|*.MP3) exec pw-play "$1" ;; *) exec ffplay -nodisp -autoexit -loglevel quiet "$1" ;; esac'
    function playFileCommand(path) {
        return ["sh", "-c", root.playScript, "sh", path.replace(/^file:\/\//, "")];
    }

    // The command playing `soundName` from the sound theme (sounds.theme,
    // else freedesktop), looked up in $XDG_DATA_DIRS: the first file found.
    function systemSoundCommand(soundName) {
        const dirs = (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":").filter(d => d !== "");
        const candidates = [];
        for (const theme of [...new Set([root.audioTheme, "freedesktop"])])
            for (const dir of dirs)
                for (const ext of ["oga", "ogg", "wav"])
                    candidates.push(`${dir}/sounds/${theme}/stereo/${soundName}.${ext}`);
        return ["sh", "-c",
            `for f in "$@"; do [ -f "$f" ] && { set -- "$f"; ${root.playScript}; }; done`,
            "sh", ...candidates];
    }
    function playSystemSound(soundName) {
        Quickshell.execDetached(root.systemSoundCommand(soundName));
    }

    // A ringtone setting (sounds.focusRingtone, countdownRingtone,
    // alarmRingtone): an audio file's path, or a sound theme name
    // ("alarm-clock-elapsed"). The command plays it once.
    function ringtoneCommand(ringtone) {
        if ((ringtone ?? "").includes("/"))
            return root.playFileCommand(ringtone);
        return root.systemSoundCommand(ringtone || "alarm-clock-elapsed");
    }
    function playRingtone(ringtone) {
        Quickshell.execDetached(root.ringtoneCommand(ringtone));
    }

    // What plays for `kind` ("notification", "focus", "countdown", "alarm"),
    // for playRingtone/ringtoneCommand: on a theme with its own sounds
    // (Themes.themeSounds) the theme's; else the setting (sounds.
    // notificationFile, empty: the default chime; sounds.<kind>Ringtone).
    function soundFor(kind) {
        if (Themes.themeSounds) {
            const themed = Themes.sound(kind);
            if (themed !== "") return themed;
        }
        const sounds = Config.options.sounds;
        if (kind === "notification")
            return sounds.notificationFile || Themes.sound("notification");
        return sounds[kind + "Ringtone"] || "alarm-clock-elapsed";
    }

    // Play an arbitrary audio file (absolute path or file:// URL).
    function playSoundFile(path) {
        Quickshell.execDetached(root.playFileCommand(path));
    }
}
