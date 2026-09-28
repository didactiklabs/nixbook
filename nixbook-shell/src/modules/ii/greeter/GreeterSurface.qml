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
import Qt5Compat.GraphicalEffects

/**
 * The login screen (greeter.qml): the lock screen's look — the theme, its
 * palette and fonts, the wallpaper, a large clock — around a card with the
 * user (arrows to switch), the password (Enter logs in), PAM's cues
 * (security key, fingerprint) and the session to start; power buttons in the
 * corner. `primary`: the screen holding the keyboard.
 */
Item {
    id: root
    required property GreeterContext context
    property bool primary: true

    function focusField() {
        passwordBox.forceActiveFocus();
    }
    Component.onCompleted: if (root.primary) Qt.callLater(root.focusField)

    // ------------------------------------------------------------ background
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3background
    }
    Image {
        id: wall
        anchors.fill: parent
        source: Config.options.background.wallpaperPath ? `file://${FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)}` : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        sourceSize.width: root.width
        sourceSize.height: root.height
    }
    // Soft scrim so the clock and the card read on any wallpaper.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.55) }
            GradientStop { position: 0.45; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.85) }
            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35) }
        }
    }

    // ----------------------------------------------------------------- clock
    ColumnLayout {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: root.height * 0.1
        }
        spacing: 0
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")
            font.family: Appearance.font.family.title
            font.pixelSize: Math.min(128, root.height * 0.13)
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.locale().toString(clock.date, "dddd d MMMM")
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnLayer0
            opacity: 0.85
        }
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ------------------------------------------------------------------ card
    Rectangle {
        id: card
        visible: root.primary
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.height * 0.08
        width: Math.min(440, root.width - 48)
        height: cardColumn.implicitHeight + 48
        radius: Appearance.rounding.verylarge
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.08)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.6)

        StyledRectangularShadow {
            target: card
            z: -1
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 24
            }
            spacing: 14

            // Avatar
            ClippingRectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 96
                implicitHeight: 96
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimaryContainer
                StyledText {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: (root.context.user?.realName || root.context.user?.name || "?").charAt(0).toUpperCase()
                    font.family: Appearance.font.family.title
                    font.pixelSize: 44
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }
                Image {
                    id: avatar
                    anchors.fill: parent
                    source: root.context.user?.avatar ? `file://${root.context.user.avatar}` : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 192
                    sourceSize.height: 192
                    asynchronous: true
                }
            }

            // User (arrows: the other users)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                IconToolbarButton {
                    visible: root.context.users.length > 1
                    text: "chevron_left"
                    onClicked: { root.context.cycleUser(-1); root.focusField(); }
                }
                StyledText {
                    Layout.maximumWidth: card.width - 140
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.context.user?.realName || root.context.user?.name || ""
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                IconToolbarButton {
                    visible: root.context.users.length > 1
                    text: "chevron_right"
                    onClicked: { root.context.cycleUser(1); root.focusField(); }
                }
            }

            // Password
            Toolbar {
                id: passwordRow
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                enableShadow: false
                colBackground: Appearance.colors.colLayer1

                MaterialSymbol {
                    Layout.leftMargin: 10
                    text: root.context.waitingForKey ? "passkey" : "lock"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    color: root.context.waitingForKey ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                }
                ToolbarTextField {
                    id: passwordBox
                    Layout.fillWidth: true
                    placeholderText: root.context.waitingForKey ? Translation.tr("Touch your security key")
                        : root.context.failed ? Translation.tr("Incorrect password")
                        : root.context.pendingPrompt && root.context.message ? root.context.message
                        : Translation.tr("Password")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    echoMode: root.context.pendingPrompt && root.context.promptEcho ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    enabled: !root.context.busy || root.context.pendingPrompt
                    onTextChanged: {
                        root.context.currentText = text;
                        if (text.length > 0) root.context.failed = false;
                    }
                    onAccepted: root.context.login()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.context.currentText = "";
                            root.context.reset();
                            event.accepted = true;
                        }
                    }
                    ErrorShakeAnimation {
                        id: shake
                        target: passwordBox
                    }
                    Connections {
                        target: root.context
                        function onCurrentTextChanged() {
                            if (passwordBox.text !== root.context.currentText)
                                passwordBox.text = root.context.currentText;
                        }
                        function onFailure() {
                            shake.restart();
                            root.focusField();
                        }
                    }
                }
                ToolbarButton {
                    id: goButton
                    implicitWidth: height
                    toggled: true
                    enabled: !root.context.busy || root.context.pendingPrompt
                    colBackgroundToggled: Appearance.colors.colPrimary
                    onClicked: root.context.login()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.context.busy && !root.context.pendingPrompt ? "hourglass_top" : "arrow_forward"
                        iconSize: 24
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }

            // PAM's info (security key, fingerprint, errors from greetd)
            StyledText {
                Layout.fillWidth: true
                visible: text !== "" && !root.context.pendingPrompt
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.context.message
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.context.waitingForKey ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            // Session
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: root.context.sessions.length > 0
                spacing: 4
                IconToolbarButton {
                    visible: root.context.sessions.length > 1
                    text: "chevron_left"
                    onClicked: { root.context.cycleSession(-1); root.focusField(); }
                }
                RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "desktop_windows"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: root.context.session?.name ?? ""
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
                IconToolbarButton {
                    visible: root.context.sessions.length > 1
                    text: "chevron_right"
                    onClicked: { root.context.cycleSession(1); root.focusField(); }
                }
            }
        }
    }

    // The Chiikawa theme's character, beside the card.
    ChiikawaMascot {
        visible: root.primary && Chiikawa.mascot
        anchors {
            left: card.right
            bottom: card.bottom
            leftMargin: -30
            bottomMargin: -10
        }
        width: 150
        height: 150
        hopOnHover: true
    }

    // ----------------------------------------------------------------- power
    Toolbar {
        visible: root.primary
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 20
        }
        IconToolbarButton {
            text: "dark_mode"
            onClicked: root.context.suspend()
            StyledToolTip { text: Translation.tr("Suspend") }
        }
        IconToolbarButton {
            text: "restart_alt"
            onClicked: root.context.reboot()
            StyledToolTip { text: Translation.tr("Reboot") }
        }
        IconToolbarButton {
            text: "power_settings_new"
            onClicked: root.context.poweroff()
            StyledToolTip { text: Translation.tr("Power off") }
        }
    }
}
