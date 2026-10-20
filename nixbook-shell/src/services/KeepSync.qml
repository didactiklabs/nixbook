pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The notes' sync with Google Keep.
 *
 * Google has no public Keep API (only for Workspace), so the sync goes
 * through gkeepapi (the unofficial client), in `nixbook-keep`
 * (scripts/keep-sync.py): it authenticates with the account's email and
 * master token, merges the shell's notes (services/Notes.qml) with the
 * account's Keep notes and hands the merged list back. The credentials live
 * in the keyring, never in the notes file nor in the settings.
 *
 * The notes are merged both ways: a note changed here is pushed to Keep, a
 * note changed there comes back. Deletions are not synced (a note deleted in
 * one place stays in the other, and is not brought back). The notes' Keep id
 * ("keepId") and the moment of the last sync ("keepEdited") travel with each
 * note, so the sync knows which side changed.
 *
 * The sync runs when the user asks for it (the Keep panel of the Notes app,
 * or `nixbook-shell ipc call keep sync`), and on its own every
 * `keep.refreshMinutes` when `keep.enable` is on and an account is set.
 */
Singleton {
    id: root

    readonly property string bin: "nixbook-keep"

    // The account (its credentials are in the keyring).
    property bool configured: false
    property string email: ""
    // The last sync.
    property bool syncing: false
    property real lastSync: 0
    property string lastError: ""
    // What the last sync did: { pushed, pulled, created, imported, linked,
    // conflicts, skipped }.
    property var stats: ({})

    // The directions (keep.push, keep.pull).
    readonly property bool pushEnabled: Config.options?.keep?.push ?? true
    readonly property bool pullEnabled: Config.options?.keep?.pull ?? true

    property bool _started: false
    // The notes as they were when the sync started ({ id: note }): a note
    // changed, added or removed while it ran keeps that change (the merged
    // copy of it is stale), and the sync runs again, once, to send it.
    property var _sent: ({})
    property bool _resynced: false
    // The account being signed in (the credentials go to the keyring, they
    // are not kept here).
    property string _loginEmail: ""
    property string _loginToken: ""

    function load() {
        if (root._started) return
        root._started = true
        root.refreshStatus()
    }

    // The account's state: is there one, and what is its email.
    function refreshStatus(then) {
        statusProc.running = true
        statusProc.onDone = then ?? null
    }

    // Signs in: the email and the master token (checked against Keep right
    // away, so a wrong one is said now).
    function login(email, token, then) {
        if (root.syncing) return
        root.lastError = ""
        root._loginEmail = (email ?? "").trim()
        root._loginToken = (token ?? "").trim()
        if (!root._loginEmail || !root._loginToken) {
            root.lastError = Translation.tr("the email and the master token are needed")
            return
        }
        // The channel is opened before the start, else the script reads
        // nothing.
        loginProc.stdinEnabled = true
        loginProc.running = true
        loginProc.onDone = then ?? null
    }

    // Forgets the account (the notes stay).
    function logout(then) {
        logoutProc.running = true
        logoutProc.onDone = then ?? null
    }

    // The sync: the notes go in, the merged notes come back and replace them.
    function sync(then) {
        if (root.syncing) return
        if (!root.configured) {
            root.lastError = Translation.tr("no Google Keep account yet")
            if (then) then(false, root.lastError)
            return
        }
        root.syncing = true
        root.lastError = ""
        root._sent = root._stamps()
        syncProc.payload = JSON.stringify({
            notes: Notes.list,
            push: root.pushEnabled,
            pull: root.pullEnabled
        })
        // The channel is opened before the start, else the script reads
        // nothing.
        syncProc.stdinEnabled = true
        syncProc.running = true
        syncProc.onDone = then ?? null
    }

    // Each note's text and pin as sent: what changed while the sync ran.
    function _stamps() {
        const stamps = {}
        for (const n of Notes.list) stamps[n.id] = { content: n.content, pinned: !!n.pinned }
        return stamps
    }

    // The sync's answer: the merged notes replace the current ones, except
    // what changed here while it ran (typed, pinned, added, deleted), which
    // stays as it is now: the merged copy of it is stale.
    function _apply(answer, then) {
        root.stats = answer.stats ?? {}
        root.lastSync = root.stats.lastSync ?? Date.now()
        const merged = answer.notes ?? []
        const sent = root._sent
        const current = {}
        for (const n of Notes.list) current[n.id] = n
        const result = []
        const seen = {}
        let stale = false
        for (const m of merged) {
            seen[m.id] = true
            if (!Object.prototype.hasOwnProperty.call(sent, m.id)) {
                // From Keep.
                result.push(m)
                continue
            }
            const now = current[m.id]
            const was = sent[m.id]
            if (!now) {
                // Deleted here meanwhile.
                stale = true
                continue
            }
            // Changed here meanwhile: what changed (the text, the pin) stays
            // as it is now, on the merged note (linked to its Keep note, so
            // a note just created there isn't created twice).
            const changes = {}
            if (now.content !== was.content) {
                changes.content = now.content
                changes.updatedAt = now.updatedAt
                changes.attachments = now.attachments
            }
            if (!!now.pinned !== was.pinned)
                changes.pinned = !!now.pinned
            if (Object.keys(changes).length > 0) {
                stale = true
                result.push(Object.assign({}, m, changes))
            } else {
                result.push(m)
            }
        }
        // Added here meanwhile. A note that was sent and isn't in the answer
        // was removed by the merge (deleted in Keep): it stays removed.
        for (const n of Notes.list) {
            if (!seen[n.id] && !Object.prototype.hasOwnProperty.call(sent, n.id)) {
                stale = true
                result.push(n)
            }
        }
        Notes.applySynced(result)
        // What changed meanwhile is sent now (once), with the same callback.
        if (stale && !root._resynced) {
            root._resynced = true
            root.sync(then)
            return false
        }
        root._resynced = false
        return true
    }

    // -- The commands ----------------------------------------------------------

    Process {
        id: statusProc
        property var onDone: null
        command: [root.bin, "status"]
        stdout: StdioCollector {
            id: statusOut
        }
        onExited: code => {
            let answer = null
            try {
                answer = JSON.parse(statusOut.text)
            } catch (e) {}
            if (answer) {
                root.configured = !!answer.configured
                root.email = answer.email ?? ""
                root.lastSync = answer.lastSync ?? root.lastSync
            }
            const done = statusProc.onDone
            statusProc.onDone = null
            if (done) done(code === 0, answer)
        }
    }

    Process {
        id: loginProc
        property var onDone: null
        command: [root.bin, "login"]
        stdout: StdioCollector {
            id: loginOut
        }
        onRunningChanged: {
            if (!loginProc.running) return
            loginProc.write(`${root._loginEmail}\n${root._loginToken}\n`)
            root._loginEmail = ""
            root._loginToken = ""
            loginProc.stdinEnabled = false
        }
        onExited: code => {
            let answer = null
            try {
                answer = JSON.parse(loginOut.text)
            } catch (e) {}
            if (code !== 0) {
                root.lastError = answer?.error ?? Translation.tr("the sign-in failed")
                root.configured = false
            } else {
                root.lastError = ""
                root.configured = true
                root.email = answer?.email ?? root.email
                // The first sync right away: the notes are already there.
                root.sync()
            }
            const done = loginProc.onDone
            loginProc.onDone = null
            if (done) done(code === 0, root.lastError)
        }
    }

    Process {
        id: logoutProc
        property var onDone: null
        command: [root.bin, "logout"]
        stdout: StdioCollector {
            id: logoutOut
        }
        onExited: code => {
            root.configured = false
            root.email = ""
            root.lastError = ""
            const done = logoutProc.onDone
            logoutProc.onDone = null
            if (done) done(code === 0)
        }
    }

    Process {
        id: syncProc
        property string payload: ""
        property var onDone: null
        command: [root.bin, "sync"]
        stdout: StdioCollector {
            id: syncOut
        }
        onRunningChanged: {
            if (!syncProc.running) return
            syncProc.write(syncProc.payload + "\n")
            syncProc.payload = ""
            syncProc.stdinEnabled = false
        }
        onExited: code => {
            root.syncing = false
            let answer = null
            try {
                answer = JSON.parse(syncOut.text)
            } catch (e) {}
            if (code !== 0 || !answer || answer.error) {
                root.lastError = answer?.error ?? Translation.tr("the sync failed")
                root._resynced = false
                const failed = syncProc.onDone
                syncProc.onDone = null
                if (failed) failed(false, root.lastError)
                return
            }
            root.lastError = ""
            const done = syncProc.onDone
            syncProc.onDone = null
            const applied = root._apply(answer, done)
            // A stale answer: the sync runs again, and its own answer is the
            // one that counts.
            if (applied && done) done(true, "")
        }
    }

    // -- On its own ------------------------------------------------------------

    // The sync on its own, every keep.refreshMinutes.
    Timer {
        interval: Math.max(1, Config.options?.keep?.refreshMinutes ?? 15) * 60 * 1000
        running: root._started && root.configured && (Config.options?.keep?.enable ?? true)
        repeat: true
        onTriggered: root.sync()
    }

    // The first sync once the shell is up (a minute, so the notes are read).
    Timer {
        interval: 60000
        running: root._started && root.configured && (Config.options?.keep?.enable ?? true)
        repeat: false
        onTriggered: root.sync()
    }

    // `nixbook-shell ipc call keep status|sync`.
    IpcHandler {
        target: "keep"

        function status(): string {
            root.load();
            return JSON.stringify({
                configured: root.configured,
                email: root.email,
                lastSync: root.lastSync,
                error: root.lastError
            });
        }
        function sync(): string {
            root.load();
            root.sync();
            return root.syncing ? "ok: the sync is running" : "ok: the sync is done";
        }
    }
}
