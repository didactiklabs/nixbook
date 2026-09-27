import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings → Notifications → Persona cut-in: shows, live while the rules are
 * edited, whether a typed sample and the recent notifications would get a
 * cut-in and which rule decided (Notifications.cutInVerdict).
 */
ColumnLayout {
    id: root
    spacing: 6

    // Read here so every verdict re-evaluates when a rule changes.
    readonly property var rules: Config.options.notifications.cutIn
    function verdict(n) {
        const deps = [root.rules.enable, root.rules.critical, root.rules.apps, root.rules.keywords, root.rules.blacklist];
        return Notifications.cutInVerdict(n);
    }
    readonly property var recent: [...Notifications.list].sort((a, b) => b.time - a.time).slice(0, 8)

    // "✓ Cut-in · keyword "Victor + Instagram"" / "⊘ Blocked · …" / "– No cut-in".
    component Verdict: RowLayout {
        id: verdictRow
        required property var verdict
        readonly property bool blocked: !verdict.cutIn && verdict.reason.startsWith("blacklist")
        readonly property color tint: verdict.cutIn ? Appearance.colors.colPrimary
            : blocked ? Appearance.colors.colError : Appearance.colors.colSubtext
        spacing: 4
        MaterialSymbol {
            text: verdictRow.verdict.cutIn ? "theater_comedy" : verdictRow.blocked ? "block" : "remove"
            iconSize: Appearance.font.pixelSize.normal
            color: verdictRow.tint
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: verdictRow.tint
            text: verdictRow.verdict.cutIn ? Translation.tr("Cut-in · %1").arg(verdictRow.verdict.reason)
                : verdictRow.blocked ? Translation.tr("Blocked · %1").arg(verdictRow.verdict.reason)
                : verdictRow.verdict.reason ? Translation.tr("No cut-in · %1").arg(verdictRow.verdict.reason)
                : Translation.tr("No cut-in")
        }
    }

    RowLayout {
        spacing: 10
        MaterialSymbol {
            text: "science"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            text: Translation.tr("Test your rules")
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 6
        MaterialTextField {
            id: sampleApp
            Layout.fillWidth: true
            placeholderText: Translation.tr("App")
        }
        MaterialTextField {
            id: sampleTitle
            Layout.fillWidth: true
            placeholderText: Translation.tr("Title")
        }
        MaterialTextField {
            id: sampleBody
            Layout.fillWidth: true
            placeholderText: Translation.tr("Text")
        }
    }
    Verdict {
        Layout.fillWidth: true
        visible: sampleApp.text || sampleTitle.text || sampleBody.text
        verdict: root.verdict({ appName: sampleApp.text, summary: sampleTitle.text, body: sampleBody.text, hints: {} })
    }

    StyledText {
        Layout.topMargin: 6
        text: root.recent.length > 0 ? Translation.tr("Recent notifications") : Translation.tr("Recent notifications show up here.")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
    Repeater {
        model: root.recent
        delegate: ColumnLayout {
            id: recentRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: `${recentRow.modelData.appName} — ${recentRow.modelData.summary}`
                    + (recentRow.modelData.body ? ` · ${recentRow.modelData.body.replace(/\s+/g, " ")}` : "")
                color: Appearance.colors.colOnLayer1
            }
            Verdict {
                Layout.fillWidth: true
                verdict: root.verdict(recentRow.modelData)
            }
        }
    }
}
