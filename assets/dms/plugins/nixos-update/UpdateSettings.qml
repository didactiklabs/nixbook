import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

/**
 * NixOS Update Checker Plugin Settings
 * Allows users to configure update check intervals, repository source, and service monitoring
 */
PluginSettings {
    id: root
    pluginId: "nixosUpdate"

    // ==================== Default Configuration ====================
    readonly property string defaultRepoUrl: "https://github.com/didactiklabs/nixbook"
    readonly property string defaultRemoteBranch: "refs/heads/main"
    readonly property string defaultSystemdService: "nixos-upgrade-manual.service"
    readonly property int defaultCheckIntervalMs: 5 * 60 * 1000  // 5 minutes
    readonly property int defaultProcessTimeoutMs: 30 * 1000     // 30 seconds
    readonly property int defaultMonitorPollMs: 2000              // 2 seconds

    // ==================== UI Content ====================
    StyledText {
        width: parent.width
        text: "NixOS Update Checker"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure automatic NixOS update checking from a git repository with systemd service integration."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ==================== Settings Sections ====================

    // --- Repository Configuration ---
    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: "Repository Configuration"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.SemiBold
            color: Theme.surfaceText
        }

        // Repository URL
        StyledText {
            text: "Repository URL"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        TextField {
            id: repoUrlField
            Layout.fillWidth: true
            placeholderText: root.defaultRepoUrl
            text: settings.repoUrl || root.defaultRepoUrl
            onEditingFinished: {
                if (text.trim().length > 0) {
                    settings.repoUrl = text.trim()
                }
            }
            selectByMouse: true
        }

        StyledText {
            text: "Git branch to monitor"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        TextField {
            id: remoteBranchField
            Layout.fillWidth: true
            placeholderText: root.defaultRemoteBranch
            text: settings.remoteBranch || root.defaultRemoteBranch
            onEditingFinished: {
                if (text.trim().length > 0) {
                    settings.remoteBranch = text.trim()
                }
            }
            selectByMouse: true
        }
    }

    // --- Service Configuration ---
    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: "Service Configuration"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.SemiBold
            color: Theme.surfaceText
        }

        StyledText {
            text: "Systemd service name"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        TextField {
            id: systemdServiceField
            Layout.fillWidth: true
            placeholderText: root.defaultSystemdService
            text: settings.systemdServiceName || root.defaultSystemdService
            onEditingFinished: {
                if (text.trim().length > 0) {
                    settings.systemdServiceName = text.trim()
                }
            }
            selectByMouse: true
        }
    }

    // --- Timing Configuration ---
    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: "Timing Configuration"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.SemiBold
            color: Theme.surfaceText
        }

        // Check interval
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Check interval (minutes)"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                }
                StyledText {
                    text: Math.round((settings.checkIntervalMs || root.defaultCheckIntervalMs) / 60000) + " min"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    font.weight: Font.Bold
                }
            }

            Slider {
                id: checkIntervalSlider
                Layout.fillWidth: true
                from: 1
                to: 60
                stepSize: 1
                value: Math.round((settings.checkIntervalMs || root.defaultCheckIntervalMs) / 60000)
                onMoved: {
                    settings.checkIntervalMs = Math.round(value * 60000)
                }
            }
        }

        // Process timeout
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Process timeout (seconds)"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                }
                StyledText {
                    text: Math.round((settings.processTimeoutMs || root.defaultProcessTimeoutMs) / 1000) + " s"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    font.weight: Font.Bold
                }
            }

            Slider {
                id: processTimeoutSlider
                Layout.fillWidth: true
                from: 10
                to: 120
                stepSize: 5
                value: Math.round((settings.processTimeoutMs || root.defaultProcessTimeoutMs) / 1000)
                onMoved: {
                    settings.processTimeoutMs = Math.round(value * 1000)
                }
            }
        }

        // Monitor poll interval
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Monitor poll interval (milliseconds)"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                }
                StyledText {
                    text: (settings.monitorPollMs || root.defaultMonitorPollMs) + " ms"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    font.weight: Font.Bold
                }
            }

            Slider {
                id: monitorPollSlider
                Layout.fillWidth: true
                from: 500
                to: 5000
                stepSize: 100
                value: settings.monitorPollMs || root.defaultMonitorPollMs
                onMoved: {
                    settings.monitorPollMs = Math.round(value / 100) * 100
                }
            }
        }
    }

    // --- Reset to Defaults ---
    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingM

        DankButton {
            Layout.fillWidth: true
            text: "Reset to Default Settings"
            onClicked: {
                settings.repoUrl = root.defaultRepoUrl
                settings.remoteBranch = root.defaultRemoteBranch
                settings.systemdServiceName = root.defaultSystemdService
                settings.checkIntervalMs = root.defaultCheckIntervalMs
                settings.processTimeoutMs = root.defaultProcessTimeoutMs
                settings.monitorPollMs = root.defaultMonitorPollMs

                // Reset UI fields
                repoUrlField.text = root.defaultRepoUrl
                remoteBranchField.text = root.defaultRemoteBranch
                systemdServiceField.text = root.defaultSystemdService
                checkIntervalSlider.value = 5
                processTimeoutSlider.value = 30
                monitorPollSlider.value = root.defaultMonitorPollMs
            }
        }
    }
}
