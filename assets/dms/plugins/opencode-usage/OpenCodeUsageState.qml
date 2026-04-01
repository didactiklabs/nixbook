pragma Singleton
import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

QtObject {
    id: root

    // Settings
    property int refreshInterval: 120000 // 2 min default, updated by widget

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
    property ListModel anthropicModels: ListModel { }

    // Gemini State
    property real geminiWeekTokens: 0
    property real geminiMonthTokens: 0
    property real geminiTodayCost: 0
    property real geminiWeekCost: 0
    property real geminiMonthCost: 0
    property var geminiDaily: [0, 0, 0, 0, 0, 0, 0]
    property var geminiDailyCosts: [0, 0, 0, 0, 0, 0, 0]
    property ListModel geminiModels: ListModel { }

    // OpenCode State
    property real opencodeWeekTokens: 0
    property real opencodeMonthTokens: 0
    property real opencodeTodayCost: 0
    property real opencodeWeekCost: 0
    property real opencodeMonthCost: 0
    property var opencodeDaily: [0, 0, 0, 0, 0, 0, 0]
    property var opencodeDailyCosts: [0, 0, 0, 0, 0, 0, 0]
    property ListModel opencodeModels: ListModel { }
    property int selectedTab: 0

    // Chart hover state
    property int hoveredDayAnthropic: -1
    property int hoveredDayGemini: -1
    property int hoveredDayOpenCode: -1

    // Today's index in the calendar week (0=Monday, 6=Sunday)
    property int todayIndex: {
        void(countdownNow)
        var dow = new Date().getDay()
        return dow === 0 ? 6 : dow - 1
    }

    // Derived
    property real maxDailyAnthropic: Math.max.apply(null, anthropicDaily) || 1
    property real maxDailyGemini: Math.max.apply(null, geminiDaily) || 1
    property real maxDailyOpenCode: Math.max.apply(null, opencodeDaily) || 1
    property bool isLoading: true

    // Live countdown
    property real countdownNow: Date.now()

    property string fiveHourCountdown: {
        if (!fiveHourReset) return ""
        var resetMs = new Date(fiveHourReset).getTime()
        var remaining = Math.max(0, resetMs - countdownNow)
        if (remaining <= 0) return "Resetting..."
        var hours = Math.floor(remaining / 3600000)
        var mins = Math.floor((remaining % 3600000) / 60000)
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
    }

    property string sevenDayCountdown: {
        if (!sevenDayReset) return ""
        var resetMs = new Date(sevenDayReset).getTime()
        var remaining = Math.max(0, resetMs - countdownNow)
        if (remaining <= 0) return "Resetting..."
        var days = Math.floor(remaining / 86400000)
        var hours = Math.floor((remaining % 86400000) / 3600000)
        var mins = Math.floor((remaining % 3600000) / 60000)
        if (days > 0) return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
    }

    // True when no provider data is available (after initial load)
    property bool noProviderData: !isLoading && rateLimitTier === "" && anthropicMonthTokens <= 0 && geminiMonthTokens <= 0 && opencodeMonthTokens <= 0

    // Refresh epoch (increments on each data fetch)
    property int refreshEpoch: 0

    // Claude auth login state
    property bool claudeAuthRunning: false

    property string scriptPath: PluginService.pluginDirectory + "/opencodeUsage/get-opencode-usage"

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
        var useEur = usdEurRate > 0
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

    function updateTabs() {
        // no-op: tabs are managed by the widget, but we keep selectedTab valid
        if (selectedTab < 0) selectedTab = 0
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
        case "ANTHROPIC_MODELS": fillModelList(root.anthropicModels, val); break

        case "GEMINI_WEEK_TOKENS": root.geminiWeekTokens = parseFloat(val) || 0; break
        case "GEMINI_MONTH_TOKENS": root.geminiMonthTokens = parseFloat(val) || 0; break
        case "GEMINI_TODAY_COST": root.geminiTodayCost = parseFloat(val) || 0; break
        case "GEMINI_WEEK_COST": root.geminiWeekCost = parseFloat(val) || 0; break
        case "GEMINI_MONTH_COST": root.geminiMonthCost = parseFloat(val) || 0; break
        case "GEMINI_DAILY": root.geminiDaily = parseArray(val); break
        case "GEMINI_DAILY_COSTS": root.geminiDailyCosts = parseArray(val); break
        case "GEMINI_MODELS": fillModelList(root.geminiModels, val); break

        case "OPENCODE_WEEK_TOKENS": root.opencodeWeekTokens = parseFloat(val) || 0; break
        case "OPENCODE_MONTH_TOKENS": root.opencodeMonthTokens = parseFloat(val) || 0; break
        case "OPENCODE_TODAY_COST": root.opencodeTodayCost = parseFloat(val) || 0; break
        case "OPENCODE_WEEK_COST": root.opencodeWeekCost = parseFloat(val) || 0; break
        case "OPENCODE_MONTH_COST": root.opencodeMonthCost = parseFloat(val) || 0; break
        case "OPENCODE_DAILY": root.opencodeDaily = parseArray(val); break
        case "OPENCODE_DAILY_COSTS": root.opencodeDailyCosts = parseArray(val); break
        case "OPENCODE_MODELS": fillModelList(root.opencodeModels, val); break
        }
    }

    // --- Processes ---

    property Process claudeAuthProcess: Process {
        command: ["kitty", "--hold", "-e", "opencode", "auth", "login"]
        running: false
        onStarted: root.claudeAuthRunning = true
        onExited: (exitCode, exitStatus) => {
            root.claudeAuthRunning = false
            root.isLoading = true
            if (!root.forceRefreshProcess.running)
                root.forceRefreshProcess.running = true
        }
    }

    property Process usageProcess: Process {
        command: ["bash", root.scriptPath, String(Math.floor(root.refreshInterval / 1000))]
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

    property Process forceRefreshProcess: Process {
        command: ["bash", root.scriptPath, "0"]
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

    // --- Timers ---

    property Timer countdownTimer: Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now()
            var elapsed = now - root.countdownNow
            root.countdownNow = now
            if (elapsed > 120000 && !root.usageProcess.running) {
                root.usageProcess.running = true
            }
        }
    }

    property Timer refreshTimer: Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.usageProcess.running)
                root.usageProcess.running = true
        }
    }
}
