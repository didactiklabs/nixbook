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

    // The list on screen (one per conversation opened: `lists`).
    property var currentList: null

    // The ✨ picker (nudges, quick messages) open.
    property bool picking: false
    // The picker's tab: "nudges" or "moods" (How I feel).
    property string pickerTab: "nudges"
    onConvChanged: {
        root.picking = false;
        root.replyTo = null;
    }

    // Files to send with the next message: [path].
    property var pending: []
    function attach(path) {
        path = FileUtils.trimFileProtocol(`${path}`);
        if (path !== "" && !root.pending.includes(path)) root.pending = [...root.pending, path];
    }
    function send(text) {
        if (root.pending.length > 0) {
            if (Mesh.sendFiles(root.pending, text, root.conv, root.replyTo)) {
                root.pending = [];
                input.text = "";
                root.replyTo = null;
            }
            return;
        }
        if (Mesh.sendText(text, root.conv, "", root.replyTo)) {
            input.text = "";
            root.replyTo = null;
        }
    }

    // The message answered by the next one (Mesh.replyOf: {mid, from,
    // text}), shown above the field; null for none.
    property var replyTo: null
    function startReply(m) {
        root.replyTo = Mesh.replyOf(m);
        input.forceActiveFocus();
    }
    // A quote clicked: its message, centred and flashed.
    property string flashMid: ""
    function jumpTo(mid) {
        if (!root.currentList?.jumpTo(mid)) return;
        root.flashMid = mid;
        flashOff.restart();
    }
    Timer {
        id: flashOff
        interval: 1600
        onTriggered: root.flashMid = ""
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
        description: Translation.tr("Talk with the people you choose, desktop to desktop: set it up in Settings > Mesh.")
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
                    ? Translation.tr("Watch together: share what %1 plays on this computer with %2; they can watch along")
                        .arg(MeshListen.serviceName(MeshListen.serviceOf(MeshListen.shareablePlayer("video")))).arg(Mesh.nameOf(root.conv))
                    : Translation.tr("Watch together: play a video from the YouTube tab, or something from Jellyfin on this computer, then share it here")
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

        // The messages: one list per conversation, built when it is first
        // opened and kept, so going back to one is only showing it again
        // (rebuilding Everyone's 300 rows on each switch made it lag); each
        // keeps where it was scrolled to.
        Item {
            id: lists
            Layout.fillWidth: true
            Layout.fillHeight: true
            property var opened: [root.conv]
            function open(c) {
                if (!lists.opened.includes(c)) lists.opened = [...lists.opened, c];
            }
            Connections {
                target: root
                function onConvChanged() { lists.open(root.conv); }
            }
            Repeater {
                model: lists.opened
                delegate: Loader {
                    id: convLoader
                    required property string modelData
                    anchors.fill: parent
                    visible: convLoader.modelData === root.conv
                    // Built off the GUI thread's way when it can (a first open).
                    asynchronous: true
                    sourceComponent: convList
                    onLoaded: convLoader.item.conv = convLoader.modelData
                    Binding {
                        when: convLoader.modelData === root.conv && convLoader.item !== null
                        root.currentList: convLoader.item
                    }
                }
            }
        }
        Component {
            id: convList
            StyledListView {
                id: list
                // The conversation this list shows, and its messages: the last
                // `limit` of them, older ones loaded 60 at a time when scrolled
                // near the top (all 300 rows of Everyone's built at once lagged).
                property string conv
                readonly property var all: Mesh.messagesIn(list.conv)
                property int limit: 60
                readonly property var shown: list.all.length > list.limit ? list.all.slice(list.all.length - list.limit) : list.all
                readonly property bool hasOlder: list.all.length > list.limit
                property bool loadingOlder: false
                function loadOlder() {
                    if (!list.hasOlder || list.loadingOlder) return;
                    list.loadingOlder = true;
                    list.limit += 60;
                    Qt.callLater(() => list.loadingOlder = false);
                }
                // Your last message here (Everyone's "seen by" goes under it).
                readonly property string lastMineMid: list.shown.filter(m => m.mine && !m.deleted).slice(-1)[0]?.mid ?? ""
                // A quote clicked: its message, centred (root.jumpTo flashes it).
                function jumpTo(mid) {
                    // Older than what is loaded: loaded up to it first.
                    const inAll = list.all.findIndex(m => m.mid === mid);
                    if (inAll < 0) return false;
                    if (inAll < list.all.length - list.limit) list.limit = list.all.length - inAll + 10;
                    const at = list.shown.findIndex(m => m.mid === mid);
                    if (at < 0) return false;
                    list.positionViewAtIndex(at, ListView.Center);
                    return true;
                }
                clip: true
                spacing: 6
                // One row per message id, diffed (ScriptModel compares the ids):
                // a new message adds its row, a reaction or a status only updates
                // its own (row.msg follows Mesh.byMid). A plain array rebuilt every
                // row on each change, flickering and jumping to the end.
                model: ScriptModel {
                    values: list.shown.map(m => m.mid)
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
                // Kept at its end until you scroll up: re-pinned when its rows
                // or its size change (a list built in the background gets its
                // width late, rows rewrap) and when it shows again (messages
                // came while it was hidden). It used to open above the end.
                property bool following: true
                // How far the end is below what is shown (ListView's contentY
                // counts from originY, which moves as rows get their height).
                function gapToEnd() {
                    return Math.max(0, list.originY + list.contentHeight - list.contentY - list.height);
                }
                // `instant`: a jump, not the scroll animation (opening, showing
                // again, a re-pin).
                function toEnd(instant) {
                    list.autoScrolling = true;
                    if (instant) list.animateScroll = false;
                    list.positionViewAtEnd();
                    list.animateScroll = true;
                    list.following = true;
                    autoScrollDone.restart();
                }
                function pin() {
                    if (list.following && !list.loadingOlder) list.toEnd(true);
                }
                onContentHeightChanged: Qt.callLater(list.pin)
                onHeightChanged: Qt.callLater(list.pin)
                onVisibleChanged: if (list.visible) Qt.callLater(list.pin)
                Timer {
                    id: autoScrollDone
                    interval: 500
                    onTriggered: {
                        list.autoScrolling = false;
                        list.bottomGap = list.gapToEnd();
                        list.following = list.bottomGap < 80;
                    }
                }
                onContentYChanged: {
                    if (list.autoScrolling) return;
                    list.bottomGap = list.gapToEnd();
                    list.following = list.bottomGap < 80;
                    // Scrolled up near the top: the older ones (ListView keeps
                    // what is shown in place when rows come in above it).
                    if (!list.following && list.contentY - list.originY < 300 && list.hasOlder) list.loadOlder();
                }
                // A new message (the newest one changed): to the end when the
                // one before it was on screen (you were reading the end), or it
                // is yours. Not the row count: past `limit` messages a new one
                // drops the oldest, the count stays the same, and the view
                // stayed above it; nor the gap to the end alone, which the new
                // row's own height (an image, a long message) made too big.
                readonly property string newestMid: list.shown.length > 0 ? list.shown[list.shown.length - 1].mid : ""
                property string _prevNewest: ""
                onNewestMidChanged: {
                    const prev = list._prevNewest;
                    list._prevNewest = list.newestMid;
                    if (list.loadingOlder || prev === "" || list.newestMid === "") return;
                    const wasFollowing = list.following;
                    // After the model has its new row (ScriptModel updates on the
                    // same change).
                    Qt.callLater(() => {
                        const mine = !!list.shown[list.shown.length - 1]?.mine;
                        const i = list.shown.findIndex(m => m.mid === prev);
                        const it = i >= 0 ? list.itemAtIndex(i) : null;
                        const prevInView = it !== null && it.y < list.contentY + list.height + 80;
                        if (mine || wasFollowing || prevInView) list.toEnd(false);
                    });
                }
                Component.onCompleted: {
                    list._prevNewest = list.newestMid;
                    Qt.callLater(() => list.toEnd(true));
                }
                delegate: Item {
                    id: row
                    required property string modelData
                    required property int index
                    // The message itself, live: its reactions, status, deletion.
                    readonly property var msg: Mesh.byMid[row.modelData] ?? ({ mid: row.modelData, text: "", time: 0 })
                    readonly property bool mine: row.msg.mine
                    readonly property var prev: row.index > 0 ? list.shown[row.index - 1] : null
                    readonly property bool firstOfRun: row.prev?.from !== row.msg.from
                    readonly property bool showName: !row.mine && list.conv === "" && row.firstOfRun
                    // Everyone's conversation: the sender's picture beside their
                    // first message of a run, their messages lined up after it.
                    readonly property real indent: !row.mine && list.conv === "" ? 34 : 0
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
                        // The member's name now (each message keeps the one it came
                        // with: a renamed member showed under both).
                        text: Mesh.nameOf(row.msg.from)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    // Reply, react, copy and delete: a small toolbar on the
                    // bubble's top edge while hovered (Discord-like), beside it
                    // when there is room, over its corner when not, never out of
                    // the list.
                    Rectangle {
                        id: toolbar
                        z: 2
                        visible: actions.visible
                        readonly property real wanted: row.mine ? bubble.x - width - 4 : bubble.x + bubble.width + 4
                        x: Math.max(0, Math.min(row.width - width, toolbar.wanted))
                        y: Math.max(0, bubble.y - height / 2 + 4)
                        width: actions.implicitWidth + 6
                        height: actions.implicitHeight + 6
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                    }
                    Row {
                        id: actions
                        z: 3
                        visible: (rowHover.hovered || row.armed || row.picking) && !row.busy
                        x: toolbar.x + 3
                        y: toolbar.y + 3
                        layoutDirection: row.mine ? Qt.RightToLeft : Qt.LeftToRight
                        spacing: 0
                        RippleButton {
                            visible: !row.deleted && (row.msg.status ?? "sent") === "sent"
                            implicitHeight: 26
                            implicitWidth: 26
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.startReply(row.msg)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "reply"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                            StyledToolTip {
                                text: Translation.tr("Reply")
                            }
                        }
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
                        // Flashed when a reply's quote jumps to it.
                        readonly property bool flashed: root.flashMid !== "" && root.flashMid === row.msg.mid
                        border.width: bubble.flashed ? 2 : row.deleted ? 1 : 0
                        border.color: bubble.flashed ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        Behavior on border.width {
                            NumberAnimation { duration: 150 }
                        }
                        ColumnLayout {
                            id: bubbleColumn
                            anchors.fill: parent
                            anchors.margins: 6
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 2
                            // What it answers: the quoted message (live when kept here,
                            // else the snippet it came with); a click jumps to it.
                            Rectangle {
                                id: quote
                                readonly property var r: row.deleted ? null : row.msg.reply ?? null
                                readonly property var original: quote.r ? Mesh.byMid[quote.r.mid] ?? null : null
                                visible: quote.r !== null
                                Layout.fillWidth: true
                                Layout.maximumWidth: row.maxWidth - 20
                                Layout.bottomMargin: 2
                                implicitWidth: quoteColumn.implicitWidth + 14
                                implicitHeight: quoteColumn.implicitHeight + 8
                                radius: Appearance.rounding.small
                                color: ColorUtils.transparentize(row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2, 0.9)
                                Rectangle {
                                    width: 3
                                    height: parent.height
                                    radius: 1.5
                                    color: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                }
                                ColumnLayout {
                                    id: quoteColumn
                                    x: 10
                                    y: 4
                                    width: quote.width - 14
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: quote.r ? (quote.r.from === Mesh.me ? Translation.tr("You") : Mesh.nameOf(quote.r.from)) : ""
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: quote.original?.deleted ? Translation.tr("Original message was deleted")
                                            : quote.original ? Mesh.replyOf(quote.original).text : (quote.r?.text ?? "")
                                        font.italic: !!quote.original?.deleted
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: row.mine ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                        opacity: 0.85
                                    }
                                }
                                TapHandler {
                                    enabled: !!quote.original
                                    onTapped: root.jumpTo(quote.r.mid)
                                }
                                HoverHandler {
                                    cursorShape: quote.original ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                            }
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
                                    if (row.msg.to !== "") return Mesh.seen(row.msg) ? Translation.tr("%1 · seen").arg(when) : when;
                                    // Everyone's: who read it, under your last message only.
                                    if (row.msg.mid !== list.lastMineMid) return when;
                                    const by = Mesh.seenBy(row.msg);
                                    if (by.length === 0) return when;
                                    return by.length === 1 ? Translation.tr("%1 · seen by %2").arg(when).arg(Mesh.nameOf(by[0]))
                                        : Translation.tr("%1 · seen by %2").arg(when).arg(by.length);
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

        }

        // Nudges and quick messages (the ✨ button): one picker instead of
        // rows of chips. A nudge shows as its own cut-in on the other side
        // (Mesh.sendNudge, MeshNudge.qml); your quick messages
        // (mesh.quickMessages) go as plain messages.
        Rectangle {
            id: picker
            Layout.fillWidth: true
            visible: root.picking
            // Never taller than about half the tab: the moods made it
            // overflow the panel, the last rows and the field out of reach.
            implicitHeight: pickerHeader.implicitHeight + pickerFlick.height + 22
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            RowLayout {
                id: pickerHeader
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("Nudge %1: they get it as a cut-in").arg(Mesh.nameOf(root.conv))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: [{ id: "nudges", label: Translation.tr("Nudges") }, { id: "moods", label: Translation.tr("How I feel") }]
                    delegate: RippleButton {
                        id: tabChip
                        required property var modelData
                        readonly property bool on: root.pickerTab === tabChip.modelData.id
                        implicitHeight: 26
                        implicitWidth: tabText.implicitWidth + 18
                        buttonRadius: Appearance.rounding.full
                        colBackground: tabChip.on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                        colBackgroundHover: tabChip.on ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                        onClicked: {
                            root.pickerTab = tabChip.modelData.id;
                            pickerFlick.contentY = 0;
                        }
                        contentItem: StyledText {
                            id: tabText
                            horizontalAlignment: Text.AlignHCenter
                            text: tabChip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: tabChip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
            StyledFlickable {
                id: pickerFlick
                anchors { left: parent.left; right: parent.right; top: pickerHeader.bottom; margins: 8; topMargin: 6 }
                height: Math.min(pickerColumn.implicitHeight, Math.max(120, root.height * 0.45))
                contentHeight: pickerColumn.implicitHeight
                clip: true
                ColumnLayout {
                    id: pickerColumn
                    width: pickerFlick.width
                    spacing: 6
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 5
                            rowSpacing: 4
                            columnSpacing: 4
                            Repeater {
                                model: Mesh.nudges.filter(n => !!n.mood === (root.pickerTab === "moods"))
                                delegate: RippleButton {
                                    id: nudgeButton
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 54
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1)
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    onClicked: {
                                        Mesh.sendNudge(nudgeButton.modelData.id, root.conv);
                                        root.picking = false;
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: 0
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: nudgeButton.modelData.emoji
                                            font.pixelSize: Appearance.font.pixelSize.larger
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.maximumWidth: nudgeButton.width - 6
                                            text: nudgeButton.modelData.text
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }
                                    StyledToolTip {
                                        text: nudgeButton.modelData.text
                                    }
                                }
                            }
                        }
                        StyledText {
                            visible: (Config.options?.mesh?.quickMessages ?? []).length > 0
                            Layout.topMargin: 2
                            text: Translation.tr("Your quick messages")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: Config.options?.mesh?.quickMessages ?? []
                                delegate: RippleButton {
                                    id: quick
                                    required property string modelData
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer1
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    implicitHeight: 30
                                    implicitWidth: quickText.implicitWidth + 20
                                    onClicked: {
                                        root.send(quick.modelData);
                                        root.picking = false;
                                    }
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
                }
            }
        }

        // Answering a message: who and what, above the field (✕ or Escape
        // cancels it).
        Rectangle {
            Layout.fillWidth: true
            visible: root.replyTo !== null
            implicitHeight: replyRow.implicitHeight + 10
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            Rectangle {
                width: 3
                height: parent.height
                radius: 1.5
                color: Appearance.colors.colPrimary
            }
            RowLayout {
                id: replyRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 4
                spacing: 8
                MaterialSymbol {
                    text: "reply"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.replyTo ? Translation.tr("Replying to %1").arg(root.replyTo.from === Mesh.me ? Translation.tr("yourself") : Mesh.nameOf(root.replyTo.from)) : ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.replyTo?.text ?? ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.replyTo = null
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip {
                        text: Translation.tr("Don't reply")
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
                    implicitWidth: Math.min(lists.width, pendingRow.implicitWidth + 16)
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
                            Layout.maximumWidth: lists.width - 70
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
            // Nudges and quick messages.
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                toggled: root.picking
                onClicked: root.picking = !root.picking
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "auto_awesome"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.picking ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Nudges and quick messages")
                }
            }
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
                    } else if (event.key === Qt.Key_Escape && root.replyTo !== null) {
                        root.replyTo = null;
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
