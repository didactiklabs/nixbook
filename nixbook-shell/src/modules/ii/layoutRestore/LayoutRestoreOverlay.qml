pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Shown while a window layout is restored (services/WindowLayouts.qml): dims
 * every output, says which layout is being set up and takes the input
 * (keyboard and pointer), so a click or a key doesn't land on a window that
 * is being moved or focus one the restore then has to fight. The windows
 * stay visible through the scrim. Lifts when the restore exits — or after
 * maxMs at the latest, so a stuck restore never keeps the desktop locked up.
 */
Scope {
    id: root

    // The restore waits up to 15 s for the apps it starts.
    readonly property int maxMs: 30000

    property bool timedOut: false
    readonly property bool active: WindowLayouts.restoring && !root.timedOut
    // Stay mapped through the fade-out.
    property bool shown: false

    onActiveChanged: {
        if (root.active) {
            fadeOut.stop();
            root.shown = true;
        } else {
            fadeOut.restart();
        }
    }
    Connections {
        target: WindowLayouts
        function onRestoringChanged() {
            if (WindowLayouts.restoring) {
                root.timedOut = false;
                maxTimer.restart();
            } else {
                maxTimer.stop();
            }
        }
    }
    Timer {
        id: maxTimer
        interval: root.maxMs
        onTriggered: root.timedOut = true
    }
    Timer {
        id: fadeOut
        interval: 240
        onTriggered: root.shown = false
    }

    LazyLoader {
        active: root.shown

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: overlay
                required property var modelData
                screen: modelData
                visible: root.shown

                WlrLayershell.namespace: "quickshell:layoutRestore"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                // Fading out: the input goes back to the windows at once.
                mask: root.active ? null : noInput
                Region { id: noInput }
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: "transparent"

                Rectangle {
                    id: content
                    anchors.fill: parent
                    color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45)
                    opacity: 0
                    Component.onCompleted: opacity = Qt.binding(() => root.active ? 1 : 0)
                    Behavior on opacity {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    // Swallow every click, scroll and key while restoring.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        hoverEnabled: true
                        onWheel: wheel => wheel.accepted = true
                    }
                    focus: true
                    Keys.onPressed: event => event.accepted = true

                    Rectangle {
                        anchors.centerIn: parent
                        implicitWidth: card.implicitWidth + 48
                        implicitHeight: card.implicitHeight + 40
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer1
                        scale: 0.94 + 0.06 * content.opacity

                        ColumnLayout {
                            id: card
                            anchors.centerIn: parent
                            spacing: 12

                            MaterialLoadingIndicator {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 64
                                loading: root.active
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Restoring the window layout")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: WindowLayouts.restoringName.length > 0
                                text: WindowLayouts.restoringName
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
