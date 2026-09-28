pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        // Counted in `unread` (popped up and not yet seen). Not persisted.
        property bool read: true
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        // Raw hints (desktop-entry, x-kde-origin-name, …): the only place some
        // apps/browsers say where a notification comes from. Not persisted.
        property var hints: notification?.hints ?? ({})
        // Inline reply (the app asked for a typed answer; live only).
        readonly property bool hasInlineReply: notification?.hasInlineReply ?? false
        readonly property string inlineReplyPlaceholder: notification?.inlineReplyPlaceholder ?? ""
        property Timer timer
        // Ids of the earlier copies this one supersedes (duplicateVerdict):
        // a thread re-post, or the desktop copy of a phone-mirrored message.
        property var replaces: []

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    // One single-notification "group" per popup (notifications.splitPopups),
    // keyed by app name + id so it sorts and diffs like the grouped lists.
    function separateGroupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            groups[`${notif.appName}\u0001${notif.notificationId}`] = {
                appName: notif.appName,
                appIcon: notif.appIcon,
                notifications: [notif],
                time: notif.time
            };
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: (Config.options?.notifications?.splitPopups ?? false)
        ? separateGroupsForList(root.popupList) : groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        inlineReplySupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            const duplicate = root.duplicateVerdict(notification, Date.now());
            if (duplicate.drop !== "") {
                console.log(`[Notifications] Dropped "${notification.appName}: ${notification.summary}" (${duplicate.drop})`);
                notification.expire();
                return;
            }
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
                "replaces": duplicate.supersedes,
            });
            const replaced = (root.dedupOptions?.history ?? true)
                ? root.recent.filter(r => duplicate.supersedes.includes(r.notificationId)) : [];
            root.remember(newNotifObject);
			root.list = [...root.list, newNotifObject];

            // Popup
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                // Messages (Settings → Notifications → Keep on screen) stay until
                // dismissed: no expiry timer at all.
                if (notification.expireTimeout != 0 && !root.staysOnScreen(newNotifObject)) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
                newNotifObject.read = false;
                root.unread++;
            }
            NotificationHistory.record(newNotifObject, (v => v.cutIn ? v.reason : "")(root.cutInVerdict(newNotifObject)),
                replaced.map(r => ({ id: r.notificationId, time: r.time })));
            // notify first: a cut-in plays its own sound, and the chime then
            // falls within the 300 ms gap instead of doubling it. Before
            // discarding what it replaces, so a cut-in on screen for the old
            // copy is updated in place instead of leaving and coming back.
            root.notify(newNotifObject);
            if (duplicate.replaces.length > 0) {
                console.log(`[Notifications] "${notification.appName}: ${notification.summary}" replaces ${duplicate.replaces.join(", ")}`);
                root.discardNotifications(duplicate.replaces, true);
            }
            root.playNotificationSound(notification);
            // console.log(notifToString(newNotifObject));
            notifFileView.setText(stringifyList(root.list));
        }
    }

    // Notification chime (Settings → General → Sounds). Skipped in Do Not
    // Disturb, for senders asking for silence (`suppress-sound` hint) and
    // within 300 ms of the last one so a burst doesn't stack up.
    property real lastSoundTime: 0
    function playNotificationSound(notification) {
        if (!(Config.options?.sounds?.notification ?? false) || root.silent) return;
        if (notification?.hints?.["suppress-sound"] ?? false) return;
        const now = Date.now();
        if (now - root.lastSoundTime < 300) return;
        root.lastSoundTime = now;
        const file = Config.options.sounds.notificationFile;
        Audio.playSoundFile(file !== "" ? file : `${Directories.assetsPath}/sounds/persona5-notification.mp3`);
    }

    // Persona cut-in sound (notifications.cutIn.sound/soundFile), played by
    // PersonaCutIn when a cut-in shows — even with the chime off. Counts as
    // the chime for the 300 ms gap.
    function playCutInSound(notification) {
        const rules = Config.options?.notifications?.cutIn;
        if (!(rules?.sound ?? true) || root.silent) return;
        if (notification?.hints?.["suppress-sound"] ?? false) return;
        root.lastSoundTime = Date.now();
        const file = rules?.soundFile ?? "";
        Audio.playSoundFile(file !== "" ? file : `${Directories.assetsPath}/sounds/persona5-cut-in.mp3`);
    }

    function markAllRead() {
        root.unread = 0;
        root.list.forEach((notif) => notif.read = true);
    }

    // How the reply button answers `notif` (null: no reply button):
    // { kind: "inline" } — type the reply in the card (the app asked for it),
    // { kind: "action", identifier } — the app's own Reply action,
    // { kind: "open", identifier: "default" } — a message (Keep on screen
    // rules) whose default action opens the conversation in the app.
    function replyMethod(notif) {
        if (!notif?.notification) return null; // from history: no longer live
        if (notif.hasInlineReply) return { kind: "inline" };
        const action = (notif.actions ?? []).find((a) =>
            /^(quick.?)?reply$|reply/i.test(a.identifier) || /^reply$|répondre|antworten/i.test(a.text));
        if (action) return { kind: "action", identifier: action.identifier };
        if (root.staysOnScreen(notif) && (notif.actions ?? []).some((a) => a.identifier === "default"))
            return { kind: "open", identifier: "default" };
        return null;
    }

    // Send a typed inline reply; the notification counts as read.
    function sendReply(id, text) {
        const notif = root.list.find((n) => n.notificationId === id);
        if (!notif?.notification || !notif.hasInlineReply || text.trim().length === 0) return false;
        notif.notification.sendInlineReply(text);
        root.markRead([id]);
        return true;
    }

    // Popups with an open reply box: the popup layer takes the keyboard.
    property int replyingPopups: 0

    // The app's own "mark as read" action, if it offers one (mail and chat
    // clients do): invoking it marks the message read in the app too.
    function markReadAction(notif) {
        return (notif?.actions ?? []).find((a) =>
            /mark.?(as.?)?read|^read$/i.test(a.identifier) || /mark.?(as.?)?read/i.test(a.text)) ?? null;
    }

    // Mark as read (popup button): no longer counted as unread, popup hidden
    // (still in the notification centre), and the app's mark-as-read action
    // invoked when there is one.
    function markRead(ids) {
        const idSet = new Set(ids);
        root.list.forEach((notif) => {
            if (!idSet.has(notif.notificationId)) return;
            if (!notif.read) {
                notif.read = true;
                root.unread = Math.max(0, root.unread - 1);
            }
            const action = root.markReadAction(notif);
            if (action) {
                notifServer.trackedNotifications.values
                    .find((n) => n.id + root.idOffset === notif.notificationId)
                    ?.actions.find((a) => a.identifier === action.identifier)
                    ?.invoke();
            }
            root.timeoutNotification(notif.notificationId);
        });
    }

    function discardNotification(id) {
        root.discardNotifications([id]);
    }

    // `expired`: close them as expired rather than dismissed by the user
    // (duplicates replaced by another copy).
    function discardNotifications(ids, expired = false) {
        console.log("[Notifications] Discarding notifications with IDs: " + ids.join(", "));
        const idSet = new Set(ids);
        // Assign a new array instead of splicing: on a list<> property, splice()
        // shifts the following elements one by one and emits listChanged for each,
        // re-running the grouping and every model bound to the list each time.
        const remaining = root.list.filter((notif) => !idSet.has(notif.notificationId));
        const discardedUnread = root.list.filter((notif) => idSet.has(notif.notificationId) && !notif.read).length;
        if (discardedUnread > 0)
            root.unread = Math.max(0, root.unread - discardedUnread);
        if (remaining.length !== root.list.length) {
            root.list = remaining;
            notifFileView.setText(stringifyList(root.list));
        }
        notifServer.trackedNotifications.values
            .filter((notif) => idSet.has(notif.id + root.idOffset))
            .forEach((notif) => expired ? notif.expire() : notif.dismiss());
        ids.forEach((id) => root.discard(id)); // Emit signal
    }

    // Duplicates (Settings → Notifications → Duplicates). The same message
    // often arrives twice: from the desktop app and mirrored from the phone
    // (KDE Connect: appName "KDE Connect", title = the phone app). The
    // desktop copy wins — it has the app's actions, reply and icon.
    // Notifications of the last `window` seconds, dismissed or not:
    // { notificationId, time, appName, summary, body, relayed }.
    property var recent: []
    readonly property var dedupOptions: Config.options?.notifications?.deduplicate

    function remember(notif) {
        if (!(root.dedupOptions?.enable ?? true)) return;
        root.recent = [...root.recent, {
            notificationId: notif.notificationId,
            time: notif.time,
            appName: notif.appName,
            summary: notif.summary,
            body: notif.body,
            relayed: NotificationUtils.isRelayed(notif, root.dedupOptions?.relayApps),
        }];
    }

    // What to do with incoming `n`: { drop, replaces, supersedes }. drop =
    // why it is not shown ("" = show it); supersedes = ids of the earlier
    // copies it supersedes, replaces = those still in the list.
    //  - a mirrored copy of a desktop notification: dropped;
    //  - a desktop notification whose mirrored copy came first: replaces it;
    //  - the same app, title and text again within `repeatWindow` s (a
    //    sender repeating itself): dropped;
    //  - the same app and title re-posted with lines appended (a phone
    //    mirroring the whole chat thread each time): replaces the old one.
    // Matching: NotificationUtils.isRelayOf / isRepeatOf / isThreadUpdateOf.
    function duplicateVerdict(n, now) {
        const verdict = { drop: "", replaces: [], supersedes: [] };
        const options = root.dedupOptions;
        if (!(options?.enable ?? true)) return verdict;
        const windowMs = Math.max(0, options?.window ?? 1800) * 1000;
        root.recent = root.recent.filter(r => now - r.time <= windowMs);
        const relayed = NotificationUtils.isRelayed(n, options?.relayApps);
        const repeatMs = Math.max(0, options?.repeatWindow ?? 2) * 1000;
        for (const r of [...root.recent].reverse()) {
            if (now - r.time <= repeatMs && NotificationUtils.isRepeatOf(n, r))
                return { drop: `repeat of #${r.notificationId}`, replaces: [], supersedes: [] };
            if (relayed && !r.relayed && NotificationUtils.isRelayOf(r, n))
                return { drop: `mirrors ${r.appName} #${r.notificationId}`, replaces: [], supersedes: [] };
            if ((!relayed && r.relayed && NotificationUtils.isRelayOf(n, r))
                    || NotificationUtils.isThreadUpdateOf(n, r))
                verdict.supersedes.push(r.notificationId);
        }
        verdict.replaces = verdict.supersedes.filter(id => root.list.some(notif => notif.notificationId === id));
        return verdict;
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null && root.list[index].timer != null)
            root.list[index].timer.stop();
    }

    // Does this notification's popup stay until dismissed? App name (exact) or
    // keywords in the app name / title / string hints — not the message text,
    // so a message merely mentioning "Discord" doesn't stick around.
    function staysOnScreen(n) {
        const rules = Config.options?.notifications?.persistent;
        if (!n || !(rules?.enable ?? false)) return false;
        const app = (n.appName ?? "").toLowerCase();
        if ((rules.apps ?? []).some(a => a.toLowerCase() === app)) return true;
        const hints = n.hints ?? {};
        const text = `${n.appName ?? ""} ${n.summary ?? ""} ${Object.keys(hints).map(k => typeof hints[k] === "string" ? hints[k] : "").join(" ")}`.toLowerCase();
        return (rules.keywords ?? []).some(k => k.trim().length > 0 && text.includes(k.trim().toLowerCase()));
    }

    // Persona cut-in decision (Settings → Notifications → Persona cut-in):
    // { cutIn, reason }. A blacklist rule vetoes everything; otherwise
    // critical urgency, a chosen app or a keyword rule gives a cut-in.
    // Rule syntax ("Victor + Instagram", "!x", "app:x", "\"word\""):
    // NotificationUtils.ruleMatches.
    function cutInVerdict(n) {
        const rules = Config.options?.notifications?.cutIn ?? {};
        if (!n) return { cutIn: false, reason: "" };
        if (!(rules.enable ?? true)) return { cutIn: false, reason: "cut-ins off" };
        const blocked = NotificationUtils.firstMatchingRule(n, rules.blacklist);
        if (blocked) return { cutIn: false, reason: `blacklist "${blocked}"` };
        if ((rules.critical ?? true) && (n.urgency == NotificationUrgency.Critical || n.urgency === "critical"))
            return { cutIn: true, reason: "critical" };
        const app = (n.appName ?? "").toLowerCase();
        if ((rules.apps ?? []).some(a => a.toLowerCase() === app)) return { cutIn: true, reason: `app "${n.appName}"` };
        const keyword = NotificationUtils.firstMatchingRule(n, rules.keywords);
        if (keyword) return { cutIn: true, reason: `keyword "${keyword}"` };
        return { cutIn: false, reason: "" };
    }

    // Restart a popup's expiry countdown (after hovering it paused the timer).
    function resumeTimeout(id) {
        const notif = root.list.find((notif) => notif.notificationId === id);
        if (notif?.timer != null)
            notif.timer.restart();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    // Invoke an action and keep the notification (attemptInvokeAction below
    // discards it).
    function invokeAction(id, identifier) {
        const action = notifServer.trackedNotifications.values
            .find((n) => n.id + root.idOffset === id)
            ?.actions.find((a) => a.identifier === identifier);
        if (!action) return false;
        action.invoke();
        return true;
    }

    // Reply button without an inline reply: run the reply/default action,
    // then treat the notification as read (kept in the centre).
    function replyViaApp(id) {
        const notif = root.list.find((n) => n.notificationId === id);
        const method = root.replyMethod(notif);
        if (!method || method.kind === "inline") return;
        root.invokeAction(id, method.identifier);
        root.markRead([id]);
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            if (action) {
                action.invoke();
            } else {
                console.warn("[Notifications] Action not found:", notifIdentifier);
            }
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            try {
                const fileContents = notifFileView.text()
                root.list = JSON.parse(fileContents).map((notif) => {
                    return notifComponent.createObject(root, {
                        "notificationId": notif.notificationId,
                        "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                        "appIcon": notif.appIcon,
                        "appName": notif.appName,
                        "body": notif.body,
                        "image": notif.image,
                        "summary": notif.summary,
                        "time": notif.time,
                        "urgency": notif.urgency,
                    });
                });
                // Find largest notificationId
                let maxId = 0
                root.list.forEach((notif) => {
                    maxId = Math.max(maxId, notif.notificationId)
                })

                console.log("[Notifications] File loaded")
                root.idOffset = maxId
                root.initDone()
            } catch (e) {
                console.error("[Notifications] Failed to parse notifications file, resetting:", e)
                root.list = []
                notifFileView.setText(stringifyList(root.list))
                root.idOffset = 0
                root.initDone()
            }
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
