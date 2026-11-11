pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Listening together in a Mesh conversation (services/MeshListen.qml): what
 * you share (Stop), what someone shares (Listen along), how following goes
 * (Leave), and why it stopped; where the song is (the host's position,
 * as the listeners follow it).
 */
ColumnLayout {
    id: root
    required property string conv

    readonly property bool hosting: MeshListen.hostingIn(root.conv)
    readonly property var session: MeshListen.sessionIn(root.conv)
    readonly property bool followingThis: !!root.session && MeshListen.following === root.session.sid
    readonly property var track: root.hosting ? MeshListen.hostTrack : root.session?.track ?? null
    readonly property var listeners: root.hosting ? MeshListen.hosting.listeners : root.session?.listeners ?? {}
    // A film or an episode (Jellyfin): watching, not listening.
    readonly property bool video: (root.hosting ? MeshListen.hostService : root.session?.service ?? "") === "jellyfin"
    spacing: 4
    visible: root.hosting || !!root.session || MeshListen.notice !== ""

    // Where the shared song is: the host's last state, moved on by the time
    // since (as listeners follow it, MeshListen._followTick).
    readonly property var shared: root.hosting ? MeshListen._lastState : root.session
    readonly property real length: root.shared?.track?.length > 0 ? root.shared.track.length : 0
    property real now: Date.now()
    readonly property real position: MeshListen.positionOf(root.shared, root.now)
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.length > 0 && !!root.shared?.playing
        onTriggered: root.now = Date.now()
    }
    function clock(seconds) {
        const t = Math.floor(seconds);
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), sec = t % 60;
        const mm = h > 0 ? `${h}:${String(m).padStart(2, "0")}` : `${m}`;
        return `${mm}:${String(sec).padStart(2, "0")}`;
    }

    function trackText(t) {
        return t ? [t.title, t.artist].filter(x => x).join(" — ") : "";
    }
    function statusText() {
        const svc = MeshListen.serviceName(MeshListen.localService(root.session?.service ?? ""));
        switch (MeshListen.followStatus) {
        case "synced": return Translation.tr("In sync, in %1").arg(svc);
        case "opening": return root.video ? Translation.tr("Opening it in mpv…") : Translation.tr("Opening the song in %1…").arg(svc);
        case "starting": return Translation.tr("Starting %1…").arg(svc);
        case "next": return Translation.tr("Waiting for their next song…");
        case "matching": return Translation.tr("Looking for it on YouTube Music…");
        case "nomatch": return Translation.tr("Not found on YouTube Music: waiting for the next song");
        case "unavailable": return Translation.tr("This song doesn't play in your %1 (not available to your account or country): waiting for the next one").arg(svc);
        case "search": return Translation.tr("Spotify can't open YouTube Music songs: pick it in Spotify's search");
        case "noapp": return root.video ? Translation.tr("Set up Jellyfin (Settings > Apps & accounts > Jellyfin) to watch along")
            : Translation.tr("Install YouTube Music or Spotify to listen along");
        case "notonserver": return Translation.tr("It isn't on your Jellyfin server");
        case "jferror": return Translation.tr("Jellyfin couldn't play it: %1").arg(MeshListen.followError);
        default: return "";
        }
    }

    Rectangle {
        id: card
        Layout.fillWidth: true
        visible: root.hosting || !!root.session
        implicitHeight: row.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: root.followingThis || root.hosting ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
        readonly property color fg: root.followingThis || root.hosting ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10
            Item {
                implicitWidth: 40
                implicitHeight: 40
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.video ? "movie" : "headphones"
                        iconSize: 22
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                Image {
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: root.track?.art ?? ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 80
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: card.fg
                    opacity: 0.8
                    text: {
                        const host = root.session?.hostName || Mesh.nameOf(root.session?.host ?? "");
                        if (root.video)
                            return root.hosting ? Translation.tr("You're sharing what you watch")
                                : root.followingThis ? Translation.tr("Watching along with %1").arg(host)
                                : Translation.tr("%1 is sharing what they watch").arg(host);
                        return root.hosting ? Translation.tr("You're sharing your music")
                            : root.followingThis ? Translation.tr("Listening along with %1").arg(host)
                            : Translation.tr("%1 is sharing their music").arg(host);
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: card.fg
                    text: root.trackText(root.track) || (root.hosting
                        ? Translation.tr("Nothing is playing in %1: play something and it's shared").arg(MeshListen.serviceName(MeshListen.hostService))
                        : root.video ? Translation.tr("Waiting…") : Translation.tr("Waiting for a song…"))
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: card.fg
                    opacity: 0.8
                    text: {
                        const names = MeshListen.listenersOf(root.listeners);
                        const who = names.length === 0 ? (root.hosting ? (root.video ? Translation.tr("No one is watching yet") : Translation.tr("No one is listening yet")) : "")
                            : (root.video ? Translation.tr("Watching: %1") : Translation.tr("Listening: %1")).arg(names.join(", "));
                        const paused = root.session && !root.session.playing ? Translation.tr("Paused") : "";
                        return [root.followingThis ? root.statusText() : "", paused, who].filter(x => x).join(" · ");
                    }
                }
                // How far into the song (or the film) the host is.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: root.length > 0 && !!root.track
                    spacing: 6
                    StyledText {
                        text: root.clock(root.position)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: card.fg
                        opacity: 0.8
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.2)
                        Rectangle {
                            width: parent.width * (root.length > 0 ? root.position / root.length : 0)
                            height: parent.height
                            radius: 2
                            color: card.fg
                            Behavior on width {
                                enabled: root.visible
                                NumberAnimation { duration: 900; easing.type: Easing.Linear }
                            }
                        }
                    }
                    StyledText {
                        text: root.clock(root.length)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.features: { "tnum": 1 }
                        color: card.fg
                        opacity: 0.8
                    }
                }
            }
            // Their song into one of your YouTube Music playlists.
            RippleButton {
                visible: root.canAdd
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                toggled: root.adding
                onClicked: root.adding = !root.adding
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "playlist_add"
                    iconSize: Appearance.font.pixelSize.huge
                    color: card.fg
                }
                StyledToolTip {
                    text: Translation.tr("Add this song to one of your YouTube Music playlists")
                }
            }
            RippleButtonWithIcon {
                materialIcon: root.hosting ? "stop" : root.followingThis ? "logout" : root.video ? "movie" : "headphones"
                mainText: root.hosting ? Translation.tr("Stop") : root.followingThis ? Translation.tr("Leave")
                    : root.video ? Translation.tr("Watch along") : Translation.tr("Listen along")
                onClicked: {
                    if (root.hosting) MeshListen.stop();
                    else if (root.followingThis) MeshListen.leave("");
                    else MeshListen.join(root.session.sid);
                }
            }
        }
    }

    // Someone else's song (listening along or not), once signed in to
    // YouTube Music in the background: it goes to your own playlists.
    readonly property bool canAdd: !root.hosting && !root.video && !!root.session?.track && YouTubeMusic.signedIn
    property bool adding: false
    onCanAddChanged: if (!root.canAdd) root.adding = false
    YouTubeMusicAddToPlaylist {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        visible: root.adding && root.canAdd
        songTitle: root.trackText(root.track)
        // The song shown when it is picked: a Spotify one looked for there.
        resolve: then => MeshListen.youtubeIdOf(root.session, then)
        onClosed: root.adding = false
    }

    // Calling while listening together: the music kept out of the microphone.
    RippleButtonWithIcon {
        visible: EchoCancel.available && (root.hosting || root.followingThis)
        buttonRadius: Appearance.rounding.full
        toggled: EchoCancel.active
        enabled: !EchoCancel.busy
        materialIcon: EchoCancel.active ? "noise_aware" : "noise_control_off"
        mainText: EchoCancel.active ? Translation.tr("Echo cancellation on") : Translation.tr("Calling too? Echo cancellation")
        onClicked: EchoCancel.toggle()
        StyledToolTip {
            text: Translation.tr("Keeps what plays here out of your microphone, so the people you're calling don't hear the music twice")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: MeshListen.notice !== ""
        spacing: 6
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: MeshListen.notice
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RippleButton {
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            onClicked: MeshListen.notice = ""
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "close"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }
}
