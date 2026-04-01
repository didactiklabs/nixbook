import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import OpenCodeUsageModule
import "translations.js" as Tr

PluginComponent {
    id: root

    // i18n
    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) { return Tr.tr(key, lang) }

    // Calendar week labels: Monday to Sunday (fixed order)
    property var dayLabels: lang === "fr"
        ? ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]
        : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Settings (push to singleton)
    property int refreshIntervalSetting: (pluginData.refreshInterval || 2) * 60000
    onRefreshIntervalSettingChanged: OpenCodeUsageState.refreshInterval = refreshIntervalSetting

    // Tab model (UI-only, not shared)
    ListModel { id: tabModel }
    property int refreshEpoch: OpenCodeUsageState.refreshEpoch

    // Always show the widget (disconnect icon when no data, normal content otherwise)
    _visibilityOverride: true
    _visibilityOverrideValue: true

    // Derived popout sizing
    popoutWidth: 380
    popoutHeight: {
        var h = 120 // Header & Footer
        if (OpenCodeUsageState.noProviderData) h += 160
        if (OpenCodeUsageState.rateLimitTier) h += 240
        if (OpenCodeUsageState.anthropicMonthTokens > 0) h += 180 + (OpenCodeUsageState.anthropicModels.count > 0 ? 50 + OpenCodeUsageState.anthropicModels.count * 20 : 0)
        if (OpenCodeUsageState.geminiMonthTokens > 0) h += 180 + (OpenCodeUsageState.geminiModels.count > 0 ? 50 + OpenCodeUsageState.geminiModels.count * 20 : 0)
        if (OpenCodeUsageState.opencodeMonthTokens > 0) h += 180 + (OpenCodeUsageState.opencodeModels.count > 0 ? 50 + OpenCodeUsageState.opencodeModels.count * 20 : 0)
        return Math.min(800, h)
    }

    // EUR-aware cost formatting (needs lang context)
    function formatCost(usd) {
        var useEur = lang === "fr" && OpenCodeUsageState.usdEurRate > 0
        var n = useEur ? usd * OpenCodeUsageState.usdEurRate : usd
        var sym = useEur ? "" : "$"
        var suffix = useEur ? " \u20ac" : ""
        if (n >= 1000) return sym + (n / 1000).toFixed(1) + "K" + suffix
        if (n >= 100) return sym + Math.round(n) + suffix
        if (n >= 10) return sym + n.toFixed(1) + suffix
        return sym + n.toFixed(2) + suffix
    }

    function updateTabs() {
        tabModel.clear()
        tabModel.append({ label: tr("Anthropic"), icon: "smart_toy", available: !!(OpenCodeUsageState.rateLimitTier || OpenCodeUsageState.anthropicWeekTokens > 0 || OpenCodeUsageState.fiveHourUtil > 0) })
        tabModel.append({ label: tr("Gemini"), icon: "auto_awesome", available: OpenCodeUsageState.geminiWeekTokens > 0 })
        tabModel.append({ label: tr("OpenCode"), icon: "code", available: OpenCodeUsageState.opencodeWeekTokens > 0 })
        if (tabModel.count > 0 && !tabModel.get(OpenCodeUsageState.selectedTab).available) {
            for (var i = 0; i < tabModel.count; i++) {
                if (tabModel.get(i).available) { OpenCodeUsageState.selectedTab = i; break }
            }
        }
    }

    onRefreshEpochChanged: updateTabs()

    // --- Taskbar pills ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingM

            // Disconnected icon: shown when no data is available
            DankIcon {
                name: "signal_disconnected"
                size: 14
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: OpenCodeUsageState.noProviderData
            }

            // Anthropic
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: OpenCodeUsageState.fiveHourUtil > 0 || OpenCodeUsageState.rateLimitTier !== ""

                DankIcon {
                    name: "warning"
                    size: 12
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                    visible: OpenCodeUsageState.dataStale
                }

                Canvas {
                    id: hRing
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    renderStrategy: Canvas.Cooperative

                    property real percent: OpenCodeUsageState.fiveHourUtil
                    onPercentChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = width / 2, cy = height / 2, r = 7.5, lw = 2.5

                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                        ctx.lineWidth = lw
                        ctx.strokeStyle = Theme.surfaceVariant
                        ctx.stroke()

                        var pct = percent / 100
                        if (pct > 0) {
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                            ctx.lineWidth = lw
                            ctx.strokeStyle = OpenCodeUsageState.progressColor(percent)
                            ctx.lineCap = "round"
                            ctx.stroke()
                        }
                    }
                }

                StyledText {
                    text: OpenCodeUsageState.fiveHourUtil < 0 ? "N/A" : Math.round(OpenCodeUsageState.fiveHourUtil) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: OpenCodeUsageState.fiveHourUtil < 0 ? Theme.surfaceVariantText : Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: OpenCodeUsageState.fiveHourCountdown ? "\u00b7 " + OpenCodeUsageState.fiveHourCountdown : ""
                    visible: OpenCodeUsageState.fiveHourCountdown !== ""
                    font.pixelSize: 9
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Gemini
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: OpenCodeUsageState.geminiWeekTokens > 0

                DankIcon {
                    name: "smart_toy"
                    size: 14
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: formatCost(OpenCodeUsageState.geminiTodayCost)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // OpenCode
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: OpenCodeUsageState.opencodeWeekTokens > 0

                DankIcon {
                    name: "code"
                    size: 14
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: OpenCodeUsageState.formatTokens(OpenCodeUsageState.opencodeWeekTokens)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingS

            // Disconnected icon: shown when no data is available
            DankIcon {
                name: "signal_disconnected"
                size: 14
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: OpenCodeUsageState.noProviderData
            }

            // Anthropic
            Column {
                spacing: Theme.spacingXS || 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: OpenCodeUsageState.fiveHourUtil > 0 || OpenCodeUsageState.rateLimitTier !== ""

                DankIcon {
                    name: "warning"
                    size: 12
                    color: Theme.warning
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: OpenCodeUsageState.dataStale
                }

                Canvas {
                    id: vRing
                    width: 20
                    height: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    renderStrategy: Canvas.Cooperative

                    property real percent: OpenCodeUsageState.fiveHourUtil
                    onPercentChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = width / 2, cy = height / 2, r = 7.5, lw = 2.5

                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                        ctx.lineWidth = lw
                        ctx.strokeStyle = Theme.surfaceVariant
                        ctx.stroke()

                        var pct = percent / 100
                        if (pct > 0) {
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                            ctx.lineWidth = lw
                            ctx.strokeStyle = OpenCodeUsageState.progressColor(percent)
                            ctx.lineCap = "round"
                            ctx.stroke()
                        }
                    }
                }

                StyledText {
                    text: OpenCodeUsageState.fiveHourUtil < 0 ? "N/A" : Math.round(OpenCodeUsageState.fiveHourUtil) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: OpenCodeUsageState.fiveHourUtil < 0 ? Theme.surfaceVariantText : Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: OpenCodeUsageState.fiveHourCountdown || ""
                    visible: OpenCodeUsageState.fiveHourCountdown !== ""
                    font.pixelSize: 9
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            // Gemini
            Column {
                spacing: Theme.spacingXS || 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: OpenCodeUsageState.geminiWeekTokens > 0

                DankIcon {
                    name: "smart_toy"
                    size: 14
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: formatCost(OpenCodeUsageState.geminiTodayCost)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            // OpenCode
            Column {
                spacing: Theme.spacingXS || 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: OpenCodeUsageState.opencodeWeekTokens > 0

                DankIcon {
                    name: "code"
                    size: 14
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: OpenCodeUsageState.formatTokens(OpenCodeUsageState.opencodeWeekTokens)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // --- Provider Stats Template ---
    component ProviderStats: Column {
        property string providerName: ""
        property real weekTokens: 0
        property real monthTokens: 0
        property real todayCost: 0
        property real weekCost: 0
        property real monthCost: 0
        property var dailyTokens: []
        property var dailyCosts: []
        property real maxDaily: 1
        property ListModel modelsList
        property int hoverDayProp: -1
        signal dayHovered(int dayIndex)

        width: parent.width
        spacing: Theme.spacingM

        Row {
            width: parent.width
            spacing: Theme.spacingS
            
            Rectangle {
                width: 3
                height: 16
                color: Theme.primary
                radius: 1
                anchors.verticalCenter: parent.verticalCenter
            }
            
            StyledText {
                text: providerName
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
            
        }
        
        StyledText {
            text: OpenCodeUsageState.formatTokens(monthTokens) + " \u2022 " + formatCost(monthCost) + " / " + root.tr("Month")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        // Token Consumption card
        StyledRect {
            width: parent.width
            height: consumptionCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainerHigh

            Column {
                id: consumptionCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Row {
                    width: parent.width

                    Column {
                        width: parent.width / 2
                        spacing: 4

                        StyledText {
                            text: root.tr("Today")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        StyledText {
                            text: OpenCodeUsageState.formatTokens(dailyTokens[OpenCodeUsageState.todayIndex])
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.primary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        StyledText {
                            text: formatCost(todayCost)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: todayCost > 0
                        }
                    }

                    Column {
                        width: parent.width / 2
                        spacing: 4

                        StyledText {
                            text: root.tr("Week")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        StyledText {
                            text: OpenCodeUsageState.formatTokens(weekTokens)
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        StyledText {
                            text: formatCost(weekCost)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: weekCost > 0
                        }
                    }
                }
            }
        }

        // Daily activity card
        StyledRect {
            width: parent.width
            height: dailyCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainerHigh

            Column {
                id: dailyCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    text: root.tr("Daily Activity")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                Item {
                    width: parent.width
                    height: 50

                    Row {
                        id: chartRow
                        anchors.fill: parent
                        spacing: 4

                        Repeater {
                            model: 7
                            delegate: Column {
                                width: (chartRow.width - 6 * 4) / 7
                                height: chartRow.height
                                spacing: 2

                                Item {
                                    width: parent.width
                                    height: parent.height - dayLabel.height - 2

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.max(parent.width - 4, 4)
                                        height: maxDaily > 0
                                            ? Math.max(dailyTokens[index] / maxDaily * parent.height, dailyTokens[index] > 0 ? 3 : 0)
                                            : 0
                                        radius: 2
                                        color: index === hoverDayProp
                                            ? Theme.primary
                                            : index === OpenCodeUsageState.todayIndex ? Theme.primary : Theme.surfaceVariant
                                        opacity: hoverDayProp >= 0 && index !== hoverDayProp ? 0.4 : 1.0

                                        Behavior on opacity {
                                            NumberAnimation { duration: 120 }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: dailyTokens[index] > 0
                                        onEntered: dayHovered(index)
                                        onExited: dayHovered(-1)
                                    }
                                }

                                StyledText {
                                    id: dayLabel
                                    text: root.dayLabels[index]
                                    font.pixelSize: 10
                                    color: index === hoverDayProp
                                        ? Theme.primary
                                        : index === OpenCodeUsageState.todayIndex ? Theme.primary : Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }
            }

            // Tooltip on hover
            Rectangle {
                id: chartTooltip
                visible: hoverDayProp >= 0 && dailyTokens[hoverDayProp] > 0
                z: 10

                x: {
                    var colW = (chartRow.width - 6 * 4) / 7
                    var cx = hoverDayProp * (colW + 4) + colW / 2 - width / 2
                    var chartX = chartRow.mapToItem(chartTooltip.parent, 0, 0).x
                    var raw = chartX + cx
                    return Math.max(Theme.spacingM, Math.min(raw, parent.width - width - Theme.spacingM))
                }
                y: -height - 2

                width: tooltipCol.width + Theme.spacingS * 2
                height: tooltipCol.height + Theme.spacingXS * 2
                radius: 4
                color: Theme.surfaceContainer

                Column {
                    id: tooltipCol
                    anchors.centerIn: parent
                    spacing: 1

                    StyledText {
                        text: hoverDayProp >= 0 ? OpenCodeUsageState.formatTokens(dailyTokens[hoverDayProp]) : ""
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        visible: hoverDayProp >= 0 && dailyCosts[hoverDayProp] > 0
                        text: hoverDayProp >= 0 ? formatCost(dailyCosts[hoverDayProp]) : ""
                        font.pixelSize: 11
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        // Model breakdown card
        StyledRect {
            width: parent.width
            height: modelCardCol.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainerHigh
            visible: modelsList.count > 0

            Column {
                id: modelCardCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    text: root.tr("Models This Week")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                Column {
                    id: modelCol
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: modelsList
                        delegate: Column {
                            width: modelCol.width
                            spacing: 3

                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: OpenCodeUsageState.shortModelName(modelName)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: OpenCodeUsageState.formatTokens(modelTokens)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Theme.surfaceVariant

                                Rectangle {
                                    width: weekTokens > 0
                                        ? parent.width * Math.min(modelTokens / weekTokens, 1)
                                        : 0
                                    height: parent.height
                                    radius: 2
                                    color: Theme.primary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Popout ---

    popoutContent: Component {
        PopoutComponent {
            headerText: root.tr("OpenCode Usage")
            detailsText: {
                var parts = []
                if (OpenCodeUsageState.rateLimitTier) parts.push(root.tr("Anthropic") + " \u00b7 " + OpenCodeUsageState.formatTier(OpenCodeUsageState.rateLimitTier))
                if (OpenCodeUsageState.geminiMonthTokens > 0) parts.push(root.tr("Gemini"))
                if (OpenCodeUsageState.opencodeMonthTokens > 0) parts.push(root.tr("OpenCode"))
                return parts.join("  |  ")
            }
            showCloseButton: true

            Flickable {
                width: parent.width
                height: Math.min(contentHeight, 700)
                contentHeight: mainCol.implicitHeight + Theme.spacingL
                clip: true
                interactive: contentHeight > height

                Column {
                    id: mainCol
                    width: parent.width - Theme.spacingM * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingL

                    // --- Refresh button ---
                    Row {
                        width: parent.width
                        layoutDirection: Qt.RightToLeft

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
                                    color: OpenCodeUsageState.isLoading ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter

                                    RotationAnimation on rotation {
                                        running: OpenCodeUsageState.isLoading
                                        from: 0
                                        to: 360
                                        duration: 1000
                                        loops: Animation.Infinite
                                    }
                                }

                                StyledText {
                                    text: OpenCodeUsageState.isLoading ? root.tr("Refreshing...") : root.tr("Refresh")
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
                                enabled: !OpenCodeUsageState.isLoading
                                onClicked: {
                                    OpenCodeUsageState.isLoading = true
                                    if (!OpenCodeUsageState.forceRefreshProcess.running)
                                        OpenCodeUsageState.forceRefreshProcess.running = true
                                }
                            }
                        }
                    }

                    // --- Not connected warning ---
                    StyledRect {
                        width: parent.width
                        height: authWarningCol.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: OpenCodeUsageState.noProviderData

                        Column {
                            id: authWarningCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingM

                            Row {
                                spacing: Theme.spacingS
                                width: parent.width

                                DankIcon {
                                    name: "warning"
                                    size: 16
                                    color: Theme.warning
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: root.tr("Not authenticated")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: root.tr("No provider data found. Run opencode auth login to authenticate with Anthropic.")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }

                            DankButton {
                                width: parent.width
                                text: OpenCodeUsageState.claudeAuthRunning ? root.tr("Running...") : root.tr("opencode auth login")
                                enabled: !OpenCodeUsageState.claudeAuthRunning
                                onClicked: {
                                    if (!OpenCodeUsageState.claudeAuthRunning)
                                        OpenCodeUsageState.claudeAuthProcess.running = true
                                }
                            }
                        }
                    }

                    // --- Stale data warning ---
                    StyledRect {
                        width: parent.width
                        height: staleWarningCol.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: OpenCodeUsageState.dataStale && !OpenCodeUsageState.noProviderData

                        Column {
                            id: staleWarningCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingM

                            Row {
                                spacing: Theme.spacingS
                                width: parent.width

                                DankIcon {
                                    name: "schedule"
                                    size: 16
                                    color: Theme.warning
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: root.tr("Data outdated")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: Theme.warning
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: root.tr("Usage data could not be refreshed. API may be unreachable or credentials expired.")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }

                            DankButton {
                                width: parent.width
                                text: OpenCodeUsageState.claudeAuthRunning ? root.tr("Running...") : root.tr("Re-authenticate")
                                enabled: !OpenCodeUsageState.claudeAuthRunning
                                onClicked: {
                                    if (!OpenCodeUsageState.claudeAuthRunning)
                                        OpenCodeUsageState.claudeAuthProcess.running = true
                                }
                            }
                        }
                    }

                    // --- Provider Tabs ---

                    // Tab bar
                    Row {
                        width: parent.width
                        spacing: 0
                        visible: !OpenCodeUsageState.noProviderData

                        Repeater {
                            model: tabModel
                            delegate: Rectangle {
                                width: parent.width / tabModel.count
                                height: 36
                                color: OpenCodeUsageState.selectedTab === index ? Theme.surfaceContainerHigh : (tabHover.containsMouse ? Theme.surfaceContainerLow : "transparent")
                                radius: Theme.cornerRadius
                                opacity: model.available ? 1.0 : 0.35

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: model.icon
                                        size: 14
                                        color: OpenCodeUsageState.selectedTab === index ? Theme.primary : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: model.label
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: OpenCodeUsageState.selectedTab === index ? Font.DemiBold : Font.Normal
                                        color: OpenCodeUsageState.selectedTab === index ? Theme.primary : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: tabHover
                                    anchors.fill: parent
                                    enabled: model.available
                                    hoverEnabled: model.available
                                    cursorShape: model.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: OpenCodeUsageState.selectedTab = index
                                }
                            }
                        }
                    }

                    // Tab content
                    Column {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: !OpenCodeUsageState.noProviderData

                        // --- Anthropic Tab ---
                        Column {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: OpenCodeUsageState.selectedTab === 0

                            // 5h rate window
                            Column {
                                width: parent.width
                                spacing: Theme.spacingM
                                visible: OpenCodeUsageState.fiveHourUtil !== 0

                                StyledRect {
                                    width: parent.width
                                    height: fiveHourContent.implicitHeight + Theme.spacingS * 2
                                    color: Theme.surfaceContainerHigh

                                    Row {
                                        id: fiveHourContent
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingS
                                        spacing: Theme.spacingM

                                        Canvas {
                                            id: fiveHourRing
                                            width: 80
                                            height: 80
                                            anchors.verticalCenter: parent.verticalCenter
                                            renderStrategy: Canvas.Cooperative

                                            property real percent: OpenCodeUsageState.fiveHourUtil
                                            onPercentChanged: requestPaint()

                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.reset()
                                                var cx = width / 2, cy = height / 2, r = 30, lw = 6

                                                ctx.beginPath()
                                                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                                ctx.lineWidth = lw
                                                ctx.strokeStyle = Theme.surfaceVariant
                                                ctx.stroke()

                                                var pct = percent / 100
                                                if (pct > 0) {
                                                    ctx.beginPath()
                                                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                                                    ctx.lineWidth = lw
                                                    ctx.strokeStyle = OpenCodeUsageState.progressColor(percent)
                                                    ctx.lineCap = "round"
                                                    ctx.stroke()
                                                }
                                            }

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: OpenCodeUsageState.fiveHourUtil < 0 ? "N/A" : Math.round(OpenCodeUsageState.fiveHourUtil) + "%"
                                                font.pixelSize: Theme.fontSizeLarge
                                                font.weight: Font.DemiBold
                                                color: OpenCodeUsageState.fiveHourUtil < 0 ? Theme.surfaceVariantText : Theme.surfaceText
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.spacingXS

                                            StyledText {
                                                text: root.tr("5h Rate Window")
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.Medium
                                                color: Theme.surfaceText
                                            }
                                            StyledText {
                                                text: OpenCodeUsageState.fiveHourUtil < 0 ? root.tr("Data unavailable") : (OpenCodeUsageState.fiveHourCountdown ? root.tr("Resets in") + " " + OpenCodeUsageState.fiveHourCountdown : OpenCodeUsageState.dataStale ? root.tr("Data outdated") : "")
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: OpenCodeUsageState.fiveHourUtil < 0 || OpenCodeUsageState.dataStale ? Theme.warning : Theme.surfaceVariantText
                                            }
                                        }
                                    }
                                }
                            }

                            ProviderStats {
                                visible: OpenCodeUsageState.anthropicMonthTokens > 0 || OpenCodeUsageState.fiveHourUtil > 0
                                providerName: root.tr("Anthropic")
                                weekTokens: OpenCodeUsageState.anthropicWeekTokens
                                monthTokens: OpenCodeUsageState.anthropicMonthTokens
                                todayCost: OpenCodeUsageState.anthropicTodayCost
                                weekCost: OpenCodeUsageState.anthropicWeekCost
                                monthCost: OpenCodeUsageState.anthropicMonthCost
                                dailyTokens: OpenCodeUsageState.anthropicDaily
                                dailyCosts: OpenCodeUsageState.anthropicDailyCosts
                                maxDaily: OpenCodeUsageState.maxDailyAnthropic
                                modelsList: OpenCodeUsageState.anthropicModels
                                hoverDayProp: OpenCodeUsageState.hoveredDayAnthropic
                                onDayHovered: function(dayIndex) { OpenCodeUsageState.hoveredDayAnthropic = dayIndex }
                            }
                        }

                        // --- Gemini Tab ---
                        ProviderStats {
                            width: parent.width
                            visible: OpenCodeUsageState.selectedTab === 1
                            providerName: root.tr("Gemini")
                            weekTokens: OpenCodeUsageState.geminiWeekTokens
                            monthTokens: OpenCodeUsageState.geminiMonthTokens
                            todayCost: OpenCodeUsageState.geminiTodayCost
                            weekCost: OpenCodeUsageState.geminiWeekCost
                            monthCost: OpenCodeUsageState.geminiMonthCost
                            dailyTokens: OpenCodeUsageState.geminiDaily
                            dailyCosts: OpenCodeUsageState.geminiDailyCosts
                            maxDaily: OpenCodeUsageState.maxDailyGemini
                            modelsList: OpenCodeUsageState.geminiModels
                            hoverDayProp: OpenCodeUsageState.hoveredDayGemini
                            onDayHovered: function(dayIndex) { OpenCodeUsageState.hoveredDayGemini = dayIndex }
                        }

                        // --- OpenCode Tab ---
                        ProviderStats {
                            width: parent.width
                            visible: OpenCodeUsageState.selectedTab === 2
                            providerName: root.tr("OpenCode")
                            weekTokens: OpenCodeUsageState.opencodeWeekTokens
                            monthTokens: OpenCodeUsageState.opencodeMonthTokens
                            todayCost: OpenCodeUsageState.opencodeTodayCost
                            weekCost: OpenCodeUsageState.opencodeWeekCost
                            monthCost: OpenCodeUsageState.opencodeMonthCost
                            dailyTokens: OpenCodeUsageState.opencodeDaily
                            dailyCosts: OpenCodeUsageState.opencodeDailyCosts
                            maxDaily: OpenCodeUsageState.maxDailyOpenCode
                            modelsList: OpenCodeUsageState.opencodeModels
                            hoverDayProp: OpenCodeUsageState.hoveredDayOpenCode
                            onDayHovered: function(dayIndex) { OpenCodeUsageState.hoveredDayOpenCode = dayIndex }
                        }
                    }

                    // --- All-time footer card ---
                    StyledRect {
                        width: parent.width
                        height: allTimeRow.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: OpenCodeUsageState.alltimeSessions > 0 || OpenCodeUsageState.alltimeMessages > 0

                        Row {
                            id: allTimeRow
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "calendar_today"
                                size: 14
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: {
                                    var parts = []
                                    if (OpenCodeUsageState.firstSession && OpenCodeUsageState.firstSession !== "unknown")
                                        parts.push(root.tr("Since") + " " + OpenCodeUsageState.firstSession)
                                    parts.push(OpenCodeUsageState.alltimeSessions + " " + root.tr("sessions"))
                                    parts.push(OpenCodeUsageState.alltimeMessages.toLocaleString() + " " + root.tr("msgs"))
                                    return parts.join("  \u00b7  ")
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
