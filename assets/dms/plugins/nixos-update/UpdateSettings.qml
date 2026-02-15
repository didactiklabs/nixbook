import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "nixosUpdate"

    property string defaultRepoUrl: "https://github.com/didactiklabs/nixbook"
    property string defaultUpdateCommand: "osupdate"

    StyledText {
        width: parent.width
        text: "NixOS Update Checker"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Check for NixOS updates from a git repository."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: "Repository URL"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }

        TextField {
            id: repoUrlField
            Layout.fillWidth: true
            placeholderText: root.defaultRepoUrl
            text: settings.repoUrl || root.defaultRepoUrl
            onEditingFinished: {
                settings.repoUrl = text
            }
        }

        StyledText {
            text: "Update Command"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }

        TextField {
            id: updateCommandField
            Layout.fillWidth: true
            placeholderText: root.defaultUpdateCommand
            text: settings.updateCommand || root.defaultUpdateCommand
            onEditingFinished: {
                settings.updateCommand = text
            }
        }
    }
}
