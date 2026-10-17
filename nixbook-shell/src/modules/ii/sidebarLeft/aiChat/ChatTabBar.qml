import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The chat's tabs (Ai.chats), each a conversation answering on its own: a
 * spinner while it works, a dot when it answered unseen, its agent
 * desktop's number while agents work on their own desktops ("Assistant's
 * desktop N"). Ctrl+T opens one, Ctrl+W closes it (its conversation stays
 * in the history), Ctrl+Tab and Ctrl+Shift+Tab go through them; middle
 * click closes one.
 */
RowLayout {
    id: root
    spacing: 4

    ListView {
        id: tabList
        Layout.fillWidth: true
        implicitHeight: 32
        orientation: ListView.Horizontal
        spacing: 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Ai.chats
        currentIndex: Ai.currentIndex
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: RippleButton {
            id: tab
            required property var modelData
            required property int index
            readonly property bool current: index === Ai.currentIndex
            implicitHeight: 32
            implicitWidth: Math.min(170, tabRow.implicitWidth + 20)
            buttonRadius: Appearance.rounding.full
            toggled: current
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive
            onClicked: Ai.currentIndex = index
            middleClickAction: () => Ai.closeChat(index)
            readonly property color fg: current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

            contentItem: RowLayout {
                id: tabRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 4
                }
                spacing: 4

                Rectangle { // its agent desktop
                    visible: DesktopControl.onAgentDesktop
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: tab.fg
                    StyledText {
                        anchors.centerIn: parent
                        text: tab.modelData.slot
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: tab.fg
                    }
                }
                MaterialLoadingIndicator {
                    visible: tab.modelData.responding
                    implicitSize: 16
                    loading: visible
                }
                Rectangle {
                    visible: tab.modelData.unread && !tab.modelData.responding
                    implicitWidth: 7
                    implicitHeight: 7
                    radius: 4
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 110
                    text: tab.modelData.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: tab.fg
                }
                RippleButton {
                    visible: Ai.chats.length > 1 && (tab.current || tab.hovered)
                    implicitWidth: 22
                    implicitHeight: 22
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Active
                    onClicked: Ai.closeChat(tab.index)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: tab.fg
                    }
                    StyledToolTip {
                        text: Translation.tr("Close (Ctrl+W): it stays in the history")
                    }
                }
            }

            StyledToolTip {
                text: tab.modelData.title + (DesktopControl.onAgentDesktop
                    ? "\n" + Translation.tr("Works on the assistant's desktop %1").arg(tab.modelData.slot) : "")
            }
        }
    }

    RippleButton {
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        enabled: Ai.chats.length < Ai.maxChats
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: Ai.newChat()
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: "add"
            iconSize: Appearance.font.pixelSize.larger
            color: parent.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer2Disabled
        }
        StyledToolTip {
            text: Translation.tr("New tab (Ctrl+T): chats run side by side")
        }
    }
}
