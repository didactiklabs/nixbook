pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * KDE Connect state + actions for the bar's `kdeConnect` widget — a port of
 * DankMaterialShell's DankKDEConnect plugin (Phone Connect) without the DMS
 * D-Bus bridge: state is read with busctl by scripts/kdeconnect/
 * kdeconnect-state.sh, actions are busctl method calls.
 *
 * Event-driven: a `gdbus monitor` on org.kde.kdeconnect triggers a debounced
 * refresh on any daemon signal (battery, reachability, pairing, connectivity)
 * and on the daemon appearing/disappearing. The only timer is a slow safety
 * refresh while a paired device is reachable.
 */
Singleton {
    id: root

    property bool available: false
    property bool loaded: false
    property string selfName: ""
    property var devices: []
    property bool refreshing: stateProc.running

    readonly property var pairedDevices: root.devices.filter(d => d.paired)
    readonly property var reachableDevices: root.pairedDevices.filter(d => d.reachable)
    readonly property var pairRequests: root.devices.filter(d => d.pairRequested)
    // The device the bar pill summarizes: first reachable paired one, else the
    // first paired one.
    readonly property var primaryDevice: root.reachableDevices[0] ?? root.pairedDevices[0] ?? null

    property string lastError: ""
    signal actionFinished(string action, bool ok)

    function load() {} // force singleton creation

    function refresh() {
        if (stateProc.running) {
            refreshPending = true;
            return;
        }
        stateProc.running = true;
    }
    property bool refreshPending: false

    function hasPlugin(device, plugin) {
        return (device?.plugins ?? []).includes(plugin);
    }

    // Icon for a device (the daemon's `type` is unreliable: a Pixel reports
    // "tablet"), in the spirit of DMS's per-device type override.
    function deviceIcon(device) {
        if (!device) return "devices";
        const name = (device.name ?? "").toLowerCase();
        if (device.type === "desktop" || device.type === "laptop") return device.type === "laptop" ? "laptop" : "desktop_windows";
        if (device.type === "tv") return "tv";
        if (/tab|pad/.test(name) || (device.type === "tablet" && !root.hasPlugin(device, "telephony") && !root.hasPlugin(device, "mmtelephony")))
            return "tablet_android";
        return "smartphone";
    }

    function batteryIcon(device) {
        const b = device?.battery ?? -1;
        if (b < 0) return "battery_unknown";
        if (device.charging) return "battery_charging_full";
        if (b >= 95) return "battery_full";
        const step = Math.max(0, Math.min(6, Math.floor(b / 100 * 7)));
        return `battery_${step}_bar`;
    }

    function signalIcon(device) {
        const s = device?.signal ?? -1;
        if (s < 0) return "signal_cellular_off";
        return `signal_cellular_${Math.max(0, Math.min(4, s))}_bar`;
    }

    // ---------------------------------------------------------------- actions
    function call(action, deviceId, subPath, iface, method, signature = "", args = []) {
        const path = `/modules/kdeconnect/devices/${deviceId}${subPath ? "/" + subPath : ""}`;
        const cmd = ["busctl", "--user", "call", "org.kde.kdeconnect", path, iface, method];
        if (signature !== "") cmd.push(signature, ...args.map(a => String(a)));
        actionProc.pendingAction = action;
        actionProc.command = cmd;
        actionProc.running = true;
    }

    function ring(id) { root.call("ring", id, "findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring") }
    function ping(id) { root.call("ping", id, "ping", "org.kde.kdeconnect.device.ping", "sendPing") }
    function sendClipboard(id) { root.call("clipboard", id, "clipboard", "org.kde.kdeconnect.device.clipboard", "sendClipboard") }
    function shareUrl(id, url) { root.call("share", id, "share", "org.kde.kdeconnect.device.share", "shareUrl", "s", [url]) }
    function shareText(id, text) { root.call("shareText", id, "share", "org.kde.kdeconnect.device.share", "shareText", "s", [text]) }
    function browse(id) { root.call("browse", id, "sftp", "org.kde.kdeconnect.device.sftp", "startBrowsing") }
    function openSms(id) { root.call("sms", id, "sms", "org.kde.kdeconnect.device.sms", "launchApp") }
    function requestPairing(id) { root.call("pair", id, "", "org.kde.kdeconnect.device", "requestPairing") }
    function acceptPairing(id) { root.call("acceptPair", id, "", "org.kde.kdeconnect.device", "acceptPairing") }
    function rejectPairing(id) { root.call("rejectPair", id, "", "org.kde.kdeconnect.device", "cancelPairing") }
    function unpair(id) { root.call("unpair", id, "", "org.kde.kdeconnect.device", "unpair") }
    function requestPhoto(id) {
        const dir = FileUtils.trimFileProtocol(`${Directories.pictures}`);
        const file = `${dir}/kdeconnect-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")}.jpg`;
        root.call("photo", id, "photo", "org.kde.kdeconnect.device.photo", "requestPhoto", "s", [file]);
    }
    // Ask connected phones for their media players: KDE Connect republishes
    // them as org.mpris.MediaPlayer2.kdeconnect.mpris_* on the session bus, so
    // they appear in the media source selectors. Rate-limited; called when a
    // media panel/selector shows up.
    property real lastPlayerListRequest: 0
    function requestMediaPlayers() {
        if (Date.now() - root.lastPlayerListRequest < 10000)
            return;
        root.lastPlayerListRequest = Date.now();
        for (const d of root.reachableDevices) {
            if (root.hasPlugin(d, "mprisremote"))
                Quickshell.execDetached(["busctl", "--user", "call", "org.kde.kdeconnect",
                    `/modules/kdeconnect/devices/${d.id}/mprisremote`, "org.kde.kdeconnect.device.mprisremote", "requestPlayerList"]);
        }
    }

    // File picker, then share. kdialog is part of the shell's runtime deps.
    function pickAndShareFile(id) {
        filePickProc.deviceId = id;
        filePickProc.running = true;
    }

    Process {
        id: actionProc
        property string pendingAction: ""
        stderr: StdioCollector { id: actionErr }
        onExited: (code) => {
            root.lastError = code === 0 ? "" : (actionErr.text.trim().split("\n")[0] || `exit ${code}`);
            root.actionFinished(actionProc.pendingAction, code === 0);
            root.refresh();
        }
    }

    Process {
        id: filePickProc
        property string deviceId: ""
        command: ["kdialog", "--getopenfilename", FileUtils.trimFileProtocol(`${Directories.home}`)]
        stdout: StdioCollector {
            id: pickedFile
            onStreamFinished: {
                const f = pickedFile.text.trim();
                if (f.length > 0)
                    root.shareUrl(filePickProc.deviceId, "file://" + f);
            }
        }
    }

    // ------------------------------------------------------------------ state
    Process {
        id: stateProc
        command: ["bash", Quickshell.shellPath("scripts/kdeconnect/kdeconnect-state.sh")]
        stdout: StdioCollector {
            id: stateOut
            onStreamFinished: {
                try {
                    const s = JSON.parse(stateOut.text);
                    root.available = s.available;
                    root.selfName = s.selfName ?? "";
                    // Only publish when something changed, so the bar/panel
                    // bindings don't churn on every battery signal.
                    if (JSON.stringify(s.devices) !== JSON.stringify(root.devices))
                        root.devices = s.devices;
                    root.loaded = true;
                } catch (e) {
                    console.log("[KdeConnect] state parse error: " + e);
                }
            }
        }
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Timer {
        id: refreshDebounce
        interval: 400
        onTriggered: root.refresh()
    }

    Process {
        id: monitor
        running: true
        command: ["gdbus", "monitor", "--session", "--dest", "org.kde.kdeconnect"]
        stdout: SplitParser {
            onRead: line => {
                if (line.length > 0)
                    refreshDebounce.restart();
            }
        }
        onExited: monitorRestart.restart()
    }
    Timer {
        id: monitorRestart
        interval: 5000
        onTriggered: monitor.running = true
    }

    // Safety net only (e.g. a missed signal): slow, and only while something
    // is actually connected.
    Timer {
        interval: 120000
        repeat: true
        running: root.reachableDevices.length > 0
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
