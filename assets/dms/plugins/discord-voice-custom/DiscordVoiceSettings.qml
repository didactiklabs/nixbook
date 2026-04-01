import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "discordVoiceCustom"

    StyledText {
        width: parent.width
        text: "Discord Voice Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Show Discord voice channel participants in DankBar with speaking and mute indicators."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "maxBarAvatars"
        label: "Max Bar Avatars"
        description: "Maximum number of user avatars shown in the bar"
        defaultValue: 5
        minimum: 1
        maximum: 10
        leftIcon: "group"
    }

    StyledText {
        width: parent.width
        text: "Keybind integration: use 'dms ipc call discord toggleMute' and 'dms ipc call discord toggleDeafen' in your compositor keybinds. For push-to-talk: muteOn / muteOff."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
