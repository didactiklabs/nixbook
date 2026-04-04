import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "solidtime"

    StyledText {
        width: parent.width
        text: "Solidtime"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Track time with Solidtime. Shows current or last timer in the bar. Click to start/stop timers and select projects."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    StringSetting {
        settingKey: "apiUrl"
        label: "Solidtime URL"
        description: "Base URL of your Solidtime instance (e.g. https://time.example.com)"
        placeholder: "https://time.example.com"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "apiToken"
        label: "API Token"
        description: "Your Solidtime API token. Generate one from your Solidtime profile settings."
        placeholder: "your-api-token"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "organizationId"
        label: "Organization ID"
        description: "UUID of your Solidtime organization."
        placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often to poll for timer updates (seconds)."
        defaultValue: 30
        minimum: 10
        maximum: 300
        unit: "sec"
        leftIcon: "schedule"
    }
}
