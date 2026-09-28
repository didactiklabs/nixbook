import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * App chips + keyword field for a notification rule in
 * Config.options.notifications.<ruleKey> (`apps`, `keywords`, and
 * `blacklist` when `blacklistLabel` is set): used by
 * Settings → Notifications for "Keep on screen" and "Persona cut-in".
 * The chips list every app seen in the notification history plus the ones
 * already chosen. Both lists honour Nix locks.
 */
ColumnLayout {
    id: root
    required property string ruleKey
    property string appsLabel: Translation.tr("For these apps")
    property string keywordsLabel: Translation.tr("For notifications containing")
    property string keywordsPlaceholder: ""
    // Non-empty: also show a field for `blacklist` (words that veto the rule).
    property string blacklistLabel: ""
    property string blacklistPlaceholder: ""
    spacing: 0

    readonly property var rules: Config.options.notifications[root.ruleKey]
    readonly property var appChoices: {
        const seen = new Map();
        for (const a of [...(root.rules?.apps ?? []), ...Notifications.appNameList])
            if (a && !seen.has(a.toLowerCase())) seen.set(a.toLowerCase(), a);
        return [...seen.values()].sort((x, y) => x.localeCompare(y));
    }
    function hasApp(app) {
        return (root.rules?.apps ?? []).some(a => a.toLowerCase() === app.toLowerCase());
    }
    function toggleApp(app) {
        const apps = root.rules?.apps ?? [];
        Config.options.notifications[root.ruleKey].apps = root.hasApp(app)
            ? apps.filter(a => a.toLowerCase() !== app.toLowerCase())
            : apps.concat([app]);
        Config.save();
    }
    // Comma-separated field text → Config.options.notifications.<ruleKey>.<key>.
    function saveWords(key, value) {
        const words = value.split(",").map(w => w.trim()).filter(w => w.length > 0);
        if (JSON.stringify(words) !== JSON.stringify(root.rules?.[key] ?? [])) {
            Config.options.notifications[root.ruleKey][key] = words;
            Config.save();
        }
    }

    ColumnLayout {
        id: apps
        readonly property bool nixManaged: NixManaged.isPinned(`notifications.${root.ruleKey}.apps`)
        Layout.fillWidth: true
        Layout.margins: 8
        spacing: 6
        enabled: !nixManaged
        opacity: enabled ? 1 : 0.5
        RowLayout {
            spacing: 10
            MaterialSymbol {
                text: "apps"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: root.appsLabel
                color: Appearance.colors.colOnSecondaryContainer
            }
            NixManagedBadge { pinned: apps.nixManaged }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.appChoices
                delegate: RippleButton {
                    id: appChip
                    required property string modelData
                    readonly property bool chosen: root.hasApp(modelData)
                    implicitHeight: 32
                    implicitWidth: appChipRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    toggled: chosen
                    onClicked: root.toggleApp(modelData)
                    // Locked (Nix): RippleButton drops its background when
                    // disabled, so outline the chosen chips instead.
                    readonly property color labelColor: chosen && enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    Rectangle {
                        anchors.fill: parent
                        visible: appChip.chosen && !appChip.enabled
                        radius: height / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Appearance.colors.colPrimary
                    }
                    contentItem: RowLayout {
                        id: appChipRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            visible: appChip.chosen
                            text: "check"
                            iconSize: Appearance.font.pixelSize.normal
                            color: appChip.labelColor
                        }
                        StyledText {
                            text: appChip.modelData
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: appChip.labelColor
                        }
                    }
                }
            }
            StyledText {
                visible: root.appChoices.length === 0
                text: Translation.tr("Apps appear here once they have sent a notification.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }

    ConfigTextArea {
        id: keywords
        configKey: `notifications.${root.ruleKey}.keywords`
        Layout.fillWidth: true
        buttonIcon: "key"
        text: root.keywordsLabel
        placeholderText: root.keywordsPlaceholder
        // Lists get long: wider field that grows with its wrapped content.
        fieldWidth: 360
        fieldHeight: Math.max(40, textArea.contentHeight + 18)
        value: (root.rules?.keywords ?? []).join(", ")
        onValueChanged: keywordsTimer.restart()
        Timer {
            id: keywordsTimer
            interval: 800
            onTriggered: root.saveWords("keywords", keywords.value)
        }
    }

    ConfigTextArea {
        id: blacklist
        visible: root.blacklistLabel !== ""
        configKey: `notifications.${root.ruleKey}.blacklist`
        Layout.fillWidth: true
        buttonIcon: "block"
        text: root.blacklistLabel
        placeholderText: root.blacklistPlaceholder
        fieldWidth: 360
        fieldHeight: Math.max(40, textArea.contentHeight + 18)
        value: (root.rules?.blacklist ?? []).join(", ")
        onValueChanged: blacklistTimer.restart()
        Timer {
            id: blacklistTimer
            interval: 800
            onTriggered: if (blacklist.visible) root.saveWords("blacklist", blacklist.value)
        }
    }
}
