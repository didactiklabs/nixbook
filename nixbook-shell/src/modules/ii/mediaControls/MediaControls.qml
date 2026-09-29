pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: {
        // A source picked in the selector shows just that player's card.
        if (!MprisController.autoSelect && MprisController.selectedPlayer)
            return [MprisController.selectedPlayer]
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return filterDuplicatePlayers(realPlayers)
        const filtered = realPlayers.filter(p =>
            (p.identity ?? "").toLowerCase().includes(preferred) ||
            (p.desktopEntry ?? "").toLowerCase().includes(preferred)
        )
        if (filtered.length === 0) return filterDuplicatePlayers(realPlayers)
        return filterDuplicatePlayers(filtered)
    }
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.gapsOut + 1

    readonly property string mediaPosition: {
        if (Config.options.bar.layouts.leftLayout.includes("media")) return "left"
        if (Config.options.bar.layouts.middleLayout.includes("media")) return "center"
        if (Config.options.bar.layouts.rightLayout.includes("media")) return "right"
        return "center"
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real gap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.gapsOut : 0
    readonly property bool cornerStyleReducesGap: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 2
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    // cava re-plans its FFT (FFTW "measure", hundreds of ms of CPU) on every
    // start, and it used to start/stop with each sidebar/media popup
    // open/close. Keep it running for a grace period after the last consumer
    // goes away, as long as something is playing.
    readonly property bool cavaWanted: (GlobalStates.mediaControlsOpen ||
            GlobalStates.sidebarRightOpen ||
            (GlobalStates.sidebarLeftOpen && !GlobalStates.mediaLyricsVisible) ||
            GlobalStates.equalizerOpen ||
            Config.options.bar.layouts.leftLayout.includes("visualizer") ||
            Config.options.bar.layouts.middleLayout.includes("visualizer") ||
            (Config.options.bar.layouts.middleLayout.includes("dynamicIsland") &&
                (Config.options.bar.dynamicIsland.visualizerStyle === "wave" ||
                (Config.options.bar.dynamicIsland.visualizerStyle === "dots" && !Config.options.bar.dynamicIsland.showMediaControls))) ||
            Config.options.bar.layouts.rightLayout.includes("visualizer") ||
            GlobalStates.desktopVisualizersAnimating > 0)
    readonly property bool playing: MprisController.activePlayer?.isPlaying ?? false
    onCavaWantedChanged: if (!cavaWanted) cavaGrace.restart()
    Timer {
        id: cavaGrace
        interval: 60000
    }
    Process {
        id: cavaProc
        running: root.playing && (root.cavaWanted || cavaGrace.running)
        onRunningChanged: {
            if (!cavaProc.running) {
                GlobalStates.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                GlobalStates.visualizerPoints = points;
            }
        }
    }

    // Built on first open, then only shown/hidden: the layer surface still
    // maps/unmaps exactly as before, but the player list (and its artwork)
    // survives between openings instead of being rebuilt every time.
    property bool mediaEverOpened: false
    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen)
                root.mediaEverOpened = true;
        }
    }

    Loader {
        id: mediaControlsLoader
        active: root.mediaEverOpened || Preloader.media
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            // Stays mapped once built (hiding destroys the surface and Qt
            // rebuilt its GL context on every open). Closed = no input region,
            // transparent content; our own fade replaces the map/unmap.
            readonly property bool shown: GlobalStates.mediaControlsOpen
            visible: true
            function followFocusedScreen() {
                const s = Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name);
                if (s && panelWindow.screen !== s) panelWindow.screen = s;
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"
            // Overlay so it stays above GlobalFocusGrab's click catcher (Top).
            WlrLayershell.layer: WlrLayer.Overlay
            // Takes the keyboard while open (the equalizer, opened from here,
            // takes it over while it is shown); Escape closes.
            WlrLayershell.keyboardFocus: panelWindow.shown && !GlobalStates.equalizerOpen
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Item {
                focus: true
                Keys.onEscapePressed: GlobalStates.mediaControlsOpen = false
            }

            anchors {
                top: true
                left: true
            }
            margins {
                top: {
                    if (root.barEdge === "top") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap -6 : root.gap)
                    if (root.barEdge === "bottom") return panelWindow.screen.height - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - playerColumnLayout.implicitHeight
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.height - playerColumnLayout.implicitHeight - root.gap
                    return (panelWindow.screen.height - playerColumnLayout.implicitHeight) / 2
                }
                left: {
                    if (root.barEdge === "left") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap : root.gap)
                    if (root.barEdge === "right") return panelWindow.screen.width - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - root.widgetWidth
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.width - root.widgetWidth - root.gap
                    return (panelWindow.screen.width - root.widgetWidth) / 2
                }
            }

            mask: panelWindow.shown ? openMask : noInput
            Region { id: openMask; item: playerColumnLayout }
            Region { id: noInput }

            Component.onCompleted: {
                panelWindow.followFocusedScreen();
                // May be built hidden by the Preloader.
                if (!Config.options.bar.media.alwaysVisible && panelWindow.shown)
                    GlobalFocusGrab.addDismissable(panelWindow, "media");
            }
            // The window outlives a single opening now, so a hidden popup must
            // not stay in the grab's dismissable list (it would leave the grab
            // armed with nothing on screen).
            onShownChanged: {
                if (panelWindow.shown) panelWindow.followFocusedScreen();
                if (Config.options.bar.media.alwaysVisible)
                    return;
                if (panelWindow.shown)
                    GlobalFocusGrab.addDismissable(panelWindow, "media");
                else
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Component.onDestruction: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (GlobalFocusGrab.spares(panelWindow)) return;
                    if (!Config.options.bar.media.alwaysVisible)
                        GlobalStates.mediaControlsOpen = false;
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                opacity: panelWindow.shown ? 1 : (Preloader.prerender ? 0.004 : 0)
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                }
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                // Media source picker (Spotify / YouTube Music / browser / phone…)
                Item {
                    Layout.fillWidth: true
                    visible: sourceSelector.shouldShow
                    implicitHeight: selectorCard.implicitHeight + Appearance.sizes.elevationMargin * 2
                    StyledRectangularShadow {
                        target: selectorCard
                        visible: !Persona.shapes
                    }
                    Rectangle {
                        id: selectorCard
                        anchors {
                            fill: parent
                            margins: Appearance.sizes.elevationMargin
                        }
                        implicitHeight: sourceSelector.implicitHeight + 20
                        radius: root.popupRounding
                        color: Persona.shapes ? "transparent" : Appearance.colors.colLayer0
                        border.width: Persona.shapes ? 0 : 1
                        border.color: Appearance.colors.colLayer0Border
                        PersonaFrame {
                            visible: Persona.shapes
                            anchors.fill: parent
                            z: -1
                            color: Appearance.colors.colLayer0
                        }
                        MediaSourceSelector {
                            id: sourceSelector
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: 10
                            }
                        }
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: Player {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: GlobalStates.visualizerPoints  
                        implicitWidth: root.widgetWidth
                        implicitHeight: showLyrics ? 290 : Appearance.sizes.mediaControlsHeight
                        radius: root.popupRounding
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.gapsOut
                    Layout.rightMargin: Appearance.sizes.gapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                        visible: !Persona.shapes
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Persona.shapes ? "transparent" : Appearance.colors.colLayer0
                        PersonaFrame {
                            visible: Persona.shapes
                            anchors.fill: parent
                            z: -1
                            color: Appearance.colors.colLayer0
                        }
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }
}
