pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Puts text in the clipboard, from any surface.
 *
 * Not by setting Quickshell.clipboardText: that goes through Qt's Wayland clipboard,
 * and the compositor ignores it from a surface without keyboard focus, silently
 * (the bar's panels, popups, menus). wl-copy needs no focus. The text goes
 * through stdin, so its size isn't limited like an argument's.
 */
Singleton {
    id: root

    // done(ok), if given, once the text is there or couldn't be.
    function copy(text, done) {
        writer.createObject(root, {
            "text": String(text ?? ""),
            "done": done ?? null,
            "running": true
        });
    }

    Component {
        id: writer
        Process {
            id: proc
            property string text
            property var done
            command: ["wl-copy", "--type", "text/plain;charset=utf-8"]
            stdinEnabled: true
            onStarted: {
                proc.write(proc.text);
                proc.stdinEnabled = false;
            }
            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0)
                    console.warn(`[Clipboard] wl-copy exited with code ${exitCode}`);
                proc.done?.(exitCode === 0);
                proc.destroy();
            }
        }
    }
}
