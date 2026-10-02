import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale

    property Item wallpaperItem: null

    property bool visibleWhenLocked: Config.options.lock.showWidgets
    // The widget's entry, or one of its extra instances' ("customImage:<id>",
    // see DesktopWidgets); {} once that instance is removed.
    property var configEntry: DesktopWidgets.entry(configEntryName) ?? ({})
    // Writes to configEntry (needed for an instance: its entry is a copy).
    function setEntry(values) {
        DesktopWidgets.setEntry(root.configEntryName, values);
    }
    property string placementStrategy: configEntry.placementStrategy ?? "free"
    // Set by WidgetsLoader. Each monitor keeps its own position
    // (background.widgets.screenPositions); a screen without one uses the
    // widget's shared x/y/z.
    property string screenName: ""
    // This widget's setting `prop` on this monitor (DesktopWidgets: its
    // per-monitor override, else the shared value); `setScreenValues` stores
    // values for this monitor only. Widgets read/write their size through these.
    function screenValue(prop, fallback) {
        return DesktopWidgets.value(root.configEntryName, root.screenName, prop, fallback);
    }
    function setScreenValues(values) {
        DesktopWidgets.setValues(root.configEntryName, root.screenName, values);
    }
    readonly property var position: ({
        x: root.screenValue("x", configEntry.x ?? 0),
        y: root.screenValue("y", configEntry.y ?? 0),
        z: root.screenValue("z", configEntry.z ?? 0)
    })
    property real targetX: Math.max(0, Math.min(position.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(position.y, scaledScreenHeight - height))
    property real targetZ: position.z
    x: targetX
    y: targetY
    z: targetZ
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free" && !Config.options.background.widgetsLocked

    // Where it is on its monitor and how big (DesktopWidgets.geometries, for
    // `ipc call widgets layout`), reported once it settles.
    QtObject {
        id: geometryReport
        function send() {
            DesktopWidgets.reportGeometry(root.configEntryName, root.screenName, root.visible && root.width > 0
                ? { x: Math.round(root.x), y: Math.round(root.y), width: Math.round(root.width), height: Math.round(root.height), z: root.z }
                : null);
        }
        property Timer timer: Timer {
            interval: 300
            onTriggered: geometryReport.send()
        }
        property Connections changes: Connections {
            target: root
            function onXChanged() { geometryReport.timer.restart() }
            function onYChanged() { geometryReport.timer.restart() }
            function onZChanged() { geometryReport.timer.restart() }
            function onWidthChanged() { geometryReport.timer.restart() }
            function onHeightChanged() { geometryReport.timer.restart() }
            function onVisibleChanged() { geometryReport.timer.restart() }
        }
        Component.onCompleted: timer.restart()
        Component.onDestruction: DesktopWidgets.reportGeometry(root.configEntryName, root.screenName, null)
    }

    function requestDelete() {
        if (DesktopWidgets.splitName(root.configEntryName))
            DesktopWidgets.removeInstance(root.configEntryName)
        else
            Config.options.background.widgets[root.configEntryName].enable = false
    }
    function restoreXYBinding() {
        root.x = Qt.binding(() => root.targetX);
        root.y = Qt.binding(() => root.targetY);
        root.z = Qt.binding(() => root.targetZ);
    }

    function commitPosition() {
        // Only this monitor moves.
        root.setScreenValues({ x: root.x, y: root.y, z: root.z });
        root.targetX = Qt.binding(() => Math.max(0, Math.min(root.position.x, scaledScreenWidth - width)));
        root.targetY = Qt.binding(() => Math.max(0, Math.min(root.position.y, scaledScreenHeight - height)));
        root.targetZ = Qt.binding(() => root.position.z);
        root.restoreXYBinding();
    }

    onReleased: root.commitPosition()

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh")
            , "--screen-width", Math.round(root.scaledScreenWidth)
            , "--screen-height", Math.round(root.scaledScreenHeight)
            , "--width", contentWidth
            , "--height", contentHeight
            , "--horizontal-padding", horizontalPadding
            , "--vertical-padding", verticalPadding
            , wallpaperPath
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }
}