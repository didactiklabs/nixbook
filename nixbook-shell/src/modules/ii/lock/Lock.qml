pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Io

LockScreen {
    id: root

    property string lastProcessedLockWall: ""
    property bool lastProcessedDarkmode: Appearance.m3colors.darkmode

    lockSurface: LockSurface {
        context: root.context
    }

    Process {
        id: lockThemeProc
        command: ["bash", "-c",
            `${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "dark" : "light"} --colors_lock --image '${Config.options.background.lockWall}'`
        ]
        onExited: {
            // Generating the palette takes a while: when the screen was
            // unlocked meanwhile, the live palette stays (switching now would
            // leave the lock one in place for good, apps included).
            if (GlobalStates.screenLocked)
                MaterialThemeLoader.useLockTheme()
            root.lastProcessedLockWall = Config.options.background.lockWall
            root.lastProcessedDarkmode = Appearance.m3colors.darkmode
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            var wallChanged = Config.options.background.lockWall !== root.lastProcessedLockWall
            var modeChanged = Appearance.m3colors.darkmode !== root.lastProcessedDarkmode

            if (GlobalStates.screenLocked) {
                if (Config.options.background.lockWall !== "" && (wallChanged || modeChanged)) {
                    lockThemeProc.running = true
                } else if (Config.options.background.lockWall !== "") {
                    MaterialThemeLoader.useLockTheme()
                }
            } else if (MaterialThemeLoader.filePath !== Directories.generatedMaterialThemePath) {
                MaterialThemeLoader.useLiveTheme()
            }
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}