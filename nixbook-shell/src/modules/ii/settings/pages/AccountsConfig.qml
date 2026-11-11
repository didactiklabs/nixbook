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
    }
}
