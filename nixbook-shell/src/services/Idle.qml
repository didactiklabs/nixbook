pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Idle inhibition (the idle toggle) and screens-off detection.
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    // The screens are off: no input for as long as hypridle waits before
    // `niri msg action power-off-monitors` (niriConfig.nix, 300 s), with the
    // same idle inhibitors honoured (a playing video, the idle toggle). Polls
    // and per-second redraws that only feed what is on screen pause on it
    // (resources, network speed, VPN status, media position, the clock's
    // seconds…) and refresh as soon as there is input again.
    readonly property int screenOffTimeout: 300
    readonly property bool screensOff: idleMonitor.isIdle
    IdleMonitor {
        id: idleMonitor
        timeout: root.screenOffTimeout
        respectInhibitors: true
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.inhibit = Persistent.states.idle.inhibit;
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}