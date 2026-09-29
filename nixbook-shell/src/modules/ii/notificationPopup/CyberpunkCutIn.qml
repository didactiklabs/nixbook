pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * The Cyberpunk 2077 theme's take on the cut-in, for the same notifications
 * (Notifications.cutInVerdict: critical ones and the cut-in rules): an
 * incoming holocall on the focused screen. A dark HUD panel with cut corners
 * glitches in from a line (RGB split in the variant's glitch colour, torn
 * slices), the sender's portrait with a scan line, the name in the accent
 * colour, the message typed out, over scanlines — to the theme's critical
 * sound (Themes.sound("critical")). Never while locked or silenced (Do Not
 * Disturb). appearance.cyberpunk.glitch: false keeps it steady.
 *
 * Click / Enter: run the notification's default action and dismiss. Right
 * click / Escape / Space: dismiss (it stays in the notification centre).
 * Reply and the app's actions as HUD buttons; several queue up.
 */
Scope {
    id: root

    property var queue: []
    readonly property var current: root.queue.length > 0 ? root.queue[0] : null
    readonly property bool enabled: Cyberpunk.enabled

    function show(n) {
        const replaces = (Config.options?.notifications?.cutIn?.mergeUpdates ?? true) ? n.replaces ?? [] : [];
        const index = root.queue.findIndex(q => replaces.includes(q.notificationId));
        if (index !== -1 && !(index === 0 && leaveAnim.running)) {
            if (index === 0) root.swapping = true;
            root.queue = root.queue.map((q, i) => i === index ? n : q);
            return;
        }
        Notifications.playCutInSound(n);
        root.queue = root.queue.concat([n]);
    }
    property bool swapping: false
    function next() {
        root.queue = root.queue.slice(1);
    }
    function dismiss() {
        call.leave(() => root.next());
    }
    function activate() {
        const n = root.current;
        if (n && n.actions.some(a => a.identifier === "default"))
            Notifications.attemptInvokeAction(n.notificationId, "default");
        root.dismiss();
    }

    Connections {
        target: Notifications
        function onNotify(n) {
            if (root.enabled && !Notifications.silent && !GlobalStates.screenLocked && Notifications.cutInVerdict(n).cutIn)
                root.show(n);
        }
        function onDiscard(id) {
            if (root.current?.notificationId === id) root.dismiss();
            else root.queue = root.queue.filter(n => n.notificationId !== id);
        }
    }
    // Settings → "Preview cut-in" shows this one in the Cyberpunk theme.
    Connections {
        target: GlobalStates
        enabled: root.enabled
        function onPersonaCutInPreviewChanged() {
            root.show({ notificationId: -1, summary: Translation.tr("Preview"), body: Translation.tr("This is how an important notification looks."),
                appName: "nixbook-shell", appIcon: "", image: UserAvatar.source, actions: [], time: Date.now() });
        }
    }

    // A chamfered outline (top left and bottom right corners cut), filled.
    component Chamfer: Shape {
        id: chamfer
        property real cut: 12
        property color fill: "transparent"
        property color stroke: "transparent"
        property real strokeWidth: 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: chamfer.fill
            strokeColor: chamfer.stroke
            strokeWidth: chamfer.strokeWidth
            joinStyle: ShapePath.MiterJoin
            startX: chamfer.cut; startY: 0
            PathLine { x: chamfer.width; y: 0 }
            PathLine { x: chamfer.width; y: chamfer.height - chamfer.cut }
            PathLine { x: chamfer.width - chamfer.cut; y: chamfer.height }
            PathLine { x: 0; y: chamfer.height }
            PathLine { x: 0; y: chamfer.cut }
            PathLine { x: chamfer.cut; y: 0 }
        }
    }

    // A HUD button: chamfered outline in the accent, filled on hover.
    component HudButton: RippleButton {
        id: hud
        property string label
        implicitHeight: 36
        implicitWidth: hudLabel.implicitWidth + 36
        buttonRadius: 0
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colRipple: ColorUtils.transparentize(Cyberpunk.accent, 0.6)
        contentItem: Item {
            Chamfer {
                anchors.fill: parent
                cut: 9
                fill: hud.hovered || hud.toggled ? Cyberpunk.accent : ColorUtils.transparentize(Cyberpunk.accent, 0.9)
                stroke: Cyberpunk.accent
                strokeWidth: 1.5
            }
            StyledText {
                id: hudLabel
                anchors.centerIn: parent
                text: hud.label.toUpperCase()
                font.family: Cyberpunk.font
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                font.letterSpacing: 1.5
                color: hud.hovered || hud.toggled ? Cyberpunk.panel : Cyberpunk.accent
            }
        }
    }

    PanelWindow {
        id: call
        visible: root.current !== null
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null
        WlrLayershell.namespace: "quickshell:cyberpunkCutIn"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        readonly property var n: root.current
        readonly property string fullBody: NotificationUtils.plainText(
            NotificationUtils.processNotificationBody(n?.body ?? "", n?.appName ?? "")).trim()
        // Phone chats mirrored by KDE Connect: the last message and its sender.
        readonly property var mirrored: (v => (n?.appName ?? "") === "KDE Connect" && v.sender !== "" && v.text !== "" ? v : null)(
            NotificationUtils.lastMessage(fullBody))
        readonly property string bodyText: (mirrored ? mirrored.text : fullBody)
            || NotificationUtils.plainText(n?.summary).trim()
        readonly property string speaker: mirrored ? mirrored.sender
            : ((n?.body ? NotificationUtils.plainText(n?.summary) : n?.appName) || n?.appName || "")
        readonly property string source: mirrored ? NotificationUtils.plainText(n?.summary ?? "") : (n?.appName ?? "")
        readonly property var replyMethod: n ? Notifications.replyMethod(n) : null
        // A chat (something to answer) is a call, anything else an alert.
        readonly property string header: replyMethod ? Translation.tr("Incoming call") : Translation.tr("Priority alert")
        // A made-up frequency per sender, for the HUD.
        readonly property string frequency: {
            let h = 7;
            for (const ch of call.speaker) h = (h * 31 + ch.charCodeAt(0)) % 99991;
            return `${(80 + h % 280) / 10 + 80}`.slice(0, 5);
        }
        property bool replying: false
        onReplyingChanged: if (replying) Qt.callLater(() => replyInput.forceActiveFocus())
        function sendReply() {
            if (Notifications.sendReply(call.n?.notificationId ?? -1, replyInput.text)) {
                replyInput.text = "";
                call.replying = false;
                root.dismiss();
            }
        }

        // 0 → 1 entrance (a line opens into the panel, flickering), reversed
        // on leave.
        property real t: 0
        property var afterLeave: null
        function leave(cb) {
            afterLeave = cb;
            enterAnim.stop();
            leaveAnim.restart();
        }
        onNChanged: {
            if (!n) return;
            typeProgress = 0;
            if (root.swapping) {
                root.swapping = false;
                typeAnim.restart();
                return;
            }
            leaveAnim.stop();
            t = 0;
            replying = false;
            replyInput.text = "";
            enterAnim.restart();
            typeAnim.restart();
            call.burst(6);
        }
        NumberAnimation on t {
            id: enterAnim
            running: false
            to: 1
            duration: 460
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            id: leaveAnim
            ScriptAction { script: call.burst(3) }
            NumberAnimation { target: call; property: "t"; to: 0; duration: 220; easing.type: Easing.InCubic }
            ScriptAction { script: { const cb = call.afterLeave; call.afterLeave = null; if (cb) cb(); } }
        }
        // Flicker while opening or closing: steps between dim and full.
        readonly property real flicker: t >= 1 ? 1 : (Math.floor(t * 14) % 3 === 1 ? 0.35 : 1)

        // The message, typed out (a 0 → 1 progress: the text is only known
        // once `n` has settled).
        property real typeProgress: 1
        readonly property int typed: Math.round(typeProgress * bodyText.length)
        readonly property bool typing: typeProgress < 1
        NumberAnimation on typeProgress {
            id: typeAnim
            running: false
            from: 0
            to: 1
            duration: Math.min(1400, 180 + call.bodyText.length * 16)
        }

        // ------------------------------------------------------------ glitch
        // A burst: a few frames of random offsets for the RGB split and the
        // torn slices, then steady; bursts come back now and then while shown.
        property real gx: 0
        property real gy: 0
        property int burstFrames: 0
        property int sliceSeed: 0
        readonly property bool glitching: Cyberpunk.glitch && burstFrames > 0
        function burst(frames) {
            if (!Cyberpunk.glitch) return;
            call.burstFrames = Math.max(call.burstFrames, frames);
            jitter.restart();
        }
        Timer {
            id: jitter
            interval: 45
            repeat: true
            onTriggered: {
                if (call.burstFrames <= 0) {
                    call.gx = 0;
                    call.gy = 0;
                    stop();
                    return;
                }
                call.burstFrames -= 1;
                call.gx = (Math.random() - 0.5) * 18;
                call.gy = (Math.random() - 0.5) * 5;
                call.sliceSeed = Math.floor(Math.random() * 1000);
            }
        }
        Timer {
            running: call.visible && Cyberpunk.glitch && call.t >= 1
            repeat: true
            interval: 1800 + Math.random() * 2200
            onTriggered: {
                interval = 1800 + Math.random() * 2200;
                call.burst(2 + Math.floor(Math.random() * 3));
            }
        }

        Item {
            id: keyTarget
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if ([Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
                    root.activate();
                    event.accepted = true;
                } else if ([Qt.Key_Escape, Qt.Key_Space].includes(event.key)) {
                    root.dismiss();
                    event.accepted = true;
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => mouse.button === Qt.RightButton ? root.dismiss() : root.activate()
            }

            // Dark scrim with scanlines.
            Rectangle {
                anchors.fill: parent
                color: Cyberpunk.panel
                opacity: 0.62 * Math.min(1, call.t * 1.5)
            }
            Canvas {
                id: scanlines
                anchors.fill: parent
                visible: Cyberpunk.glitch
                opacity: 0.22 * Math.min(1, call.t * 1.5)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "#000000";
                    for (let y = 0; y < height; y += 4)
                        ctx.fillRect(0, y, width, 2);
                }
            }

            // The holocall.
            Item {
                id: panelArea
                width: Math.min(820, call.width - 64)
                height: panel.height
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(32, call.height * 0.3 - height / 3)
                opacity: Math.min(1, call.t * 2) * call.flicker
                transform: [
                    Scale {
                        origin.x: panelArea.width / 2
                        origin.y: panelArea.height / 2
                        yScale: Math.max(0.02, Math.min(1, call.t / 0.45))
                        xScale: 0.9 + 0.1 * Math.min(1, call.t * 1.6)
                    },
                    Translate { x: call.gx * 0.4 }
                ]

                // RGB split: the frame again, offset, in the glitch and alert colours.
                Chamfer {
                    x: 6 + call.gx; y: 5 + call.gy
                    width: panel.width; height: panel.height
                    cut: Cyberpunk.chamfer
                    stroke: Cyberpunk.glitchColor
                    strokeWidth: 2
                    opacity: Cyberpunk.glitch ? 0.9 : 0
                }
                Chamfer {
                    visible: call.glitching
                    x: -4 - call.gx * 0.6; y: -call.gy
                    width: panel.width; height: panel.height
                    cut: Cyberpunk.chamfer
                    stroke: Cyberpunk.alertColor
                    strokeWidth: 2
                    opacity: 0.8
                }

                Item {
                    id: panel
                    width: parent.width
                    height: content.implicitHeight + 36
                    Chamfer {
                        anchors.fill: parent
                        cut: Cyberpunk.chamfer
                        fill: ColorUtils.transparentize(Cyberpunk.panel, 0.06)
                        stroke: Cyberpunk.accent
                        strokeWidth: 2
                    }

                    MouseArea { // the panel activates, like the rest; keeps the reply box usable
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => mouse.button === Qt.RightButton ? root.dismiss() : root.activate()
                    }

                    // Accent notch on the cut corner and a tick on the right edge.
                    Rectangle {
                        x: 0; y: Cyberpunk.chamfer + 8
                        width: 5; height: 46
                        color: Cyberpunk.accent
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: -3
                        y: 20
                        width: 6; height: 22
                        color: Cyberpunk.glitchColor
                    }

                    ColumnLayout {
                        id: content
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 30; rightMargin: 26; topMargin: 18 }
                        spacing: 14

                        // Header: the tag in the accent, the source, a barcode.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                implicitWidth: headerText.implicitWidth + 22
                                implicitHeight: headerText.implicitHeight + 4
                                color: Cyberpunk.accent
                                StyledText {
                                    id: headerText
                                    anchors.centerIn: parent
                                    text: call.header.toUpperCase()
                                    font.family: Cyberpunk.font
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Bold
                                    font.letterSpacing: 2.5
                                    color: Cyberpunk.panel
                                }
                                // Blinking "live" dot.
                                Rectangle {
                                    anchors.left: parent.right
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8; height: 8
                                    color: Cyberpunk.alertColor
                                    SequentialAnimation on opacity {
                                        running: call.visible
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.15; duration: 420 }
                                        NumberAnimation { to: 1; duration: 420 }
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.leftMargin: 14
                                text: `// ${call.source.toUpperCase()}`
                                elide: Text.ElideRight
                                font.family: Cyberpunk.font
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.5
                                color: Cyberpunk.glitchColor
                            }
                            Row {
                                spacing: 2
                                Repeater {
                                    model: 16
                                    delegate: Rectangle {
                                        required property int index
                                        width: [1, 3, 1, 2, 1, 1, 4, 1, 2, 1, 3, 1, 1, 2, 1, 3][index]
                                        height: 18
                                        color: Cyberpunk.accent
                                        opacity: 0.8
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20

                            // Portrait, in brackets, with a scan line.
                            Item {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 112
                                implicitHeight: 112
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    color: ColorUtils.transparentize(Cyberpunk.accent, 0.88)
                                    border.width: 1
                                    border.color: ColorUtils.transparentize(Cyberpunk.accent, 0.5)
                                    clip: true
                                    readonly property bool hasImage: (call.n?.image ?? "") !== ""
                                    Image {
                                        id: portrait
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        visible: parent.hasImage
                                        source: call.n?.image ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 200; sourceSize.height: 200
                                    }
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: !parent.hasImage && (call.n?.appIcon ?? "") !== ""
                                        implicitSize: 56
                                        source: visible ? Quickshell.iconPath(call.n.appIcon, "dialog-warning") : ""
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: !parent.hasImage && (call.n?.appIcon ?? "") === ""
                                        text: call.replyMethod ? "person" : "warning"
                                        iconSize: 56
                                        color: Cyberpunk.accent
                                    }
                                    // Tint and scan line.
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Cyberpunk.glitchColor
                                        opacity: 0.12
                                    }
                                    Rectangle {
                                        id: scan
                                        width: parent.width
                                        height: 2
                                        color: Cyberpunk.glitchColor
                                        opacity: 0.85
                                        NumberAnimation on y {
                                            running: call.visible
                                            loops: Animation.Infinite
                                            from: 0
                                            to: 98
                                            duration: 1600
                                        }
                                    }
                                }
                                // Corner brackets.
                                Repeater {
                                    model: 4
                                    delegate: Item {
                                        id: bracket
                                        required property int index
                                        readonly property bool atRight: index % 2 === 1
                                        readonly property bool atBottom: index > 1
                                        x: atRight ? parent.width - 16 : 0
                                        y: atBottom ? parent.height - 16 : 0
                                        width: 16; height: 16
                                        Rectangle { width: 16; height: 3; y: bracket.atBottom ? 13 : 0; color: Cyberpunk.accent }
                                        Rectangle { width: 3; height: 16; x: bracket.atRight ? 13 : 0; color: Cyberpunk.accent }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                // The name, with its RGB split while glitching.
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: nameText.implicitHeight
                                    StyledText {
                                        visible: call.glitching
                                        width: parent.width
                                        x: call.gx * 0.5; y: call.gy
                                        text: nameText.text
                                        elide: Text.ElideRight
                                        font: nameText.font
                                        color: Cyberpunk.glitchColor
                                        opacity: 0.85
                                    }
                                    StyledText {
                                        visible: call.glitching
                                        width: parent.width
                                        x: -call.gx * 0.4; y: -call.gy
                                        text: nameText.text
                                        elide: Text.ElideRight
                                        font: nameText.font
                                        color: Cyberpunk.alertColor
                                        opacity: 0.7
                                    }
                                    StyledText {
                                        id: nameText
                                        width: parent.width
                                        text: call.speaker.toUpperCase()
                                        elide: Text.ElideRight
                                        font.family: Cyberpunk.font
                                        font.pixelSize: 38
                                        font.weight: Font.Bold
                                        font.letterSpacing: 2
                                        color: Cyberpunk.accent
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: `FREQ ${call.frequency} MHZ  //  ${Qt.formatTime(new Date(call.n?.time ?? Date.now()), "hh:mm:ss")}`
                                    font.family: Cyberpunk.font
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.5
                                    color: ColorUtils.transparentize(Cyberpunk.ink, 0.45)
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    text: call.bodyText.substring(0, call.typed) + (call.typing ? "▌" : "")
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 6
                                    elide: Text.ElideRight
                                    font.family: Cyberpunk.font
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    font.weight: Font.Medium
                                    color: Cyberpunk.ink
                                }
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: replyButton.visible || actionsRepeater.count > 0
                            HudButton {
                                id: replyButton
                                visible: call.replyMethod !== null
                                label: call.replyMethod?.kind === "inline" ? Translation.tr("Reply")
                                    : Translation.tr("Reply in %1").arg(call.n?.appName || Translation.tr("the app"))
                                toggled: call.replying
                                onClicked: {
                                    if (call.replyMethod?.kind === "inline") {
                                        call.replying = !call.replying;
                                        if (!call.replying) keyTarget.forceActiveFocus();
                                    } else {
                                        Notifications.replyViaApp(call.n.notificationId);
                                        root.dismiss();
                                    }
                                }
                            }
                            Repeater {
                                id: actionsRepeater
                                model: (call.n?.actions ?? []).filter(a => a.identifier !== "default"
                                    && a.identifier !== call.replyMethod?.identifier).slice(0, 3)
                                delegate: HudButton {
                                    required property var modelData
                                    label: modelData.text
                                    onClicked: {
                                        Notifications.attemptInvokeAction(call.n.notificationId, modelData.identifier);
                                        root.dismiss();
                                    }
                                }
                            }
                        }

                        // Inline reply
                        Item {
                            visible: call.replying
                            Layout.fillWidth: true
                            implicitHeight: Math.max(44, replyInput.contentHeight + 22)
                            Chamfer {
                                anchors.fill: parent
                                cut: 10
                                fill: ColorUtils.transparentize(Cyberpunk.glitchColor, 0.92)
                                stroke: Cyberpunk.glitchColor
                                strokeWidth: 1.5
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: replyInput.forceActiveFocus()
                            }
                            StyledText {
                                id: prompt
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 18 }
                                text: ">"
                                font.family: Cyberpunk.font
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                color: Cyberpunk.glitchColor
                            }
                            TextInput {
                                id: replyInput
                                anchors { left: prompt.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 18 }
                                color: Cyberpunk.ink
                                selectionColor: ColorUtils.transparentize(Cyberpunk.glitchColor, 0.5)
                                font.family: Cyberpunk.font
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Medium
                                clip: true
                                Keys.onReturnPressed: call.sendReply()
                                Keys.onEnterPressed: call.sendReply()
                                Keys.onEscapePressed: {
                                    call.replying = false;
                                    keyTarget.forceActiveFocus();
                                }
                                StyledText {
                                    visible: replyInput.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: call.n?.inlineReplyPlaceholder || Translation.tr("Reply… (Enter sends)")
                                    font.family: Cyberpunk.font
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: ColorUtils.transparentize(Cyberpunk.ink, 0.55)
                                }
                            }
                        }

                        // Key hints.
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: Translation.tr("[ENTER] ANSWER    [ESC] DISMISS")
                            font.family: Cyberpunk.font
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                            color: ColorUtils.transparentize(Cyberpunk.accent, 0.35)
                        }
                    }
                }

                // Torn slices: bands of the panel shifted sideways while glitching.
                Repeater {
                    model: call.glitching ? 5 : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property real r: ((call.sliceSeed + 1) * (index + 3) * 7919 % 1000) / 1000
                        x: (r - 0.5) * 60
                        y: panel.height * ((r * 1.7 + index * 0.21) % 1)
                        width: panel.width * (0.25 + 0.6 * ((r * 3.1) % 1))
                        height: 2 + Math.floor(r * 9)
                        color: index % 2 === 0 ? Cyberpunk.accent : Cyberpunk.glitchColor
                        opacity: 0.55
                    }
                }
            }
        }
    }
}
