import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Settings > Apps & accounts: the services the shell signs in to (Google
// Keep, Jellyfin, YouTube Music; from the General and Services pages).
ContentPage {
    id: page
    forceWidth: true

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }
    
    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "cloud_sync"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Google Keep")
            GroupedList {
                ConfigSwitch {
                    configKey: "keep.enable";
                    enabled: !nixManaged;
                    buttonIcon: "sync"
                    text: Translation.tr("Sync the notes with Google Keep")
                    checked: Config.options.keep.enable
                    onCheckedChanged: {
                        Config.options.keep.enable = checked;
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        configKey: "keep.refreshMinutes";
                        enabled: !nixManaged;
                        icon: "timer"
                        text: Translation.tr("Every")
                        value: Config.options.keep.refreshMinutes
                        from: 5
                        to: 240
                        stepSize: 5
                        onValueChanged: {
                            Config.options.keep.refreshMinutes = value;
                        }
                    }
                }
                ConfigSwitch {
                    configKey: "keep.push";
                    enabled: !nixManaged;
                    buttonIcon: "north_east"
                    text: Translation.tr("Send the shell's new notes to Keep")
                    checked: Config.options.keep.push
                    onCheckedChanged: {
                        Config.options.keep.push = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "keep.pull";
                    enabled: !nixManaged;
                    buttonIcon: "south_west"
                    text: Translation.tr("Bring Keep's new notes in")
                    checked: Config.options.keep.pull
                    onCheckedChanged: {
                        Config.options.keep.pull = checked;
                    }
                }
            }
        }

        // Jellyfin on this computer (services/Jellyfin.qml): a plain service,
        // used by watching along in the Mesh and by DAI when it is on.
        ContentSection {
            icon: "movie"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Jellyfin")
            shown: Jellyfin.available

            JellyfinAccount {
                Layout.fillWidth: true
            }

            // services/Jellyfin.qml writes it into the player's settings.
            ConfigSpinBox {
                configKey: "ai.jellyfin.maxBitrateMbps"
                enabled: !nixManaged
                icon: "speed"
                text: Translation.tr("Streaming limit away from home, in Mbit/s (0: none, the files played as they are)")
                value: Config.options.ai.jellyfin.maxBitrateMbps
                from: 0
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.ai.jellyfin.maxBitrateMbps = value
                StyledToolTip {
                    text: Translation.tr("The most this computer's player streams from a Jellyfin server that isn't on your local network (over a VPN, behind a reverse proxy); more is transcoded by the server. The player restarts when it changes.")
                }
            }
        }

        // YouTube Music in the background (services/YouTubeMusic.qml): no AI,
        // signed in with a browser's YouTube session; Last.fm scrobbling.
        ContentSection {
            icon: "queue_music"
            shape: MaterialShape.Shape.Cookie4Sided
            title: Translation.tr("YouTube Music")

            YouTubeMusicAccount {
                Layout.fillWidth: true
            }
        }

        // The quality YouTube videos start at in mpv (media.videoQuality,
        // which the player's quality script reads; its own menu changes it
        // for the video playing).
        ContentSection {
            icon: "high_quality"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("YouTube videos")
            shown: Config.options.sidebar.youtubeTab || YouTubeMusic.linksAvailable

            GroupedList {
                ConfigSelectionArray {
                    configKey: "media.videoQuality";
                    enabled: !nixManaged;
                    text: Translation.tr("Quality videos start at")
                    icon: "high_quality"
                    currentValue: Config.options.media.videoQuality
                    onSelected: newValue => {
                        Config.options.media.videoQuality = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Best"), value: "best" },
                        { displayName: "2160p", value: "2160" },
                        { displayName: "1440p", value: "1440" },
                        { displayName: "1080p", value: "1080" },
                        { displayName: "720p", value: "720" },
                        { displayName: "480p", value: "480" },
                        { displayName: "360p", value: "360" }
                    ]
                }
            }
        }

        // Links to the Jellyfin server set up here play in mpv instead of
        // opening its web page (media.jellyfinLinks), where something
        // brings links here and Jellyfin is signed in.
        ContentSection {
            icon: "movie"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Jellyfin links")
            shown: YouTubeMusic.linksAvailable && Jellyfin.available

            GroupedList {
                ConfigSwitch {
                    configKey: "media.jellyfinLinks.enable";
                    enabled: !nixManaged;
                    buttonIcon: "open_in_new"
                    text: Translation.tr("Play links to your Jellyfin server's films and episodes in mpv, not the browser")
                    checked: Config.options.media.jellyfinLinks.enable
                    onCheckedChanged: {
                        Config.options.media.jellyfinLinks.enable = checked;
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Jellyfin.ready
                        ? Translation.tr("Links from any app, and links opened in Zen from another site. Browsing inside Jellyfin's own web page stays in the browser.")
                        : Translation.tr("Sign in to Jellyfin above first: the links are the ones of that server.")
                }
            }
        }

        // YouTube links opened by the shell instead of the browser, on the
        // whole machine (YouTubeMusic.openLink; media.youtubeLinks, also
        // settable in Nix), shown where something brings the links here
        // (Zen's extension, the link router: YouTubeMusic.linksAvailable).
        // Off, or a kind off: those links open in the browser or app as before.
        ContentSection {
            icon: "link"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("YouTube links")
            shown: YouTubeMusic.linksAvailable

            GroupedList {
                ConfigSwitch {
                    configKey: "media.youtubeLinks.enable";
                    enabled: !nixManaged;
                    buttonIcon: "open_in_new"
                    text: Translation.tr("Open YouTube links here instead of the browser, from every app")
                    checked: Config.options.media.youtubeLinks.enable
                    onCheckedChanged: {
                        Config.options.media.youtubeLinks.enable = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "media.youtubeLinks.videos";
                    enabled: !nixManaged && Config.options.media.youtubeLinks.enable
                    buttonIcon: "smart_display"
                    text: Translation.tr("Play YouTube video links in mpv, not the browser")
                    checked: Config.options.media.youtubeLinks.videos
                    onCheckedChanged: {
                        Config.options.media.youtubeLinks.videos = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "media.youtubeLinks.music";
                    enabled: !nixManaged && Config.options.media.youtubeLinks.enable
                    buttonIcon: "queue_music"
                    text: Translation.tr("Play YouTube Music song and playlist links in the background player")
                    checked: Config.options.media.youtubeLinks.music
                    onCheckedChanged: {
                        Config.options.media.youtubeLinks.music = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "media.youtubeLinks.openPanel";
                    enabled: !nixManaged && Config.options.media.youtubeLinks.enable && Config.options.media.youtubeLinks.music
                    buttonIcon: "right_panel_open"
                    text: Translation.tr("Open the right panel on the YouTube Music tab when one plays")
                    checked: Config.options.media.youtubeLinks.openPanel
                    onCheckedChanged: {
                        Config.options.media.youtubeLinks.openPanel = checked;
                    }
                }
            }
        }
    }
}
