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
 * The right sidebar's YouTube tab (sidebar.youtubeTab, on by default):
 * YouTube's videos to browse, played in mpv (no AI, no browser). Home is
 * your home page's recommendations, Subscriptions your subscriptions'
 * latest videos, both with the YouTube session YouTube Music signs in
 * (services/YouTubeMusic.qml, `nixbook-ytmusic videos`, through yt-dlp);
 * the search field finds any video, signed in or not. A click opens the
 * video in mpv (`nixbook-ytmusic watch`: your mpv and its configuration),
 * pausing the music playing in the background. Each feed shows its last
 * copy at once and is asked again when older than ten minutes. A video's
 * channel name opens that channel's latest videos (newest first). While a
 * video plays, a card on top shows it with its own volume (mpv's, through
 * MPRIS), which the next video starts at too.
 */
Item {
    id: root

    // home | subscriptions
    property string feed: "home"
    // {home: {items, at}, subscriptions: {items, at}}
    property var feeds: ({})
    property var loading: ({})
    property var errors: ({})
    property var counts: ({})
    readonly property int page: 30
    readonly property int maxCount: 150

    // The video playing in mpv (its MPRIS player: the YouTube link it plays;
    // not the background music player, nor Jellyfin's).
    readonly property var player: {
        const found = Mpris.players.values.filter(p => !String(p?.dbusName ?? "").includes("nixbook_ytmusic")
            && /^https:\/\/(www\.|m\.)?(youtube\.com\/watch\?|youtu\.be\/)/.test(String(p?.metadata?.["xesam:url"] ?? "")));
        return found.length ? found[found.length - 1] : null;
    }
    function setVolume(value) {
        MprisController.setPlayerVolume(root.player, value);
        Persistent.states.media.videoVolume = Math.max(0, Math.min(1, value));
    }

    // A channel's latest videos: {key, name, url, followers, items}; null
    // for your pages.
    property var channel: null
    property bool channelLoading: false
    property string channelError: ""
    function openChannel(video) {
        const key = video.channelUrl || video.id;
        root.channel = { key: key, name: video.channel, url: video.channelUrl, followers: 0, items: [] };
        root.set("counts", "channel", root.page);
        searchField.text = "";
        root.loadChannel();
    }
    function loadChannel() {
        if (!root.channel) return;
        root.channelLoading = true;
        root.channelError = "";
        const key = root.channel.key;
        YouTubeMusic.channelVideos(key, root.countOf("channel"), (ok, answer) => {
            if (root.channel?.key !== key) return;
            root.channelLoading = false;
            if (!ok) {
                root.channelError = answer?.error || Translation.tr("YouTube didn't give this channel's videos");
                return;
            }
            root.channel = Object.assign({}, root.channel, {
                name: answer.channel?.name || root.channel.name,
                url: answer.channel?.url || root.channel.url,
                followers: answer.channel?.followers ?? 0,
                items: answer.items ?? []
            });
        });
    }
    function closeChannel() {
        YouTubeMusic.cancelChannel();
        root.channel = null;
        root.channelLoading = false;
        root.channelError = "";
    }

    // How the last open went: { text, kind: busy|ok|error }.
    property var status: null
    function say(text, kind) {
        root.status = text === "" ? null : { text: text, kind: kind };
        if (kind === "ok" || kind === "busy") statusOff.restart();
    }
    Timer {
        id: statusOff
        interval: 4000
        onTriggered: root.status = null
    }

    function set(map, key, value) {
        const copy = Object.assign({}, root[map]);
        copy[key] = value;
        root[map] = copy;
    }
    function countOf(feed) {
        return root.counts[feed] ?? root.page;
    }
    function load(feed, force) {
        if (feed !== "home" && feed !== "subscriptions") return;
        if (root.loading[feed]) return;
        const have = root.feeds[feed];
        // The last copy first, at once.
        if (!have) {
            YouTubeMusic.videos(feed, root.countOf(feed), true, (ok, answer) => {
                if (ok && !root.feeds[feed] && (answer?.items ?? []).length)
                    root.set("feeds", feed, answer);
            });
        }
        if (!YouTubeMusic.signedIn) return;
        if (!force && have && Date.now() / 1000 - (have.at ?? 0) < 10 * 60) return;
        root.set("loading", feed, true);
        YouTubeMusic.videos(feed, root.countOf(feed), false, (ok, answer) => {
            root.set("loading", feed, false);
            root.set("errors", feed, ok ? "" : (answer?.error || Translation.tr("YouTube didn't answer")));
            if (ok) root.set("feeds", feed, answer);
        });
    }
    function more() {
        const feed = root.inSearch ? "search" : root.channel ? "channel" : root.feed;
        const n = Math.min(root.maxCount, root.countOf(feed) + root.page);
        root.set("counts", feed, n);
        if (feed === "channel") {
            root.loadChannel();
        } else if (feed === "search") {
            root.results = null;
            root.search(true);
        } else {
            root.load(feed, true);
        }
    }

    // A search: {query, items}; null without one.
    property var results: null
    property bool searching: false
    property string searchError: ""
    readonly property bool inSearch: searchField.text.trim().length >= 2
    function search(force) {
        const q = searchField.text.trim();
        searchDelay.stop();
        if (q.length < 2) {
            YouTubeMusic.cancelVideoSearch();
            root.searching = false;
            root.results = null;
            root.searchError = "";
            root.set("counts", "search", root.page);
            return;
        }
        if (!force && root.results?.query === q && root.searchError === "") return;
        if (root.results?.query !== q) root.set("counts", "search", root.page);
        root.searching = true;
        YouTubeMusic.searchVideos(q, root.countOf("search"), (ok, answer) => {
            root.searching = false;
            root.searchError = ok ? "" : (answer?.error || Translation.tr("YouTube didn't answer the search"));
            if (ok) root.results = answer;
        });
    }
    Timer {
        id: searchDelay
        interval: 600
        onTriggered: root.search(false)
    }

    readonly property string view: root.inSearch ? "search" : root.channel ? "channel" : root.feed
    readonly property var shown: root.view === "search" ? (root.results?.items ?? [])
        : root.view === "channel" ? (root.channel?.items ?? []) : (root.feeds[root.feed]?.items ?? [])
    readonly property bool busy: root.view === "search" ? root.searching : root.view === "channel" ? root.channelLoading : !!root.loading[root.feed]
    readonly property string error: root.view === "search" ? root.searchError : root.view === "channel" ? root.channelError : (root.errors[root.feed] ?? "")
    readonly property bool canMore: root.shown.length >= root.countOf(root.view) && root.countOf(root.view) < root.maxCount

    function watch(video) {
        if (YouTubeMusic.watch(video.id)) root.say(Translation.tr("Opening “%1” in mpv…").arg(video.title), "busy");
    }

    function length(s) {
        s = Math.max(0, Math.round(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}` : `${m}:${String(sec).padStart(2, "0")}`;
    }
    function short(n) {
        const t = n >= 1e9 ? `${(n / 1e9).toFixed(1)} B` : n >= 1e6 ? `${(n / 1e6).toFixed(1)} M` : n >= 1e3 ? `${Math.round(n / 1e3)} K` : `${n}`;
        return t.replace(".0 ", " ");
    }
    function views(n) {
        return n ? Translation.tr("%1 views").arg(root.short(n)) : "";
    }

    onVisibleChanged: {
        if (!root.visible) return;
        YouTubeMusic.refresh();
        root.load(root.feed, false);
    }
    onFeedChanged: root.load(root.feed, false)
    // Another list: from its top.
    onViewChanged: list.positionViewAtBeginning()
    Component.onCompleted: root.load(root.feed, false)
    Connections {
        target: YouTubeMusic
        function onSignedInChanged() {
            if (YouTubeMusic.signedIn) root.load(root.feed, false);
        }
    }

    component Chip: RippleButton {
        id: chip
        property string symbol
        property string label
        property bool lit: false
        implicitHeight: 34
        implicitWidth: chipRow.implicitWidth + 24
        buttonRadius: Appearance.rounding.full
        toggled: chip.lit
        colBackground: Appearance.colors.colLayer2
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: chip.symbol
                    iconSize: Appearance.font.pixelSize.large
                    fill: chip.lit ? 1 : 0
                    color: chip.lit ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: chip.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: chip.lit ? Font.DemiBold : Font.Normal
                    color: chip.lit ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
            }
        }
    }
    component IconButton: RippleButton {
        id: ib
        property string symbol
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: ib.symbol
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: ib.tip
        }
    }

    // A video: its picture with its length, title, channel and views.
    component VideoRow: RippleButton {
        id: row
        property var video
        implicitHeight: 78
        buttonRadius: Appearance.rounding.small
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        onClicked: root.watch(row.video)
        contentItem: RowLayout {
            spacing: 10
            Rectangle {
                id: pic
                implicitWidth: 120
                implicitHeight: 68
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: image.status !== Image.Ready
                    text: "smart_display"
                    iconSize: 26
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
                        source: row.video?.thumb ?? ""
                        sourceSize.width: 240
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                Rectangle {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: 4
                    }
                    visible: (row.video?.live ?? false) || (row.video?.duration ?? 0) > 0
                    implicitWidth: badge.implicitWidth + 8
                    implicitHeight: badge.implicitHeight + 2
                    radius: 4
                    color: row.video?.live ? Appearance.m3colors.m3error : "#cc000000"
                    StyledText {
                        id: badge
                        anchors.centerIn: parent
                        text: row.video?.upcoming ? Translation.tr("SOON") : row.video?.live ? Translation.tr("LIVE") : root.length(row.video?.duration)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: row.video?.live ? Appearance.m3colors.m3onError : "white"
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: row.video?.title ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    // The channel: its latest videos (not in its own list).
                    StyledText {
                        id: channelName
                        Layout.maximumWidth: parent.width - viewsText.implicitWidth
                        readonly property bool linked: root.view !== "channel" && (row.video?.channel ?? "") !== ""
                        readonly property bool hovered: channelHover.hovered
                        text: row.video?.channel ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.underline: channelName.linked && channelHover.hovered
                        color: channelName.linked && channelHover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        HoverHandler {
                            id: channelHover
                            enabled: channelName.linked
                            cursorShape: Qt.PointingHandCursor
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: channelName.linked
                            onClicked: root.openChannel(row.video)
                        }
                        StyledToolTip {
                            extraVisibleCondition: channelName.linked
                            text: Translation.tr("Their latest videos")
                        }
                    }
                    StyledText {
                        id: viewsText
                        Layout.fillWidth: true
                        text: (row.video?.channel && row.video?.views ? " · " : "") + root.views(row.video?.views ?? 0)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
        StyledToolTip {
            text: Translation.tr("Play in mpv")
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: statusBar.visible ? statusBar.height + 8 : 0
        spacing: 8

        // The video playing in mpv: its title, pause, its own volume.
        Rectangle {
            Layout.fillWidth: true
            visible: root.player !== null
            implicitHeight: nowCol.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: nowCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: "smart_display"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.player?.trackTitle ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    IconButton {
                        symbol: root.player?.isPlaying ? "pause" : "play_arrow"
                        tip: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                        onClicked: root.player?.togglePlaying()
                    }
                }
                // mpv's own volume, not the system output's.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    readonly property real volume: MprisController.playerVolume(root.player)
                    readonly property bool muted: MprisController.playerMuted(root.player)
                    IconButton {
                        symbol: parent.muted ? "volume_off" : parent.volume < 0.5 ? "volume_down" : "volume_up"
                        tip: parent.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                        onClicked: MprisController.togglePlayerMute(root.player)
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.XS
                        from: 0
                        to: 1
                        value: parent.volume
                        onMoved: root.setVolume(value)
                    }
                    StyledText {
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                        text: `${Math.round(parent.volume * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // Searching YouTube.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 40
                placeholderText: Translation.tr("Search YouTube")
                colBackground: Appearance.colors.colLayer2
                onTextChanged: {
                    if (searchField.text.trim().length < 2) root.search(false);
                    else searchDelay.restart();
                }
                onAccepted: root.search(false)
                Keys.onEscapePressed: event => {
                    if (searchField.text === "" && root.channel !== null) {
                        root.closeChannel();
                        event.accepted = true;
                        return;
                    }
                    if (searchField.text === "") {
                        event.accepted = false;
                        return;
                    }
                    searchField.text = "";
                    event.accepted = true;
                }
            }
            IconButton {
                visible: searchField.text !== ""
                symbol: "close"
                tip: Translation.tr("Clear the search")
                onClicked: searchField.text = ""
            }
        }

        // A channel's videos: back to your pages.
        RowLayout {
            Layout.fillWidth: true
            visible: !root.inSearch && root.channel !== null
            spacing: 6
            IconButton {
                symbol: "arrow_back"
                tip: Translation.tr("Back")
                onClicked: root.closeChannel()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.channel?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (root.channel?.followers ?? 0) > 0
                    text: Translation.tr("%1 subscribers · latest videos").arg(root.short(root.channel?.followers ?? 0))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: root.channelLoading
                loading: visible
            }
        }

        // Your pages.
        RowLayout {
            Layout.fillWidth: true
            visible: !root.inSearch && root.channel === null
            spacing: 6
            Chip {
                symbol: "home"
                label: Translation.tr("Home")
                lit: root.feed === "home"
                onClicked: root.feed = "home"
            }
            Chip {
                symbol: "subscriptions"
                label: Translation.tr("Subscriptions")
                lit: root.feed === "subscriptions"
                onClicked: root.feed = "subscriptions"
            }
            Item {
                Layout.fillWidth: true
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: root.busy
                loading: visible
            }
            IconButton {
                visible: YouTubeMusic.signedIn && !root.busy
                symbol: "refresh"
                tip: Translation.tr("Refresh")
                onClicked: root.load(root.feed, true)
            }
        }
        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 22
            visible: root.inSearch && root.searching
            loading: visible
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.error !== ""
            wrapMode: Text.WordWrap
            text: root.error
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.inSearch && !root.searching && root.searchError === "" && root.results !== null && root.shown.length === 0
            text: Translation.tr("Nothing found for “%1”").arg(root.results?.query ?? "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        // Signed out: your pages need the YouTube session (the search
        // doesn't).
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.inSearch && root.channel === null && !YouTubeMusic.signedIn && root.shown.length === 0
            contentHeight: signIn.implicitHeight + 20
            clip: true
            ColumnLayout {
                id: signIn
                width: parent.width
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Your home page and subscriptions need your YouTube session, the one YouTube Music uses. Searching works without it.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                YouTubeMusicAccount {
                    Layout.fillWidth: true
                    compact: true
                }
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.inSearch || root.channel !== null || YouTubeMusic.signedIn || root.shown.length > 0
            clip: true
            spacing: 2
            popin: false
            model: ScriptModel {
                values: root.shown
                objectProp: "id"
            }
            delegate: VideoRow {
                required property var modelData
                width: ListView.view.width
                video: modelData
            }
            footer: Item {
                width: list.width
                implicitHeight: root.canMore ? 48 : 0
                visible: root.canMore
                RippleButton {
                    anchors.centerIn: parent
                    implicitHeight: 34
                    implicitWidth: moreText.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    enabled: !root.busy
                    onClicked: root.more()
                    contentItem: StyledText {
                        id: moreText
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("More videos")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    // How the last open went.
    Rectangle {
        id: statusBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: root.status !== null
        implicitHeight: statusRow.implicitHeight + 16
        radius: Appearance.rounding.small
        color: root.status?.kind === "error" ? Appearance.m3colors.m3errorContainer : Appearance.colors.colLayer2
        RowLayout {
            id: statusRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8
            MaterialSymbol {
                text: root.status?.kind === "error" ? "error" : "smart_display"
                iconSize: Appearance.font.pixelSize.large
                color: root.status?.kind === "error" ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.status?.text ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.status?.kind === "error" ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer2
            }
        }
    }
}
