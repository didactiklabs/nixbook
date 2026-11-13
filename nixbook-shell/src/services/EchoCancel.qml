pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

/**
 * Echo cancellation: the computer's own sound (music, a film, the other side
 * of a call) kept out of the microphone, with noise suppression. The
 * `nixbook-echo-cancel` user unit runs PipeWire's WebRTC echo canceller
 * (scripts/echo-cancel.sh): an "Echo-cancelled microphone", made the default
 * input while it runs; what the default output plays is the reference to
 * remove, so nothing is rerouted. On or off from the quick toggle, the
 * audio input dialog, or the Mesh's listening-together bar; remembered
 * across logins (Persistent.states.media.echoCancel). No AI.
 */
Singleton {
    id: root

    // Loaded at the shell's start (shell.qml).
    function load() {}

    readonly property string unit: "nixbook-echo-cancel.service"
    readonly property string sourceName: "nixbook-echo-cancel.source"
    // The unit is installed (programs.nixbook-shell.echoCancel.enable).
    property bool available: false
    // Running: its microphone is there.
    readonly property bool active: Pipewire.nodes.values.some(n => n.name === root.sourceName)
    // Used: the default input is it.
    readonly property bool inUse: Pipewire.defaultAudioSource?.name === root.sourceName
    property bool busy: false
    property string error: ""
    // The microphone it cancels from (its node.name: scripts/echo-cancel.sh
    // keeps it in the runtime dir); "" until known.
    property string mic: ""
    readonly property string micFile: `${Quickshell.env("XDG_RUNTIME_DIR")}/nixbook-shell/echo-cancel-previous-source`
    FileView {
        path: root.micFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // Gone for a moment while it restarts: the last one is kept.
        onLoaded: {
            const name = text().trim();
            if (name !== "") root.mic = name;
        }
    }
    // A microphone it can take: a real one, not its own source nor
    // EasyEffects' (which records the default input: this one, a loop).
    function canCapture(node) {
        const name = node?.name ?? "";
        return name !== "" && name !== root.sourceName && name !== root.aecName && name !== "easyeffects_source" && !name.endsWith(".monitor")
            && !(node?.isStream ?? true);
    }
    // Another microphone: while it runs, the canceller takes it (a restart,
    // about a second); otherwise it becomes the default input.
    function useMic(node) {
        if (!root.canCapture(node)) return;
        if (!root.active) {
            Pipewire.preferredDefaultAudioSource = node;
            return;
        }
        root.mic = node.name;
        root._restart(node.name);
    }
    function _restart(name) {
        if (root.busy) return;
        root.error = "";
        root.busy = true;
        ctl.command = ["sh", "-c", 'printf "%s\\n" "$1" > "$2" && systemctl --user restart "$3"', "_", name, root.micFile, root.unit];
        ctl.running = true;
    }
    // On the same microphone (the unit puts it back as the default input
    // when it stops, and takes the default when it starts).
    function _restartSame() {
        if (root.busy) return;
        root.error = "";
        root.busy = true;
        ctl.command = ["systemctl", "--user", "restart", root.unit];
        ctl.running = true;
    }
    // Its microphone came back (a suspend, plugged in again): the canceller
    // is put back on it, since WirePlumber left it on another meanwhile.
    readonly property bool micHere: root.mic !== "" && Pipewire.nodes.values.some(n => n.name === root.mic)
    property bool _micWasGone: false
    onMicHereChanged: {
        if (!root.micHere) {
            if (root.mic !== "" && root.active) root._micWasGone = true;
        } else if (root._micWasGone) {
            root._micWasGone = false;
            if (root.active) micBack.restart();
        }
    }
    Timer {
        id: micBack
        interval: 1500 // the device settles (its profile, the other nodes) first
        onTriggered: if (root.active && root.micHere) root._restart(root.mic)
    }

    function set(on) {
        if (!root.available || root.busy) return;
        Persistent.states.media.echoCancel = on;
        root.error = "";
        root.busy = true;
        ctl.command = ["systemctl", "--user", on ? "start" : "stop", root.unit];
        ctl.running = true;
    }
    function toggle() {
        root.set(!root.active);
    }
    Process {
        id: ctl
        stderr: StdioCollector { id: ctlErr }
        onExited: code => {
            root.busy = false;
            if (code !== 0) root.error = ctlErr.text.trim() || Translation.tr("Echo cancellation didn't start");
        }
    }

    // Installed? Then on again if it was on at the last session.
    Process {
        id: probe
        running: true
        command: ["systemctl", "--user", "show", "-p", "LoadState", "--value", root.unit]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = text.trim() === "loaded";
                if (root.available && Persistent.ready && Persistent.states.media.echoCancel && !root.active)
                    root.set(true);
            }
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready && root.available && Persistent.states.media.echoCancel && !root.active)
                root.set(true);
        }
    }

    // Resting while nothing records the cancelled microphone. PipeWire runs
    // what is downstream of an output that plays, through passive links too:
    // with its reference on the default output, the canceller, its speech
    // stage and the microphone ran whenever a sound played, with nobody
    // listening to the microphone (music alone: 18 % of a core, and the whole
    // audio graph at a 5 ms period; measured on totoro). So while no stream
    // records from it, the reference waits on the unit's idle sink
    // (`nixbook-echo-cancel rest on`) and nothing of it runs; a recorder
    // starts the chain by itself (its link isn't passive), and the reference
    // goes back to the default output at once. A new unit starts awake
    // (another reference stream): what a crash of the shell leaves is the
    // canceller working, never a call without it.
    readonly property string referenceName: "nixbook-echo-cancel.reference"
    readonly property string voiceStageName: "nixbook-echo-cancel.voice"
    readonly property int referenceId: Pipewire.nodes.values.find(n => n.name === root.referenceName)?.id ?? -1
    // Something records it: a link from its microphone (or the canceller's
    // own, under the voice stage) to anything but that stage.
    readonly property bool recorded: Pipewire.linkGroups.values.some(g =>
        (g.source?.name === root.sourceName || g.source?.name === root.aecName)
        && g.target && g.target.name !== root.voiceStageName)
    // What this unit's reference was last told.
    property bool resting: false
    property var _restQueued: null
    function _rest(on) {
        if (root.referenceId < 0) return;
        if (restCtl.running) {
            root._restQueued = on; // the latest wins
            return;
        }
        root.resting = on;
        restCtl.command = ["nixbook-echo-cancel", "rest", on ? "on" : "off"];
        restCtl.running = true;
    }
    Process {
        id: restCtl
        onExited: {
            if (root._restQueued === null) return;
            const on = root._restQueued;
            root._restQueued = null;
            if (on !== root.resting) root._rest(on);
        }
    }
    onRecordedChanged: {
        if (root.recorded) {
            restTimer.stop();
            // Always said, whatever this shell believes: a call without
            // echo cancellation is the one thing that must not happen.
            root._rest(false);
        } else {
            restTimer.restart();
        }
    }
    onReferenceIdChanged: {
        root.resting = false;
        root._restQueued = null;
        if (root.referenceId < 0) return;
        // Found resting by a shell that just started, while a call runs.
        if (root.recorded) root._rest(false);
        else restTimer.restart();
    }
    Timer {
        id: restTimer
        interval: 4000 // a recorder that reconnects (a call app switching device) keeps it awake
        onTriggered: if (root.referenceId >= 0 && !root.recorded) root._rest(true)
    }

    // Voices made clearer in calls, the unit's two speech stages
    // (scripts/echo-cancel.sh; no AI: an equalizer, a compressor, a
    // limiter), each a switch of audio.calls:
    // - clearMicrophone, your voice for the others: the stage sits between
    //   the canceller's own microphone (aecName) and the one apps record;
    // - clearVoices, the others' voices for you: the "Call voices" output
    //   (voicesName), where call apps play: a PipeWire stream rule gives
    //   them that target (hm-module.nix, echoCancel.callApps, and callSites
    //   for a browser's call tabs), and without
    //   it they play straight on the default output, never through
    //   EasyEffects (the music equalizer's curve and preamp, on voices).
    // The unit reads the switches from the settings file when it starts: one
    // changed while it runs restarts it once the file is written, and so
    // does a unit found running without what the switches ask (after an
    // update). Only then: a stage that didn't load isn't retried in a loop.
    readonly property string aecName: "nixbook-echo-cancel.aec"
    readonly property string voicesName: "nixbook-call-voices"
    readonly property bool micStage: Pipewire.nodes.values.some(n => n.name === root.aecName)
    readonly property bool voicesStage: Pipewire.nodes.values.some(n => n.name === root.voicesName && !n.isStream)
    readonly property bool wantMicStage: Config.options.audio.calls.clearMicrophone
    readonly property bool wantVoicesStage: Config.options.audio.calls.clearVoices
    onWantMicStageChanged: stagesTimer.restart()
    onWantVoicesStageChanged: stagesTimer.restart()
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) stagesTimer.restart(); }
    }
    Component.onCompleted: if (Config.ready) stagesTimer.restart()
    Timer {
        id: stagesTimer
        interval: 2500 // the settings written, the unit's nodes listed
        onTriggered: {
            if (!Config.ready || !root.active || root.busy) return;
            if (root.micStage !== root.wantMicStage || root.voicesStage !== root.wantVoicesStage)
                root._restartSame();
        }
    }

    // Call apps and calls in a browser on "Call voices" (audio.calls.apps and
    // .sites): their PipeWire stream rule, written by `nixbook-echo-cancel
    // call-rules` once the settings are read and a few seconds after the last
    // edit; a change restarts pipewire-pulse (it reads the rule when it
    // starts). Only where the unit is installed: the rule targets its sink.
    readonly property string callRulesKey: JSON.stringify([Config.options.audio.calls.apps, Config.options.audio.calls.sites])
    onCallRulesKeyChanged: if (Config.ready) callRulesTimer.restart()
    onAvailableChanged: if (root.available && Config.ready) callRulesTimer.restart()
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) callRulesTimer.restart(); }
    }
    Timer {
        id: callRulesTimer
        interval: 3000
        onTriggered: {
            if (!root.available) return;
            if (callRules.running) {
                callRulesTimer.restart();
                return;
            }
            callRules.running = true;
        }
    }
    Process {
        id: callRules
        command: ["nixbook-echo-cancel", "call-rules", "--restart"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (/"changed": true/.test(this.text)) console.info("[EchoCancel] call apps' stream rule written; pipewire-pulse restarted");
            }
        }
    }

    // `nixbook-shell ipc call echoCancel on|off|toggle|status`.
    IpcHandler {
        target: "echoCancel"
        function on(): void {
            root.set(true);
        }
        function off(): void {
            root.set(false);
        }
        function toggle(): void {
            root.toggle();
        }
        function status(): string {
            return JSON.stringify({ available: root.available, active: root.active, inUse: root.inUse, mic: root.mic, error: root.error,
                clearMicrophone: root.micStage, clearVoices: root.voicesStage, recorded: root.recorded, resting: root.resting });
        }
    }
}
