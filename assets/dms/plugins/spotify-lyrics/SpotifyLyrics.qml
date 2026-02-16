import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string artist: ""
    property string title: ""
    property bool isPlaying: false
    property string lyrics: ""
    property string lyricsBuffer: ""
    property bool lyricsVisible: isPlaying && lyrics !== "" && lyrics !== "Lyrics not found." && lyrics !== "Error parsing lyrics."

    layerNamespacePlugin: "spotifyLyrics"
    popoutWidth: 320
    popoutHeight: 400

    Timer {
        interval: 2000 // Check every 2 seconds
        running: true
        repeat: true
        onTriggered: {
            checkStatus()
        }
    }

    Component.onCompleted: {
        checkStatus()
    }

    function checkStatus() {
        statusProcess.running = true
    }
    
    Process {
        id: statusProcess
        command: ["playerctl", "--player=spotify", "metadata", "--format", "{{status}}||{{artist}}||{{title}}"]
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split("||")
                if (parts.length >= 3) {
                    var status = parts[0].trim()
                    var newArtist = parts[1].trim()
                    var newTitle = parts[2].trim()
                    
                    if (status === "Playing") {
                        root.isPlaying = true
                        if (newArtist !== root.artist || newTitle !== root.title) {
                            root.artist = newArtist
                            root.title = newTitle
                            fetchLyrics()
                        }
                    } else {
                        root.isPlaying = false
                    }
                }
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.isPlaying = false
            }
        }
    }
    
    function fetchLyrics() {
        root.lyricsBuffer = ""
        lyricsProcess.running = true
    }

    Process {
        id: lyricsProcess
        command: ["curl", "-s", "https://api.lyrics.ovh/v1/" + root.artist + "/" + root.title]
        stdout: SplitParser {
            onRead: line => {
                root.lyricsBuffer += line
            }
        }
        onExited: (code) => {
             if (code === 0 && root.lyricsBuffer !== "") {
                 try {
                     var data = JSON.parse(root.lyricsBuffer)
                     if (data.lyrics) {
                         root.lyrics = data.lyrics
                     } else {
                         root.lyrics = "Lyrics not found."
                     }
                 } catch (e) {
                     root.lyrics = "Error parsing lyrics."
                 }
             } else {
                 root.lyrics = "Error fetching lyrics."
             }
        }
    }
    
    // Desktop Widget Window
    Window {
        id: desktopWidget
        visible: root.lyricsVisible
        flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnBottomHint
        width: 600
        height: 800
        x: (Screen.width - width) / 2
        y: (Screen.height - height) / 2
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: "#80000000"
            radius: 20
            
            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: lyricsText.paintedHeight + 40
                clip: true
                
                Text {
                    id: lyricsText
                    width: parent.width - 40
                    anchors.centerIn: parent
                    text: root.lyrics
                    color: "white"
                    font.pixelSize: 18
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
    
    // Minimal bar pill implementation
    horizontalBarPill: Component { Item {} }
    verticalBarPill: Component { Item {} }
    popoutContent: Component { Item {} }
}
