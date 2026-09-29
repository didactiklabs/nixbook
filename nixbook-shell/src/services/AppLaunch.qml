pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Launches user applications outside the shell's own process tree.
 *
 * DesktopEntry.execute() / Quickshell.execDetached() spawn apps as children of
 * the shell, i.e. inside the nixbook-shell.service cgroup (so restarting the shell
 * killed Discord, the browser, ...) and with the shell's environment (the
 * quickshell wrapper's QT_PLUGIN_PATH / QML import paths / tool PATH leak into
 * every Qt app, which then loads the shell's Qt plugin set).
 *
 * niri spawns the app instead (`niri msg action spawn`): it gets its own
 * app-niri-*.scope, the session environment, and an activation token, exactly
 * like apps started from a niri keybind.
 */
Singleton {
    id: root

    function quote(arg) {
        return `'${StringUtils.shellSingleQuoteEscape(String(arg))}'`;
    }

    // Run an argv list as a detached application.
    function spawn(argv, workingDirectory = "") {
        if (!argv || argv.length === 0)
            return;
        if (workingDirectory && workingDirectory.length > 0) {
            root.spawnShell(`cd ${root.quote(workingDirectory)} && exec ${argv.map(a => root.quote(a)).join(" ")}`);
            return;
        }
        Quickshell.execDetached(["niri", "msg", "action", "spawn", "--", ...argv]);
    }

    // Run a shell command line (Config.options.apps.* style strings).
    function spawnShell(command) {
        if (!command || command.length === 0)
            return;
        Quickshell.execDetached(["niri", "msg", "action", "spawn-sh", "--", command]);
    }

    function spawnInTerminal(argv, workingDirectory = "") {
        const cmd = `${Config.options.apps.terminal} -e ${argv.map(a => root.quote(a)).join(" ")}`;
        if (workingDirectory && workingDirectory.length > 0)
            root.spawnShell(`cd ${root.quote(workingDirectory)} && ${cmd}`);
        else
            root.spawnShell(cmd);
    }

    // Replacement for Qt.openUrlExternally(): the browser/file manager xdg-open
    // starts must not end up in the shell's cgroup either.
    function openUrl(url) {
        const u = String(url ?? "");
        if (u.length === 0)
            return;
        root.spawn(["xdg-open", u]);
    }

    // DesktopEntry (or DesktopAction, which has no workingDirectory/runInTerminal).
    function launchEntry(entry, parent = null) {
        if (!entry)
            return;
        const argv = entry.command;
        if (!argv || argv.length === 0) {
            entry.execute();
            return;
        }
        const cwd = entry.workingDirectory ?? parent?.workingDirectory ?? "";
        if (entry.runInTerminal ?? parent?.runInTerminal ?? false)
            root.spawnInTerminal(argv, cwd);
        else
            root.spawn(argv, cwd);
    }
}
