pragma Singleton
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        // HyprlandData is empty under niri: ask niri to close each window
        // instead, so apps shut down gracefully before logout/poweroff rather
        // than being killed when systemd tears the session down.
        if (WM.compositor === "niri") {
            WM.windowList.forEach(w => WM.closeWindow(w.id));
            return;
        }
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        AppLaunch.spawnShell(Config.options.apps.changePassword);
    }

    function lock() {
        if (WM.compositor === "niri") {
            Quickshell.execDetached(["qs", "-c", "nixbook-shell", "ipc", "call", "lock", "activate"]);
        } else {
            Quickshell.execDetached(["loginctl", "lock-session"]);
        }
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        closeAllWindows();
        if (WM.compositor === "niri") {
            Quickshell.execDetached(["niri", "msg", "action", "quit"]);
        } else {
            Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
        }
    }

    function launchTaskManager() {
        AppLaunch.spawnShell(Config.options.apps.taskManager);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
    }

    function reboot() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
    }

    function rebootToFirmware() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
    }
}
