pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The right sidebar's Mesh tab (services/Mesh.qml): the conversations
 * (everyone, then each member, with their status and unread count), the one
 * picked, quick messages and a field to write. Files (the clip button, a
 * drop, or Ctrl+V of a copied image or file) wait above the field and go
 * when it is sent, the text with the first. Hovering a message shows its
 * react button (an emoji, Mesh.reactionChoices) and its delete button (a
 * second click confirms): your own for everyone, anyone's for this desktop
 * only. Members show their shared picture (MeshAvatar).
 */
Item {
    id: root

    readonly property string conv: Mesh.conversation
    readonly property var shown: Mesh.messagesIn(root.conv)

    // A message's text as rich text: escaped, line breaks kept, its http(s)
    // links clickable (in `linkColor`, underlined). Nothing else of the
    // sender's is markup.
    function linkified(text, linkColor) {
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
        const re = /https?:\/\/[^\s<>"']+/g;
        let out = "", last = 0, m;
        while ((m = re.exec(text)) !== null) {
            // Not the punctuation a sentence puts after a link.
            let url = m[0].replace(/[.,;:!?)\]}]+$/, "");
            out += esc(text.slice(last, m.index));
            out += `<a href="${esc(url)}" style="color: ${linkColor}; text-decoration: underline">${esc(url)}</a>`;
            last = m.index + url.length;
            re.lastIndex = last;
        }
        out += esc(text.slice(last));
        return out.replace(/\n/g, "<br>");
    }

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

    component ShareButton: RippleButton {
        id: share
        property string kind
        property string symbol
        property bool can
        property string tip
        visible: !MeshListen.hostingIn(root.conv) && !MeshListen.sessionIn(root.conv)
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        onClicked: MeshListen.notice = MeshListen.start(root.conv, share.kind)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: share.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: share.can ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: share.tip
        }
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
                                    visible: chip.memberId === ""
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondaryContainer
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "groups"
                                        iconSize: 16
                                        color: chip.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                                MeshAvatar {
                                    visible: chip.memberId !== ""
                                    anchors.fill: parent
                                    size: 22
                                    memberId: chip.memberId
                                    onPrimary: chip.toggled
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
                visible: root.conv === ""
                text: "groups"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            MeshAvatar {
                visible: root.conv !== ""
                size: 32
                memberId: root.conv
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
            // Listening / watching together: share what plays here, music
            // (YouTube Music, Spotify) or Jellyfin, one button each.
            ShareButton {
                kind: "music"
                symbol: "headphones"
                can: MeshListen.canShareMusic
                tip: MeshListen.canShareMusic
                    ? Translation.tr("Listen together: share what your %1 plays with %2; they can listen along")
                        .arg(MeshListen.serviceName(MeshListen.serviceOf(MeshListen.shareablePlayer("music")))).arg(Mesh.nameOf(root.conv))
                    : Translation.tr("Listen together: play something in YouTube Music or Spotify, then share it here")
            }
            ShareButton {
                kind: "video"
                symbol: "movie"
                visible: MeshListen.videoOffered && !MeshListen.hostingIn(root.conv) && !MeshListen.sessionIn(root.conv)
                can: MeshListen.canShareVideo
                tip: MeshListen.canShareVideo
                    ? Translation.tr("Watch together: share what Jellyfin plays on this computer with %1; they can watch along on their own Jellyfin").arg(Mesh.nameOf(root.conv))
                    : Translation.tr("Watch together: play something from Jellyfin on this computer (its player), then share it here")
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

        MeshListenBar {
            Layout.fillWidth: true
            conv: root.conv
        }

        // The messages.
        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            // One row per message id, diffed (ScriptModel compares the ids):
            // a new message adds its row, a reaction or a status only updates
            // its own (row.msg follows Mesh.byMid). A plain array rebuilt every
            // row on each change, flickering and jumping to the end.
            model: ScriptModel {
                values: root.shown.map(m => m.mid)
            }
            // Every row built (a conversation keeps 500 at most): ListView
            // otherwise guesses the height of the rows not built yet, and a
            // new message changing that guess clamped the view to its end
            // while you were reading higher up.
            cacheBuffer: 1000000
            // The newest at the bottom, in view: when the list was left at
            // (or near) its end, or the new message is yours. Scrolled up to
            // read, it stays where it is.
            property real bottomGap: 0
            property bool autoScrolling: false
            property int lastCount: 0
            // How far the end is below what is shown (ListView's contentY
            // counts from originY, which moves as rows get their height).
            function gapToEnd() {
                return Math.max(0, list.originY + list.contentHeight - list.contentY - list.height);
            }
            function toEnd() {
                list.autoScrolling = true;
                list.positionViewAtEnd();
                autoScrollDone.restart();
            }
            Timer {
                id: autoScrollDone
                interval: 500
                onTriggered: {
                    list.autoScrolling = false;
                    list.bottomGap = list.gapToEnd();
                }
            }
            onContentYChanged: if (!list.autoScrolling) list.bottomGap = list.gapToEnd()
            onCountChanged: {
                const grew = list.count > list.lastCount;
                list.lastCount = list.count;
                if (grew && (list.bottomGap < 80 || root.shown[root.shown.length - 1]?.mine)) Qt.callLater(list.toEnd);
            }
            Component.onCompleted: {
                list.lastCount = list.count;
                Qt.callLater(list.toEnd);
            }
            Connections {
                target: root
                function onConvChanged() { Qt.callLater(list.toEnd); }
            }
            delegate: Item {
                id: row
                required property string modelData
                required property int index
                // The message itself, live: its reactions, status, deletion.
                readonly property var msg: Mesh.byMid[row.modelData] ?? ({ mid: row.modelData, text: "", time: 0 })
                readonly property bool mine: row.msg.mine
                readonly property var prev: row.index > 0 ? root.shown[row.index - 1] : null
                readonly property bool firstOfRun: row.prev?.from !== row.msg.from
                readonly property bool showName: !row.mine && root.conv === "" && row.firstOfRun
                // Everyone's conversation: the sender's picture beside their
                // first message of a run, their messages lined up after it.
                readonly property real indent: !row.mine && root.conv === "" ? 34 : 0
                readonly property real maxWidth: (list.width - row.indent) * 0.8
                readonly property bool deleted: !!row.msg.deleted
                readonly property var reactions: row.deleted ? [] : Object.keys(row.msg.reactions ?? {})
                    .map(e => ({ emoji: e, who: row.msg.reactions[e] }))
                // Your own: for everyone; anyone's (or yours from before
                // deleting existed, to everyone): for this desktop.
                readonly property bool forEveryone: Mesh.canDeleteForEveryone(row.msg)
                property bool armed: false
                property bool picking: false
                readonly property bool busy: !!row.msg.deleting || row.msg.status === "sending"
                width: list.width
                implicitHeight: bubble.y + bubble.height + (row.reactions.length > 0 ? reactionRow.implicitHeight + 3 : 0)
                    + (row.picking ? picker.implicitHeight + 4 : 0)

                HoverHandler {
                    id: rowHover
                }
                Timer {
                    id: disarm
                    interval: 3000
                    onTriggered: row.armed = false
                }

                MeshAvatar {
                    visible: row.indent > 0 && row.firstOfRun
                    x: 0
                    y: bubble.y
                    size: 28
                    memberId: row.msg.from
                }
                StyledText {
                    id: nameText
                    visible: row.showName
                    x: row.indent + 10
                    text: row.msg.name || Mesh.nameOf(row.msg.from)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // React and delete, beside the message while hovered.
                Row {
                    id: actions
                    visible: (rowHover.hovered || row.armed || row.picking) && !row.busy
                    anchors.verticalCenter: bubble.verticalCenter
                    anchors.right: row.mine ? bubble.left : undefined
                    anchors.left: row.mine ? undefined : bubble.right
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    layoutDirection: row.mine ? Qt.RightToLeft : Qt.LeftToRight
                    spacing: 2
                    RippleButton {
                        id: reactButton
                        visible: !row.deleted
                        implicitHeight: 26
                        implicitWidth: 26
                        buttonRadius: Appearance.rounding.full
                        toggled: row.picking
                        onClicked: row.picking = !row.picking
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: "add_reaction"
                            iconSize: Appearance.font.pixelSize.normal
                            color: row.picking ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: Translation.tr("React")
                        }
                    }
                    RippleButton {
                        visible: !row.deleted && (row.msg.text ?? "") !== ""
                        implicitHeight: 26
                        implicitWidth: 26
                        buttonRadius: Appearance.rounding.full
                        property bool copied: false
                        onClicked: {
                            Clipboard.copy(row.msg.text);
                            copied = true;
                            copiedReset.restart();
                        }
                        Timer {
                            id: copiedReset
                            interval: 1500
                            onTriggered: parent.copied = false
                        }
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.copied ? "check" : "content_copy"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: Translation.tr("Copy the text")
                        }
                    }
                    // Delete: a click arms it, a second within 3 s deletes.
                    RippleButton {
                        id: deleteButton
                        implicitHeight: 26
                        implicitWidth: 26
                        buttonRadius: Appearance.rounding.full
                        colBackground: row.armed ? Appearance.m3colors.m3error : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                        colBackgroundHover: row.armed ? Appearance.m3colors.m3error : Appearance.colors.colLayer1Hover
                        onClicked: {
                            if (!row.armed) {
                                row.armed = true;
                                disarm.restart();
                                return;
                            }
                            row.armed = false;
                            disarm.stop();
                            if (row.forEveryone) Mesh.deleteForEveryone(row.msg.mid);
                            else Mesh.deleteForMe(row.msg.mid);
                        }
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: row.armed ? "delete_forever" : "delete"
                            iconSize: Appearance.font.pixelSize.normal
                            color: row.armed ? Appearance.m3colors.m3onError : Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: row.armed
                                ? (row.forEveryone ? Translation.tr("Click again to delete it for everyone") : Translation.tr("Click again to delete it on this computer"))
                                : (row.forEveryone ? Translation.tr("Delete for everyone") : Translation.tr("Delete on this computer"))
                        }
                    }
                }

                Rectangle {
                    id: bubble
                    y: row.showName ? nameText.implicitHeight + 2 : 0
                    x: row.mine ? row.width - bubble.width : row.indent
                    width: Math.min(row.maxWidth, bubbleColumn.implicitWidth + 20)
                    implicitHeight: bubbleColumn.implicitHeight + 12
                    radius: Appearance.rounding.normal
                    color: row.deleted ? "transparent" : (row.mine ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2)
                    border.width: row.deleted ? 1 : 0
                    border.color: Appearance.colors.colOutlineVariant
                    ColumnLayout {
                        id: bubbleColumn
                        anchors.fill: parent
                        anchors.margins: 6
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 2
                        StyledText {
                            visible: row.deleted
                            text: row.mine ? Translation.tr("You deleted this message") : Translation.tr("This message was deleted")
                            font.italic: true
                            color: Appearance.colors.colSubtext
                        }
                        MeshAttachment {
                            visible: !!row.msg.file
                            message: row.msg
                            maxWidth: row.maxWidth - 20
                            textColor: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            subColor: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                        // Selectable (drag; Ctrl+C), its links clickable.
                        TextEdit {
                            id: messageText
                            visible: row.msg.text !== ""
                            Layout.fillWidth: true
                            Layout.maximumWidth: row.maxWidth - 20
                            readOnly: true
                            selectByMouse: true
                            persistentSelection: false
                            textFormat: TextEdit.RichText
                            text: root.linkified(row.msg.text ?? "", row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary)
                            wrapMode: TextEdit.Wrap
                            color: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            selectionColor: Appearance.colors.colPrimary
                            selectedTextColor: Appearance.colors.colOnPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.variableAxes: Appearance.font.variableAxes.main
                            onLinkActivated: link => AppLaunch.openUrl(link)
                            Keys.onPressed: event => {
                                if (event.matches(StandardKey.Copy) && messageText.selectedText !== "") {
                                    // Through wl-copy: the compositor may ignore a copy
                                    // from a panel's own clipboard (Clipboard.copy).
                                    Clipboard.copy(messageText.selectedText);
                                    event.accepted = true;
                                } else if (event.text !== "" && event.text.charCodeAt(0) >= 32
                                        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                                    // Typing after selecting: back to the field.
                                    input.forceActiveFocus();
                                    input.insert(input.cursorPosition, event.text);
                                    event.accepted = true;
                                }
                            }
                            // The link under the pointer: hoveredLink reads the global
                            // cursor position, unknown on Wayland (NotesWidget does the same).
                            readonly property string hoveredUrl: textHover.hovered
                                ? messageText.linkAt(textHover.point.position.x, textHover.point.position.y) : ""
                            HoverHandler {
                                id: textHover
                                cursorShape: messageText.hoveredUrl !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                            }
                        }
                        StyledText {
                            Layout.alignment: row.mine ? Qt.AlignRight : Qt.AlignLeft
                            text: {
                                const when = Qt.locale().toString(new Date(row.msg.time), Config.options?.time.format ?? "hh:mm");
                                if (!row.mine || row.deleted) return when;
                                if (row.msg.deleting) return Translation.tr("%1 · deleting…").arg(when);
                                if (row.msg.deleteError)
                                    return Translation.tr("%1 · couldn't delete: %2").arg(when).arg(row.msg.deleteError);
                                if (row.msg.status === "failed")
                                    return row.msg.error ? Translation.tr("%1 · not sent: %2 (click to retry)").arg(when).arg(row.msg.error)
                                        : Translation.tr("%1 · not sent, click to retry").arg(when);
                                if (row.msg.status === "sending") return Translation.tr("%1 · sending…").arg(when);
                                const seen = row.msg.to !== "" && (Mesh.members[row.msg.to]?.readUpTo ?? 0) >= row.msg.time;
                                return seen ? Translation.tr("%1 · seen").arg(when) : when;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: row.msg.status === "failed" || (!!row.msg.deleteError && !row.deleted) ? Appearance.m3colors.m3error
                                : (row.mine && !row.deleted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext)
                            opacity: 0.8
                        }
                    }
                    // Only on a message that failed (click to retry).
                    MouseArea {
                        anchors.fill: parent
                        visible: row.msg.status === "failed"
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Mesh.retry(row.msg.mid)
                    }
                }

                // The reactions: an emoji and how many; yours highlighted, a
                // click takes yours back or adds it.
                Row {
                    id: reactionRow
                    visible: row.reactions.length > 0
                    y: bubble.y + bubble.height + 3
                    x: row.mine ? row.width - reactionRow.width : row.indent + 4
                    layoutDirection: row.mine ? Qt.RightToLeft : Qt.LeftToRight
                    spacing: 4
                    Repeater {
                        model: row.reactions
                        delegate: RippleButton {
                            id: chipReaction
                            required property var modelData
                            readonly property bool byMe: chipReaction.modelData.who.includes(Mesh.me)
                            implicitHeight: 24
                            implicitWidth: reactionText.implicitWidth + 14
                            buttonRadius: Appearance.rounding.full
                            toggled: chipReaction.byMe
                            colBackground: Appearance.colors.colLayer2
                            onClicked: Mesh.react(row.msg.mid, chipReaction.modelData.emoji)
                            contentItem: StyledText {
                                id: reactionText
                                horizontalAlignment: Text.AlignHCenter
                                text: chipReaction.modelData.who.length > 1
                                    ? `${chipReaction.modelData.emoji} ${chipReaction.modelData.who.length}` : chipReaction.modelData.emoji
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: chipReaction.byMe ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                            StyledToolTip {
                                text: chipReaction.modelData.who.map(id => id === Mesh.me ? Translation.tr("You") : Mesh.nameOf(id)).join(", ")
                            }
                        }
                    }
                }

                // Picking a reaction.
                Rectangle {
                    id: picker
                    visible: row.picking
                    y: bubble.y + bubble.height + (row.reactions.length > 0 ? reactionRow.implicitHeight + 3 : 0) + 4
                    x: row.mine ? row.width - picker.width : row.indent
                    implicitWidth: pickerRow.implicitWidth + 8
                    implicitHeight: pickerRow.implicitHeight + 8
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    Row {
                        id: pickerRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: Mesh.reactionChoices
                            delegate: RippleButton {
                                id: choice
                                required property string modelData
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                toggled: (row.msg.reactions?.[choice.modelData] ?? []).includes(Mesh.me)
                                onClicked: {
                                    Mesh.react(row.msg.mid, choice.modelData);
                                    row.picking = false;
                                }
                                contentItem: StyledText {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: choice.modelData
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                }
                            }
                        }
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
                        const kept = Mesh.fileExpiry > 0 ? Translation.tr("\nThe server keeps it %1, encrypted").arg(Mesh.durationText(Mesh.fileExpiry)) : "";
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
