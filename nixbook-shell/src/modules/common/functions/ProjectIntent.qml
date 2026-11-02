pragma Singleton
import Quickshell
import "project_intent.js" as Rules

/**
 * What the bubble is told about a project or teach mode, in plain code
 * (project_intent.js): "work on the hackathon", "pause hackathon", "watch
 * me", "done"… in four languages (services/QuickIntent.qml).
 */
Singleton {
    function projectIntent(text, names) {
        return Rules.projectIntent(text, names)
    }
    function teachIntent(text, recording) {
        return Rules.teachIntent(text, recording)
    }
}
