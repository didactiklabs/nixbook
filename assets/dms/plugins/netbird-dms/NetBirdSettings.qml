import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "netbirdStatus"

    StyledText {
        width: parent.width
        text: "NetBird VPN Status"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitor and control your NetBird VPN connection"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "autoConnect"
        label: "Auto Connect"
        description: "Automatically connect on startup"
        defaultValue: false
    }
}
