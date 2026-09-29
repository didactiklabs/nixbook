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

/**
 * The login screen (greeter.qml): the wallpaper under the date and a large
 * clock, and a card with the user, a greeting, the password (Enter logs in,
 * the eye shows it, Up / Down or the chips below switch users), PAM's cues
 * (security key, fingerprint, errors) and the session pill (click / scroll to
 * switch); power buttons in the corner. `primary`: the screen holding the
 * keyboard; the others only show the wallpaper and the clock.
 *
 * One layout, drawn in the current theme's own style:
 *   Material — frosted card over the wallpaper, avatar ring, accent colon,
 *              expressive rise-in
 *   Persona  — slanted PersonaFrame card with its hard shadow and halftone,
 *              italic outlined clock over an accent shadow, the variant's
 *              diagonal slash across the screen, slam-in
 *   Chiikawa — bubbly frosted card with the variant's character peeking
 *              over it (it hops on a wrong password), the pattern behind,
 *              bouncy entrance
 * Everything here is static once the entrance has played: no endless
 * animation outside the security-key cue and the busy indicator.
 */
Item {
    id: root
    required property GreeterContext context
    property bool primary: true

    readonly property bool persona: Persona.shapes
    readonly property bool chiikawa: Chiikawa.enabled
    readonly property string displayName: root.context.user?.realName || root.context.user?.name || ""
    property bool revealPassword: false

    function focusField() {
        passwordBox.forceActiveFocus();
    }
    Component.onCompleted: {
        if (root.primary)
            Qt.callLater(root.focusField);
        introAnim.start();
    }

    // ------------------------------------------------------------- entrance
    // 0 → 1 once: the clock fades down, the card rises (Material), slams in
    // (Persona) or bounces up (Chiikawa).
    property real intro: 0
    NumberAnimation {
        id: introAnim
        target: root
        property: "intro"
        from: 0
        to: 1
        duration: root.persona ? 420 : root.chiikawa ? 620 : Appearance.animationCurves.expressiveDefaultSpatialDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.persona ? Persona.curves.slam : (Themes.curves?.slam ?? Appearance.animationCurves.expressiveDefaultSpatial)
    }

    // ------------------------------------------------------------ background
    Rectangle {
        anchors.fill: parent
        color: root.persona ? Persona.frameColor : Appearance.m3colors.m3background
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
    // Scrim: darker at the top (the clock) and the bottom (the corner
    // buttons), clear around the card.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.35) }
            GradientStop { position: 0.4; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.8) }
            GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.3) }
        }
    }

    // Persona: the game's art over the wallpaper and the menu slash behind
    // the card, in the variant's colours.
    Loader {
        anchors.fill: parent
        active: root.persona
        sourceComponent: Item {
            Image {
                anchors.fill: parent
                visible: Persona.halftone
                source: visible ? Persona.textureUrl(Persona.textureShapeFor(root.width, root.height)) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0.4
            }
            Item {
                anchors.fill: parent
                clip: true
                Rectangle {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.height * 0.1
                    width: parent.width * 1.6
                    height: Math.max(180, root.height * 0.3)
                    rotation: -9
                    color: Persona.frameColor
                    border.width: Persona.borderWidth
                    border.color: Persona.outlineColor
                    opacity: 0.85
                }
                Rectangle {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.height * 0.1 + Math.max(180, root.height * 0.3) * 0.5
                    width: parent.width * 1.6
                    height: 18
                    rotation: -9
                    color: Persona.stripeColor
                }
            }
        }
    }

    // Chiikawa: the variant's stars and hearts, faint, over the wallpaper.
    Image {
        anchors.fill: parent
        visible: Chiikawa.mascot
        source: visible ? Chiikawa.patternUrl() : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.3
    }

    // ----------------------------------------------------------------- clock
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    readonly property real clockSize: Math.min(root.persona ? 168 : 150, root.height * (root.persona ? 0.17 : 0.15))
    readonly property string timeText: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")

    ColumnLayout {
        id: clockColumn
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: root.height * 0.08 - 16 * (1 - root.intro)
        }
        opacity: Math.min(1, root.intro * 1.6)
        spacing: root.persona ? 4 : 0

        // Date: plain above the clock, a slanted tag in the Persona style,
        // a soft pill in the Chiikawa one.
        Item {
            id: dateTag
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: dateText.implicitWidth + (root.persona || root.chiikawa ? 32 : 0)
            implicitHeight: dateText.implicitHeight + (root.persona || root.chiikawa ? 10 : 0)
            Rectangle {
                anchors.fill: parent
                visible: root.persona || root.chiikawa
                radius: root.persona ? 0 : height / 2
                color: root.persona ? Persona.stripeColor : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.15)
                transform: Matrix4x4 {
                    readonly property real k: root.persona ? Persona.skew * 2 : 0
                    matrix: Qt.matrix4x4(1, k, 0, -k * dateTag.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
            }
            StyledText {
                id: dateText
                anchors.centerIn: parent
                text: root.persona ? Qt.locale().toString(clock.date, "dddd  MM/dd").toUpperCase() : Qt.locale().toString(clock.date, "dddd d MMMM")
                font.family: root.persona ? Persona.titleFont : Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: root.persona ? Font.Bold : Font.Medium
                font.italic: root.persona
                font.letterSpacing: root.persona ? 1.5 : 0
                color: root.persona ? Persona.spec.ink : root.chiikawa ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
            }
        }

        // Time: the Persona clock sits on its hard accent shadow.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: clockMain.implicitWidth
            implicitHeight: clockMain.implicitHeight
            ClockLine {
                visible: root.persona
                time: root.timeText
                pixelSize: root.clockSize
                x: Persona.shadowOffset * 1.5
                y: Persona.shadowOffset * 1.5
                textColor: Persona.shadowColor
                accentColor: Persona.shadowColor
            }
            ClockLine {
                id: clockMain
                time: root.timeText
                pixelSize: root.clockSize
                textColor: root.persona ? Persona.spec.ink : Appearance.colors.colOnLayer0
                accentColor: root.persona ? Persona.spec.ink : Appearance.colors.colPrimary
            }
        }
    }

    component ClockLine: Row {
        id: line
        property color textColor
        property color accentColor
        property string time
        property real pixelSize
        readonly property var parts: line.time.split(":")
        spacing: Persona.shapes ? 2 : 4
        Repeater {
            model: line.parts.length * 2 - 1
            delegate: StyledText {
                required property int index
                readonly property bool separator: index % 2 === 1
                anchors.verticalCenter: parent?.verticalCenter
                anchors.verticalCenterOffset: separator && !Persona.shapes ? -height * 0.06 : 0
                text: separator ? ":" : line.parts[index / 2]
                font.family: Appearance.font.family.numbers
                font.pixelSize: line.pixelSize
                font.weight: Persona.shapes ? Font.Bold : Chiikawa.enabled ? Font.Black : Font.Medium
                font.italic: Persona.shapes
                color: separator ? line.accentColor : line.textColor
                style: Persona.shapes ? Text.Outline : Text.Normal
                styleColor: Persona.frameColor
            }
        }
    }

    // ------------------------------------------------------------------ card
    // The card and its decorations move together (the entrance transform).
    Item {
        id: stage
        visible: root.primary
        anchors.fill: parent
        opacity: Math.min(1, root.intro * 2)
        transform: [
            Scale {
                origin.x: stage.width / 2
                origin.y: card.y + card.height / 2
                xScale: root.persona ? 1.08 - 0.08 * root.intro : 0.94 + 0.06 * root.intro
                yScale: xScale
            },
            Rotation {
                origin.x: stage.width / 2
                origin.y: card.y + card.height / 2
                angle: root.persona ? -4 * (1 - root.intro) : 0
            },
            Translate {
                x: root.persona ? -24 * (1 - root.intro) : 0
                y: root.persona ? 0 : 36 * (1 - root.intro)
            }
        ]

        // Chiikawa: the character peeks over the card's top edge (drawn
        // before the card, so the card hides its bottom).
        ChiikawaMascot {
            id: mascot
            anchors {
                bottom: card.top
                bottomMargin: -height * 0.3
                right: card.right
                rightMargin: 36
            }
            width: 132
            height: 132
            idle: false
        }

        // Persona: the slanted frame with its hard shadow and art.
        PersonaFrame {
            visible: root.persona
            anchors.fill: card
            maxLean: 16
        }
        StyledRectangularShadow {
            visible: !root.persona
            target: card
        }

        // A plain Rectangle, not a ClippingRectangle: that one's content
        // isn't drawn by Qt's software renderer.
        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.height * 0.1
            width: Math.min(420, root.width - 48)
            height: cardColumn.implicitHeight + 56
            radius: root.persona ? 0 : Appearance.rounding.verylarge
            // Glass: the theme's surface, mostly opaque, with a light rim
            // (opaque for Chiikawa: the character sits behind it).
            color: root.persona ? "transparent" : ColorUtils.transparentize(Appearance.colors.colLayer0Base, root.chiikawa ? 0 : 0.12)
            border.width: root.persona ? 0 : 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)

            ColumnLayout {
                id: cardColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 28
                    leftMargin: root.persona ? 40 : 28
                    rightMargin: root.persona ? 40 : 28
                }
                spacing: 12

                Avatar {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    user: root.context.user
                    size: 104
                    selected: true
                }

                // Greeting and name
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.persona ? 0 : 2
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        readonly property int hour: clock.date.getHours()
                        text: {
                            const t = hour < 5 ? Translation.tr("Welcome back") : hour < 12 ? Translation.tr("Good morning") : hour < 18 ? Translation.tr("Good afternoon") : Translation.tr("Good evening");
                            return root.persona ? t.toUpperCase() : t;
                        }
                        font.family: root.persona ? Persona.titleFont : Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: root.persona ? Font.Bold : Font.Normal
                        font.italic: root.persona
                        font.letterSpacing: root.persona ? 2 : 0.2
                        color: root.persona ? Persona.stripeColor : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.persona ? root.displayName.toUpperCase() : root.displayName
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.persona ? 38 : 28
                        font.weight: root.persona ? Font.Bold : Font.DemiBold
                        font.italic: root.persona
                        color: root.persona ? Persona.spec.ink : Appearance.colors.colOnLayer0
                    }
                }

                // Password
                Item {
                    id: fieldBox
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    implicitHeight: 54
                    readonly property bool focused: passwordBox.activeFocus
                    readonly property color ringColor: root.context.failed ? Appearance.colors.colError
                        : root.persona ? (fieldBox.focused ? Persona.stripeColor : Persona.outlineColor)
                        : fieldBox.focused ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.8)

                    // Persona: a slanted field on a hard shadow; otherwise a
                    // pill with a focus ring.
                    Rectangle {
                        visible: root.persona
                        anchors.fill: fieldBg
                        anchors.leftMargin: Persona.shadowOffset * 0.6
                        anchors.topMargin: Persona.shadowOffset * 0.6
                        anchors.rightMargin: -Persona.shadowOffset * 0.6
                        anchors.bottomMargin: -Persona.shadowOffset * 0.6
                        color: Persona.shadowColor
                        transform: Matrix4x4 {
                            readonly property real k: Persona.skew * 1.5
                            matrix: Qt.matrix4x4(1, k, 0, -k * fieldBg.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                    Rectangle {
                        id: fieldBg
                        anchors.fill: parent
                        radius: root.persona ? 0 : height / 2
                        color: root.persona ? Persona.frameColor : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.1)
                        border.width: fieldBox.focused || root.context.failed || root.persona ? 2 : 1
                        border.color: fieldBox.ringColor
                        Behavior on border.color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                        transform: Matrix4x4 {
                            readonly property real k: root.persona ? Persona.skew * 1.5 : 0
                            matrix: Qt.matrix4x4(1, k, 0, -k * fieldBg.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 6
                        spacing: 4

                        MaterialSymbol {
                            text: root.context.waitingForKey ? "passkey" : root.context.pendingPrompt ? "pin" : "lock"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.huge
                            color: root.context.waitingForKey || fieldBox.focused ? (root.persona ? Persona.stripeColor : Appearance.colors.colPrimary) : Appearance.colors.colOnSurfaceVariant
                        }
                        ToolbarTextField {
                            id: passwordBox
                            Layout.fillWidth: true
                            colBackground: "transparent"
                            placeholderText: root.context.waitingForKey ? Translation.tr("Touch your security key")
                                : root.context.pendingPrompt && root.context.message ? root.context.message
                                : Translation.tr("Password")
                            font.family: root.persona ? Persona.titleFont : Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.letterSpacing: echoMode === TextInput.Password && text.length > 0 ? 2 : 0
                            color: root.persona ? Persona.spec.ink : Appearance.colors.colOnLayer1
                            passwordCharacter: "●"
                            echoMode: (root.context.pendingPrompt && root.context.promptEcho) || root.revealPassword ? TextInput.Normal : TextInput.Password
                            inputMethodHints: Qt.ImhSensitiveData
                            enabled: !root.context.busy || root.context.pendingPrompt
                            onTextChanged: {
                                root.context.currentText = text;
                                if (text.length > 0)
                                    root.context.failed = false;
                            }
                            onAccepted: root.context.login()
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.context.currentText = "";
                                    root.revealPassword = false;
                                    root.context.reset();
                                    event.accepted = true;
                                } else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && !root.context.pendingPrompt) {
                                    root.context.cycleUser(event.key === Qt.Key_Up ? -1 : 1);
                                    event.accepted = true;
                                }
                            }
                            Connections {
                                target: root.context
                                function onCurrentTextChanged() {
                                    if (passwordBox.text !== root.context.currentText)
                                        passwordBox.text = root.context.currentText;
                                }
                                function onFailure() {
                                    shake.restart();
                                    mascot.hop();
                                    root.focusField();
                                }
                                function onUserChanged() {
                                    root.revealPassword = false;
                                }
                            }
                        }
                        // Show / hide what's typed.
                        IconToolbarButton {
                            visible: passwordBox.text.length > 0 && !(root.context.pendingPrompt && root.context.promptEcho)
                            implicitHeight: 40
                            text: root.revealPassword ? "visibility_off" : "visibility"
                            onClicked: {
                                root.revealPassword = !root.revealPassword;
                                root.focusField();
                            }
                            StyledToolTip {
                                text: root.revealPassword ? Translation.tr("Hide password") : Translation.tr("Show password")
                            }
                        }
                        // Sign in: busy shows the loading shape.
                        RippleButton {
                            id: goButton
                            implicitWidth: 42
                            implicitHeight: 42
                            buttonRadius: root.persona ? 0 : height / 2
                            toggled: true
                            enabled: !root.context.busy || root.context.pendingPrompt
                            colBackgroundToggled: root.persona ? Persona.stripeColor : Appearance.colors.colPrimary
                            colBackgroundToggledHover: root.persona ? Persona.stripeColor : Appearance.colors.colPrimaryHover
                            onClicked: root.context.login()
                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !root.context.busy || root.context.pendingPrompt
                                    text: "arrow_forward"
                                    iconSize: 24
                                    color: root.persona ? Persona.spec.ink : Appearance.colors.colOnPrimary
                                }
                                MaterialLoadingIndicator {
                                    anchors.centerIn: parent
                                    visible: root.context.busy && !root.context.pendingPrompt
                                    loading: visible
                                    implicitSize: 34
                                    colBg: "transparent"
                                    colShape: root.persona ? Persona.spec.ink : Appearance.colors.colOnPrimary
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Sign in")
                            }
                        }
                    }
                    ErrorShakeAnimation {
                        id: shake
                        target: fieldBox
                    }
                }

                // Status: a wrong password, PAM's info (security key,
                // fingerprint), greetd's errors.
                RowLayout {
                    id: status
                    readonly property string text: root.context.failed ? Translation.tr("Incorrect password") : root.context.pendingPrompt ? "" : root.context.message
                    readonly property color tone: root.context.failed ? Appearance.colors.colError
                        : root.context.waitingForKey ? (root.persona ? Persona.stripeColor : Appearance.colors.colPrimary)
                        : Appearance.colors.colOnSurfaceVariant
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: cardColumn.width
                    visible: status.text !== ""
                    spacing: 6
                    MaterialSymbol {
                        text: root.context.failed ? "error" : root.context.waitingForKey ? "passkey" : "info"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: status.tone
                        SequentialAnimation on opacity {
                            running: root.context.waitingForKey
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: status.text
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: status.tone
                    }
                }

                // Session: a pill; click / scroll switches, right-click goes back.
                Item {
                    id: sessionPill
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    visible: root.context.sessions.length > 0
                    readonly property bool several: root.context.sessions.length > 1
                    implicitWidth: sessionRow.implicitWidth + 28
                    implicitHeight: 34
                    Rectangle {
                        anchors.fill: parent
                        radius: root.persona ? 0 : height / 2
                        color: sessionArea.containsMouse && sessionPill.several
                            ? (root.persona ? Persona.shadowColor : Appearance.colors.colLayer2Hover)
                            : (root.persona ? ColorUtils.transparentize(Persona.frameColor, 0.2) : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.3))
                        border.width: root.persona ? 1 : 0
                        border.color: Persona.outlineColor
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                        transform: Matrix4x4 {
                            readonly property real k: root.persona ? Persona.skew * 2 : 0
                            matrix: Qt.matrix4x4(1, k, 0, -k * sessionPill.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                    RowLayout {
                        id: sessionRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "desktop_windows"
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.persona ? Persona.spec.ink : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: root.persona ? (root.context.session?.name ?? "").toUpperCase() : (root.context.session?.name ?? "")
                            font.family: root.persona ? Persona.titleFont : Appearance.font.family.main
                            font.weight: Font.Medium
                            color: root.persona ? Persona.spec.ink : Appearance.colors.colOnSurfaceVariant
                        }
                        MaterialSymbol {
                            visible: sessionPill.several
                            text: "unfold_more"
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.persona ? Persona.spec.ink : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                    MouseArea {
                        id: sessionArea
                        anchors.fill: parent
                        enabled: sessionPill.several
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            root.context.cycleSession(mouse.button === Qt.RightButton ? -1 : 1);
                            root.focusField();
                        }
                        onWheel: wheel => {
                            root.context.cycleSession(wheel.angleDelta.y > 0 ? -1 : 1);
                        }
                    }
                    StyledToolTip {
                        extraVisibleCondition: sessionArea.containsMouse
                        text: Translation.tr("Session")
                    }
                }
            }
        }

        // The other users: avatar chips under the card.
        Row {
            anchors {
                horizontalCenter: card.horizontalCenter
                top: card.bottom
                topMargin: root.persona ? 28 : 20
            }
            visible: root.context.users.length > 1
            spacing: 12
            Repeater {
                model: root.context.users
                delegate: Avatar {
                    id: chip
                    required property var modelData
                    required property int index
                    user: chip.modelData
                    size: 44
                    selected: chip.index === root.context.userIndex
                    opacity: chip.selected ? 1 : chipArea.containsMouse ? 0.95 : 0.7
                    scale: chipArea.pressed ? 0.92 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.context.cycleUser(chip.index - root.context.userIndex);
                            root.focusField();
                        }
                    }
                    StyledToolTip {
                        extraVisibleCondition: chipArea.containsMouse
                        text: chip.modelData.realName || chip.modelData.name
                    }
                }
            }
        }
    }

    // An account picture (or its initial) in the theme's frame: a ring with a
    // gap (Material, Chiikawa), a tilted square on a hard shadow (Persona).
    component Avatar: Item {
        id: av
        property var user: null
        property real size: 96
        property bool selected: false
        readonly property real ring: av.selected ? (Chiikawa.enabled ? 4 : 3) : 0
        readonly property real gap: av.selected ? 3 : 0
        implicitWidth: av.size
        implicitHeight: av.size
        rotation: Persona.shapes ? -4 : 0

        Rectangle {
            visible: Persona.shapes
            x: Persona.shadowOffset * (av.size > 60 ? 1 : 0.5)
            y: x
            width: av.size
            height: av.size
            color: Persona.shadowColor
        }
        Rectangle {
            anchors.fill: parent
            radius: Persona.shapes ? 0 : width / 2
            color: Persona.shapes ? Persona.frameColor : "transparent"
            border.width: Persona.shapes ? (av.selected ? Persona.borderWidth : 1) : av.ring
            border.color: Persona.shapes ? Persona.outlineColor : Chiikawa.enabled ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
        }
        // The initial on a plain disc (always drawn), the picture clipped
        // over it when there is one.
        Rectangle {
            id: disc
            anchors.fill: parent
            anchors.margins: Persona.shapes ? (av.selected ? Persona.borderWidth + 2 : 3) : av.ring + av.gap
            radius: Persona.shapes ? 0 : width / 2
            color: Persona.shapes ? Persona.stripeColor : Appearance.colors.colPrimaryContainer
            StyledText {
                anchors.centerIn: parent
                text: (av.user?.realName || av.user?.name || "?").charAt(0).toUpperCase()
                font.family: Appearance.font.family.title
                font.pixelSize: av.size * 0.42
                font.weight: Font.Bold
                font.italic: Persona.shapes
                color: Persona.shapes ? Persona.spec.ink : Appearance.colors.colOnPrimaryContainer
            }
        }
        ClippingRectangle {
            anchors.fill: disc
            visible: !!av.user?.avatar
            radius: disc.radius
            color: "transparent"
            Image {
                anchors.fill: parent
                source: av.user?.avatar ? `file://${av.user.avatar}` : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: av.size * 2
                sourceSize.height: av.size * 2
                asynchronous: true
            }
        }
    }

    // ----------------------------------------------------------------- power
    Item {
        visible: root.primary
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: root.persona ? 32 : 20
        }
        implicitWidth: powerBar.implicitWidth
        implicitHeight: powerBar.implicitHeight
        opacity: Math.min(1, root.intro * 1.4)

        PersonaFrame {
            visible: root.persona
            anchors.fill: powerBar
            showStripe: false
        }
        Toolbar {
            id: powerBar
            enableShadow: !root.persona
            radius: root.persona ? 0 : height / 2
            colBackground: root.persona ? "transparent" : ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.2)
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
}
