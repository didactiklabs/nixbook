pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool packageManagerRunning: false
    property bool downloadRunning: false

    function refresh() {
        packageManagerRunning = false;
        downloadRunning = false;
        detectPackageManagerProc.running = false;
        detectPackageManagerProc.running = true;
        detectDownloadProc.running = false;
        detectDownloadProc.running = true;
    }

    Process {
        id: detectPackageManagerProc
        // NixOS: a rebuild / deploy / profile change in progress (process names
        // are matched exactly, comm is truncated to 15 chars), or the shell's
        // own update service running.
        command: ["bash", "-c", "pgrep -x 'nixos-rebuild.*|colmena|home-manager|nix-env|switch-to-conf.*|nix-collect-gar.*' >/dev/null || systemctl is-active --quiet nixos-upgrade-manual.service nixos-upgrade.service"]
        onExited: (exitCode, exitStatus) => {
            root.packageManagerRunning = (exitCode === 0);
        }
    }

    Process {
        id: detectDownloadProc
        command: ["bash", "-c", "pidof curl wget aria2c yt-dlp || ls ~/Downloads | grep -E '\.crdownload$|\.part$'"]
        onExited: (exitCode, exitStatus) => {
            root.downloadRunning = (exitCode === 0);
        }
    }
}
