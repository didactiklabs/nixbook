pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The model provider every Claude Code the shell starts talks to
 * (ai.provider, scripts/model-provider.sh): Anthropic, Claude Code on the
 * user's own Claude login (the default); Meta, Meta's Model API (Muse
 * models) through its Anthropic-compatible Messages endpoint; or another
 * Anthropic-compatible server. Claude Code stays the agent either way (its
 * tools, the desktop MCP server, the sandbox): only the model behind it
 * changes. The side panel, the memory and initiative passes, routines, the
 * equalizer agent and nixbook-improve all start it through
 * `nixbook-model-provider run`. The API key is in the keyring (saved per
 * provider and host), handed to the launcher on stdin, never kept here.
 */
Singleton {
    id: root

    readonly property var settings: Config.options?.ai?.provider ?? ({})
    readonly property string kind: String(settings.kind ?? "anthropic").toLowerCase() || "anthropic"
    readonly property bool isAnthropic: kind === "anthropic"
    // What `nixbook-model-provider status` says: presets filled in, key saved,
    // and why the settings can't be used, if they can't.
    property var status: ({})
    readonly property bool keySaved: status.keySaved === true
    readonly property string error: status.error ?? ""
    readonly property bool ready: isAnthropic || (keySaved && error === "")
    readonly property string model: status.model ?? ""
    readonly property string label: kind === "meta" ? "Meta" : kind === "custom" ? Translation.tr("Custom") : "Anthropic"
    // The side panel's model name.
    readonly property string chatName: isAnthropic ? "Claude" : model.length > 0 ? `${label} ${model}` : label
    // Bumped when the key changes: the side panel's running Claude Code
    // holds the old one, its command line then differs and it starts again.
    property int keyRevision: 0
    // What a command answered, for Settings.
    property bool busy: false
    property string message: ""

    // In the side panel's Claude Code command line: a provider change starts
    // it again.
    readonly property string signature: isAnthropic ? "anthropic"
        : [kind, settings.baseUrl ?? "", settings.model ?? "", settings.smallModel ?? "", settings.bigModel ?? "", keyRevision].join("|")

    onSignatureChanged: refreshTimer.restart()
    Component.onCompleted: refreshTimer.restart()

    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
    }

    function refresh() {
        if (!Config.ready) {
            refreshTimer.restart()
            return
        }
        statusProc.running = false
        statusProc.running = true
    }

    function setKey(key) {
        const k = String(key ?? "").trim()
        if (k.length === 0 || root.busy) return
        root.busy = true
        root.message = ""
        keyProc.secret = k
        keyProc.command = ["nixbook-model-provider", "key", "set"]
        keyProc.stdinEnabled = true
        keyProc.running = true
    }
    function forgetKey() {
        if (root.busy) return
        root.busy = true
        keyProc.secret = ""
        keyProc.command = ["nixbook-model-provider", "key", "forget"]
        keyProc.stdinEnabled = false
        keyProc.running = true
    }
    // One short request with the saved key and the main model.
    function test() {
        if (root.busy) return
        root.busy = true
        root.message = Translation.tr("Asking %1…").arg(root.label)
        testProc.running = true
    }

    Process {
        id: statusProc
        command: ["nixbook-model-provider", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = JSON.parse(text)
                } catch (e) {
                    root.status = { error: Translation.tr("nixbook-model-provider didn't answer") }
                }
            }
        }
    }

    Process {
        id: keyProc
        property string secret: ""
        onRunningChanged: {
            if (!keyProc.running || !keyProc.stdinEnabled) return
            keyProc.write(keyProc.secret + "\n")
            keyProc.secret = ""
            keyProc.stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                try {
                    const out = JSON.parse(text)
                    root.message = out.error ? out.error : out.saved ? Translation.tr("Key saved in the keyring.") : Translation.tr("Key forgotten.")
                    if (!out.error) root.keyRevision++
                } catch (e) {
                    root.message = Translation.tr("nixbook-model-provider didn't answer")
                }
                root.refresh()
            }
        }
    }

    Process {
        id: testProc
        command: ["nixbook-model-provider", "test"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                try {
                    const out = JSON.parse(text)
                    root.message = out.ok
                        ? Translation.tr("It works: %1 answered \"%2\".").arg(out.model).arg(out.answer ?? "")
                        : Translation.tr("It doesn't work: %1").arg(out.error ?? "?")
                } catch (e) {
                    root.message = Translation.tr("nixbook-model-provider didn't answer")
                }
            }
        }
    }
}
