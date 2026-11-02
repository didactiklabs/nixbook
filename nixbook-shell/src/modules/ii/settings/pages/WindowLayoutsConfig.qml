import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > Window layouts (services/WindowLayouts.qml): save the windows
// as they are under a name, restore, update, rename and delete the saved
// layouts; the shortcut that picks one.
ContentPage {
    id: page
    forceWidth: true

    Component.onCompleted: {
        WindowLayouts.refresh()
        Projects.refresh()
    }

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

    // "2026-09-29T15:14:02+0000" -> the local date and time.
    function savedWhen(iso) {
        const d = new Date((iso ?? "").replace(/([+-]\d\d)(\d\d)$/, "$1:$2"))
        return isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "d MMM yyyy, hh:mm")
    }

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
        enabled: !WindowLayouts.busy
        opacity: enabled ? 1 : 0.5
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "view_quilt"
            title: Translation.tr("Window layouts")
            shape: MaterialShape.Shape.Pentagon

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("A layout remembers where every window is: its monitor, workspace, column (or position when floating) and size. Restoring it puts the windows back and starts the apps that were closed. AI agents with desktop control can save and restore them too.")
            }

            ConfigSwitch {
                configKey: "windowLayouts.closeOthers"
                enabled: !nixManaged
                buttonIcon: "close"
                text: Translation.tr("Close the other windows when restoring")
                checked: Config.options.windowLayouts.closeOthers
                onCheckedChanged: {
                    Config.options.windowLayouts.closeOthers = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Windows the layout doesn't have are closed as their close button would (apps may ask to save). Only your restores: agents' never close windows.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Save the windows as they are")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialTextField {
                        id: newName
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Name, e.g. work, gaming, meeting")
                        onAccepted: saveButton.clicked()
                    }
                    SmallButton {
                        id: saveButton
                        materialIcon: "save"
                        mainText: Translation.tr("Save")
                        onClicked: {
                            const name = newName.text.trim() || WindowLayouts.nextName()
                            if (!WindowLayouts.validName(name)) return
                            if (WindowLayouts.save(name)) newName.text = ""
                        }
                    }
                }
                StyledText {
                    visible: newName.text.trim().length > 0 && !WindowLayouts.validName(newName.text.trim())
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Letters, digits, '.', '-' and '_' only")
                }
            }

            ContentSubsection {
                title: Translation.tr("Saved layouts")

                StyledText {
                    visible: WindowLayouts.layouts.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("None yet.")
                }

                Repeater {
                    model: WindowLayouts.layouts
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        property bool renaming: false
                        readonly property bool isCurrent: WindowLayouts.current === modelData.name
                        Layout.fillWidth: true
                        implicitHeight: rowLayout.implicitHeight + 20
                        radius: Appearance.rounding.normal
                        color: isCurrent ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1

                        RowLayout {
                            id: rowLayout
                            anchors { fill: parent; margins: 10; leftMargin: 14 }
                            spacing: 10

                            MaterialSymbol {
                                text: "view_quilt"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colOnLayer1
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    visible: !row.renaming
                                    spacing: 8
                                    StyledText {
                                        text: row.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        visible: row.isCurrent
                                        text: Translation.tr("current")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                                MaterialTextField {
                                    id: renameField
                                    visible: row.renaming
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    onVisibleChanged: if (visible) { text = row.modelData.name; forceActiveFocus(); selectAll() }
                                    onAccepted: {
                                        const name = text.trim()
                                        if (name === row.modelData.name) row.renaming = false
                                        else if (WindowLayouts.rename(row.modelData.name, name)) row.renaming = false
                                    }
                                    Keys.onEscapePressed: row.renaming = false
                                }
                                StyledText {
                                    readonly property string name: renameField.text.trim()
                                    visible: row.renaming && name !== row.modelData.name
                                        && (!WindowLayouts.validName(name) || WindowLayouts.layouts.some(l => l.name === name))
                                    color: Appearance.m3colors.m3error
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    text: WindowLayouts.validName(name) ? Translation.tr("A layout with this name exists already")
                                        : Translation.tr("Letters, digits, '.', '-' and '_' only")
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("%1 windows · %2 · saved %3")
                                        .arg(row.modelData.windows)
                                        .arg((row.modelData.apps ?? []).join(", "))
                                        .arg(page.savedWhen(row.modelData.saved))
                                }
                            }

                            SmallButton {
                                materialIcon: "settings_backup_restore"
                                mainText: Translation.tr("Restore")
                                onClicked: WindowLayouts.restore(row.modelData.name)
                            }
                            SmallButton {
                                materialIcon: "save"
                                mainText: Translation.tr("Update")
                                onClicked: WindowLayouts.save(row.modelData.name)
                            }
                            SmallButton {
                                materialIcon: row.renaming ? "check" : "edit"
                                mainText: row.renaming ? Translation.tr("Done") : Translation.tr("Rename")
                                onClicked: {
                                    if (row.renaming) renameField.accepted()
                                    else row.renaming = true
                                }
                            }
                            SmallButton {
                                materialIcon: "delete"
                                mainText: Translation.tr("Delete")
                                onClicked: WindowLayouts.remove(row.modelData.name)
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "work"
            title: Translation.tr("Projects")
            shape: MaterialShape.Shape.Clover4Leaf

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("A project is a whole context to come back to: its window layout, the Zen tabs of its window, Do Not Disturb and a focus timer. Say \"work on the hackathon\" to DAI (or pick it with %1 in the launcher) and it comes back as you left it; \"pause the hackathon\" saves it as it is, then does what its pause rule says.").arg(Config.options.search.prefix.layouts)
            }

            ContentSubsection {
                title: Translation.tr("Save the desktop as a project")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialTextField {
                        id: newProject
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Name, e.g. hackathon, thesis, taxes")
                        onAccepted: saveProject.clicked()
                    }
                    SmallButton {
                        id: saveProject
                        enabled: !Projects.busy && Projects.validName(newProject.text)
                        materialIcon: "save"
                        mainText: Translation.tr("Save")
                        onClicked: if (Projects.save(newProject.text)) newProject.text = ""
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Saved projects")

                StyledText {
                    visible: Projects.projects.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("None yet.")
                }

                Repeater {
                    model: Projects.projects
                    delegate: Rectangle {
                        id: prow
                        required property var modelData
                        readonly property bool isOpen: modelData.state === "open"
                        readonly property var focusChoices: [0, 25, 50, 90, "pomodoro"]
                        Layout.fillWidth: true
                        implicitHeight: pcol.implicitHeight + 20
                        radius: Appearance.rounding.normal
                        color: isOpen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1

                        ColumnLayout {
                            id: pcol
                            anchors { fill: parent; margins: 10; leftMargin: 14 }
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                MaterialSymbol {
                                    text: "work"
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colOnLayer1
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        text: prow.modelData.name + (prow.isOpen ? `  · ${Translation.tr("open")}` : "")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                        text: Translation.tr("%1 · %2 tabs · saved %3")
                                            .arg((prow.modelData.apps ?? []).join(", "))
                                            .arg((prow.modelData.tabs ?? []).length)
                                            .arg(page.savedWhen(prow.modelData.saved))
                                    }
                                }
                                SmallButton {
                                    enabled: !Projects.busy
                                    materialIcon: prow.isOpen ? "pause" : "play_arrow"
                                    mainText: prow.isOpen ? Translation.tr("Pause") : Translation.tr("Open")
                                    onClicked: prow.isOpen ? Projects.pause(prow.modelData.name) : Projects.open(prow.modelData.name)
                                }
                                SmallButton {
                                    enabled: !Projects.busy
                                    materialIcon: "save"
                                    mainText: Translation.tr("Update")
                                    onClicked: Projects.save(prow.modelData.name)
                                }
                                SmallButton {
                                    enabled: !Projects.busy
                                    materialIcon: "delete"
                                    mainText: Translation.tr("Delete")
                                    onClicked: Projects.remove(prow.modelData.name)
                                }
                            }
                            // Its options, one click each to the next choice.
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                SmallButton {
                                    enabled: !Projects.busy
                                    materialIcon: "do_not_disturb_on"
                                    mainText: prow.modelData.dnd === true ? Translation.tr("DND: on while open")
                                        : prow.modelData.dnd === false ? Translation.tr("DND: off while open")
                                        : Translation.tr("DND: left alone")
                                    onClicked: Projects.set(prow.modelData.name, "dnd",
                                        prow.modelData.dnd === true ? "off" : prow.modelData.dnd === false ? "none" : "on")
                                }
                                SmallButton {
                                    enabled: !Projects.busy
                                    materialIcon: "timer"
                                    readonly property var focusNow: prow.modelData.focus?.kind === "pomodoro" ? "pomodoro"
                                        : (prow.modelData.focus?.minutes ?? 0)
                                    mainText: focusNow === "pomodoro" ? Translation.tr("Timer: a pomodoro")
                                        : focusNow > 0 ? Translation.tr("Timer: %1 min").arg(focusNow) : Translation.tr("Timer: none")
                                    onClicked: {
                                        const i = prow.focusChoices.indexOf(focusNow);
                                        Projects.set(prow.modelData.name, "focus", prow.focusChoices[(i + 1) % prow.focusChoices.length]);
                                    }
                                }
                                SmallButton {
                                    enabled: !Projects.busy
                                    materialIcon: "inventory_2"
                                    readonly property string rule: prow.modelData.onPause ?? "keep"
                                    mainText: rule === "tabs" ? Translation.tr("Pausing closes its tabs")
                                        : Translation.tr("Pausing leaves it all open")
                                    onClicked: Projects.set(prow.modelData.name, "on-pause", rule === "keep" ? "tabs" : "keep")
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "keyboard"
            title: Translation.tr("Shortcut")
            shape: MaterialShape.Shape.Cookie4Sided

            GroupedList {
                ConfigRow {
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Pick a layout: restore one, or type a name to save the windows"); color: Appearance.colors.colOnLayer1 }
                    StyledText { text: "Mod+G"; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("It opens the launcher on its layouts list; typing %1 in the launcher does the same. Other key bindings can call nixbook-shell ipc call layouts cycle, saveCurrent, restoreNumber N, restore NAME or save NAME.").arg(Config.options.search.prefix.layouts)
            }
        }
    }
}
