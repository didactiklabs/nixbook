pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25

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
    // when the desired state differs from the applied one): it used
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
        if (!root.staleCleared)
            return; // staleCleanup re-evaluates when done
        if (root.shouldBeOn && !root.temperatureActive) {
            root.enableTemperature();
        } else if (!root.shouldBeOn && root.temperatureActive) {
            root.disableTemperature();
        }
    }

    function load() {
        root.disableTemperature();
    }

    function enableTemperature() {
        root.startWlsunset(root.colorTemperature);
        root.temperatureActive = true;
    }

    function disableTemperature() {
        root.stopWlsunset();
        root.temperatureActive = false;
    }

    // Only tracked (the brightness keys fall back to it below 0 brightness):
    // wlsunset has no separate gamma control.
    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();
    }

    // One wlsunset owned by the shell (it exits with the shell, and the
    // compositor restores neutral gamma). Forced to "night" all day: sunset
    // 00:00, sunrise 23:59, 1 s transitions, day/night temperatures 50 K apart.
    // (Re)started only when it isn't running or the temperature changed.
    property int appliedTemp: 0
    property bool stopping: false
    function startWlsunset(temp) {
        if (wlsunsetProc.running && root.appliedTemp === temp) return;
        root.appliedTemp = temp;
        wlsunsetProc.command = ["wlsunset", "-T", `${temp + 50}`, "-t", `${temp}`, "-S", "23:59", "-s", "00:00", "-d", "1"];
        if (wlsunsetProc.running) {
            root.restarting = true;
            wlsunsetProc.running = false; // onExited starts it again
        } else {
            wlsunsetProc.running = true;
        }
    }
    property bool restarting: false

    function stopWlsunset() {
        root.restarting = false;
        root.appliedTemp = 0;
        if (wlsunsetProc.running) {
            root.stopping = true;
            wlsunsetProc.running = false;
        }
    }

    Process {
        id: wlsunsetProc
        onExited: (exitCode, exitStatus) => {
            if (root.restarting) {
                root.restarting = false;
                Qt.callLater(() => wlsunsetProc.running = true);
                return;
            }
            if (!root.stopping && root.temperatureActive) {
                // Died on its own (no gamma control, crashed): don't loop, just
                // reflect it; the next toggle/boundary tries again.
                console.warn(`[NightLightService] wlsunset exited (${exitCode}); night light is off`);
                root.temperatureActive = false;
                root.appliedTemp = 0;
            }
            root.stopping = false;
        }
    }

    // Instances started detached by older builds of the shell would fight ours
    // for the gamma ramps: clear them once, before the first apply.
    property bool staleCleared: false
    Process {
        id: staleCleanup
        running: true
        command: ["pkill", "-x", "-u", Quickshell.env("USER") ?? "", "wlsunset"]
        onExited: {
            root.staleCleared = true;
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
        root.temperatureActive = wlsunsetProc.running;
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
            root.startWlsunset(Config.options.light.night.colorTemperature);
        }
    }
}
