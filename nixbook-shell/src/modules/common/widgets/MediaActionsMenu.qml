pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris

/**
 * "More" menu for any MPRIS player, shared by the dock card, the media popup /
 * right sidebar player and the left sidebar player. Everything is gated on
 * what the current player actually supports, so each app shows its own extras:
 *
 *  - the media source (which player the shell controls)
 *  - stop, shuffle, repeat, fullscreen
 *  - the track's link (xesam:url, Spotify track ids): copy / open / send to
 *    the phone over KDE Connect
 *  - play a link from the clipboard (OpenUri; open.spotify.com links become
 *    spotify: URIs for Spotify, http links go to mpv/VLC…)
 *  - "Up next" (MPRIS TrackList) and playlists (MPRIS Playlists), read over
 *    D-Bus by scripts/mpris/mpris-extras.sh when the menu opens
 *  - show / quit the player
 *
 * Open with toggle(); closes on an action, when the pointer leaves it, or with
 * its parent window.
 */
PopupWindow {
    id: root
    property MprisPlayer player: MprisController.activePlayer
    required property Item anchorItem
    property bool openUpwards: true
    property bool open: false
    // Opened from the dock: keep the dock revealed while open.
    property bool holdsDock: false
    property bool _holding: false
    function _syncHold() {
        const want = root.holdsDock && root.open;
        if (want === root._holding) return;
        root._holding = want;
        GlobalStates.dockPopupsOpen += want ? 1 : -1;
    }
    onHoldsDockChanged: root._syncHold()
    Component.onDestruction: if (root._holding) GlobalStates.dockPopupsOpen -= 1

    anchor.item: root.anchorItem
    anchor.edges: root.openUpwards ? Edges.Top : Edges.Bottom
    anchor.gravity: root.openUpwards ? Edges.Top : Edges.Bottom
    // (An xdg popup goes away with its parent surface, so a hidden media
    // popup/sidebar takes the menu with it.)
    visible: root.open
    color: "transparent"
    implicitWidth: card.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: card.implicitHeight + Appearance.sizes.elevationMargin * 2

    // Per-open state
    property string trackUrl: ""
    property string clipUri: ""
    property var tracks: []
    property var playlists: []
    readonly property var phone: KdeConnect.reachableDevices.find(d => KdeConnect.hasPlugin(d, "share")) ?? null

    function toggle() {
        if (root.open) {
            root.open = false;
            return;
        }
        root.refresh();
        root.open = true;
    }
    function close() {
        root.open = false;
    }
    function refresh() {
        root.trackUrl = MprisController.trackUrl(root.player);
        root.clipUri = MprisController.clipboardUriFor(root.player);
        root.tracks = [];
        root.playlists = [];
        if (root.player?.dbusName) {
            extras.run(["caps", root.player.dbusName]);
        }
    }
    function act(fn) {
        fn();
        root.close();
    }
    onPlayerChanged: if (root.open) root.refresh()

    Process {
        id: extras
        property var args: []
        property var queue: []
        function run(a) {
            if (running) {
                queue.push(a);
                return;
            }
            args = a;
            command = ["bash", Quickshell.shellPath("scripts/mpris/mpris-extras.sh"), ...a];
            running = true;
        }
        stdout: StdioCollector {
            id: extrasOut
            onStreamFinished: {
                let data;
                try {
                    data = JSON.parse(extrasOut.text);
                } catch (e) {
                    return;
                }
                const bus = extras.args[1];
                switch (extras.args[0]) {
                case "caps":
                    if (data.trackList) extras.queue.push(["tracks", bus]);
                    if (data.playlists) extras.queue.push(["playlists", bus]);
                    break;
                case "tracks":
                    root.tracks = Array.isArray(data) ? data : [];
                    break;
                case "playlists":
                    root.playlists = Array.isArray(data) ? data : [];
                    break;
                }
            }
        }
        onExited: {
            const next = queue.shift();
            if (next) Qt.callLater(() => run(next));
        }
    }

    // Close shortly after the pointer leaves the menu; if it never gets there,
    // give it a few seconds (the menu opens under a click on its button).
    readonly property bool hovered: menuHover.hovered
    property bool everHovered: false
    onHoveredChanged: {
        if (hovered) {
            everHovered = true;
            leaveTimer.stop();
        } else {
            leaveTimer.restart();
        }
    }
    onOpenChanged: {
        root._syncHold();
        everHovered = false;
        if (open) leaveTimer.restart();
    }
    Timer {
        id: leaveTimer
        interval: root.everHovered ? 800 : 4000
        onTriggered: if (!root.hovered) root.close()
    }

    component SectionLabel: StyledText {
        Layout.topMargin: 4
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }
    component ActionRow: RippleButtonWithIcon {
        Layout.fillWidth: true
        buttonRadius: Appearance.rounding.small
        implicitHeight: 34
        colBackground: "transparent"
    }
    StyledRectangularShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: 300
        implicitHeight: menuCol.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        HoverHandler {
            id: menuHover
        }

        ColumnLayout {
            id: menuCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                spacing: 8
                Item {
                    implicitWidth: 20
                    implicitHeight: 20
                    IconImage {
                        anchors.fill: parent
                        visible: MprisController.playerIcon(root.player) !== ""
                        source: visible ? Quickshell.iconPath(MprisController.playerIcon(root.player), "audio-x-generic") : ""
                        asynchronous: true
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: MprisController.playerIcon(root.player) === ""
                        text: MprisController.playerSymbol(root.player)
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: MprisController.playerName(root.player) || Translation.tr("No player")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }

            // Source: switch between players (browser, YouTube Music, Spotify,
            // phone…) — hidden when there's only one.
            SectionLabel {
                visible: sourceChips.shouldShow
                text: Translation.tr("Source")
            }
            MediaSourceSelector {
                id: sourceChips
                Layout.fillWidth: true
                Layout.bottomMargin: 4
            }

            // Playback
            SectionLabel {
                text: Translation.tr("Playback")
            }
            ActionRow {
                visible: root.player?.canControl ?? false
                materialIcon: "stop"
                mainText: Translation.tr("Stop")
                onClicked: root.act(() => root.player.stop())
            }
            ActionRow {
                visible: root.player?.shuffleSupported ?? false
                materialIcon: (root.player?.shuffle ?? false) ? "shuffle_on" : "shuffle"
                mainText: (root.player?.shuffle ?? false) ? Translation.tr("Shuffle: on") : Translation.tr("Shuffle: off")
                onClicked: MprisController.toggleShuffle(root.player)
            }
            ActionRow {
                visible: root.player?.loopSupported ?? false
                materialIcon: MprisController.loopIcon(root.player)
                mainText: root.player?.loopState === MprisLoopState.Track ? Translation.tr("Repeat: track")
                    : root.player?.loopState === MprisLoopState.Playlist ? Translation.tr("Repeat: all")
                    : Translation.tr("Repeat: off")
                onClicked: MprisController.cycleLoop(root.player)
            }
            ActionRow {
                visible: root.player?.canSetFullscreen ?? false
                materialIcon: (root.player?.fullscreen ?? false) ? "fullscreen_exit" : "fullscreen"
                mainText: (root.player?.fullscreen ?? false) ? Translation.tr("Exit fullscreen") : Translation.tr("Fullscreen")
                onClicked: root.act(() => root.player.fullscreen = !root.player.fullscreen)
            }

            // Track link
            SectionLabel {
                visible: root.trackUrl !== ""
                text: Translation.tr("Track link")
            }
            ActionRow {
                visible: root.trackUrl !== ""
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy link")
                onClicked: root.act(() => Quickshell.clipboardText = root.trackUrl)
            }
            ActionRow {
                visible: root.trackUrl !== ""
                materialIcon: "open_in_browser"
                mainText: Translation.tr("Open in browser")
                onClicked: root.act(() => AppLaunch.openUrl(root.trackUrl))
            }
            ActionRow {
                visible: root.trackUrl !== "" && root.phone !== null
                materialIcon: "send_to_mobile"
                mainText: Translation.tr("Send to %1").arg(root.phone?.name ?? "")
                onClicked: root.act(() => KdeConnect.shareUrl(root.phone.id, root.trackUrl))
            }

            // Clipboard link the player can open
            ActionRow {
                visible: root.clipUri !== ""
                materialIcon: "content_paste_go"
                mainText: Translation.tr("Play link from clipboard")
                onClicked: root.act(() => root.player.openUri(root.clipUri))
            }

            // Up next (MPRIS TrackList)
            SectionLabel {
                visible: root.tracks.length > 0
                text: Translation.tr("Up next")
            }
            Repeater {
                model: root.tracks.slice(0, 8)
                delegate: RippleButton {
                    id: trackRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    onClicked: {
                        extras.run(["goto", root.player.dbusName, modelData.id]);
                        root.close();
                    }
                    contentItem: ColumnLayout {
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            elide: Text.ElideRight
                            text: trackRow.modelData.title || Translation.tr("Unknown title")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            visible: trackRow.modelData.artist !== ""
                            elide: Text.ElideRight
                            text: trackRow.modelData.artist
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Playlists (MPRIS Playlists)
            SectionLabel {
                visible: root.playlists.length > 0
                text: Translation.tr("Playlists")
            }
            Repeater {
                model: root.playlists.slice(0, 12)
                delegate: ActionRow {
                    required property var modelData
                    materialIcon: "queue_music"
                    mainText: modelData.name
                    onClicked: {
                        extras.run(["activate", root.player.dbusName, modelData.id]);
                        root.close();
                    }
                }
            }

            // App
            SectionLabel {
                visible: (root.player?.canRaise ?? false) || (root.player?.canQuit ?? false)
                text: Translation.tr("App")
            }
            ActionRow {
                visible: root.player?.canRaise ?? false
                materialIcon: "open_in_new"
                mainText: Translation.tr("Show %1").arg(MprisController.playerName(root.player))
                onClicked: root.act(() => MprisController.raisePlayer(root.player))
            }
            ActionRow {
                visible: root.player?.canQuit ?? false
                materialIcon: "close"
                mainText: Translation.tr("Quit %1").arg(MprisController.playerName(root.player))
                onClicked: root.act(() => root.player.quit())
            }
        }
    }
}
