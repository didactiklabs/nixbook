import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The mesh (services/Mesh.qml): how many members are around, and unread
// messages. Hovering lists everyone's status; a click opens the right
// sidebar's Mesh tab. Hidden until the mesh is set up.
BarWidgetSwitcher {
    id: root
    vertical: Config.options.bar.vertical
    visible: Mesh.configured

    readonly property bool hasUnread: Mesh.unread > 0
    readonly property color accent: root.hasUnread ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1

    rowDefault: Component {
        RowLayout {
            spacing: 4
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: Mesh.connected ? "hub" : "cloud_off"
                iconSize: Appearance.font.pixelSize.larger
                fill: root.hasUnread ? 1 : 0
                color: Mesh.connected ? root.accent : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasUnread || Mesh.around > 0
                text: root.hasUnread ? `${Mesh.unread}` : `${Mesh.around}`
                font.weight: root.hasUnread ? Font.DemiBold : Font.Normal
                color: root.accent
            }
        }
    }
    rowMaterial: rowDefault

    colDefault: Component {
        ColumnLayout {
            spacing: 0
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: Mesh.connected ? "hub" : "cloud_off"
                iconSize: Appearance.font.pixelSize.larger
                fill: root.hasUnread ? 1 : 0
                color: Mesh.connected ? root.accent : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.hasUnread
                text: `${Mesh.unread}`
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.accent
            }
        }
    }
    colMaterial: colDefault

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // Straight to what is unread, else where it was.
            const unreadConv = Mesh.messages.filter(m => !m.mine && m.time > (Mesh.readAt[Mesh.conversationOf(m)] ?? 0)).slice(-1)[0];
            Mesh.open(unreadConv ? Mesh.conversationOf(unreadConv) : undefined);
        }

        StyledPopup {
            hoverTarget: mouseArea

            ColumnLayout {
                spacing: 6
                width: 280

                StyledPopupHeaderRow {
                    icon: "hub"
                    label: Translation.tr("Mesh")
                }

                StyledText {
                    visible: !Mesh.connected
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Mesh.lastError || Translation.tr("Not connected to the mesh's server")
                    color: Appearance.m3colors.m3error
                }
                StyledText {
                    visible: Mesh.memberList.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("No one else yet: members appear when they come online")
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: Mesh.memberList
                    delegate: RowLayout {
                        id: member
                        required property var modelData
                        readonly property int unread: Mesh.unreadIn(member.modelData.id)
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 5
                            color: Mesh.stateColor(Mesh.stateOf(member.modelData.id))
                        }
                        StyledText {
                            text: Mesh.nameOf(member.modelData.id)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Mesh.statusLine(member.modelData.id)
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            visible: member.unread > 0
                            text: Translation.tr("%1 new").arg(member.unread)
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                StyledText {
                    visible: Mesh.unreadIn("") > 0
                    text: Translation.tr("%1 new to everyone").arg(Mesh.unreadIn(""))
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Click to open the conversations")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
