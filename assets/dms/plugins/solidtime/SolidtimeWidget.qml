import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings from DMS plugin settings panel
    property string apiUrl: (pluginData.apiUrl || "").replace(/\/+$/, "").replace(/\/api\/?$/, "")
    property string apiToken: pluginData.apiToken || ""
    property string organizationId: pluginData.organizationId || ""
    property int refreshInterval: (pluginData.refreshInterval || 30) * 1000

    // Push settings to singleton
    onApiUrlChanged: SolidtimeState.apiUrl = apiUrl
    onApiTokenChanged: SolidtimeState.apiToken = apiToken
    onOrganizationIdChanged: SolidtimeState.organizationId = organizationId
    onRefreshIntervalChanged: SolidtimeState.refreshInterval = refreshInterval

    Component.onCompleted: {
        SolidtimeState.apiUrl = apiUrl
        SolidtimeState.apiToken = apiToken
        SolidtimeState.organizationId = organizationId
        SolidtimeState.refreshInterval = refreshInterval
    }

    // Popup state
    property bool showProjectPicker: false
    property string newTimerDescription: ""

    // Always show
    _visibilityOverride: true
    _visibilityOverrideValue: true

    popoutWidth: 360
    popoutHeight: 0

    // Live duration display text
    property real _t: SolidtimeState._tick
    property string liveDurationText: SolidtimeState.hasActiveTimer
        ? SolidtimeState.formatDuration(SolidtimeState.activeTimerDuration)
        : ""

    // --- Bar pill (horizontal) ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            // Timer icon
            DankIcon {
                name: SolidtimeState.hasActiveTimer ? "timer" : "timer_off"
                size: 14
                color: SolidtimeState.hasActiveTimer ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            // Active: show duration + project
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: SolidtimeState.hasActiveTimer

                // Project color dot
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: SolidtimeState.activeTimerProjectColor || Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                    visible: SolidtimeState.activeTimerProjectName !== ""
                }

                StyledText {
                    text: root.liveDurationText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Inactive: show last entry duration
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: !SolidtimeState.hasActiveTimer && SolidtimeState.lastEntryDuration > 0

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: SolidtimeState.lastEntryProjectColor || Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: SolidtimeState.lastEntryProjectName !== ""
                }

                StyledText {
                    text: SolidtimeState.formatDuration(SolidtimeState.lastEntryDuration)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Not configured
            DankIcon {
                name: "signal_disconnected"
                size: 14
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: !SolidtimeState.configured
            }
        }
    }

    // --- Bar pill (vertical) ---

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: SolidtimeState.hasActiveTimer ? "timer" : "timer_off"
                size: 14
                color: SolidtimeState.hasActiveTimer ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: SolidtimeState.hasActiveTimer
                    ? root.liveDurationText
                    : (SolidtimeState.lastEntryDuration > 0
                        ? SolidtimeState.formatDuration(SolidtimeState.lastEntryDuration)
                        : "")
                font.pixelSize: Theme.fontSizeSmall
                color: SolidtimeState.hasActiveTimer ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
            }
        }
    }

    // --- Popout ---

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Solidtime"
            detailsText: SolidtimeState.hasActiveTimer
                ? "Tracking: " + (SolidtimeState.activeTimerProjectName || "No project")
                : "No active timer"
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.showProjectPicker ? 400 : mainColumn.height + Theme.spacingM

                // --- Main view ---
                Column {
                    id: mainColumn
                    width: parent.width
                    spacing: Theme.spacingL
                    visible: !root.showProjectPicker

                    // Not configured warning
                    StyledRect {
                        width: parent.width
                        height: notConfiguredCol.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: !SolidtimeState.configured

                        Column {
                            id: notConfiguredCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingM

                            Row {
                                spacing: Theme.spacingS
                                DankIcon {
                                    name: "warning"
                                    size: 16
                                    color: Theme.warning
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Not configured"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: "Set your Solidtime URL, API token, and Organization ID in the widget settings."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // Error display
                    StyledRect {
                        width: parent.width
                        height: 50
                        radius: Theme.cornerRadius
                        color: Theme.error
                        visible: SolidtimeState.lastError !== ""

                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width - Theme.spacingL * 2
                            text: SolidtimeState.lastError
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // Current / Last timer card
                    StyledRect {
                        width: parent.width
                        height: timerCardCol.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: SolidtimeState.configured

                        Column {
                            id: timerCardCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingM

                            // Header
                            Row {
                                spacing: Theme.spacingS
                                width: parent.width

                                DankIcon {
                                    name: SolidtimeState.hasActiveTimer ? "timer" : "history"
                                    size: 18
                                    color: SolidtimeState.hasActiveTimer ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: SolidtimeState.hasActiveTimer ? "Active Timer" : "Last Entry"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Project name with color dot
                            Row {
                                spacing: Theme.spacingS
                                visible: {
                                    var pn = SolidtimeState.hasActiveTimer
                                        ? SolidtimeState.activeTimerProjectName
                                        : SolidtimeState.lastEntryProjectName
                                    return pn !== ""
                                }

                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: SolidtimeState.hasActiveTimer
                                        ? (SolidtimeState.activeTimerProjectColor || Theme.primary)
                                        : (SolidtimeState.lastEntryProjectColor || Theme.surfaceVariantText)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: SolidtimeState.hasActiveTimer
                                        ? SolidtimeState.activeTimerProjectName
                                        : SolidtimeState.lastEntryProjectName
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Description
                            StyledText {
                                width: parent.width
                                text: SolidtimeState.hasActiveTimer
                                    ? (SolidtimeState.activeTimerDescription || "No description")
                                    : (SolidtimeState.lastEntryDescription || "No description")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                            }

                            // Duration (big)
                            StyledText {
                                text: SolidtimeState.hasActiveTimer
                                    ? root.liveDurationText
                                    : SolidtimeState.formatDuration(SolidtimeState.lastEntryDuration)
                                font.pixelSize: Theme.fontSizeLarge + 4
                                font.weight: Font.Bold
                                color: SolidtimeState.hasActiveTimer ? Theme.primary : Theme.surfaceText
                            }
                        }
                    }

                    // Action buttons
                    Row {
                        spacing: Theme.spacingS
                        width: parent.width
                        visible: SolidtimeState.configured

                        // Stop button (when active)
                        DankButton {
                            width: SolidtimeState.hasActiveTimer ? (parent.width - Theme.spacingS) / 2 : 0
                            text: "Stop"
                            visible: SolidtimeState.hasActiveTimer
                            onClicked: SolidtimeState.stopTimer()
                        }

                        // Start / New timer button
                        DankButton {
                            width: SolidtimeState.hasActiveTimer ? (parent.width - Theme.spacingS) / 2 : parent.width
                            text: SolidtimeState.hasActiveTimer ? "Switch" : "Start Timer"
                            onClicked: {
                                root.showProjectPicker = true
                                root.newTimerDescription = ""
                                SolidtimeState.refresh()
                            }
                        }
                    }

                    // Refresh row
                    Row {
                        width: parent.width
                        layoutDirection: Qt.RightToLeft
                        visible: SolidtimeState.configured

                        Rectangle {
                            width: refreshRow.implicitWidth + Theme.spacingS * 2
                            height: refreshRow.implicitHeight + Theme.spacingXS * 2
                            radius: Theme.cornerRadius
                            color: refreshArea.containsMouse ? Theme.surfaceContainerHigh : "transparent"

                            Row {
                                id: refreshRow
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "refresh"
                                    size: 14
                                    color: SolidtimeState.loading ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter

                                    RotationAnimation on rotation {
                                        running: SolidtimeState.loading
                                        from: 0
                                        to: 360
                                        duration: 1000
                                        loops: Animation.Infinite
                                    }
                                }

                                StyledText {
                                    text: SolidtimeState.loading ? "Refreshing..." : "Refresh"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: refreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !SolidtimeState.loading
                                onClicked: SolidtimeState.refresh()
                            }
                        }
                    }
                }

                // --- Project picker view ---
                Column {
                    id: projectPickerColumn
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.showProjectPicker

                    StyledText {
                        text: "Select Project"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    // Description input
                    StyledRect {
                        width: parent.width
                        height: 36
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius

                        TextInput {
                            id: descriptionInput
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            clip: true
                            text: root.newTimerDescription
                            onTextChanged: root.newTimerDescription = text

                            StyledText {
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Description (optional)"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: descriptionInput.text === ""
                            }
                        }
                    }

                    // No project option
                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: Theme.cornerRadius
                        color: noProjectMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "No project"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: noProjectMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (SolidtimeState.hasActiveTimer)
                                    SolidtimeState.stopTimer()
                                SolidtimeState.startTimer("", root.newTimerDescription)
                                root.showProjectPicker = false
                            }
                        }
                    }

                    // Project list
                    ScrollView {
                        width: parent.width
                        height: Math.min(SolidtimeState.projects.count * 45, 250)
                        clip: true

                        GridView {
                            anchors.fill: parent
                            cellWidth: parent.width
                            cellHeight: 45
                            model: SolidtimeState.projects

                            delegate: Rectangle {
                                width: parent ? parent.width - 10 : 0
                                height: 40
                                radius: Theme.cornerRadius
                                color: {
                                    var isActive = SolidtimeState.hasActiveTimer && SolidtimeState.activeTimerProjectId === model.projectId
                                    if (isActive) return Theme.primaryContainer
                                    return projMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingS
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: model.projectColor
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: model.projectName
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        width: parent.width - 30
                                    }
                                }

                                MouseArea {
                                    id: projMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (SolidtimeState.hasActiveTimer)
                                            SolidtimeState.stopTimer()
                                        SolidtimeState.startTimer(model.projectId, root.newTimerDescription)
                                        root.showProjectPicker = false
                                    }
                                }
                            }
                        }
                    }

                    DankButton {
                        width: parent.width
                        text: "Back"
                        onClicked: root.showProjectPicker = false
                    }
                }
            }
        }
    }
}
