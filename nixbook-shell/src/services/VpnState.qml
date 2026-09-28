pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shared Tailscale + NetBird state behind the bar VPN widget.
 *
 * The bar is instantiated once per monitor, so keeping the polling here instead
 * of in the widget means a multi-monitor machine runs one set of probes rather
 * than one per screen.
 *
 * Polling policy (battery): status only, at 15 s while nothing is on screen and
 * 4 s while the panel is open or a command is in flight. The account and
 * profile lists are cached and only refreshed on demand — panel open, or right
 * after a mutation — never on a timer.
 *
 * Process starts go through kick(), which queues a rerun instead of silently
 * doing nothing when the process is already in flight. The old widget set
 * `running = true` unconditionally, so whenever the poll happened to be running
 * at the moment a Tailscale switch finished, the refresh was dropped and the
 * panel kept showing the previous account.
 */
Singleton {
    id: root

    // -------------------------------------------------------------- Tailscale
    property bool tsAvailable: false
    property bool tsConnected: false
    property string tsStatusText: "Disconnected"
    property string tsIp: ""
    property var tsNetworks: []
    property string tsSelectedNetwork: ""
    property var tsExitNodes: []
    property string tsExitNode: ""
    property real tsNetworksFetchedAt: 0

    // ---------------------------------------------------------------- NetBird
    property bool nbAvailable: false
    property bool nbConnected: false
    property string nbStatusText: "Disconnected"
    property string nbIp: ""
    property string nbPeerCount: "0"
    property var nbProfiles: []
    property string nbSelectedProfile: ""
    property real nbProfilesFetchedAt: 0

    // --------------------------------------------------------- operation state
    property string op: "" // "", "tsToggle" | "tsSwitch" | "tsExit" | "nbToggle" | "nbSelect"
    property string opTarget: ""
    property string opError: ""
    property string tsPrevSelected: ""
    property string tsPrevExit: ""
    property string nbPrevProfile: ""
    signal operationFinished(kind: string, ok: bool)

    property bool probeDone: false
    property int openPanels: 0
    property bool fastPoll: false
    readonly property bool busy: op !== ""

    function panelOpened() {
        root.openPanels += 1
        if (root.openPanels === 1) {
            root.refreshStatus()
            root.refreshLists(false)
        }
        root.updatePollRate()
    }

    function panelClosed() {
        root.openPanels = Math.max(0, root.openPanels - 1)
        root.updatePollRate()
    }

    function updatePollRate() {
        const want = root.openPanels > 0 || root.busy
        const interval = want ? 4000 : 15000
        if (want === root.fastPoll && pollTimer.interval === interval) return
        root.fastPoll = want
        pollTimer.interval = interval
        pollTimer.restart()
    }

    onBusyChanged: root.updatePollRate()

    function refreshStatus() {
        if (root.tsAvailable) root.kick(tsStatusProc)
        if (root.nbAvailable) root.kick(nbStatusProc)
    }

    function refreshLists(force = false) {
        const now = Date.now()
        if (root.tsAvailable && (force || now - root.tsNetworksFetchedAt > 30000))
            root.kick(tsNetworksProc)
        if (root.nbAvailable && (force || now - root.nbProfilesFetchedAt > 30000))
            root.kick(nbProfilesProc)
    }

    function refresh() {
        root.refreshStatus()
        root.refreshLists(true)
    }

    // Setting `running = true` on an in-flight Process is a no-op, which is how
    // refreshes used to get dropped. Queue one rerun instead.
    function kick(p) {
        if (p.running) {
            p.pending = true
            return
        }
        p.running = true
    }

    function settle(p) {
        if (p.pending) {
            p.pending = false
            p.running = true
        }
    }

    function describeError(code, stderr) {
        const line = (stderr || "").split("\n").map(s => s.trim()).filter(s => s.length > 0)[0]
        if (line) return line
        return `Command failed (${code})`
    }

    function beginOp(kind, target) {
        if (root.busy) return false
        root.opError = ""
        root.op = kind
        root.opTarget = target
        root.updatePollRate()
        return true
    }

    function finishOp(ok, message = "") {
        const kind = root.op
        root.opError = ok ? "" : (message || root.opError)
        root.op = ""
        root.opTarget = ""
        root.updatePollRate()
        root.operationFinished(kind, ok)
    }

    Timer {
        id: opTimeout
        interval: 20000
        onTriggered: {
            if (!root.busy) return
            console.log(`[VpnState] ${root.op} timed out`)
            root.finishOp(false, "Timed out")
            root.refreshStatus()
            root.refreshLists(true)
        }
    }

    onOpChanged: {
        if (root.busy) opTimeout.restart()
        else opTimeout.stop()
    }

    // Binary presence probe: when a backend is not installed we never poll it,
    // instead of spawning a failing command forever.
    Process {
        id: probeProc
        running: true
        command: ["bash", "-c", "command -v tailscale >/dev/null 2>&1 && echo ts; command -v netbird >/dev/null 2>&1 && echo nb"]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: {
                const found = (probeOut.text || "").split(/\s+/)
                root.tsAvailable = found.includes("ts")
                root.nbAvailable = found.includes("nb")
                root.probeDone = true
                if (root.tsAvailable || root.nbAvailable) {
                    root.refreshStatus()
                    root.refreshLists(true)
                    root.updatePollRate()
                }
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 15000
        repeat: true
        running: root.probeDone && (root.tsAvailable || root.nbAvailable)
        onTriggered: root.refreshStatus()
    }

    // ------------------------------------------------------------- Tailscale

    Process {
        id: tsStatusProc
        property bool pending: false
        // StdioCollector gathers the output natively. The former SplitParser +
        // `buffer += line` built hundreds of ever-longer QML strings per poll
        // (the JSON is pretty-printed), and that garbage forced a full V4 GC
        // over the whole shell: a ~200 ms GUI stall every poll.
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: tsStatusCollector
        }
        onExited: (code) => {
            if (code === 0 || tsStatusCollector.text.length > 0)
                root.tsParseStatus(tsStatusCollector.text)
            else
                root.tsReset()
            root.settle(tsStatusProc)
        }
    }

    function tsReset() {
        tsConnected = false
        tsStatusText = "Disconnected"
        tsIp = ""
        tsExitNodes = []
        tsExitNode = ""
    }

    function tsParseStatus(output) {
        try {
            const data = JSON.parse(output)
            const state = data.BackendState || "Stopped"
            tsConnected = state === "Running"
            if (tsConnected) {
                const ips = data.TailscaleIPs || []
                tsIp = ips.length > 0 ? ips[0] : ""
                tsStatusText = "Connected"
                const nodes = []
                let curExit = ""
                const peers = data.Peer || {}
                for (const key in peers) {
                    const peer = peers[key]
                    if (peer.ExitNodeOption) {
                        nodes.push({
                            hostname: peer.HostName || "",
                            ip: (peer.TailscaleIPs && peer.TailscaleIPs.length > 0) ? peer.TailscaleIPs[0] : "",
                            online: peer.Online || false,
                            active: peer.ExitNode || false,
                            country: (peer.Location && peer.Location.Country) ? peer.Location.Country : "",
                            city: (peer.Location && peer.Location.City) ? peer.Location.City : ""
                        })
                        if (peer.ExitNode) curExit = peer.HostName || ""
                    }
                }
                tsExitNodes = nodes
                tsExitNode = curExit
            } else {
                tsIp = ""
                tsExitNodes = []
                tsExitNode = ""
                tsStatusText = state !== "Stopped" ? state : "Disconnected"
            }
        } catch (e) {
            console.log("VpnState: tailscale status parse error: " + e)
        }
    }

    Process {
        id: tsNetworksProc
        property bool pending: false
        property var rows: []
        command: ["tailscale", "switch", "--list"]
        onStarted: rows = []
        stdout: SplitParser {
            onRead: line => root.tsParseNetworkLine(line)
        }
        onExited: (code) => {
            if (code === 0) {
                root.tsNetworks = rows
                root.tsNetworksFetchedAt = Date.now()
            }
            root.settle(tsNetworksProc)
        }
    }

    function tsParseNetworkLine(line) {
        const trimmed = line.trim()
        if (!trimmed || trimmed.startsWith("ID") || trimmed.startsWith("---")) return
        const parts = trimmed.split(/\s+/)
        if (parts.length < 3) return
        let account = parts[2]
        let selected = false
        if (account.endsWith("*")) {
            selected = true
            account = account.slice(0, -1)
            root.tsSelectedNetwork = parts[1]
        }
        tsNetworksProc.rows.push({ id: parts[0], name: parts[1], account: account, selected: selected })
    }

    function tsToggle() {
        if (!root.tsAvailable) return
        if (!root.beginOp("tsToggle", root.tsConnected ? "down" : "up")) return
        tsStatusText = root.tsConnected ? "Disconnected" : "Connecting…"
        tsToggleProc.command = ["tailscale", root.opTarget]
        tsToggleProc.err = ""
        tsToggleProc.running = true
    }

    Process {
        id: tsToggleProc
        property string err: ""
        stderr: StdioCollector {
            id: tsToggleErr
            onStreamFinished: tsToggleProc.err = tsToggleErr.text
        }
        onExited: (code) => {
            const ok = code === 0
            if (root.op === "tsToggle")
                root.finishOp(ok, ok ? "" : root.describeError(code, tsToggleProc.err))
            tsToggleProc.err = ""
            root.refreshStatus()
        }
    }

    function tsSwitchNetwork(name) {
        if (!root.tsAvailable) return
        if (root.busy || !name) return
        if (name === root.tsSelectedNetwork && root.opError === "") return
        if (!root.beginOp("tsSwitch", name)) return
        tsPrevSelected = tsSelectedNetwork
        tsSelectedNetwork = name
        tsSwitchProc.command = ["tailscale", "switch", name]
        tsSwitchProc.err = ""
        tsSwitchProc.running = true
    }

    Process {
        id: tsSwitchProc
        property string err: ""
        stderr: StdioCollector {
            id: tsSwitchErr
            onStreamFinished: tsSwitchProc.err = tsSwitchErr.text
        }
        onExited: (code) => {
            const ok = code === 0
            if (root.op === "tsSwitch") {
                if (!ok) root.tsSelectedNetwork = root.tsPrevSelected
                root.finishOp(ok, ok ? "" : root.describeError(code, tsSwitchProc.err))
            }
            tsSwitchProc.err = ""
            root.kick(tsStatusProc)
            root.kick(tsNetworksProc)
        }
    }

    function tsSetExitNode(hostname) {
        if (!root.tsAvailable) return
        if (!root.beginOp("tsExit", hostname ?? "")) return
        tsPrevExit = tsExitNode
        tsExitNode = opTarget
        tsExitProc.command = ["tailscale", "set", "--exit-node=" + opTarget]
        tsExitProc.err = ""
        tsExitProc.running = true
    }

    function tsClearExitNode() {
        if (!root.tsAvailable) return
        if (!root.beginOp("tsExit", "")) return
        tsPrevExit = tsExitNode
        tsExitNode = ""
        tsExitProc.command = ["tailscale", "set", "--exit-node="]
        tsExitProc.err = ""
        tsExitProc.running = true
    }

    Process {
        id: tsExitProc
        property string err: ""
        stderr: StdioCollector {
            id: tsExitErr
            onStreamFinished: tsExitProc.err = tsExitErr.text
        }
        onExited: (code) => {
            const ok = code === 0
            if (root.op === "tsExit") {
                if (!ok) root.tsExitNode = root.tsPrevExit
                root.finishOp(ok, ok ? "" : root.describeError(code, tsExitProc.err))
            }
            tsExitProc.err = ""
            root.kick(tsStatusProc)
        }
    }

    // ---------------------------------------------------------------- NetBird

    Process {
        id: nbStatusProc
        property bool pending: false
        // StdioCollector gathers the output natively. The former SplitParser +
        // `buffer += line` built hundreds of ever-longer QML strings per poll
        // (the JSON is pretty-printed), and that garbage forced a full V4 GC
        // over the whole shell: a ~200 ms GUI stall every poll.
        command: ["netbird", "status", "--json"]
        stdout: StdioCollector {
            id: nbStatusCollector
        }
        onExited: (code) => {
            if (code === 0 && nbStatusCollector.text.trim())
                root.nbParseStatus(nbStatusCollector.text)
            else
                root.nbReset()
            root.settle(nbStatusProc)
        }
    }

    function nbReset() {
        nbConnected = false
        nbStatusText = "Disconnected"
        nbPeerCount = "0"
        nbIp = ""
    }

    function nbParseStatus(output) {
        try {
            const data = JSON.parse(output)
            const connectedPeers = data.peers?.connected ?? 0
            if (data.profileName) nbSelectedProfile = data.profileName
            nbConnected = connectedPeers > 0 || (data.management?.connected ?? false)
            if (nbConnected) {
                nbStatusText = connectedPeers > 0 ? "Connected (" + connectedPeers + ")" : "Connecting"
                nbPeerCount = connectedPeers.toString()
                nbIp = data.netbirdIp || ""
            } else {
                nbReset()
            }
        } catch (e) {
            nbReset()
        }
    }

    Process {
        id: nbProfilesProc
        property bool pending: false
        property var rows: []
        command: ["netbird", "profile", "list"]
        onStarted: rows = []
        stdout: SplitParser {
            onRead: line => root.nbParseProfileLine(line)
        }
        onExited: (code) => {
            if (code === 0) {
                root.nbProfiles = rows
                root.nbProfilesFetchedAt = Date.now()
                let found = ""
                for (let i = 0; i < rows.length; i++) {
                    if (rows[i].selected) {
                        found = rows[i].name
                        break
                    }
                }
                root.nbSelectedProfile = found
            }
            root.settle(nbProfilesProc)
        }
    }

    function nbParseProfileLine(line) {
        const trimmed = line.trim()
        if (!trimmed || trimmed.startsWith("Found")) return
        // Header row: "NAME     ACTIVE"
        if (/^NAME\s+ACTIVE$/.test(trimmed)) return
        // Marker is a trailing "✓" on the active row (may be padded), not a prefix.
        const selected = /✓\s*$/.test(trimmed)
        const name = trimmed.replace(/\s*[✓✗]\s*$/, "").trim()
        if (!name || name === "NAME") return
        nbProfilesProc.rows.push({ id: name, name: name, selected: selected })
    }

    function nbToggle() {
        if (!root.nbAvailable) return
        if (!root.beginOp("nbToggle", root.nbConnected ? "down" : "up")) return
        nbStatusText = root.nbConnected ? "Disconnected" : "Connecting…"
        nbToggleProc.command = ["netbird", root.opTarget]
        nbToggleProc.err = ""
        nbToggleProc.running = true
    }

    Process {
        id: nbToggleProc
        property string err: ""
        stderr: StdioCollector {
            id: nbToggleErr
            onStreamFinished: nbToggleProc.err = nbToggleErr.text
        }
        onExited: (code) => {
            const ok = code === 0
            if (root.op === "nbToggle")
                root.finishOp(ok, ok ? "" : root.describeError(code, nbToggleProc.err))
            nbToggleProc.err = ""
            root.refreshStatus()
        }
    }

    function nbSelectProfile(name) {
        if (!root.nbAvailable) return
        if (root.busy || !name) return
        if (name === root.nbSelectedProfile && root.opError === "") return
        if (!root.beginOp("nbSelect", name)) return
        nbPrevProfile = nbSelectedProfile
        nbSelectedProfile = name
        nbSelectProc.command = ["netbird", "profile", "select", name]
        nbSelectProc.err = ""
        nbSelectProc.running = true
    }

    Process {
        id: nbSelectProc
        property string err: ""
        stderr: StdioCollector {
            id: nbSelectErr
            onStreamFinished: nbSelectProc.err = nbSelectErr.text
        }
        onExited: (code) => {
            const ok = code === 0
            if (root.op === "nbSelect") {
                if (!ok) root.nbSelectedProfile = root.nbPrevProfile
                root.finishOp(ok, ok ? "" : root.describeError(code, nbSelectProc.err))
            }
            nbSelectProc.err = ""
            root.kick(nbStatusProc)
            root.kick(nbProfilesProc)
        }
    }
}
