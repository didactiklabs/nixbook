pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    function load() {}

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime // This is a binding that's to be kept
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    // Countdown
    property bool countdownRunning: Persistent.states.timer.countdown.running
    property int countdownDuration: Persistent.states.timer.countdown.duration // seconds, total
    property int countdownStart: Persistent.states.timer.countdown.start
    property int countdownSecondsLeft: countdownDuration

    // Alarm: one, at a date and time (epoch seconds), once or every day.
    // Rings (alarmRingtone, looped) until dismissed or snoozed, or for
    // `alarmRingSeconds` at most.
    readonly property var alarm: Persistent.states.timer.alarm
    property bool alarmEnabled: alarm.enabled
    property int alarmAt: alarm.at
    property string alarmLabel: alarm.label
    property bool alarmDaily: alarm.daily
    property int alarmSnoozeUntil: alarm.snoozeUntil
    property bool alarmRinging: false
    property int alarmRingStart: 0
    readonly property int alarmRingSeconds: 120
    readonly property int alarmSnoozeMinutes: 5
    // An alarm missed by more than this (the shell wasn't running, the
    // machine slept) is only reported, not rung.
    readonly property int alarmMissedSeconds: 3600

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
        if (!countdownRunning)
            countdownSecondsLeft = countdownDuration;
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    function formatSeconds(totalSeconds) {
        const s = Math.max(0, Math.round(totalSeconds));
        const m = Math.floor(s / 60);
        const sec = s % 60;
        return `${m}:${sec.toString().padStart(2, "0")}`;
    }

    // Pomodoro
    function refreshPomodoro() {
        // Work <-> break ?
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Quickshell.execDetached(["notify-send", "Pomodoro", notificationMessage, "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playRingtone(Audio.soundFor("focus"))
            }

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }
        }

        pomodoroSecondsLeft = pomodoroLapDuration - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        refreshPomodoro();
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        // Reads the clock on each tick, so a slower tick loses no accuracy:
        // once per frame with the sidebar open (10 ms was faster than the
        // display), 10/s when only the bar shows it.
        interval: GlobalStates.sidebarRightOpen ? 16 : 100
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }

    // Countdown
    function refreshCountdown() {
        if (!Persistent.states.timer.countdown.running) return;

        const elapsed = getCurrentTimeInSeconds() - Persistent.states.timer.countdown.start;
        let left = Persistent.states.timer.countdown.duration - elapsed;

        if (left <= 0) {
            left = 0;
            Persistent.states.timer.countdown.running = false;
            Persistent.states.timer.countdown.duration = 0;
            Quickshell.execDetached(["notify-send", "Timers", "⏰ Countdown finished", "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playRingtone(Audio.soundFor("countdown"))
            }
        }

        countdownSecondsLeft = left;
    }

    Timer {
        id: countdownTimer
        interval: 200
        running: root.countdownRunning
        repeat: true
        onTriggered: refreshCountdown()
    }

    // Adds minutes to the countdown. Works whether paused or running.
    function addCountdownMinutes(minutes) {
        const addSeconds = minutes * 60;
        if (root.countdownRunning) {
            Persistent.states.timer.countdown.duration += addSeconds;
        } else {
            Persistent.states.timer.countdown.duration = (Persistent.states.timer.countdown.duration ?? 0) + addSeconds;
            countdownSecondsLeft = Persistent.states.timer.countdown.duration;
        }
    }

    function toggleCountdown() {
        if (countdownDuration <= 0) return;
        Persistent.states.timer.countdown.running = !countdownRunning;
        if (Persistent.states.timer.countdown.running) {
            Persistent.states.timer.countdown.start = getCurrentTimeInSeconds() - (countdownDuration - countdownSecondsLeft);
        }
    }

    function resetCountdown() {
        Persistent.states.timer.countdown.running = false;
        Persistent.states.timer.countdown.duration = 0;
        countdownSecondsLeft = 0;
    }

    // Alarm
    // "YYYY-MM-DD HH:MM" (or with a T) as local time, or "HH:MM" today;
    // epoch seconds, or null.
    function parseAlarmTime(text) {
        const m = (text ?? "").trim().match(/^(?:(\d{4})-(\d{1,2})-(\d{1,2})[ T])?(\d{1,2}):(\d{2})$/);
        if (!m) return null;
        const now = new Date();
        const d = m[1] ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5])
            : new Date(now.getFullYear(), now.getMonth(), now.getDate(), +m[4], +m[5]);
        if (isNaN(d.getTime()) || +m[4] > 23 || +m[5] > 59) return null;
        return Math.floor(d.getTime() / 1000);
    }

    // The next time at or after `now` with the same wall-clock time as `at`
    // (stepping by calendar days, so it stays put across DST changes).
    function nextDaily(at, now) {
        const d = new Date(at * 1000);
        while (d.getTime() / 1000 <= now)
            d.setDate(d.getDate() + 1);
        return Math.floor(d.getTime() / 1000);
    }

    // Sets and enables the alarm. A daily alarm in the past moves to its next
    // time; a one-off alarm in the past is refused (false).
    function setAlarm(at, label, daily) {
        const now = getCurrentTimeInSeconds();
        if (daily)
            at = nextDaily(at, now);
        else if (at <= now)
            return false;
        root.dismissAlarm();
        alarm.at = at;
        alarm.label = label ?? "";
        alarm.daily = !!daily;
        alarm.snoozeUntil = 0;
        alarm.enabled = true;
        return true;
    }

    // On/off without changing the time; switching a passed one-off alarm on
    // fails (false): it needs a new date.
    function toggleAlarm() {
        if (alarm.enabled) {
            alarm.enabled = false;
            alarm.snoozeUntil = 0;
            return true;
        }
        if (alarm.at <= 0)
            return false;
        return root.setAlarm(alarm.at, alarm.label, alarm.daily);
    }

    function clearAlarm() {
        root.dismissAlarm();
        alarm.enabled = false;
        alarm.at = 0;
        alarm.label = "";
        alarm.daily = false;
        alarm.snoozeUntil = 0;
    }

    function checkAlarm() {
        if (root.alarmRinging || !Persistent.ready) return;
        const now = getCurrentTimeInSeconds();
        if (alarm.snoozeUntil > 0 && now >= alarm.snoozeUntil) {
            alarm.snoozeUntil = 0;
            root.ringAlarm();
            return;
        }
        if (!alarm.enabled || now < alarm.at) return;
        const late = now - alarm.at;
        // Schedule the next one before ringing this one.
        if (alarm.daily)
            alarm.at = nextDaily(alarm.at, now);
        else
            alarm.enabled = false;
        if (late > root.alarmMissedSeconds) {
            Quickshell.execDetached(["notify-send", "-a", "Shell", "Missed alarm",
                (alarm.label || Translation.tr("Alarm")) + " · " + Qt.formatDateTime(new Date((now - late) * 1000), Qt.locale().dateTimeFormat(Locale.ShortFormat))]);
            return;
        }
        root.ringAlarm();
    }

    function ringAlarm() {
        root.alarmRinging = true;
        root.alarmRingStart = getCurrentTimeInSeconds();
        alarmSound.running = true;
        alarmNotification.serverId = -1;
        alarmNotification.running = true;
    }

    function dismissAlarm() {
        if (!root.alarmRinging) return;
        root.alarmRinging = false;
        alarmSound.running = false;
        alarmNotification.close();
    }

    function snoozeAlarm() {
        root.dismissAlarm();
        alarm.snoozeUntil = getCurrentTimeInSeconds() + root.alarmSnoozeMinutes * 60;
    }

    Timer {
        id: alarmTimer
        interval: 1000
        running: root.alarmEnabled || root.alarmSnoozeUntil > 0 || root.alarmRinging
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.checkAlarm();
            if (root.alarmRinging && getCurrentTimeInSeconds() - root.alarmRingStart >= root.alarmRingSeconds)
                root.dismissAlarm();
        }
    }

    // The ringtone, played again each time it ends while ringing.
    Process {
        id: alarmSound
        command: Audio.ringtoneCommand(Audio.soundFor("alarm"))
        onExited: {
            if (root.alarmRinging)
                alarmSoundRestart.start();
        }
    }
    Timer {
        id: alarmSoundRestart
        interval: 400
        onTriggered: if (root.alarmRinging) alarmSound.running = true
    }

    // The notification, with Snooze / Dismiss: notify-send prints the
    // notification's id (-p), then the action clicked.
    Process {
        id: alarmNotification
        property int serverId: -1
        function close() {
            if (serverId > 0)
                Notifications.discardNotification(serverId + Notifications.idOffset);
            serverId = -1;
            running = false;
        }
        command: ["notify-send", "-a", "Shell", "-u", "critical", "-i", "alarm-clock", "-p",
            "--action=snooze=" + Translation.tr("Snooze %1 min").arg(root.alarmSnoozeMinutes),
            "--action=dismiss=" + Translation.tr("Dismiss"),
            root.alarmLabel || Translation.tr("Alarm"),
            Qt.formatDateTime(new Date(root.alarmRingStart * 1000), Config.options.time.format)]
        // Closed without an action (its close button): stop ringing too.
        // close() and the actions clear serverId first, so they don't land here.
        // Ids start at 1: notify-send prints 0 when no notification server
        // answered, and the alarm then keeps ringing.
        onExited: {
            if (serverId > 0 && root.alarmRinging) {
                serverId = -1;
                root.dismissAlarm();
            }
        }
        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (/^[0-9]+$/.test(text)) {
                    alarmNotification.serverId = parseInt(text);
                } else if (text === "snooze") {
                    alarmNotification.serverId = -1;
                    root.snoozeAlarm();
                } else if (text === "dismiss") {
                    alarmNotification.serverId = -1;
                    root.dismissAlarm();
                }
            }
        }
    }

    // `nixbook-shell ipc call timers …`: the timers widget's pomodoro,
    // stopwatch and countdown, for key bindings and the desktop MCP server.
    IpcHandler {
        target: "timers"

        function status(): string {
            root.refreshStopwatch();
            return JSON.stringify({
                pomodoro: { running: root.pomodoroRunning, isBreak: root.pomodoroBreak, cycle: root.pomodoroCycle, secondsLeft: root.pomodoroSecondsLeft },
                stopwatch: { running: root.stopwatchRunning, seconds: Math.floor(root.stopwatchTime / 100), laps: (root.stopwatchLaps ?? []).map(l => Math.floor(l / 100)) },
                countdown: { running: root.countdownRunning, secondsLeft: root.countdownSecondsLeft },
                alarm: { enabled: root.alarmEnabled, at: root.alarmAt > 0 ? new Date(root.alarmAt * 1000).toISOString() : "",
                    label: root.alarmLabel, daily: root.alarmDaily, ringing: root.alarmRinging,
                    snoozedUntil: root.alarmSnoozeUntil > 0 ? new Date(root.alarmSnoozeUntil * 1000).toISOString() : "" },
            });
        }
        function pomodoroToggle(): string {
            root.togglePomodoro();
            return `ok: pomodoro ${root.pomodoroRunning ? "running" : "paused"}`;
        }
        function pomodoroReset(): string {
            root.resetPomodoro();
            return "ok: pomodoro reset";
        }
        function stopwatchToggle(): string {
            root.toggleStopwatch();
            return `ok: stopwatch ${root.stopwatchRunning ? "running" : "paused"}`;
        }
        function stopwatchLap(): string {
            if (!root.stopwatchRunning)
                return "error: the stopwatch isn't running";
            root.refreshStopwatch();
            root.stopwatchRecordLap();
            return "ok: lap recorded";
        }
        function stopwatchReset(): string {
            root.stopwatchReset();
            return "ok: stopwatch reset";
        }
        // Adds minutes to the countdown and starts it if it was stopped.
        function countdownAdd(minutes: int): string {
            if (minutes <= 0 || minutes > 24 * 60)
                return "error: minutes must be between 1 and 1440";
            root.addCountdownMinutes(minutes);
            if (!root.countdownRunning)
                root.toggleCountdown();
            return `ok: countdown ${Math.ceil(Persistent.states.timer.countdown.duration / 60)} min`;
        }
        function countdownToggle(): string {
            if (root.countdownDuration <= 0)
                return "error: no countdown set (countdownAdd first)";
            root.toggleCountdown();
            return `ok: countdown ${root.countdownRunning ? "running" : "paused"}`;
        }
        function countdownReset(): string {
            root.resetCountdown();
            return "ok: countdown reset";
        }
        // `when`: a local date and time ("2026-12-24 07:30", "2026-12-24T07:30")
        // or a time today ("07:30"; daily: the next 07:30).
        function alarmSet(when: string, label: string, daily: bool): string {
            const at = root.parseAlarmTime(when);
            if (at === null)
                return `error: can't read "${when}" (YYYY-MM-DD HH:MM or HH:MM)`;
            if (!root.setAlarm(at, label, daily))
                return "error: that time has passed";
            return `ok: alarm at ${new Date(root.alarmAt * 1000).toString()}`;
        }
        function alarmToggle(): string {
            if (!root.toggleAlarm())
                return "error: the alarm's time has passed (alarmSet a new one)";
            return `ok: alarm ${root.alarmEnabled ? "on" : "off"}`;
        }
        function alarmClear(): string {
            root.clearAlarm();
            return "ok: alarm cleared";
        }
        function alarmDismiss(): string {
            if (!root.alarmRinging)
                return "error: the alarm isn't ringing";
            root.dismissAlarm();
            return "ok: alarm dismissed";
        }
        function alarmSnooze(): string {
            if (!root.alarmRinging)
                return "error: the alarm isn't ringing";
            root.snoozeAlarm();
            return `ok: snoozed ${root.alarmSnoozeMinutes} min`;
        }
    }
}
