pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

/**
 * The mesh: a few people's desktops talking through an ntfy server on the
 * internet (`nixbook-mesh`, scripts/mesh.py). Messages to everyone or to one
 * person, everyone's status (free, in a meeting, gaming, busy, do not
 * disturb, away), read receipts. Everything is end-to-end encrypted with the
 * mesh's key (every member holds it); the server only relays ciphertext.
 *
 * Set up in Settings > Mesh: the server (mesh.server), your
 * access token (keyring), then create a mesh or enter a member's mesh code.
 * Members appear when they first say something or share their status.
 *
 * Files (images and GIFs shown in the conversation, any other file as a
 * card): encrypted and uploaded by `nixbook-mesh sendfile`, downloaded as
 * soon as their message arrives (`fetch`: the server deletes them after a
 * while) into ~/.local/share/nixbook-shell/mesh/files/.
 *
 * Profile pictures: this desktop's account picture (UserAvatar) goes to
 * the others (`nixbook-mesh profile`, again when it changes, and once a
 * month; mesh.shareAvatar), theirs are downloaded like files (avatarOf).
 * Reactions: an emoji on any message (react), shown under it; a reaction
 * to your own message notifies.
 *
 * Nudges: a quick message from the Mesh tab's ✨ picker (nudges: an id,
 * an emoji and a line) carries its id (`quick`); the other side shows it as
 * its own cut-in (modules/ii/notificationPopup/MeshNudge.qml, `nudged`)
 * instead of a notification, when it can (mesh.nudgeCutIn; not locked, Do
 * Not Disturb, a fullscreen window; the Mesh tab open or not).
 * Back after being away (the listener catching up after this desktop was
 * off or offline, a nudge sent over 10 minutes ago, or one that came while
 * the screen was locked): one "welcome back" cut-in instead (`welcomed`),
 * each sender's nudges grouped with a count, shown once.
 *
 * Deleting: your own messages for everyone (deleteForEveryone: each desktop
 * puts "deleted" in its place, its file, notification and history entry go;
 * scripts/mesh.py "Deleting" says why nobody can delete someone else's),
 * anyone's for this desktop only (deleteForMe).
 *
 * The conversation is kept in ~/.local/state/quickshell/user/
 * mesh-conversation.json (the last 500 messages). Its view is the right sidebar's
 * Mesh tab; the bar's `mesh` widget shows who is around.
 */
Singleton {
    id: root

    readonly property string bin: "nixbook-mesh"
    readonly property string server: (Config.options?.mesh?.server ?? "").trim().replace(/\/+$/, "")
    readonly property bool enabled: Config.options?.mesh?.enable ?? true
    readonly property bool sharePresence: Config.options?.mesh?.sharePresence ?? true
    readonly property bool shareAvatar: Config.options?.mesh?.shareAvatar ?? true
    // Nudges (the Mesh tab's ✨ picker): { id, emoji, text }. The id travels
    // with the message (`quick`) and the receiver shows its own words for
    // it; an unknown id (a newer sender) shows the text sent.
    readonly property var nudges: [
        { id: "love", emoji: "❤️", text: Translation.tr("Love you") },
        { id: "thinking", emoji: "💭", text: Translation.tr("Thinking of you") },
        { id: "miss", emoji: "🥺", text: Translation.tr("Miss you") },
        { id: "hug", emoji: "🤗", text: Translation.tr("Sending you a hug") },
        // Its cut-in pats the receiver's own picture (MeshNudge.qml).
        { id: "pet", emoji: "🫳", text: Translation.tr("Head pats") },
        { id: "kiss", emoji: "😘", text: Translation.tr("A kiss") },
        { id: "wave", emoji: "👋", text: Translation.tr("Hey!") },
        { id: "morning", emoji: "☀️", text: Translation.tr("Good morning") },
        { id: "night", emoji: "🌙", text: Translation.tr("Good night") },
        { id: "onmyway", emoji: "🏃", text: Translation.tr("On my way") },
        { id: "callme", emoji: "📞", text: Translation.tr("Call me when you can?") },
        { id: "coffee", emoji: "☕", text: Translation.tr("Coffee break?") },
        { id: "food", emoji: "🍜", text: Translation.tr("Hungry? Let's eat") },
        { id: "game", emoji: "🎮", text: Translation.tr("Up for a game?") },
        { id: "proud", emoji: "🌟", text: Translation.tr("Proud of you") },
        { id: "laugh", emoji: "😂", text: Translation.tr("Haha") }
    ]
    function nudgeOf(id) {
        return root.nudges.find(n => n.id === id) ?? null;
    }
    // A nudge arrived and can be shown as its cut-in (MeshNudge.qml):
    // { mid, from, name, to, time, text, quick }.
    signal nudged(var message)
    // Whether a nudge now gets its cut-in, else a notification: not locked,
    // on Do Not Disturb, while an agent works, nor for one from long ago.
    // With the Mesh tab open (even on its conversation) it does, and over a
    // fullscreen window (a film) too: a nudge is meant to be seen, its card
    // is small and never takes the keyboard, and the message's own cut-in
    // showed there anyway, in its place.
    function _nudgeCutInNow(m) {
        if (!(Config.options?.mesh?.nudgeCutIn ?? true) || !root.nudgeOf(m.quick)) return false;
        if (GlobalStates.screenLocked || Notifications.silent || MakeWay.active) return false;
        return Date.now() - m.time <= 10 * 60 * 1000;
    }
    // -- Welcome back --------------------------------------------------------------
    // Nudges that came while this desktop wasn't there — the listener just
    // (re)connected and catches up, one sent over 10 minutes ago, or the
    // screen locked — make one "welcome back" cut-in once the screen can
    // show it (unlocked, not Do Not Disturb, no agent at work, booted), 3 s
    // after the last of them: each sender's nudges of a kind grouped with a
    // count (MeshNudge.qml), not a cut-in nor a notification each. A nudge
    // held for it carries `welcome`, then `greeted` once shown or read in the
    // Mesh tab first: a restart before it shows still shows it, and it never
    // shows twice. Older than a week: unread only.
    // groups: [{ from, name, quick, emoji, text, to, conv, count, time }],
    // the latest first.
    signal welcomed(var groups)
    property real _connectedAt: 0
    property bool _welcomeWaiting: false
    function _welcomeBlocked() {
        return GlobalStates.screenLocked || Notifications.silent || MakeWay.active || Preloader.booting;
    }
    Timer {
        id: welcomeSoon
        interval: 3000
        onTriggered: root._flushWelcome()
    }
    Timer {
        // Held back (locked, Do Not Disturb…): tried again.
        interval: 5000
        repeat: true
        running: root._welcomeWaiting
        onTriggered: root._flushWelcome()
    }
    function _flushWelcome() {
        const held = MeshWelcome.heldIds(root.messages);
        if (held.length === 0) {
            root._welcomeWaiting = false;
            return;
        }
        if (root._welcomeBlocked()) {
            root._welcomeWaiting = true;
            return;
        }
        root._welcomeWaiting = false;
        const groups = MeshWelcome.groups(root.messages, { now: Date.now(), readAt: root.readAt,
            nudgeOf: id => root.nudgeOf(id), conversationOf: m => root.conversationOf(m), nameOf: id => root.nameOf(id) });
        root.messages = root.messages.map(m => held.indexOf(m.mid) >= 0 ? Object.assign({}, m, { greeted: true }) : m);
        root._save();
        if (groups.length > 0) root.welcomed(groups);
    }

    function sendNudge(id, to) {
        const n = root.nudgeOf(id);
        if (!n) return false;
        return root.sendText(`${n.emoji} ${n.text}`, to, id);
    }

    // The reactions offered on a message.
    readonly property var reactionChoices: Config.options?.mesh?.reactions ?? ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    readonly property string me: Quickshell.env("USER") ?? ""
    // As the others see you: mesh.name, else login@hostname (khoa@totoro),
    // like the side panel's header. Only shown: the identity stays the login.
    readonly property string myName: {
        const name = (Config.options?.mesh?.name ?? "").trim();
        if (name !== "") return name;
        return SystemInfo.hostname !== "" ? `${root.me}@${SystemInfo.hostname}` : root.me;
    }
    // A new name reaches the others with the next status, at once.
    onMyNameChanged: if (root.configured) nameAnnounce.restart()
    Timer {
        id: nameAnnounce
        interval: 3000
        onTriggered: root._sharePresence(true)
    }

    // What `nixbook-mesh status` says: {token, tokenSource, joined, keySource}.
    property var setup: ({})
    readonly property bool configured: root.server !== "" && !!root.setup.token && !!root.setup.joined
    property bool connected: false
    property string lastError: ""
    // This desktop's account on the server ({user, role}, from `test`): the
    // admin invites and removes people (Settings > Mesh).
    property var account: ({})
    readonly property bool isAdmin: root.account.role === "admin"
    // The admin's view of who is in: [{ name, role }].
    property var people: []
    // Private messages are sealed for each member's own key: the keys this
    // desktop pinned ({ id: { fingerprint, changed } }, `nixbook-mesh keys`)
    // and its own fingerprint.
    property var keys: ({})
    property string myFingerprint: ""
    function keyChanged(id) {
        return !!(root.keys[id]?.changed);
    }
    function refreshKeys() {
        root.run(["keys"], "", (ok, answer) => {
            if (ok) root.keys = answer.members ?? {};
        });
        root.run(["keys", "mine"], "", (ok, answer) => {
            if (ok) root.myFingerprint = answer.fingerprint ?? "";
        });
    }
    // A member's new key (a new computer): private messages from and to them
    // go again. Only the user decides this.
    function trustKey(id, then) {
        root.run(["keys", "trust", id], "", (ok, answer) => {
            root.refreshKeys();
            if (then) then(ok, answer);
        });
    }

    // Everyone seen: { id: { id, name, state, seen (ms), readUpTo (ms),
    // avatar: { sha, path (once downloaded), meta (until then) } } }.
    property var members: ({})
    // The messages, oldest first: { mid, from, name, to, time (ms), text,
    // mine, status: "sent" | "sending" | "failed", file?, dh? (what proves
    // its deletion), deleted? (deleted for everyone: no text, no file),
    // deleting?, deleteError?, reactions?: { emoji: [member ids] } }. A file: received
    // and not yet downloaded { u, k, n, name, size, sha, mime, w, h, exp },
    // downloaded { path, name, size, sha, mime, image, animated, w, h },
    // being sent { source, name }; `expired` when it was gone from the
    // server first, `error` when the download failed.
    property var messages: []
    // The messages by id (the Mesh tab's rows read theirs from here).
    readonly property var byMid: {
        const by = {};
        for (const m of root.messages) by[m.mid] = m;
        return by;
    }
    // Read up to (ms), per conversation ("" = everyone, else a member's id).
    property var readAt: ({})
    // The conversation shown in the Mesh tab.
    property string conversation: ""
    readonly property bool viewing: GlobalStates.sidebarRightOpen && Persistent.states.sidebar.tab === "mesh"
    // The Mesh tab on screen (not behind the lock, the screens on): its
    // messages still notify (but the open conversation's), without a cut-in
    // (Notifications.arrive).
    readonly property bool inView: root.viewing && !GlobalStates.screenLocked && !Idle.screensOff

    // Files moving, by message: { mid: { done, total } } (not saved).
    property var transfers: ({})
    // What the server takes (`nixbook-mesh limits`): the largest file, in
    // bytes (0: not known), and how long it keeps one (seconds).
    property real maxFileBytes: 0
    property real fileExpiry: 0
    // Received files up to this size download by themselves; bigger ones
    // wait for a click (Download), the server keeping them (a year on
    // nixbook's).
    readonly property real autoFetchBytes: 250e6

    property real now: Date.now()
    readonly property int staleMs: 25 * 60 * 1000

    property bool _started: false
    property bool _loaded: false

    function load() {
        if (root._started) return;
        root._started = true;
        root.refreshStatus();
    }

    // -- What a desktop shows -------------------------------------------------------

    function conversationOf(m) {
        if (!m.to) return "";
        return m.mine ? m.to : m.from;
    }
    function messagesIn(conv) {
        return root.messages.filter(m => root.conversationOf(m) === conv);
    }
    function unreadIn(conv) {
        const since = root.readAt[conv] ?? 0;
        return root.messages.filter(m => !m.mine && !m.deleted && m.time > since && root.conversationOf(m) === conv).length;
    }
    readonly property int unread: {
        let n = 0;
        for (const m of root.messages)
            if (!m.mine && !m.deleted && m.time > (root.readAt[root.conversationOf(m)] ?? 0)) n++;
        return n;
    }
    readonly property var memberList: Object.values(root.members)
        .filter(m => m.id !== root.me)
        .sort((a, b) => (b.seen ?? 0) - (a.seen ?? 0))
    function stateOf(id) {
        const m = root.members[id];
        if (!m) return "offline";
        if (!m.state || root.now - (m.seen ?? 0) > root.staleMs) return "offline";
        return m.state;
    }
    readonly property int around: root.memberList.filter(m => {
        const s = root.stateOf(m.id);
        return s !== "offline" && s !== "hidden";
    }).length
    function nameOf(id) {
        id = `${id ?? ""}`;
        if (id === "") return Translation.tr("Everyone");
        const m = root.members[id];
        return m?.name || (id.charAt(0).toUpperCase() + id.slice(1));
    }
    function stateText(state) {
        switch (state) {
        case "free": return Translation.tr("Free");
        case "meeting": return Translation.tr("In a meeting");
        case "gaming": return Translation.tr("Gaming");
        case "busy": return Translation.tr("Busy");
        case "dnd": return Translation.tr("Do not disturb");
        case "away": return Translation.tr("Away");
        case "hidden": return Translation.tr("Not sharing their status");
        default: return Translation.tr("Offline");
        }
    }
    function stateColor(state) {
        switch (state) {
        case "free": return "#4caf50";
        case "meeting": case "dnd": return Appearance.m3colors.m3error;
        case "gaming": return "#9c6ade";
        case "busy": return "#f0a030";
        case "away": return "#c8b040";
        default: return Appearance.colors.colSubtext;
        }
    }
    // "2 min ago", "3 h ago", "yesterday".
    function ago(ms) {
        const s = Math.max(0, (root.now - ms) / 1000);
        if (s < 60) return Translation.tr("just now");
        if (s < 3600) return Translation.tr("%1 min ago").arg(Math.round(s / 60));
        if (s < 86400) return Translation.tr("%1 h ago").arg(Math.round(s / 3600));
        return Translation.tr("%1 days ago").arg(Math.round(s / 86400));
    }
    function statusLine(id) {
        const state = root.stateOf(id);
        const m = root.members[id];
        if (state === "offline")
            return m?.seen ? Translation.tr("Offline · seen %1").arg(root.ago(m.seen)) : Translation.tr("Offline");
        return root.stateText(state);
    }

    // -- Opening the view ---------------------------------------------------------------

    function open(conv) {
        if (conv !== undefined) root.conversation = conv;
        GlobalStates.sidebarRightOpen = true;
        // After the sidebar's own choice on opening (Notifications, when one
        // arrived while it was closed): this is the tab asked for.
        Qt.callLater(() => {
            Persistent.states.sidebar.tab = "mesh";
            root.markRead(root.conversation);
        });
    }
    function openSettings() {
        GlobalStates.settingsOpen = true;
        GlobalStates.settingsPage = "Mesh";
    }

    // What is shown is read; a private conversation tells its member so.
    function markRead(conv) {
        const last = root.messagesIn(conv).filter(m => !m.mine && !m.deleted).slice(-1)[0];
        if (!last || (root.readAt[conv] ?? 0) >= last.time) return;
        root.readAt = Object.assign({}, root.readAt, { [conv]: last.time });
        root._save();
        // Everyone's conversation too: "seen by" under your last message
        // there (seenBy); the receipt then goes open to the mesh.
        root._send("read", { to: conv, upTo: last.time });
    }
    // Who read your message `m`: a private one, its member (seen); one to
    // everyone, the members who read the conversation up to it (seenBy).
    // A second's slack: the reader's copy of its time is in whole seconds.
    function seen(m) {
        return !!m && m.to !== "" && (root.members[m.to]?.readUpTo ?? 0) + 999 >= m.time;
    }
    function seenBy(m) {
        if (!m || m.to !== "") return [];
        return root.memberList.filter(x => (x.readEveryoneUpTo ?? 0) + 999 >= m.time).map(x => x.id);
    }
    onViewingChanged: if (root.viewing) root.markRead(root.conversation)
    onConversationChanged: if (root.viewing) root.markRead(root.conversation)

    // -- Sending ----------------------------------------------------------------------------

    // `quick`: a nudge's id (sendNudge), for its cut-in on the other side.
    // `reply`: the message answered (replyOf), shown quoted above this one.
    function sendText(text, to, quick, reply) {
        text = (text ?? "").trim();
        if (text === "" || !root.configured) return false;
        const mid = root._mid();
        const m = { mid: mid, from: root.me, name: root.myName, to: to ?? "", time: Date.now(), text: text.slice(0, 1000),
            mine: true, status: "sending" };
        if (quick) m.quick = quick;
        if (reply) m.reply = reply;
        root.messages = [...root.messages, m].slice(-500);
        root._save();
        root._send("message", root._payload(m));
        return true;
    }
    // What goes with a message: its text, a nudge's id, what it answers.
    function _payload(m) {
        return Object.assign({ to: m.to, text: m.text, mid: m.mid }, m.quick ? { quick: m.quick } : {}, m.reply ? { reply: m.reply } : {});
    }
    // A message, as what a reply to it carries: {mid, from, text}: its
    // sender and a snippet (its file's label when it has no text), so the
    // quote shows even where it isn't kept.
    function replyOf(m) {
        if (!m) return null;
        const text = (m.text ?? "") !== "" ? m.text : root.fileLabel(m.file);
        return { mid: m.mid, from: m.from, text: text.replace(/\s+/g, " ").slice(0, 200) };
    }
    // What a received message answers, checked.
    function _replyIn(r) {
        if (!r || typeof r !== "object" || !/^[A-Za-z0-9_-]{1,64}$/.test(`${r.mid ?? ""}`)) return null;
        return { mid: `${r.mid}`, from: /^[A-Za-z0-9._-]{1,64}$/.test(`${r.from ?? ""}`) ? `${r.from}` : "",
            text: `${r.text ?? ""}`.slice(0, 200) };
    }
    // Files picked, dropped or pasted: one message each, the text with the
    // first.
    function sendFiles(paths, text, to, reply) {
        paths = (paths ?? []).map(p => FileUtils.trimFileProtocol(`${p}`)).filter(p => p !== "");
        if (paths.length === 0 || !root.configured) return false;
        const added = paths.map((path, i) => Object.assign({ mid: root._mid(), from: root.me, name: root.myName, to: to ?? "",
            time: Date.now() + i, text: i === 0 ? (text ?? "").trim().slice(0, 1000) : "", mine: true, status: "sending",
            file: { source: path, name: path.split("/").pop() } }, i === 0 && reply ? { reply: reply } : {}));
        root.messages = [...root.messages, ...added].slice(-500);
        root._save();
        for (const m of added) root._sendFile(m);
        return true;
    }
    function _sendFile(m) {
        fileSender.createObject(root, {
            mid: m.mid,
            payload: JSON.stringify(Object.assign({ path: m.file.source, to: m.to, text: m.text, mid: m.mid, name: root.myName },
                m.reply ? { reply: m.reply } : {})),
            command: [root.bin, "sendfile", root.server]
        });
    }
    function _progress(mid, line) {
        root.transfers = Object.assign({}, root.transfers, { [mid]: { done: line.done ?? 0, total: line.total ?? 0 } });
    }
    function _doneMoving(mid) {
        if (!(mid in root.transfers)) return;
        const t = Object.assign({}, root.transfers);
        delete t[mid];
        root.transfers = t;
    }
    function _update(mid, fields) {
        root.messages = root.messages.map(m => m.mid === mid ? Object.assign({}, m, fields) : m);
        root._save();
    }
    function messageOf(mid) {
        return root.messages.find(m => m.mid === mid) ?? null;
    }
    Component {
        id: fileSender
        Process {
            id: proc
            property string mid
            property string payload
            property var answer: null
            stdinEnabled: true
            stdout: SplitParser {
                onRead: line => {
                    let e = null;
                    try {
                        e = JSON.parse(line);
                    } catch (err) {
                        return;
                    }
                    if (e.event === "progress") root._progress(proc.mid, e);
                    else proc.answer = e;
                }
            }
            Component.onCompleted: proc.running = true
            onRunningChanged: {
                if (!proc.running) return;
                proc.write(proc.payload + "\n");
                proc.stdinEnabled = false;
            }
            onExited: code => {
                root._doneMoving(proc.mid);
                const m = root.messageOf(proc.mid);
                if (m && !m.deleted) {
                    if (code === 0 && proc.answer?.ok)
                        root._update(proc.mid, { status: "sent", error: "", dh: root._dh(proc.answer.dh),
                            file: Object.assign({ source: m.file?.source ?? "" }, proc.answer.file) });
                    else
                        root._update(proc.mid, { status: "failed",
                            error: proc.answer?.error ?? Translation.tr("Couldn't run the mesh helper") });
                }
                if (code === 0 && proc.answer?.ok && !root.connected) root._kick();
                proc.destroy();
            }
        }
    }

    // -- Files received -------------------------------------------------------------------

    property var _fetchQueue: []
    property int _fetching: 0
    function _needsFetch(m) {
        return !!(m?.file?.k && !m.file.path && !m.file.expired);
    }
    function fetchFile(mid) {
        if (!root._fetchQueue.includes(mid)) root._fetchQueue = [...root._fetchQueue, mid];
        root._nextFetch();
    }
    function _nextFetch() {
        if (!root.configured) return;
        while (root._fetching < 2 && root._fetchQueue.length > 0) {
            const mid = root._fetchQueue[0];
            root._fetchQueue = root._fetchQueue.slice(1);
            const m = root.messageOf(mid);
            if (!root._needsFetch(m) || mid in root.transfers) continue;
            root._fetching++;
            root._progress(mid, { done: 0, total: m.file.size ?? 0 });
            fileFetcher.createObject(root, {
                mid: mid,
                payload: JSON.stringify({ file: m.file }),
                command: [root.bin, "fetch", root.server]
            });
        }
    }
    Component {
        id: fileFetcher
        Process {
            id: proc
            property string mid
            property string payload
            property var answer: null
            stdinEnabled: true
            stdout: SplitParser {
                onRead: line => {
                    let e = null;
                    try {
                        e = JSON.parse(line);
                    } catch (err) {
                        return;
                    }
                    if (e.event === "progress") root._progress(proc.mid, e);
                    else proc.answer = e;
                }
            }
            Component.onCompleted: proc.running = true
            onRunningChanged: {
                if (!proc.running) return;
                proc.write(proc.payload + "\n");
                proc.stdinEnabled = false;
            }
            onExited: code => {
                root._fetching--;
                root._doneMoving(proc.mid);
                const m = root.messageOf(proc.mid);
                // Deleted while it came: what landed goes too.
                if (m?.deleted) root._pruneFiles();
                if (m && !m.deleted) {
                    if (code === 0 && proc.answer?.ok) {
                        root._update(proc.mid, { file: proc.answer.file });
                    } else if (proc.answer?.expired) {
                        // Gone from the server: nothing more to try (its key goes).
                        root._update(proc.mid, { file: { name: m.file.name, size: m.file.size, mime: m.file.mime,
                            sha: m.file.sha, expired: true } });
                    } else {
                        root._update(proc.mid, { file: Object.assign({}, m.file,
                            { error: proc.answer?.error ?? Translation.tr("Couldn't run the mesh helper") }) });
                    }
                    if (m.notifyWhenFetched) {
                        root._update(proc.mid, { notifyWhenFetched: false });
                        root._notify(root.messageOf(proc.mid));
                    }
                }
                proc.destroy();
                root._nextFetch();
            }
        }
    }
    // What is being sent, or arriving: { done, total } or null.
    function transferOf(mid) {
        return root.transfers[mid] ?? null;
    }
    // Opened with its app; a file that could run something (a script, a
    // launcher, a program) shows its folder instead.
    function openFile(file) {
        if (!file?.path) return;
        const risky = /\.(desktop|sh|bash|zsh|fish|py|pl|rb|run|bin|appimage|exe|msi|bat|cmd|com|jar|deb|rpm|flatpakref|so|ko)$/i;
        AppLaunch.openUrl(risky.test(file.path) ? file.path.replace(/\/[^/]*$/, "") : file.path);
    }
    // A copy in Downloads; then(ok, path or error).
    function saveFile(file, then) {
        if (!file?.path) return;
        root.run(["save"], JSON.stringify({ path: file.path }), (ok, answer) => {
            if (then) then(ok, ok ? answer.path : (answer.error ?? ""));
        });
    }
    function sizeText(bytes) {
        const n = Number(bytes ?? 0);
        if (n < 1000) return Translation.tr("%1 bytes").arg(n);
        if (n < 1e6) return Translation.tr("%1 KB").arg(Math.round(n / 1000));
        if (n < 1e9) return Translation.tr("%1 MB").arg((n / 1e6).toFixed(1));
        return Translation.tr("%1 GB").arg((n / 1e9).toFixed(1));
    }
    // "3 days", "1 year": how long the server keeps files.
    function durationText(seconds) {
        const d = Math.round(seconds / 86400);
        if (seconds < 2 * 86400) return Translation.tr("%1 h").arg(Math.round(seconds / 3600));
        if (d >= 360) return d >= 720 ? Translation.tr("%1 years").arg(Math.round(d / 365)) : Translation.tr("a year");
        return Translation.tr("%1 days").arg(d);
    }
    // One of the mesh's own copies (not a file shown from where it was sent).
    function isMeshCopy(file) {
        return /\/nixbook-shell\/mesh\/files\/[0-9a-f]{32}\/[^/]+$/.test(file?.path ?? "");
    }
    function refreshLimits() {
        if (root.server === "" || !root.setup.token) return;
        root.run(["limits", root.server], "", (ok, answer) => {
            if (!ok) return;
            root.maxFileBytes = answer.maxFile ?? 0;
            root.fileExpiry = answer.expiry ?? 0;
        });
    }
    // A message's file, in a few words (notifications, previews).
    function fileLabel(file) {
        if (!file) return "";
        if (file.image || /^image\//.test(file.mime ?? ""))
            return /gif$/.test(file.mime ?? "") ? Translation.tr("🎞 GIF") : Translation.tr("🖼 Image");
        return Translation.tr("📎 %1").arg(file.name ?? Translation.tr("File"));
    }

    function _mid() {
        let s = "";
        for (let i = 0; i < 16; i++) s += Math.floor(Math.random() * 16).toString(16);
        return s;
    }
    function _setStatus(mid, status, error) {
        let changed = false;
        const list = root.messages.map(m => {
            if (m.mid !== mid || (m.status === status && (m.error ?? "") === (error ?? ""))) return m;
            changed = true;
            return Object.assign({}, m, { status: status, error: error ?? "" });
        });
        if (changed) {
            root.messages = list;
            root._save();
        }
    }
    function retry(mid) {
        const m = root.messages.find(x => x.mid === mid && x.mine);
        if (!m || m.deleted) return;
        root._setStatus(mid, "sending");
        if (m.file?.source && !m.file.sha) root._sendFile(m);
        else root._send("message", root._payload(m));
    }

    function _send(kind, data) {
        if (!root.configured) return;
        sender.createObject(root, {
            kind: kind,
            mid: data.mid ?? "",
            target: data.target ?? "",
            payload: JSON.stringify(Object.assign({ name: root.myName }, data)),
            command: [root.bin, "send", root.server, kind]
        });
    }
    Component {
        id: sender
        Process {
            id: proc
            property string kind
            property string mid
            property string target
            property string payload
            stdinEnabled: true
            stdout: StdioCollector { id: sendOut }
            Component.onCompleted: proc.running = true
            onRunningChanged: {
                if (!proc.running) return;
                proc.write(proc.payload + "\n");
                proc.stdinEnabled = false;
            }
            onExited: code => {
                let answer = null;
                try {
                    answer = JSON.parse(sendOut.text);
                } catch (e) {}
                if (proc.kind === "message" && proc.mid !== "") {
                    root._setStatus(proc.mid, code === 0 && answer?.ok ? "sent" : "failed",
                        code === 0 && answer?.ok ? "" : (answer?.error ?? ""));
                    const dh = root._dh(answer?.dh);
                    if (code === 0 && dh !== "" && root.messageOf(proc.mid)?.dh !== dh) root._update(proc.mid, { dh: dh });
                }
                if (proc.kind === "delete" && proc.target !== "") {
                    if (code === 0 && answer?.ok) root._tombstone(proc.target);
                    else if (root.messageOf(proc.target) && !root.messageOf(proc.target).deleted)
                        root._update(proc.target, { deleting: false,
                            deleteError: answer?.error ?? Translation.tr("Couldn't run the mesh helper") });
                }
                // The server took it but the listener says it's cut off (a
                // refusal it waits a minute after): listen again now.
                if (code === 0 && answer?.ok && !root.connected) root._kick();
                if (code !== 0 && answer?.error) root.lastError = answer.error;
                proc.destroy();
            }
        }
    }

    // -- Your status ----------------------------------------------------------------------

    // Coarse on purpose: never which app or which window.
    readonly property string myState: {
        if (!root.sharePresence) return "hidden";
        if (GlobalStates.screenLocked || Idle.screensOff) return "away";
        if (Notifications.silent) return "dnd";
        if (CalendarEvents.meetingNow(new Date(root.now))) return "meeting";
        const app = ToplevelManager.activeToplevel?.appId ?? "";
        if (/^steam_app_[0-9]+$|^gamescope$/.test(app)) return "gaming";
        const mon = WM.focusedMonitor?.name ?? "";
        if (mon !== "" && WM.fullscreenOnMonitor(mon)) return "busy";
        return "free";
    }
    // How the others see you.
    readonly property string myStateText: root.myState === "hidden" ? Translation.tr("Not shared")
        : root.stateText(root.myState)
    property string _sentState: ""
    property real _sentAt: 0
    onMyStateChanged: presenceDebounce.restart()
    onConfiguredChanged: if (root.configured) {
        presenceDebounce.restart();
        profileSoon.restart();
        root._nextFetch();
    }
    Timer {
        id: presenceDebounce
        // A short meeting gap, a brief lock: not worth telling.
        interval: 15000
        onTriggered: root._sharePresence(false)
    }
    function _sharePresence(heartbeat) {
        if (!root.configured || !root.enabled) return;
        // Not sharing: said once, then nothing.
        if (root.myState === "hidden" && root._sentState === "hidden") return;
        if (!heartbeat && root.myState === root._sentState) return;
        root._sentState = root.myState;
        root._sentAt = Date.now();
        root._send("presence", { state: root.myState });
    }
    Timer {
        // Still here: members count anyone silent for 25 min as offline.
        interval: 10 * 60 * 1000
        running: root.configured && root.enabled && root.sharePresence
        repeat: true
        onTriggered: root._sharePresence(true)
    }
    Timer {
        interval: 30000
        running: root._started
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // -- Receiving --------------------------------------------------------------------------

    Process {
        id: listener
        running: root._loaded && root.configured && root.enabled
        command: [root.bin, "listen", root.server]
        stdout: SplitParser {
            onRead: line => root._event(line)
        }
        onExited: {
            root.connected = false;
            if (root.configured && root.enabled) restartListener.start();
        }
    }
    property bool _kicked: false
    function _kick() {
        if (!listener.running) {
            restartListener.restart();
            return;
        }
        root._kicked = true;
        listener.running = false;
    }
    Timer {
        id: restartListener
        interval: root._kicked ? 500 : 15000
        onTriggered: {
            root._kicked = false;
            if (root.configured && root.enabled && !listener.running) listener.running = true;
        }
    }

    function _event(line) {
        let e = null;
        try {
            e = JSON.parse(line);
        } catch (err) {
            return;
        }
        if (e.event === "status") {
            // (Re)connected: what comes in the next seconds is the catch-up.
            if (e.connected && !root.connected) root._connectedAt = Date.now();
            root.connected = !!e.connected;
            root.lastError = e.connected ? "" : (e.error ?? "");
            return;
        }
        if (e.event === "error") {
            root.lastError = e.error ?? "";
            return;
        }
        if (e.event === "keychange") {
            root.refreshKeys();
            return;
        }
        if (e.event !== "message") return;
        const time = (e.time ?? 0) * 1000;
        const id = `${e.from ?? ""}`;
        if (id === "") return;
        // Everyone who speaks is a member; their name follows what they send.
        const prev = root.members[id] ?? { id: id };
        const member = Object.assign({}, prev, {
            name: e.name || prev.name || "",
            seen: Math.max(prev.seen ?? 0, time)
        });
        if (e.kind === "presence" && time >= (prev.stateAt ?? 0)) {
            member.state = `${e.data?.state ?? ""}`;
            member.stateAt = time;
        }
        if (e.kind === "read" && !e.mine && (e.to ?? "") === root.me)
            member.readUpTo = Math.max(prev.readUpTo ?? 0, Number(e.data?.upTo ?? 0));
        if (e.kind === "read" && !e.mine && (e.to ?? "") === "")
            member.readEveryoneUpTo = Math.max(prev.readEveryoneUpTo ?? 0, Number(e.data?.upTo ?? 0));
        if (!e.mine || id === root.me)
            root.members = Object.assign({}, root.members, { [id]: member });
        if (!root.keys[id]) keysSoon.restart();
        if (e.kind === "message") root._receive(e, time);
        else if (e.kind === "delete") root._applyDelete(e);
        else if (e.kind === "react") root._applyReact(e, time);
        else if (e.kind === "profile") {
            if (!e.mine) root._applyProfile(id, e.data?.avatar ?? null);
        } else root._saveSoon();
        // Listening together (services/MeshListen.qml).
        if (e.kind === "listen") MeshListen.receive(e);
    }

    function _receive(e, time) {
        const mid = `${e.mid ?? ""}`;
        const text = `${e.data?.text ?? ""}`;
        const f = e.data?.file;
        const file = f && typeof f === "object" ? {
            u: `${f.u ?? ""}`, k: `${f.k ?? ""}`, n: `${f.n ?? ""}`, sha: `${f.sha ?? ""}`,
            name: `${f.name ?? ""}`.slice(0, 200), size: Number(f.size ?? 0), mime: `${f.mime ?? ""}`.slice(0, 100),
            w: Number(f.w ?? 0), h: Number(f.h ?? 0), exp: Number(f.exp ?? 0)
        } : null;
        if (text === "" && !file) return;
        const dh = root._dh(e.data?.dh);
        // Mine, from this desktop: already here (now sent).
        const known = root.messages.find(m => m.mid === mid);
        if (known) {
            if (known.deleted) return;
            if (known.status !== "sent") root._setStatus(mid, "sent");
            if (e.mine && dh !== "" && known.mine && known.dh !== dh) root._update(mid, { dh: dh });
            return;
        }
        const m = { mid: mid, from: e.from, name: e.name ?? "", to: e.to ?? "", time: time, text: text,
            mine: !!e.mine, status: "sent" };
        if (file) m.file = file;
        if (dh !== "") m.dh = dh;
        const quick = `${e.data?.quick ?? ""}`;
        if (/^[a-z]{1,20}$/.test(quick)) m.quick = quick;
        const reply = root._replyIn(e.data?.reply);
        if (reply) m.reply = reply;
        if ((Config.options?.mesh?.nudgeCutIn ?? true) && root.nudgeOf(m.quick)
                && MeshWelcome.waits(m, { now: Date.now(), connectedAt: root._connectedAt, locked: GlobalStates.screenLocked }))
            m.welcome = true;
        // In its place by time, after those of the same second (times are
        // whole seconds): a re-sort is not stable here and reordered them,
        // which rebuilt the Mesh tab's rows and moved its view.
        let at = root.messages.length;
        while (at > 0 && root.messages[at - 1].time > time) at--;
        const list = [...root.messages.slice(0, at), m, ...root.messages.slice(at)].slice(-500);
        root.messages = list;
        root._saveSoon();
        // At once: the server deletes files after a while.
        if (file && file.size <= root.autoFetchBytes) root.fetchFile(mid);
        if (m.mine) return;
        const conv = root.conversationOf(m);
        const looking = root.viewing && root.conversation === conv;
        if (looking) root.markRead(conv);
        // Came while this desktop wasn't there: the welcome back, once the
        // catch-up is over (nothing else: no cut-in, no notification).
        if (m.welcome) {
            welcomeSoon.restart();
            return;
        }
        // A nudge: its own cut-in when it can show (MeshNudge.qml), in place
        // of the notification, the Mesh tab open or not.
        if (m.quick && root._nudgeCutInNow(m)) {
            root.nudged(m);
            return;
        }
        if (looking) return;
        // What was said while this desktop was off for long: unread, not a
        // pile of notifications.
        if (Date.now() - time < 2 * 3600 * 1000 && (Config.options?.mesh?.notify ?? true)) {
            // An image: once here, so the notification shows it.
            if (file && /^image\//.test(file.mime) && file.size <= root.autoFetchBytes) root._update(mid, { notifyWhenFetched: true });
            else root._notify(m);
        }
    }

    function _notify(m) {
        const who = m.name || root.nameOf(m.from);
        const title = m.to === "" ? Translation.tr("%1 · to everyone").arg(who) : who;
        const body = [m.reply ? Translation.tr("↩ %1: %2").arg(root.nameOf(m.reply.from)).arg(m.reply.text.slice(0, 60)) : "",
            root.fileLabel(m.file), m.text].filter(t => t).join("\n");
        const image = m.file?.image && m.file?.path ? [`--hint=string:image-path:${m.file.path}`] : [];
        notifier.createObject(root, {
            conv: root.conversationOf(m),
            command: ["notify-send", `--app-name=${who}`, `--icon=${root.members[m.from]?.avatar?.path || "avatar-default"}`, ...image,
                `--hint=string:x-nixbook-mesh:${m.to === "" ? "nixbook-mesh-everyone" : "nixbook-mesh-direct"}`,
                `--hint=string:x-nixbook-mesh-mid:${m.mid}`,
                "--wait", `--action=reply=${Translation.tr("Reply")}`, "--", title, body]
        });
    }
    Component {
        id: notifier
        Process {
            id: notify
            property string conv
            stdout: StdioCollector { id: notifyOut }
            Component.onCompleted: notify.running = true
            onExited: {
                if (notifyOut.text.trim() === "reply") root.open(notify.conv);
                notify.destroy();
            }
        }
    }

    // -- Profile pictures ---------------------------------------------------------------

    // A member's picture (a file:// URL), "" while there is none.
    function avatarOf(id) {
        if (id === root.me) return root.shareAvatar ? UserAvatar.source : "";
        const path = root.members[id]?.avatar?.path ?? "";
        return path !== "" ? `file://${path}` : "";
    }
    function _setMember(id, fields) {
        root.members = Object.assign({}, root.members, { [id]: Object.assign({}, root.members[id] ?? { id: id }, fields) });
        root._saveSoon();
    }
    function _applyProfile(id, meta) {
        const cur = root.members[id]?.avatar ?? null;
        if (!meta?.sha) {
            if (cur) {
                root._setMember(id, { avatar: null });
                root._pruneFiles();
            }
            return;
        }
        if (cur?.sha === meta.sha && cur.path) return;
        root._setMember(id, { avatar: { sha: meta.sha, meta: meta } });
        root._fetchAvatar(id);
    }
    function _fetchAvatar(id) {
        const a = root.members[id]?.avatar;
        if (!a?.meta || !root.configured) return;
        root.run(["fetch", root.server], JSON.stringify({ file: a.meta }), (ok, answer) => {
            const now = root.members[id]?.avatar;
            if (now?.sha !== a.sha) return;
            if (ok && answer.file?.path) root._setMember(id, { avatar: { sha: a.sha, path: answer.file.path } });
            // Gone from the server: none until they send it again.
            else if (answer?.expired) root._setMember(id, { avatar: null });
        });
    }
    // This desktop's picture to the others: when it changes, and once a
    // month (the helper skips it otherwise).
    function _shareProfile() {
        if (!root.configured || !root.enabled) return;
        root.run(["profile", root.server], JSON.stringify({ path: root.shareAvatar ? UserAvatar.path : "", name: root.myName }),
            (ok, answer) => {
                if (!ok && answer?.error) console.log(`[Mesh] Couldn't share the profile picture: ${answer.error}`);
            });
    }
    Timer {
        id: profileSoon
        interval: 5000
        onTriggered: root._shareProfile()
    }
    Timer {
        interval: 24 * 3600 * 1000
        running: root.configured && root.enabled
        repeat: true
        onTriggered: profileSoon.restart()
    }
    Connections {
        target: UserAvatar
        function onPathChanged() { profileSoon.restart(); }
        function onRevisionChanged() { profileSoon.restart(); }
    }
    onShareAvatarChanged: profileSoon.restart()

    // -- Reactions ---------------------------------------------------------------------

    // Yours on or off.
    function react(mid, emoji) {
        const m = root.messageOf(mid);
        if (!m || m.deleted || !root.configured || (emoji ?? "") === "") return;
        const on = !(m.reactions?.[emoji] ?? []).includes(root.me);
        root._setReaction(mid, root.me, emoji, on);
        root._send("react", { to: m.to !== "" ? root.conversationOf(m) : "", target: mid, emoji: emoji, on: on });
    }
    function _setReaction(mid, who, emoji, on) {
        root.messages = root.messages.map(m => {
            if (m.mid !== mid || m.deleted) return m;
            const reactions = Object.assign({}, m.reactions ?? {});
            const list = (reactions[emoji] ?? []).filter(x => x !== who);
            if (on) list.push(who);
            if (list.length > 0) reactions[emoji] = list;
            else delete reactions[emoji];
            return Object.assign({}, m, { reactions: reactions });
        });
        root._saveSoon();
    }
    // From the listener: on a message of the conversation it came in (a
    // private one sealed in it, one to everyone open).
    function _applyReact(e, time) {
        const target = `${e.data?.target ?? ""}`;
        const emoji = `${e.data?.emoji ?? ""}`;
        const who = `${e.from ?? ""}`;
        const m = root.messageOf(target);
        if (!m || m.deleted || emoji === "" || who === "") return;
        if (e.private ? (m.to === "" || root.conversationOf(m) !== (e.mine ? e.to : e.from)) : m.to !== "") return;
        const on = e.data?.on !== false;
        const had = (m.reactions?.[emoji] ?? []).includes(who);
        if (had === on) return;
        root._setReaction(target, who, emoji, on);
        if (on && m.mine && !e.mine && !root.inView && Date.now() - time < 2 * 3600 * 1000
            && (Config.options?.mesh?.notify ?? true))
            root._notifyReaction(e, m);
    }
    function _notifyReaction(e, m) {
        const who = e.name || root.nameOf(e.from);
        const what = m.text !== "" ? m.text : root.fileLabel(m.file);
        const avatar = root.members[e.from]?.avatar?.path ?? "";
        notifier.createObject(root, {
            conv: root.conversationOf(m),
            command: ["notify-send", `--app-name=${who}`, `--icon=${avatar || "avatar-default"}`, "--urgency=low",
                `--hint=string:x-nixbook-mesh-reaction:${m.mid}`, "--wait", `--action=reply=${Translation.tr("Open")}`,
                "--", Translation.tr("%1 reacted %2").arg(who).arg(`${e.data?.emoji ?? ""}`),
                Translation.tr("To “%1”").arg(what.length > 80 ? what.slice(0, 79) + "…" : what)]
        });
    }

    // -- Deleting ----------------------------------------------------------------------------

    function _dh(v) {
        return /^[0-9a-f]{64}$/.test(`${v ?? ""}`) ? `${v}` : "";
    }
    // For everyone: your own sent messages; to everyone only those that
    // carry their proof (dh: sent since deleting exists).
    function canDeleteForEveryone(m) {
        if (!m?.mine || m.deleted || m.deleting || m.status === "sending") return false;
        return m.status === "failed" || (m.to ?? "") !== "" || !!m.dh;
    }
    function deleteForEveryone(mid) {
        const m = root.messageOf(mid);
        if (!root.canDeleteForEveryone(m)) return false;
        if (m.status === "failed") {
            // It may have left all the same: told to go, and gone from here.
            root._send("delete", { to: m.to, target: mid });
            root._tombstone(mid);
            return true;
        }
        root._update(mid, { deleting: true, deleteError: "" });
        root._send("delete", { to: m.to, target: mid });
        return true;
    }
    // From this desktop only; the others keep theirs.
    function deleteForMe(mid) {
        const m = root.messageOf(mid);
        if (!m || m.status === "sending") return false;
        root.messages = root.messages.filter(x => x.mid !== mid);
        root._save();
        root._dropFile(mid);
        root._forgetNotification(mid);
        return true;
    }
    // A deletion from the listener ({from, to, private, data: {target,
    // proofHash}}): applied when it comes from the message's sender — sealed
    // (a private conversation: the envelope proves who sent it), or showing
    // the proof the message's `dh` commits to.
    function _applyDelete(e) {
        const target = `${e.data?.target ?? ""}`;
        const proof = `${e.data?.proofHash ?? ""}`;
        const to = `${e.to ?? ""}`;
        const from = `${e.from ?? ""}`;
        if (target === "" || from === "") return;
        const victims = root.messages.filter(m => m.mid === target && m.from === from && !m.deleted && (m.to ?? "") === to
            && ((e.private && to !== "") || (!!m.dh && m.dh === proof)));
        // Nothing here (no longer kept, or not the sender's): nothing to do.
        // The server keeps the order, so a message always comes before its
        // deletion.
        if (victims.length === 0) {
            root._saveSoon();
            return;
        }
        root._tombstone(target);
    }
    function _tombstone(mid) {
        root.messages = root.messages.map(m => m.mid !== mid ? m
            : { mid: m.mid, from: m.from, name: m.name, to: m.to, time: m.time, mine: m.mine, status: "sent", text: "",
                deleted: true });
        root._save();
        root._dropFile(mid);
        root._forgetNotification(mid);
    }
    function _dropFile(mid) {
        root._fetchQueue = root._fetchQueue.filter(x => x !== mid);
        root._pruneFiles();
    }
    function _pruneFiles() {
        const keep = [...root.messages.map(m => m.file?.sha ?? ""), ...Object.values(root.members).map(m => m.avatar?.sha ?? "")];
        root.run(["prune"], JSON.stringify({ keep: keep.filter(s => s !== "") }));
    }
    // Its notification: off the screen and out of the history.
    function _forgetNotification(mid) {
        const live = Notifications.list.filter(n => n.hints?.["x-nixbook-mesh-mid"] === mid);
        if (live.length > 0) Notifications.discardNotifications(live.map(n => n.notificationId), true, false);
        NotificationHistory.forgetMeshMessage(mid);
    }

    // -- Setting up (Settings > Mesh) ----------------------------------------

    property bool busy: false
    // run(args, secret, then(ok, answer)): the helper, a secret on stdin.
    function run(args, secret, then) {
        helper.createObject(root, { args: args, secret: secret ?? "", then: then ?? null, command: [root.bin, ...args] });
    }
    function refreshStatus(then) {
        root.run(["status"], "", (ok, answer) => {
            if (ok) root.setup = answer;
            const first = !root._loaded;
            root._loaded = true;
            if (first) {
                root.refreshAccount();
                root.refreshKeys();
                root._resumeFiles();
            }
            if (then) then(ok, answer);
        });
    }
    Component {
        id: helper
        Process {
            id: proc
            property var args: []
            property string secret
            property var then
            stdinEnabled: proc.secret !== ""
            stdout: StdioCollector { id: helperOut }
            Component.onCompleted: {
                root.busy = true;
                proc.running = true;
            }
            onRunningChanged: {
                if (!proc.running || !proc.stdinEnabled) return;
                proc.write(proc.secret + "\n");
                proc.secret = "";
                proc.stdinEnabled = false;
            }
            onExited: code => {
                root.busy = false;
                let answer = null;
                try {
                    answer = JSON.parse(helperOut.text);
                } catch (e) {}
                const ok = code === 0 && !!answer?.ok;
                const done = proc.then;
                proc.destroy();
                if (done) done(ok, answer ?? { error: Translation.tr("Couldn't run the mesh helper") });
            }
        }
    }
    // After the token or the key changed: listen again with them.
    function reconnect() {
        root.refreshStatus(() => {
            listener.running = false;
            root._sentState = "";
            if (root.configured && root.enabled) restartListener.restart();
            root.refreshAccount();
        });
    }

    // Who this token is, on the server; the admin also gets the people.
    function refreshAccount(then) {
        if (root.server === "" || !root.setup.token) {
            root.account = {};
            root.people = [];
            if (then) then(false, {});
            return;
        }
        root.run(["test", root.server], "", (ok, answer) => {
            root.account = ok ? { user: answer.user, role: answer.role } : {};
            if (ok) root.refreshLimits();
            if (ok && answer.role === "admin") root.refreshPeople();
            if (then) then(ok, answer);
        });
    }
    function refreshPeople() {
        root.run(["members", root.server], "", (ok, answer) => {
            if (ok) root.people = answer.members ?? [];
        });
    }
    // The admin: an account for `name`, and their invite code.
    function invite(name, then) {
        root.run(["invite", root.server, name], "", (ok, answer) => {
            if (ok) root.refreshPeople();
            if (then) then(ok, answer);
        });
    }
    function removePerson(name, then) {
        root.run(["remove", root.server, name], "", (ok, answer) => {
            if (ok) root.refreshPeople();
            if (then) then(ok, answer);
        });
    }
    // Joining with an invite code: the server (when not set in Nix), this
    // desktop's own token and the mesh key all come from it.
    function accept(code, then) {
        root.run(["accept"], code, (ok, answer) => {
            if (ok) {
                if (!NixManaged.isPinned("mesh.server")) Config.options.mesh.server = answer.server;
                else if (answer.server !== root.server) {
                    ok = false;
                    answer = { error: Translation.tr("This invite is for %1, but this computer's mesh server is set to %2 in Nix.").arg(answer.server).arg(root.server) };
                }
                root.reconnect();
            }
            if (then) then(ok, answer);
        });
    }

    // -- The conversation on disk -----------------------------------------------------------

    FileView {
        id: store
        path: FileUtils.trimFileProtocol(`${Directories.state}/user/mesh-conversation.json`)
        blockLoading: false
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(store.text());
                root.messages = data.messages ?? [];
                root.members = data.members ?? {};
                root.readAt = data.readAt ?? {};
                // Still sending when the shell stopped: it may not have gone.
                root.messages = root.messages.map(m => m.status === "sending" ? Object.assign({}, m, { status: "failed" })
                    : m.deleting ? Object.assign({}, m, { deleting: false }) : m);
                root._storeRead = true;
                root._resumeFiles();
                // Held for a welcome back the shell didn't show before it stopped.
                welcomeSoon.restart();
            } catch (e) {}
        }
    }
    // Once the conversation and the setup are read: the files of messages
    // no longer kept go, the ones not downloaded yet are fetched.
    property bool _storeRead: false
    property bool _filesResumed: false
    function _resumeFiles() {
        if (root._filesResumed || !root._storeRead || !root._loaded) return;
        root._filesResumed = true;
        root._pruneFiles();
        for (const id in root.members)
            if (root.members[id]?.avatar?.meta && !root.members[id].avatar.path) root._fetchAvatar(id);
        for (const m of root.messages)
            if (root._needsFetch(m) && !m.file.error && m.file.size <= root.autoFetchBytes) root.fetchFile(m.mid);
    }
    function _save() {
        saveTimer.stop();
        store.setText(JSON.stringify({ messages: root.messages, members: root.members, readAt: root.readAt }));
    }
    function _saveSoon() {
        saveTimer.restart();
    }
    Timer {
        id: keysSoon
        interval: 2000
        onTriggered: root.refreshKeys()
    }
    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: root._save()
    }

    // `nixbook-shell ipc call mesh status|send TEXT|sendTo MEMBER TEXT|sendFile PATH|sendFileTo MEMBER PATH|open|openConversation MEMBER|deleteMessage MID|react MID EMOJI|nudge MEMBER ID|reply MID TEXT`,
    // and listening together: `listenShare MEMBER|watchShare MEMBER|listenStop|listenJoin MEMBER|listenLeave|listenStatus` ("" = everyone).
    // Denied to the desktop agents (desktop-mcp's shellIpcDenyTargets): they
    // would speak in the user's name.
    IpcHandler {
        target: "mesh"

        function status(): string {
            root.load();
            return JSON.stringify({
                configured: root.configured,
                connected: root.connected,
                server: root.server,
                me: root.me,
                myState: root.myState,
                members: root.memberList.map(m => ({ id: m.id, name: m.name, state: root.stateOf(m.id) })),
                unread: root.unread,
                account: root.account,
                people: root.people,
                error: root.lastError
            });
        }
        function send(text: string): string {
            return root.sendText(text, "") ? "ok: sent to everyone" : "error: the mesh isn't set up";
        }
        function sendTo(member: string, text: string): string {
            return root.sendText(text, member) ? `ok: sent to ${member}` : "error: the mesh isn't set up";
        }
        // A file (its path) to everyone / to a member.
        function sendFile(path: string): string {
            return root.sendFiles([path], "", "") ? "ok: sending to everyone" : "error: the mesh isn't set up";
        }
        function sendFileTo(member: string, path: string): string {
            return root.sendFiles([path], "", member) ? `ok: sending to ${member}` : "error: the mesh isn't set up";
        }
        function open(): void {
            root.open();
        }
        // Listening together: share what YouTube Music / Spotify plays with
        // everyone ("") or a member, stop; follow a member's session, leave.
        function listenShare(member: string): string {
            const why = MeshListen.start(member, "music");
            return why === "" ? `ok: sharing with ${member === "" ? "everyone" : member}` : `error: ${why}`;
        }
        // Watching together: what Jellyfin's mpv plays.
        function watchShare(member: string): string {
            const why = MeshListen.start(member, "video");
            return why === "" ? `ok: sharing with ${member === "" ? "everyone" : member}` : `error: ${why}`;
        }
        function listenStop(): string {
            MeshListen.stop();
            return "ok";
        }
        function listenJoin(member: string): string {
            const s = Object.values(MeshListen.sessions).find(x => x.host === member);
            if (!s) return `error: ${member} isn't sharing music`;
            MeshListen.join(s.sid);
            return `ok: listening along with ${member}`;
        }
        function listenLeave(): string {
            MeshListen.leave("");
            return "ok";
        }
        function listenStatus(): string {
            return JSON.stringify({ hosting: MeshListen.hosting, track: MeshListen.hostTrack, following: MeshListen.following,
                status: MeshListen.followStatus, sessions: Object.values(MeshListen.sessions), notice: MeshListen.notice });
        }
        // A member's conversation ("" = everyone).
        function openConversation(member: string): void {
            root.open(member);
        }
        // An answer to a message (its mid), in its conversation.
        function reply(mid: string, text: string): string {
            const m = root.messageOf(mid);
            if (!m || m.deleted) return "error: no such message";
            return root.sendText(text, root.conversationOf(m), "", root.replyOf(m)) ? "ok" : "error: the mesh isn't set up";
        }
        // A nudge (its id: love, hug, …) to everyone ("") or a member.
        function nudge(member: string, id: string): string {
            return root.sendNudge(id, member) ? "ok" : `error: no nudge "${id}" (${root.nudges.map(n => n.id).join(", ")}) or the mesh isn't set up`;
        }
        // Your reaction (an emoji) to a message (its mid), on or off.
        function react(mid: string, emoji: string): string {
            if (!root.messageOf(mid)) return "error: no such message";
            root.react(mid, emoji);
            return "ok";
        }
        // A message (its mid): yours for everyone, anyone else's here only.
        function deleteMessage(mid: string): string {
            const m = root.messageOf(mid);
            if (!m) return "error: no such message";
            if (root.canDeleteForEveryone(m)) return root.deleteForEveryone(mid) ? "ok: deleting for everyone" : "error: can't delete it";
            return root.deleteForMe(mid) ? "ok: deleted here" : "error: can't delete it";
        }
    }
}
