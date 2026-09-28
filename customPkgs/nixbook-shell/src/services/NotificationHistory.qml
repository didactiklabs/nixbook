pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Notification history: every notification as it arrived, kept after it is
 * dismissed from the notification centre (Notifications.list only holds the
 * undismissed ones). Entries older than notifications.history.retentionDays
 * (0 = forever) are pruned on load, on each new entry and hourly.
 * Stored in ~/.local/state/…/user/notification-history.json, oldest first.
 */
Singleton {
    id: root
    readonly property var options: Config.options?.notifications?.history
    readonly property bool enabled: root.options?.enable ?? true
    readonly property int retentionDays: root.options?.retentionDays ?? 30
    // Safety cap so the file (rewritten on each entry) stays small.
    readonly property int maxEntries: 5000
    readonly property real dayMs: 24 * 60 * 60 * 1000

    // { id, time, appName, appIcon, summary, body, urgency, cutIn }
    property var entries: []
    property bool loaded: false
    property var pending: [] // recorded before the file finished loading

    function countOlderThan(days) {
        const cutoff = Date.now() - days * root.dayMs;
        return root.entries.filter(e => e.time < cutoff).length;
    }

    // Called by Notifications for each incoming notification; `cutIn` is the
    // cut-in rule that matched ("" = none). `replaced`: [{ id, time }] of the
    // earlier copies it supersedes (a chat thread re-posted with a new
    // message, a phone copy of the same message), dropped from the history
    // so each message is logged once.
    function record(notif, cutIn, replaced) {
        if (!root.enabled || !notif || notif.isTransient) return;
        const entry = {
            id: notif.notificationId,
            time: notif.time,
            appName: notif.appName,
            appIcon: notif.appIcon,
            summary: notif.summary,
            body: notif.body,
            urgency: notif.urgency,
            cutIn: cutIn ?? "",
        };
        const isReplaced = e => (replaced ?? []).some(r => r.id === e.id && r.time === e.time);
        if (!root.loaded) {
            root.pending = [...root.pending.filter(e => !isReplaced(e)), entry];
            return;
        }
        root.save(root.pruned([...root.entries.filter(e => !isReplaced(e)), entry]));
    }

    function deleteOlderThan(days) {
        const cutoff = Date.now() - days * root.dayMs;
        root.save(root.entries.filter(e => e.time >= cutoff));
    }
    function deleteEntry(id, time) {
        root.save(root.entries.filter(e => !(e.id === id && e.time === time)));
    }
    function clear() {
        root.save([]);
    }

    function pruned(list) {
        let kept = list;
        if (root.retentionDays > 0) {
            const cutoff = Date.now() - root.retentionDays * root.dayMs;
            kept = kept.filter(e => e.time >= cutoff);
        }
        return kept.length > root.maxEntries ? kept.slice(kept.length - root.maxEntries) : kept;
    }
    function prune() {
        if (!root.loaded) return;
        const kept = root.pruned(root.entries);
        if (kept.length !== root.entries.length) root.save(kept);
    }
    function save(list) {
        root.entries = list;
        saveTimer.restart();
    }

    onRetentionDaysChanged: root.prune()

    // Batch bursts of notifications into one write.
    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: historyFileView.setText(JSON.stringify(root.entries))
    }
    Timer {
        interval: 60 * 60 * 1000
        running: root.loaded
        repeat: true
        onTriggered: root.prune()
    }

    Component.onCompleted: historyFileView.reload()

    // `nixbook-shell ipc call notificationHistory count|clear|deleteOlderThan 7`
    IpcHandler {
        target: "notificationHistory"
        function count(): int { return root.entries.length; }
        function clear(): void { root.clear(); }
        function deleteOlderThan(days: int): void { root.deleteOlderThan(days); }
    }

    FileView {
        id: historyFileView
        path: Qt.resolvedUrl(Directories.notificationHistoryPath)
        function finishLoad(list) {
            root.loaded = true;
            root.entries = list;
            const merged = root.pruned([...list, ...root.pending]);
            root.pending = [];
            if (merged.length !== list.length || merged.some((e, i) => e !== list[i])) root.save(merged);
        }
        onLoaded: {
            let list = [];
            try {
                list = JSON.parse(historyFileView.text());
                if (!Array.isArray(list)) list = [];
            } catch (e) {
                console.error("[NotificationHistory] Failed to parse history file, resetting:", e);
            }
            finishLoad(list);
        }
        onLoadFailed: (error) => {
            if (error != FileViewError.FileNotFound)
                console.log("[NotificationHistory] Error loading file: " + error);
            finishLoad([]);
        }
    }
}
