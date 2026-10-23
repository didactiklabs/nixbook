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

    // Ctrl+V: true when what was copied is an image or a file (attached),
    // false for text, to paste as usual. The live clipboard, not Cliphist's
    // newest entry: an image picked again from the history (Cliphist.copy)
    // is not on top of the list until it is read again.
    function paste(): bool {
        const live = Quickshell.clipboardText ?? "";
        if (live === "") {
            decodeProc.decodeLive();
            return true;
        }
        if (live.startsWith("file://")) {
            root.attached(decodeURIComponent(live.split("\n")[0].trim()));
            return true;
        }
        return false;
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

    Process {
        id: decodeProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFilePath: ""
        // The clipboard's first image type, written to a file of its own.
        function decodeLive() {
            imageDecodeFilePath = `${imageDecodePath}/paste-${Date.now()}`;
            decodeProc.exec(["bash", "-c", 'type=$(wl-paste --list-types | grep -m1 "^image/") && wl-paste --no-newline --type "$type" > "$1"',
                "_", imageDecodeFilePath]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.attached(imageDecodeFilePath);
            } else {
                console.warn("[ChatAttacher] No image in the clipboard");
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
