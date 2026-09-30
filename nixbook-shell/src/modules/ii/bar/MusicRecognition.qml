pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell

// Music recognition (services/SongRec.qml, songrec/Shazam) in the bar. Left
// click listens (again to stop), right click switches between the desktop
// audio and the microphone, middle click opens the last song found on
// Shazam. While listening the icon pulses; a song found shows as
// "Title – Artist" for a few minutes (horizontal bar), then the icon alone.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            SongRec.toggleMonitorSource();
        else if (mouse.button === Qt.MiddleButton)
            SongRec.openShazam();
        else
            SongRec.toggleRunning();
    }

    readonly property bool listening: SongRec.running
    readonly property bool fromMonitor: SongRec.monitorSource === SongRec.MonitorSource.Monitor
    readonly property bool hasTrack: (SongRec.recognizedTrack.title ?? "").length > 0

    // The song found stays next to the icon for this long.
    readonly property int showTrackMs: 5 * 60 * 1000
    property real now: Date.now()
    Timer {
        interval: 15000
        running: root.hasTrack && !root.vertical
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Connections {
        target: SongRec
        function onRecognizedAtChanged() { root.now = Date.now() }
    }
    readonly property bool showTrack: !vertical && !listening && hasTrack
        && now - SongRec.recognizedAt < showTrackMs

    readonly property string icon: listening ? "music_cast" : fromMonitor ? "music_note" : "frame_person_mic"
    readonly property string label: listening ? Translation.tr("Listening…")
        : showTrack ? `${SongRec.recognizedTrack.title} – ${SongRec.recognizedTrack.subtitle}` : ""

    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.listening
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.pulse = 1
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.isMaterial ? materialContent : plainContent
    }

    component TrackLabel: StyledText {
        visible: !root.vertical && text.length > 0
        text: root.label
        elide: Text.ElideRight
        Layout.maximumWidth: 220
        font.pixelSize: Appearance.font.pixelSize.small
    }

    Component {
        id: plainContent
        RowLayout {
            spacing: 4
            MaterialSymbol {
                Layout.leftMargin: 4
                Layout.rightMargin: plainLabel.visible ? 0 : 4
                text: root.icon
                fill: root.listening ? 1 : 0
                iconSize: Appearance.font.pixelSize.normal
                color: root.listening ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                opacity: root.pulse
            }
            TrackLabel {
                id: plainLabel
                Layout.rightMargin: 4
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    Component {
        id: materialContent
        Item {
            implicitWidth: pill.width + 8
            implicitHeight: 24 + 6
            Rectangle {
                id: pill
                anchors.centerIn: parent
                width: Math.max(24, row.implicitWidth + (materialLabel.visible ? 14 : 0))
                height: 24
                radius: Appearance.rounding.full
                color: root.listening ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                RowLayout {
                    id: row
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: root.icon
                        fill: 1
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.listening ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        opacity: root.pulse
                    }
                    TrackLabel {
                        id: materialLabel
                        color: root.listening ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    StyledPopup {
        hoverTarget: root
        active: root.containsMouse && Config.options.bar.tooltips.enable

        ColumnLayout {
            spacing: 4

            StyledPopupHeaderRow {
                icon: "music_note"
                label: Translation.tr("Music recognition")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: root.listening ? "music_cast" : "pause_circle"
                label: Translation.tr("Status")
                value: root.listening ? Translation.tr("Listening…") : Translation.tr("Idle")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: root.fromMonitor ? "speaker" : "mic"
                label: Translation.tr("Source")
                value: root.fromMonitor ? Translation.tr("System sound") : Translation.tr("Microphone")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: root.hasTrack
                icon: "album"
                label: Translation.tr("Last song")
                value: `${SongRec.recognizedTrack.title} – ${SongRec.recognizedTrack.subtitle}`
            }

            StyledText {
                text: Translation.tr("Click: listen/stop • Right-click: switch source")
                    + (root.hasTrack ? "\n" + Translation.tr("Middle-click: open the last song on Shazam") : "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
