import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

/**
 * Where a song is: a seek bar (a progress bar when the player can't seek)
 * with the time gone and the song's length. The position is read once a
 * second, only while the bar is on screen and the song plays; no wave, so a
 * paused song draws nothing and a playing one one frame a second. Used by
 * the YouTube Music tab.
 */
ColumnLayout {
    id: root

    property MprisPlayer player
    property color highlightColor: Appearance.colors.colPrimary
    property color trackColor: Appearance.colors.colSecondaryContainer
    property color textColor: Appearance.colors.colSubtext
    property bool showTimes: true
    readonly property real length: root.player?.length ?? 0
    // The position as last read (MprisPlayer's is only re-read on positionChanged).
    property real position: 0

    visible: root.player !== null && root.length > 0
    spacing: 0

    function time(s) {
        s = Math.max(0, Math.round(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = String(s % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
    }
    // positionChanged makes MprisPlayer work out the position again (it is
    // the time since the last report while playing); a seek reports it too.
    function read() {
        if (root.player) root.player.positionChanged();
    }
    onPlayerChanged: root.position = root.player?.position ?? 0
    Connections {
        target: root.player
        function onPositionChanged() { root.position = root.player.position; }
        function onPostTrackChanged() { root.read(); }
        function onPlaybackStateChanged() { root.read(); }
    }
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible && (root.player?.isPlaying ?? false) && ObjectUtils.shown(root)
        onTriggered: root.read()
    }

    Loader {
        Layout.fillWidth: true
        active: root.player?.canSeek ?? false
        visible: active
        sourceComponent: StyledSlider {
            configuration: StyledSlider.Configuration.XS
            highlightColor: root.highlightColor
            trackColor: root.trackColor
            handleColor: root.highlightColor
            usePercentTooltip: false
            tooltipContent: root.time(value * root.length)
            value: root.length > 0 ? Math.min(1, root.position / root.length) : 0
            onMoved: {
                root.player.position = value * root.length;
                root.position = value * root.length;
            }
        }
    }
    Loader {
        Layout.fillWidth: true
        active: !(root.player?.canSeek ?? false)
        visible: active
        sourceComponent: StyledProgressBar {
            highlightColor: root.highlightColor
            trackColor: root.trackColor
            value: root.length > 0 ? Math.min(1, root.position / root.length) : 0
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: root.showTimes
        StyledText {
            text: root.time(root.position)
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.textColor
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: root.time(root.length)
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.textColor
        }
    }
}
