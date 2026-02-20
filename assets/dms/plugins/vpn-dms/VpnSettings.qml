import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "vpnStatus"

    StyledText {
        width: parent.width
        text: "VPN Status"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitor and control your Tailscale and NetBird VPN connections"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "tailscaleAutoConnect"
        label: "Tailscale Auto Connect"
        description: "Automatically connect Tailscale on startup"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "netbirdAutoConnect"
        label: "NetBird Auto Connect"
        description: "Automatically connect NetBird on startup"
        defaultValue: false
    }
}
