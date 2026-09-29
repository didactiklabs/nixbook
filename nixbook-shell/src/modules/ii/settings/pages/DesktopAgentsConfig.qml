import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > Desktop agents (services/DesktopControl.qml): whether AI agents
// may drive the desktop (nixbook-desktop-mcp), and the memory they keep of
// it — notes they wrote, app aliases and usage learned — to review, prune or
// clear.
ContentPage {
    id: page
    forceWidth: true

    Component.onCompleted: DesktopControl.refreshMemory()

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }

    function ago(seconds) {
        if (!seconds) return ""
        const d = new Date(seconds * 1000)
        return Qt.formatDateTime(d, "d MMM, hh:mm")
    }

    // [[key, {count, last}], …], most used first.
    function ranked(obj) {
        return Object.entries(obj ?? {}).sort((a, b) => (b[1].count ?? 0) - (a[1].count ?? 0))
    }

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "smart_toy"
            title: Translation.tr("Desktop control")
            shape: MaterialShape.Shape.Pentagon

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("AI agents (Claude Code, the AI chat, any MCP client using nixbook-desktop-mcp) can see and drive the desktop. Pausing refuses every tool to every agent until you allow them again; the Desktop Control bar widget does the same.")
            }

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "pan_tool"
                    text: Translation.tr("Pause desktop control")
                    checked: DesktopControl.paused
                    onClicked: DesktopControl.toggle()
                }
            }
        }

        ContentSection {
            icon: "psychology"
            title: Translation.tr("Desktop memory")
            shape: MaterialShape.Shape.Cookie4Sided

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("What agents learned about this desktop, so the next task is faster: notes they wrote (shortcuts, where things are, recipes), app names they resolved and what gets used. Every agent receives it when it connects, as hints — never as your instructions. Delete what is wrong or private.")
            }

            ContentSubsection {
                title: Translation.tr("Notes")

                StyledText {
                    visible: (DesktopControl.memory.notes ?? []).length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("None yet.")
                }

                Repeater {
                    model: DesktopControl.memory.notes ?? []
                    delegate: Rectangle {
                        id: noteRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: noteLayout.implicitHeight + 20
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            id: noteLayout
                            anchors { fill: parent; margins: 10; leftMargin: 14 }
                            spacing: 10

                            MaterialSymbol {
                                text: noteRow.modelData.kind === "recipe" ? "format_list_numbered" : "sticky_note_2"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: noteRow.modelData.topic
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    text: noteRow.modelData.text
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    text: Translation.tr("by %1 · %2 · used %3 times")
                                        .arg(noteRow.modelData.client ?? "?")
                                        .arg(page.ago(noteRow.modelData.updated))
                                        .arg(noteRow.modelData.uses ?? 0)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            SmallButton {
                                materialIcon: "delete"
                                mainText: Translation.tr("Delete")
                                onClicked: DesktopControl.forgetNote(noteRow.modelData.id)
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Learned")

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var aliases: Object.entries(DesktopControl.memory.aliases ?? {})
                    text: aliases.length === 0 ? Translation.tr("App aliases: none yet.")
                        : Translation.tr("App aliases: %1").arg(aliases.map(([k, v]) => `${k} → ${v}`).join(", "))
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var apps: page.ranked(DesktopControl.memory.usage?.apps).slice(0, 10)
                    text: apps.length === 0 ? Translation.tr("Apps launched by agents: none yet.")
                        : Translation.tr("Apps launched by agents: %1").arg(apps.map(([k, v]) => `${k} (${v.count})`).join(", "))
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    readonly property var tools: page.ranked(DesktopControl.memory.usage?.tools).slice(0, 8)
                    text: tools.length === 0 ? Translation.tr("Tools used: none yet.")
                        : Translation.tr("Tools used: %1").arg(tools.map(([k, v]) => `${k} (${v.count})`).join(", "))
                }
            }

            RowLayout {
                spacing: 8
                SmallButton {
                    materialIcon: "delete_sweep"
                    mainText: Translation.tr("Clear notes")
                    onClicked: DesktopControl.clearMemory(["notes"])
                }
                SmallButton {
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Clear usage and aliases")
                    onClicked: DesktopControl.clearMemory(["usage", "aliases"])
                }
                SmallButton {
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh")
                    onClicked: DesktopControl.refreshMemory()
                }
            }
        }
    }
}
