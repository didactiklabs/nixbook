pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState == UPowerDeviceState.Charging
    // On AC, whatever the battery does: full, held at a charge threshold
    // (PendingCharge) or briefly discharging under load. Testing the charge
    // state played the unplug sound on reaching 100 % and could raise
    // low-battery alerts or suspend while plugged in.
    property bool isPluggedIn: !UPower.onBattery
    property real percentage: UPower.displayDevice?.percentage ?? 1
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend
    readonly property bool soundEnabled: Config.options.sounds.battery

    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    // Plugged in, but the charger gives less than the computer uses (a
    // phone charger, a low-power USB-C hub, or a fair one under a long heavy
    // job): the battery empties while UPower says "charging". Seen as the
    // level falling `drainPoints` without rising in between, or staying under
    // the low threshold `stallMs` without rising (an empty battery at the
    // shell's start can't fall any further). A brief dip under load doesn't
    // count; the level rising again or unplugging clears it.
    property bool chargerTooWeak: false
    // What heavy optional work (and power saving) should go by: on battery,
    // or on a charger that can't keep up.
    readonly property bool runningOnBattery: available && (!isPluggedIn || chargerTooWeak)
    readonly property real drainPoints: 0.03
    readonly property int stallMs: 10 * 60 * 1000
    property real _acHigh: -1 // level the fall is measured from
    property real _acLow: -1  // lowest level since

    function _resetAc() {
        root._acHigh = root.percentage;
        root._acLow = root.percentage;
        root.chargerTooWeak = false;
        stallTimer.restart();
    }
    function _checkAc() {
        if (!root.available || !root.isPluggedIn) return;
        if (root._acLow < 0) { root._resetAc(); return; }
        if (root.percentage >= root._acLow + 0.015) { root._resetAc(); return; } // rising
        root._acLow = Math.min(root._acLow, root.percentage);
        if (root._acHigh - root._acLow >= root.drainPoints) root.chargerTooWeak = true;
    }
    onPercentageChanged: root._checkAc()
    Component.onCompleted: {
        root._checkAc();
        root.refreshChargeLimit();
    }

    Timer {
        id: stallTimer
        interval: root.stallMs
        running: root.available && root.isPluggedIn && !root.chargerTooWeak
            && root.percentage < Config.options.battery.low / 100
        onTriggered: root.chargerTooWeak = true
    }

    onChargerTooWeakChanged: {
        if (!root.available || !chargerTooWeak) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Charger not keeping up"),
            Translation.tr("The battery is not charging while plugged in (%1%). Use a more powerful charger; heavy background work is paused meanwhile.").arg(Math.round(root.percentage * 100)),
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);
    }

    property bool isLowAndNotCharging: isLow && !isPluggedIn
    property bool isCriticalAndNotCharging: isCritical && !isPluggedIn
    property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isPluggedIn
    property bool isFullAndCharging: isFull && isCharging

    // The level charging stops at (the kernel's charge_control_end_threshold),
    // read and set through `nixbook-charge-limit` (scripts/charge-limit.sh):
    // a battery kept under 100 % on the charger lasts longer. 0: this battery
    // has no such limit. Read at the start and when the battery panel opens,
    // never polled.
    property int chargeLimit: 0
    property bool chargeLimitSettable: false
    property string chargeLimitError: ""
    readonly property bool chargeLimitBusy: chargeLimitProc.running
    property int _limitWanted: 0
    // On the charger and not charging because the limit is reached.
    readonly property bool heldAtLimit: available && isPluggedIn && !isCharging
        && chargeState != UPowerDeviceState.FullyCharged
        && chargeLimit > 0 && chargeLimit < 100
        && percentage * 100 >= chargeLimit - 2

    function refreshChargeLimit() {
        if (!root.available || chargeLimitProc.running) return;
        chargeLimitProc.command = ["nixbook-charge-limit", "status"];
        chargeLimitProc.running = true;
    }
    function setChargeLimit(percent) {
        if (chargeLimitProc.running) {
            root._limitWanted = percent; // the latest choice wins
            return;
        }
        root.chargeLimitError = "";
        root.chargeLimit = percent; // shown at once; the answer corrects it
        chargeLimitProc.command = ["nixbook-charge-limit", "set", String(percent)];
        chargeLimitProc.running = true;
    }
    onAvailableChanged: if (available) root.refreshChargeLimit()

    Process {
        id: chargeLimitProc
        stdout: StdioCollector {
            id: chargeLimitOut
            onStreamFinished: {
                let answer = null;
                try {
                    answer = JSON.parse(chargeLimitOut.text.trim());
                } catch (e) {
                    return;
                }
                root.chargeLimit = answer.limit ?? 0;
                root.chargeLimitSettable = answer.canSet ?? false;
                root.chargeLimitError = answer.error ?? "";
            }
        }
        onExited: {
            if (root._limitWanted <= 0) return;
            const percent = root._limitWanted;
            root._limitWanted = 0;
            Qt.callLater(() => root.setChargeLimit(percent));
        }
    }

    property real energyRate: UPower.displayDevice.changeRate
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    property real health: (function() {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery && dev.healthSupported) {
                const health = dev.healthPercentage;
                if (health === 0) {
                    return 0.01;
                } else if (health < 1) {
                    return health * 100;
                } else {
                    return health;
                }
            }
        }
        return 0;
    })()

    property int chargeCycles: (function() {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery) {
                return dev.chargeCycles ?? -1
            }
        }
        return -1
    })()

    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Low battery"), 
            Translation.tr("Consider plugging in your device"), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ])

        if (root.soundEnabled) Audio.playSystemSound("dialog-warning");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Critically low battery"), 
            Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(Config.options.battery.suspend), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("suspend-error");
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Quickshell.execDetached(["bash", "-c", `systemctl suspend || loginctl suspend`]);
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr("Please unplug the charger"),
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("complete");
    }

    onIsPluggedInChanged: {
        if (isPluggedIn) root._resetAc(); else root.chargerTooWeak = false;
        if (!root.available || !root.soundEnabled) return;
        if (isPluggedIn) {
            Audio.playSystemSound("power-plug")
        } else {
            Audio.playSystemSound("power-unplug")
        }
    }
}
