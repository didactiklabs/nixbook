import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: root

    signal done(string path, int width, int height);
    required property string filePath;
    required property string sourceUrl;
    property string downloadUserAgent: Config.options?.networking.userAgent ?? ""
    
    running: true
    // Path, URL and user agent as arguments, not spliced into the script
    // (a folder with a space broke `mkdir`).
    command: ["bash", "-c",
        'mkdir -p "$(dirname "$1")"; [ -f "$1" ] || curl -sSL --url "$2" ${3:+-H "User-Agent: $3"} -o "$1" && file "$1"',
        "_", FileUtils.trimFileProtocol(root.filePath), root.sourceUrl, root.downloadUserAgent
    ]
    stdout: StdioCollector {
        id: imageSizeOutputCollector
        onStreamFinished: {
            const output = imageSizeOutputCollector.text.trim();
            const match = output.match(/(\d+)\s*x\s*(\d+)/);

            if (match) {
                const width = Number(match[1]);
                const height = Number(match[2]);
                root.done(root.filePath, width, height);
            }
        }
    }
}