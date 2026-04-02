pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // State
    property bool loading: false
    property string lastError: ""
    property bool ghOk: true
    property bool authOk: true

    property int prCount: 0
    property int issuesCount: 0
    property ListModel prItems: ListModel {}
    property ListModel issueItems: ListModel {}

    function asBool(v, defaultValue) {
        if (v === undefined || v === null)
            return defaultValue;
        if (typeof v === "boolean")
            return v;
        if (typeof v === "string")
            return v.toLowerCase() === "true";
        return !!v;
    }

    function setError(msg) {
        root.lastError = msg || "";
    }

    function parseJsonArrayLen(stdout) {
        const raw = (stdout || "").trim();
        if (!raw) return 0;

        try {
            const data = JSON.parse(raw);
            if (Array.isArray(data)) return data.length;
            if (Array.isArray(data.items)) return data.items.length;
            if (Array.isArray(data.data)) return data.data.length;
            if (typeof data === "object" && data !== null) {
                if (typeof data.total_count === "number") return data.total_count;
                if (typeof data.total === "number") return data.total;
            }
        } catch (e) {}

        try {
            const lines = raw.split(/\r?\n/).map(s => s.trim()).filter(s => s.length > 0);
            var count = 0;
            for (var i = 0; i < lines.length; i++) {
                try {
                    const obj = JSON.parse(lines[i]);
                    if (obj !== null && typeof obj === "object") count++;
                } catch (e) {}
            }
            if (count > 0) return count;
        } catch (e) {}

        const num = parseInt(raw, 10);
        if (!isNaN(num)) return num;

        return 0;
    }

    function fillItemsFromJson(listModel, stdout) {
        listModel.clear();
        const raw = (stdout || "").trim();
        if (!raw) return;

        try {
            const data = JSON.parse(raw);
            if (Array.isArray(data)) {
                for (var i = 0; i < data.length; i++) {
                    if (data[i] && typeof data[i] === "object") {
                        var repo = data[i].repository || {};
                        listModel.append({
                            itemNumber: data[i].number || 0,
                            itemTitle: data[i].title || "",
                            itemRepo: repo.nameWithOwner || ""
                        });
                    }
                }
            }
        } catch (e) {}
    }

    function fillItemsFromJsonMerge(listModel, stdout) {
        const raw = (stdout || "").trim();
        if (!raw) return;

        try {
            const data = JSON.parse(raw);
            if (Array.isArray(data)) {
                for (var i = 0; i < data.length; i++) {
                    if (data[i] && typeof data[i] === "object") {
                        var repo = data[i].repository || {};
                        var num = data[i].number || 0;
                        var repoName = repo.nameWithOwner || "";
                        var exists = false;
                        for (var j = 0; j < listModel.count; j++) {
                            if (listModel.get(j).itemNumber === num && listModel.get(j).itemRepo === repoName) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists) {
                            listModel.append({
                                itemNumber: num,
                                itemTitle: data[i].title || "",
                                itemRepo: repoName
                            });
                        }
                    }
                }
            }
        } catch (e) {}
    }

    // --- Command arguments ---
    property string _ghBinary: ""
    property string _org: ""
    property bool _showPRs: true
    property bool _showIssues: true
    property bool _showReviewer: true

    function refresh(ghBinary, org, showPRs, showIssues, showReviewer) {
        root.loading = true;
        root.setError("");
        root.ghOk = true;
        root.authOk = true;
        root._ghBinary = ghBinary;
        root._org = (org || "").trim();
        root._showPRs = showPRs;
        root._showIssues = showIssues;
        root._showReviewer = showReviewer;

        ghVersionProcess.command = [ghBinary, "--version"];
        ghVersionProcess.running = true;
    }

    // gh --version
    property Process ghVersionProcess: Process {
        command: []
        running: false

        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.ghOk = false;
                root.authOk = false;
                root.loading = false;
                root.prCount = 0;
                root.issuesCount = 0;
                root.prItems.clear();
                root.issueItems.clear();
                root.setError("Could not execute gh. Is it installed and in PATH?");
            } else {
                authStatusProcess.command = [root._ghBinary, "auth", "status"];
                authStatusProcess.running = true;
            }
        }
    }

    // gh auth status
    property Process authStatusProcess: Process {
        command: []
        running: false

        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.authOk = false;
                root.loading = false;
                root.prCount = 0;
                root.issuesCount = 0;
                root.prItems.clear();
                root.issueItems.clear();
                root.setError("gh is not authenticated. Run: gh auth login");
            } else {
                if (root._showPRs) {
                    var prBase = [root._ghBinary, "search", "prs", "--author=@me", "--state=open", "--json", "number,title,repository", "--", "archived:false"];
                    if (root._org) prBase.push("--owner=" + root._org);
                    prListProcess.command = prBase;
                    prListProcess.running = true;
                } else if (root._showIssues) {
                    var issueBase = [root._ghBinary, "search", "issues", "--assignee=@me", "--state=open", "--json", "number,title,repository", "--", "archived:false"];
                    if (root._org) issueBase.push("--owner=" + root._org);
                    issueListProcess.command = issueBase;
                    issueListProcess.running = true;
                } else {
                    root.loading = false;
                }
            }
        }
    }

    // gh search prs (author)
    property Process prListProcess: Process {
        command: []
        running: false

        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.fillItemsFromJson(root.prItems, prListProcess.stdout.text);
            }
            if (root._showReviewer) {
                var prBase = [root._ghBinary, "search", "prs", "--review-requested=@me", "--state=open", "--json", "number,title,repository", "--", "archived:false"];
                if (root._org) prBase.push("--owner=" + root._org);
                prReviewerListProcess.command = prBase;
                prReviewerListProcess.running = true;
            } else {
                root.prCount = root.prItems.count;
                if (root._showIssues) {
                    var issueBase = [root._ghBinary, "search", "issues", "--assignee=@me", "--state=open", "--json", "number,title,repository", "--", "archived:false"];
                    if (root._org) issueBase.push("--owner=" + root._org);
                    issueListProcess.command = issueBase;
                    issueListProcess.running = true;
                } else {
                    root.loading = false;
                }
            }
        }
    }

    // gh search prs (reviewer)
    property Process prReviewerListProcess: Process {
        command: []
        running: false

        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.fillItemsFromJsonMerge(root.prItems, prReviewerListProcess.stdout.text);
            }
            root.prCount = root.prItems.count;
            if (root._showIssues) {
                var issueBase = [root._ghBinary, "search", "issues", "--assignee=@me", "--state=open", "--json", "number,title,repository", "--", "archived:false"];
                if (root._org) issueBase.push("--owner=" + root._org);
                issueListProcess.command = issueBase;
                issueListProcess.running = true;
            } else {
                root.loading = false;
            }
        }
    }

    // gh search issues
    property Process issueListProcess: Process {
        command: []
        running: false

        stdout: StdioCollector {}

        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.fillItemsFromJson(root.issueItems, issueListProcess.stdout.text);
                root.issuesCount = root.issueItems.count;
            }
            root.loading = false;
        }
    }
}
