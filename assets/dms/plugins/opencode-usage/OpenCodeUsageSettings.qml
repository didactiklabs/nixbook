import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginSettings {
    id: root
    pluginId: "opencodeUsage"

    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) { return Tr.tr(key, lang) }

    StyledText {
        width: parent.width
        text: root.tr("OpenCode Usage")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("Monitor your AI coding usage across providers. Currently tracks Anthropic rate limits, token consumption, and estimated costs via OpenCode credentials.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: root.tr("Refresh Interval")
        description: root.tr("How often to fetch usage data (minutes)")
        defaultValue: 2
        minimum: 2
        maximum: 15

        unit: "min"
        leftIcon: "schedule"
    }
}
