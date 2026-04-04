pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // --- Config (pushed from widget settings) ---
    property string apiUrl: ""
    property string apiToken: ""
    property string organizationId: ""
    property int refreshInterval: 30000

    // --- State ---
    property bool loading: false
    property bool hasActiveTimer: false
    property string activeTimerDescription: ""
    property string activeTimerProjectName: ""
    property string activeTimerProjectColor: ""
    property string activeTimerStart: ""
    property string activeTimerId: ""
    property string activeTimerProjectId: ""
    property int activeTimerDuration: 0

    property string lastEntryDescription: ""
    property string lastEntryProjectName: ""
    property string lastEntryProjectColor: ""
    property int lastEntryDuration: 0

    property ListModel projects: ListModel {}

    property string lastError: ""
    property bool configured: apiUrl !== "" && apiToken !== "" && organizationId !== ""

    // Build base API path: <apiUrl>/api/v1/organizations/<orgId>
    function orgApiBase() {
        var base = apiUrl.replace(/\/+$/, "")
        return base + "/api/v1/organizations/" + organizationId
    }

    // --- Helpers ---

    function formatDuration(seconds) {
        if (seconds <= 0) return "0:00"
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        var s = seconds % 60
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function liveDuration() {
        if (!hasActiveTimer || !activeTimerStart) return 0
        var startMs = new Date(activeTimerStart).getTime()
        var nowMs = Date.now()
        return Math.max(0, Math.floor((nowMs - startMs) / 1000))
    }

    // --- Live tick ---
    property real _tick: 0
    property Timer tickTimer: Timer {
        interval: 1000
        running: root.hasActiveTimer
        repeat: true
        onTriggered: {
            root.activeTimerDuration = root.liveDuration()
            root._tick++
        }
    }

    // --- Lookup helpers ---

    function projectNameById(id) {
        if (!id) return ""
        for (var i = 0; i < projects.count; i++) {
            if (projects.get(i).projectId === id)
                return projects.get(i).projectName
        }
        return ""
    }

    function projectColorById(id) {
        if (!id) return ""
        for (var i = 0; i < projects.count; i++) {
            if (projects.get(i).projectId === id)
                return projects.get(i).projectColor
        }
        return ""
    }

    // --- API: Fetch projects ---

    property Process fetchProjectsProcess: Process {
        command: []
        running: false
        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.parseProjects(fetchProjectsProcess.stdout.text)
            } else {
                root.lastError = "Failed to fetch projects (exit " + exitCode + ")"
            }
            // Chain: after projects, fetch entries
            root._startFetchEntries()
        }
    }

    function parseProjects(raw) {
        try {
            var resp = JSON.parse(raw)
            var items = resp.data || []
            root.projects.clear()
            for (var i = 0; i < items.length; i++) {
                root.projects.append({
                    projectId: items[i].id || "",
                    projectName: items[i].name || "",
                    projectColor: items[i].color || "#888888"
                })
            }
        } catch (e) {
            root.lastError = "Projects parse error: " + e.message
        }
    }

    // --- API: Fetch time entries ---

    property Process fetchEntriesProcess: Process {
        command: []
        running: false
        stdout: StdioCollector {}

        onExited: (exitCode) => {
            root.loading = false
            if (exitCode === 0) {
                root.parseTimeEntries(fetchEntriesProcess.stdout.text)
            } else {
                root.lastError = "Failed to fetch entries (exit " + exitCode + ")"
            }
        }
    }

    function _startFetchEntries() {
        fetchEntriesProcess.command = [
            "curl", "-s", "--max-time", "10",
            "-H", "Authorization: Bearer " + root.apiToken,
            "-H", "Accept: application/json",
            root.orgApiBase() + "/time-entries?limit=5&active=true"
        ]
        fetchEntriesProcess.running = true
    }

    // Also fetch recent completed entries separately
    property Process fetchRecentProcess: Process {
        command: []
        running: false
        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.parseRecentEntries(fetchRecentProcess.stdout.text)
            }
        }
    }

    function parseTimeEntries(raw) {
        try {
            var resp = JSON.parse(raw)
            var entries = resp.data || []

            var active = null
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].end === null || entries[i].end === undefined) {
                    active = entries[i]
                    break
                }
            }

            if (active) {
                root.hasActiveTimer = true
                root.activeTimerId = active.id || ""
                root.activeTimerDescription = active.description || ""
                root.activeTimerStart = active.start || ""
                root.activeTimerProjectId = active.project_id || ""
                root.activeTimerDuration = root.liveDuration()
                root.activeTimerProjectName = root.projectNameById(active.project_id)
                root.activeTimerProjectColor = root.projectColorById(active.project_id)
                root.lastError = ""
            } else {
                root.hasActiveTimer = false
                root.activeTimerId = ""
                root.activeTimerDescription = ""
                root.activeTimerStart = ""
                root.activeTimerProjectId = ""
                root.activeTimerDuration = 0
                root.activeTimerProjectName = ""
                root.activeTimerProjectColor = ""
                // Fetch recent completed entries
                fetchRecentProcess.command = [
                    "curl", "-s", "--max-time", "10",
                    "-H", "Authorization: Bearer " + root.apiToken,
                    "-H", "Accept: application/json",
                    root.orgApiBase() + "/time-entries?limit=1&active=false"
                ]
                fetchRecentProcess.running = true
            }

            root.lastError = ""
        } catch (e) {
            root.lastError = "Parse error: " + e.message
        }
    }

    function parseRecentEntries(raw) {
        try {
            var resp = JSON.parse(raw)
            var entries = resp.data || []
            if (entries.length > 0) {
                var last = entries[0]
                root.lastEntryDescription = last.description || ""
                root.lastEntryDuration = last.duration || 0
                root.lastEntryProjectName = root.projectNameById(last.project_id)
                root.lastEntryProjectColor = root.projectColorById(last.project_id)
            }
        } catch (e) {}
    }

    // --- API: Start timer ---

    property Process startTimerProcess: Process {
        command: []
        running: false
        stdout: StdioCollector {}

        onExited: (exitCode) => {
            root.refresh()
        }
    }

    function startTimer(projectId, description) {
        if (!root.configured) return
        var body = {
            project_id: projectId || null,
            description: description || "",
            billable: false,
            start: new Date().toISOString(),
            end: null,
            tags: []
        }
        startTimerProcess.command = [
            "curl", "-s", "--max-time", "10",
            "-X", "POST",
            "-H", "Authorization: Bearer " + root.apiToken,
            "-H", "Accept: application/json",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify(body),
            root.orgApiBase() + "/time-entries"
        ]
        startTimerProcess.running = true
    }

    // --- API: Stop timer ---

    property Process stopTimerProcess: Process {
        command: []
        running: false
        stdout: StdioCollector {}

        onExited: (exitCode) => {
            root.refresh()
        }
    }

    function stopTimer() {
        if (!root.configured || !root.activeTimerId) return
        var body = {
            start: root.activeTimerStart,
            end: new Date().toISOString()
        }
        stopTimerProcess.command = [
            "curl", "-s", "--max-time", "10",
            "-X", "PUT",
            "-H", "Authorization: Bearer " + root.apiToken,
            "-H", "Accept: application/json",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify(body),
            root.orgApiBase() + "/time-entries/" + root.activeTimerId
        ]
        stopTimerProcess.running = true
    }

    // --- Refresh ---

    function refresh() {
        if (!root.configured) return
        root.loading = true
        root.lastError = ""
        fetchProjectsProcess.command = [
            "curl", "-s", "--max-time", "10",
            "-H", "Authorization: Bearer " + root.apiToken,
            "-H", "Accept: application/json",
            root.orgApiBase() + "/projects"
        ]
        fetchProjectsProcess.running = true
    }

    // --- Auto refresh ---
    property Timer autoRefreshTimer: Timer {
        interval: root.refreshInterval
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
