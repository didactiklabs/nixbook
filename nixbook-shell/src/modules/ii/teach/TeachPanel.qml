pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Teach mode's card (services/TeachMode.qml), top centre of the focused
 * screen: while watching, a small bar — "Watching you · N steps", a field
 * for what the user typed (the only way typed text gets in, besides what
 * they copy), Done and Cancel; then "Writing it down…"; then the review:
 * the recipe's name, its steps (copied text unticked until the user ticks
 * it), its variables (renamable), Save / Discard. Built the first time teach
 * mode starts; the keyboard only when a field is clicked (OnDemand); out of
 * an agent's screenshots and clicks (MakeWay).
 */
Scope {
    id: root
    property bool everShown: false
    Connections {
        target: TeachMode
        function onPhaseChanged() {
            if (TeachMode.phase !== "idle") root.everShown = true
        }
    }

    LazyLoader {
        active: root.everShown
        component: PanelWindow {
            id: window
            readonly property bool open: TeachMode.phase !== "idle" && !GlobalStates.screenLocked
            visible: window.open
            screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? Quickshell.screens[0]
            color: "transparent"
            implicitWidth: card.implicitWidth + 8
            implicitHeight: card.implicitHeight + 8
            anchors.top: true
            margins.top: (!(Config.options.bar.bottom ?? false) && !(Config.options.bar.vertical ?? false))
                ? Appearance.sizes.barHeight + 8 : 12
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:teachMode"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: MakeWay.active ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
            property Region noInput: Region {}
            property Region cardInput: Region { item: card }
            mask: MakeWay.active ? window.noInput : window.cardInput

            Rectangle {
                id: card
                x: 4
                y: 4
                implicitWidth: Math.min(620, Math.max(420, column.implicitWidth + 28))
                implicitHeight: column.implicitHeight + 22
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1
                border.color: TeachMode.recording ? Appearance.m3colors.m3error : Appearance.m3colors.m3outlineVariant
                opacity: MakeWay.capture ? 0 : 1

                ColumnLayout {
                    id: column
                    x: 14
                    y: 11
                    width: card.width - 28
                    spacing: 8

                    // ── The title line ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            visible: TeachMode.recording
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 5
                            color: Appearance.m3colors.m3error
                            SequentialAnimation on opacity {
                                running: TeachMode.recording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 700 }
                                NumberAnimation { to: 1; duration: 700 }
                            }
                        }
                        MaterialSymbol {
                            visible: !TeachMode.recording
                            text: "school"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.m3colors.m3primary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: TeachMode.recording
                                ? Translation.tr("Watching you · %1 recorded").arg(TeachMode.events)
                                : TeachMode.phase === "drafting" ? Translation.tr("Writing down what you did…")
                                : TeachMode.phase === "saving" ? Translation.tr("Saving…")
                                : Translation.tr("What I learned: check it")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSurface
                        }
                        DialogButton {
                            visible: TeachMode.recording
                            buttonText: Translation.tr("Done")
                            onClicked: TeachMode.stop()
                        }
                        DialogButton {
                            visible: TeachMode.phase !== "saving"
                            buttonText: TeachMode.phase === "review" ? Translation.tr("Discard") : Translation.tr("Cancel")
                            colEnabled: Appearance.colors.colSubtext
                            onClicked: TeachMode.cancel()
                        }
                    }

                    // ── Recording: what the user typed, given by them ──
                    StyledText {
                        visible: TeachMode.recording
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Do the task once. I see the apps, windows and links, never your keys: if you type something that matters, put it here too.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    RowLayout {
                        visible: TeachMode.recording
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialTextField {
                            id: typed
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("I typed… (e.g. Report for March)")
                            onAccepted: if (TeachMode.mark(typed.text)) typed.text = ""
                        }
                        DialogButton {
                            buttonText: Translation.tr("Add")
                            enabled: typed.text.trim().length > 0
                            onClicked: if (TeachMode.mark(typed.text)) typed.text = ""
                        }
                    }

                    // ── Review ──
                    MaterialTextField {
                        id: topicField
                        visible: TeachMode.phase === "review"
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Its name (e.g. expenses: monthly report)")
                        text: TeachMode.topic
                        onTextEdited: TeachMode.topic = topicField.text
                    }
                    StyledText {
                        visible: TeachMode.phase === "review" && (TeachMode.draft?.summary ?? "").length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: TeachMode.draft?.summary ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    Repeater {
                        model: TeachMode.phase === "review" ? (TeachMode.draft?.steps ?? []) : []
                        delegate: RowLayout {
                            id: stepRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 8
                            StyledSwitch {
                                checked: TeachMode.include[stepRow.index] ?? false
                                onToggled: TeachMode.setIncluded(stepRow.index, checked)
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: `${stepRow.index + 1}. ${stepRow.modelData.label ?? stepRow.modelData.tool}`
                                    + (stepRow.modelData.pending ? `  ${Translation.tr("(you copied it: keep it?)")}` : "")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: (TeachMode.include[stepRow.index] ?? false) ? Appearance.m3colors.m3onSurface : Appearance.colors.colSubtext
                            }
                        }
                    }
                    Repeater {
                        model: TeachMode.phase === "review" ? Object.keys(TeachMode.draft?.vars ?? {}) : []
                        delegate: RowLayout {
                            id: varRow
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                text: Translation.tr("Changes each time: “%1” as").arg(TeachMode.draft?.vars?.[varRow.modelData] ?? "")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSurface
                            }
                            MaterialTextField {
                                Layout.preferredWidth: 140
                                text: varRow.modelData
                                onTextEdited: TeachMode.rename(varRow.modelData, text)
                            }
                        }
                    }
                    StyledText {
                        visible: TeachMode.phase === "review" && ((TeachMode.draft?.note ?? "").length > 0 || TeachMode.error.length > 0)
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: TeachMode.error.length > 0 ? TeachMode.error : (TeachMode.draft?.note ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: TeachMode.error.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                    }
                    RowLayout {
                        visible: TeachMode.phase === "review"
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        DialogButton {
                            buttonText: Translation.tr("Save it")
                            enabled: TeachMode.topic.trim().length > 0
                            onClicked: TeachMode.save()
                        }
                    }
                }
            }
        }
    }
}
