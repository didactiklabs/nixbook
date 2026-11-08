import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs

Item {
    id: root

    required property var fileModelData
    property bool isDirectory: fileModelData ? Boolean(fileModelData.fileIsDir) : false
    // Live (video) wallpapers get a thumbnail of a frame, like images.
    readonly property bool isLive: fileModelData ? (!isDirectory && Wallpapers.isVideo(fileModelData.fileName)) : false
    property bool useThumbnail: fileModelData ? (Images.isValidImageByName(fileModelData.fileName) || isLive) : false
    property alias colBackground: background.color
    property alias colText: wallpaperItemName.color
    property alias radius: background.radius
    property alias margins: background.anchors.margins
    property bool showLabel: true
    property alias padding: wallpaperItemColumnLayout.anchors.margins

    signal activated()
    signal previewRequested()

    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    Rectangle {
        id: background

        anchors.fill: parent
        radius: Appearance.rounding.normal

        ColumnLayout {
            id: wallpaperItemColumnLayout

            anchors.fill: parent
            spacing: 4

            Item {
                id: wallpaperItemImageContainer

                Layout.fillHeight: true
                Layout.fillWidth: true

                Loader {
                    id: thumbnailShadowLoader

                    active: thumbnailImageLoader.active && thumbnailImageLoader.item.status === Image.Ready
                    anchors.fill: thumbnailImageLoader

                    sourceComponent: StyledRectangularShadow {
                        target: thumbnailImageLoader
                        anchors.fill: undefined
                        radius: Appearance.rounding.small
                    }

                }

                Loader {
                    id: thumbnailImageLoader

                    anchors.fill: parent
                    active: root.useThumbnail

                    sourceComponent: ThumbnailImage {
                        id: thumbnailImage

                        generateThumbnail: false
                        sourcePath: (fileModelData && fileModelData.filePath) ? fileModelData.filePath : ""
                        // Cached: scrolling back or reopening doesn't decode it again.
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height - wallpaperItemColumnLayout.spacing - wallpaperItemName.height
                        layer.enabled: true

                        // No thumbnail yet: have it generated (batched per folder).
                        onStatusChanged: {
                            if (status === Image.Error)
                                Wallpapers.requestMissingThumbnail(thumbnailSizeName, sourcePath);
                        }

                        Connections {
                            function onThumbnailGenerated(directory) {
                                if (thumbnailImage.status !== Image.Error)
                                    return ;

                                if (FileUtils.parentDirectory(thumbnailImage.sourcePath) !== FileUtils.trimFileProtocol(directory))
                                    return ;

                                thumbnailImage.source = "";
                                thumbnailImage.source = thumbnailImage.thumbnailPath;
                            }

                            function onThumbnailGeneratedFile(filePath) {
                                if (thumbnailImage.status !== Image.Error)
                                    return ;

                                if (Qt.resolvedUrl(thumbnailImage.sourcePath) !== Qt.resolvedUrl(filePath))
                                    return ;

                                thumbnailImage.source = "";
                                thumbnailImage.source = thumbnailImage.thumbnailPath;
                            }

                            target: Wallpapers
                        }

                        layer.effect: OpacityMask {

                            maskSource: Rectangle {
                                width: wallpaperItemImageContainer.width
                                height: wallpaperItemImageContainer.height
                                radius: Appearance.rounding.small
                            }

                        }

                    }

                }

                // Marks a live wallpaper.
                Rectangle {
                    visible: root.isLive
                    anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                    implicitWidth: liveBadgeRow.implicitWidth + 12
                    implicitHeight: liveBadgeRow.implicitHeight + 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                    RowLayout {
                        id: liveBadgeRow
                        anchors.centerIn: parent
                        spacing: 3
                        MaterialSymbol {
                            text: "play_circle"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Live")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                Loader {
                    id: iconLoader

                    active: !root.useThumbnail
                    anchors.fill: parent

                    sourceComponent: DirectoryIcon {
                        fileModelData: root.fileModelData
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height - wallpaperItemColumnLayout.spacing - wallpaperItemName.height
                    }

                }

            }

            StyledText {
                id: wallpaperItemName

                visible: root.showLabel
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: (fileModelData && fileModelData.fileName) ? fileModelData.fileName : ""

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

            }

        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

    }

}
