pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Full AI mode's layer (services/FullAi.qml): over every screen, a soft
 * glow at the edges saying the AI is in charge, and the mascot
 * (MascotStage) on the screen the mode was started on. It takes no keys and
 * no clicks but on the balloon's Yes / No while a question waits: the user
 * keeps working, the agent's own clicks and keys go through too. While the
 * agent takes a screenshot, it vanishes.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: window
            required property var modelData
            readonly property bool main: window.modelData.name === FullAi.screenName
                || (!Quickshell.screens.some(s => s.name === FullAi.screenName) && window.modelData === Quickshell.screens[0])
            screen: window.modelData
            visible: FullAi.active && !GlobalStates.screenLocked
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.namespace: "quickshell:fullAi"
            WlrLayershell.layer: WlrLayer.Overlay
            // Never in the way: no keys, every click through to the apps
            // (the user keeps their desktop; Mod+Shift+T leaves the mode).
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Clicks only on the balloon's Yes / No while a question waits.
            property Region noInput: Region {}
            property Region choicesInput: Region {
                item: stageLoader.item ? stageLoader.item.choicesArea : null
            }
            mask: FullAi.yesNo && stageLoader.item && !MakeWay.capture ? window.choicesInput : window.noInput

            Item {
                id: keys
                anchors.fill: parent
                // Hidden from the agent's own screenshots.
                opacity: MakeWay.capture ? 0 : 1

                // The AI is in charge: a breathing glow around the screen.
                Rectangle {
                    id: glow
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 4
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.55)
                    radius: Appearance.rounding.screenRounding
                    SequentialAnimation on opacity {
                        running: window.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.45; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1; to: 0.45; duration: 1600; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 14
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.12)
                    radius: Appearance.rounding.screenRounding
                    opacity: glow.opacity
                }

                Loader {
                    id: stageLoader
                    anchors.fill: parent
                    active: window.main && window.visible
                    sourceComponent: MascotStage {
                        active: true
                        mood: FullAi.mood
                        line: FullAi.line
                        lineKind: FullAi.lineKind
                        yesNo: FullAi.yesNo
                        onChose: yes => FullAi.answer(yes)
                        hint: FullAi.hint
                        talking: FullAi.mood === "speaking"
                    }
                }
                Connections {
                    target: Initiative.chat?.strategy ?? null
                    ignoreUnknownSignals: true
                    // A step starting: the mascot darts there.
                    function onStepsChanged() {
                        if (stageLoader.item && (Initiative.chat?.strategy?.steps ?? []).some(s => s.status === "run")) stageLoader.item.dash();
                    }
                }
                Connections {
                    target: FullAi
                    function onFlashChanged() {
                        if (!stageLoader.item) return;
                        if (FullAi.flash === "happy") stageLoader.item.celebrate();
                        else if (FullAi.flash === "sad") stageLoader.item.shake();
                    }
                }
            }
        }
    }
}
