pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * The Studio Ghibli theme's take on the cut-in, for the same notifications
 * (Notifications.cutInVerdict: critical ones and the cut-in rules): a gust of
 * wind across the focused screen carries the variant's things (leaves, paper
 * birds, fireflies) and a frosted-glass card that settles in the lower
 * third over two blurred glows of the palette, the variant's spirit leaning
 * on its corner; the app and the time as chips, the sender in the storybook
 * title face, the message beneath. To the theme's
 * critical sound (Themes.sound("critical")). Never while locked or silenced
 * (Do Not Disturb). appearance.ghibli.spirits: false leaves the spirit and
 * the drifting things out.
 *
 * Click / Enter: run the notification's default action and dismiss. Right
 * click / Escape / Space: dismiss (it stays in the notification centre).
 * Reply and the app's actions as soft round buttons; several queue up.
 */
Scope {
    id: root

    property var queue: []
    readonly property var current: root.queue.length > 0 ? root.queue[0] : null
    readonly property bool enabled: Ghibli.enabled

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
        card.leave(() => root.next());
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
    // Settings → "Preview cut-in" shows this one in the Ghibli theme.
    Connections {
        target: GlobalStates
        enabled: root.enabled
        function onPersonaCutInPreviewChanged() {
            root.show({ notificationId: -1, summary: Translation.tr("Preview"), body: Translation.tr("This is how an important notification looks."),
                appName: "nixbook-shell", appIcon: "", image: UserAvatar.source, actions: [], time: Date.now() });
        }
    }

    // A soft pill button: the accent's wash, filled on hover.
    component SoftButton: RippleButton {
        id: soft
        property string label
        implicitHeight: 38
        implicitWidth: softLabel.implicitWidth + 34
        buttonRadius: height / 2
        colBackground: soft.toggled ? Ghibli.accent : ColorUtils.transparentize(Ghibli.accent, 0.85)
        colBackgroundHover: soft.toggled ? Ghibli.accent : ColorUtils.transparentize(Ghibli.accent, 0.7)
        colRipple: ColorUtils.transparentize(Ghibli.accent, 0.5)
        contentItem: StyledText {
            id: softLabel
            horizontalAlignment: Text.AlignHCenter
            text: soft.label
            font.family: Ghibli.titleFont
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: soft.toggled ? Appearance.m3colors.m3onPrimary : Ghibli.ink
        }
    }

    PanelWindow {
        id: card
        visible: root.current !== null
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null
        WlrLayershell.namespace: "quickshell:ghibliCutIn"
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
        property bool replying: false
        onReplyingChanged: if (replying) Qt.callLater(() => replyInput.forceActiveFocus())
        function sendReply() {
            if (Notifications.sendReply(card.n?.notificationId ?? -1, replyInput.text)) {
                replyInput.text = "";
                card.replying = false;
                root.dismiss();
            }
        }

        // 0 → 1: the card drifts in from the left on the gust and settles
        // with a soft sway; reversed (drifting on to the right) on leave.
        property real t: 0
        property bool leaving: false
        property var afterLeave: null
        function leave(cb) {
            afterLeave = cb;
            enterAnim.stop();
            leaveAnim.restart();
        }
        onNChanged: {
            if (!n) return;
            if (root.swapping) {
                root.swapping = false;
                return;
            }
            leaveAnim.stop();
            leaving = false;
            t = 0;
            replying = false;
            replyInput.text = "";
            enterAnim.restart();
            gust.restart();
        }
        NumberAnimation on t {
            id: enterAnim
            running: false
            to: 1
            duration: 1100
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.16, 0.9, 0.3, 1.06, 1, 1]
        }
        SequentialAnimation {
            id: leaveAnim
            ScriptAction { script: card.leaving = true }
            NumberAnimation { target: card; property: "t"; to: 0; duration: 520; easing.type: Easing.InSine }
            ScriptAction { script: { card.leaving = false; const cb = card.afterLeave; card.afterLeave = null; if (cb) cb(); } }
        }
        // Drift: from the left on the way in, on to the right on the way out.
        readonly property real drift: (1 - t) * (leaving ? 1 : -1)

        // The gust: 0 → 1 across the screen, once per card.
        property real g: 0
        NumberAnimation on g {
            id: gust
            running: false
            from: 0
            to: 1
            duration: 2600
            easing.type: Easing.OutSine
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

            // A soft wash over the screen, darker toward the bottom (the
            // card sits there), like the edge of a painting.
            Rectangle {
                anchors.fill: parent
                opacity: Math.min(1, card.t * 1.4) * (Ghibli.night ? 0.7 : 0.55)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.55; color: ColorUtils.transparentize(Ghibli.night ? "#000000" : Ghibli.ink, Ghibli.night ? 0.6 : 0.82) }
                    GradientStop { position: 1.0; color: ColorUtils.transparentize(Ghibli.night ? "#000000" : Ghibli.ink, Ghibli.night ? 0.2 : 0.55) }
                }
            }

            // What the gust carries across: leaves (Totoro), paper birds
            // (Spirited Away), fireflies (Mononoke). Each on its own path,
            // bobbing; they fly through once with the gust, then a few stay
            // floating while the card is up.
            Repeater {
                model: Ghibli.spirits ? 22 : 0
                delegate: Item {
                    id: mote
                    required property int index
                    readonly property real r1: ((index * 7919 + 13) % 997) / 997
                    readonly property real r2: ((index * 4271 + 71) % 991) / 991
                    readonly property real r3: ((index * 2909 + 5) % 983) / 983
                    readonly property bool stays: index % 4 === 0
                    // Where along the gust it is (staggered), then where it rests.
                    readonly property real p: Math.max(0, Math.min(1, card.g * 1.6 - r1 * 0.6))
                    readonly property real restX: card.width * (0.1 + 0.8 * r2)
                    readonly property real restY: card.height * (0.15 + 0.6 * r3)
                    readonly property real flyX: -80 + (card.width + 160) * p
                    readonly property real flyY: card.height * (0.2 + 0.7 * r3) - Math.sin(p * Math.PI) * card.height * 0.18 * (0.5 + r2)
                    x: stays ? flyX + (restX - flyX) * Math.max(0, (card.g - 0.6) / 0.4) : flyX
                    y: (stays ? flyY + (restY - flyY) * Math.max(0, (card.g - 0.6) / 0.4) : flyY) + bob
                    visible: stays || (p > 0 && p < 1)
                    opacity: Math.min(1, card.t * 2) * (stays ? 0.9 : 0.8)
                    width: Ghibli.variant === "mononoke" ? 8 + 6 * r2 : 18 + 10 * r2
                    height: width
                    property real bob: 0
                    SequentialAnimation on bob {
                        running: card.visible && mote.stays
                        loops: Animation.Infinite
                        NumberAnimation { to: -10 - mote.r1 * 10; duration: 1600 + mote.r2 * 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 1600 + mote.r2 * 900; easing.type: Easing.InOutSine }
                    }
                    rotation: Ghibli.variant === "mononoke" ? 0 : (p * 540 * (r1 - 0.5)) + bob * 3

                    // Leaf: a pointed oval.
                    Rectangle {
                        visible: Ghibli.variant === "totoro"
                        anchors.centerIn: parent
                        width: parent.width * 0.55
                        height: parent.height
                        radius: width / 2
                        color: mote.index % 3 === 0 ? (Ghibli.spec.stripe ?? Ghibli.drift) : Ghibli.drift
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 1.2; height: parent.height * 0.8
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"
                            opacity: 0.5
                        }
                    }
                    // Paper bird: a paper doll, head and spread arms.
                    Item {
                        visible: Ghibli.variant === "spirited"
                        anchors.fill: parent
                        Rectangle { x: parent.width * 0.38; y: 0; width: parent.width * 0.24; height: width; radius: width / 2; color: Ghibli.drift }
                        Rectangle { x: 0; y: parent.height * 0.28; width: parent.width; height: parent.height * 0.16; radius: 2; color: Ghibli.drift }
                        Rectangle { x: parent.width * 0.32; y: parent.height * 0.22; width: parent.width * 0.36; height: parent.height * 0.78; radius: 2; color: Ghibli.drift }
                    }
                    // Firefly: a glowing dot.
                    Rectangle {
                        visible: Ghibli.variant === "mononoke"
                        anchors.centerIn: parent
                        width: parent.width * 2.6; height: width; radius: width / 2
                        color: Ghibli.drift
                        opacity: 0.25
                    }
                    Rectangle {
                        visible: Ghibli.variant === "mononoke"
                        anchors.fill: parent
                        radius: width / 2
                        color: Ghibli.drift
                        SequentialAnimation on opacity {
                            running: card.visible && Ghibli.variant === "mononoke"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900 + mote.r1 * 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 900 + mote.r1 * 700; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            // The card.
            Item {
                id: cardArea
                width: Math.min(760, card.width - 64)
                height: paper.height
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: card.drift * card.width * 0.6
                y: card.height * 0.62 - height / 2 + (1 - card.t) * 40
                opacity: Math.min(1, card.t * 1.8)
                rotation: card.drift * 8

                // Two glows of the palette behind the glass (the accent, and the
                // lantern / sun glow), blurred: the card's colour comes from them.
                Repeater {
                    model: [
                        { col: Ghibli.accent, x: -0.08, y: -0.35, w: 0.55, h: 1.5 },
                        { col: Ghibli.night ? Ghibli.glow : Ghibli.warm, x: 0.55, y: 0.1, w: 0.5, h: 1.4 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        x: paper.width * modelData.x
                        y: paper.height * modelData.y
                        width: paper.width * modelData.w
                        height: paper.height * modelData.h
                        radius: Math.min(width, height) / 2
                        color: modelData.col
                        opacity: Ghibli.night ? 0.55 : 0.45
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 64
                        }
                    }
                }
                // Soft, wide shadow.
                Rectangle {
                    x: 0; y: 18
                    width: paper.width; height: paper.height
                    radius: paper.radius
                    color: ColorUtils.transparentize("#000000", Ghibli.night ? 0.45 : 0.75)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 48
                    }
                }

                Rectangle {
                    id: paper
                    width: parent.width
                    height: content.implicitHeight + 48
                    radius: Appearance.rounding.verylarge
                    // Frosted glass: the paper colour, see-through.
                    color: ColorUtils.transparentize(Ghibli.paper, Ghibli.night ? 0.2 : 0.16)
                    border.width: 1
                    border.color: ColorUtils.transparentize("#ffffff", Ghibli.night ? 0.82 : 0.35)
                    clip: true

                    // The glass's sheen, brightest along the top edge.
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ColorUtils.transparentize("#ffffff", Ghibli.night ? 0.9 : 0.55) }
                            GradientStop { position: 0.45; color: "transparent" }
                        }
                    }

                    MouseArea { // the card activates, like the rest; keeps the reply box usable
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => mouse.button === Qt.RightButton ? root.dismiss() : root.activate()
                    }

                    ColumnLayout {
                        id: content
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 30; rightMargin: 30; topMargin: 22 }
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 18

                            // Portrait in a round frame.
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 84
                                implicitHeight: 84
                                radius: width / 2
                                color: ColorUtils.transparentize(Ghibli.accent, 0.82)
                                border.width: 2
                                border.color: ColorUtils.transparentize(Ghibli.accent, 0.2)
                                readonly property bool hasImage: (card.n?.image ?? "") !== ""
                                ClippingRectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: width / 2
                                    color: "transparent"
                                    visible: parent.hasImage
                                    Image {
                                        anchors.fill: parent
                                        source: card.n?.image ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 160; sourceSize.height: 160
                                    }
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !parent.hasImage && (card.n?.appIcon ?? "") !== ""
                                    implicitSize: 44
                                    source: visible ? Quickshell.iconPath(card.n.appIcon, "dialog-warning") : ""
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !parent.hasImage && (card.n?.appIcon ?? "") === ""
                                    text: card.replyMethod ? "person" : "eco"
                                    iconSize: 42
                                    color: Ghibli.accent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 4

                                // The app and the time, as chips.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        visible: card.source !== "" && card.source !== card.speaker
                                        Layout.maximumWidth: 320
                                        implicitWidth: sourceText.implicitWidth + 22
                                        implicitHeight: sourceText.implicitHeight + 8
                                        radius: height / 2
                                        color: ColorUtils.transparentize(Ghibli.accent, 0.82)
                                        StyledText {
                                            id: sourceText
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, parent.Layout.maximumWidth - 22)
                                            text: card.source
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: Ghibli.ink
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        implicitWidth: timeText.implicitWidth + 22
                                        implicitHeight: timeText.implicitHeight + 8
                                        radius: height / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: ColorUtils.transparentize(Ghibli.ink, 0.75)
                                        StyledText {
                                            id: timeText
                                            anchors.centerIn: parent
                                            text: Qt.formatTime(new Date(card.n?.time ?? Date.now()), "hh:mm")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.features: { "tnum": 1 }
                                            color: ColorUtils.transparentize(Ghibli.ink, 0.25)
                                        }
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.speaker
                                    elide: Text.ElideRight
                                    font.family: Ghibli.titleFont
                                    font.pixelSize: 30
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: -0.2
                                    color: Ghibli.ink
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    text: card.bodyText
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 6
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: Ghibli.ink
                                    lineHeight: 1.15
                                }
                            }

                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: replyButton.visible || actionsRepeater.count > 0
                            SoftButton {
                                id: replyButton
                                visible: card.replyMethod !== null
                                label: card.replyMethod?.kind === "inline" ? Translation.tr("Reply")
                                    : Translation.tr("Reply in %1").arg(card.n?.appName || Translation.tr("the app"))
                                toggled: card.replying
                                onClicked: {
                                    if (card.replyMethod?.kind === "inline") {
                                        card.replying = !card.replying;
                                        if (!card.replying) keyTarget.forceActiveFocus();
                                    } else {
                                        Notifications.replyViaApp(card.n.notificationId);
                                        root.dismiss();
                                    }
                                }
                            }
                            Repeater {
                                id: actionsRepeater
                                model: (card.n?.actions ?? []).filter(a => a.identifier !== "default"
                                    && a.identifier !== card.replyMethod?.identifier).slice(0, 3)
                                delegate: SoftButton {
                                    required property var modelData
                                    label: modelData.text
                                    onClicked: {
                                        Notifications.attemptInvokeAction(card.n.notificationId, modelData.identifier);
                                        root.dismiss();
                                    }
                                }
                            }
                        }

                        // Inline reply
                        Rectangle {
                            visible: card.replying
                            Layout.fillWidth: true
                            implicitHeight: Math.max(44, replyInput.contentHeight + 22)
                            radius: height / 2
                            color: ColorUtils.transparentize(Ghibli.accent, 0.9)
                            border.width: 1.5
                            border.color: Ghibli.accent
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: replyInput.forceActiveFocus()
                            }
                            TextInput {
                                id: replyInput
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 20 }
                                color: Ghibli.ink
                                selectionColor: ColorUtils.transparentize(Ghibli.accent, 0.5)
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.larger
                                clip: true
                                Keys.onReturnPressed: card.sendReply()
                                Keys.onEnterPressed: card.sendReply()
                                Keys.onEscapePressed: {
                                    card.replying = false;
                                    keyTarget.forceActiveFocus();
                                }
                                StyledText {
                                    visible: replyInput.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.n?.inlineReplyPlaceholder || Translation.tr("Reply… (Enter sends)")
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: ColorUtils.transparentize(Ghibli.ink, 0.55)
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: Translation.tr("Enter: open · Esc: let it drift away")
                            font.family: Ghibli.titleFont
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: ColorUtils.transparentize(Ghibli.ink, 0.45)
                        }
                    }
                }

                // The spirit, leaning on the card's top corner.
                GhibliSpirit {
                    width: 132
                    height: 132
                    anchors.right: paper.right
                    anchors.rightMargin: 64
                    anchors.bottom: paper.top
                    anchors.bottomMargin: -22
                    wobbleOnHover: true
                }
            }
        }
    }
}
