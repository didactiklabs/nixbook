pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The right sidebar's Mesh tab (services/Mesh.qml): the conversations
 * (everyone, then each member, with their status and unread count), the one
 * picked, quick messages and a field to write. Files (the clip button, a
 * drop, or Ctrl+V of a copied image or file) wait above the field and go
 * when it is sent, the text with the first.
 */
Item {
    id: root

    readonly property string conv: Mesh.conversation
    readonly property var shown: Mesh.messagesIn(root.conv)

    // Files to send with the next message: [path].
    property var pending: []
    function attach(path) {
        path = FileUtils.trimFileProtocol(`${path}`);
        if (path !== "" && !root.pending.includes(path)) root.pending = [...root.pending, path];
    }
    function send(text) {
        if (root.pending.length > 0) {
            if (Mesh.sendFiles(root.pending, text, root.conv)) {
                root.pending = [];
                input.text = "";
            }
            return;
        }
        if (Mesh.sendText(text, root.conv)) input.text = "";
    }

    ChatAttacher {
        id: attacher
        pickFolder: Directories.home
        pickFilter: ""
        pickMultiple: true
        onAttached: path => root.attach(path)
    }

    // Not set up yet.
    PagePlaceholder {
        shown: !Mesh.configured
        icon: "hub"
        title: Translation.tr("Mesh")
        description: Translation.tr("Talk with the people you choose, desktop to desktop: set it up in Settings > General > Mesh.")
        shape: MaterialShape.Shape.Clover4Leaf
        descriptionHorizontalAlignment: Text.AlignHCenter
    }
    RippleButtonWithIcon {
        visible: !Mesh.configured
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        materialIcon: "settings"
        mainText: Translation.tr("Set up the mesh")
        onClicked: Mesh.openSettings()
    }

    ColumnLayout {
        anchors.fill: parent
        visible: Mesh.configured
        spacing: 8

        // The conversations.
        StyledFlickable {
            Layout.fillWidth: true
            implicitHeight: chips.implicitHeight
            contentWidth: chips.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            Row {
                id: chips
                spacing: 6
                Repeater {
                    model: [{ id: "" }, ...Mesh.memberList]
                    delegate: RippleButton {
                        id: chip
                        required property var modelData
                        readonly property string memberId: chip.modelData.id
                        readonly property int unread: Mesh.unreadIn(chip.memberId)
                        toggled: Mesh.conversation === chip.memberId
                        buttonRadius: Appearance.rounding.full
                        implicitHeight: 36
                        implicitWidth: chipRow.implicitWidth + 24
                        onClicked: Mesh.conversation = chip.memberId
                        contentItem: RowLayout {
                            id: chipRow
                            spacing: 6
                            Item {
                                implicitWidth: 22
                                implicitHeight: 22
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondaryContainer
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: chip.memberId === ""
                                        text: "groups"
                                        iconSize: 16
                                        color: chip.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: chip.memberId !== ""
                                        text: Mesh.nameOf(chip.memberId).charAt(0).toUpperCase()
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: chip.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                                Rectangle {
                                    visible: chip.memberId !== ""
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    border.width: 1.5
                                    border.color: Appearance.colors.colLayer1
                                    color: Mesh.stateColor(Mesh.stateOf(chip.memberId))
                                }
                            }
                            StyledText {
                                text: Mesh.nameOf(chip.memberId)
                                color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                            Rectangle {
                                visible: chip.unread > 0
                                implicitHeight: 18
                                implicitWidth: Math.max(18, unreadText.implicitWidth + 8)
                                radius: 9
                                color: Appearance.colors.colPrimary
                                StyledText {
                                    id: unreadText
                                    anchors.centerIn: parent
                                    text: chip.unread
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

        // How the others see you.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: Mesh.stateColor(Mesh.myState)
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("You (%1): %2").arg(Mesh.myName).arg(Mesh.myStateText)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // Who it is with, and how they are.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: root.conv === "" ? "groups" : "person"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Mesh.nameOf(root.conv)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.conv === ""
                        ? (Mesh.memberList.length === 0 ? Translation.tr("No one else yet: members appear when they come online")
                            : Translation.tr("%1 around").arg(Mesh.around))
                        : Mesh.statusLine(root.conv)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            MaterialSymbol {
                visible: !Mesh.connected
                text: "cloud_off"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3error
            }
        }
        // A private conversation: sealed for their key alone.
        StyledText {
            Layout.fillWidth: true
            visible: root.conv !== "" && !Mesh.keyChanged(root.conv)
            wrapMode: Text.Wrap
            text: Mesh.keys[root.conv]
                ? Translation.tr("🔒 Only %1 can read these · their key %2").arg(Mesh.nameOf(root.conv)).arg(Mesh.keys[root.conv].fingerprint)
                : Translation.tr("🔒 Private messages are sealed for %1's key: it comes with their first message or status.").arg(Mesh.nameOf(root.conv))
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.conv !== "" && Mesh.keyChanged(root.conv)
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("%1's key changed (a new computer, or someone posing as them): private messages from and to them are held back. New key: %2. If you're not sure, ask them.")
                    .arg(Mesh.nameOf(root.conv)).arg(Mesh.keys[root.conv]?.changed ?? "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }
            RippleButtonWithIcon {
                materialIcon: "verified_user"
                mainText: Translation.tr("Trust the new key")
                onClicked: Mesh.trustKey(root.conv)
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: !Mesh.connected
            wrapMode: Text.Wrap
            text: Mesh.lastError || Translation.tr("Not connected to the mesh's server: messages wait here until it is back.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3error
        }

        // The messages.
        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.shown
            // The newest at the bottom, in view.
            onCountChanged: Qt.callLater(list.positionViewAtEnd)
            Component.onCompleted: Qt.callLater(list.positionViewAtEnd)
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool mine: row.modelData.mine
                readonly property var prev: row.index > 0 ? root.shown[row.index - 1] : null
                readonly property bool showName: !row.mine && root.conv === "" && (row.prev?.from !== row.modelData.from)
                width: list.width
                implicitHeight: bubble.implicitHeight + (row.showName ? nameText.implicitHeight + 2 : 0)

                StyledText {
                    id: nameText
                    visible: row.showName
                    x: 10
                    text: row.modelData.name || Mesh.nameOf(row.modelData.from)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Rectangle {
                    id: bubble
                    y: row.showName ? nameText.implicitHeight + 2 : 0
                    anchors.right: row.mine ? parent.right : undefined
                    anchors.left: row.mine ? undefined : parent.left
                    width: Math.min(list.width * 0.82, bubbleColumn.implicitWidth + 20)
                    implicitHeight: bubbleColumn.implicitHeight + 12
                    radius: Appearance.rounding.normal
                    color: row.mine ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    ColumnLayout {
                        id: bubbleColumn
                        anchors.fill: parent
                        anchors.margins: 6
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 2
                        MeshAttachment {
                            visible: !!row.modelData.file
                            message: row.modelData
                            maxWidth: list.width * 0.82 - 20
                            textColor: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            subColor: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                        StyledText {
                            visible: row.modelData.text !== ""
                            Layout.fillWidth: true
                            Layout.maximumWidth: list.width * 0.82 - 20
                            text: row.modelData.text
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            color: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: row.mine ? Qt.AlignRight : Qt.AlignLeft
                            text: {
                                const when = Qt.locale().toString(new Date(row.modelData.time), Config.options?.time.format ?? "hh:mm");
                                if (!row.mine) return when;
                                if (row.modelData.status === "failed")
                                    return row.modelData.error ? Translation.tr("%1 · not sent: %2 (click to retry)").arg(when).arg(row.modelData.error)
                                        : Translation.tr("%1 · not sent, click to retry").arg(when);
                                if (row.modelData.status === "sending") return Translation.tr("%1 · sending…").arg(when);
                                const seen = row.modelData.to !== "" && (Mesh.members[row.modelData.to]?.readUpTo ?? 0) >= row.modelData.time;
                                return seen ? Translation.tr("%1 · seen").arg(when) : when;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: row.modelData.status === "failed" ? Appearance.m3colors.m3error
                                : (row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext)
                            opacity: 0.8
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: row.modelData.status === "failed"
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: Mesh.retry(row.modelData.mid)
                    }
                }
            }
        }

        // Quick messages.
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Config.options?.mesh?.quickMessages ?? []
                delegate: RippleButton {
                    id: quick
                    required property string modelData
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    implicitHeight: 30
                    implicitWidth: quickText.implicitWidth + 20
                    onClicked: root.send(quick.modelData)
                    contentItem: StyledText {
                        id: quickText
                        horizontalAlignment: Text.AlignHCenter
                        text: quick.modelData
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        // The files that go with the next message.
        Flow {
            Layout.fillWidth: true
            visible: root.pending.length > 0
            spacing: 6
            Repeater {
                model: root.pending
                delegate: Rectangle {
                    id: pendingChip
                    required property string modelData
                    implicitHeight: 30
                    implicitWidth: Math.min(list.width, pendingRow.implicitWidth + 16)
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                    RowLayout {
                        id: pendingRow
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 4
                        spacing: 4
                        MaterialSymbol {
                            text: /\.(png|jpe?g|gif|webp|avif|bmp)$/i.test(pendingChip.modelData) ? "image" : "attach_file"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.maximumWidth: list.width - 70
                            text: pendingChip.modelData.split("/").pop()
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        RippleButton {
                            implicitWidth: 22
                            implicitHeight: 22
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.pending = root.pending.filter(p => p !== pendingChip.modelData)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "close"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                onClicked: attacher.pick()
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "attach_file"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: {
                        const limit = Mesh.maxFileBytes > 0 ? Translation.tr(" (up to %1)").arg(Mesh.sizeText(Mesh.maxFileBytes)) : "";
                        const kept = Mesh.fileExpiry > 0 ? Translation.tr("\nThe server keeps it %1 h, encrypted").arg(Math.round(Mesh.fileExpiry / 3600)) : "";
                        return Translation.tr("Send files%1: pick them, drop them here, or paste a copied image (Ctrl+V)").arg(limit) + kept;
                    }
                }
            }
            MaterialTextField {
                id: input
                Layout.fillWidth: true
                placeholderText: root.conv === "" ? Translation.tr("To everyone…")
                    : Translation.tr("To %1…").arg(Mesh.nameOf(root.conv))
                focus: Mesh.viewing
                onAccepted: root.send(input.text)
                Keys.onPressed: event => {
                    if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V) {
                        // A copied image or file is attached, text pasted.
                        event.accepted = attacher.paste(input);
                    } else if (event.key === Qt.Key_Escape && root.pending.length > 0) {
                        root.pending = [];
                        event.accepted = true;
                    }
                }
            }
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                enabled: input.text.trim() !== "" || root.pending.length > 0
                colBackground: Appearance.colors.colPrimary
                onClicked: root.send(input.text)
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "send"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // Files dropped on the tab: they wait above the field.
    DropArea {
        id: drop
        anchors.fill: parent
        enabled: Mesh.configured
        onDropped: event => {
            const urls = event.hasUrls ? event.urls.map(u => u.toString()).filter(u => u.startsWith("file://")) : [];
            for (const u of urls) root.attach(decodeURIComponent(u));
            if (urls.length > 0) {
                event.acceptProposedAction();
                input.forceActiveFocus();
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: drop.containsDrag
        radius: Appearance.rounding.normal
        color: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.15)
        border.width: 2
        border.color: Appearance.colors.colPrimary
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "upload_file"
                iconSize: 40
                color: Appearance.colors.colOnPrimaryContainer
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Drop to send to %1").arg(Mesh.nameOf(root.conv))
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }

    // Opening the tab: the field takes the keyboard.
    Connections {
        target: Mesh
        function onViewingChanged() {
            if (Mesh.viewing) input.forceActiveFocus();
        }
    }
}
