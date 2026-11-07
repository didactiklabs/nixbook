import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.iconPicker

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property bool showIconPickerDialog: false

    readonly property bool sidebarOpen: GlobalStates.sidebarRightOpen

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    Connections {
        target: GlobalStates
        function onRequestBluetoothDialog() {
            if (!BluetoothStatus.available) return;
            root.showBluetoothDialog = true;
            GlobalStates.sidebarRightOpen = true;
        }

        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            }
        }
    }

    Process {
        id: fileChooser
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp"]
        
        stdout: StdioCollector {
            id: fileChooserOutput
        }
        
        onExited: (code) => {
            if (code === 0) {
                const path = fileChooserOutput.text.trim()
                if (path !== "") {
                    Config.options.sidebar.bannerImage = path
                }
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
        visible: !Persona.shapes // PersonaFrame draws its own hard shadow
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.gapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.gapsOut * 2
        // Persona style: the slanted comic-panel frame (same as the popups)
        // replaces the rounded body.
        color: Persona.shapes ? "transparent" : Appearance.colors.colLayer0
        border.width: Persona.shapes ? 0 : 1
        border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.8)
        radius: Appearance.rounding.screenRounding - Appearance.sizes.gapsOut + 5

        PersonaFrame {
            visible: Persona.shapes
            anchors.fill: parent
            z: -1
            color: Appearance.colors.colLayer0
            maxLean: 10
        }
        // Background art without the frame (shapes off, art on)
        PersonaTexture {
            visible: Persona.halftone && !Persona.shapes
            anchors.fill: parent
            anchors.margins: parent.border.width
            opacity: 0.55
        }
        // Chiikawa theme: stars and hearts, the character in the corner
        ChiikawaDecor {
            anchors.fill: parent
            anchors.margins: parent.border.width
        }
        // Ghibli theme: leaves, paper birds or fireflies, the spirit in the corner
        GhibliDecor {
            anchors.fill: parent
            anchors.margins: parent.border.width
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SidebarHeader {
                Layout.fillWidth: true
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            Loader {
                id: slidersLoader
                Layout.fillWidth: true
                visible: active
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders {}
            }

            MediaSourceSelector {
                Layout.fillWidth: true
                visible: shouldShow && root.activePlayer !== null && Config.options.sidebar.mediaPlayer
            }

            Loader {
                // Built on first open, then kept (its timers/visualizer idle
                // while the sidebar is hidden) instead of rebuilt on every open.
                property bool builtOnce: false
                onActiveChanged: if (active) builtOnce = true
                active: root.activePlayer !== null && Config.options.sidebar.mediaPlayer
                    && (GlobalStates.sidebarRightOpen || builtOnce)
                visible: active
                Layout.fillWidth: true
                Layout.topMargin: -10
                Layout.bottomMargin: -10
                Layout.leftMargin: -10
                Layout.rightMargin: -10
                sourceComponent: Player {
                    id: sidebarPlayer
                    player: root.activePlayer
                    // Hidden (sidebar closed): no copy of every cava frame.
                    visualizerPoints: ObjectUtils.shown(sidebarPlayer) ? GlobalStates.visualizerPoints : []
                    implicitHeight: 160
                    radius: Appearance.rounding.normal
                }
            }

            SidebarTabs {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: BluetoothStatus.discoveryWanted = shown
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showIconPickerDialog"
        dialog: IconPickerDialog {}
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (toggleDialogLoader.item && !toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true; }
            function onOpenAudioInputDialog() { root.showAudioInputDialog = true; }
            function onOpenBluetoothDialog() { root.showBluetoothDialog = true; }
            function onOpenNightLightDialog() { root.showNightLightDialog = true; }
            function onOpenWifiDialog() { root.showWifiDialog = true; }
        }
    }

    // Who and how long up, with the system buttons. With the banner on, the
    // wallpaper (or the chosen image) runs behind it: click to choose an
    // image, right click to go back to the wallpaper.
    component SidebarHeader: Item {
        id: header
        readonly property bool banner: Config.options.sidebar.banner
        implicitHeight: 64

        ClippingRectangle {
            anchors.fill: parent
            visible: header.banner
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            StyledImage {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: Config.options.sidebar.bannerImage !== ""
                    ? Config.options.sidebar.bannerImage
                    : Wallpapers.isVideo(Config.options.background.wallpaperPath)
                        ? Config.options.background.thumbnailPath
                        : Config.options.background.wallpaperPath
                cache: false
                antialiasing: true
                sourceSize.width: width * 2
            }
            // Keeps the text and buttons readable over any picture.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: ColorUtils.applyAlpha(Appearance.colors.colLayer1Base, 0.92) }
                    GradientStop { position: 0.55; color: ColorUtils.applyAlpha(Appearance.colors.colLayer1Base, 0.62) }
                    GradientStop { position: 1; color: ColorUtils.applyAlpha(Appearance.colors.colLayer1Base, 0.78) }
                }
            }
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (event) => {
                    if (event.button === Qt.LeftButton) {
                        fileChooser.running = true
                        GlobalStates.sidebarRightOpen = false
                    } else if (event.button === Qt.RightButton) {
                        Config.options.sidebar.bannerImage = ""
                    }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 10

            ClippingRectangle {
                visible: header.banner
                implicitWidth: 40
                implicitHeight: 40
                radius: width / 2
                color: Appearance.colors.colPrimaryContainer

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: UserAvatar.source // AccountsService account picture (services/UserAvatar.qml)
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    fillMode: Image.PreserveAspectCrop
                    visible: status !== Image.Error
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "account_circle"
                    iconSize: 28
                    color: Appearance.colors.colOnPrimaryContainer
                    visible: avatarImage.status === Image.Error
                }
            }

            Item {
                visible: !header.banner
                implicitWidth: 28
                implicitHeight: 28

                CustomIcon {
                    anchors.fill: parent
                    source: Config.options.custom.distroIcon || SystemInfo.distroIcon
                    colorize: Config.options.custom.colorizeIcon
                    color: Appearance.colors.colOnLayer0
                }
                MouseArea {
                    hoverEnabled: true
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showIconPickerDialog = true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName) + "@" + SystemInfo.hostname
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            SystemButtons {
                color: "transparent"
            }
        }
    }

    // Edit toggles, reload, settings and session.
    component SystemButtons: ButtonGroup {
        padding: 4

        QuickToggleButton {
            toggled: root.editMode
            visible: Config.options.sidebar.quickToggles.style === "android"
            buttonIcon: "edit"
            onClicked: root.editMode = !root.editMode
            StyledToolTip {
                text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
            }
        }
        QuickToggleButton {
            toggled: false
            buttonIcon: "restart_alt"
            onClicked: {
                Quickshell.execDetached(["niri", "msg", "action", "reload-config"]);
                Quickshell.reload(true);
            }
            StyledToolTip {
                text: Translation.tr("Reload Niri & Quickshell")
            }
        }
        QuickToggleButton {
            toggled: GlobalStates.settingsOpen
            buttonIcon: "settings"
            onClicked: {
                GlobalStates.sidebarRightOpen = false;
                GlobalStates.settingsOpen = !GlobalStates.settingsOpen
            }
            StyledToolTip {
                text: Translation.tr("Settings")
            }
        }
        QuickToggleButton {
            toggled: false
            buttonIcon: "mode_off_on"
            onClicked: GlobalStates.sessionOpen = true
            StyledToolTip {
                text: Translation.tr("Session")
            }
        }
    }
}
