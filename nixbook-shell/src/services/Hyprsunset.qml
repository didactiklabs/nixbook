pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25
    readonly property bool isNiri: WM.compositor === "niri"

    property string from: Config.options?.light?.night?.from ?? "19:00"
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: (Config.options?.light?.night?.automatic ?? false) && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            return (t >= from || t <= to);
        }
    }

    // Re-evaluated every minute. Applying is idempotent (ensureState only acts
    // when the desired state differs from the applied one): the niri path used
    // to `pkill wlsunset` and start a new one on every minute tick, so the
    // screen flashed back to neutral once a minute all night.
    function reEvaluate() {
        if (!(Config?.ready ?? false)) return;
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);
        // Apply right away, including the first evaluation after startup (it
        // used to be skipped, leaving the screen neutral until the next minute).
        root.firstEvaluation = false;
        root.ensureState();
    }

    function ensureState() {
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.isNiri && !root.niriReady)
            return; // niriCleanup re-evaluates when done
        if (root.shouldBeOn && !root.temperatureActive) {
            root.enableTemperature();
        } else if (!root.shouldBeOn && root.temperatureActive) {
            root.disableTemperature();
        }
    }

    function startHyprsunset() {
        if (root.isNiri) return;
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset`]);
    }

    function load() {
        if (root.isNiri) {
            root.disableTemperature();
            return;
        }
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset & disown; sleep 0.3; hyprctl hyprsunset identity`]);
        root.temperatureActive = false;
    }

    function enableTemperature() {
        if (root.isNiri) {
            root.startNiriSunset(root.colorTemperature);
        } else {
            root.startHyprsunset();
            Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
        }
        root.temperatureActive = true;
    }

    function disableTemperature() {
        if (root.isNiri) {
            root.stopNiriSunset();
        } else {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        }
        root.temperatureActive = false;
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();

        if (root.isNiri) {
            return;
        }
        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
    }

    // niri: one wlsunset owned by the shell (it exits with the shell, and the
    // compositor restores neutral gamma). Forced to "night" all day: sunset
    // 00:00, sunrise 23:59, 1 s transitions, day/night temperatures 50 K apart.
    // (Re)started only when it isn't running or the temperature changed.
    property int niriAppliedTemp: 0
    property bool niriStopping: false
    function startNiriSunset(temp) {
        if (wlsunsetProc.running && root.niriAppliedTemp === temp) return;
        root.niriAppliedTemp = temp;
        wlsunsetProc.command = ["wlsunset", "-T", `${temp + 50}`, "-t", `${temp}`, "-S", "23:59", "-s", "00:00", "-d", "1"];
        if (wlsunsetProc.running) {
            root.niriRestart = true;
            wlsunsetProc.running = false; // onExited starts it again
        } else {
            wlsunsetProc.running = true;
        }
    }
    property bool niriRestart: false

    function stopNiriSunset() {
        root.niriRestart = false;
        root.niriAppliedTemp = 0;
        if (wlsunsetProc.running) {
            root.niriStopping = true;
            wlsunsetProc.running = false;
        }
    }

    Process {
        id: wlsunsetProc
        onExited: (exitCode, exitStatus) => {
            if (root.niriRestart) {
                root.niriRestart = false;
                Qt.callLater(() => wlsunsetProc.running = true);
                return;
            }
            if (!root.niriStopping && root.temperatureActive) {
                // Died on its own (no gamma control, crashed): don't loop, just
                // reflect it; the next toggle/boundary tries again.
                console.warn(`[Hyprsunset] wlsunset exited (${exitCode}); night light is off`);
                root.temperatureActive = false;
                root.niriAppliedTemp = 0;
            }
            root.niriStopping = false;
        }
    }

    // Instances started detached by older builds of the shell would fight ours
    // for the gamma ramps: clear them once, before the first apply.
    property bool niriReady: false
    Process {
        id: niriCleanup
        running: root.isNiri
        command: ["pkill", "-x", "-u", Quickshell.env("USER") ?? "", "wlsunset"]
        onExited: {
            root.niriReady = true;
            root.reEvaluate();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.reEvaluate();
        }
    }

    function fetchState() {
        if (root.isNiri) {
            root.temperatureActive = wlsunsetProc.running;
        } else {
            fetchProc.running = true;
        }
    }

    Process {
        id: fetchProc
        running: false
        command: ["bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't"))
                    root.temperatureActive = false;
                else
                    root.temperatureActive = (output != "6500");
            }
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            if (root.isNiri) {
                root.startNiriSunset(Config.options.light.night.colorTemperature);
            } else {
                Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
            }
        }
    }
}
