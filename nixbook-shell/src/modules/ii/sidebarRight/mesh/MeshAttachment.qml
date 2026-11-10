pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * A mesh message's file (services/Mesh.qml): an image or a GIF shown in the
 * bubble once it is here (click: open it, right click or the button: a copy
 * in Downloads), any other file as a card (open, save). While it moves, how
 * far it is; when it can't come, why (gone from the server, an error to retry).
 */
ColumnLayout {
    id: root
    required property var message
    property real maxWidth: 260
    property color textColor: Appearance.colors.colOnLayer2
    property color subColor: Appearance.colors.colSubtext

    readonly property var file: root.message.file ?? {}
    readonly property bool here: !!root.file.path
    readonly property var transfer: Mesh.transfers[root.message.mid] ?? null
    // Shown as a picture: an image Qt can decode in reasonable memory.
    readonly property bool showImage: root.here && !!root.file.image && !imageFailed
        && (root.file.size ?? 0) <= 60e6 && (root.file.w ?? 0) * (root.file.h ?? 0) <= 80e6
    readonly property bool animated: root.showImage && !!root.file.animated && (root.file.size ?? 0) <= 30e6
    property bool imageFailed: false
    // A big file: downloaded on a click (Mesh.autoFetchBytes).
    readonly property bool waitsForClick: !root.here && !root.transfer && !root.file.expired && !root.file.error
        && !!root.file.k && (root.file.size ?? 0) > Mesh.autoFetchBytes
    property string saved: ""

    // The picture's box: its own proportions, within the bubble, ≤ 280 px high.
    readonly property real natW: (root.file.w ?? 0) > 0 ? root.file.w : 240
    readonly property real natH: (root.file.h ?? 0) > 0 ? root.file.h : 160
    readonly property real scaleBy: Math.min(1, root.maxWidth / root.natW, 280 / root.natH)
    spacing: 4

    function url(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }
    function save() {
        Mesh.saveFile(root.file, (ok, where) => {
            root.saved = ok ? Translation.tr("Saved to %1").arg(where.replace(Directories.home, "~"))
                : Translation.tr("Not saved: %1").arg(where);
            savedTimer.restart();
        });
    }
    Timer {
        id: savedTimer
        interval: 4000
        onTriggered: root.saved = ""
    }

    Item {
        visible: root.showImage
        Layout.preferredWidth: Math.max(48, Math.round(root.natW * root.scaleBy))
        Layout.preferredHeight: Math.max(48, Math.round(root.natH * root.scaleBy))
        Loader {
            id: picture
            anchors.fill: parent
            active: root.showImage
            sourceComponent: root.animated ? gifComponent : imageComponent
        }
        Component {
            id: imageComponent
            Image {
                asynchronous: true
                autoTransform: true
                cache: false
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(root.maxWidth * 2)
                source: root.url(root.file.path)
                onStatusChanged: if (status === Image.Error) root.imageFailed = true
            }
        }
        Component {
            id: gifComponent
            AnimatedImage {
                id: gif
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectFit
                source: root.url(root.file.path)
                // Only while it can be seen: the sidebar stays mapped when closed.
                playing: Mesh.viewing && ObjectUtils.shown(gif)
                onStatusChanged: if (status === Image.Error) root.imageFailed = true
            }
        }
        MouseArea {
            id: pictureMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => mouse.button === Qt.RightButton && Mesh.isMeshCopy(root.file) ? root.save() : Mesh.openFile(root.file)
        }
        RippleButton {
            visible: (pictureMouse.containsMouse || hovered) && Mesh.isMeshCopy(root.file)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 4
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)
            onClicked: root.save()
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "download"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
            }
            StyledToolTip {
                text: Translation.tr("Save a copy in Downloads")
            }
        }
    }

    // Any other file, or a picture not here yet.
    RowLayout {
        visible: !root.showImage
        Layout.maximumWidth: root.maxWidth
        spacing: 8
        MaterialSymbol {
            text: {
                const mime = root.file.mime ?? "";
                if (root.file.expired) return "cloud_off";
                if (/^image\//.test(mime)) return "image";
                if (/^video\//.test(mime)) return "movie";
                if (/^audio\//.test(mime)) return "music_note";
                if (/pdf$/.test(mime)) return "picture_as_pdf";
                if (/zip|tar|compressed|x-7z|rar/.test(mime)) return "folder_zip";
                if (/^text\//.test(mime)) return "description";
                return "draft";
            }
            iconSize: 28
            color: root.textColor
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.file.name || Translation.tr("File")
                elide: Text.ElideMiddle
                font.weight: Font.DemiBold
                color: root.textColor
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: {
                    const size = (root.file.size ?? 0) > 0 ? Mesh.sizeText(root.file.size) : "";
                    const t = root.transfer;
                    if (t && t.total > 0)
                        return Translation.tr("%1 · %2%").arg(root.message.mine && !root.file.sha ? Translation.tr("sending")
                            : Translation.tr("downloading")).arg(Math.floor(100 * t.done / t.total));
                    if (root.file.expired) return Translation.tr("No longer on the mesh's server");
                    if (root.file.error) return Translation.tr("%1 · not downloaded: %2 (click to retry)").arg(size).arg(root.file.error);
                    if (!root.here && root.message.mine && root.message.status !== "sent") return size;
                    if (!root.here && root.waitsForClick) {
                        const until = (root.file.exp ?? 0) > 0
                            ? Translation.tr(" · on the server until %1").arg(Qt.locale().toString(new Date(root.file.exp * 1000), Locale.ShortFormat))
                            : "";
                        return size + until;
                    }
                    if (!root.here) return Translation.tr("%1 · waiting").arg(size);
                    return size;
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.file.error || root.file.expired ? Appearance.m3colors.m3error : root.subColor
                MouseArea {
                    anchors.fill: parent
                    enabled: !!root.file.error
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Mesh.fetchFile(root.message.mid)
                }
            }
            Rectangle {
                visible: !!root.transfer && root.transfer.total > 0
                Layout.fillWidth: true
                Layout.topMargin: 3
                implicitHeight: 3
                radius: 1.5
                color: ColorUtils.transparentize(root.textColor, 0.8)
                Rectangle {
                    width: parent.width * Math.min(1, (root.transfer?.done ?? 0) / Math.max(1, root.transfer?.total ?? 1))
                    height: parent.height
                    radius: parent.radius
                    color: root.textColor
                }
            }
        }
        RippleButton {
            visible: root.waitsForClick
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: Mesh.fetchFile(root.message.mid)
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "download"
                iconSize: Appearance.font.pixelSize.normal
                color: root.textColor
            }
            StyledToolTip {
                text: Translation.tr("Download")
            }
        }
        RippleButton {
            visible: root.here
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: Mesh.openFile(root.file)
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "open_in_new"
                iconSize: Appearance.font.pixelSize.normal
                color: root.textColor
            }
            StyledToolTip {
                text: Translation.tr("Open")
            }
        }
        RippleButton {
            visible: root.here && Mesh.isMeshCopy(root.file)
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: root.save()
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "download"
                iconSize: Appearance.font.pixelSize.normal
                color: root.textColor
            }
            StyledToolTip {
                text: Translation.tr("Save a copy in Downloads")
            }
        }
    }

    StyledText {
        visible: root.saved !== ""
        Layout.maximumWidth: root.maxWidth
        wrapMode: Text.Wrap
        text: root.saved
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: root.subColor
    }
}
