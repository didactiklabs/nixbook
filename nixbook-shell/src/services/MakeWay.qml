pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The shell's own windows over the apps (the side panel, Claude's speech
 * bubble, notification popups, a theme's cut-in) making way for an agent
 * working underneath, so its clicks, keys and screenshots reach the app
 * windows while the user still follows the chat:
 *   - `overlays.json` ($XDG_RUNTIME_DIR/nixbook-shell) says which are on
 *     screen, written when that changes: nixbook-desktop-mcp reads it before
 *     an action or a screenshot on the user's desktop (a file read, no IPC);
 *   - with any on screen, it writes `make-way.json` {seq, until, capture}:
 *     until `until` (ms; while each action or screenshot of the agent goes
 *     on, and a moment after), they let clicks through and give up the keyboard, faded a
 *     little, with a word that Claude works underneath; `capture` (its
 *     screenshot being taken) makes them invisible for that moment. Then
 *     they are back as they were: nothing is dismissed or put away. `make-way.ack` says when that is
 *     on screen (a couple of frames after), the server waits for it;
 *   - an action (not a screenshot) asks `clearCutIns` while a theme's cut-in
 *     is on screen: `clearCutIns()` dismisses it and those queued, as Escape
 *     would (they stay in the notification centre), so the agent's keys and
 *     focus aren't fought over;
 *   - `makeWay setAside NAME` (the server's set_aside tool): the popups, a
 *     cut-in or the bubble hidden while the agent works, back when it
 *     stops; never the side panel (it lets the agent through already) nor
 *     the lock screen or a password prompt.
 * The windows read `active`, `capture`, `fade(base, name)`.
 */
Singleton {
    id: root

    readonly property string dir: Directories.runtimeTemp
    property var request: ({})
    property real now: Date.now()
    readonly property bool active: (root.request.until ?? 0) > root.now
    readonly property bool capture: root.active && root.request.capture === true

    // A window's opacity while making way: hidden for a screenshot or set
    // aside, else a little faded (`base`: how much shows, the side panel more
    // than a cut-in).
    function fade(base, name) {
        return root.capture || (root.active && (root.aside[name] ?? false)) ? 0 : root.active ? base : 1
    }
    // Set aside by the agent (by name): hidden while it works, back after.
    property var aside: ({})
    onActiveChanged: if (!root.active) root.aside = {}

    // An agent's action dismisses the cut-ins (each listens), once per request.
    signal clearCutIns()
    property int clearedSeq: -1

    // The theme cut-ins say when they show (several kinds may exist).
    property var cutIns: ({})
    function setCutIn(kind, on) {
        if ((root.cutIns[kind] ?? false) === on) return
        root.cutIns = Object.assign({}, root.cutIns, { [kind]: on })
    }

    readonly property var overlays: {
        const out = []
        if (GlobalStates.sidebarLeftOpen) out.push("sidePanel")
        if (Initiative.speaking !== null) out.push("speechBubble")
        if (Notifications.popupList.length > 0) out.push("notificationPopups")
        if (Object.values(root.cutIns).some(v => v)) out.push("cutIn")
        if (FullAi.active) out.push("fullAi")
        if (Kiroshi.open) out.push("kiroshi")
        return out
    }
    onOverlaysChanged: overlaysWrite.restart()
    Timer {
        id: overlaysWrite
        interval: 30
        onTriggered: overlaysFile.setText(JSON.stringify({ overlays: root.overlays }))
    }
    FileView {
        id: overlaysFile
        path: `${root.dir}/overlays.json`
        blockWrites: true
        printErrors: false
    }
    Component.onCompleted: overlaysWrite.restart()

    FileView {
        id: requestFile
        path: `${root.dir}/make-way.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.request = JSON.parse(text()) ?? {}
            } catch (e) {
                return // caught mid-write: the next change has it
            }
            root.now = Date.now()
            if (root.active) expire.restart()
            if (root.active && root.request.clearCutIns === true && root.request.seq !== root.clearedSeq) {
                root.clearedSeq = root.request.seq ?? -1
                root.clearCutIns()
            }
            // On screen after a couple of frames: then the server goes on.
            acknowledge.restart()
        }
        onLoadFailed: root.request = {}
    }
    Timer {
        id: acknowledge
        interval: 50
        onTriggered: ackFile.setText(String(root.request.seq ?? ""))
    }
    FileView {
        id: ackFile
        path: `${root.dir}/make-way.ack`
        blockWrites: true
        printErrors: false
    }
    // Lifts once `until` is past, without a word from the server.
    Timer {
        id: expire
        interval: Math.max(50, (root.request.until ?? 0) - Date.now() + 20)
        onTriggered: root.now = Date.now()
    }
    // A change caught half-written is read again: the server giving them
    // back is never missed, at most a second late.
    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            requestFile.reload()
            root.now = Date.now()
        }
    }

    IpcHandler {
        target: "makeWay"
        function setAside(name: string): string {
            if (["notificationPopups", "cutIn", "speechBubble"].includes(name)) {
                if (!root.active) return "error: set aside only while you work on the user's desktop"
                root.aside = Object.assign({}, root.aside, { [name]: true })
                return `ok: ${name} hidden while you work; back for the user when you stop`
            }
            if (name === "sidePanel")
                return "error: the side panel is the user's chat with you: leave it; it lets your clicks through and is hidden from your screenshots"
            return `error: no overlay "${name}" (${root.overlays.join(", ") || "none on screen"})`
        }
        function list(): string {
            return JSON.stringify(root.overlays)
        }
    }
}
