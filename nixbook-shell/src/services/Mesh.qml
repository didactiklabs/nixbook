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
 * Set up in Settings > General > Mesh: the server (mesh.server), your
 * access token (keyring), then create a mesh or enter a member's mesh code.
 * Members appear when they first say something or share their status.
 *
 * Files (images and GIFs shown in the conversation, any other file as a
 * card): encrypted and uploaded by `nixbook-mesh sendfile`, downloaded as
 * soon as their message arrives (`fetch`: the server deletes them after a
 * while) into ~/.local/share/nixbook-shell/mesh/files/.
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
    readonly property string me: Quickshell.env("USER") ?? ""
    readonly property string myName: {
        const name = (Config.options?.mesh?.name ?? "").trim();
        return name !== "" ? name : root.me.charAt(0).toUpperCase() + root.me.slice(1);
    }

    // What `nixbook-mesh status` says: {token, tokenSource, joined, keySource}.
    property var setup: ({})
    readonly property bool configured: root.server !== "" && !!root.setup.token && !!root.setup.joined
    property bool connected: false
    property string lastError: ""
    // This desktop's account on the server ({user, role}, from `test`): the
    // admin invites and removes people (Settings > General > Mesh).
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

    // Everyone seen: { id: { id, name, state, seen (ms), readUpTo (ms) } }.
    property var members: ({})
    // The messages, oldest first: { mid, from, name, to, time (ms), text,
    // mine, status: "sent" | "sending" | "failed", file? }. A file: received
    // and not yet downloaded { u, k, n, name, size, sha, mime, w, h, exp },
    // downloaded { path, name, size, sha, mime, image, animated, w, h },
    // being sent { source, name }; `expired` when it was gone from the
    // server first, `error` when the download failed.
    property var messages: []
    // Read up to (ms), per conversation ("" = everyone, else a member's id).
    property var readAt: ({})
    // The conversation shown in the Mesh tab.
    property string conversation: ""
    readonly property bool viewing: GlobalStates.sidebarRightOpen && Persistent.states.sidebar.tab === "mesh"

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
        return root.messages.filter(m => !m.mine && m.time > since && root.conversationOf(m) === conv).length;
    }
    readonly property int unread: {
        let n = 0;
        for (const m of root.messages)
            if (!m.mine && m.time > (root.readAt[root.conversationOf(m)] ?? 0)) n++;
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
        GlobalStates.settingsPage = "General:Mesh";
    }

    // What is shown is read; a private conversation tells its member so.
    function markRead(conv) {
        const last = root.messagesIn(conv).filter(m => !m.mine).slice(-1)[0];
        if (!last || (root.readAt[conv] ?? 0) >= last.time) return;
        root.readAt = Object.assign({}, root.readAt, { [conv]: last.time });
        root._save();
        if (conv !== "") root._send("read", { to: conv, upTo: last.time });
    }
    onViewingChanged: if (root.viewing) root.markRead(root.conversation)
    onConversationChanged: if (root.viewing) root.markRead(root.conversation)

    // -- Sending ----------------------------------------------------------------------------

    function sendText(text, to) {
        text = (text ?? "").trim();
        if (text === "" || !root.configured) return false;
        const mid = root._mid();
        const m = { mid: mid, from: root.me, name: root.myName, to: to ?? "", time: Date.now(), text: text.slice(0, 1000),
            mine: true, status: "sending" };
        root.messages = [...root.messages, m].slice(-500);
        root._save();
        root._send("message", { to: m.to, text: m.text, mid: mid });
        return true;
    }
    // Files picked, dropped or pasted: one message each, the text with the
    // first.
    function sendFiles(paths, text, to) {
        paths = (paths ?? []).map(p => FileUtils.trimFileProtocol(`${p}`)).filter(p => p !== "");
        if (paths.length === 0 || !root.configured) return false;
        const added = paths.map((path, i) => ({ mid: root._mid(), from: root.me, name: root.myName, to: to ?? "",
            time: Date.now() + i, text: i === 0 ? (text ?? "").trim().slice(0, 1000) : "", mine: true, status: "sending",
            file: { source: path, name: path.split("/").pop() } }));
        root.messages = [...root.messages, ...added].slice(-500);
        root._save();
        for (const m of added) root._sendFile(m);
        return true;
    }
    function _sendFile(m) {
        fileSender.createObject(root, {
            mid: m.mid,
            payload: JSON.stringify({ path: m.file.source, to: m.to, text: m.text, mid: m.mid, name: root.myName }),
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
                if (m) {
                    if (code === 0 && proc.answer?.ok)
                        root._update(proc.mid, { status: "sent", error: "",
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
                if (m) {
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
        if (!m) return;
        root._setStatus(mid, "sending");
        if (m.file?.source && !m.file.sha) root._sendFile(m);
        else root._send("message", { to: m.to, text: m.text, mid: mid });
    }

    function _send(kind, data) {
        if (!root.configured) return;
        sender.createObject(root, {
            kind: kind,
            mid: data.mid ?? "",
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
                if (proc.kind === "message" && proc.mid !== "")
                    root._setStatus(proc.mid, code === 0 && answer?.ok ? "sent" : "failed",
                        code === 0 && answer?.ok ? "" : (answer?.error ?? ""));
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
        if (!e.mine || id === root.me)
            root.members = Object.assign({}, root.members, { [id]: member });
        if (!root.keys[id]) keysSoon.restart();
        if (e.kind === "message") root._receive(e, time);
        else root._saveSoon();
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
        // Mine, from this desktop: already here (now sent).
        const known = root.messages.find(m => m.mid === mid);
        if (known) {
            if (known.status !== "sent") root._setStatus(mid, "sent");
            return;
        }
        const m = { mid: mid, from: e.from, name: e.name ?? "", to: e.to ?? "", time: time, text: text,
            mine: !!e.mine, status: "sent" };
        if (file) m.file = file;
        const list = [...root.messages, m].sort((a, b) => a.time - b.time).slice(-500);
        root.messages = list;
        root._saveSoon();
        // At once: the server deletes files after a while.
        if (file && file.size <= root.autoFetchBytes) root.fetchFile(mid);
        if (m.mine) return;
        const conv = root.conversationOf(m);
        if (root.viewing && root.conversation === conv) {
            root.markRead(conv);
            return;
        }
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
        const body = [root.fileLabel(m.file), m.text].filter(t => t).join("\n");
        const image = m.file?.image && m.file?.path ? [`--hint=string:image-path:${m.file.path}`] : [];
        notifier.createObject(root, {
            conv: root.conversationOf(m),
            command: ["notify-send", `--app-name=${who}`, "--icon=avatar-default", ...image,
                `--hint=string:x-nixbook-mesh:${m.to === "" ? "nixbook-mesh-everyone" : "nixbook-mesh-direct"}`,
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

    // -- Setting up (Settings > General > Mesh) ----------------------------------------

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
                root.messages = root.messages.map(m => m.status === "sending" ? Object.assign({}, m, { status: "failed" }) : m);
                root._storeRead = true;
                root._resumeFiles();
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
        root.run(["prune"], JSON.stringify({ keep: root.messages.map(m => m.file?.sha ?? "").filter(s => s !== "") }));
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

    // `nixbook-shell ipc call mesh status|send TEXT|sendTo MEMBER TEXT|sendFile PATH|sendFileTo MEMBER PATH|open|openConversation MEMBER`.
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
        // A member's conversation ("" = everyone).
        function openConversation(member: string): void {
            root.open(member);
        }
    }
}
