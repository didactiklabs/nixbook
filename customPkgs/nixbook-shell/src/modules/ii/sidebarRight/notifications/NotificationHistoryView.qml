pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Notification centre → History: NotificationHistory newest first, grouped by
 * day, filtered by the search field (app, title, text).
 */
ColumnLayout {
    id: root
    spacing: 5

    function plain(text) {
        return `${text ?? ""}`.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();
    }
    function dayLabel(time) {
        const d = new Date(time);
        const today = new Date();
        const yesterday = new Date(today.getTime() - NotificationHistory.dayMs);
        if (d.toDateString() === today.toDateString()) return Translation.tr("Today");
        if (d.toDateString() === yesterday.toDateString()) return Translation.tr("Yesterday");
        return Qt.locale().toString(d, "ddd d MMM yyyy");
    }

    // Newest first, with a { header } row before each day.
    readonly property var rows: {
        const query = search.text.trim().toLowerCase();
        const rows = [];
        let lastDay = "";
        for (let i = NotificationHistory.entries.length - 1; i >= 0; i--) {
            const e = NotificationHistory.entries[i];
            if (query && !`${e.appName} ${e.summary} ${root.plain(e.body)}`.toLowerCase().includes(query)) continue;
            const day = root.dayLabel(e.time);
            if (day !== lastDay) {
                rows.push({ header: day, key: `h${e.time}` });
                lastDay = day;
            }
            rows.push({ entry: e, key: `${e.id}-${e.time}` });
        }
        return rows;
    }

    ToolbarTextField {
        id: search
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: 40
        placeholderText: Translation.tr("Search history")
        colBackground: Appearance.colors.colLayer2
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        StyledListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 4
            popin: false
            model: ScriptModel {
                values: root.rows
                objectProp: "key"
            }
            delegate: Loader {
                id: row
                required property var modelData
                width: ListView.view.width
                sourceComponent: row.modelData.header !== undefined ? headerRow : entryRow

                Component {
                    id: headerRow
                    StyledText {
                        topPadding: 8
                        leftPadding: 6
                        text: row.modelData.header
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                }
                Component {
                    id: entryRow
                    Rectangle {
                        id: card
                        readonly property var entry: row.modelData.entry
                        implicitHeight: entryLayout.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            id: entryLayout
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    StyledText {
                                        text: Qt.locale().toString(new Date(card.entry.time), Config.options?.time?.format ?? "hh:mm")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: card.entry.appName
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    MaterialSymbol {
                                        visible: card.entry.cutIn !== ""
                                        text: "theater_comedy"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colPrimary
                                        StyledToolTip {
                                            text: Translation.tr("Cut-in · %1").arg(card.entry.cutIn)
                                        }
                                    }
                                    MaterialSymbol {
                                        visible: card.entry.urgency === "critical"
                                        text: "priority_high"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colError
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    elide: Text.ElideRight
                                    text: root.plain(card.entry.summary)
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    text: root.plain(card.entry.body)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            RippleButton {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.full
                                onClicked: NotificationHistory.deleteEntry(card.entry.id, card.entry.time)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                                StyledToolTip {
                                    text: Translation.tr("Delete from history")
                                }
                            }
                        }
                    }
                }
            }
        }

        PagePlaceholder {
            shown: root.rows.length === 0
            icon: "history"
            description: !NotificationHistory.enabled ? Translation.tr("History is off (Settings → Notifications)")
                : search.text ? Translation.tr("No match") : Translation.tr("No history yet")
            shape: MaterialShape.Shape.Ghostish
            descriptionHorizontalAlignment: Text.AlignHCenter
        }
    }
}
