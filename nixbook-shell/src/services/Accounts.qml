pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The user's accounts, through `nixbook-accounts` (accounts/, on the shell's
 * PATH): each signed in once (Google with the user's own OAuth client,
 * Google Cloud "Desktop app": DankCalendar's built-in one is for
 * DankCalendar only; CalDAV/CardDAV servers, iCloud, Fastmail, Nextcloud…,
 * with a user name and an app password; and the built-in local account,
 * "This computer", kept on this computer only), their contacts
 * (services/Contacts.qml), tasks (services/Todo.qml) and calendars
 * (services/CalendarEvents.qml) merged.
 *
 * `call` runs a nixbook-accounts command on a lane: one at a time per lane,
 * so a long contacts sync doesn't hold up a task being ticked. The accounts
 * window (modules/ii/accounts/, `openWindow`) lists them, adds one (the
 * one-time Google setup, then the sign-in) and removes one.
 */
Singleton {
    id: root

    readonly property string bin: "nixbook-accounts"

    // [{ id, provider, preset, name, email, username, connected, contacts,
    // tasks (has them), contactsError, tasksError }]
    property var accounts: []
    // Some account (the local one is always there).
    readonly property bool connected: root.accounts.length > 0
    // An account that syncs (not only the local one).
    readonly property bool syncing: root.accounts.some(a => a.provider !== "local")
    // Google's OAuth client set up.
    property bool googleConfigured: false
    property bool statusKnown: false
    // Google's sign-in page, while it waits (for "copy the link").
    property string authUrl: ""
    // A sign-in waiting for the browser.
    property bool connecting: false
    // The last setup or sign-in failure.
    property string lastError: ""
    // Where Google's client comes from and which APIs to enable.
    property var googleSetup: ({ console: "https://console.cloud.google.com/apis/credentials", apis: ({}) })
    // The CalDAV/CardDAV servers offered: { icloud: { name, passwordHelp,
    // needsUrl }, fastmail, nextcloud, custom }.
    property var davPresets: ({})
    // A CalDAV/CardDAV account being checked on its server.
    property bool addingDav: false

    // After an account was added: the services read their copies (the
    // sign-in synced them).
    signal added(var account)

    property bool _started: false
    function load() {
        if (root._started) return
        root._started = true
        root.refreshStatus()
    }

    function openWindow() {
        GlobalStates.accountsOpen = true
    }

    function find(id) {
        return root.accounts.find(a => a.id === id) ?? null
    }
    // An account's name ("" when it is gone).
    function nameOf(id) {
        return root.find(id)?.name ?? ""
    }
    // A short name, for labels next to a list or a contact: the email's
    // local part, else the name.
    function shortName(id) {
        const a = root.find(id)
        if (!a) return ""
        if (a.provider === "local") return Translation.tr("this computer")
        return a.email ? a.email.split("@")[0] : a.name
    }
    // Several accounts: views say which one a thing is in.
    readonly property bool several: root.accounts.length > 1

    // `nixbook-accounts <args…>` on `lane` ("accounts", "contacts", "tasks"
    // or "calendar"); onDone(ok, result, error, code) gets the parsed JSON,
    // or its error message (code 2: sign in again).
    function call(args, onDone, lane) {
        const l = lane === "contacts" ? contactsLane : lane === "tasks" ? tasksLane : lane === "calendar" ? calendarLane : accountsLane
        l.add([root.bin].concat(args), onDone)
    }

    function refreshStatus(then) {
        root.call(["status"], (ok, result) => {
            if (ok && result) {
                root.accounts = result.accounts ?? []
                const google = result.providers?.google ?? {}
                root.googleConfigured = !!google.configured
                root.googleSetup = { console: google.console ?? root.googleSetup.console, apis: google.apis ?? {} }
                root.davPresets = result.providers?.dav?.presets ?? {}
            }
            root.statusKnown = true
            if (then) then()
        })
    }

    // An answer saying an account is signed out (code 2): the status follows.
    function checkAuth(code) {
        if (code === 2) root.refreshStatus()
    }

    // Google's OAuth client: the newest downloaded client_secret*.json, or
    // its two values.
    function setupGoogleFromDownloads(onDone) {
        root._setup(["setup", "google", "--find"], onDone)
    }
    function setupGoogleFromValues(clientId, clientSecret, onDone) {
        root._setup(["setup", "google", "--id", clientId, "--secret", clientSecret], onDone)
    }
    function _setup(args, onDone) {
        root.call(args, (ok, result, error) => {
            root.lastError = ok ? "" : error
            root.refreshStatus()
            if (onDone) onDone(ok, error)
        })
    }

    // A Google account: Google's consent page in the browser, the token
    // back on 127.0.0.1 (up to 5 minutes), then a first sync. The same
    // email again signs that account in anew. Without a client yet: the
    // accounts window, which walks through making one.
    function addGoogle() {
        if (root.connecting) return
        if (!root.googleConfigured) {
            root.openWindow()
            return
        }
        root.connecting = true
        root.authUrl = ""
        root.lastError = ""
        addProc.command = [root.bin, "add", "google"]
        addProc.running = true
    }
    // A CalDAV/CardDAV account: checked on its server (the password, its
    // address books and calendars), then a first sync. The same server and
    // user again signs that account in anew. The password goes on stdin.
    // onDone(ok, error).
    function addDav(preset, url, username, password, name, onDone) {
        if (root.addingDav) return
        const args = [root.bin, "add", "dav", "--preset", preset, "--username", username, "--password-stdin"]
        if (url) args.push("--url", url)
        if (name) args.push("--name", name)
        root.addingDav = true
        root.lastError = ""
        davProc.password = password
        davProc.onDone = onDone ?? null
        davProc.command = args
        davProc.stdinEnabled = true
        davProc.running = true
    }
    // Sign the first signed-out account in again (Google: its sign-in;
    // others: the accounts window), else add one.
    function connect() {
        const out = root.accounts.find(a => !a.connected)
        if (out && out.provider === "google") root.addGoogle()
        else if (root.accounts.length === 0 && root.googleConfigured) root.addGoogle()
        else root.openWindow()
    }
    function cancelAdd() {
        addProc.running = false
    }
    function remove(id, onDone) {
        root.call(["remove", id], (ok, result, error) => {
            if (!ok) root.lastError = error
            root.refreshStatus()
            if (onDone) onDone(ok)
        })
    }

    // A queue of commands run one at a time.
    component Lane: Process {
        id: lane
        property var queue: []
        function add(args, onDone) {
            lane.queue.push({ args: args, onDone: onDone })
            if (lane.queue.length === 1) Qt.callLater(lane.next)
        }
        function next() {
            const n = lane.queue[0]
            if (!n || lane.running) return
            lane.command = n.args
            lane.running = true
        }
        stdout: StdioCollector {
            id: out
        }
        onExited: code => {
            const done = lane.queue.shift()
            if (!done) return
            let result = null
            try {
                result = JSON.parse(out.text)
            } catch (e) {}
            const error = code === 0 ? "" : (result?.error ?? Translation.tr("nixbook-accounts failed (%1)").arg(code))
            if (code !== 0) console.warn(`Accounts: ${done.args.slice(1, 3).join(" ")} failed: ${error}`)
            root.checkAuth(code)
            if (done.onDone) done.onDone(code === 0, result, error, code)
            // Not from inside this process's own exit handler.
            Qt.callLater(lane.next)
        }
    }
    Lane { id: accountsLane }
    Lane { id: contactsLane }
    Lane { id: tasksLane }
    Lane { id: calendarLane }

    // Its first line is the sign-in link, its last the outcome.
    Process {
        id: addProc
        property string last: ""
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line)
                    if (data.authUrl) root.authUrl = data.authUrl
                    else addProc.last = line
                } catch (e) {}
            }
        }
        onExited: code => {
            root.connecting = false
            root.authUrl = ""
            let result = null
            try {
                result = JSON.parse(addProc.last)
            } catch (e) {}
            root.lastError = code === 0 ? "" : (result?.error ?? "")
            addProc.last = ""
            root.refreshStatus(() => {
                if (code === 0) root.added(result?.account ?? null)
            })
        }
    }

    Process {
        id: davProc
        property string password: ""
        property var onDone: null
        stdout: StdioCollector {
            id: davOut
        }
        onRunningChanged: {
            if (!davProc.running) return
            davProc.write(davProc.password + "\n")
            davProc.password = ""
            // End of the password.
            davProc.stdinEnabled = false
        }
        onExited: code => {
            root.addingDav = false
            let result = null
            try {
                result = JSON.parse(davOut.text)
            } catch (e) {}
            const error = code === 0 ? "" : (result?.error ?? Translation.tr("the account couldn't be added"))
            root.lastError = error
            const done = davProc.onDone
            davProc.onDone = null
            root.refreshStatus(() => {
                if (code === 0) root.added(result?.account ?? null)
            })
            if (done) done(code === 0, error)
        }
    }

    // `nixbook-shell ipc call accounts launch|status`.
    IpcHandler {
        target: "accounts"

        // The accounts window: the accounts, add one, remove one.
        function launch(): string {
            root.load();
            root.openWindow();
            return "ok: opened the accounts window";
        }
        function status(): string {
            return JSON.stringify(root.accounts.map(a => ({ id: a.id, provider: a.provider, name: a.name, connected: a.connected })));
        }
    }
}
