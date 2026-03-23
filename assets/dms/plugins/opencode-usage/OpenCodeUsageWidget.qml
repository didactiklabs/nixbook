import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginComponent {
    id: root

    // i18n
    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) { return Tr.tr(key, lang) }

    // Calendar week labels: Monday to Sunday (fixed order)
    property int refreshEpoch: 0
    property var dayLabels: lang === "fr"
        ? ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]
        : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Settings
    property int refreshInterval: (pluginData.refreshInterval || 2) * 60000

    // API usage data (Anthropic)
    property string subscriptionType: ""
    property string rateLimitTier: ""
    property real fiveHourUtil: 0
    property string fiveHourReset: ""
    property real sevenDayUtil: 0
    property string sevenDayReset: ""
    property bool dataStale: false

    // Global
    property int weekMessages: 0
    property int weekSessions: 0
    property int alltimeSessions: 0
    property int alltimeMessages: 0
    property string firstSession: ""
    property real usdEurRate: 0

    // Anthropic State
    property real anthropicWeekTokens: 0
    property real anthropicMonthTokens: 0
    property real anthropicTodayCost: 0
    property real anthropicWeekCost: 0
    property real anthropicMonthCost: 0
    property var anthropicDaily: [0, 0, 0, 0, 0, 0, 0]
    property var anthropicDailyCosts: [0, 0, 0, 0, 0, 0, 0]
    ListModel { id: anthropicModels }

    // Gemini State
    property real geminiWeekTokens: 0
    property real geminiMonthTokens: 0
    property real geminiTodayCost: 0
    property real geminiWeekCost: 0
    property real geminiMonthCost: 0
    property var geminiDaily: [0, 0, 0, 0, 0, 0, 0]
    property var geminiDailyCosts: [0, 0, 0, 0, 0, 0, 0]
    ListModel { id: geminiModels }

    // Chart hover state
    property int hoveredDayAnthropic: -1
    property int hoveredDayGemini: -1

    // Today's index in the calendar week (0=Monday, 6=Sunday)
    property int todayIndex: {
        void(countdownNow)
        var dow = new Date().getDay() // 0=Sunday, 6=Saturday
        return dow === 0 ? 6 : dow - 1
    }

    // Derived
    property real maxDailyAnthropic: Math.max.apply(null, anthropicDaily) || 1
    property real maxDailyGemini: Math.max.apply(null, geminiDaily) || 1
    property bool isLoading: true

    // Always show the widget (disconnect icon when no data, normal content otherwise)
    _visibilityOverride: true
    _visibilityOverrideValue: true

    // Live countdown
    property real countdownNow: Date.now()

    property string fiveHourCountdown: {
        if (!fiveHourReset) return ""
        var resetMs = new Date(fiveHourReset).getTime()
        var remaining = Math.max(0, resetMs - countdownNow)
        if (remaining <= 0) return tr("Resetting...")
        var hours = Math.floor(remaining / 3600000)
        var mins = Math.floor((remaining % 3600000) / 60000)
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
    }

    property string sevenDayCountdown: {
        if (!sevenDayReset) return ""
        var resetMs = new Date(sevenDayReset).getTime()
        var remaining = Math.max(0, resetMs - countdownNow)
        if (remaining <= 0) return tr("Resetting...")
        var days = Math.floor(remaining / 86400000)
        var hours = Math.floor((remaining % 86400000) / 3600000)
        var mins = Math.floor((remaining % 3600000) / 60000)
        if (days > 0) return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now()
            var elapsed = now - root.countdownNow
            root.countdownNow = now
            if (elapsed > 120000 && !usageProcess.running) {
                usageProcess.running = true
            }
        }
    }

    property string scriptPath: PluginService.pluginDirectory + "/opencodeUsage/get-opencode-usage"

    popoutWidth: 380
    popoutHeight: {
        var h = 120 // Header & Footer
        if (root.noProviderData) h += 160
        if (root.rateLimitTier) h += 240
        if (root.anthropicMonthTokens > 0) h += 180 + (anthropicModels.count > 0 ? 50 + anthropicModels.count * 20 : 0)
        if (root.geminiMonthTokens > 0) h += 180 + (geminiModels.count > 0 ? 50 + geminiModels.count * 20 : 0)
        return Math.min(800, h)
    }

    // --- Helpers ---

    function formatTokens(n) {
        if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000) return (n / 1000).toFixed(1) + "K"
        return Math.round(n).toString()
    }

    function shortModelName(name) {
        if (!name || name.length === 0) return name
        return name.charAt(0).toUpperCase() + name.slice(1)
    }

    function progressColor(pct) {
        if (pct > 80) return Theme.error
        if (pct > 50) return Theme.warning
        return Theme.primary
    }

    function formatCost(usd) {
        var useEur = lang === "fr" && usdEurRate > 0
        var n = useEur ? usd * usdEurRate : usd
        var sym = useEur ? "" : "$"
        var suffix = useEur ? " \u20ac" : ""
        if (n >= 1000) return sym + (n / 1000).toFixed(1) + "K" + suffix
        if (n >= 100) return sym + Math.round(n) + suffix
        if (n >= 10) return sym + n.toFixed(1) + suffix
        return sym + n.toFixed(2) + suffix
    }

    function formatTier(tier) {
        if (tier.indexOf("max_20x") >= 0) return "Max 20x"
        if (tier.indexOf("max_5x") >= 0) return "Max 5x"
        if (tier.indexOf("pro") >= 0) return "Pro"
        if (tier.indexOf("free") >= 0) return "Free"
        return tier
    }

    function fillModelList(listModel, val) {
        listModel.clear()
        if (val && val.length > 0) {
            var pairs = val.split(",")
            for (var i = 0; i < pairs.length; i++) {
                var kv = pairs[i].split(":")
                if (kv.length === 2)
                    listModel.append({ modelName: kv[0], modelTokens: parseInt(kv[1]) || 0 })
            }
        }
    }

    function parseArray(val) {
        var parts = val.split(",")
        var arr = []
        for (var j = 0; j < 7; j++)
            arr.push(j < parts.length ? (parseFloat(parts[j]) || 0) : 0)
        return arr
    }

    function parseLine(line) {
        var idx = line.indexOf("=")
        if (idx < 0) return
        var key = line.substring(0, idx)
        var val = line.substring(idx + 1)

        switch (key) {
        case "SUBSCRIPTION_TYPE": root.subscriptionType = val; break
        case "RATE_LIMIT_TIER": root.rateLimitTier = val; break
        case "FIVE_HOUR_UTIL": root.fiveHourUtil = parseFloat(val) || 0; break
        case "FIVE_HOUR_RESET": root.fiveHourReset = val; break
        case "SEVEN_DAY_UTIL": root.sevenDayUtil = parseFloat(val) || 0; break
        case "SEVEN_DAY_RESET": root.sevenDayReset = val; break
        case "EXTRA_USAGE_ENABLED": break
        case "DATA_STALE": root.dataStale = val === "true"; break
        case "CACHE_AGE": break
        case "WEEK_MESSAGES": root.weekMessages = parseInt(val) || 0; break
        case "WEEK_SESSIONS": root.weekSessions = parseInt(val) || 0; break
        case "ALLTIME_SESSIONS": root.alltimeSessions = parseInt(val) || 0; break
        case "ALLTIME_MESSAGES": root.alltimeMessages = parseInt(val) || 0; break
        case "FIRST_SESSION": root.firstSession = val; break
        case "USD_EUR_RATE": root.usdEurRate = parseFloat(val) || 0; break
        
        case "ANTHROPIC_WEEK_TOKENS": root.anthropicWeekTokens = parseFloat(val) || 0; break
        case "ANTHROPIC_MONTH_TOKENS": root.anthropicMonthTokens = parseFloat(val) || 0; break
        case "ANTHROPIC_TODAY_COST": root.anthropicTodayCost = parseFloat(val) || 0; break
        case "ANTHROPIC_WEEK_COST": root.anthropicWeekCost = parseFloat(val) || 0; break
        case "ANTHROPIC_MONTH_COST": root.anthropicMonthCost = parseFloat(val) || 0; break
        case "ANTHROPIC_DAILY": root.anthropicDaily = parseArray(val); break
        case "ANTHROPIC_DAILY_COSTS": root.anthropicDailyCosts = parseArray(val); break
        case "ANTHROPIC_MODELS": fillModelList(anthropicModels, val); break
        
        case "GEMINI_WEEK_TOKENS": root.geminiWeekTokens = parseFloat(val) || 0; break
        case "GEMINI_MONTH_TOKENS": root.geminiMonthTokens = parseFloat(val) || 0; break
        case "GEMINI_TODAY_COST": root.geminiTodayCost = parseFloat(val) || 0; break
        case "GEMINI_WEEK_COST": root.geminiWeekCost = parseFloat(val) || 0; break
        case "GEMINI_MONTH_COST": root.geminiMonthCost = parseFloat(val) || 0; break
        case "GEMINI_DAILY": root.geminiDaily = parseArray(val); break
        case "GEMINI_DAILY_COSTS": root.geminiDailyCosts = parseArray(val); break
        case "GEMINI_MODELS": fillModelList(geminiModels, val); break
        }
    }

    // Claude auth login state
    property bool claudeAuthRunning: false

    Process {
        id: claudeAuthProcess
        command: ["kitty", "--hold", "-e", "claude", "auth", "login"]
        running: false
        onStarted: root.claudeAuthRunning = true
        onExited: (exitCode, exitStatus) => {
            root.claudeAuthRunning = false
            if (!usageProcess.running)
                usageProcess.running = true
        }
    }

    // --- Data fetching ---

    Process {
        id: usageProcess
        command: ["bash", root.scriptPath]
        running: false

        stdout: SplitParser {
            onRead: data => root.parseLine(data.trim())
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            if (exitCode === 0) {
                root.refreshEpoch++
            }
        }
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!usageProcess.running)
                usageProcess.running = true
        }
    }

    // --- Taskbar pills ---

    // True when no provider data is available (after initial load)
    property bool noProviderData: !isLoading && rateLimitTier === "" && anthropicMonthTokens <= 0 && geminiMonthTokens <= 0

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingM

            // Disconnected icon: shown when no data is available
            DankIcon {
                name: "signal_disconnected"
                size: 14
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.noProviderData
            }

            // Anthropic
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: root.fiveHourUtil !== 0 || root.rateLimitTier !== ""

                DankIcon {
                    name: "warning"
                    size: 12
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.dataStale
                }

                Canvas {
                    id: hRing
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    renderStrategy: Canvas.Cooperative

                    property real percent: root.fiveHourUtil
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
                            ctx.strokeStyle = root.progressColor(percent)
                            ctx.lineCap = "round"
                            ctx.stroke()
                        }
                    }
                }

                StyledText {
                    text: root.fiveHourUtil < 0 ? "N/A" : Math.round(root.fiveHourUtil) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.fiveHourUtil < 0 ? Theme.surfaceVariantText : Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.fiveHourCountdown ? "\u00b7 " + root.fiveHourCountdown : ""
                    visible: root.fiveHourCountdown !== ""
                    font.pixelSize: 9
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Gemini
            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: root.geminiWeekTokens > 0

                DankIcon {
                    name: "smart_toy"
                    size: 14
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.formatCost(root.geminiTodayCost)
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
                visible: root.noProviderData
            }

            // Anthropic
            Column {
                spacing: Theme.spacingXS || 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.fiveHourUtil !== 0 || root.rateLimitTier !== ""

                DankIcon {
                    name: "warning"
                    size: 12
                    color: Theme.warning
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.dataStale
                }

                Canvas {
                    id: vRing
                    width: 20
                    height: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    renderStrategy: Canvas.Cooperative

                    property real percent: root.fiveHourUtil
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
                            ctx.strokeStyle = root.progressColor(percent)
                            ctx.lineCap = "round"
                            ctx.stroke()
                        }
                    }
                }

                StyledText {
                    text: root.fiveHourUtil < 0 ? "N/A" : Math.round(root.fiveHourUtil) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.fiveHourUtil < 0 ? Theme.surfaceVariantText : Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.fiveHourCountdown || ""
                    visible: root.fiveHourCountdown !== ""
                    font.pixelSize: 9
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            // Gemini
            Column {
                spacing: Theme.spacingXS || 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.geminiWeekTokens > 0

                DankIcon {
                    name: "smart_toy"
                    size: 14
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.formatCost(root.geminiTodayCost)
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
            text: root.formatTokens(monthTokens) + " \u2022 " + root.formatCost(monthCost) + " / " + root.tr("Month")
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
                            text: root.formatTokens(dailyTokens[root.todayIndex])
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.primary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        StyledText {
                            text: root.formatCost(todayCost)
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
                            text: root.formatTokens(weekTokens)
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        StyledText {
                            text: root.formatCost(weekCost)
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
                                            : index === root.todayIndex ? Theme.primary : Theme.surfaceVariant
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
                                        : index === root.todayIndex ? Theme.primary : Theme.surfaceVariantText
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
                        text: hoverDayProp >= 0 ? root.formatTokens(dailyTokens[hoverDayProp]) : ""
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        visible: hoverDayProp >= 0 && dailyCosts[hoverDayProp] > 0
                        text: hoverDayProp >= 0 ? root.formatCost(dailyCosts[hoverDayProp]) : ""
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
                                    text: root.shortModelName(modelName)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    text: root.formatTokens(modelTokens)
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
                if (root.rateLimitTier) parts.push(root.tr("Anthropic") + " \u00b7 " + root.formatTier(root.rateLimitTier))
                if (root.geminiMonthTokens > 0) parts.push(root.tr("Gemini"))
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

                    // --- Not connected warning ---
                    StyledRect {
                        width: parent.width
                        height: authWarningCol.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: root.noProviderData

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
                                text: root.tr("No provider data found. Run claude auth login to authenticate with Anthropic.")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }

                            DankButton {
                                width: parent.width
                                text: root.claudeAuthRunning ? root.tr("Running...") : root.tr("claude auth login")
                                enabled: !root.claudeAuthRunning
                                onClicked: {
                                    if (!root.claudeAuthRunning)
                                        claudeAuthProcess.running = true
                                }
                            }
                        }
                    }

                    // --- Stale data warning ---
                    StyledRect {
                        width: parent.width
                        height: staleWarningCol.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: root.dataStale && !root.noProviderData

                        Column {
                            id: staleWarningCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

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
                        }
                    }

                    // --- Anthropic Limits ---
                    Column {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: root.fiveHourUtil !== 0

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

                                    property real percent: root.fiveHourUtil
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
                                            ctx.strokeStyle = root.progressColor(percent)
                                            ctx.lineCap = "round"
                                            ctx.stroke()
                                        }
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: root.fiveHourUtil < 0 ? "N/A" : Math.round(root.fiveHourUtil) + "%"
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Font.DemiBold
                                        color: root.fiveHourUtil < 0 ? Theme.surfaceVariantText : Theme.surfaceText
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
                                        text: root.fiveHourUtil < 0 ? root.tr("Data unavailable") : (root.fiveHourCountdown ? root.tr("Resets in") + " " + root.fiveHourCountdown : root.dataStale ? root.tr("Data outdated") : "")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: root.fiveHourUtil < 0 || root.dataStale ? Theme.warning : Theme.surfaceVariantText
                                    }
                                }
                            }
                        }
                    }

                    // --- Anthropic Stats ---
                    ProviderStats {
                        visible: root.anthropicMonthTokens > 0 || root.fiveHourUtil > 0
                        providerName: root.tr("Anthropic")
                        weekTokens: root.anthropicWeekTokens
                        monthTokens: root.anthropicMonthTokens
                        todayCost: root.anthropicTodayCost
                        weekCost: root.anthropicWeekCost
                        monthCost: root.anthropicMonthCost
                        dailyTokens: root.anthropicDaily
                        dailyCosts: root.anthropicDailyCosts
                        maxDaily: root.maxDailyAnthropic
                        modelsList: anthropicModels
                        hoverDayProp: root.hoveredDayAnthropic
                        onDayHovered: function(dayIndex) { root.hoveredDayAnthropic = dayIndex }
                    }

                    // Divider
                    Rectangle {
                        width: parent.width - Theme.spacingXL * 2
                        height: 1
                        color: Theme.surfaceVariant
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.anthropicMonthTokens > 0 && root.geminiMonthTokens > 0
                    }

                    // --- Gemini Stats ---
                    ProviderStats {
                        visible: root.geminiMonthTokens > 0
                        providerName: root.tr("Gemini")
                        weekTokens: root.geminiWeekTokens
                        monthTokens: root.geminiMonthTokens
                        todayCost: root.geminiTodayCost
                        weekCost: root.geminiWeekCost
                        monthCost: root.geminiMonthCost
                        dailyTokens: root.geminiDaily
                        dailyCosts: root.geminiDailyCosts
                        maxDaily: root.maxDailyGemini
                        modelsList: geminiModels
                        hoverDayProp: root.hoveredDayGemini
                        onDayHovered: function(dayIndex) { root.hoveredDayGemini = dayIndex }
                    }

                    // --- All-time footer card ---
                    StyledRect {
                        width: parent.width
                        height: allTimeRow.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        visible: root.alltimeSessions > 0 || root.alltimeMessages > 0

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
                                    if (root.firstSession && root.firstSession !== "unknown")
                                        parts.push(root.tr("Since") + " " + root.firstSession)
                                    parts.push(root.alltimeSessions + " " + root.tr("sessions"))
                                    parts.push(root.alltimeMessages.toLocaleString() + " " + root.tr("msgs"))
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
