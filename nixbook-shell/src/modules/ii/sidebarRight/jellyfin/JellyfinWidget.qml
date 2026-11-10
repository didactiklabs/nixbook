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
 * mpv on this computer (jellyfin-mpv-shim), where you stopped. The list comes
 * from `jellyfin-mcp shelf` (services/Jellyfin.qml: kept between opens,
 * refreshed when shown, every 10 minutes while shown, and after a play).
 */
Item {
    id: root

    readonly property var shelf: Jellyfin.shelf
    readonly property var upNext: root.shelf?.upNext ?? []
    readonly property var recent: root.shelf?.recent ?? []
    property string playing: ""
    property string playError: ""

    function play(item) {
        root.playing = item.id;
        root.playError = "";
        Jellyfin.playItem(item.id, (ok, error) => {
            root.playing = "";
            if (!ok) root.playError = error || Translation.tr("Jellyfin couldn't play it");
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
        visible: root.shelf !== null
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
                Layout.fillWidth: true
                visible: root.playError !== ""
                text: root.playError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
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
                        onClicked: root.play(poster.modelData)
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
                            text: Translation.tr("Play %1").arg(poster.modelData.title ?? "")
                        }
                    }
                }
            }
        }
    }
}
