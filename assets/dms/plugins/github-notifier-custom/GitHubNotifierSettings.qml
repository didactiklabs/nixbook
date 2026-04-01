import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "githubNotifierCustom"

    StyledText {
        width: parent.width
        text: "GitHub Notifier"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows open PRs authored by or awaiting review from you, and issues assigned to you. Requires the gh CLI authenticated."
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
        settingKey: "org"
        label: "Organization (optional)"
        description: "Filter by GitHub organization. Leave empty to show all repositories."
        placeholder: "my-org"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "ghBinary"
        label: "gh binary"
        description: "Binary name or path to the gh executable (default: gh)."
        placeholder: "gh"
        defaultValue: "gh"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "Refresh interval (in seconds)."
        defaultValue: 60
        minimum: 15
        maximum: 3600
        unit: "sec"
        leftIcon: "schedule"
    }

    SelectionSetting {
        settingKey: "showPRs"
        label: "Count Pull Requests"
        description: "Include open PRs authored by you."
        options: [
            {label: "Yes", value: "true"},
            {label: "No", value: "false"}
        ]
        defaultValue: "true"
    }

    SelectionSetting {
        settingKey: "showIssues"
        label: "Count Issues"
        description: "Include open issues assigned to you."
        options: [
            {label: "Yes", value: "true"},
            {label: "No", value: "false"}
        ]
        defaultValue: "true"
    }

    SelectionSetting {
        settingKey: "showReviewer"
        label: "Count Review Requests"
        description: "Include open PRs where you are requested as a reviewer."
        options: [
            {label: "Yes", value: "true"},
            {label: "No", value: "false"}
        ]
        defaultValue: "true"
    }
}
