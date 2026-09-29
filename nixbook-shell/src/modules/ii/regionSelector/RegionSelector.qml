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

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
                niriLayout: RegionFunctions.parseNiriLayout(niriConfigFile.text())
                onSelectionModeRequested: mode => root.selectionMode = mode
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
    }
}