pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * A song into one of your YouTube Music playlists (services/YouTubeMusic.qml,
 * `nixbook-ytmusic add`): your playlists as chips (Liked Music likes it), and
 * a new private playlist by name. `resolve(then)` gives the song's YouTube
 * Music id (a friend's song listening along may need looking for first);
 * `closed` when it is done or cancelled. Used by the Mesh's listen-along card
 * and the YouTube Music tab.
 */
ColumnLayout {
    id: root

    // then(videoId): "" when the song isn't on YouTube Music.
    property var resolve: then => then("")
    property string songTitle: ""
    property color textColor: Appearance.colors.colOnLayer2
    signal closed

    spacing: 6

    // "" | "finding" | "adding": one thing at a time.
    property string busy: ""
    property string message: ""
    property bool failed: false
    property bool naming: false

    function reset() {
        root.busy = "";
        root.message = "";
        root.failed = false;
        root.naming = false;
        newName.text = "";
    }
    onVisibleChanged: if (root.visible) {
        root.reset();
        YouTubeMusic.refreshPlaylists(false);
    }

    function _withSong(act) {
        root.busy = "finding";
        root.message = "";
        root.resolve(id => {
            if (id === "") {
                root.busy = "";
                root.failed = true;
                root.message = Translation.tr("This song isn't on YouTube Music");
                return;
            }
            root.busy = "adding";
            act(id);
        });
    }
    function _answer(ok, answer, title) {
        root.busy = "";
        root.failed = !ok;
        if (!ok) root.message = answer?.error ?? Translation.tr("YouTube Music didn't add it");
        else if (answer?.status === "already") root.message = Translation.tr("Already in %1").arg(title);
        else root.message = Translation.tr("Added to %1").arg(title);
        if (ok) closeTimer.restart();
    }
    function add(p) {
        const title = p.id === "LM" ? Translation.tr("Liked Music") : p.title;
        root._withSong(id => YouTubeMusic.addToPlaylist(p.id, id, (ok, answer) => root._answer(ok, answer, title)));
    }
    function create() {
        const title = newName.text.trim();
        if (title === "") return;
        root._withSong(id => YouTubeMusic.createPlaylist(title, id, (ok, answer) => root._answer(ok, answer, title)));
    }
    Timer {
        id: closeTimer
        interval: 1800
        onTriggered: root.closed()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.textColor
            text: root.songTitle !== "" ? Translation.tr("Add “%1” to").arg(root.songTitle) : Translation.tr("Add to a playlist")
        }
        RippleButton {
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            onClicked: root.closed()
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "close"
                iconSize: Appearance.font.pixelSize.small
                color: root.textColor
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !YouTubeMusic.signedIn
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Translation.tr("Sign in to YouTube Music first: Settings > Apps & accounts > YouTube Music")
    }

    Flow {
        Layout.fillWidth: true
        visible: YouTubeMusic.signedIn
        spacing: 4
        Repeater {
            model: YouTubeMusic.ownPlaylists
            delegate: RippleButton {
                id: chip
                required property var modelData
                enabled: root.busy === ""
                implicitHeight: 30
                implicitWidth: chipRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.add(chip.modelData)
                contentItem: RowLayout {
                    id: chipRow
                    spacing: 4
                    MaterialSymbol {
                        text: chip.modelData.id === "LM" ? "thumb_up" : "queue_music"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.maximumWidth: 180
                        elide: Text.ElideRight
                        text: chip.modelData.id === "LM" ? Translation.tr("Liked Music") : chip.modelData.title
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
        RippleButton {
            id: newChip
            visible: !root.naming
            enabled: root.busy === ""
            implicitHeight: 30
            implicitWidth: newRow.implicitWidth + 20
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            onClicked: {
                root.naming = true;
                newName.forceActiveFocus();
            }
            contentItem: RowLayout {
                id: newRow
                spacing: 4
                MaterialSymbol {
                    text: "add"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    text: Translation.tr("New playlist")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer3
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: YouTubeMusic.signedIn && YouTubeMusic.ownPlaylists.length === 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: YouTubeMusic.playlistsLoading ? Translation.tr("Reading your playlists…") : YouTubeMusic.playlistsError
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.naming
        spacing: 6
        MaterialTextField {
            id: newName
            Layout.fillWidth: true
            placeholderText: Translation.tr("The new playlist's name")
            onAccepted: root.create()
            Keys.onEscapePressed: root.naming = false
        }
        RippleButtonWithIcon {
            enabled: root.busy === "" && newName.text.trim() !== ""
            materialIcon: "playlist_add"
            mainText: Translation.tr("Create")
            onClicked: root.create()
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.busy !== "" || root.message !== ""
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
        text: root.busy === "finding" ? Translation.tr("Looking for it on YouTube Music…")
            : root.busy === "adding" ? Translation.tr("Adding…") : root.message
    }
}
