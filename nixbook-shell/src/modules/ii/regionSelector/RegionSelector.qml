pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    // The screen being recorded: only its selector stays (drawing the border).
    property string recordingScreen: ""

    // niri's gaps and struts (not in its IPC), for placing tiled windows in
    // window selection. Re-read on each open: a switch replaces the file.
    FileView {
        id: niriConfigFile
        path: Quickshell.env("NIRI_CONFIG") || `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/niri/config.kdl`
        printErrors: false
    }
    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (!GlobalStates.regionSelectorOpen) return;
            root.recordingScreen = "";
            niriConfigFile.reload();
            // The previous copies' files, kept for their notification image.
            Quickshell.execDetached(["bash", "-c", `rm -f '${StringUtils.shellSingleQuoteEscape(Directories.screenshotTemp)}'/{window-,snip-}*.png`]);
        }
    }
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen
                && (root.recordingScreen === "" || root.recordingScreen === regionSelectorLoader.modelData.name)

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
                niriLayout: RegionFunctions.parseNiriLayout(niriConfigFile.text())
                onSelectionModeRequested: mode => root.selectionMode = mode
                onRecordingStarted: root.recordingScreen = regionSelectorLoader.modelData.name
            }
        }
    }

    function screenshot() {
        if (Persistent.states.record.enable) {
            // Recording: the selector would show in the video, so slurp picks the region.
            Quickshell.execDetached(["bash", "-c", `${ScreenshotAction.outputFileCommand(ScreenshotAction.saveDir)} && `
                + `grim -g "$(slurp)" "$out" && wl-copy --type image/png < "$out" && ${ScreenshotAction.notifyCommand}`]);
            return;
        }
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function record() {
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function recordWithSound() {
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }

        // Without the selector (the desktop MCP server's screen_capture),
        // through the same script, indicator and notifications. `target`: ""
        // (the focused monitor), a monitor's name, or a region "X,Y WxH" in
        // logical pixels.
        function recordStart(target: string, sound: bool): string {
            if (Persistent.states.record.enable)
                return "error: already recording (recordStop first)";
            const args = [Directories.recordScriptPath];
            if (target === "")
                args.push("--fullscreen");
            else if (/^-?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+$/.test(target))
                args.push("--region", target);
            else if (Quickshell.screens.some(s => s.name === target))
                args.push("--output", target);
            else
                return `error: "${target}" isn't a monitor (${Quickshell.screens.map(s => s.name).join(", ")}) or a region "X,Y WxH"`;
            args.push(sound ? "--sound" : "--no-sound");
            Quickshell.execDetached(args);
            return `ok: recording ${target || "the focused monitor"}${sound ? " with sound" : ""}`;
        }
        // The script stops the running recording when called again.
        function recordStop(): string {
            if (!Persistent.states.record.enable)
                return "error: not recording";
            Quickshell.execDetached([Directories.recordScriptPath]);
            return "ok: stopped";
        }
        function recordStatus(): string {
            return JSON.stringify({ recording: Persistent.states.record.enable,
                folder: FileUtils.trimFileProtocol(Config.options.screenRecord.savePath) });
        }
    }
}