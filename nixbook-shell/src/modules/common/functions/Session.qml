pragma Singleton
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        // Ask niri to close each window, so apps shut down gracefully before
        // logout/poweroff rather than being killed when systemd tears the
        // session down.
        WM.windowList.forEach(w => WM.closeWindow(w.id));
    }

    // Close the windows, then run `action` once they are gone (at most
    // ~4 s: an app may be asking about unsaved work). Reboot/poweroff sent
    // while the apps were still quitting were refused by logind (apps hold
    // shutdown inhibitors while they save), so the power menu closed
    // everything and did nothing more.
    property var pendingAction: null
    property int waitedMs: 0
    function closeWindowsThen(action) {
        root.closeAllWindows();
        if (WM.windowList.length === 0) {
            action();
            return;
        }
        root.pendingAction = action;
        root.waitedMs = 0;
        afterClose.restart();
    }
    Timer {
        id: afterClose
        interval: 200
        repeat: true
        onTriggered: {
            root.waitedMs += interval;
            if (WM.windowList.length > 0 && root.waitedMs < 4000)
                return;
            afterClose.stop();
            // A moment more for the last app to release its inhibitor.
            Qt.callLater(() => {
                const action = root.pendingAction;
                root.pendingAction = null;
                if (action) action();
            });
        }
    }

    function changePassword() {
        AppLaunch.spawnShell(Config.options.apps.changePassword);
    }

    function lock() {
        Quickshell.execDetached(["qs", "-c", "nixbook-shell", "ipc", "call", "lock", "activate"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        root.closeWindowsThen(() => {
            Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]);
        });
    }

    function launchTaskManager() {
        AppLaunch.spawnShell(Config.options.apps.taskManager);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        root.closeWindowsThen(() => Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]));
    }

    function reboot() {
        root.closeWindowsThen(() => Quickshell.execDetached(["bash", "-c", `systemctl reboot || loginctl reboot`]));
    }

    function rebootToFirmware() {
        root.closeWindowsThen(() => Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]));
    }
}
