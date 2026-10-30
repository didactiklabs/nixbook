pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Claude speaking (services/Initiative.qml, `speaking`): not a notification
 * but the agent itself, on the left of the screen under the bar, a speech
 * bubble from the robot that is a small chat of its own: the user answers
 * in it (a field at the bottom, or a quick answer: Yes please, one click on
 * a reaction's Open, Summarize it…) and Claude answers there, saying what
 * it is doing meanwhile; the conversation goes to the side panel only when
 * asked (the expand button). Also how a chat of the side panel says it has
 * answered while the panel is closed (Initiative.chatDone), and what
 * Mod+C calls up to ask anything. Looks like the theme: a
 * Material card with a tail, a slanted Persona frame, a round pastel
 * Chiikawa bubble, a chamfered neon Cyberpunk panel, a paper Ghibli card.
 * Left alone (not hovered, not typed in: 25 s for a word, 15 s for a
 * reaction, 90 s after an answer) it goes to the bar's bubble, its
 * conversation with it. Hovered, typed in or closed, it was read: the bar's
 * bubble then stays dark (Initiative.markRead).
 * Its other words come as small bubbles under it (Initiative.stacked), like
 * notifications: what it says while the bubble is taken, a word put aside
 * unread, its quiet words. A click opens one in the bubble; one waiting
 * for an answer stays, the others go to the bar.
 */
Scope {
    id: root

    readonly property var item: Initiative.speaking
    readonly property var chat: Initiative.chat
    readonly property bool conversing: Initiative.conversing
    readonly property bool responding: root.chat?.responding ?? false
    readonly property string style: Persona.enabled ? "persona" : Chiikawa.enabled ? "chiikawa"
        : Cyberpunk.enabled ? "cyberpunk" : Ghibli.enabled ? "ghibli" : "material"

    readonly property color bg: root.style === "persona" ? Persona.frameColor
        : root.style === "chiikawa" ? (Chiikawa.spec.background ?? "#fff6f8")
        : root.style === "cyberpunk" ? Cyberpunk.panel
        : root.style === "ghibli" ? Ghibli.paper
        : Appearance.colors.colPrimaryContainer
    readonly property color fg: root.style === "persona" ? Appearance.colors.colOnLayer1
        : root.style === "chiikawa" ? (Chiikawa.spec.ink ?? "#4a3a3f")
        : root.style === "cyberpunk" ? Cyberpunk.ink
        : root.style === "ghibli" ? Ghibli.ink
        : Appearance.colors.colOnPrimaryContainer
    readonly property color accent: root.style === "persona" ? Persona.stripeColor
        : root.style === "chiikawa" ? (Chiikawa.spec.accent ?? "#f29bb2")
        : root.style === "cyberpunk" ? Cyberpunk.glitchColor
        : root.style === "ghibli" ? Ghibli.accent
        : Appearance.colors.colPrimary
    readonly property color edge: root.style === "chiikawa" ? (Chiikawa.spec.line ?? "#7a5560")
        : root.style === "cyberpunk" ? Cyberpunk.accent
        : root.style === "ghibli" ? Ghibli.warm
        : root.accent
    readonly property string font: root.style === "cyberpunk" ? Cyberpunk.font
        : root.style === "ghibli" ? Ghibli.titleFont : Appearance.font.family.main
    readonly property bool square: root.style === "cyberpunk" || root.style === "persona"
    readonly property real radius: root.style === "chiikawa" ? 28 : root.style === "ghibli" ? 16
        : root.style === "material" ? Appearance.rounding.large : 0

    // A message as plain text: no thinking or tool blocks, little markdown;
    // a table's rows as "a · b", its |---| line gone.
    // The last few answers (a plain object changed in place, never a
    // notifying property: bindings read it): the message line and the
    // thinking dots ask for the same text on each streamed chunk, and each
    // ran these regexes over the whole message, tool blocks and all.
    readonly property var _plainMemo: ({ keys: [], values: [] })
    function plain(text) {
        const s = String(text ?? "")
        const memo = root._plainMemo
        const at = memo.keys.indexOf(s)
        if (at >= 0) return memo.values[at]
        const out = root._plain(s)
        memo.keys.push(s)
        memo.values.push(out)
        if (memo.keys.length > 6) {
            memo.keys.shift()
            memo.values.shift()
        }
        return out
    }
    function _plain(text) {
        return String(text ?? "")
            .replace(/<think>[\s\S]*?(<\/think>|$)/g, "")
            .replace(/^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*\n?/gm, "")
            .replace(/^[ \t]*\|(.*)\|[ \t]*$/gm, (_, row) => row.split("|").map(c => c.trim()).join(" · "))
            .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
            .replace(/^#{1,6}\s+/gm, "")
            .replace(/(\*\*|__|`)/g, "")
            .replace(/\n{3,}/g, "\n\n")
            .trim()
    }
    // The conversation, the last messages (their AiMessageData). The
    // messages themselves, not copies of their text: a streamed chunk then
    // re-reads only its own line, instead of every line being rebuilt.
    readonly property var lines: {
        if (!root.conversing || !root.chat) return []
        const out = []
        for (const id of root.chat.messageIDs) {
            const m = root.chat.messageByID[id]
            if (!m || (m.role !== "user" && m.role !== "assistant") || m.visibleToUser === false) continue
            out.push(m)
        }
        return out.slice(-8)
    }
    // While it answers: what it is doing (its last tool), else thinking.
    readonly property string status: {
        if (!root.responding) return ""
        const ids = root.chat.messageIDs
        const m = ids.length > 0 ? root.chat.messageByID[ids[ids.length - 1]] : null
        const raw = m?.rawContent ?? ""
        const open = raw.lastIndexOf("<think>") > raw.lastIndexOf("</think>")
        const re = /<think>\n\*\*([^*]+)\*\*/g
        let tool = "", m2
        while ((m2 = re.exec(raw)) !== null) tool = m2[1]
        if (tool && !open) return Translation.tr("Used %1…").arg(tool)
        return open ? Translation.tr("Thinking…") : raw.trim().length > 0 ? "" : Translation.tr("Thinking…")
    }
    // What it says when nothing is said yet in the bubble.
    readonly property bool asks: /[?？]\s*$/.test(root.item?.text ?? "")
    // Quick answers under what it said: {label, main, run}.
    readonly property var chips: {
        const it = root.item
        if (!it || root.conversing) return []
        const out = []
        if (it.accept) out.push({ label: Translation.tr("Yes, do it"), main: true, run: () => Initiative.accept() })
        else if ((it.actions ?? []).length > 0)
            for (const [i, a] of it.actions.entries())
                out.push({ label: a.label, main: i === 0, run: () => Initiative.act(a) })
        else if (root.asks && !Initiative.isAsk(it) && Initiative.online) {
            out.push({ label: Translation.tr("Yes, please"), main: true, run: () => Initiative.reply(Translation.tr("Yes, please.")) })
            out.push({ label: Translation.tr("No thanks"), main: false, run: () => Initiative.hush("dismissed") })
        }
        // A watch the user asked for: seen, nothing to silence.
        if (it.id && it.kind === "watch")
            out.push({ label: Translation.tr("OK"), main: out.length === 0, run: () => Initiative.hush("later") })
        else if (it.id) {
            out.push({ label: Translation.tr("Not now"), main: false, run: () => Initiative.hush("later") })
            out.push({ label: Translation.tr("Don't tell me this"), main: false, run: () => Initiative.hush("never") })
        }
        return out
    }

    PanelWindow {
        id: window
        visible: (root.item !== null || Initiative.stacked.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:agentSpeech"
        WlrLayershell.layer: WlrLayer.Overlay
        // The keys when called up with them (Mod+C), until put
        // away (Escape, close, expand) or an agent starts acting (its keys
        // and clicks go to the apps then, the field only once clicked into);
        // else only once clicked into, never taken from the app.
        property bool grab: false
        WlrLayershell.keyboardFocus: MakeWay.active ? WlrKeyboardFocus.None
            : window.grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        // Only the card takes clicks; none while an agent works underneath.
        mask: MakeWay.active ? noInput : cardRegion
        Region {
            id: cardRegion
            item: root.item ? card : null
            Region { item: stackColumn }
        }
        Region { id: noInput }
        exclusiveZone: 0
        color: "transparent"
        anchors { top: true; left: true }
        readonly property bool barTop: !(Config.options.bar.bottom ?? false) && !(Config.options.bar.vertical ?? false)
        readonly property bool barLeft: (Config.options.bar.vertical ?? false) && !(Config.options.bar.bottom ?? false)
        margins {
            top: window.barTop ? Appearance.sizes.barHeight + 6 : 12
            left: window.barLeft ? Appearance.sizes.verticalBarWidth + 6 : 12
        }
        implicitWidth: 404
        implicitHeight: stackColumn.y + stackColumn.implicitHeight + 24
        onVisibleChanged: if (!visible) {
            window.grab = false
            input.focus = false
            input.text = ""
        }

        Connections {
            target: MakeWay
            function onActiveChanged() { if (MakeWay.active) window.grab = false }
        }
        Connections {
            target: Initiative
            function onFocusWanted() {
                window.grab = true
                focusLater.restart()
            }
        }
        Timer {
            id: focusLater
            interval: 60
            onTriggered: input.forceActiveFocus()
        }

        // An agent working underneath (services/MakeWay.qml): faded, and gone
        // from its screenshots.
        Item {
            anchors.fill: parent
            opacity: MakeWay.fade(0.85, "speechBubble")
            // Slides in from the left, a little bounce (a snap in Persona).
            Item {
                id: card
                visible: root.item !== null
                x: 12
                y: 14
                width: 376
                implicitHeight: body.implicitHeight + 28
                opacity: 0
                transform: Translate { id: slide; x: -60 }
                Connections {
                    target: root
                    function onItemChanged() {
                        if (root.item) {
                            enter.restart()
                            if (window.visible) unanswered.restart()
                        }
                    }
                    function onLinesChanged() {
                        if (unanswered.running) unanswered.restart()
                    }
                }
                Component.onCompleted: if (root.item) enter.restart()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: root.style === "persona" ? 120 : 260 }
                    NumberAnimation { target: slide; property: "x"; from: -60; to: 0; duration: root.style === "persona" ? 140 : 420
                                      easing.type: root.style === "persona" ? Easing.OutQuart : Easing.OutBack }
                }

                // The tail, pointing up to the bar's robot.
                Rectangle {
                    visible: root.style !== "persona" && root.style !== "cyberpunk"
                    x: 26
                    y: -7
                    width: 16
                    height: 16
                    rotation: 45
                    color: root.bg
                    border.color: root.edge
                    border.width: root.style === "material" ? 0 : 2
                }
                PersonaFrame {
                    visible: root.style === "persona"
                    anchors.fill: parent
                }
                Rectangle {
                    visible: root.style !== "persona"
                    anchors.fill: parent
                    radius: root.radius
                    color: root.bg
                    border.color: root.edge
                    border.width: root.style === "material" ? 0 : root.style === "cyberpunk" ? 2 : 3
                    // Covers the tail's base, so the bubble and the tail are one.
                    Rectangle {
                        visible: root.style !== "cyberpunk"
                        x: 22
                        y: root.style === "material" ? 0 : 3
                        width: 24
                        height: 8
                        color: root.bg
                    }
                }
                // Cyberpunk: a notched corner and a neon stripe.
                Item {
                    visible: root.style === "cyberpunk"
                    anchors { top: parent.top; right: parent.right }
                    width: Cyberpunk.chamfer * 0.7
                    height: width
                    clip: true
                    Rectangle {
                        width: parent.width * 1.42
                        height: width
                        x: parent.width - width / 2
                        y: -height / 2
                        rotation: 45
                        color: Cyberpunk.accent
                    }
                }
                Rectangle {
                    visible: root.style === "cyberpunk"
                    width: 4
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 6 }
                    color: root.accent
                }

                HoverHandler {
                    id: hover
                    onHoveredChanged: if (hovered) Initiative.markRead()
                }

                component HeaderButton: MaterialSymbol {
                    id: headerButton
                    signal clicked()
                    property string tip: ""
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.fg
                    opacity: headerMouse.containsMouse ? 1 : 0.6
                    MouseArea {
                        id: headerMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: headerButton.clicked()
                    }
                    StyledToolTip {
                        text: headerButton.tip
                        extraVisibleCondition: headerMouse.containsMouse
                    }
                }

                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: root.style === "cyberpunk" ? 20 : 14 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: root.square ? 0 : 13
                            color: root.accent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "smart_toy"
                                fill: 1
                                iconSize: 17
                                color: root.bg
                                // Bobs while it thinks.
                                transform: Translate { id: bob }
                                SequentialAnimation {
                                    running: root.responding
                                    loops: Animation.Infinite
                                    NumberAnimation { target: bob; property: "y"; to: -2; duration: 260; easing.type: Easing.OutSine }
                                    NumberAnimation { target: bob; property: "y"; to: 1; duration: 260; easing.type: Easing.InOutSine }
                                    NumberAnimation { target: bob; property: "y"; to: 0; duration: 200; easing.type: Easing.InSine }
                                    PauseAnimation { duration: 240 }
                                    onRunningChanged: if (!running) bob.y = 0
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: root.style === "cyberpunk" ? "DAI //" : "DAI"
                                font.family: root.font
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: root.style === "persona" ? root.accent : root.fg
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                elide: Text.ElideRight
                                // What it is doing, or the side panel's chat it speaks for.
                                text: root.status || (root.item?.kind === "done" ? (root.item?.title ?? "") : "")
                                font.family: root.font
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.fg
                                opacity: 0.7
                            }
                        }
                        HeaderButton {
                            visible: Initiative.threads.length > 0 && !(root.item?.accept)
                            text: "forum"
                            color: threadList.visible ? root.accent : root.fg
                            tip: Translation.tr("Earlier conversations")
                            onClicked: threadList.shown = !threadList.shown
                        }
                        HeaderButton {
                            visible: root.conversing
                            text: "add_comment"
                            tip: Translation.tr("New conversation (this one stays in the side panel's history)")
                            onClicked: Initiative.fresh()
                        }
                        HeaderButton {
                            visible: !(root.item?.accept)
                            text: "open_in_full"
                            tip: Translation.tr("Continue in the side panel")
                            onClicked: Initiative.expand()
                        }
                        HeaderButton {
                            text: "close"
                            tip: root.conversing ? Translation.tr("Put away (the robot's bubble brings it back)") : Translation.tr("Not now")
                            onClicked: Initiative.hush("later")
                        }
                    }

                    // Its earlier threads: one clicked comes back here.
                    ColumnLayout {
                        id: threadList
                        property bool shown: false
                        Layout.fillWidth: true
                        visible: shown && Initiative.threads.length > 0
                        spacing: 2
                        Connections {
                            target: root
                            function onItemChanged() { threadList.shown = false }
                        }
                        Repeater {
                            model: Initiative.threads
                            delegate: Rectangle {
                                id: threadRow
                                required property var modelData
                                readonly property bool current: modelData.id === (root.chat?.chatId ?? "")
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: root.square ? 0 : 8
                                color: threadRow.current ? Qt.alpha(root.accent, 0.22)
                                    : threadMouse.containsMouse ? Qt.alpha(root.accent, 0.12) : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Rectangle { // not answered yet
                                        visible: (threadRow.modelData.turns ?? 0) <= 1
                                        implicitWidth: 6
                                        implicitHeight: 6
                                        radius: 3
                                        color: root.accent
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        text: threadRow.modelData.title
                                        font.family: root.font
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.fg
                                    }
                                    StyledText {
                                        text: Qt.locale().toString(new Date(threadRow.modelData.updated ?? 0),
                                            new Date(threadRow.modelData.updated ?? 0).toDateString() === new Date().toDateString() ? "hh:mm" : "d MMM")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.fg
                                        opacity: 0.6
                                    }
                                }
                                MouseArea {
                                    id: threadMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        threadList.shown = false
                                        Initiative.openThread(threadRow.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // What it said, before any answer.
                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.conversing && !threadList.visible && text.length > 0
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText // its words may quote third-party text
                        text: root.item?.text ?? ""
                        font.family: root.font
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: root.fg
                    }

                    // The conversation: Claude's words plain, the user's in a pill
                    // on the right; follows the newest.
                    Flickable {
                        id: talk
                        Layout.fillWidth: true
                        visible: root.conversing && !threadList.visible
                        implicitHeight: Math.min(lines.implicitHeight, 300)
                        contentHeight: lines.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        onContentHeightChanged: talk.contentY = Math.max(0, talk.contentHeight - talk.height)
                        ColumnLayout {
                            id: lines
                            width: talk.width
                            spacing: 6
                            Repeater {
                                model: ScriptModel { values: root.lines }
                                delegate: Item {
                                    id: line
                                    required property var modelData
                                    readonly property bool mine: line.modelData.role === "user"
                                    Layout.fillWidth: true
                                    visible: lineText.text.length > 0
                                    implicitHeight: lineText.implicitHeight + (line.mine ? 10 : 0)
                                    Rectangle {
                                        visible: line.mine
                                        anchors.right: parent.right
                                        width: Math.min(lineText.implicitWidth + 20, parent.width * 0.85)
                                        height: parent.height
                                        radius: root.square ? 0 : 12
                                        color: Qt.alpha(root.accent, 0.22)
                                    }
                                    StyledText {
                                        id: lineText
                                        anchors.right: line.mine ? parent.right : undefined
                                        anchors.rightMargin: line.mine ? 10 : 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, line.mine ? parent.width * 0.85 - 20 : parent.width)
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: root.plain(line.modelData.rawContent || line.modelData.content)
                                        font.family: root.font
                                        font.pixelSize: line.mine ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                                        color: root.fg
                                    }
                                }
                            }
                            // Thinking: three dots.
                            Row {
                                visible: root.responding && root.plain((m => m?.rawContent || m?.content)(root.lines[root.lines.length - 1])).length === 0
                                spacing: 4
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        id: dot
                                        required property int index
                                        width: 6
                                        height: 6
                                        radius: root.square ? 0 : 3
                                        color: root.fg
                                        SequentialAnimation on opacity {
                                            running: root.responding
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: dot.index * 160 }
                                            NumberAnimation { from: 0.25; to: 1; duration: 320 }
                                            NumberAnimation { from: 1; to: 0.25; duration: 320 }
                                            PauseAnimation { duration: (2 - dot.index) * 160 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // What a question asked here takes along (RecentContext):
                    // said, its text on hover, and × leaves it out.
                    RowLayout {
                        id: context
                        Layout.fillWidth: true
                        visible: Initiative.isAsk(root.item) && !root.conversing && RecentContext.enabled
                            && RecentContext.text.length > 0
                        spacing: 6
                        opacity: Initiative.skipContext ? 0.5 : 0.8
                        MaterialSymbol {
                            text: Initiative.skipContext ? "visibility_off" : "history"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.accent
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Initiative.skipContext ? Translation.tr("Not sending what you were just doing")
                                : Translation.tr("Knows what you were just doing")
                            font.family: root.font
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.strikeout: Initiative.skipContext
                            color: root.fg
                            HoverHandler { id: contextHover }
                            StyledToolTip {
                                text: RecentContext.text
                                extraVisibleCondition: contextHover.hovered
                            }
                        }
                        MaterialSymbol {
                            text: Initiative.skipContext ? "undo" : "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.fg
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Initiative.skipContext = !Initiative.skipContext
                            }
                        }
                    }

                    // Quick answers. Wraps when the labels don't fit on one line.
                    Flow {
                        Layout.fillWidth: true
                        visible: root.chips.length > 0
                        spacing: 6
                        Repeater {
                            model: root.chips
                            delegate: Rectangle {
                                id: button
                                required property var modelData
                                implicitWidth: label.implicitWidth + 22
                                implicitHeight: 28
                                radius: root.square ? 0 : 14
                                color: button.modelData.main ? (mouse.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent)
                                    : (mouse.containsMouse ? Qt.alpha(root.accent, 0.18) : "transparent")
                                border.color: root.accent
                                border.width: button.modelData.main ? 0 : 1
                                StyledText {
                                    id: label
                                    anchors.centerIn: parent
                                    text: button.modelData.label
                                    font.family: root.font
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: button.modelData.main ? Font.Bold : Font.Normal
                                    color: button.modelData.main ? root.bg : root.fg
                                }
                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: button.modelData.run()
                                }
                            }
                        }
                    }

                    // The image or file to go with the answer, on the bubble's
                    // chat: still there when the talk is expanded to the panel.
                    AttachedFileIndicator {
                        Layout.fillWidth: true
                        highlight: false
                        maxHeight: 72
                        color: Qt.alpha(root.fg, 0.06)
                        filePath: root.chat?.pendingFilePath ?? ""
                        onRemove: root.chat?.attachFile("")
                    }

                    ChatAttacher {
                        id: attacher
                        visible: false // no space in the layout
                        onAttached: path => {
                            Initiative.prepare()
                            root.chat?.attachFile(path)
                            input.forceActiveFocus()
                        }
                    }

                    // The answer, typed: Enter sends (Shift+Enter: a new line),
                    // Escape puts it away. Not for a routine to say yes to.
                    // Ctrl+V of an image, a file dropped or the clip button
                    // attaches it (ChatAttacher, as in the side panel).
                    Rectangle {
                        Layout.fillWidth: true
                        visible: !(root.item?.accept) && Initiative.online
                        implicitHeight: Math.max(34, Math.min(input.implicitHeight, 96))
                        radius: root.square ? 0 : 17
                        color: Qt.alpha(root.fg, input.activeFocus || drop.containsDrag ? 0.10 : 0.06)
                        border.color: input.activeFocus || drop.containsDrag ? root.accent : "transparent"
                        border.width: 1
                        DropArea {
                            id: drop
                            anchors.fill: parent
                            keys: ["text/uri-list"]
                            onDropped: event => {
                                if (attacher.dropped(event)) event.acceptProposedAction()
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: 2
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: "attach_file"
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.fg
                                opacity: attachMouse.containsMouse ? 1 : 0.6
                                MouseArea {
                                    id: attachMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: attacher.pick()
                                }
                                StyledToolTip {
                                    text: Translation.tr("Attach an image")
                                    extraVisibleCondition: attachMouse.containsMouse
                                }
                            }
                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                StyledTextArea {
                                    id: input
                                    wrapMode: TextArea.Wrap
                                    padding: 8
                                    background: null
                                    color: root.fg
                                    placeholderTextColor: Qt.alpha(root.fg, 0.5)
                                    font.family: root.font
                                    placeholderText: window.grab ? Translation.tr("Message DAI… (Esc: put away, /new: start over)")
                                        : root.conversing || Initiative.isAsk(root.item) ? Translation.tr("Message DAI…")
                                        : Translation.tr("Answer DAI…")
                                    onActiveFocusChanged: {
                                        Initiative.typing = activeFocus || text.length > 0
                                        if (activeFocus) {
                                            Initiative.markRead()
                                            Initiative.prepare()
                                        }
                                    }
                                    onTextChanged: Initiative.typing = activeFocus || text.length > 0
                                    Keys.onPressed: event => {
                                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                            event.accepted = true
                                            root.send()
                                        } else if (event.key === Qt.Key_V && event.modifiers === Qt.ControlModifier && attacher.paste(input)) {
                                            event.accepted = true
                                        } else if (event.key === Qt.Key_Escape) {
                                            event.accepted = true
                                            window.grab = false
                                            input.focus = false
                                            Initiative.markRead()
                                            Initiative.hush("wait")
                                        }
                                    }
                                }
                            }
                            MaterialSymbol {
                                readonly property bool stop: root.responding && input.text.trim().length === 0
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 6
                                text: stop ? "stop_circle" : "send"
                                fill: 1
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.accent
                                opacity: stop || input.text.trim().length > 0 ? 1 : 0.4
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.stop ? root.chat?.stopResponse() : root.send()
                                }
                            }
                        }
                    }
                }

                // Left alone: to the bar's bubble, a conversation with it (the
                // timer waits while hovered, typed in, answering, and while hidden).
                Timer {
                    id: unanswered
                    // What it just did for a command: a glance, then gone.
                    interval: root.conversing ? 90000 : root.item?.kind === "quick" ? 5000 : root.item?.kind === "react" ? 15000 : 25000
                    running: root.item !== null && window.visible && !hover.hovered && !root.responding
                        && !(Initiative.typing && (root.item?.kind !== "quick" || input.text.length > 0))
                    && !MakeWay.active
                    onTriggered: Initiative.hush("wait")
                }
            }

            // Its other words (Initiative.stacked), small, under the bubble:
            // like notifications. A click opens one in the bubble (the
            // conversation there is put away to the bar); one waiting for an
            // answer stays, the others go to the bar once read or after 10
            // minutes.
            Column {
                id: stackColumn
                x: 12
                y: root.item ? card.y + card.implicitHeight + 10 : 14
                width: 376
                spacing: 8
                Repeater {
                    model: ScriptModel { values: Initiative.stacked; objectProp: "id" }
                    delegate: Item {
                        id: small
                        required property var modelData
                        readonly property bool waits: Initiative.waits(small.modelData)
                        readonly property var chips: {
                            const it = small.modelData
                            if (it.accept) return [{ label: Translation.tr("Yes, do it"), run: () => Initiative.accept(it) }]
                            const acts = (it.actions ?? []).slice(0, 2).map(a => ({ label: a.label, run: () => Initiative.act(a, it) }))
                            if (acts.length > 0) return acts
                            return small.waits && Initiative.online ? [{ label: Translation.tr("Reply"), run: () => { Initiative.open(it); Initiative.focusWanted() } }] : []
                        }
                        width: stackColumn.width
                        implicitHeight: smallBody.implicitHeight + 20
                        opacity: 0
                        transform: Translate { id: smallSlide; x: -40 }
                        Component.onCompleted: smallEnter.start()
                        ParallelAnimation {
                            id: smallEnter
                            NumberAnimation { target: small; property: "opacity"; to: 1; duration: 220 }
                            NumberAnimation { target: smallSlide; property: "x"; to: 0; duration: root.style === "persona" ? 140 : 320
                                              easing.type: root.style === "persona" ? Easing.OutQuart : Easing.OutCubic }
                        }
                        // Not waiting for an answer: to the bar a minute after
                        // it was read, else after 10 minutes.
                        Timer {
                            interval: Initiative._read[small.modelData.id] ? 60000 : 600000
                            running: !small.waits && !smallHover.hovered && !MakeWay.active
                            onTriggered: Initiative.unstack(small.modelData)
                        }
                        HoverHandler {
                            id: smallHover
                            onHoveredChanged: if (hovered) Initiative.markRead(small.modelData)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: root.square ? 0 : Math.min(root.radius, 16)
                            color: root.bg
                            border.color: root.edge
                            border.width: root.style === "material" ? 0 : 2
                        }
                        Rectangle {
                            visible: root.style === "cyberpunk" || root.style === "persona"
                            width: 3
                            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 5 }
                            color: root.accent
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Initiative.open(small.modelData)
                        }
                        ColumnLayout {
                            id: smallBody
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 14 }
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                MaterialSymbol {
                                    text: small.waits ? "chat_bubble" : "smart_toy"
                                    fill: 1
                                    iconSize: 15
                                    color: root.accent
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText // its words may quote third-party text
                                    text: small.modelData.text ?? ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    font.family: root.font
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: root.fg
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: root.fg
                                    opacity: smallClose.containsMouse ? 1 : 0.6
                                    MouseArea {
                                        id: smallClose
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Initiative.dismissStacked(small.modelData, "later")
                                    }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.leftMargin: 23
                                visible: small.chips.length > 0
                                spacing: 6
                                Repeater {
                                    model: small.chips
                                    delegate: Rectangle {
                                        id: smallChip
                                        required property var modelData
                                        required property int index
                                        implicitWidth: smallLabel.implicitWidth + 18
                                        implicitHeight: 24
                                        radius: root.square ? 0 : 12
                                        color: smallChip.index === 0 ? (smallChipMouse.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent)
                                            : (smallChipMouse.containsMouse ? Qt.alpha(root.accent, 0.18) : "transparent")
                                        border.color: root.accent
                                        border.width: smallChip.index === 0 ? 0 : 1
                                        StyledText {
                                            id: smallLabel
                                            anchors.centerIn: parent
                                            text: smallChip.modelData.label
                                            font.family: root.font
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: smallChip.index === 0 ? Font.Bold : Font.Normal
                                            color: smallChip.index === 0 ? root.bg : root.fg
                                        }
                                        MouseArea {
                                            id: smallChipMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: smallChip.modelData.run()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function send() {
        const text = input.text.trim()
        if (text.length === 0) return
        input.text = ""
        // A new conversation, typed.
        if (/^\/(new|clear)$/i.test(text)) Initiative.fresh()
        else Initiative.reply(text, root.chat?.pendingFilePath ?? "")
    }
}
