pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    // Mapped at once, but drawing nothing until the screen is captured
    // (`preparationDone`): the press of a selection started while grim was
    // still running used to land on the window underneath (the selector only
    // appeared mid-drag and never saw the press, so the first selection took
    // no screenshot). A transparent surface can't show up in the capture.
    visible: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    // Only exists while selecting: take the keyboard (Escape cancels).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound } 
    // Window / Screen: hovering a window or a screen selects it, a click takes it.
    enum SelectionMode { RectCorners, Circle, Window, Screen }
    enum Phase { Select, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    signal dismiss()
    // The mode is shared by every screen's selector: ask RegionSelector.
    signal selectionModeRequested(var mode)
    // niri's gaps/struts, for the window estimate (RegionFunctions.parseNiriLayout).
    property var niriLayout: RegionFunctions.parseNiriLayout("")

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property var monitor: WM.monitorFor(screen)
    readonly property var monitorGeometry: WM.monitorGeometry(screen)
    readonly property real monitorScale: monitorGeometry.scale
    readonly property real monitorOffsetX: monitorGeometry.x
    readonly property real monitorOffsetY: monitorGeometry.y
    property int activeWorkspaceId: WM.activeWorkspaceForMonitor(root.monitor?.name)?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    // The window taken in window selection: captured by niri, not cropped.
    property string snipWindowId: ""
    property var imageRegions: []
    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    readonly property bool isTargetSelection: root.selectionMode === RegionSelection.SelectionMode.Window
        || root.selectionMode === RegionSelection.SelectionMode.Screen

    function toggleSelectionMode(mode) {
        root.selectionModeRequested(root.selectionMode === mode ? RegionSelection.SelectionMode.RectCorners : mode);
    }

    // Window/screen selection: the windows of this screen's workspace, and
    // whatever is under the pointer (null while it is on another screen).
    readonly property var windowTargets: root.selectionMode === RegionSelection.SelectionMode.Window
        ? RegionFunctions.windowTargets(WM.windowList, WM.activeWorkspaceForMonitor(root.screen.name),
            root.screen.width, root.screen.height, root.niriLayout, root.reservedBarSpace)
        : []
    readonly property var reservedBarSpace: {
        const bar = Config.options.bar;
        const screens = bar.screenList ?? [];
        const barHere = screens.length === 0 || screens.includes(root.screen.name);
        const side = barHere && bar.vertical ? Appearance.sizes.verticalBarWidth : 0;
        return { left: bar.bottom ? 0 : side, right: bar.bottom ? side : 0, bottom: barHere && !bar.vertical && bar.bottom };
    }
    readonly property var hoverTarget: {
        if (!root.isTargetSelection || !mouseArea.containsMouse) return null;
        if (root.selectionMode === RegionSelection.SelectionMode.Screen)
            return { id: "", title: root.screen.name, x: 0, y: 0, width: root.screen.width, height: root.screen.height };
        return RegionFunctions.targetAt(root.windowTargets, mouseArea.mouseX, mouseArea.mouseY);
    }
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = root.imageRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions) imageDetectionProcess.running = true;
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    // Drawn once the file to crop exists and niri's frozen frame is here (so
    // the overlay never shows over an empty view).
    readonly property bool shown: root.preparationDone && frozenView.hasContent
    // The captures of the screens not snipped are deleted on close (the
    // snipped one is removed by the snip command once it has read it).
    property bool snipped: false
    Component.onDestruction: {
        if (!root.snipped) Quickshell.execDetached(["rm", "-f", root.screenshotPath]);
    }
    // A selection finished before the capture was ready: taken once it is.
    property bool snipPending: false
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        if (root.snipPending) {
            root.snipPending = false;
            root.snip();
        }
    }

    Connections {
        target: Persistent.states.record
        function onEnableChanged() {
            if (!Persistent.states.record.enable && root.isRecording) {
                root.dismiss();
            }
        }
    }

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh ` 
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' ` 
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} ` 
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                imageRegions = RegionFunctions.filterOverlappingImageRegions(
                    JSON.parse(imageDimensionCollector.text).map(r => ({ at: [r.x, r.y], size: [r.width, r.height] }))
                );
            }
        }
    }

    function getScreenshotAction() {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
                return ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Edit:
                return ScreenshotAction.Action.Edit;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case RegionSelection.SnipAction.Record:
                return ScreenshotAction.Action.Record;
            case RegionSelection.SnipAction.RecordWithSound:
                return ScreenshotAction.Action.RecordWithSound;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    // Execution after selection
    function snip() {
        // The crop source (screenshotPath) isn't written yet: wait for it.
        if (!root.preparationDone) {
            root.snipPending = true;
            return;
        }
        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
            return;
        }

        // Clamp region to screen bounds
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Adjust action
        if (root.action === RegionSelection.SnipAction.Copy || root.action === RegionSelection.SnipAction.Edit) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }
        
        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
            Config.options.screenSnip.savePath : "";
        var screenshotAction = root.getScreenshotAction();
        const isRecording = root.action === RegionSelection.SnipAction.Record
            || root.action === RegionSelection.SnipAction.RecordWithSound;
        let command;
        if (root.snipWindowId !== "" && !isRecording) {
            const windowPath = `${root.screenshotDir}/window-${root.snipWindowId}`;
            command = ScreenshotAction.getWindowCommand(root.snipWindowId, windowPath,
                ScreenshotAction.getCommand(0, 0, 0, 0, windowPath, screenshotAction, screenshotDir));
        } else {
            root.snipped = !isRecording; // the command reads and removes the capture
            command = ScreenshotAction.getCommand(
                root.regionX * root.monitorScale, //
                root.regionY * root.monitorScale, //
                root.regionWidth * root.monitorScale,// 
                root.regionHeight * root.monitorScale, //
                root.screenshotPath, //
                screenshotAction, //
                screenshotDir
            )
        }
        Quickshell.execDetached(command);
        if (root.action == RegionSelection.SnipAction.Record || root.action == RegionSelection.SnipAction.RecordWithSound) {
            root.phase = RegionSelection.Phase.Post
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        } else {
            root.dismiss();
        }
    }

    // Only clickable in Selection phase
    mask: Region {
        item: switch(root.phase) {
            case RegionSelection.Phase.Select: return mouseArea;
            case RegionSelection.Phase.Post: return null;
        }
    }

    ScreencopyView { // For freezing
        id: frozenView
        anchors.fill: parent
        live: false
        captureSource: root.screen
        visible: root.phase === RegionSelection.Phase.Select
        opacity: root.shown ? 1 : 0 // stays focusable (Esc) meanwhile

        focus: root.visible
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) { // Esc to close
                Qt.callLater(root.dismiss);
            } else if (event.key === Qt.Key_S) { // hover a screen to select it
                root.toggleSelectionMode(RegionSelection.SelectionMode.Screen);
            } else if (event.key === Qt.Key_W) { // hover a window to select it
                root.toggleSelectionMode(RegionSelection.SelectionMode.Window);
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        // Takes input from the start (opacity doesn't block it); its overlay
        // (dimming, guides, toolbar) shows once the capture is ready.
        opacity: root.shown ? 1 : 0
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        // Controls
        onPressed: (mouse) => {
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragging = true;
            root.mouseButton = mouse.button;
        }
        onReleased: (mouse) => {
            if (root.isTargetSelection) {
                root.dragging = false;
                const target = root.hoverTarget;
                if (!target) return; // no window there: keep selecting
                root.regionX = target.x;
                root.regionY = target.y;
                root.regionWidth = target.width;
                root.regionHeight = target.height;
                root.snipWindowId = target.id;
                root.snip();
                return;
            }
            // Detect if it was a click -> Try to select targeted region
            if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                }
            }
            // Circle dragging?
            else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
            }
            root.snip();
        }
        onPositionChanged: (mouse) => {
            root.updateTargetedRegion(mouse.x, mouse.y);
            if (!root.dragging) return;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            root.points.push({ x: mouse.x, y: mouse.y });
        }
        
        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode !== RegionSelection.SelectionMode.Circle
            sourceComponent: RectCornersSelectionDetails {
                // Window/screen selection shows the hovered target (nothing:
                // the whole screen dimmed) until one is taken.
                readonly property bool showsTarget: root.isTargetSelection && root.phase === RegionSelection.Phase.Select
                regionX: showsTarget ? (root.hoverTarget?.x ?? 0) : root.regionX
                regionY: showsTarget ? (root.hoverTarget?.y ?? 0) : root.regionY
                regionWidth: showsTarget ? (root.hoverTarget?.width ?? 0) : root.regionWidth
                regionHeight: showsTarget ? (root.hoverTarget?.height ?? 0) : root.regionHeight
                label: showsTarget ? (root.hoverTarget?.title ?? "") : ""
                showAimLines: !root.isTargetSelection && Config.options.regionSelector.rect.showAimLines
                mouseX: mouseArea.mouseX
                mouseY: mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            z: 9999
            visible: root.phase === RegionSelection.Phase.Select
            x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
            y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions && !root.isTargetSelection) {
                        return root.imageRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: Translation.tr("Content region")
            }
        }

        // Controls
        Row {
            id: regionSelectionControls
            z: 10
            visible: root.phase === RegionSelection.Phase.Select
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0
            Connections {
                target: root
                function onShownChanged() {
                    if (!root.shown) return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            spacing: 6

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                selectionMode: root.selectionMode
                onSelectionModeSelected: mode => root.selectionModeRequested(mode)
                onDismiss: root.dismiss();
            }
            ToolbarPairedFab {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "close"
                onClicked: root.dismiss();
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }
        
    }
}
