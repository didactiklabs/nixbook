import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

// What can go with a message to Claude: the image or file copied (Ctrl+V),
// a file dropped, or an image picked. `attached` gives its path, for the
// chat to attach (AiChatSession.attachFile). The side panel's and the
// bubble's (AgentSpeech) input.
Item {
    id: root
    signal attached(string path)

    // Ctrl+V into `field`: an image or a file copied is attached, text is
    // pasted into it. Reads the live clipboard (wl-paste): the history's
    // first entry is only refreshed on a text copy, so an image copied was
    // never seen. Always true (the key is handled).
    function paste(field): bool {
        pasteProc.field = field;
        pasteProc.exec(["bash", "-c", 'types=$(wl-paste --list-types) || exit 1; '
            + 'img=$(printf "%s\\n" "$types" | grep -m1 "^image/"); '
            + 'if [ -n "$img" ]; then ext=${img#image/}; ext=${ext%%+*}; mkdir -p "$1"; '
            + 'f="$1/paste-$(date +%s%N).$ext"; wl-paste -t "$img" > "$f" && printf "image\\n%s" "$f"; exit; fi; '
            + 'if printf "%s\\n" "$types" | grep -qx "text/uri-list"; then '
            + 'u=$(wl-paste -t text/uri-list | tr -d "\\r" | grep -m1 "^file://"); '
            + '[ -n "$u" ] && printf "file\\n%s" "$u" && exit; fi; echo text',
            "_", Directories.cliphistDecode]);
        return true;
    }
    // A drop (DropArea's): its first local file.
    function dropped(event): bool {
        const url = event.hasUrls && event.urls.length > 0 ? event.urls[0].toString() : "";
        if (!url.startsWith("file://")) return false;
        root.attached(decodeURIComponent(url));
        return true;
    }
    function pick() {
        pickProc.running = true;
    }

    // Prints "image\n<path saved>", "file\n<file:// uri>" or "text".
    Process {
        id: pasteProc
        property var field: null
        stdout: StdioCollector {
            id: pasteOutput
        }
        onExited: (exitCode, exitStatus) => {
            const lines = pasteOutput.text.split("\n");
            if (exitCode === 0 && lines[0] === "image" && lines[1]) {
                root.attached(lines[1]);
            } else if (exitCode === 0 && lines[0] === "file" && lines[1]) {
                root.attached(decodeURIComponent(lines[1]));
            } else {
                if (exitCode !== 0) console.error("[ChatAttacher] Failed to read the clipboard");
                pasteProc.field?.paste();
            }
        }
    }

    Process {
        id: pickProc
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp image/gif"]
        stdout: StdioCollector {
            id: pickOutput
        }
        onExited: (code) => {
            const path = pickOutput.text.trim();
            if (code === 0 && path !== "") root.attached(path);
        }
    }
}
