import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
    }

    // A sound setting (Audio.soundFor `kind`: sounds.<kind>Ringtone, or
    // sounds.notificationFile): a sound theme name, or an audio file picked
    // with kdialog. Locked on themes with their own sounds (Themes.themeSounds).
    component RingtoneSetting: ColumnLayout {
        id: ringtone
        required property string kind
        property string text
        property string icon
        property var choices: [
            { displayName: Translation.tr("Alarm clock"), icon: "alarm", value: "alarm-clock-elapsed" },
            { displayName: Translation.tr("Phone ring"), icon: "ring_volume", value: "phone-incoming-call" },
            { displayName: Translation.tr("Bell"), icon: "notifications", value: "bell" },
            { displayName: Translation.tr("Chime"), icon: "check_circle", value: "complete" },
        ]
        readonly property string key: ringtone.kind === "notification" ? "notificationFile" : ringtone.kind + "Ringtone"
        readonly property string value: Config.options.sounds[ringtone.key] ?? ""
        readonly property bool isFile: ringtone.value.includes("/")
        readonly property bool locked: Themes.themeSounds
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 10
            OptionalMaterialSymbol {
                icon: ringtone.icon
                iconSize: Appearance.font.pixelSize.larger
                opacity: ringtone.enabled ? 1 : 0.4
            }
            StyledText {
                Layout.fillWidth: true
                text: ringtone.text
                color: Appearance.colors.colOnSecondaryContainer
                opacity: ringtone.enabled ? 1 : 0.4
            }
            // What plays now: the theme's sound while locked.
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.normal
                materialIcon: "play_arrow"
                mainText: Translation.tr("Preview")
                onClicked: Audio.playRingtone(Audio.soundFor(ringtone.kind))
            }
        }
        StyledText {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.fillWidth: true
            visible: ringtone.locked
            wrapMode: Text.Wrap
            text: Translation.tr("Set by the %1 theme").arg(Themes.currentVariant?.name ?? Themes.currentTheme?.name ?? "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        ConfigSelectionArray {
            configKey: "sounds." + ringtone.key
            shown: !ringtone.locked
            currentValue: ringtone.isFile ? "file" : ringtone.value
            options: [...ringtone.choices,
                { displayName: Translation.tr("Custom file…"), icon: "audio_file", value: "file" }]
            onSelected: newValue => {
                if (newValue === "file")
                    ringtonePicker.running = true;
                else
                    Config.options.sounds[ringtone.key] = newValue;
            }
        }
        StyledText {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.fillWidth: true
            visible: ringtone.isFile && !ringtone.locked
            elide: Text.ElideMiddle
            text: FileUtils.fileNameForPath(ringtone.value)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        Process {
            id: ringtonePicker
            command: ["kdialog", "--title", ringtone.text, "--getopenfilename",
                FileUtils.trimFileProtocol(Directories.music), "Audio (*.mp3 *.ogg *.oga *.opus *.flac *.wav *.m4a)"]
            stdout: StdioCollector {
                id: ringtonePickerOut
                onStreamFinished: {
                    const file = ringtonePickerOut.text.trim();
                    if (file !== "")
                        Config.options.sounds[ringtone.key] = file;
                }
            }
        }
    }

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
            icon: "nest_clock_farsight_analog"
            shape: MaterialShape.Shape.Bun
            title: Translation.tr("Time")

            Rectangle {
                id: previewCard
                Layout.fillWidth: true
                implicitHeight: 180
                radius: Appearance.rounding.normal
                clip: true

                gradient: Gradient { // I didn't like how it turned out but in case I regret it 
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Appearance.colors.colLayer1  }
                    GradientStop { position: 0.6; color: Appearance.colors.colLayer1  }
                    GradientStop { position: 1.0; color: Appearance.colors.colLayer1  }
                }

                property date now: new Date()

                Timer {
                    interval: Config.options.time.secondPrecision ? 1000 : 15000
                    // The page outlives the Settings window: tick only while shown.
                    running: ObjectUtils.shown(previewCard)
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: previewCard.now = new Date()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    ColumnLayout {
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Appearance.font.family.expressive
                            font.pixelSize: 42
                            font.letterSpacing: 1
                            font.features: { "tnum": 1 }
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                            text: {
                                const fmt = Config.options.time.format;
                                if (Config.options.time.secondPrecision) {
                                    if (fmt === "hh:mm") return Qt.formatTime(previewCard.now, "hh:mm:ss");
                                    if (fmt === "h:mm ap") return Qt.formatTime(previewCard.now, "h:mm:ss ap");
                                    if (fmt === "h:mm AP") return Qt.formatTime(previewCard.now, "h:mm:ss AP");
                                }
                                return Qt.formatTime(previewCard.now, fmt);
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: DateTime.longDate
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 32
                            font.weight: Font.Normal
                            opacity: 0.6
                            color: Appearance.colors.colPrimary
                        }
                    }

                    AndroidClock {
                        Layout.rightMargin: 6
                        width: 130
                        height: 130
                        backgroundColor: Appearance.colors.colPrimaryContainer
                        handColor:       Appearance.colors.colPrimary
                        centerDotColor:  Appearance.colors.colPrimary
                    }
                }
            }

            GroupedList {
                Layout.topMargin: -2
                ConfigSelectionArray {
                    configKey: "time.format";
                    enabled: !nixManaged;
                    text: Translation.tr("Format")
                    icon: "schedule"
                    currentValue: Config.options.time.format
                    onSelected: newValue => {
                        Config.options.time.format = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("24h"), value: "hh:mm" },
                        { displayName: Translation.tr("12h am/pm"), value: "h:mm ap" },
                        { displayName: Translation.tr("12h AM/PM"), value: "h:mm AP" }
                    ]
                }
                ConfigSwitch {
                    configKey: "time.secondPrecision";
                    enabled: !nixManaged;
                    buttonIcon: "pace"
                    text: Translation.tr("Second precision")
                    checked: Config.options.time.secondPrecision
                    onCheckedChanged: {
                        Config.options.time.secondPrecision = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "time.showDate";
                    enabled: !nixManaged;
                    buttonIcon: "date_range"
                    text: Translation.tr("Show date")
                    checked: Config.options.time.showDate
                    onCheckedChanged: {
                        Config.options.time.showDate = checked;
                    }
                }
                ConfigTextArea {
                    configKey: "time.format";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    buttonIcon: "scoreboard"
                    text: Translation.tr("Clock String Format")
                    placeholderText: Translation.tr("Clock String Format")
                    value: Config.options.time.format
                    onValueChanged: {
                        Config.options.time.format = value;
                    }
                }
                
                ConfigTextArea {
                    configKey: "time.dateFormat";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    buttonIcon: "calendar_month"
                    text: Translation.tr("Date String Format")
                    placeholderText: Translation.tr("Date String Format")
                    value: Config .options.time.dateFormat
                    onValueChanged: {
                        Config.options.time.dateFormat = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "battery_android_full"
            shape: MaterialShape.Shape.SemiCircle
            title: Translation.tr("Battery")
            shown: Battery.available

            GroupedList {
                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        configKey: "battery.low";
                        enabled: !nixManaged;
                        icon: "warning"
                        text: Translation.tr("Low warning")
                        value: Config.options.battery.low
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.options.battery.low = value;
                        }
                    }
                    ConfigSpinBox {
                        configKey: "battery.critical";
                        enabled: !nixManaged;
                        icon: "dangerous"
                        text: Translation.tr("Critical warning")
                        value: Config.options.battery.critical
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.options.battery.critical = value;
                        }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        configKey: "battery.automaticSuspend";
                        enabled: !nixManaged;
                        buttonIcon: "pause"
                        text: Translation.tr("Automatic suspend")
                        checked: Config.options.battery.automaticSuspend
                        onCheckedChanged: {
                            Config.options.battery.automaticSuspend = checked;
                        }
                    }
                    ConfigSpinBox {
                        configKey: "battery.suspend";
                        enabled: (Config.options.battery.automaticSuspend) && !nixManaged
                        text: Translation.tr("at")
                        value: Config.options.battery.suspend
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.options.battery.suspend = value;
                        }
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        configKey: "battery.full";
                        enabled: !nixManaged;
                        icon: "charger"
                        text: Translation.tr("Full warning")
                        value: Config.options.battery.full
                        from: 0
                        to: 101
                        stepSize: 5
                        onValueChanged: {
                            Config.options.battery.full = value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "volume_up"
            shape: MaterialShape.Shape.Circle
            title: Translation.tr("Audio")
            GroupedList {
                ConfigSwitch {
                    configKey: "audio.protection.enable";
                    enabled: !nixManaged;
                    buttonIcon: "hearing"
                    text: Translation.tr("Earbang protection")
                    checked: Config.options.audio.protection.enable
                    onCheckedChanged: {
                        Config.options.audio.protection.enable = checked;
                    }
                }
                ConfigRow {
                    enabled: Config.options.audio.protection.enable
                    ConfigSpinBox {
                        configKey: "audio.protection.maxAllowedIncrease";
                        enabled: !nixManaged;
                        icon: "arrow_warm_up"
                        text: Translation.tr("Max allowed increase")
                        value: Config.options.audio.protection.maxAllowedIncrease
                        from: 0
                        to: 100
                        stepSize: 2
                        onValueChanged: {
                            Config.options.audio.protection.maxAllowedIncrease = value;
                        }
                    }
                    ConfigSpinBox {
                        configKey: "audio.protection.maxAllowed";
                        enabled: !nixManaged;
                        icon: "vertical_align_top"
                        text: Translation.tr("Volume limit")
                        value: Config.options.audio.protection.maxAllowed
                        from: 0
                        to: 154 // pavucontrol allows up to 153%
                        stepSize: 2
                        onValueChanged: {
                            Config.options.audio.protection.maxAllowed = value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "notification_sound"
            shape: MaterialShape.Shape.Clover8Leaf
            title: Translation.tr("Sounds")
            GroupedList {
                ConfigSwitch {
                    configKey: "sounds.battery";
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery")
                    enabled: (Battery.available) && !nixManaged
                    checked: Config.options.sounds.battery
                    onCheckedChanged: {
                        Config.options.sounds.battery = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "sounds.pomodoro";
                    enabled: !nixManaged;
                    buttonIcon: "av_timer"
                    text: Translation.tr("Timers (focus and countdown)")
                    checked: Config.options.sounds.pomodoro
                    onCheckedChanged: {
                        Config.options.sounds.pomodoro = checked;
                    }
                }
                RingtoneSetting {
                    kind: "focus"
                    text: Translation.tr("Focus / break ringtone")
                    icon: "search_activity"
                    enabled: Config.options.sounds.pomodoro
                }
                RingtoneSetting {
                    kind: "countdown"
                    text: Translation.tr("Countdown ringtone")
                    icon: "timer"
                    enabled: Config.options.sounds.pomodoro
                }
                // Always rings, whatever the switch above says.
                RingtoneSetting {
                    kind: "alarm"
                    text: Translation.tr("Alarm ringtone")
                    icon: "alarm"
                }
                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        configKey: "sounds.countdownRingSeconds";
                        enabled: !nixManaged;
                        icon: "timer_off"
                        text: Translation.tr("Countdown rings for (s)")
                        value: Config.options.sounds.countdownRingSeconds
                        from: 5
                        to: 3600
                        stepSize: 15
                        onValueChanged: {
                            Config.options.sounds.countdownRingSeconds = value;
                        }
                    }
                    ConfigSpinBox {
                        configKey: "sounds.alarmRingSeconds";
                        enabled: !nixManaged;
                        icon: "alarm_off"
                        text: Translation.tr("Alarm rings for (s)")
                        value: Config.options.sounds.alarmRingSeconds
                        from: 5
                        to: 3600
                        stepSize: 15
                        onValueChanged: {
                            Config.options.sounds.alarmRingSeconds = value;
                        }
                    }
                }
                ConfigSwitch {
                    configKey: "sounds.notification";
                    enabled: !nixManaged;
                    buttonIcon: "notifications_active"
                    text: Translation.tr("Notifications")
                    checked: Config.options.sounds.notification
                    onCheckedChanged: {
                        Config.options.sounds.notification = checked;
                    }
                }
                RingtoneSetting {
                    kind: "notification"
                    text: Translation.tr("Notification sound")
                    icon: "notifications_active"
                    enabled: Config.options.sounds.notification
                    choices: [
                        { displayName: Translation.tr("Default"), icon: "music_note", value: "" },
                        { displayName: Translation.tr("Message"), icon: "chat", value: "message-new-instant" },
                        { displayName: Translation.tr("Bell"), icon: "notifications", value: "bell" },
                        { displayName: Translation.tr("Pop"), icon: "bubble_chart", value: "message" },
                    ]
                }
            }
        }

        ContentSection {
            icon: "language_japanese_kana"
            shape: MaterialShape.Shape.Gem
            title: Translation.tr("Language")

            GroupedList {
                ConfigComboBox {
                    configKey: "language.ui";
                    enabled: !nixManaged;
                    Layout.fillWidth: true
                    buttonIcon: "language"
                    text: Translation.tr("Interface Language")
                    fieldWidth: 240
                    model: [
                        { displayName: Translation.tr("Auto (System)"), value: "auto" },
                        ...Translation.allAvailableLanguages.map(lang => ({ displayName: lang, value: lang }))
                    ]
                    currentValue: Config.options.language.ui
                    onSelected: newValue => {
                        Config.options.language.ui = newValue;
                    }
                }

                ColumnLayout {
                    id: translationCol
                    Layout.fillWidth: true
                    spacing: 8

                    ConfigTextArea {
                        configKey: "language.ui";
                        enabled: !nixManaged;
                        id: localeField
                        Layout.fillWidth: true
                        buttonIcon: "translate"
                        text: Translation.tr("Locale code")
                        placeholderText: Translation.tr("e.g. fr_FR, de_DE, zh_CN...")
                        value: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                    }
                }
            }
        }

        ContentSection {
            icon: "work_alert"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Work safety")
            GroupedList {
                ConfigSwitch {
                    configKey: "workSafety.enable.clipboard";
                    enabled: !nixManaged;
                    buttonIcon: "assignment"
                    text: Translation.tr("Hide clipboard images copied from sussy sources")
                    checked: Config.options.workSafety.enable.clipboard
                    onCheckedChanged: {
                        Config.options.workSafety.enable.clipboard = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "workSafety.enable.wallpaper";
                    enabled: !nixManaged;
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Hide sussy/anime wallpapers")
                    checked: Config.options.workSafety.enable.wallpaper
                    onCheckedChanged: {
                        Config.options.workSafety.enable.wallpaper = checked;
                    }
                }
            }
        }
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
        // The mesh between people's desktops (services/Mesh.qml): the
        // server and your name are settings, the access token and the mesh
        // key go to the keyring through `nixbook-mesh`, on stdin.
        ContentSection {
            id: meshSection
            icon: "hub"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Mesh")
            property string status: ""
            property string code: ""
            // The token and the mesh code by hand, instead of an invite.
            property bool byHand: false
            // The admin: the last invite made.
            property string invite: ""
            property string invited: ""

            function check() {
                meshSection.status = Translation.tr("Checking…")
                Mesh.run(["test", Mesh.server], "", (ok, answer) => {
                    meshSection.status = ok
                        ? (answer.joined ? Translation.tr("Connected as %1, in the mesh.").arg(answer.user)
                            : Translation.tr("The token works (%1). Now create a mesh or enter a member's code.").arg(answer.user))
                        : answer.error
                })
            }
            Component.onCompleted: Mesh.refreshStatus()

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Talk with the people you choose, desktop to desktop, over the internet: messages to everyone or to one person, and everyone's status (free, in a meeting, gaming, busy, do not disturb, away; never which app). Everything is encrypted on this computer with the mesh's key, which only members have: the server only passes on what it can't read. To join, paste the invite code someone gave you. The server's admin invites people from here.")
            }
            ConfigTextArea {
                id: meshServer
                configKey: "mesh.server"
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "dns"
                text: Translation.tr("Server")
                placeholderText: Translation.tr("e.g. https://ntfy.example.org")
                value: Config.options.mesh.server ?? ""
                Connections {
                    target: meshServer.textArea
                    function onEditingFinished() {
                        Config.options.mesh.server = meshServer.value.trim().replace(/\/+$/, "")
                    }
                }
            }
            ConfigTextArea {
                id: meshName
                configKey: "mesh.name"
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "badge"
                text: Translation.tr("Your name")
                placeholderText: Mesh.myName
                value: Config.options.mesh.name ?? ""
                Connections {
                    target: meshName.textArea
                    function onEditingFinished() {
                        Config.options.mesh.name = meshName.value.trim()
                    }
                }
            }

            // Joining with an invite: one code, nothing else.
            ColumnLayout {
                Layout.fillWidth: true
                visible: !Mesh.configured && !meshSection.byHand
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.weight: Font.DemiBold
                    text: Translation.tr("Got an invite? Paste it here and click Join: that's all.")
                }
                MaterialTextField {
                    id: meshInvite
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("nixbook-mesh-invite:…")
                    echoMode: TextInput.Password
                    onAccepted: meshAccept.clicked()
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    SmallButton {
                        id: meshAccept
                        enabled: !Mesh.busy && meshInvite.text.trim() !== ""
                        materialIcon: "group_add"
                        mainText: Mesh.busy ? Translation.tr("Joining…") : Translation.tr("Join")
                        onClicked: {
                            meshSection.status = Translation.tr("Joining…")
                            Mesh.accept(meshInvite.text.trim(), (ok, answer) => {
                                meshInvite.text = ""
                                meshSection.status = ok ? Translation.tr("You're in, as %1.").arg(answer.user) : answer.error
                            })
                        }
                    }
                    SmallButton {
                        enabled: !Mesh.busy
                        materialIcon: "tune"
                        mainText: Translation.tr("Set it up by hand instead")
                        onClicked: meshSection.byHand = true
                    }
                }
            }

            // By hand: the access token, then create a mesh or enter its code.
            ColumnLayout {
                Layout.fillWidth: true
                visible: Mesh.configured || meshSection.byHand
                spacing: 6
                // The access token.
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Mesh.setup.token
                        ? Translation.tr("Access token: saved (%1).").arg(Mesh.setup.tokenSource === "file"
                            ? Translation.tr("in ~/.config/nixbook-shell/mesh/token") : Translation.tr("in your keyring"))
                        : Translation.tr("Access token: none yet. Paste the one the server's admin gave you (tk_…).")
                }
                MaterialTextField {
                    id: meshToken
                    Layout.fillWidth: true
                    placeholderText: Mesh.setup.token ? Translation.tr("A new access token (saved: leave empty to keep it)")
                        : Translation.tr("Access token (tk_…)")
                    echoMode: TextInput.Password
                    onAccepted: meshTokenSave.clicked()
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    SmallButton {
                        id: meshTokenSave
                        enabled: !Mesh.busy && meshToken.text.trim() !== ""
                        materialIcon: "key"
                        mainText: Translation.tr("Save the token")
                        onClicked: {
                            Mesh.run(["token", "set"], meshToken.text.trim(), (ok, answer) => {
                                meshToken.text = ""
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                Mesh.reconnect()
                                if (Mesh.server !== "") meshSection.check()
                            })
                        }
                    }
                    SmallButton {
                        enabled: !Mesh.busy && !!Mesh.setup.token && Mesh.server !== ""
                        materialIcon: "network_check"
                        mainText: Translation.tr("Test")
                        onClicked: meshSection.check()
                    }
                    SmallButton {
                        visible: !!Mesh.setup.token
                        enabled: !Mesh.busy
                        materialIcon: "key_off"
                        mainText: Translation.tr("Forget the token")
                        onClicked: Mesh.run(["token", "forget"], "", () => Mesh.reconnect())
                    }
                }

                // The mesh key.
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Mesh.setup.joined
                        ? (Mesh.connected ? Translation.tr("In the mesh, connected. Members seen: %1.").arg(Mesh.memberList.length)
                            : Translation.tr("In the mesh, not connected yet.") + (Mesh.lastError ? ` ${Mesh.lastError}` : ""))
                        : Translation.tr("Not in a mesh yet: create one (then show its code to the others), or enter the code a member shows you.")
                }
                MaterialTextField {
                    id: meshCode
                    Layout.fillWidth: true
                    visible: !Mesh.setup.joined
                    placeholderText: Translation.tr("A member's mesh code (XXXXX-XXXXX-…)")
                    onAccepted: meshJoin.clicked()
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    SmallButton {
                        id: meshJoin
                        visible: !Mesh.setup.joined
                        enabled: !Mesh.busy && meshCode.text.trim() !== ""
                        materialIcon: "group_add"
                        mainText: Translation.tr("Join")
                        onClicked: {
                            Mesh.run(["mesh", "join"], meshCode.text.trim(), (ok, answer) => {
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                meshCode.text = ""
                                meshSection.status = Translation.tr("Joined.")
                                Mesh.reconnect()
                            })
                        }
                    }
                    SmallButton {
                        visible: !Mesh.setup.joined
                        enabled: !Mesh.busy
                        materialIcon: "add_circle"
                        mainText: Translation.tr("Create a mesh")
                        onClicked: {
                            Mesh.run(["mesh", "create"], "", (ok, answer) => {
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                meshSection.code = answer.code
                                meshSection.status = Translation.tr("Created. Show this code to the others.")
                                Mesh.reconnect()
                            })
                        }
                    }
                    SmallButton {
                        visible: !!Mesh.setup.joined
                        enabled: !Mesh.busy
                        materialIcon: meshSection.code !== "" ? "visibility_off" : "qr_code"
                        mainText: meshSection.code !== "" ? Translation.tr("Hide the code") : Translation.tr("Show the mesh code")
                        onClicked: {
                            if (meshSection.code !== "") {
                                meshSection.code = ""
                                return
                            }
                            Mesh.run(["mesh", "code"], "", (ok, answer) => {
                                if (ok) meshSection.code = answer.code
                                else meshSection.status = answer.error
                            })
                        }
                    }
                    SmallButton {
                        visible: meshSection.code !== ""
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy")
                        onClicked: Clipboard.copy(meshSection.code)
                    }
                    SmallButton {
                        visible: !!Mesh.setup.joined
                        enabled: !Mesh.busy
                        materialIcon: "logout"
                        mainText: Translation.tr("Leave the mesh")
                        onClicked: {
                            meshSection.code = ""
                            Mesh.run(["mesh", "leave"], "", () => Mesh.reconnect())
                        }
                    }
                }
            }

            // The server's admin: who is in, inviting and removing people.
            ColumnLayout {
                Layout.fillWidth: true
                visible: Mesh.isAdmin && !!Mesh.setup.joined
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    font.weight: Font.DemiBold
                    text: Translation.tr("People (you are the server's admin)")
                }
                Repeater {
                    model: Mesh.people
                    delegate: RowLayout {
                        id: person
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: person.modelData.role === "admin" ? "shield_person" : "person"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: person.modelData.name + (person.modelData.name === Mesh.account.user ? Translation.tr(" (you)") : "")
                                + (person.modelData.role === "admin" ? ` · ${Translation.tr("admin")}` : "")
                        }
                        SmallButton {
                            visible: person.modelData.role !== "admin"
                            enabled: !Mesh.busy
                            materialIcon: "person_remove"
                            mainText: Translation.tr("Remove")
                            onClicked: Mesh.removePerson(person.modelData.name, (ok, answer) => {
                                meshSection.status = ok ? Translation.tr("%1 is out: their desktop can't reach the mesh any more.").arg(answer.name) : answer.error
                            })
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialTextField {
                        id: meshInviteName
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Their name (lower case, e.g. choco)")
                        onAccepted: meshInviteButton.clicked()
                    }
                    SmallButton {
                        id: meshInviteButton
                        enabled: !Mesh.busy && meshInviteName.text.trim() !== ""
                        materialIcon: "person_add"
                        mainText: Translation.tr("Invite")
                        onClicked: {
                            Mesh.invite(meshInviteName.text.trim().toLowerCase(), (ok, answer) => {
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                meshInviteName.text = ""
                                meshSection.invite = answer.code
                                meshSection.invited = answer.name
                                meshSection.status = ""
                            })
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: meshSection.invite !== ""
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Send this to %1 privately (it holds the mesh's key). It works once; inviting %1 again makes a new one.").arg(meshSection.invited)
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: meshSection.invite !== ""
                    wrapMode: Text.WrapAnywhere
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: meshSection.invite
                }
                Flow {
                    Layout.fillWidth: true
                    visible: meshSection.invite !== ""
                    spacing: 6
                    SmallButton {
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy the invite")
                        onClicked: Clipboard.copy(meshSection.invite)
                    }
                    SmallButton {
                        materialIcon: "visibility_off"
                        mainText: Translation.tr("Hide it")
                        onClicked: {
                            meshSection.invite = ""
                            meshSection.invited = ""
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: meshSection.code !== ""
                wrapMode: Text.WrapAnywhere
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.large
                text: meshSection.code
            }
            StyledText {
                Layout.fillWidth: true
                visible: Mesh.myFingerprint !== "" && !!Mesh.setup.joined
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("This desktop's key (private messages are sealed for it): %1. The others see it in your private conversation; compare it to be sure no one poses as you.").arg(Mesh.myFingerprint)
            }
            StyledText {
                Layout.fillWidth: true
                visible: meshSection.status !== ""
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: meshSection.status
            }
            GroupedList {
                ConfigSwitch {
                    configKey: "mesh.sharePresence";
                    enabled: !nixManaged;
                    buttonIcon: "radio_button_checked"
                    text: Translation.tr("Share my status (free, in a meeting, gaming, busy, away)")
                    checked: Config.options.mesh.sharePresence
                    onCheckedChanged: {
                        Config.options.mesh.sharePresence = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.shareAvatar";
                    enabled: !nixManaged;
                    buttonIcon: "account_circle"
                    text: Translation.tr("Show my account picture to the others")
                    checked: Config.options.mesh.shareAvatar
                    onCheckedChanged: {
                        Config.options.mesh.shareAvatar = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.nudgeCutIn";
                    enabled: !nixManaged;
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Show the nudges I receive as a cut-in")
                    checked: Config.options.mesh.nudgeCutIn
                    onCheckedChanged: {
                        Config.options.mesh.nudgeCutIn = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.notify";
                    enabled: !nixManaged;
                    buttonIcon: "notifications"
                    text: Translation.tr("A notification for each message")
                    checked: Config.options.mesh.notify
                    onCheckedChanged: {
                        Config.options.mesh.notify = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.enable";
                    enabled: !nixManaged;
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Connected to the mesh")
                    checked: Config.options.mesh.enable
                    onCheckedChanged: {
                        Config.options.mesh.enable = checked;
                    }
                }
            }
        }
    }
}
