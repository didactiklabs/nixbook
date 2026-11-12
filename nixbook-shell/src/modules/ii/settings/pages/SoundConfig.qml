import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Settings > Sound: volume protection, the shell's sounds and ringtones, and
// echo cancellation (from the General and Services pages).
ContentPage {
    id: page
    forceWidth: true

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

        // Echo cancellation (services/EchoCancel.qml): the microphone, for
        // every app (also the quick toggle, the audio input dialog and the
        // Mesh's listening-together bar).
        ContentSection {
            icon: "noise_aware"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Echo cancellation")
            shown: EchoCancel.available

            ConfigSwitch {
                id: echoSwitch
                buttonIcon: EchoCancel.active ? "noise_aware" : "noise_control_off"
                text: Translation.tr("Keep the computer's sound out of the microphone")
                checked: EchoCancel.active
                enabled: !EchoCancel.busy
                onCheckedChanged: if (checked !== EchoCancel.active) EchoCancel.set(checked)
                Connections {
                    target: EchoCancel
                    function onActiveChanged() {
                        echoSwitch.checked = EchoCancel.active
                    }
                    function onBusyChanged() {
                        if (!EchoCancel.busy) echoSwitch.checked = EchoCancel.active
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: EchoCancel.error !== "" ? EchoCancel.error
                    : Translation.tr("For calls in any app: what plays on this computer (music, a film, the other side of the call) isn't heard through your microphone, and background noise is reduced. While on, the \"Echo-cancelled microphone\" is your default input; off, your microphone comes back. It stays on across logins.")
            }

            // Voices made clearer in calls: the unit's two speech stages
            // (audio.calls; EchoCancel restarts it when one changes).
            ConfigSwitch {
                configKey: "audio.calls.clearMicrophone"
                enabled: !nixManaged
                buttonIcon: "record_voice_over"
                text: Translation.tr("Clearer voice in calls: mine, for the others")
                checked: Config.options.audio.calls.clearMicrophone
                onCheckedChanged: {
                    Config.options.audio.calls.clearMicrophone = checked;
                }
            }
            ConfigSwitch {
                configKey: "audio.calls.clearVoices"
                enabled: !nixManaged
                buttonIcon: "hearing"
                text: Translation.tr("Clearer voices in calls: the others', for me")
                checked: Config.options.audio.calls.clearVoices
                onCheckedChanged: {
                    Config.options.audio.calls.clearVoices = checked;
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("While echo cancellation is on, and without AI. Mine: your voice is equalized for speech (less rumble and boxiness, more presence) and evened out, a quiet voice coming up, before call apps record it. The others': call apps (Discord, Slack, Zoom…) and call tabs of the browser (Google Meet…; echoCancel.callApps and callSites in the Nix configuration) play through \"Call voices\", the same treatment for listening with quiet speakers brought up, and never through the music equalizer. Changing a switch restarts echo cancellation: about a second without microphone.")
            }
        }
    }
}
