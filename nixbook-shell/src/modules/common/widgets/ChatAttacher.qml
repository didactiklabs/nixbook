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
    // false for text, to paste as usual.
    function paste(): bool {
        const entry = Cliphist.entries[0] ?? "";
        const clean = StringUtils.cleanCliphistEntry(entry);
        if (Cliphist.entryIsImage(entry)) {
            decodeProc.handleEntry(entry);
            return true;
        }
        if (clean.startsWith("file://")) {
            root.attached(decodeURIComponent(clean));
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
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            const id = entry.match(/^(\d+)\t/);
            if (!id) return;
            imageDecodeFileName = id[1];
            // Arguments, never interpolated: the entry is clipboard text.
            decodeProc.exec(["bash", "-c", '[ -f "$1" ] || printf "%s\\n" "$2" | "$3" decode > "$1"',
                "_", imageDecodeFilePath, entry, Cliphist.cliphistBinary]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.attached(imageDecodeFilePath);
            } else {
                console.error("[ChatAttacher] Failed to decode image in clipboard content");
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
