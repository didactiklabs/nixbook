pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * Builds popup windows ahead of time so their first open is as instant as
 * every later one. Popups are kept alive after being built, and the frequently
 * used ones stay *mapped* while closed (hiding a Wayland window destroys its
 * surface, and Qt then rebuilds the window's GL context on the next open —
 * 100–200 ms per open, measured).
 *
 * Boot: while the shell starts, a loading screen (modules/ii/splash) covers
 * every output and blocks input; meanwhile every stage runs back to back, one
 * per frame, heavy ones included (unless the battery is low), and the
 * kept-mapped windows are drawn once invisibly (`prerender`) so their
 * textures/glyphs are uploaded too. It only covers work that would stall the
 * GUI thread in view (each stage freezes it ~100–300 ms: building, polishing
 * and first-rendering a panel; the bar and wallpaper are built underneath it
 * too). It lifts as soon as that is over — every stage built and no frame gap
 * over `stallMs` for `quietMs` — and `maxBootMs` caps it so it can never trap
 * the user. Things that load smoothly are left to appear in view: async
 * images fade in when decoded, and desktop widgets are revealed one by one
 * after the fade-out (`queueReveal`).
 *
 * After boot (e.g. plugging in later), remaining stages run while idle, as
 * before: a gap between stages, paused while locked or while a popup is open.
 * Preloaded windows stay hidden and idle: their timers/visualizers are gated
 * on the window being visible.
 */
Singleton {
    id: root

    property bool osd: false
    property bool session: false
    property bool media: false
    property bool desktopMenu: false
    property bool launcher: false
    property bool sidebarRight: false
    property bool sidebarLeft: false
    property bool equalizer: false
    property bool overlay: false
    property bool wallpaperSelector: false

    readonly property var lightStages: ["osd", "session", "media", "desktopMenu", "launcher", "sidebarRight", "sidebarLeft"]
    readonly property var heavyStages: ["equalizer", "overlay", "wallpaperSelector"]
    readonly property var stageLabels: ({
        osd: "On-screen display", session: "Power menu", media: "Media controls",
        desktopMenu: "Desktop menu", launcher: "Launcher", sidebarRight: "Quick settings",
        sidebarLeft: "Sidebar", equalizer: "Equalizer", overlay: "Overlay", wallpaperSelector: "Wallpapers"
    })

    // ---- boot
    readonly property int maxBootMs: 15000
    readonly property int quietMs: 200
    readonly property int stallMs: 40
    // "building" → "rendering" (all stages built, waiting for the last frames)
    property string bootPhase: "building"
    property bool booting: true
    // Kept-mapped windows draw their closed content at ~0 opacity while this
    // is set, so the first real open finds everything uploaded.
    readonly property bool prerender: root.booting
    property string currentStage: ""
    readonly property int stageCount: root.lightStages.length + (root.bootHeavy ? root.heavyStages.length : 0)
    property int stagesDone: 0
    readonly property real progress: root.stageCount > 0 ? root.stagesDone / root.stageCount : 1
    readonly property bool bootHeavy: !root.batteryLow

    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property var chargeState: UPower.displayDevice?.state
    readonly property bool onAc: !root.hasBattery
        || root.chargeState === UPowerDeviceState.Charging
        || root.chargeState === UPowerDeviceState.PendingCharge
        || root.chargeState === UPowerDeviceState.FullyCharged
    readonly property bool batteryLow: root.hasBattery && !root.onAc
        && (UPower.displayDevice?.percentage ?? 1) <= Math.max(0.2, (Config.options?.battery?.low ?? 20) / 100)

    readonly property bool userBusy: GlobalStates.screenLocked
        || GlobalStates.overviewOpen || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
        || GlobalStates.sessionOpen || GlobalStates.mediaControlsOpen || GlobalStates.overlayOpen
        || GlobalStates.wallpaperSelectorOpen || GlobalStates.settingsOpen

    function load() {} // force singleton creation

    function nextStage(heavyAllowed) {
        if (root.batteryLow && !root.booting)
            return "";
        for (const s of root.lightStages)
            if (!root[s]) return s;
        if (heavyAllowed)
            for (const s of root.heavyStages)
                if (!root[s]) return s;
        return "";
    }

    // Desktop widgets: revealed one at a time after the loading screen has
    // faded out, `revealGapMs` apart (longer than a widget's fade-in, so a
    // build never lands in the middle of the previous fade). Later requests
    // (a widget enabled from the menu) run at once.
    readonly property int revealGapMs: 220
    property var _revealQueue: []
    function queueReveal(fn) {
        if (!root.booting && !revealTimer.running && root._revealQueue.length === 0 && root._revealReady) {
            fn();
            return;
        }
        root._revealQueue.push(fn);
    }
    property bool _revealReady: false
    Timer {
        id: revealTimer
        interval: root.revealGapMs
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._revealReady = true;
            const fn = root._revealQueue.shift();
            if (fn) {
                try { fn(); } catch (e) {} // its delegate may be gone
            }
            if (root._revealQueue.length === 0)
                revealTimer.stop();
        }
    }
    // Wait for the loading screen's fade-out (BootSplash) before revealing.
    Timer {
        id: revealStart
        interval: 340
        onTriggered: {
            if (root._revealQueue.length > 0) revealTimer.start();
            else root._revealReady = true;
        }
    }

    function finishBoot() {
        if (!root.booting) return;
        bootTimer.stop();
        root.currentStage = "";
        root.booting = false;
        revealStart.start();
        // Anything left (e.g. heavy stages on a low battery) continues idle.
        if (root.nextStage(root.onAc) !== "") stageTimer.start();
    }

    // Boot: one stage per tick. A timer tick only runs once the GUI thread is
    // free again, so stages follow each other as fast as they can be built.
    Timer {
        id: bootTimer
        interval: 16
        repeat: true
        running: root.booting && Config.ready
        onTriggered: {
            const s = root.nextStage(root.bootHeavy);
            if (s === "") {
                // Everything is built: now wait until it is rendered.
                bootTimer.stop();
                root.bootPhase = "rendering";
                root.currentStage = "";
                settleTimer.lastTick = Date.now();
                settleTimer.quietSince = Date.now();
                settleTimer.start();
                return;
            }
            root.currentStage = root.stageLabels[s] ?? s;
            root[s] = true;
            root.stagesDone += 1;
        }
    }
    // Render quiescence: lift once the GUI thread has run without a stall for
    // `quietMs` (the last windows are laid out and drawn).
    Timer {
        id: settleTimer
        interval: 16
        repeat: true
        property real lastTick: 0
        property real quietSince: 0
        onTriggered: {
            const now = Date.now();
            const gap = now - lastTick;
            lastTick = now;
            if (gap > root.stallMs)
                quietSince = now;
            if (now - quietSince >= root.quietMs) {
                settleTimer.stop();
                root.finishBoot();
            }
        }
    }
    Timer {
        id: bootCap
        interval: root.maxBootMs
        running: root.booting
        onTriggered: root.finishBoot()
    }

    // After boot: idle staged preloading (only if something is left).
    Timer {
        id: stageTimer
        interval: 400
        repeat: true
        onTriggered: {
            if (root.userBusy)
                return; // try again next tick
            const s = root.nextStage(root.onAc);
            if (s === "") {
                stageTimer.stop(); // resumes below if we get plugged in
                return;
            }
            root[s] = true;
        }
    }

    // Plugging in later finishes the heavy stages.
    onOnAcChanged: if (root.onAc && !root.booting && root.nextStage(true) !== "") stageTimer.start()
}
