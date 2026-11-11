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
        return name !== "" && name !== root.sourceName && name !== "easyeffects_source" && !name.endsWith(".monitor")
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
            return JSON.stringify({ available: root.available, active: root.active, inUse: root.inUse, mic: root.mic, error: root.error });
        }
    }
}
