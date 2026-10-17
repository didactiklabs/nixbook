pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The contacts of every account (services/Accounts.qml), merged by
 * `nixbook-accounts`.
 *
 * The contacts are nixbook-accounts' local copy
 * ($XDG_STATE_HOME/nixbook-accounts/contacts.json), watched: whatever changes
 * it (this app, a sync, an agent's `contacts` tool) shows at once. Each
 * contact: { id ("<account>:…"), account, name, givenName, familyName, nickname, emails, phones,
 * urls ([{ value, type }]), organization, title, addresses ([{ value, type,
 * street, city, region, postalCode, country }]), birthday ("YYYY-MM-DD" or
 * "--MM-DD"), notes, photo (URL), starred, labels (ids), updated }; each
 * label: { id, account, name, count }.
 *
 * Changes go to Google first (`apply`), their answer lands in the copy.
 * Synced on first use, every 30 minutes, and on demand. A failure lands in
 * `lastError`; `error` is the last sync's.
 */
Singleton {
    id: root

    readonly property string cachePath: {
        const state = Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
        return `${state}/nixbook-accounts/contacts.json`
    }

    // Some account added (Accounts').
    readonly property bool connected: Accounts.connected
    readonly property bool statusKnown: Accounts.statusKnown
    property var contacts: []
    // [{ id, name, count }]
    property var labels: []
    property real syncedAt: 0
    property string error: ""
    property string lastError: ""
    property bool syncing: false

    // Starred first, then by name (the copy is sorted by name).
    readonly property var sorted: root.contacts.filter(c => c.starred).concat(root.contacts.filter(c => !c.starred))
    readonly property var starred: root.contacts.filter(c => c.starred)

    property bool _started: false

    function load() {
        if (root._started) return
        root._started = true
        Accounts.load()
    }

    // Accounts known (at start): sync. An account just added synced
    // already: read the copy.
    Connections {
        target: Accounts
        function onConnectedChanged() {
            if (Accounts.connected && root._started) root.sync()
        }
        function onAdded() {
            cacheFile.reload()
        }
        function onAccountsChanged() {
            cacheFile.reload()
        }
    }

    function find(id) {
        return root.contacts.find(c => c.id === id) ?? null
    }
    function labelName(id) {
        return root.labels.find(l => l.id === id)?.name ?? ""
    }
    function initials(c) {
        const name = (c?.name || c?.organization || c?.emails?.[0]?.value || "?").trim()
        // Words that start with a letter or digit ("(Work)" and "-" skipped).
        const words = name.split(/\s+/).filter(w => w[0] && w[0].toLowerCase() !== w[0].toUpperCase() || /[0-9]/.test(w[0] ?? ""))
        if (words.length === 0) return name[0]?.toUpperCase() ?? "?"
        return (words[0][0] + (words.length > 1 ? words[words.length - 1][0] : "")).toUpperCase()
    }
    function displayName(c) {
        return c?.name || c?.organization || c?.emails?.[0]?.value || c?.phones?.[0]?.value || Translation.tr("(No name)")
    }
    // Google's types (home, work, mobile…) as words; the user's own as is.
    function typeText(type) {
        const known = {
            home: Translation.tr("Home"), work: Translation.tr("Work"), other: Translation.tr("Other"),
            mobile: Translation.tr("Mobile"), main: Translation.tr("Main"), homeFax: Translation.tr("Home fax"),
            workFax: Translation.tr("Work fax"), pager: Translation.tr("Pager"), workMobile: Translation.tr("Work mobile"),
            blog: Translation.tr("Blog"), homePage: Translation.tr("Website"), profile: Translation.tr("Profile"),
        }
        return known[type] ?? type ?? ""
    }
    // A stable colour per contact for its initials.
    function hue(c) {
        let h = 0
        for (const ch of (c?.id ?? "")) h = (h * 31 + ch.charCodeAt(0)) % 360
        return h / 360
    }

    // The next birthday on or after `now`: { date, age (0 when the year is
    // unknown), days } or null.
    function nextBirthday(c, now = new Date()) {
        const m = /^(\d{4}|-)-?(\d{2})-(\d{2})$/.exec(c?.birthday ?? "")
        if (!m) return null
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        let date = new Date(today.getFullYear(), Number(m[2]) - 1, Number(m[3]))
        if (date < today) date = new Date(today.getFullYear() + 1, Number(m[2]) - 1, Number(m[3]))
        const year = m[1].length === 4 ? Number(m[1]) : 0
        return { date: date, age: year ? date.getFullYear() - year : 0, days: Math.round((date - today) / 86400000) }
    }
    // Birthdays within `days`: [{ contact, date, age, days }], soonest first.
    function upcomingBirthdays(days, now = new Date()) {
        const out = []
        for (const c of root.contacts) {
            const b = root.nextBirthday(c, now)
            if (b && b.days <= days) out.push(Object.assign({ contact: c }, b))
        }
        return out.sort((a, b) => a.days - b.days || root.displayName(a.contact).localeCompare(root.displayName(b.contact)))
    }
    // "Today", "Tomorrow", "Fri 24", "Nov 3".
    function birthdayText(b) {
        if (b.days === 0) return Translation.tr("Today")
        if (b.days === 1) return Translation.tr("Tomorrow")
        return Qt.locale().toString(b.date, b.days < 7 ? "ddd d" : "MMM d")
    }

    // Accents and case ignored; every word must match; phone numbers by
    // their digits.
    function fold(s) {
        return (s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    }
    function matches(c, query) {
        const words = query.trim().split(/\s+/).filter(w => w !== "")
        if (words.length === 0) return true
        const hay = root.fold([c.name, c.nickname, c.organization, c.title, c.notes,
            ...c.emails.map(e => e.value), ...c.addresses.map(a => a.value),
            ...c.labels.map(l => root.labelName(l))].join(" "))
        const digits = c.phones.map(p => p.value.replace(/\D/g, "")).join(" ")
        return words.every(w => {
            if (hay.includes(root.fold(w))) return true
            const d = w.replace(/\D/g, "")
            return d.length >= 3 && d.length >= w.length - 3 && digits.includes(d)
        })
    }

    // `nixbook-accounts <args…>` on the contacts lane; the copy may have just
    // been made (a watch misses a new file): read again.
    function call(args, onDone) {
        Accounts.call(args, (ok, result, error, code) => {
            cacheFile.reload()
            if (onDone) onDone(ok, result, error, code)
        }, "contacts")
    }

    function sync(full) {
        if (!root.connected || root.syncing) return
        root.syncing = true
        root.call(full ? ["contacts", "sync", "--full"] : ["contacts", "sync"], () => root.syncing = false)
    }

    // Runs changes ({ op, … } or a list of them); onDone(results) with
    // [{ ok, result | error }], the first error also in lastError.
    function apply(ops, onDone) {
        const request = Array.isArray(ops) ? { ops: ops } : ops
        root.call(["contacts", "apply", JSON.stringify(request)], (ok, result, error, code) => {
            const results = ok && Array.isArray(result) ? result : [{ ok: false, error: error || Translation.tr("nixbook-accounts failed") }]
            const failed = results.find(r => !r.ok)
            root.lastError = failed ? failed.error : ""
            if (onDone) onDone(results)
        })
    }
    function create(fields, onDone) {
        root.apply(Object.assign({ op: "create" }, fields), r => onDone?.(r[0]))
    }
    function update(id, fields, onDone) {
        root.apply(Object.assign({ op: "update", id: id }, fields), r => onDone?.(r[0]))
    }
    function remove(id, onDone) {
        root.apply({ op: "delete", id: id }, r => onDone?.(r[0]))
    }
    function setStarred(id, starred) {
        root.apply({ op: starred ? "star" : "unstar", id: id })
    }

    Timer {
        interval: 30 * 60 * 1000
        running: root._started && root.connected
        repeat: true
        onTriggered: root.sync()
    }

    FileView {
        id: cacheFile
        path: root._started ? root.cachePath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(cacheFile.text())
                root.contacts = Array.isArray(data.contacts) ? data.contacts : []
                root.labels = Array.isArray(data.labels) ? data.labels : []
                root.syncedAt = data.syncedAt ?? 0
                root.error = data.error ?? ""
            } catch (e) {
                console.warn("Contacts: unreadable local copy: " + e)
            }
        }
    }

    // `nixbook-shell ipc call contacts show|open ID|toggle|close|sync`.
    IpcHandler {
        target: "contacts"

        function show(): string {
            root.load();
            GlobalStates.openContactsApp("");
            return "ok: opened the Contacts app";
        }
        // The Contacts app, on that contact ("" for none).
        function open(id: string): string {
            root.load();
            if (id && root.contacts.length > 0 && !root.find(id))
                return `error: no contact "${id}"`;
            GlobalStates.openContactsApp(id);
            return "ok: opened the Contacts app";
        }
        function toggle(): void {
            if (GlobalStates.contactsAppOpen) {
                GlobalStates.contactsAppOpen = false;
            } else {
                root.load();
                GlobalStates.openContactsApp("");
            }
        }
        function close(): void {
            GlobalStates.contactsAppOpen = false;
        }
        function sync(): string {
            root.load();
            root.sync(false);
            return "ok";
        }
    }
}
