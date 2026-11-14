pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell.Services.Mpris
import QtQuick.Layouts

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft

    implicitWidth: 200
    implicitHeight: 200

    // The player whose lyrics these are (a view showing one player's song
    // sets it). This view's song, its lyrics (LyricsService keeps them per
    // song) and its line follow this player alone: other views showing
    // another player don't change what this one shows.
    property MprisPlayer player: MprisController.activePlayer
    readonly property string songKey: LyricsService.keyOf(root.player)
    readonly property var entry: {
        LyricsService.revision
        return LyricsService.entry(root.songKey)
    }
    readonly property string status: root.songKey === "" ? "no_info" : (root.entry?.status ?? "loading")
    readonly property var lines: root.entry?.lines ?? []
    property int activeIndex: -1
    property var slots: LyricsService.slotsFor(root.lines, root.activeIndex)

    // Asked for once the song's metadata has settled (players fill in the
    // title, artist and length in more than one update), and only while shown.
    function _ask() {
        if (root.visible && root.songKey !== "") LyricsService.need(root.songKey, root.player)
    }
    onSongKeyChanged: {
        root.activeIndex = -1
        askTimer.restart()
    }
    onVisibleChanged: if (root.visible) askTimer.restart()
    Component.onCompleted: askTimer.restart()
    Timer {
        id: askTimer
        interval: 300
        onTriggered: root._ask()
    }

    // The line follows the song to a tenth of a second; only while shown.
    Timer {
        interval: 100
        repeat: true
        running: root.visible && root.status === "ok" && root.lines.length > 0 && !Idle.screensOff
        triggeredOnStart: true
        onTriggered: {
            const idx = LyricsService.lineAt(root.lines, root.player?.position ?? 0)
            if (idx !== root.activeIndex) root.activeIndex = idx
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.status !== "ok"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    // Only while it looks: no lyrics is said, not shown as a
                    // spinner that never turns.
                    visible: root.status === "loading"
                    implicitWidth: 48
                    implicitHeight: 48

                    MaterialLoadingIndicator {
                        anchors.fill: parent
                        loading: root.status === "loading"
                        colBg: root.indicatorColor
                        colShape: root.indicatorShapeColor
                        implicitSize: 48
                    }

                    MouseArea {
                        hoverEnabled: true
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LyricsService.refetch(root.songKey, root.player)
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.status !== "loading"
                    horizontalAlignment: Text.AlignHCenter
                    text: root.status === "no_info" ? Translation.tr("No song playing")
                        : Translation.tr("No lyrics for this song")
                    color: root.dimColor
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.status === "ok"
            spacing: 6

            Repeater {
                model: 7
                delegate: StyledText {
                    id: lyricSlot
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: root.textAlignment
                    wrapMode: Text.WordWrap
                    text: root.slots[index] ?? ""
                    readonly property int dist: Math.abs(index - LyricsService.before)
                    font.pixelSize: {
                        if (dist === 0) return Appearance.font.pixelSize.normal
                        if (dist === 1) return Appearance.font.pixelSize.small
                        return Appearance.font.pixelSize.smaller
                    }
                    opacity: {
                        if (dist === 0) return 1.0
                        if (dist === 1) return 0.6
                        if (dist === 2) return 0.35
                        return 0.15
                    }
                    color: dist === 0 ? root.activeColor : root.textColor
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}