pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets

/**
 * The right sidebar's YouTube Music tab (sidebar.youtubeMusicTab, on by
 * default): YouTube Music played in the background, without a window
 * (services/YouTubeMusic.qml, `nixbook-ytmusic`). Signed out, how to sign in
 * (YouTubeMusicAccount). Signed in: what plays (shuffle, previous, play/pause,
 * next, repeat; its synced lyrics), a search field for all of YouTube Music
 * (songs and videos, `nixbook-ytmusic search`, asked once typing pauses or
 * on Enter; a found one plays with the rest of its list after it), then your
 * playlists (Liked Music first); one opens its songs: Play, Shuffle, or a
 * song to start from. How a play goes shows at the bottom.
 *
 * Offline listening: the songs heard 30 s and the playlists kept offline
 * (the detail's download button) are on this computer ("On this computer"
 * lists them); the storage button opens the space it may use, whether heard
 * songs are kept, the kept playlists and what downloads. Without network,
 * the playlists come from their last copy and only what is here plays.
 * The song playing has a seek bar with its time.
 */
Item {
    id: root

    readonly property MprisPlayer player: YouTubeMusic.player
    property bool showLyrics: false
    // How the last play goes: { text, kind: busy|ok|error }.
    property var status: null
    property string starting: ""

    function say(text, kind) {
        root.status = text === "" ? null : { text: text, kind: kind };
        if (kind === "ok") statusOff.restart();
    }
    Timer {
        id: statusOff
        interval: 3500
        onTriggered: if (root.status?.kind === "ok") root.status = null
    }

    // A playlist's songs: {id, title, tracks}; null for the playlists.
    property var detail: null
    property bool detailLoading: false
    function open(pl) {
        root.detailLoading = true;
        root.detail = { id: pl.id, title: root.playlistTitle(pl), tracks: [] };
        YouTubeMusic.playlist(pl.id, (ok, answer) => {
            root.detailLoading = false;
            if (!ok) {
                root.detail = null;
                root.say(answer?.error || Translation.tr("YouTube Music didn't give that playlist"), "error");
                return;
            }
            answer.title = root.playlistTitle(answer);
            root.detail = answer;
        });
    }
    // The open playlist read again (what is on this computer now), in place.
    function refreshDetail() {
        const id = root.detail?.id;
        if (!id || root.detailLoading) return;
        YouTubeMusic.playlist(id, (ok, answer) => {
            if (!ok || root.detail?.id !== id) return;
            answer.title = root.playlistTitle(answer);
            root.detail = answer;
        });
    }
    Connections {
        target: YouTubeMusic
        function onDownloadingChanged() {
            if (!YouTubeMusic.downloading) root.refreshDetail();
        }
    }
    function play(tracks, index, shuffle, playlistId, name) {
        if (!tracks?.length) return;
        // No network (the playlist from its copy): only what is here.
        if (root.detail?.offline && tracks === root.detail.tracks) {
            const from = tracks[index];
            tracks = tracks.filter(t => t.cached);
            if (!tracks.length) {
                root.say(Translation.tr("No song of it is on this computer, and YouTube Music can't be reached"), "error");
                return;
            }
            index = Math.max(0, tracks.indexOf(from));
        }
        root.starting = tracks[index]?.videoId ?? "";
        root.say(Translation.tr("Starting %1…").arg(name), "busy");
        YouTubeMusic.playTracks(tracks, index, shuffle, playlistId, (ok, answer) => {
            root.starting = "";
            root.say(ok ? Translation.tr("Playing %1 in the background").arg(name)
                : (answer?.error || Translation.tr("It couldn't be played")), ok ? "ok" : "error");
        });
    }
    // A search of YouTube Music: {query, songs, videos}; null without one.
    property var results: null
    property bool searching: false
    property string searchError: ""
    readonly property bool inSearch: searchField.text.trim().length >= 2
    function search() {
        const q = searchField.text.trim();
        searchDelay.stop();
        if (q.length < 2) {
            YouTubeMusic.cancelSearch();
            root.searching = false;
            root.results = null;
            root.searchError = "";
            return;
        }
        if (root.results?.query === q && root.searchError === "") return;
        root.searching = true;
        YouTubeMusic.search(q, (ok, answer) => {
            root.searching = false;
            root.searchError = ok ? "" : (answer?.error || Translation.tr("YouTube Music didn't answer the search"));
            if (ok) root.results = answer;
        });
    }
    Timer {
        id: searchDelay
        interval: 500
        onTriggered: root.search()
    }
    // The rows of the results: a heading, then its songs or videos.
    readonly property var resultRows: {
        const rows = [];
        for (const part of [["songs", Translation.tr("Songs")], ["videos", Translation.tr("Videos")]]) {
            const list = root.results?.[part[0]] ?? [];
            if (!list.length) continue;
            rows.push({ header: part[1], key: `h-${part[0]}` });
            list.forEach((t, i) => rows.push({ track: t, list: list, index: i, key: `${part[0]}-${t.videoId}` }));
        }
        return rows;
    }

    function time(s) {
        s = Math.max(0, Math.round(s || 0));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    onVisibleChanged: {
        YouTubeMusic.offlineWatched = root.visible;
        if (!root.visible) return;
        YouTubeMusic.refresh();
        YouTubeMusic.refreshPlaylists(false);
        YouTubeMusic.refreshOffline();
    }
    Component.onCompleted: {
        YouTubeMusic.offlineWatched = root.visible;
        YouTubeMusic.refreshPlaylists(false);
        YouTubeMusic.refreshOffline();
    }
    // The offline page (space, kept playlists, downloads).
    property bool offlinePage: false
    function size(bytes) {
        const gb = bytes / 1073741824;
        return gb >= 1 ? Translation.tr("%1 GB").arg(gb.toFixed(gb >= 10 ? 0 : 1)) : Translation.tr("%1 MB").arg(Math.round(bytes / 1048576));
    }
    function playlistTitle(pl) {
        return pl?.id === "_offline" ? Translation.tr("On this computer") : (pl?.title ?? "");
    }

    // A picture, rounded, with a symbol until it loads.
    component Picture: Rectangle {
        id: pic
        property string source
        property string symbol: "music_note"
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        MaterialSymbol {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: pic.symbol
            iconSize: 24
            color: Appearance.colors.colSubtext
        }
        ClippingRectangle {
            anchors.fill: parent
            radius: pic.radius
            color: "transparent"
            visible: image.status === Image.Ready
            Image {
                id: image
                anchors.fill: parent
                source: pic.source === "" ? "" : pic.source.startsWith("https://") ? pic.source : `file://${pic.source}`
                sourceSize.width: pic.width * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
    }
    component IconButton: RippleButton {
        id: ib
        property string symbol
        property bool lit: false
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: ib.lit ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: ib.symbol
            iconSize: Appearance.font.pixelSize.huge
            color: ib.lit ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: ib.tip
        }
    }

    // A song: its picture, title, artist, length; the one playing lit.
    component TrackRow: RippleButton {
        id: row
        property var track
        signal activated
        readonly property bool current: (row.track?.videoId ?? "") !== "" && String(root.player?.metadata?.["xesam:url"] ?? "").endsWith(row.track.videoId)
        // Offline, a song that isn't here can't play.
        property bool reachable: true
        opacity: row.reachable ? 1 : 0.45
        implicitHeight: 48
        buttonRadius: Appearance.rounding.small
        colBackground: row.current ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        onClicked: row.activated()
        contentItem: RowLayout {
            spacing: 10
            Picture {
                implicitWidth: row.track?.kind === "video" ? 56 : 38
                implicitHeight: 38
                source: row.track?.thumb || row.track?.art || ""
                symbol: row.track?.kind === "video" ? "movie" : "music_note"
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    implicitSize: 22
                    visible: root.starting !== "" && root.starting === (row.track?.videoId ?? "")
                    loading: visible
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.track?.title ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                    color: row.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: [row.track?.artist ?? "", row.track?.album ?? ""].filter(x => x !== "").join(" · ")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            MaterialSymbol {
                visible: row.track?.cached ?? false
                // StyledToolTip shows while its parent is hovered.
                readonly property bool hovered: cachedHover.hovered
                HoverHandler {
                    id: cachedHover
                }
                text: "download_done"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
                StyledToolTip {
                    text: Translation.tr("On this computer: plays without network")
                }
            }
            StyledText {
                text: row.track?.duration ? root.time(row.track.duration) : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // -- signed out: how to sign in --------------------------------------------
    StyledFlickable {
        anchors.fill: parent
        visible: !YouTubeMusic.signedIn
        contentHeight: signIn.implicitHeight + 20
        clip: true
        ColumnLayout {
            id: signIn
            width: parent.width
            spacing: 8
            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: "queue_music"
                    iconSize: 28
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("YouTube Music in the background")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
            }
            YouTubeMusicAccount {
                Layout.fillWidth: true
                compact: true
            }
        }
    }

    // -- signed in ---------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: statusBar.visible ? statusBar.height + 8 : 0
        visible: YouTubeMusic.signedIn
        spacing: 8

        // What plays.
        Rectangle {
            Layout.fillWidth: true
            visible: root.player !== null
            implicitHeight: nowCol.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: nowCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Picture {
                        implicitWidth: 52
                        implicitHeight: 52
                        source: root.player?.trackArtUrl ?? ""
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.player?.trackTitle ?? ""
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.player?.trackArtist ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                MediaProgressBar {
                    Layout.fillWidth: true
                    player: root.player
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4
                    IconButton {
                        symbol: "shuffle"
                        lit: root.player?.shuffle ?? false
                        tip: Translation.tr("Shuffle")
                        onClicked: YouTubeMusic.control("shuffle", "toggle")
                    }
                    IconButton {
                        symbol: "skip_previous"
                        tip: Translation.tr("Previous")
                        onClicked: YouTubeMusic.control("previous")
                    }
                    IconButton {
                        symbol: root.player?.isPlaying ? "pause" : "play_arrow"
                        lit: true
                        tip: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                        onClicked: YouTubeMusic.control("toggle")
                    }
                    IconButton {
                        symbol: "skip_next"
                        tip: Translation.tr("Next")
                        onClicked: YouTubeMusic.control("next")
                    }
                    IconButton {
                        readonly property int loop: root.player?.loopState ?? MprisLoopState.None
                        symbol: loop === MprisLoopState.Track ? "repeat_one" : "repeat"
                        lit: loop !== MprisLoopState.None
                        tip: loop === MprisLoopState.Track ? Translation.tr("Repeat: this song")
                            : loop === MprisLoopState.Playlist ? Translation.tr("Repeat: the playlist") : Translation.tr("Repeat: off")
                        onClicked: YouTubeMusic.control("repeat", "cycle")
                    }
                    IconButton {
                        symbol: "lyrics"
                        lit: root.showLyrics
                        tip: Translation.tr("Lyrics")
                        onClicked: root.showLyrics = !root.showLyrics
                    }
                }
                Lyrics {
                    Layout.fillWidth: true
                    visible: root.showLyrics && root.visible
                    implicitHeight: 180
                    textColor: Appearance.colors.colOnLayer2
                    activeColor: Appearance.colors.colPrimary
                    dimColor: Appearance.colors.colSubtext
                    textAlignment: Text.AlignHCenter
                }
            }
        }

        // Searching YouTube Music.
        RowLayout {
            Layout.fillWidth: true
            visible: root.detail === null && !root.offlinePage
            spacing: 4
            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 40
                placeholderText: Translation.tr("Search YouTube Music")
                colBackground: Appearance.colors.colLayer2
                onTextChanged: {
                    if (searchField.text.trim().length < 2) root.search();
                    else searchDelay.restart();
                }
                onAccepted: root.search()
                Keys.onEscapePressed: event => {
                    if (searchField.text === "") {
                        event.accepted = false;
                        return;
                    }
                    searchField.text = "";
                    event.accepted = true;
                }
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: root.searching
                loading: visible
            }
            IconButton {
                visible: searchField.text !== ""
                symbol: "close"
                tip: Translation.tr("Clear the search")
                onClicked: searchField.text = ""
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.detail === null && !root.offlinePage && root.inSearch && root.searchError !== ""
            wrapMode: Text.WordWrap
            text: root.searchError
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.detail === null && !root.offlinePage && root.inSearch && !root.searching && root.searchError === ""
                && root.results !== null && root.resultRows.length === 0
            text: Translation.tr("Nothing found for “%1”").arg(root.results?.query ?? "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.detail === null && !root.offlinePage && root.inSearch
            clip: true
            spacing: 2
            popin: false
            model: ScriptModel {
                values: root.resultRows
                objectProp: "key"
            }
            delegate: Loader {
                id: resultRow
                required property var modelData
                width: ListView.view.width
                sourceComponent: resultRow.modelData.header !== undefined ? resultHeader : resultTrack
                Component {
                    id: resultHeader
                    StyledText {
                        topPadding: 6
                        bottomPadding: 2
                        text: resultRow.modelData.header
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }
                Component {
                    id: resultTrack
                    TrackRow {
                        track: resultRow.modelData.track
                        // The rest of its list plays after it.
                        onActivated: root.play(resultRow.modelData.list, resultRow.modelData.index, false, "", resultRow.modelData.track.title)
                    }
                }
            }
        }

        // The playlists.
        RowLayout {
            Layout.fillWidth: true
            visible: root.detail === null && !root.offlinePage && !root.inSearch
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Your playlists")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: YouTubeMusic.playlistsLoading
                loading: visible
            }
            Rectangle {
                visible: YouTubeMusic.playlistsOffline
                implicitWidth: offlineChip.implicitWidth + 16
                implicitHeight: 24
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer
                readonly property bool hovered: chipHover.hovered
                HoverHandler {
                    id: chipHover
                }
                StyledText {
                    id: offlineChip
                    anchors.centerIn: parent
                    text: Translation.tr("Offline")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledToolTip {
                    text: Translation.tr("YouTube Music can't be reached: your playlists as they were, and only the songs on this computer play")
                }
            }
            IconButton {
                symbol: YouTubeMusic.downloading ? "downloading" : "download_for_offline"
                lit: YouTubeMusic.downloading
                tip: YouTubeMusic.downloading
                    ? Translation.tr("Downloading %1 (%2 left)").arg(YouTubeMusic.offline?.downloading?.title || "").arg(YouTubeMusic.offline?.left ?? 0)
                    : Translation.tr("Offline listening")
                onClicked: root.offlinePage = true
            }
            IconButton {
                symbol: "refresh"
                tip: Translation.tr("Refresh")
                enabled: !YouTubeMusic.playlistsLoading
                onClicked: YouTubeMusic.refreshPlaylists(true)
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.detail === null && !root.offlinePage && !root.inSearch && YouTubeMusic.playlistsError !== ""
            wrapMode: Text.WordWrap
            text: YouTubeMusic.playlistsError
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.detail === null && !root.offlinePage && !root.inSearch
            contentHeight: grid.implicitHeight
            clip: true
            GridLayout {
                id: grid
                width: parent.width
                columns: 3
                rowSpacing: 8
                columnSpacing: 8
                readonly property real cell: (grid.width - 2 * grid.columnSpacing) / 3
                Repeater {
                    model: YouTubeMusic.playlists ?? []
                    delegate: RippleButton {
                        id: card
                        required property var modelData
                        Layout.preferredWidth: grid.cell
                        implicitHeight: grid.cell + 40
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                        onClicked: root.open(card.modelData)
                        contentItem: ColumnLayout {
                            spacing: 2
                            Picture {
                                Layout.fillWidth: true
                                implicitHeight: grid.cell
                                source: card.modelData.thumb ?? ""
                                symbol: card.modelData.id === "LM" ? "favorite" : card.modelData.id === "_offline" ? "download_done" : "queue_music"
                                Rectangle {
                                    visible: YouTubeMusic.isKept(card.modelData.id) || (card.modelData.kept ?? false)
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 4
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: Appearance.colors.colPrimary
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "download_done"
                                        iconSize: 14
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.playlistTitle(card.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.count ? Translation.tr("%1 songs").arg(card.modelData.count) : (card.modelData.author ?? "")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledToolTip {
                            text: Translation.tr("%1: its songs").arg(root.playlistTitle(card.modelData))
                        }
                    }
                }
            }
        }

        // Offline listening: the space, songs heard kept, the kept
        // playlists, what downloads.
        RowLayout {
            Layout.fillWidth: true
            visible: root.detail === null && root.offlinePage
            spacing: 6
            IconButton {
                symbol: "arrow_back"
                tip: Translation.tr("Back")
                onClicked: root.offlinePage = false
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Offline listening")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
        }
        StyledFlickable {
            id: offlineFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.detail === null && root.offlinePage
            contentHeight: offlineCol.implicitHeight
            clip: true
            readonly property var o: YouTubeMusic.offline
            readonly property real limit: (o?.limitMB ?? 4096) * 1048576
            ColumnLayout {
                id: offlineCol
                width: parent.width
                spacing: 10
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Songs on this computer play without network. When the space is used up, the songs played longest ago make room; a kept playlist's songs stay.")
                }
                // The space used.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: Translation.tr("%1 of %2 used · %3 songs").arg(root.size(offlineFlick.o?.used ?? 0)).arg(root.size(offlineFlick.limit)).arg(offlineFlick.o?.count ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        value: Math.min(1, (offlineFlick.o?.used ?? 0) / offlineFlick.limit)
                    }
                }
                // How much it may use.
                StyledText {
                    text: Translation.tr("Space it may use")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [1, 2, 4, 8, 16, 32]
                        delegate: RippleButton {
                            id: chip
                            required property int modelData
                            readonly property bool on: (offlineFlick.o?.limitMB ?? 4096) === chip.modelData * 1024
                            implicitWidth: chipText.implicitWidth + 24
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            colBackground: chip.on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                            onClicked: YouTubeMusic.offlineDo(["set", "limit", String(chip.modelData * 1024)])
                            contentItem: StyledText {
                                id: chipText
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("%1 GB").arg(chip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: chip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
                // Songs heard kept.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Keep the songs I listen to")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: Translation.tr("A song heard for 30 seconds is downloaded too")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledSwitch {
                        checked: offlineFlick.o?.auto ?? true
                        onClicked: YouTubeMusic.offlineDo(["set", "auto", checked ? "on" : "off"])
                    }
                }
                // What downloads.
                RowLayout {
                    Layout.fillWidth: true
                    visible: YouTubeMusic.downloading || (offlineFlick.o?.full ?? false) || (offlineFlick.o?.error ?? "") !== ""
                    spacing: 8
                    MaterialLoadingIndicator {
                        implicitSize: 18
                        visible: YouTubeMusic.downloading
                        loading: visible
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: !YouTubeMusic.downloading && (offlineFlick.o?.error ?? "") !== "" ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        text: YouTubeMusic.downloading
                            ? Translation.tr("Downloading %1 · %2 left").arg(offlineFlick.o?.downloading?.title || offlineFlick.o?.downloading?.videoId || "").arg(offlineFlick.o?.left ?? 0)
                            : offlineFlick.o?.full ? Translation.tr("Full: the kept playlists use all the space. Give it more room, or keep fewer playlists.")
                            : Translation.tr("The last download stopped: %1").arg(offlineFlick.o?.error ?? "")
                    }
                }
                // The kept playlists.
                StyledText {
                    visible: (offlineFlick.o?.kept ?? []).length > 0
                    text: Translation.tr("Kept playlists")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (offlineFlick.o?.kept ?? []).length === 0
                    wrapMode: Text.WordWrap
                    text: Translation.tr("To keep a whole playlist, open it and click its download button.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: offlineFlick.o?.kept ?? []
                    delegate: RowLayout {
                        id: keptRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: keptRow.modelData.cached >= keptRow.modelData.total && keptRow.modelData.total > 0 ? "download_done" : "downloading"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: keptRow.modelData.title
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("%1 of %2 songs").arg(keptRow.modelData.cached).arg(keptRow.modelData.total)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        IconButton {
                            symbol: "delete"
                            tip: Translation.tr("No longer keep it: its songs are removed")
                            onClicked: YouTubeMusic.unkeepOffline(keptRow.modelData.id)
                        }
                    }
                }
                // Freeing space (a second click within 3 s confirms).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    property string confirm: ""
                    id: freeRow
                    Timer {
                        id: confirmOff
                        interval: 3000
                        onTriggered: freeRow.confirm = ""
                    }
                    function ask(what, args) {
                        if (freeRow.confirm !== what) {
                            freeRow.confirm = what;
                            confirmOff.restart();
                            return;
                        }
                        freeRow.confirm = "";
                        YouTubeMusic.offlineDo(args, () => YouTubeMusic.refreshPlaylists(true));
                    }
                    RippleButtonWithIcon {
                        enabled: (offlineFlick.o?.count ?? 0) > 0
                        materialIcon: "cleaning_services"
                        mainText: freeRow.confirm === "free" ? Translation.tr("Click again") : Translation.tr("Free space")
                        onClicked: freeRow.ask("free", ["clear"])
                        StyledToolTip {
                            text: Translation.tr("Remove the songs no kept playlist has")
                        }
                    }
                    RippleButtonWithIcon {
                        enabled: (offlineFlick.o?.count ?? 0) > 0 || (offlineFlick.o?.kept ?? []).length > 0
                        materialIcon: "delete_sweep"
                        mainText: freeRow.confirm === "all" ? Translation.tr("Click again") : Translation.tr("Remove everything")
                        onClicked: freeRow.ask("all", ["clear", "--all"])
                        StyledToolTip {
                            text: Translation.tr("Every song on this computer, and no playlist kept")
                        }
                    }
                }
            }
        }

        // A playlist's songs.
        RowLayout {
            Layout.fillWidth: true
            visible: root.detail !== null
            spacing: 6
            IconButton {
                symbol: "arrow_back"
                tip: Translation.tr("Back")
                onClicked: root.detail = null
            }
            StyledText {
                Layout.fillWidth: true
                text: root.detail?.title ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: root.detailLoading
                loading: visible
            }
            IconButton {
                readonly property bool kept: YouTubeMusic.isKept(root.detail?.id ?? "")
                visible: (root.detail?.id ?? "_offline") !== "_offline"
                symbol: kept ? "download_done" : "download_for_offline"
                lit: kept
                tip: kept ? Translation.tr("Kept on this computer: click to remove its songs") : Translation.tr("Keep on this computer, for offline listening")
                onClicked: {
                    const id = root.detail.id;
                    if (kept) YouTubeMusic.unkeepOffline(id, () => root.open({ id: id, title: root.detail?.title }));
                    else {
                        YouTubeMusic.keepOffline(id, root.detail.title);
                        root.say(Translation.tr("Downloading %1 for offline listening").arg(root.detail.title), "ok");
                    }
                }
            }
            RippleButtonWithIcon {
                enabled: (root.detail?.tracks ?? []).length > 0
                materialIcon: "play_arrow"
                mainText: Translation.tr("Play")
                onClicked: root.play(root.detail.tracks, 0, false, root.detail.id, root.detail.title)
            }
            RippleButtonWithIcon {
                enabled: (root.detail?.tracks ?? []).length > 1
                materialIcon: "shuffle"
                mainText: Translation.tr("Shuffle")
                onClicked: root.play(root.detail.tracks, Math.floor(Math.random() * root.detail.tracks.length), true, root.detail.id, root.detail.title)
            }
        }
        // How much of a kept playlist is here.
        StyledText {
            readonly property var kept: (YouTubeMusic.offline?.kept ?? []).find(k => k.id === root.detail?.id) ?? null
            Layout.fillWidth: true
            visible: root.detail !== null && (kept !== null || (root.detail?.offline ?? false))
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: root.detail?.offline && root.detail?.id !== "_offline"
                ? Translation.tr("Offline: the songs on this computer play, the others wait for the network")
                : kept === null ? ""
                : kept.cached >= kept.total ? Translation.tr("All %1 songs on this computer").arg(kept.total)
                : YouTubeMusic.offline?.full ? Translation.tr("%1 of %2 songs on this computer: the space for offline songs is full").arg(kept.cached).arg(kept.total)
                : Translation.tr("%1 of %2 songs on this computer, downloading…").arg(kept.cached).arg(kept.total)
        }
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.detail !== null
            clip: true
            spacing: 2
            model: root.detail?.tracks ?? []
            delegate: TrackRow {
                required property var modelData
                required property int index
                width: ListView.view.width
                track: modelData
                reachable: !root.detail?.offline || (modelData.cached ?? false)
                onActivated: root.play(root.detail.tracks, index, false, root.detail.id, modelData.title)
            }
        }
    }

    // How the last play goes.
    Rectangle {
        id: statusBar
        visible: root.status !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: statusRow.implicitHeight + 14
        radius: Appearance.rounding.small
        color: root.status?.kind === "error" ? Appearance.m3colors.m3errorContainer : Appearance.colors.colLayer2
        RowLayout {
            id: statusRow
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 4
            spacing: 8
            MaterialLoadingIndicator {
                implicitSize: 20
                visible: root.status?.kind === "busy"
                loading: visible
            }
            MaterialSymbol {
                visible: root.status?.kind !== "busy"
                text: root.status?.kind === "error" ? "error" : "play_circle"
                iconSize: Appearance.font.pixelSize.larger
                color: root.status?.kind === "error" ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.status?.text ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.status?.kind === "error" ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer1
            }
            RippleButton {
                visible: root.status?.kind !== "busy"
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: Appearance.rounding.full
                onClicked: root.status = null
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.status?.kind === "error" ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
                }
            }
        }
    }
}
