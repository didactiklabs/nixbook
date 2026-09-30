import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

// Music recognition (services/SongRec.qml, songrec/Shazam) on the desktop:
// the last song found (cover, title, artist, Shazam and YouTube buttons),
// the two before it, and a Listen button. The header button switches
// between the desktop audio and the microphone.
AbstractBackgroundWidget {
    id: root
    configEntryName: "musicRecognition"
    hoverEnabled: true

    implicitWidth: 276
    implicitHeight: 252

    readonly property bool listening: SongRec.running
    readonly property bool fromMonitor: SongRec.monitorSource === SongRec.MonitorSource.Monitor
    readonly property var track: SongRec.recognizedTrack
    readonly property bool hasTrack: (track.title ?? "").length > 0
    readonly property var earlier: SongRec.history.slice(1, 3)
    // The last try found nothing (shown until the next one).
    readonly property bool noMatch: !listening && SongRec.failedAt > SongRec.recognizedAt

    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.listening
        loops: Animation.Infinite
        NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.pulse = 1
    }

    component IconButton: RippleButton {
        id: iconButton
        property string symbol
        property color colIcon: Appearance.colors.colOnPrimaryContainer
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: iconButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: iconButton.colIcon
        }
    }

    WidgetShadow {
        target: card
        visible: Config.options.background.widgets.shadow
    }
    WidgetOutline {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Appearance.colors.colWidgetCard
        radius: Appearance.rounding?.verylarge ?? 30

        FastBlurred {
            anchors.fill: parent
            blurSource: root.wallpaperItem
            cardRadius: card.radius
            tint: Appearance.colors.colLayer1
            tintOpacity: 0.55
            trackX: root.x
            trackY: root.y
            visible: Config.options.background.widgets.blurWidgets
        }

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: "music_cast"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Music recognition")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnPrimaryContainer
                }
                IconButton {
                    symbol: root.fromMonitor ? "speaker" : "mic"
                    releaseAction: () => SongRec.toggleMonitorSource()
                    StyledToolTip {
                        text: root.fromMonitor ? Translation.tr("Listening to: system sound (click for the microphone)")
                            : Translation.tr("Listening to: microphone (click for the system sound)")
                    }
                }
            }

            // The last song found
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: root.hasTrack

                Rectangle {
                    id: coverBox
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Appearance.rounding.normal
                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: coverBox.width
                            height: coverBox.height
                            radius: coverBox.radius
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        text: "album"
                        iconSize: 32
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                    }
                    StyledImage {
                        id: cover
                        anchors.fill: parent
                        source: root.track.cover ?? ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize { width: 128; height: 128 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.track.title ?? ""
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.track.subtitle ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                    }
                    RowLayout {
                        spacing: 2
                        IconButton {
                            symbol: "open_in_new"
                            releaseAction: () => SongRec.openShazam()
                            StyledToolTip { text: Translation.tr("Open on Shazam") }
                        }
                        IconButton {
                            symbol: "smart_display"
                            releaseAction: () => SongRec.openYouTube()
                            StyledToolTip { text: Translation.tr("Search on YouTube") }
                        }
                    }
                }
            }

            // Nothing found yet
            StyledText {
                Layout.fillWidth: true
                visible: !root.hasTrack
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.noMatch ? Translation.tr("No match: try again closer to the music")
                    : Translation.tr("Play some music, then press Listen")
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.8
            }

            // The songs before it
            Repeater {
                model: root.earlier
                delegate: RippleButton {
                    id: earlierRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 24
                    buttonRadius: Appearance.rounding.small
                    releaseAction: () => SongRec.openShazam(earlierRow.modelData)
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        spacing: 6
                        MaterialSymbol {
                            text: "history"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${earlierRow.modelData.title} – ${earlierRow.modelData.subtitle}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RippleButton {
                id: listenButton
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: root.listening ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
                colBackgroundHover: root.listening ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colPrimaryActive
                releaseAction: () => SongRec.toggleRunning()
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: root.listening ? "graphic_eq" : "music_note"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: root.listening ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                        opacity: root.pulse
                    }
                    StyledText {
                        text: root.listening ? Translation.tr("Listening… (stop)") : Translation.tr("Listen")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: root.listening ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }
    }
}
