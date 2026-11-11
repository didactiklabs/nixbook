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
        root.detail = { id: pl.id, title: pl.title, tracks: [] };
        YouTubeMusic.playlist(pl.id, (ok, answer) => {
            root.detailLoading = false;
            if (!ok) {
                root.detail = null;
                root.say(answer?.error || Translation.tr("YouTube Music didn't give that playlist"), "error");
                return;
            }
            root.detail = answer;
        });
    }
    function play(tracks, index, shuffle, playlistId, name) {
        if (!tracks?.length) return;
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

    onVisibleChanged: if (root.visible) {
        YouTubeMusic.refresh();
        YouTubeMusic.refreshPlaylists(false);
    }
    Component.onCompleted: YouTubeMusic.refreshPlaylists(false)

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
            visible: root.detail === null
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
            visible: root.detail === null && root.inSearch && root.searchError !== ""
            wrapMode: Text.WordWrap
            text: root.searchError
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.detail === null && root.inSearch && !root.searching && root.searchError === ""
                && root.results !== null && root.resultRows.length === 0
            text: Translation.tr("Nothing found for “%1”").arg(root.results?.query ?? "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.detail === null && root.inSearch
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
            visible: root.detail === null && !root.inSearch
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Your playlists")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: YouTubeMusic.playlistsLoading
                loading: visible
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
            visible: root.detail === null && !root.inSearch && YouTubeMusic.playlistsError !== ""
            wrapMode: Text.WordWrap
            text: YouTubeMusic.playlistsError
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.detail === null && !root.inSearch
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
                                symbol: card.modelData.id === "LM" ? "favorite" : "queue_music"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.title ?? ""
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
                            text: Translation.tr("%1: its songs").arg(card.modelData.title ?? "")
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
