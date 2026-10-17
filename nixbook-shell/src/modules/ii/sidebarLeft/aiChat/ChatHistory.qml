import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The conversation history (Ai.history), over the chat: the conversations to
 * go back to, pinned ones first then the latest, with a search, renaming,
 * pins (kept past ai.history.keepDays) and deletion. Up/Down and Enter from
 * the search field, Esc to close.
 */
Rectangle {
    id: root
    signal closed()
    property alias searchField: searchField
    property int selectedIndex: 0
    property bool confirmDeleteAll: false

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.small

    readonly property var shown: {
        const q = searchField.text.trim().toLowerCase();
        const found = Ai.history.filter(c => q.length === 0 || (c.title ?? "").toLowerCase().includes(q));
        return [...found.filter(c => c.pinned), ...found.filter(c => !c.pinned)];
    }
    onShownChanged: root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.shown.length - 1))
    readonly property int unpinnedCount: Ai.history.filter(c => !c.pinned).length

    function daysAgo(time) {
        const day = new Date(time);
        day.setHours(0, 0, 0, 0);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return Math.round((today - day) / (24 * 60 * 60 * 1000));
    }
    function group(chat) {
        if (chat.pinned) return Translation.tr("Pinned");
        const days = root.daysAgo(chat.updated);
        return days <= 0 ? Translation.tr("Today") : days === 1 ? Translation.tr("Yesterday")
            : days < 7 ? Translation.tr("This week") : days < 30 ? Translation.tr("This month") : Translation.tr("Older");
    }
    function when(chat) {
        const date = new Date(chat.updated);
        const days = root.daysAgo(chat.updated);
        return days <= 0 ? Qt.formatTime(date, Config.options?.time?.format ?? "hh:mm")
            : days < 7 ? Qt.locale().toString(date, "ddd") : Qt.formatDate(date, Config.options?.time?.shortDateFormat ?? "dd/MM");
    }

    function open(chat) {
        if (!chat) return;
        Ai.openChat(chat.id);
        root.closed();
    }

    Timer {
        id: confirmReset
        interval: 4000
        onTriggered: root.confirmDeleteAll = false
    }

    component SmallIconButton: RippleButton {
        id: smallButton
        property string symbol
        property string hint
        property color symbolColor: Appearance.colors.colOnLayer1
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: smallButton.symbol
            fill: smallButton.toggled ? 1 : 0
            iconSize: Appearance.font.pixelSize.larger
            color: smallButton.symbolColor
        }
        StyledToolTip {
            text: smallButton.hint
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 6

        RowLayout { // Back, title, new conversation
            Layout.fillWidth: true
            spacing: 4
            SmallIconButton {
                symbol: "arrow_back"
                hint: Translation.tr("Back to the chat (Esc)")
                onClicked: root.closed()
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Conversations")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            SmallIconButton {
                symbol: "add_comment"
                hint: Translation.tr("New conversation")
                onClicked: {
                    Ai.clearMessages();
                    root.closed();
                }
            }
        }

        ToolbarTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 36
            colBackground: Appearance.colors.colLayer2
            placeholderText: Translation.tr("Search conversations")
            onTextChanged: root.selectedIndex = 0
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Down) {
                    root.selectedIndex = Math.min(root.shown.length - 1, root.selectedIndex + 1);
                    historyList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                    historyList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.open(root.shown[root.selectedIndex]);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    if (text.length > 0) text = "";
                    else root.closed();
                    event.accepted = true;
                } else if (event.key === Qt.Key_H && event.modifiers === Qt.ControlModifier) {
                    root.closed();
                    event.accepted = true;
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: historyList
                anchors.fill: parent
                clip: true
                spacing: 2
                popin: false
                model: root.shown
                delegate: ColumnLayout {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool current: modelData.id === Ai.chatId
                    readonly property bool selected: index === root.selectedIndex
                    property bool editing: false
                    width: historyList.width
                    spacing: 2

                    StyledText { // The group, above its first conversation
                        visible: entry.index === 0 || root.group(root.shown[entry.index - 1]) !== root.group(entry.modelData)
                        Layout.topMargin: entry.index === 0 ? 0 : 8
                        Layout.leftMargin: 8
                        text: root.group(entry.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        id: entryButton
                        Layout.fillWidth: true
                        implicitHeight: entryRow.implicitHeight + 12
                        buttonRadius: Appearance.rounding.small
                        toggled: entry.current
                        colBackground: entry.selected ? Appearance.colors.colLayer2Hover : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                        onClicked: if (!entry.editing) root.open(entry.modelData)
                        altAction: () => entry.editing = true
                        onHoveredChanged: if (hovered) root.selectedIndex = entry.index

                        contentItem: RowLayout {
                            id: entryRow
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 10
                                rightMargin: 4
                            }
                            spacing: 8

                            Item { // The model that answered
                                implicitWidth: Appearance.font.pixelSize.large
                                implicitHeight: Appearance.font.pixelSize.large
                                CustomIcon {
                                    id: chatModelIcon
                                    anchors.fill: parent
                                    visible: (Ai.models[entry.modelData.model]?.icon ?? "") !== ""
                                    source: Ai.models[entry.modelData.model]?.icon ?? ""
                                    colorize: true
                                    color: entry.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !chatModelIcon.visible
                                    text: "chat"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: entry.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    visible: !entry.editing
                                    Layout.fillWidth: true
                                    text: entry.modelData.title
                                    elide: Text.ElideRight
                                    color: entry.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                                ToolbarTextField {
                                    id: renameField
                                    visible: entry.editing
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    implicitHeight: 30
                                    padding: 6
                                    colBackground: Appearance.colors.colLayer2
                                    onVisibleChanged: if (visible) {
                                        text = entry.modelData.title;
                                        selectAll();
                                        forceActiveFocus();
                                    }
                                    onAccepted: {
                                        Ai.renameChat(entry.modelData.id, text);
                                        entry.editing = false;
                                        searchField.forceActiveFocus();
                                    }
                                    onActiveFocusChanged: if (!activeFocus) entry.editing = false
                                    Keys.onEscapePressed: {
                                        entry.editing = false;
                                        searchField.forceActiveFocus();
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: [root.when(entry.modelData),
                                        Translation.tr("%1 messages").arg(entry.modelData.turns ?? 0),
                                        Ai.models[entry.modelData.model]?.name ?? ""].filter(s => s.length > 0).join(" · ")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: entry.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                            }

                            // Shown on hover (a pin stays shown).
                            RowLayout {
                                spacing: 0
                                readonly property bool reveal: entryButton.hovered || entry.selected || entry.editing
                                SmallIconButton {
                                    visible: parent.reveal
                                    symbol: "edit"
                                    hint: Translation.tr("Rename (right-click)")
                                    onClicked: entry.editing = true
                                }
                                SmallIconButton {
                                    visible: parent.reveal || entry.modelData.pinned
                                    symbol: "push_pin"
                                    toggled: entry.modelData.pinned
                                    colBackgroundToggled: "transparent"
                                    colBackgroundToggledHover: Appearance.colors.colLayer2Hover
                                    colRippleToggled: Appearance.colors.colLayer2Active
                                    symbolColor: entry.modelData.pinned ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                    hint: entry.modelData.pinned ? Translation.tr("Unpin")
                                        : Translation.tr("Pin: kept until you delete it")
                                    onClicked: Ai.setChatPinned(entry.modelData.id, !entry.modelData.pinned)
                                }
                                SmallIconButton {
                                    visible: parent.reveal
                                    symbol: "delete"
                                    hint: Translation.tr("Delete")
                                    onClicked: Ai.deleteChat(entry.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.shown.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: Ai.history.length === 0
                    ? Translation.tr("No conversations yet.\nThey're saved here as you chat.")
                    : Translation.tr("No conversation matches.")
                color: Appearance.colors.colSubtext
            }
        }

        RowLayout { // How long they're kept; deleting them all
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol {
                text: "auto_delete"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: Ai.historyKeepDays > 0
                    ? Translation.tr("Deleted after %1 days without a message, unless pinned").arg(Ai.historyKeepDays)
                    : Translation.tr("Kept until you delete them")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                StyledToolTip {
                    text: Translation.tr("Change it in Settings > Services > AI")
                    extraVisibleCondition: false
                    alternativeVisibleCondition: keepHover.containsMouse
                }
                MouseArea {
                    id: keepHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }
            RippleButton {
                visible: root.unpinnedCount > 0
                implicitHeight: 30
                implicitWidth: deleteAllRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                toggled: root.confirmDeleteAll
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colError
                colBackgroundToggledHover: Appearance.colors.colErrorHover
                colRippleToggled: Appearance.colors.colErrorActive
                onClicked: {
                    if (!root.confirmDeleteAll) {
                        root.confirmDeleteAll = true;
                        confirmReset.restart();
                        return;
                    }
                    root.confirmDeleteAll = false;
                    Ai.deleteUnpinnedChats();
                }
                contentItem: RowLayout {
                    id: deleteAllRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: "delete_sweep"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.confirmDeleteAll ? Appearance.colors.colOnError : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: root.confirmDeleteAll ? Translation.tr("Delete %1?").arg(root.unpinnedCount)
                            : Translation.tr("Delete all")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.confirmDeleteAll ? Appearance.colors.colOnError : Appearance.colors.colOnLayer1
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Delete every conversation but the pinned ones")
                }
            }
        }
    }
}
