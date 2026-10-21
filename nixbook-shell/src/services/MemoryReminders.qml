pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

/**
 * Reminders agents set for the user ("when I open Gmail, remind me to label
 * the invoices": the desktop memory's `triggers`, written by the `remind`
 * tool of nixbook-desktop-mcp): checked in plain code on each focus or
 * title change and every half minute, shown as a notification (app
 * "Reminder"), then fired (`nixbook-desktop-mcp memory fire ID`): gone, or
 * not again before tomorrow (repeat). A reminder's cues: an app (`match`:
 * the app ids it may have), words in a window's title, a time (`after`,
 * epoch s); all it has must hold.
 */
Singleton {
    id: root

    readonly property string memoryPath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/nixbook-shell/desktop-memory.json`
    property var triggers: []
    // Fired here, until the memory file says so too.
    property var fired: ({})

    function load() {
        memoryFile.reload()
    }

    function _matches(t, appId, title, now) {
        if (t.after && now < t.after * 1000) return false
        if (t.expires && now > t.expires * 1000) return false
        if (t.match?.length) {
            const app = (appId ?? "").toLowerCase()
            if (!app || !t.match.some(m => app === m || (m.length >= 3 && app.includes(m)))) return false
        }
        if (t.title && !(title ?? "").toLowerCase().includes(t.title)) return false
        // A time-only reminder fires at its time; a cue-only one on its cue.
        return true
    }

    function check() {
        if (root.triggers.length === 0) return
        const w = ToplevelManager.activeToplevel
        const now = Date.now()
        for (const t of root.triggers) {
            if (root.fired[t.id]) continue
            // An app or title cue needs a window that has it.
            if ((t.match?.length || t.title) && !w) continue
            if (!root._matches(t, w?.appId, w?.title, now)) continue
            root.fired = Object.assign({}, root.fired, { [t.id]: now })
            Quickshell.execDetached(["notify-send", "--app-name=Reminder", "--icon=alarm", "--urgency=normal",
                Translation.tr("Reminder"), t.text])
            Quickshell.execDetached(["nixbook-desktop-mcp", "memory", "fire", t.id])
        }
    }

    property string _triggersSig: ""
    Timer {
        id: memoryReloadTimer
        interval: 500
        onTriggered: memoryFile.reload()
    }
    FileView {
        id: memoryFile
        path: root.memoryPath
        watchChanges: true
        printErrors: false
        // Agents' tool calls rewrite it (usage counts) about once a second
        // while they act: read it once a burst settles, and only take the
        // triggers when they changed.
        onFileChanged: memoryReloadTimer.restart()
        onLoaded: {
            try {
                const data = JSON.parse(memoryFile.text())
                const next = Array.isArray(data.triggers) ? data.triggers : []
                const sig = JSON.stringify(next)
                if (sig !== root._triggersSig) {
                    root._triggersSig = sig
                    root.triggers = next
                    // Fired ones the file no longer has (or has for tomorrow)
                    // are done; the others wait for the file.
                    const kept = {}
                    for (const t of root.triggers)
                        if (root.fired[t.id] && !(t.after && t.after * 1000 > root.fired[t.id])) kept[t.id] = root.fired[t.id]
                    root.fired = kept
                }
            } catch (e) {
                root._triggersSig = ""
                root.triggers = []
            }
            root.check()
        }
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.check()
        }
    }

    Connections {
        target: ToplevelManager.activeToplevel
        ignoreUnknownSignals: true
        function onTitleChanged() {
            root.check()
        }
    }

    Timer {
        interval: 30000
        running: root.triggers.length > 0
        repeat: true
        onTriggered: root.check()
    }
}
