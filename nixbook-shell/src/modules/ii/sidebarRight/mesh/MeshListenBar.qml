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
 * (Leave), and why it stopped.
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

    function trackText(t) {
        return t ? [t.title, t.artist].filter(x => x).join(" — ") : "";
    }
    function statusText() {
        const svc = MeshListen.serviceName(MeshListen.localService(root.session?.service ?? ""));
        switch (MeshListen.followStatus) {
        case "synced": return Translation.tr("In sync, in %1").arg(svc);
        case "opening": return root.video ? Translation.tr("Opening it in mpv…") : Translation.tr("Opening the song in %1…").arg(svc);
        case "starting": return Translation.tr("Starting %1…").arg(svc);
        case "matching": return Translation.tr("Looking for it on YouTube Music…");
        case "nomatch": return Translation.tr("Not found on YouTube Music: waiting for the next song");
        case "search": return Translation.tr("Spotify can't open YouTube Music songs: pick it in Spotify's search");
        case "noapp": return root.video ? Translation.tr("Set up Jellyfin (Settings > Services > Jellyfin) to watch along")
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
