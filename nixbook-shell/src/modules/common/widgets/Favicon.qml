import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell.Io
import Quickshell.Widgets

IconImage {
    id: root
    property string url
    property string displayText

    property real size: 32
    property string downloadUserAgent: Config.options?.networking.userAgent ?? ""
    property string faviconDownloadPath: Directories.favicons
    // Only host-name characters: it ends up in a file name and a query string.
    property string domainName: (url.includes("vertexaisearch") ? displayText : StringUtils.getDomain(url)).replace(/[^A-Za-z0-9.-]/g, "")
    property string faviconUrl: `https://www.google.com/s2/favicons?domain=${domainName}&sz=32`
    property string fileName: `${domainName}.ico`
    property string faviconFilePath: `${faviconDownloadPath}/${fileName}`
    property string urlToLoad

    Process {
        id: faviconDownloadProcess
        running: false
        // Arguments, never interpolated into the script: the URL comes from
        // clipboard text and AI citations. Downloaded next to the target and
        // renamed, so a half-written icon is never kept.
        command: ["bash", "-c", '[ -f "$1" ] || { curl -sfL "$2" -o "$1.part" -H "User-Agent: $3" && mv -f "$1.part" "$1"; }', "_", root.faviconFilePath, root.faviconUrl, root.downloadUserAgent]
        onExited: (exitCode, exitStatus) => {
            root.urlToLoad = root.faviconFilePath
        }
    }

    Component.onCompleted: {
        if (root.domainName.length > 0) faviconDownloadProcess.running = true
    }

    source: Qt.resolvedUrl(root.urlToLoad)
    implicitSize: root.size

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.implicitSize
            height: root.implicitSize
            radius: Appearance.rounding.full
        }
    }
}