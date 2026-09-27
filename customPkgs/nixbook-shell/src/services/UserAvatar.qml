pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The user's account picture, the freedesktop standard way: AccountsService
 * (org.freedesktop.Accounts, the same picture login screens and other desktops
 * show). Falls back to ~/.face when AccountsService has none.
 *
 * `source` is what every avatar in the shell displays. `set(path)` changes the
 * account picture through AccountsService's SetIconFile (allowed for your own
 * account from the active session; the daemon keeps its own copy).
 */
Singleton {
    id: root

    readonly property string user: Quickshell.env("USER") ?? ""
    // AccountsService's IconFile (empty: none set, or unreadable).
    property string iconFile: ""
    property bool faceExists: false
    // Bumped on every change so Images re-read the (same-named) file.
    property int revision: 0
    property bool busy: setProc.running

    readonly property string path: root.iconFile !== "" ? root.iconFile
        : root.faceExists ? `${FileUtils.trimFileProtocol(Directories.home)}/.face` : ""
    readonly property string source: root.path !== "" ? `file://${root.path}?r=${root.revision}` : ""

    signal changed()
    signal setFailed(string message)

    function refresh() {
        readProc.running = false;
        readProc.running = true;
    }

    function set(path) {
        const file = FileUtils.trimFileProtocol(`${path}`);
        if (!file) return;
        // Normalise to a 512 px PNG first: AccountsService refuses large files
        // and keeps the file as-is for every login screen.
        setProc.command = ["bash", "-c", `
            set -e
            dir="\${XDG_CACHE_HOME:-$HOME/.cache}/nixbook-shell"; mkdir -p "$dir"
            out="$dir/account-picture.png"
            magick "$1[0]" -auto-orient -resize 512x512^ -gravity center -extent 512x512 "$out"
            obj=$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts FindUserByName s "$2" | cut -d'"' -f2)
            busctl --system call org.freedesktop.Accounts "$obj" org.freedesktop.Accounts.User SetIconFile s "$out"
        `, "set-avatar", file, root.user];
        setProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: readProc
        command: ["bash", "-c", `
            obj=$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts FindUserByName s "$1" 2>/dev/null | cut -d'"' -f2)
            icon=""
            [ -n "$obj" ] && icon=$(busctl --system get-property org.freedesktop.Accounts "$obj" org.freedesktop.Accounts.User IconFile 2>/dev/null | cut -d'"' -f2)
            [ -n "$icon" ] && [ -r "$icon" ] && [ -s "$icon" ] || icon=""
            face=0; [ -r "$HOME/.face" ] && face=1
            printf '%s\\n%s\\n' "$icon" "$face"
        `, "read-avatar", root.user]
        stdout: StdioCollector {
            id: readOut
            onStreamFinished: {
                const lines = readOut.text.split("\n");
                root.iconFile = lines[0] ?? "";
                root.faceExists = (lines[1] ?? "0") === "1";
                root.revision += 1;
                root.changed();
            }
        }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("[UserAvatar] SetIconFile failed:", setErr.text);
                root.setFailed(setErr.text.trim());
            }
            root.refresh();
        }
    }
}
