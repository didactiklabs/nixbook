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
        // Arrived within the cut-in cooldown of another cut-in: a regular
        // popup instead (cutInCooldown).
        property bool cutInCooledDown: false
        // Its app replaced it in place (D-Bus replaces_id: KDE Connect
        // re-posting a phone notification, a chat thread updated): Quickshell
        // updates the Notification without a new `notification` signal, so
        // it arrives again as a new copy (root.arrive) and this one goes.
        property bool arrived: false
        property bool superseded: false
        onSummaryChanged: root.updated(wrapper)
        onBodyChanged: root.updated(wrapper)

        onNotificationChanged: {
            if (notification === null && !superseded) {
                root.discardNotification(notificationId);
            }
        }
    }

    // image://qsimage/… handles live only in the process that received the
    // notification: after a restart they are "unknown handle" errors, so they
    // are neither saved nor restored (the app icon shows instead).
    function persistableImage(image) {
        return (image ?? "").startsWith("image://qsimage/") ? "" : (image ?? "");
    }
    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": root.persistableImage(notif.image),
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        id: notifTimer
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            // Already discarded or replaced: it used to throw here and never
            // reach destroy(), leaking the timer.
            if (!notifObject) {
                destroy();
                return;
            }
            if (notifObject.timer === notifTimer) notifObject.timer = null; // destroyed below, not by destroyTimers()
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
    // The user acted on a notification (an action, a click), or dismissed
    // it: what the agent learns which apps matter from (Initiative.qml).
    signal acted(appName: string);
    signal dismissed(appName: string);
    property var _actedIds: ({})
    signal discardAll();
    signal timeout(id: var);
    // Notif objects that left the list are destroyed (they used to pile up
    // for the whole session), but only a while later: a popup's exit
    // animation or a queued cut-in may still hold one. `retiring` comes
    // first, for those that keep one longer to let go of it.
    signal retiring(notifs: var);
    property var _retired: []
    function retire(notifs) {
        if (notifs.length === 0) return;
        const now = Date.now();
        root._retired = [...root._retired, ...notifs.map(n => ({ notif: n, at: now }))];
    }
    Timer {
        interval: 60 * 1000
        repeat: true
        running: root._retired.length > 0
        onTriggered: {
            const cutoff = Date.now() - 10 * 60 * 1000;
            const due = root._retired.filter(r => r.at <= cutoff).map(r => r.notif)
                .filter(n => !root.list.some(l => l === n));
            root._retired = root._retired.filter(r => r.at > cutoff);
            if (due.length === 0) return;
            root.retiring(due);
            due.forEach(n => n.destroy());
        }
    }

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

        onNotification: (notification) => root.arrive(notification, null)
    }

    // Replaced in place: summary and body change together, so once per
    // update, after both. Progress (a `value` hint: a file transfer, a
    // download) just updates where it is, without a popup each time.
    property var _updated: []
    function updated(notif) {
        if (!notif.arrived || notif.superseded || !notif.notification || root._updated.includes(notif)) return;
        if (notif.hints?.value !== undefined) return;
        root._updated = [...root._updated, notif];
        Qt.callLater(root.arriveUpdates);
    }
    function arriveUpdates() {
        const updated = root._updated;
        root._updated = [];
        for (const notif of updated)
            if (!notif.superseded && notif.notification && root.list.includes(notif))
                root.arrive(notif.notification, notif);
    }

    // A notification arriving, or arriving again replaced in place
    // (`previous`: its copy in the list, which the new one replaces).
    function arrive(notification, previous) {
        const id = notification.id + root.idOffset;
        const duplicate = root.duplicateVerdict(notification, Date.now());
        if (duplicate.drop !== "") {
            console.log(`[Notifications] Dropped "${notification.appName}: ${notification.summary}" (${duplicate.drop})`);
            if (previous) root.discardNotifications([id], true);
            else notification.expire();
            return;
        }
        // Its earlier copy is replaced here, not discarded: that would close
        // the notification itself.
        const replaces = duplicate.replaces.filter(r => r !== id);
        const supersedes = previous ? [...duplicate.supersedes.filter(r => r !== id), id] : duplicate.supersedes;
        notification.tracked = true
        const newNotifObject = notifComponent.createObject(root, {
            "notificationId": id,
            "notification": notification,
            "time": Date.now(),
            "replaces": supersedes,
        });
        const replaced = (root.dedupOptions?.history ?? true)
            ? root.recent.filter(r => supersedes.includes(r.notificationId)) : [];
        root.remember(newNotifObject);
        if (previous) {
            previous.superseded = true;
            newNotifObject.read = previous.read;
            root.destroyTimers([previous]);
            root.list = [...root.list.filter(n => n !== previous), newNotifObject];
            root.retire([previous]);
        } else {
            root.list = [...root.list, newNotifObject];
        }

        // Quiet (Settings → Notifications → Quiet): no popup, cut-in or
        // chime, only the notification centre and the history.
        const quiet = root.quietRule(newNotifObject);
        if (quiet !== "")
            console.log(`[Notifications] Quiet "${notification.appName}: ${notification.summary}" (${quiet})`);
        else if (!root.silent)
            root.cutInCooldown(newNotifObject);

        // Popup
        if (!root.popupInhibited && quiet === "") {
            newNotifObject.popup = true;
            // Messages (Settings → Notifications → Keep on screen) stay until
            // dismissed: no expiry timer at all.
            if (notification.expireTimeout != 0 && !root.staysOnScreen(newNotifObject)) {
                newNotifObject.timer = notifTimerComponent.createObject(root, {
                    "notificationId": newNotifObject.notificationId,
                    "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                });
            }
            if (newNotifObject.read) {
                newNotifObject.read = false;
                root.unread++;
            }
        }
        newNotifObject.arrived = true;
        NotificationHistory.record(newNotifObject,
            quiet !== "" ? "" : (v => v.cutIn ? v.reason : "")(root.cutInVerdict(newNotifObject)),
            replaced.map(r => ({ id: r.notificationId, time: r.time })));
        // notify first: a cut-in plays its own sound, and the chime then
        // falls within the 300 ms gap instead of doubling it. Before
        // discarding what it replaces, so a cut-in on screen for the old
        // copy is updated in place instead of leaving and coming back.
        if (quiet === "")
            root.notify(newNotifObject);
        if (replaces.length > 0) {
            console.log(`[Notifications] "${notification.appName}: ${notification.summary}" replaces ${replaces.join(", ")}`);
            root.discardNotifications(replaces, true);
        }
        if (quiet === "")
            root.playNotificationSound(notification);
        // console.log(notifToString(newNotifObject));
        notifFileView.setText(stringifyList(root.list));
    }

    // Notification chime (Settings → General → Sounds; the theme's on themes
    // with their own sounds: Audio.soundFor). Skipped in Do Not
    // Disturb, for senders asking for silence (`suppress-sound` hint) and
    // within 300 ms of the last one so a burst doesn't stack up.
    property real lastSoundTime: 0
    function playNotificationSound(notification) {
        if (!(Config.options?.sounds?.notification ?? false) || root.silent) return;
        if (notification?.hints?.["suppress-sound"] ?? false) return;
        const now = Date.now();
        if (now - root.lastSoundTime < 300) return;
        root.lastSoundTime = now;
        Audio.playRingtone(Audio.soundFor("notification"));
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
        Audio.playSoundFile(file !== "" ? file : Themes.sound("critical"));
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
        const discarded = root.list.filter((notif) => idSet.has(notif.notificationId));
        const discardedUnread = discarded.filter((notif) => !notif.read).length;
        if (!expired)
            for (const notif of discarded) {
                if (root._actedIds[notif.notificationId]) delete root._actedIds[notif.notificationId];
                else root.dismissed(notif.appName);
            }
        if (discardedUnread > 0)
            root.unread = Math.max(0, root.unread - discardedUnread);
        root.destroyTimers(discarded);
        if (remaining.length !== root.list.length) {
            root.list = remaining;
            notifFileView.setText(stringifyList(root.list));
        }
        root.retire(discarded);
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
    //  - a mirrored copy of a desktop notification: dropped, unless the
    //    desktop title is only the phone app's name (Instagram in the
    //    browser, no sender): then the mirrored copy replaces it, and a
    //    desktop copy arriving after it is dropped (relayIsRicher);
    //  - a mirrored copy whose newest message is the user's own ("You:"),
    //    with `hideOwnMessages`: dropped;
    //  - a mirrored thread holding a desktop notification's message and
    //    newer lines: replaces it (one entry for the conversation);
    //  - a desktop notification whose mirrored copy came first: replaces it;
    //  - the same app, title and text again within `repeatWindow` s (a
    //    sender repeating itself): dropped;
    //  - the same app and title re-posted with lines appended (a phone
    //    mirroring the whole chat thread each time, its "(N messages)" count
    //    ignored): replaces the old one.
    // Matching: NotificationUtils.relayMatch / isOwnMessage / isRepeatOf /
    // isThreadUpdateOf.
    function duplicateVerdict(n, now) {
        const verdict = { drop: "", replaces: [], supersedes: [] };
        const options = root.dedupOptions;
        if (!(options?.enable ?? true)) return verdict;
        const windowMs = Math.max(0, options?.window ?? 1800) * 1000;
        root.recent = root.recent.filter(r => now - r.time <= windowMs);
        const relayed = NotificationUtils.isRelayed(n, options?.relayApps);
        const repeatMs = Math.max(0, options?.repeatWindow ?? 2) * 1000;
        if (relayed && (options?.hideOwnMessages ?? true) && NotificationUtils.isOwnMessage(n))
            return { drop: "the user's own message", replaces: [], supersedes: [] };
        for (const r of [...root.recent].reverse()) {
            if (NotificationUtils.isRepeatOf(n, r)) {
                if (now - r.time <= repeatMs)
                    return { drop: `repeat of #${r.notificationId}`, replaces: [], supersedes: [] };
                // The same notification again later in the window (a web
                // app's "You have unseen notifications." every minute, a
                // phone re-posting a message): it replaces the earlier copy.
                verdict.supersedes.push(r.notificationId);
                continue;
            }
            if (relayed && !r.relayed) {
                const match = NotificationUtils.relayMatch(r, n);
                if (match === "same" && !NotificationUtils.relayIsRicher(r, n))
                    return { drop: `mirrors ${r.appName} #${r.notificationId}`, replaces: [], supersedes: [] };
                if (match !== "") {
                    verdict.supersedes.push(r.notificationId);
                    continue;
                }
            }
            if (!relayed && r.relayed && NotificationUtils.isRelayOf(n, r)) {
                if (NotificationUtils.relayIsRicher(n, r))
                    return { drop: `${r.appName} #${r.notificationId} names the sender`, replaces: [], supersedes: [] };
                verdict.supersedes.push(r.notificationId);
            } else if (NotificationUtils.isThreadUpdateOf(n, r))
                verdict.supersedes.push(r.notificationId);
        }
        verdict.replaces = verdict.supersedes.filter(id => root.list.some(notif => notif.notificationId === id));
        return verdict;
    }

    // A popup's expiry timer paused by hovering (or never started) destroys
    // itself only when it fires: discarding the notification first leaked it.
    function destroyTimers(notifs) {
        notifs.forEach((notif) => {
            if (notif.timer == null) return;
            const timer = notif.timer;
            notif.timer = null;
            timer.stop();
            timer.destroy();
        });
    }

    function discardAllNotifications() {
        const discarded = root.list.slice(0);
        root.destroyTimers(discarded);
        root.list = []
        root.retire(discarded);
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

    // The quiet rule `n` matches ("app \"x\"" or the rule), "" = none.
    function quietRule(n) {
        const rules = Config.options?.notifications?.quiet;
        if (!n || !(rules?.enable ?? false)) return "";
        const app = (n.appName ?? "").toLowerCase();
        if ((rules.apps ?? []).some(a => a.toLowerCase() === app)) return `app "${n.appName}"`;
        return NotificationUtils.firstMatchingRule(n, rules.keywords);
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

    // Cut-in cooldown (notifications.cutIn.cooldown s, 0 = off): after a
    // cut-in, the next ones within the cooldown are regular popups, so a
    // burst of messages doesn't chain cut-ins. A newer copy of the last
    // cut-in (a thread re-posted, mergeUpdates) still updates it in place.
    // Decided once, on arrival: `n.cutInCooledDown`.
    property var lastCutIn: ({ id: -1, time: 0 })
    function cutInCooldown(n) {
        if (!root.cutInVerdict(n).cutIn) return;
        const now = n.time;
        if ((n.replaces ?? []).includes(root.lastCutIn.id)) {
            root.lastCutIn = { id: n.notificationId, time: root.lastCutIn.time };
            return;
        }
        const cooldownMs = Math.max(0, Config.options?.notifications?.cutIn?.cooldown ?? 10) * 1000;
        if (now - root.lastCutIn.time < cooldownMs) {
            n.cutInCooledDown = true;
            return;
        }
        root.lastCutIn = { id: n.notificationId, time: now };
    }

    // Persona cut-in decision (Settings → Notifications → Persona cut-in):
    // { cutIn, reason }. A blacklist rule vetoes everything; otherwise
    // critical urgency, a chosen app or a keyword rule gives a cut-in,
    // unless it came within the cooldown of the last one.
    // Rule syntax ("Victor + Instagram", "!x", "app:x", "\"word\""):
    // NotificationUtils.ruleMatches.
    function cutInVerdict(n) {
        const rules = Config.options?.notifications?.cutIn ?? {};
        if (!n) return { cutIn: false, reason: "" };
        if (!(rules.enable ?? true)) return { cutIn: false, reason: "cut-ins off" };
        const blocked = NotificationUtils.firstMatchingRule(n, rules.blacklist);
        if (blocked) return { cutIn: false, reason: `blacklist "${blocked}"` };
        if (n.cutInCooledDown) return { cutIn: false, reason: "cooldown" };
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
                root._actedIds[id] = true;
                root.acted(root.list.find(n => n.notificationId === id)?.appName ?? "");
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
                root.retire(root.list.slice(0))
                root.list = JSON.parse(fileContents).map((notif) => {
                    return notifComponent.createObject(root, {
                        "notificationId": notif.notificationId,
                        "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                        "appIcon": notif.appIcon,
                        "appName": notif.appName,
                        "body": notif.body,
                        "image": root.persistableImage(notif.image),
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
