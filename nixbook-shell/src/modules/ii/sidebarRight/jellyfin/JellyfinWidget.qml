pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

/**
 * The right sidebar's Jellyfin tab (sidebar.jellyfinTab, on by default,
 * shown once Jellyfin is signed in): what to watch next (what you started,
 * then the next episode of each series you follow) as wide thumbnails with
 * their progress, and what was added lately as posters. A click plays it in
 * mpv on this computer (jellyfin-mpv-shim), where you stopped; a series (or
 * an episode's list button) opens its episodes, by season, to pick one (the
 * first, say). How a play goes shows at the bottom. The list comes
 * from `jellyfin-mcp shelf` (services/Jellyfin.qml: kept between opens,
 * refreshed when shown, every 10 minutes while shown, and after a play).
 */
Item {
    id: root

    readonly property var shelf: Jellyfin.shelf
    readonly property var upNext: root.shelf?.upNext ?? []
    readonly property var recent: root.shelf?.recent ?? []
    property string playing: ""
    // How the last play goes, at the bottom: { text, kind: busy|ok|error }.
    property var status: null

    function play(item, name) {
        const what = name ?? [item.title, item.subtitle].filter(x => x).join(" · ");
        root.playing = item.id;
        root.status = { text: Translation.tr("Starting %1…").arg(what), kind: "busy" };
        Jellyfin.playItem(item.id, (ok, error) => {
            root.playing = "";
            root.status = ok ? { text: Translation.tr("Playing %1 in mpv").arg(what), kind: "ok" }
                : { text: error || Translation.tr("Jellyfin couldn't play it"), kind: "error" };
            if (ok) statusOff.restart();
        });
    }
    Timer {
        id: statusOff
        interval: 3500
        onTriggered: if (root.status?.kind === "ok") root.status = null
    }

    // A series' episodes, to pick one: Jellyfin.episodes' answer, the season
    // shown; null for the shelf.
    property var detail: null
    property bool detailLoading: false
    property int season: 0
    function openEpisodes(item) {
        const id = item.seriesId || item.id;
        root.detailLoading = true;
        root.detail = { series: item.title ?? "", seasons: [] };
        Jellyfin.episodes(id, (ok, answer) => {
            root.detailLoading = false;
            if (!ok) {
                root.detail = null;
                root.status = { text: answer?.error || Translation.tr("Jellyfin couldn't list its episodes"), kind: "error" };
                return;
            }
            root.detail = answer;
            // The season of the episode to watch next, else the first.
            const at = (answer.seasons ?? []).findIndex(s => s.episodes.some(e => e.id === answer.nextUp));
            root.season = Math.max(0, at);
        });
    }

    onVisibleChanged: if (root.visible) Jellyfin.refreshShelf(false)
    Component.onCompleted: Jellyfin.refreshShelf(false)
    Timer {
        interval: 10 * 60 * 1000
        repeat: true
        running: root.visible
        onTriggered: Jellyfin.refreshShelf(true)
    }

    // A picture, rounded, with a symbol until it loads.
    component Picture: Rectangle {
        id: pic
        property string source
        property string symbol: "movie"
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        MaterialSymbol {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: pic.symbol
            iconSize: 28
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
                source: pic.source !== "" ? `file://${pic.source}` : ""
                sourceSize.width: pic.width * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
    }

    PagePlaceholder {
        shown: root.shelf === null && !Jellyfin.shelfLoading
        icon: "live_tv"
        title: Translation.tr("Jellyfin")
        description: Jellyfin.shelfError !== "" ? Jellyfin.shelfError : Translation.tr("Nothing to show yet")
        shape: MaterialShape.Shape.Clover4Leaf
        descriptionHorizontalAlignment: Text.AlignHCenter
    }
    MaterialLoadingIndicator {
        anchors.centerIn: parent
        visible: root.shelf === null && Jellyfin.shelfLoading
        loading: visible
    }

    StyledFlickable {
        anchors.fill: parent
        anchors.bottomMargin: statusBar.visible ? statusBar.height + 8 : 0
        visible: root.shelf !== null && root.detail === null
        contentHeight: column.implicitHeight
        clip: true

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Up next")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                MaterialLoadingIndicator {
                    implicitSize: 18
                    visible: Jellyfin.shelfLoading
                    loading: visible
                }
                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    enabled: !Jellyfin.shelfLoading
                    onClicked: Jellyfin.refreshShelf(true)
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip {
                        text: Translation.tr("Refresh")
                    }
                }
            }
            StyledText {
                visible: root.upNext.length === 0
                text: Translation.tr("Nothing in progress, no next episode")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            // Wide thumbnails, a row that scrolls sideways.
            ListView {
                id: upNextList
                Layout.fillWidth: true
                visible: root.upNext.length > 0
                implicitHeight: 160
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: root.upNext
                delegate: RippleButton {
                    id: card
                    required property var modelData
                    width: 200
                    height: upNextList.height
                    buttonRadius: Appearance.rounding.small
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                    onClicked: root.play(card.modelData)
                    contentItem: ColumnLayout {
                        spacing: 2
                        Picture {
                            Layout.fillWidth: true
                            implicitHeight: 112
                            source: card.modelData.image ?? ""
                            symbol: card.modelData.kind === "episode" ? "live_tv" : "movie"
                            // How far you got.
                            Rectangle {
                                visible: (card.modelData.progress ?? 0) > 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                height: 4
                                radius: 2
                                color: ColorUtils.transparentize("black", 0.4)
                                Rectangle {
                                    width: parent.width * Math.min(1, (card.modelData.progress ?? 0) / 100)
                                    height: parent.height
                                    radius: 2
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                implicitSize: 32
                                visible: root.playing === card.modelData.id
                                loading: visible
                            }
                            // Its series' episodes, to pick another.
                            RippleButton {
                                visible: !!card.modelData.seriesId
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.transparentize("black", 0.45)
                                colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                                onClicked: root.openEpisodes(card.modelData)
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "format_list_numbered"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: "white"
                                }
                                StyledToolTip {
                                    text: Translation.tr("Episodes")
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.title ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.subtitle ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Play %1").arg([card.modelData.title, card.modelData.subtitle].filter(x => x).join(" · "))
                    }
                }
            }

            StyledText {
                Layout.topMargin: 6
                text: Translation.tr("Recently added")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: root.recent.length === 0
                text: Translation.tr("Nothing new")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            // Posters, three a row.
            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8
                readonly property real cell: (grid.width - 2 * grid.columnSpacing) / 3
                Repeater {
                    model: root.recent
                    delegate: RippleButton {
                        id: poster
                        required property var modelData
                        Layout.preferredWidth: grid.cell
                        implicitHeight: grid.cell * 1.5 + 40
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                        // A series: its episodes to pick from; else it plays.
                        onClicked: poster.modelData.kind === "series" ? root.openEpisodes(poster.modelData) : root.play(poster.modelData)
                        contentItem: ColumnLayout {
                            spacing: 2
                            Picture {
                                Layout.fillWidth: true
                                implicitHeight: grid.cell * 1.5
                                source: poster.modelData.image ?? ""
                                symbol: poster.modelData.kind === "series" ? "live_tv" : poster.modelData.kind === "album" ? "album" : "movie"
                                MaterialLoadingIndicator {
                                    anchors.centerIn: parent
                                    implicitSize: 32
                                    visible: root.playing === poster.modelData.id
                                    loading: visible
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: poster.modelData.title ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: poster.modelData.subtitle ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledToolTip {
                            text: poster.modelData.kind === "series" ? Translation.tr("%1: episodes").arg(poster.modelData.title ?? "")
                                : Translation.tr("Play %1").arg(poster.modelData.title ?? "")
                        }
                    }
                }
            }
        }
    }

    // A series' episodes: back, Play next, its seasons, each episode (a
    // tick when watched, how far when started); a click plays it.
    ColumnLayout {
        id: detailView
        anchors.fill: parent
        anchors.bottomMargin: statusBar.visible ? statusBar.height + 8 : 0
        visible: root.detail !== null
        spacing: 8
        readonly property var seasons: root.detail?.seasons ?? []
        readonly property var current: detailView.seasons[Math.min(root.season, detailView.seasons.length - 1)] ?? null
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                onClicked: root.detail = null
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Back")
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.detail?.series ?? ""
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
                visible: (root.detail?.nextUp ?? "") !== ""
                materialIcon: "play_arrow"
                mainText: Translation.tr("Play next")
                onClicked: {
                    let found = null;
                    for (const s of detailView.seasons)
                        for (const e of s.episodes)
                            if (e.id === root.detail.nextUp) found = { season: s, ep: e };
                    root.play({ id: root.detail.nextUp }, found ? `${root.detail.series} · S${found.season.number}:E${found.ep.number}` : root.detail.series);
                }
            }
        }
        // The seasons, when there are several.
        Flow {
            Layout.fillWidth: true
            visible: detailView.seasons.length > 1
            spacing: 6
            Repeater {
                model: detailView.seasons
                delegate: RippleButton {
                    id: seasonChip
                    required property var modelData
                    required property int index
                    implicitHeight: 30
                    implicitWidth: seasonText.implicitWidth + 22
                    buttonRadius: Appearance.rounding.full
                    toggled: root.season === seasonChip.index
                    onClicked: root.season = seasonChip.index
                    contentItem: StyledText {
                        id: seasonText
                        horizontalAlignment: Text.AlignHCenter
                        text: seasonChip.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: seasonChip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: detailView.current?.episodes ?? []
            delegate: RippleButton {
                id: epRow
                required property var modelData
                width: ListView.view.width
                implicitHeight: 44
                buttonRadius: Appearance.rounding.small
                colBackground: epRow.modelData.id === root.detail?.nextUp ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                onClicked: root.play(epRow.modelData, `${root.detail?.series ?? ""} · S${detailView.current?.number ?? 0}:E${epRow.modelData.number ?? "?"}`)
                contentItem: RowLayout {
                    spacing: 10
                    StyledText {
                        Layout.preferredWidth: 26
                        horizontalAlignment: Text.AlignRight
                        text: epRow.modelData.number ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: epRow.modelData.name ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        Rectangle {
                            visible: (epRow.modelData.progress ?? 0) > 0 && !epRow.modelData.played
                            Layout.preferredWidth: 80
                            implicitHeight: 3
                            radius: 1.5
                            color: Appearance.colors.colLayer2
                            Rectangle {
                                width: parent.width * Math.min(1, (epRow.modelData.progress ?? 0) / 100)
                                height: parent.height
                                radius: 1.5
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                    MaterialLoadingIndicator {
                        implicitSize: 20
                        visible: root.playing === epRow.modelData.id
                        loading: visible
                    }
                    MaterialSymbol {
                        visible: !!epRow.modelData.played
                        text: "check_circle"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        visible: epRow.modelData.id === root.detail?.nextUp
                        text: Translation.tr("Next")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    // How the last play goes, wherever the page is scrolled to.
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
