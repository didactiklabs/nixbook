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
 * your home page's recommendations, New your subscriptions' videos you
 * haven't seen yet (not in YouTube's watch history, not opened here, not
 * marked seen; the last 30 days, its count on the chip), both with the
 * YouTube session YouTube Music signs in (services/YouTubeMusic.qml,
 * `nixbook-ytmusic videos`, through yt-dlp); Subscriptions lists the
 * channels you're subscribed to (how many new videos each has), each opening
 * its latest videos;
 * the search field finds any video, signed in or not (a pasted YouTube
 * link shows that video: Enter plays it, from its t= time). A click opens the
 * video in mpv (`nixbook-ytmusic watch`: your mpv and its configuration),
 * pausing the music playing in the background. Each feed shows its last
 * copy at once and is asked again when older than ten minutes. A video's
 * channel name opens that channel's latest videos (newest first). While a
 * video plays, a card on top shows it with its own volume (mpv's, through
 * MPRIS), which the next video starts at too. Hovering a video or a
 * channel shows a button copying its link (the playing video's: at its
 * current second); a channel's page subscribes to it or no longer, has its
 * tabs (Latest, Sections: its home page's shelves, Popular: its most
 * viewed, Shorts, Live, Playlists; a section or playlist opens its videos) and searches in the channel (the search
 * field, while it is open).
 */
Item {
    id: root

    // home | new | subscriptions
    property string feed: "home"
    // {home: {items, at}, new: {items, at, historyError?}, subscriptions: {channels, at}}
    property var feeds: ({})
    property var loading: ({})
    property var errors: ({})
    property var counts: ({})
    readonly property int page: 30
    readonly property int maxCount: 150

    // The video playing in mpv (services/YouTubeMusic.qml finds it).
    readonly property var player: YouTubeMusic.videoPlayer
    function setVolume(value) {
        YouTubeMusic.setVideoVolume(value);
    }

    // A channel: {key, name, url, followers, tab (latest|sections|popular|
    // shorts|live|playlists; sections: its home page's shelves, each a
    // playlist), query (a search in it), playlist ({id, title}: one of
    // its playlists open), items (the list shown), cache ({list: items})};
    // null for your pages.
    property var channel: null
    property bool channelLoading: false
    property string channelError: ""
    readonly property var channelTabs: [
        { id: "latest", label: Translation.tr("Latest") }, { id: "sections", label: Translation.tr("Sections") },
        { id: "popular", label: Translation.tr("Popular") },
        { id: "shorts", label: Translation.tr("Shorts") }, { id: "live", label: Translation.tr("Live") },
        { id: "playlists", label: Translation.tr("Playlists") }]
    function openChannel(video) {
        const key = video.channelUrl || video.id;
        root.channel = { key: key, name: video.channel, url: video.channelUrl, followers: 0, tab: "latest", query: "",
            playlist: null, items: [], cache: {} };
        root.set("counts", "channel", root.page);
        root.unsubscribeAsked = false;
        searchField.text = "";
        root.loadChannel(false);
        // Whether you're subscribed: your list (asked if it isn't here yet).
        root.load("subscriptions", false);
    }
    // Which of the channel's lists is shown (its cache's key).
    function channelList(ch) {
        return !ch ? "" : ch.playlist ? `playlist:${ch.playlist.id}` : ch.query !== "" ? `query:${ch.query}` : ch.tab;
    }
    function loadChannel(force) {
        const ch = root.channel;
        if (!ch) return;
        const list = root.channelList(ch);
        // Shown before: at once (More, or a refresh, asks again).
        if (!force && ch.cache[list]) {
            root.channel = Object.assign({}, ch, { items: ch.cache[list] });
            root.channelLoading = false;
            root.channelError = "";
            return;
        }
        root.channelLoading = true;
        root.channelError = "";
        const key = ch.key;
        const done = (ok, answer) => {
            const now = root.channel;
            if (now?.key !== key || root.channelList(now) !== list) return;
            root.channelLoading = false;
            if (!ok) {
                root.channelError = answer?.error || Translation.tr("YouTube didn't give this channel's videos");
                return;
            }
            const cache = Object.assign({}, now.cache, { [list]: answer.items ?? [] });
            root.channel = Object.assign({}, now, {
                name: answer.channel?.name || now.name,
                url: answer.channel?.url || now.url,
                followers: answer.channel?.followers || now.followers,
                items: answer.items ?? [],
                cache: cache
            });
        };
        if (ch.playlist) YouTubeMusic.playlistVideos(ch.playlist.id, root.countOf("channel"), done);
        else YouTubeMusic.channelVideos(key, root.countOf("channel"), done, ch.tab, ch.query);
    }
    function setChannelTab(tab) {
        if (!root.channel) return;
        root.channel = Object.assign({}, root.channel, { tab: tab, playlist: null, query: "", items: [] });
        if (searchField.text !== "") searchField.text = "";
        root.set("counts", "channel", root.page);
        root.loadChannel(false);
    }
    function openPlaylist(pl) {
        if (!root.channel) return;
        root.channel = Object.assign({}, root.channel, { playlist: { id: pl.id, title: pl.title }, items: [] });
        root.set("counts", "channel", root.page);
        root.loadChannel(false);
    }
    // Back: out of a playlist, then out of a search in the channel, then
    // out of the channel.
    function back() {
        const ch = root.channel;
        if (!ch) return;
        if (ch.playlist) {
            root.channel = Object.assign({}, ch, { playlist: null, items: [] });
            root.loadChannel(false);
        } else if (ch.query !== "" || searchField.text !== "") {
            searchField.text = "";
        } else {
            root.closeChannel();
        }
    }
    // Links copied (wl-copy through services/Clipboard.qml).
    function copyLink(url) {
        Clipboard.copy(url, () => root.say(Translation.tr("Link copied"), "ok"));
    }
    function videoLink(id, at) {
        const t = Math.floor(at ?? 0);
        return `https://www.youtube.com/watch?v=${id}${t > 0 ? `&t=${t}` : ""}`;
    }
    // A channel's id (UC…) from its link, "" for an @handle not resolved yet.
    function channelIdOf(url) {
        return (String(url ?? "").match(/\/channel\/(UC[A-Za-z0-9_-]{22})/) ?? [])[1] ?? "";
    }
    function isSubscribed(id) {
        return id !== "" && (root.feeds.subscriptions?.channels ?? []).some(c => c.id === id);
    }
    // Subscribing: a second click on Subscribed (within 3 s) unsubscribes.
    property bool subscribing: false
    property bool unsubscribeAsked: false
    Timer {
        id: unsubscribeAskedOff
        interval: 3000
        onTriggered: root.unsubscribeAsked = false
    }
    function toggleSubscribe() {
        const id = root.channelIdOf(root.channel?.url);
        if (id === "" || root.subscribing) return;
        const on = !root.isSubscribed(id);
        if (!on && !root.unsubscribeAsked) {
            root.unsubscribeAsked = true;
            unsubscribeAskedOff.restart();
            return;
        }
        root.unsubscribeAsked = false;
        root.subscribing = true;
        const ch = root.channel;
        YouTubeMusic.subscribeChannel(id, on, (ok, answer) => {
            root.subscribing = false;
            if (!ok) {
                root.say(answer?.error || Translation.tr("YouTube didn't take it"), "error");
                return;
            }
            // The list at once; its picture and the rest with the next refresh.
            const subs = root.feeds.subscriptions ?? { channels: [], at: 0 };
            const others = (subs.channels ?? []).filter(c => c.id !== id);
            const channels = on ? [{ id: id, name: ch?.name ?? "", url: ch?.url ?? "", followers: ch?.followers ?? 0, avatar: "" }, ...others] : others;
            root.set("feeds", "subscriptions", Object.assign({}, subs, { channels: channels, at: 0 }));
            root.say(on ? Translation.tr("Subscribed to %1").arg(ch?.name ?? "") : Translation.tr("Unsubscribed from %1").arg(ch?.name ?? ""), "ok");
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
    // Subscriptions is the list of your channels (`videos channels`).
    function command(feed) {
        return feed === "subscriptions" ? "channels" : feed;
    }
    function load(feed, force) {
        if (feed !== "home" && feed !== "new" && feed !== "subscriptions") return;
        if (root.loading[feed]) return;
        const have = root.feeds[feed];
        // The last copy first, at once.
        if (!have) {
            YouTubeMusic.videos(root.command(feed), root.countOf(feed), true, (ok, answer) => {
                if (ok && !root.feeds[feed] && (answer?.items ?? answer?.channels ?? []).length)
                    root.set("feeds", feed, answer);
            });
        }
        if (!YouTubeMusic.signedIn) return;
        if (!force && have && Date.now() / 1000 - (have.at ?? 0) < 10 * 60) return;
        root.set("loading", feed, true);
        YouTubeMusic.videos(root.command(feed), root.countOf(feed), false, (ok, answer) => {
            root.set("loading", feed, false);
            root.set("errors", feed, ok ? "" : (answer?.error || Translation.tr("YouTube didn't answer")));
            if (ok) root.set("feeds", feed, answer);
        });
    }
    function more() {
        const feed = root.view === "channel" ? "channel" : root.view === "search" ? "search" : root.feed;
        const n = Math.min(root.maxCount, root.countOf(feed) + root.page);
        root.set("counts", feed, n);
        if (feed === "channel") {
            root.loadChannel(true);
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
    // A YouTube link pasted in the field: {id, start}, else null.
    readonly property var pastedLink: YouTubeMusic.parseVideoLink(searchField.text)
    function search(force) {
        const q = searchField.text.trim();
        searchDelay.stop();
        const link = YouTubeMusic.parseVideoLink(q);
        if (link) {
            if (!force && root.results?.query === q && root.searchError === "") return;
            root.searching = true;
            YouTubeMusic.videoInfo(link.id, (ok, answer) => {
                root.searching = false;
                root.searchError = ok ? "" : (answer?.error || Translation.tr("YouTube didn't answer"));
                if (ok) root.results = Object.assign({}, answer, { query: q, start: link.start });
            });
            return;
        }
        // A channel open: a search in it (cleared: back to its tab).
        if (root.channel) {
            const query = q.length >= 2 ? q : "";
            if (!force && root.channel.query === query) return;
            root.channel = Object.assign({}, root.channel, { query: query, playlist: null, items: [] });
            root.set("counts", "channel", root.page);
            root.loadChannel(force);
            return;
        }
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

    // A pasted link is shown even in a channel; a search there is the
    // channel's own.
    readonly property string view: root.pastedLink ? "search" : root.channel ? "channel" : root.inSearch ? "search" : root.feed
    // What the rows are: your channels, a channel's playlists, else videos.
    readonly property string rowKind: root.view === "subscriptions" ? "channel"
        : root.view === "channel" && ["playlists", "sections"].includes(root.channel?.tab ?? "") && !root.channel?.playlist && (root.channel?.query ?? "") === "" ? "playlist" : "video"
    readonly property var shown: root.view === "search" ? (root.results?.items ?? [])
        : root.view === "channel" ? (root.channel?.items ?? [])
        : root.view === "subscriptions" ? (root.feeds.subscriptions?.channels ?? []) : (root.feeds[root.feed]?.items ?? [])
    readonly property bool busy: root.view === "search" ? root.searching : root.view === "channel" ? root.channelLoading : !!root.loading[root.feed]
    readonly property string error: root.view === "search" ? root.searchError : root.view === "channel" ? root.channelError : (root.errors[root.feed] ?? "")
    readonly property bool canMore: root.view !== "subscriptions" && root.shown.length >= root.countOf(root.view) && root.countOf(root.view) < root.maxCount

    function watch(video) {
        // A pasted link's video: from its t= time.
        const start = root.view === "search" && root.results?.items?.[0]?.id === video.id ? (root.results?.start ?? 0) : 0;
        if (YouTubeMusic.watch(video.id, start)) {
            root.say(Translation.tr("Opening “%1” in mpv…").arg(video.title || video.id), "busy");
            // Watching marks it seen (`nixbook-ytmusic watch`): out of New.
            root.dropNew([video.id]);
        }
    }

    // New: your subscriptions' videos not seen yet.
    readonly property var newItems: root.feeds.new?.items ?? []
    // Their ids: a video of New shown elsewhere (a channel's page, Home, a
    // search) carries a NEW badge and the tick too.
    readonly property var newIds: {
        const ids = {};
        for (const v of root.newItems) ids[v.id] = true;
        return ids;
    }
    function isNew(video) {
        return !!video?.id && root.newIds[video.id] === true;
    }
    function dropNew(ids) {
        const have = root.feeds.new;
        if (!have) return;
        root.set("feeds", "new", Object.assign({}, have, { items: (have.items ?? []).filter(v => !ids.includes(v.id)) }));
    }
    function markSeen(ids) {
        if (!ids.length) return;
        root.dropNew(ids);
        YouTubeMusic.markVideosSeen(ids, (ok, answer) => {
            if (!ok) root.say(answer?.error || Translation.tr("Couldn't mark it seen"), "error");
        });
    }
    // A channel of your list: how many of New are theirs (the feed doesn't
    // always give a channel's id: its link or name then).
    function newCountOf(ch) {
        if (!ch) return 0;
        return root.newItems.filter(v => (v.channelId !== "" && v.channelId === ch.id)
            || (v.channelUrl !== "" && v.channelUrl === ch.url) || (!v.channelId && v.channel !== "" && v.channel === ch.name)).length;
    }
    function ago(t) {
        if (!t) return "";
        const s = Math.max(0, Date.now() / 1000 - t);
        return s < 3600 ? Translation.tr("%1 min ago").arg(Math.max(1, Math.floor(s / 60)))
            : s < 86400 ? Translation.tr("%1 h ago").arg(Math.floor(s / 3600))
            : Translation.tr("%1 d ago").arg(Math.floor(s / 86400));
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
        // New's count on its chip, and on the channels.
        if (root.feed !== "new") root.load("new", false);
    }
    onFeedChanged: root.load(root.feed, false)
    // Another list: from its top.
    onViewChanged: list.positionViewAtBeginning()
    // Another of the channel's lists: from its top too.
    readonly property string channelListShown: root.channelList(root.channel)
    onChannelListShownChanged: list.positionViewAtBeginning()
    Component.onCompleted: {
        root.load(root.feed, false);
        root.load("new", false);
    }
    Connections {
        target: YouTubeMusic
        function onSignedInChanged() {
            if (!YouTubeMusic.signedIn) return;
            root.load(root.feed, false);
            root.load("new", false);
        }
    }

    component Chip: RippleButton {
        id: chip
        property string symbol
        property string label
        property bool lit: false
        // A count beside the label (0: none).
        property int count: 0
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
                    visible: chip.symbol !== ""
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
                Rectangle {
                    visible: chip.count > 0
                    implicitWidth: Math.max(implicitHeight, countText.implicitWidth + 10)
                    implicitHeight: countText.implicitHeight + 2
                    radius: height / 2
                    color: Appearance.colors.colPrimary
                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: chip.count > 99 ? "99+" : String(chip.count)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
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

    // A channel you're subscribed to: its picture, name, subscribers; a
    // click shows its latest videos.
    // A channel's playlist: its picture, title, how many videos; a click
    // shows its videos.
    component PlaylistRow: RippleButton {
        id: prow
        property var playlist
        implicitHeight: 78
        buttonRadius: Appearance.rounding.small
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        onClicked: root.openPlaylist(prow.playlist)
        contentItem: RowLayout {
            spacing: 10
            Rectangle {
                id: ppic
                implicitWidth: 120
                implicitHeight: 68
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: pimage.status !== Image.Ready
                    text: "playlist_play"
                    iconSize: 26
                    color: Appearance.colors.colSubtext
                }
                ClippingRectangle {
                    anchors.fill: parent
                    radius: ppic.radius
                    color: "transparent"
                    visible: pimage.status === Image.Ready
                    Image {
                        id: pimage
                        anchors.fill: parent
                        source: prow.playlist?.thumb ?? ""
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
                    implicitWidth: pbadge.implicitWidth + 8
                    implicitHeight: pbadge.implicitHeight + 2
                    radius: 4
                    color: "#cc000000"
                    MaterialSymbol {
                        id: pbadge
                        anchors.centerIn: parent
                        text: "playlist_play"
                        iconSize: Appearance.font.pixelSize.normal
                        color: "white"
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: prow.playlist?.title ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (prow.playlist?.count ?? 0) > 0
                    text: Translation.tr("%1 videos").arg(prow.playlist?.count ?? 0)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            IconButton {
                visible: prowHover.hovered
                symbol: "link"
                tip: Translation.tr("Copy the playlist's link")
                onClicked: root.copyLink(`https://www.youtube.com/playlist?list=${prow.playlist?.id ?? ""}`)
            }
        }
        HoverHandler {
            id: prowHover
        }
        StyledToolTip {
            text: Translation.tr("Its videos")
        }
    }

    component ChannelRow: RippleButton {
        id: crow
        property var channelData
        implicitHeight: 60
        buttonRadius: Appearance.rounding.small
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        onClicked: root.openChannel({ channel: crow.channelData?.name ?? "", channelUrl: crow.channelData?.url ?? "", id: "" })
        contentItem: RowLayout {
            spacing: 12
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: width / 2
                color: Appearance.colors.colLayer2
                StyledText {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: (crow.channelData?.name ?? "?").slice(0, 1).toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                }
                ClippingRectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    visible: avatar.status === Image.Ready
                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: crow.channelData?.avatar ?? ""
                        sourceSize.width: 88
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: crow.channelData?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (crow.channelData?.followers ?? 0) > 0
                    text: Translation.tr("%1 subscribers").arg(root.short(crow.channelData?.followers ?? 0))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            // Their videos you haven't seen yet (in New).
            Rectangle {
                readonly property int count: root.newCountOf(crow.channelData)
                visible: count > 0
                implicitWidth: Math.max(implicitHeight, newText.implicitWidth + 12)
                implicitHeight: newText.implicitHeight + 4
                radius: height / 2
                color: Appearance.colors.colPrimary
                StyledText {
                    id: newText
                    anchors.centerIn: parent
                    text: Translation.tr("%1 new").arg(parent.count)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
            IconButton {
                visible: crowHover.hovered
                symbol: "link"
                tip: Translation.tr("Copy the channel's link")
                onClicked: root.copyLink(crow.channelData?.url ?? "")
            }
            MaterialSymbol {
                text: "chevron_right"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
        }
        HoverHandler {
            id: crowHover
        }
        StyledToolTip {
            text: Translation.tr("Their latest videos")
        }
    }

    // A video: its picture with its length, title, channel and views.
    component VideoRow: RippleButton {
        id: row
        property var video
        // In New (not seen yet); New's own list doesn't need the badge.
        readonly property bool fresh: root.isNew(row.video)
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
                // Not seen yet (one of New's).
                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        margins: 4
                    }
                    visible: row.fresh && root.view !== "new"
                    implicitWidth: newBadge.implicitWidth + 8
                    implicitHeight: newBadge.implicitHeight + 2
                    radius: 4
                    color: Appearance.colors.colPrimary
                    StyledText {
                        id: newBadge
                        anchors.centerIn: parent
                        text: Translation.tr("NEW")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    // A pasted link YouTube said nothing about: its id.
                    text: row.video?.title || Translation.tr("YouTube video %1").arg(row.video?.id ?? "")
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: row.fresh && root.view !== "new" ? Font.DemiBold : Font.Normal
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
                        readonly property string age: root.ago(row.video?.published ?? 0)
                        text: [root.views(row.video?.views ?? 0), age].filter(t => t !== "").map(t => " · " + t).join("").slice(row.video?.channel ? 0 : 3)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            IconButton {
                visible: rowHover.hovered
                symbol: "link"
                tip: Translation.tr("Copy the video's link")
                onClicked: root.copyLink(root.videoLink(row.video?.id ?? ""))
            }
            // New's (here or on a channel's page): seen without watching it here.
            IconButton {
                visible: rowHover.hovered && row.fresh
                symbol: "done"
                tip: Translation.tr("Mark as seen")
                onClicked: root.markSeen([row.video?.id ?? ""])
            }
        }
        HoverHandler {
            id: rowHover
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
                        symbol: "link"
                        tip: Translation.tr("Copy the link, at this moment")
                        onClicked: root.copyLink(root.videoLink((String(root.player?.metadata?.["xesam:url"] ?? "").match(/[?&]v=([A-Za-z0-9_-]{11})/) ?? [])[1] ?? "",
                            root.player?.position ?? 0))
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
                placeholderText: root.channel ? Translation.tr("Search in %1").arg(root.channel.name || Translation.tr("this channel"))
                    : Translation.tr("Search YouTube or paste a link")
                colBackground: Appearance.colors.colLayer2
                onTextChanged: {
                    if (searchField.text.trim().length < 2) root.search(false);
                    // A pasted link: shown at once.
                    else if (YouTubeMusic.parseVideoLink(searchField.text)) root.search(false);
                    else searchDelay.restart();
                }
                // Enter on a pasted link plays it.
                onAccepted: {
                    const link = YouTubeMusic.parseVideoLink(searchField.text);
                    if (link) root.watch(root.results?.items?.[0]?.id === link.id ? root.results.items[0] : { id: link.id, title: "" });
                    else root.search(false);
                }
                Keys.onEscapePressed: event => {
                    if (searchField.text === "" && root.channel !== null) {
                        root.back();
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

        // A channel's page: back (out of a playlist, a search, the channel).
        RowLayout {
            Layout.fillWidth: true
            visible: root.channel !== null && !root.pastedLink
            spacing: 6
            IconButton {
                symbol: "arrow_back"
                tip: Translation.tr("Back")
                onClicked: root.back()
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
                    visible: text !== ""
                    // What is shown: a playlist, a search, else its subscribers
                    // and how many of its videos you haven't seen (New's).
                    readonly property int fresh: root.newCountOf({ id: root.channelIdOf(root.channel?.url), url: root.channel?.url ?? "",
                        name: root.channel?.name ?? "" })
                    text: root.channel?.playlist ? Translation.tr("Playlist: %1").arg(root.channel.playlist.title)
                        : (root.channel?.query ?? "") !== "" ? Translation.tr("Search: %1").arg(root.channel.query)
                        : [(root.channel?.followers ?? 0) > 0 ? Translation.tr("%1 subscribers").arg(root.short(root.channel?.followers ?? 0)) : "",
                            fresh > 0 ? Translation.tr("%1 new").arg(fresh) : ""].filter(t => t !== "").join(" · ")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            MaterialLoadingIndicator {
                implicitSize: 18
                visible: root.channelLoading || root.subscribing
                loading: visible
            }
            IconButton {
                visible: (root.channel?.url ?? "") !== ""
                symbol: "link"
                tip: Translation.tr("Copy the channel's link")
                onClicked: root.copyLink(root.channel?.url ?? "")
            }
            // Subscribe, or Subscribed (a second click unsubscribes).
            RippleButton {
                id: subButton
                readonly property bool subscribed: root.isSubscribed(root.channelIdOf(root.channel?.url))
                visible: YouTubeMusic.signedIn && root.channelIdOf(root.channel?.url) !== ""
                enabled: !root.subscribing
                implicitHeight: 34
                implicitWidth: subText.implicitWidth + 28
                buttonRadius: Appearance.rounding.full
                toggled: !subscribed
                colBackground: Appearance.colors.colLayer2
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                onClicked: root.toggleSubscribe()
                contentItem: StyledText {
                    id: subText
                    horizontalAlignment: Text.AlignHCenter
                    text: !subButton.subscribed ? Translation.tr("Subscribe")
                        : root.unsubscribeAsked ? Translation.tr("Unsubscribe?") : Translation.tr("Subscribed")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: !subButton.subscribed ? Appearance.colors.colOnPrimary
                        : root.unsubscribeAsked ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                }
            }
        }

        // The channel's tabs.
        Flow {
            Layout.fillWidth: true
            visible: root.channel !== null && !root.pastedLink && !root.channel?.playlist && (root.channel?.query ?? "") === ""
            spacing: 6
            Repeater {
                model: root.channelTabs
                delegate: Chip {
                    required property var modelData
                    implicitHeight: 30
                    label: modelData.label
                    lit: root.channel?.tab === modelData.id
                    onClicked: root.setChannelTab(modelData.id)
                }
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
                symbol: "new_releases"
                label: Translation.tr("New")
                count: root.newItems.length
                lit: root.feed === "new"
                onClicked: root.feed = "new"
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
            IconButton {
                visible: root.view === "new" && root.shown.length > 0
                symbol: "done_all"
                tip: Translation.tr("Mark all as seen")
                onClicked: root.markSeen(root.shown.map(v => v.id))
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
            visible: root.view === "new" && !root.busy && root.error === "" && root.feeds.new !== undefined && root.shown.length === 0
            wrapMode: Text.WordWrap
            text: Translation.tr("Nothing new: you've seen your subscriptions' latest videos")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.view === "new" && (root.feeds.new?.historyError ?? "") !== ""
            wrapMode: Text.WordWrap
            text: Translation.tr("YouTube's watch history couldn't be read: only the videos opened here or marked seen are left out")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.view === "search" && !root.searching && root.searchError === "" && root.results !== null && root.shown.length === 0
            text: Translation.tr("Nothing found for “%1”").arg(root.results?.query ?? "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.view === "channel" && !root.channelLoading && root.channelError === "" && root.shown.length === 0
                && ((root.channel?.query ?? "") !== "" || (root.channel?.cache ?? {})[root.channelListShown] !== undefined)
            text: (root.channel?.query ?? "") !== "" ? Translation.tr("Nothing found for “%1” in this channel").arg(root.channel.query)
                : Translation.tr("Nothing here")
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
            // Your channels on Subscriptions, videos everywhere else.
            delegate: Loader {
                id: rowLoader
                required property var modelData
                width: ListView.view.width
                sourceComponent: root.rowKind === "channel" ? channelRowComponent
                    : root.rowKind === "playlist" ? playlistRowComponent : videoRowComponent
                Component {
                    id: videoRowComponent
                    VideoRow {
                        video: rowLoader.modelData
                    }
                }
                Component {
                    id: channelRowComponent
                    ChannelRow {
                        channelData: rowLoader.modelData
                    }
                }
                Component {
                    id: playlistRowComponent
                    PlaylistRow {
                        playlist: rowLoader.modelData
                    }
                }
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
