import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: screenshotProc
    running: true
    property string screenshotDir: Directories.screenshotTemp
    required property ShellScreen screen
    property string screenshotPath: `${screenshotDir}/image-${screen.name}`
    // -l 0: an uncompressed PNG (in $XDG_RUNTIME_DIR, RAM). The default level
    // took up to 2 s for a 2880x1800 output with the other screens encoding at
    // the same time, and the selector waits for this file; -l 0 takes ~80 ms.
    command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(screenshotDir)}' && grim -l 0 -o '${StringUtils.shellSingleQuoteEscape(screen.name)}' '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`]
}
