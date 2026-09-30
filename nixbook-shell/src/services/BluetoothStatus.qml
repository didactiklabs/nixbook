pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false

    // BlueZ can leave Device1.Connected false when a device reconnects on its
    // own, while audio, AVRCP and battery reporting are all live
    // (https://github.com/bluez/bluez/issues/2485). Battery1 is only exported
    // while a device is connected, so count it as a connection too.
    function isConnected(device): bool {
        return !!device && (device.connected || device.batteryAvailable);
    }

    readonly property BluetoothDevice firstActiveDevice: Bluetooth.devices.values.find(device => root.isConnected(device)) ?? null
    readonly property int activeDeviceCount: Bluetooth.devices.values.filter(device => root.isConnected(device)).length
    readonly property bool connected: Bluetooth.devices.values.some(d => root.isConnected(d))

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => root.isConnected(d)).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !root.isConnected(d)).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !root.isConnected(d)).sort(sortFunction)
    readonly property list<var> connectedBatteryDevices: connectedDevices.filter(device => device.batteryAvailable && Number.isFinite(Number(device.battery)))
    readonly property var primaryConnectedDevice: firstActiveDevice ?? connectedDevices[0] ?? null
    readonly property var primaryBatteryDevice: hasBattery(primaryConnectedDevice)
        ? primaryConnectedDevice
        : connectedBatteryDevices[0] ?? null
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    function hasBattery(device): bool {
        return !!device && device.batteryAvailable && Number.isFinite(Number(device.battery));
    }

    function togglePower() {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter) return;
        adapter.enabled = !adapter.enabled;
    }

    // Discovery, wanted while the devices dialog is open. It is paused while a
    // device action runs: BlueZ connects and pairs classic devices (headsets)
    // unreliably during an inquiry scan (br-connection-busy, page timeouts).
    property bool discoveryWanted: false
    onDiscoveryWantedChanged: {
        if (discoveryWanted && Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.enabled = true;
        syncDiscovery();
    }
    onBusyChanged: syncDiscovery()
    function syncDiscovery() {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter) return;
        const want = discoveryWanted && !busy;
        if (adapter.discovering !== want) adapter.discovering = want;
    }

    // Device actions call BlueZ directly instead of BluetoothDevice's
    // connect()/disconnect(), which refuse from Quickshell's cached state:
    // "already connecting" once a Connect() succeeded without Connected ever
    // flipping, "already disconnected" for the devices isConnected() counts
    // through Battery1 alone, so their Disconnect button did nothing.
    readonly property bool busy: busyDevicePath !== ""
    property string busyDevicePath: ""
    property string busyAction: ""
    property string failedDevicePath: ""
    property string failedMessage: ""

    function connectDevice(device) {
        runDeviceAction(device, "connect", 'busctl --system --timeout=60 call org.bluez "$DEV" org.bluez.Device1 Connect');
    }
    function disconnectDevice(device) {
        runDeviceAction(device, "disconnect", 'busctl --system --timeout=30 call org.bluez "$DEV" org.bluez.Device1 Disconnect');
    }
    // "Always connect": pair, trust (BlueZ then accepts the device's own
    // reconnections) and connect.
    function pairDevice(device) {
        runDeviceAction(device, "pair", 'busctl --system --timeout=60 call org.bluez "$DEV" org.bluez.Device1 Pair'
            + ' && busctl --system set-property org.bluez "$DEV" org.bluez.Device1 Trusted b true'
            + ' && busctl --system --timeout=60 call org.bluez "$DEV" org.bluez.Device1 Connect');
    }
    function forgetDevice(device) {
        if (!device) return;
        if (root.failedDevicePath === device.dbusPath) root.failedDevicePath = "";
        device.forget();
    }

    function runDeviceAction(device, action, script) {
        if (!device || root.busy) return;
        root.busyDevicePath = device.dbusPath;
        root.busyAction = action;
        root.failedDevicePath = "";
        root.failedMessage = "";
        // busy pauses discovery (syncDiscovery) before the call is sent
        deviceAction.exec({
            "environment": { "DEV": device.dbusPath },
            "command": ["sh", "-c", script]
        });
    }

    Process {
        id: deviceAction
        stderr: StdioCollector { id: deviceActionErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                const message = deviceActionErr.text.trim().split("\n").pop() ?? "";
                console.warn(`[BluetoothStatus] ${root.busyAction} ${root.busyDevicePath} failed: ${message}`);
                root.failedDevicePath = root.busyDevicePath;
                root.failedMessage = message.replace(/^Call failed:\s*/, "");
            }
            root.busyDevicePath = "";
            root.busyAction = "";
        }
    }
}
