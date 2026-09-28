pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * The Chiikawa theme's take on the cut-in, for the same notifications
 * (Notifications.cutInVerdict: critical ones and the cut-in rules): the
 * current variant's character hops up from the bottom of the focused screen
 * holding a big round speech bubble with the message, among little stars
 * and hearts, to the theme's critical jingle (Themes.sound("critical")).
 * Never while locked or silenced (Do Not Disturb).
 *
 * Click: run the notification's default action and dismiss. Right click /
 * Escape / Enter / Space: dismiss (it stays in the notification centre).
 * Reply and the app's actions as round buttons; several queue up.
 */
Scope {
    id: root

    property var queue: []
    readonly property var current: root.queue.length > 0 ? root.queue[0] : null
    readonly property bool enabled: Chiikawa.enabled

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
        alert.leave(() => root.next());
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
    // Settings → "Preview cut-in" shows this one in the Chiikawa theme.
    Connections {
        target: GlobalStates
        enabled: root.enabled
        function onPersonaCutInPreviewChanged() {
            root.show({ notificationId: -1, summary: Translation.tr("Preview"), body: Translation.tr("This is how an important notification looks."),
                appName: "nixbook-shell", appIcon: "", image: UserAvatar.source, actions: [], time: Date.now() });
        }
    }

    // A round pill button in the bubble (actions, Reply).
    component PillButton: RippleButton {
        id: pill
        property string label
        implicitHeight: 36
        implicitWidth: pillLabel.implicitWidth + 32
        buttonRadius: height / 2
        colBackground: pill.toggled ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
        colBackgroundHover: Appearance.colors.colPrimary
        contentItem: StyledText {
            id: pillLabel
            anchors.centerIn: parent
            text: pill.label
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Bold
            color: pill.hovered || pill.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
        }
    }

    PanelWindow {
        id: alert
        visible: root.current !== null
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null
        WlrLayershell.namespace: "quickshell:chiikawaAlert"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        readonly property var n: root.current
        readonly property var spec: Chiikawa.spec
        readonly property string fullBody: NotificationUtils.plainText(
            NotificationUtils.processNotificationBody(n?.body ?? "", n?.appName ?? "")).trim()
        // Phone chats mirrored by KDE Connect: the last message and its sender.
        readonly property var mirrored: (v => (n?.appName ?? "") === "KDE Connect" && v.sender !== "" && v.text !== "" ? v : null)(
            NotificationUtils.lastMessage(fullBody))
        readonly property string bodyText: (mirrored ? mirrored.text : fullBody)
            || NotificationUtils.plainText(n?.summary).trim()
        readonly property string speaker: mirrored ? mirrored.sender
            : ((n?.body ? NotificationUtils.plainText(n?.summary) : n?.appName) || n?.appName || "")
        readonly property var replyMethod: n ? Notifications.replyMethod(n) : null
        property bool replying: false
        onReplyingChanged: if (replying) Qt.callLater(() => replyInput.forceActiveFocus())
        function sendReply() {
            if (Notifications.sendReply(alert.n?.notificationId ?? -1, replyInput.text)) {
                replyInput.text = "";
                alert.replying = false;
                root.dismiss();
            }
        }

        // 0 → 1 entrance (the character hops up, the bubble pops), reversed on leave.
        property real t: 0
        property var afterLeave: null
        function leave(cb) {
            afterLeave = cb;
            leaveAnim.restart();
        }
        onNChanged: {
            if (!n) return;
            if (root.swapping) {
                root.swapping = false;
                return;
            }
            leaveAnim.stop();
            t = 0;
            replying = false;
            replyInput.text = "";
            enterAnim.restart();
            mascot.hop();
        }
        NumberAnimation on t {
            id: enterAnim
            running: false
            to: 1
            duration: 560
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
        SequentialAnimation {
            id: leaveAnim
            NumberAnimation { target: alert; property: "t"; to: 0; duration: 220; easing.type: Easing.InBack }
            ScriptAction { script: { const cb = alert.afterLeave; alert.afterLeave = null; if (cb) cb(); } }
        }

        Item {
            id: keyTarget
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if ([Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) {
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

            // Soft pastel veil (the theme's background), not a dark scrim.
            Rectangle {
                anchors.fill: parent
                color: alert.spec.background ?? "#ffffff"
                opacity: 0.55 * Math.min(1, alert.t * 1.6)
            }

            // Stars and hearts drifting up around the bubble.
            Repeater {
                model: 14
                delegate: MaterialSymbol {
                    required property int index
                    readonly property real seed: (index * 7919) % 97 / 97
                    text: index % 3 === 0 ? "favorite" : "star"
                    fill: 1
                    iconSize: 18 + seed * 22
                    color: index % 2 === 0 ? (alert.spec.accent ?? Appearance.colors.colPrimary) : (alert.spec.blush ?? Appearance.colors.colTertiary)
                    x: alert.width * (0.2 + 0.6 * ((index * 0.137 + seed) % 1))
                    y: alert.height * (0.25 + 0.55 * seed) - alert.t * 40 * (1 + seed)
                    opacity: Math.min(1, alert.t) * (0.5 + seed * 0.5)
                    rotation: (seed - 0.5) * 60
                }
            }

            // The character, hopping up from the bottom edge.
            ChiikawaMascot {
                id: mascot
                visible: true
                hopOnHover: false
                // Only while showing: the window outlives the alerts.
                idle: alert.visible
                width: Math.min(260, alert.height * 0.3)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                y: alert.height - height * (0.92 * alert.t) + 8
            }

            // The speech bubble, just above the character.
            Item {
                id: bubbleArea
                width: Math.min(640, alert.width - 64)
                height: bubble.height + 22
                anchors.horizontalCenter: parent.horizontalCenter
                y: mascot.y - height + 18
                scale: 0.6 + 0.4 * alert.t
                opacity: Math.min(1, alert.t * 1.4)
                transformOrigin: Item.Bottom

                // Soft offset shadow, then the bubble with its tail.
                Rectangle {
                    x: bubble.x + 6; y: bubble.y + 8
                    width: bubble.width; height: bubble.height
                    radius: bubble.radius
                    color: alert.spec.shadow ?? "#e0c0c8"
                    opacity: 0.7
                }
                Rectangle {
                    // tail: a rotated square under the bubble
                    width: 30; height: 30
                    rotation: 45
                    x: parent.width / 2 - 15
                    y: bubble.height - 17
                    color: bubble.color
                    border.width: 4
                    border.color: bubble.border.color
                }
                Rectangle {
                    id: bubble
                    width: parent.width
                    height: content.implicitHeight + 40
                    radius: 30
                    color: alert.spec.body === "#ffffff" || !alert.spec.body ? "#ffffff" : Qt.lighter(alert.spec.body, 1.25)
                    border.width: 4
                    border.color: alert.spec.line ?? Appearance.colors.colOnLayer0

                    MouseArea { // the bubble activates, like the rest; keeps the reply box usable
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => mouse.button === Qt.RightButton ? root.dismiss() : root.activate()
                    }

                    ColumnLayout {
                        id: content
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                        spacing: 12

                        RowLayout {
                            spacing: 12
                            Layout.fillWidth: true
                            ClippingRectangle {
                                readonly property bool hasImage: (alert.n?.image ?? "") !== ""
                                visible: hasImage
                                implicitWidth: 52; implicitHeight: 52
                                radius: 26
                                color: Appearance.colors.colPrimaryContainer
                                Image {
                                    anchors.fill: parent
                                    source: alert.n?.image ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 104; sourceSize.height: 104
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: alert.speaker
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    font.weight: Font.Black
                                    color: alert.spec.ink ?? Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== "" && text !== alert.speaker
                                    text: alert.mirrored ? NotificationUtils.plainText(alert.n?.summary ?? "") : (alert.n?.appName ?? "")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol {
                                text: "priority_high"
                                fill: 1
                                iconSize: 30
                                color: Appearance.colors.colPrimary
                                SequentialAnimation on scale {
                                    running: alert.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 1.25; duration: 380; easing.type: Easing.OutQuad }
                                    NumberAnimation { from: 1.25; to: 1; duration: 520; easing.type: Easing.OutBounce }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: alert.bodyText
                            wrapMode: Text.Wrap
                            maximumLineCount: 6
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: alert.spec.ink ?? Appearance.colors.colOnLayer0
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: replyButton.visible || actionsRepeater.count > 0
                            PillButton {
                                id: replyButton
                                visible: alert.replyMethod !== null
                                label: alert.replyMethod?.kind === "inline" ? Translation.tr("Reply")
                                    : Translation.tr("Reply in %1").arg(alert.n?.appName || Translation.tr("the app"))
                                toggled: alert.replying
                                onClicked: {
                                    if (alert.replyMethod?.kind === "inline") {
                                        alert.replying = !alert.replying;
                                        if (!alert.replying) keyTarget.forceActiveFocus();
                                    } else {
                                        Notifications.replyViaApp(alert.n.notificationId);
                                        root.dismiss();
                                    }
                                }
                            }
                            Repeater {
                                id: actionsRepeater
                                model: (alert.n?.actions ?? []).filter(a => a.identifier !== "default"
                                    && a.identifier !== alert.replyMethod?.identifier).slice(0, 3)
                                delegate: PillButton {
                                    required property var modelData
                                    label: modelData.text
                                    onClicked: {
                                        Notifications.attemptInvokeAction(alert.n.notificationId, modelData.identifier);
                                        root.dismiss();
                                    }
                                }
                            }
                        }

                        // Inline reply
                        Rectangle {
                            visible: alert.replying
                            Layout.fillWidth: true
                            implicitHeight: Math.max(46, replyInput.contentHeight + 22)
                            radius: height / 2
                            color: Appearance.colors.colLayer1
                            border.width: 2
                            border.color: Appearance.colors.colPrimary
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: replyInput.forceActiveFocus()
                            }
                            TextInput {
                                id: replyInput
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 20 }
                                color: Appearance.colors.colOnLayer1
                                selectionColor: Appearance.colors.colPrimaryContainer
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.normal
                                clip: true
                                Keys.onReturnPressed: alert.sendReply()
                                Keys.onEnterPressed: alert.sendReply()
                                Keys.onEscapePressed: {
                                    alert.replying = false;
                                    keyTarget.forceActiveFocus();
                                }
                                StyledText {
                                    visible: replyInput.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: alert.n?.inlineReplyPlaceholder || Translation.tr("Reply… (Enter sends)")
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
