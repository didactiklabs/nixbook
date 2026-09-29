pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    required property MprisPlayer player
    required property QtObject blendedColors
    required property string displayedArtFilePath
    required property real radius
    signal toggleLyrics()

    component TrackChangeButton: RippleButton {
        implicitWidth: 24
        implicitHeight: 24
        property var iconName
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.blendedColors.colOnSecondaryContainer
            text: iconName
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 13
        spacing: 15

        Rectangle {
            id: artBackground
            Layout.fillHeight: true
            implicitWidth: height
            radius: Appearance.rounding.verysmall
            color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artBackground.width
                    height: artBackground.height
                    radius: artBackground.radius + 6
                }
            }

            StyledImage {
                id: mediaArt
                property int size: parent.height
                anchors.fill: parent
                source: root.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                width: size
                height: size
                sourceSize.width: size
                sourceSize.height: size
            }

            HoverHandler {
                id: artHover
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: artHover.hovered ? 0.6 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animationCurves.expressiveFastSpatialDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.normal
                color: root.blendedColors.colOnLayer0
                text: MprisController.playerMuted(root.player) ? "volume_off" : (MprisController.playerVolume(root.player) < 0.5 ? "volume_down" : "volume_up")
                opacity: artHover.hovered ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animationCurves.expressiveFastSpatialDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }
            }

            MaterialDial {
                anchors.fill: parent
                anchors.margins: 14
                colPrimary: root.blendedColors.colPrimary
                colSecondary: root.blendedColors.colSecondaryContainer
                // Via MprisController: the player's PipeWire stream when found
                // (Chromium/Electron players ignore MPRIS volume writes).
                value: MprisController.playerVolume(root.player)
                waveAmplitude: 3.2 * MprisController.playerVolume(root.player)
                opacity: artHover.hovered ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animationCurves.expressiveFastSpatialDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }

                onMoved: MprisController.setPlayerVolume(root.player, value)
            }
        }

        ColumnLayout {
            Layout.fillHeight: true
            spacing: 2

            StyledText {
                id: trackTitle
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                color: root.blendedColors.colOnLayer0
                elide: Text.ElideRight
                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            StyledText {
                id: trackArtist
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.blendedColors.colSubtext
                elide: Text.ElideRight
                text: root.player?.trackArtist
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            Item { Layout.fillHeight: true }

            Item {
                Layout.fillWidth: true
                implicitHeight: trackTime.implicitHeight + sliderRow.implicitHeight

                StyledText {
                    id: trackTime
                    anchors.bottom: sliderRow.top
                    anchors.bottomMargin: 5
                    anchors.left: parent.left
                    anchors.right: extraActions.left
                    anchors.rightMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                    font.features: { "tnum": 1 }
                    text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
                }

                RowLayout {
                    id: sliderRow
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }

                    TrackChangeButton {
                        iconName: "skip_previous"
                        downAction: () => root.player?.previous()
                    }

                    Item {
                        id: progressBarContainer
                        Layout.fillWidth: true
                        implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                        Loader {
                            id: sliderLoader
                            anchors.fill: parent
                            active: root.player?.canSeek ?? false
                            sourceComponent: StyledSlider {
                                configuration: StyledSlider.Configuration.Wavy
                                // The wave moves while playing only (as the progress
                                // bar below): it repainted a Canvas every frame even
                                // when paused, keeping the sidebar rendering at 60 fps.
                                animateWave: root.player?.isPlaying ?? false
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                handleColor: root.blendedColors.colPrimary
                                value: root.player?.position / root.player?.length
                                onMoved: root.player.position = value * root.player.length
                            }
                        }

                        Loader {
                            id: progressBarLoader
                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                right: parent.right
                            }
                            active: !(root.player?.canSeek ?? false)
                            sourceComponent: StyledProgressBar {
                                wavy: root.player?.isPlaying
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                value: root.player?.position / root.player?.length
                            }
                        }
                    }

                    TrackChangeButton {
                        iconName: "skip_next"
                        downAction: () => root.player?.next()
                    }

                    TrackChangeButton {
                        iconName: "lyrics"
                        visible: !GlobalStates.sidebarRightOpen
                        downAction: () => root.toggleLyrics()
                    }

                    TrackChangeButton {
                        iconName: "equalizer"
                        downAction: () => GlobalStates.equalizerOpen = !GlobalStates.equalizerOpen
                    }
                }

                // Extra actions: seek ±10 s, shuffle, repeat, bring the player's
                // window up. Each only when the player supports it.
                RowLayout {
                    id: extraActions
                    anchors.right: playPauseButton.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: playPauseButton.verticalCenter
                    spacing: 0

                    TrackChangeButton {
                        visible: root.player?.canSeek ?? false
                        iconName: "replay_10"
                        downAction: () => MprisController.seekBy(root.player, -10)
                    }
                    TrackChangeButton {
                        visible: root.player?.canSeek ?? false
                        iconName: "forward_10"
                        downAction: () => MprisController.seekBy(root.player, 10)
                    }
                    TrackChangeButton {
                        visible: root.player?.shuffleSupported ?? false
                        iconName: (root.player?.shuffle ?? false) ? "shuffle_on" : "shuffle"
                        downAction: () => MprisController.toggleShuffle(root.player)
                    }
                    TrackChangeButton {
                        visible: root.player?.loopSupported ?? false
                        iconName: MprisController.loopIcon(root.player)
                        downAction: () => MprisController.cycleLoop(root.player)
                    }
                    // Everything else this player supports (speed, stop, link,
                    // clipboard, up next, playlists, show/quit…)
                    TrackChangeButton {
                        id: moreActionsButton
                        iconName: "more_horiz"
                        downAction: () => actionsMenu.toggle()
                        MediaActionsMenu {
                            id: actionsMenu
                            anchorItem: moreActionsButton
                            player: root.player
                        }
                    }
                }

                RippleButton {
                    id: playPauseButton
                    anchors.right: parent.right
                    anchors.bottom: sliderRow.top
                    anchors.bottomMargin: 5
                    property real size: 44
                    implicitWidth: size
                    implicitHeight: size
                    downAction: () => root.player.togglePlaying()

                    buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal : size / 2
                    colBackground: root.player?.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.player?.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.player?.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive

                    contentItem: MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.huge
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.player?.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                        text: root.player?.isPlaying ? "pause" : "play_arrow"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }
}