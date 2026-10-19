import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The "From Claude" tab's threads: each thing Claude said on its own is a
 * conversation of its own (Ai.claudeThread), saved in the history; the
 * latest are listed here, newest first, a dot on those not answered yet.
 * Clicking one goes back to it in this tab; the button at the end deletes
 * them all but the pinned ones (a second click to confirm).
 */
ListView {
    id: root
    readonly property var threads: Ai.history.filter(c => c.fromClaude).slice(0, 20)
    readonly property int unpinned: Ai.history.filter(c => c.fromClaude && !c.pinned).length
    property bool confirmClear: false
    visible: Ai.current?.fromClaude === true && root.threads.length > 0
    implicitHeight: 28
    orientation: ListView.Horizontal
    spacing: 4
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.threads

    Timer {
        id: confirmReset
        interval: 4000
        onTriggered: root.confirmClear = false
    }

    footerPositioning: ListView.PinnedFooter
    footer: Item {
        visible: root.unpinned > 0
        implicitWidth: visible ? clearButton.implicitWidth + 4 : 0
        implicitHeight: 28
        RippleButton {
            id: clearButton
            anchors.right: parent.right
            implicitHeight: 28
            implicitWidth: clearRow.implicitWidth + 20
            buttonRadius: Appearance.rounding.full
            toggled: root.confirmClear
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colBackgroundToggled: Appearance.colors.colError
            colBackgroundToggledHover: Appearance.colors.colErrorHover
            colRippleToggled: Appearance.colors.colErrorActive
            onClicked: {
                if (!root.confirmClear) {
                    root.confirmClear = true;
                    confirmReset.restart();
                    return;
                }
                root.confirmClear = false;
                Ai.deleteClaudeThreads();
            }
            contentItem: RowLayout {
                id: clearRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    text: "delete_sweep"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.confirmClear ? Appearance.colors.colOnError : Appearance.colors.colOnLayer2
                }
                StyledText {
                    visible: root.confirmClear
                    text: Translation.tr("Delete %1?").arg(root.unpinned)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnError
                }
            }
            StyledToolTip {
                text: Translation.tr("Clear the threads from Claude (but the pinned ones)")
            }
        }
    }

    delegate: RippleButton {
        id: thread
        required property var modelData
        readonly property bool current: modelData.id === Ai.chatId
        implicitHeight: 28
        implicitWidth: Math.min(150, threadRow.implicitWidth + 20)
        buttonRadius: Appearance.rounding.full
        toggled: current
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        onClicked: if (!current) Ai.openChat(modelData.id)
        readonly property color fg: current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

        contentItem: RowLayout {
            id: threadRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 4
            Rectangle { // not answered yet
                visible: (thread.modelData.turns ?? 0) <= 1
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 110
                text: thread.modelData.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: thread.fg
            }
        }

        StyledToolTip {
            text: thread.modelData.title
        }
    }
}
