pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris

/**
 * Media source picker shared by every media widget/panel: "Auto" + one chip per
 * MPRIS player (desktop apps like Spotify / YouTube Music, browser tabs, and
 * phone players KDE Connect exposes). Picking one makes it the player the bar,
 * media keys, sidebars, lock screen and equalizer follow (MprisController
 * .selectPlayer, persisted); "Auto" follows whatever is playing.
 *
 * Hidden when there is at most one player and Auto is selected. `compact`
 * drops the labels (icons + tooltip).
 */
Flow {
    id: root
    property bool compact: false
    property color colChip: Appearance.colors.colLayer2
    property color colChipSelected: Appearance.colors.colPrimaryContainer
    property color colText: Appearance.colors.colOnLayer2
    property color colTextSelected: Appearance.colors.colOnPrimaryContainer

    readonly property var players: MprisController.players
    // Bind wrappers to this, not to `visible` (effective visibility is false
    // whenever an ancestor is hidden, which would latch a wrapper hidden).
    readonly property bool shouldShow: players.length > 1 || !MprisController.autoSelect
    visible: shouldShow
    spacing: 6

    // Phone players only show up once KDE Connect has fetched the phone's
    // player list; ask when a selector becomes visible.
    onVisibleChanged: if (visible) KdeConnect.requestMediaPlayers()
    Component.onCompleted: KdeConnect.requestMediaPlayers()

    component Chip: RippleButton {
        id: chip
        property bool selected: false
        property string label: ""
        property string systemIcon: ""
        property string symbol: "music_note"
        property bool playing: false
        property string tip: label

        implicitHeight: 30
        implicitWidth: chipRow.implicitWidth + 20
        buttonRadius: Appearance.rounding.full
        colBackground: chip.selected ? root.colChipSelected : root.colChip
        colBackgroundHover: chip.selected ? root.colChipSelected : Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: Item {}
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Item {
                implicitWidth: 18
                implicitHeight: 18
                IconImage {
                    anchors.fill: parent
                    visible: chip.systemIcon !== ""
                    source: chip.systemIcon !== "" ? Quickshell.iconPath(chip.systemIcon, "audio-x-generic") : ""
                    asynchronous: true
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: chip.systemIcon === ""
                    text: chip.symbol
                    iconSize: Appearance.font.pixelSize.normal
                    fill: chip.selected ? 1 : 0
                    color: chip.selected ? root.colTextSelected : root.colText
                }
            }
            StyledText {
                visible: !root.compact && chip.label !== ""
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: chip.selected ? root.colTextSelected : root.colText
                elide: Text.ElideRight
                Layout.maximumWidth: 140
            }
            MaterialSymbol {
                visible: chip.playing
                text: "graphic_eq"
                iconSize: Appearance.font.pixelSize.small
                color: chip.selected ? root.colTextSelected : Appearance.colors.colPrimary
                SequentialAnimation on opacity {
                    running: chip.playing && ObjectUtils.shown(chip)
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }
        StyledToolTip {
            text: chip.tip
        }
    }

    Chip {
        selected: MprisController.autoSelect
        label: Translation.tr("Auto")
        symbol: "auto_awesome"
        tip: Translation.tr("Follow whatever is playing")
        onClicked: MprisController.selectPlayer(null)
    }

    Repeater {
        model: root.players
        delegate: Chip {
            required property MprisPlayer modelData
            selected: !MprisController.autoSelect && MprisController.activePlayer === modelData
            // Same app twice (two browser windows, two mpv…): add the track.
            label: {
                const name = MprisController.playerName(modelData);
                const same = root.players.filter(p => MprisController.playerName(p) === name).length > 1;
                const title = StringUtils.cleanMusicTitle(modelData.trackTitle ?? "");
                return same && title ? `${name} · ${title}` : name;
            }
            systemIcon: MprisController.playerIcon(modelData)
            symbol: MprisController.playerSymbol(modelData)
            playing: modelData.isPlaying
            tip: {
                const title = modelData.trackTitle ?? "";
                const src = MprisController.playerSource(modelData);
                const where = src === "phone" ? Translation.tr("Phone") : src === "browser" ? Translation.tr("Browser") : Translation.tr("App");
                return `${MprisController.playerName(modelData)} (${where})${title ? " — " + title : ""}`;
            }
            onClicked: MprisController.selectPlayer(modelData)
        }
    }
}
