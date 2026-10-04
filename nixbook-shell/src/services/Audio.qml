pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
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

    function toggleMicMute() {
        if (!Audio.source?.audio) return;
        Audio.source.audio.muted = !Audio.source.audio.muted;
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

    // Internals
    PwObjectTracker {
        objects: [sink, source]
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
