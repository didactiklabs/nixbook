pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

/**
 * Persona-style notification popup: the in-game phone chat. A tilted mugshot
 * (the notification's image — contact photo, avatar — else the app icon) in a
 * bold frame with the variant's hard shadow, a slanted name tag (sender =
 * summary, app name beside it) and speech bubbles with a tail, one per
 * message of the group (latest three). Colours per variant come from
 * Persona.spec (bubble / tag / mugBorder). Used for popups by
 * NotificationListView while the Persona style (shapes) is on.
 *
 * Also used by the notification centre (right sidebar) with `popup: false`:
 * smaller mugshot, no entrance animation (the list recycles delegates), no
 * timeout handling, a close button, and "+N earlier" for longer threads.
 *
 * The chevron on the name tag expands the conversation: every message of the
 * group and the full text of each (collapsed: the latest three, 4 lines each).
 * It only shows when something is hidden. Popups also get a mark-as-read
 * button (Notifications.markRead: hides the popup, keeps it in the centre and
 * runs the app's own "mark as read" action when it has one) and a delete
 * button (discarded, not kept in the centre). A reply button (popup and
 * centre, Notifications.replyMethod) opens a reply box in the card when the app
 * asked for an inline reply (Enter sends, Esc cancels — the popup layer takes
 * the keyboard meanwhile), else runs the app's Reply action or, for messages,
 * opens the conversation.
 *
 * Left click: default action (or just dismiss the popup). Right click: hide
 * the popup (kept in the notification centre) / discard in the centre.
 * Middle click: discard. Hovering a popup pauses its timeout.
 */
MouseArea {
    id: root
    required property var notificationGroup
    property bool popup: true
    readonly property var notifications: root.notificationGroup?.notifications ?? []
    readonly property var latest: root.notifications.length > 0 ? root.notifications[root.notifications.length - 1] : null
    property bool expanded: false
    readonly property var replyMethod: Notifications.replyMethod(root.latest)
    property bool replying: false
    onReplyingChanged: {
        if (root.popup) {
            Notifications.replyingPopups += root.replying ? 1 : -1;
            // No timeout while typing; the countdown resumes on cancel.
            root.notifications.forEach(n => root.replying
                ? Notifications.cancelTimeout(n.notificationId)
                : Notifications.resumeTimeout(n.notificationId));
        }
        if (root.replying) Qt.callLater(() => replyInput.forceActiveFocus());
    }
    Component.onDestruction: if (root.replying && root.popup) Notifications.replyingPopups -= 1
    function sendReply() {
        if (Notifications.sendReply(root.latest?.notificationId ?? -1, replyInput.text)) {
            replyInput.text = "";
            root.replying = false;
        }
    }
    readonly property var shown: root.expanded ? root.notifications : root.notifications.slice(-3)
    // Some bubble is cut at its line limit (reported by the bubbles).
    property int truncatedBubbles: 0
    readonly property bool canExpand: root.expanded || root.hiddenCount > 0 || root.truncatedBubbles > 0
    readonly property var spec: Persona.spec
    readonly property int hiddenCount: Math.max(0, root.notifications.length - root.shown.length)
    readonly property real mugSize: root.popup ? 62 : 46

    implicitHeight: row.implicitHeight + 18
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    onContainsMouseChanged: if (root.popup && !root.replying) root.notifications.forEach(n => {
        if (root.containsMouse) Notifications.cancelTimeout(n.notificationId);
        else Notifications.resumeTimeout(n.notificationId);
    })
    onClicked: mouse => {
        const ids = root.notifications.map(n => n.notificationId);
        if (mouse.button === Qt.MiddleButton || (!root.popup && mouse.button === Qt.RightButton)) {
            Notifications.discardNotifications(ids);
        } else if (mouse.button === Qt.LeftButton && root.latest?.actions.some(a => a.identifier === "default")) {
            Notifications.attemptInvokeAction(root.latest.notificationId, "default");
            ids.forEach(id => Notifications.timeoutNotification(id));
        } else {
            ids.forEach(id => Notifications.timeoutNotification(id));
        }
    }

    // Slam in from the side.
    property real enter: root.popup ? 0 : 1
    Component.onCompleted: enter = 1
    Behavior on enter {
        NumberAnimation {
            duration: Persona.motion ? 320 : 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Persona.motion ? Persona.curves.slam : Appearance.animationCurves.expressiveDefaultSpatial
        }
    }
    opacity: Math.min(1, root.enter * 1.6)
    transform: [
        Translate { x: (1 - root.enter) * 90 },
        Rotation { origin.x: root.width; origin.y: 0; angle: (1 - root.enter) * -8 }
    ]

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
        spacing: 12

        // ---- mugshot
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 4
            implicitWidth: root.mugSize
            implicitHeight: root.mugSize
            rotation: -6
            Rectangle { // hard shadow
                x: Persona.shadowOffset; y: Persona.shadowOffset
                width: parent.width; height: parent.height
                color: Persona.shadowColor
            }
            // Critical (urgency set by the app): "!" badge on the mugshot.
            Rectangle {
                z: 2
                visible: root.notifications.some(n => n.urgency == NotificationUrgency.Critical || n.urgency === "critical")
                x: parent.width - width / 2 - 2
                y: -height / 2 + 2
                width: 20
                height: 20
                rotation: 6
                color: Persona.shadowColor
                border.width: 2
                border.color: root.spec.mugBorder
                StyledText {
                    anchors.centerIn: parent
                    text: "!"
                    font.family: Persona.titleFont
                    font.pixelSize: 15
                    font.weight: Font.Black
                    color: root.spec.mugBorder
                }
            }
            Rectangle {
                id: mugFrame
                anchors.fill: parent
                color: root.spec.frame
                border.width: 3
                border.color: root.spec.mugBorder
                clip: true
                // The picture can be gone (notification history keeps paths to
                // temporary files): fall back to the app icon, then a symbol.
                readonly property bool hasPicture: (root.latest?.image ?? "") !== "" && mugImage.status !== Image.Error
                readonly property string appIconPath: (root.notificationGroup?.appIcon ?? "") !== "" ? Quickshell.iconPath(root.notificationGroup.appIcon, true) : ""
                readonly property bool hasAppIcon: appIconPath !== ""
                Image {
                    id: mugImage
                    anchors { fill: parent; margins: 3 }
                    visible: mugFrame.hasPicture
                    source: (root.latest?.image ?? "") !== "" ? root.latest.image : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(112, 112)
                    asynchronous: true
                    cache: false
                }
                IconImage {
                    id: appIconImage
                    anchors.centerIn: parent
                    visible: !mugFrame.hasPicture && mugFrame.hasAppIcon
                    implicitSize: root.mugSize * 0.65
                    asynchronous: true
                    source: mugFrame.appIconPath
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !mugFrame.hasPicture && !mugFrame.hasAppIcon
                    text: NotificationUtils.findSuitableMaterialSymbol(root.latest?.summary ?? "")
                    iconSize: root.mugSize * 0.55
                    color: root.spec.mugBorder
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            // ---- name tag (slanted)
            Item {
                Layout.fillWidth: true
                implicitHeight: tagRow.implicitHeight + 6
                Rectangle {
                    id: tag
                    width: Math.min(parent.width - (tagControls.width + 6), tagRow.implicitWidth + 22)
                    height: parent.height
                    color: root.spec.tag
                    border.width: root.spec.tag === root.spec.frame ? 2 : 0
                    border.color: root.spec.mugBorder
                    transform: Matrix4x4 {
                        matrix: Qt.matrix4x4(1, -0.25, 0, 0.25 * tag.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                    }
                }
                // Expand (popup and centre); time + discard (centre only).
                RowLayout {
                    id: tagControls
                    visible: true
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    RippleButton {
                        id: replyButton
                        visible: root.replyMethod !== null
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Persona.corner
                        toggled: root.replying
                        colBackground: root.popup ? root.spec.tag : "transparent"
                        colBackgroundHover: Persona.shadowColor
                        onClicked: {
                            if (root.replyMethod?.kind === "inline") root.replying = !root.replying;
                            else Notifications.replyViaApp(root.latest.notificationId);
                        }
                        StyledToolTip {
                            text: root.replyMethod?.kind === "inline" ? Translation.tr("Reply")
                                : Translation.tr("Reply in %1").arg(root.notificationGroup?.appName || Translation.tr("the app"))
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "reply"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.popup || replyButton.toggled ? root.spec.tagText : Appearance.colors.colOnLayer1
                        }
                    }
                    RippleButton {
                        id: expandButton
                        visible: root.canExpand
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Persona.corner
                        colBackground: root.popup ? root.spec.tag : "transparent"
                        colBackgroundHover: Persona.shadowColor
                        onClicked: root.expanded = !root.expanded
                        StyledToolTip {
                            text: root.expanded ? Translation.tr("Collapse") : Translation.tr("Show the whole conversation")
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.expanded ? "expand_less" : "expand_more"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.popup ? root.spec.tagText : Appearance.colors.colOnLayer1
                        }
                    }
                    RippleButton {
                        id: markReadButton
                        visible: root.popup
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Persona.corner
                        colBackground: root.spec.tag
                        colBackgroundHover: Persona.shadowColor
                        onClicked: Notifications.markRead(root.notifications.map(n => n.notificationId))
                        StyledToolTip {
                            text: Translation.tr("Mark as read")
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "done_all"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.spec.tagText
                        }
                    }
                    StyledText {
                        visible: !root.popup
                        text: NotificationUtils.getFriendlyNotifTimeString(root.latest?.time ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    // Discard: popups too (delete — not kept in the centre).
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Persona.corner
                        colBackground: root.popup ? root.spec.tag : "transparent"
                        colBackgroundHover: root.popup ? Persona.shadowColor : Appearance.colors.colLayer1Hover
                        onClicked: Notifications.discardNotifications(root.notifications.map(n => n.notificationId))
                        StyledToolTip {
                            extraVisibleCondition: root.popup
                            text: Translation.tr("Delete (not kept in the notification centre)")
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.popup ? "delete" : "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.popup ? root.spec.tagText : Appearance.colors.colOnLayer1
                        }
                    }
                }
                RowLayout {
                    id: tagRow
                    anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                    width: Math.min(implicitWidth, parent.width - 22 - (tagControls.width + 6))
                    spacing: 8
                    StyledText {
                        Layout.maximumWidth: 200
                        elide: Text.ElideRight
                        text: (root.latest?.summary || root.notificationGroup?.appName || "").toUpperCase()
                        font.family: Persona.fonts ? Persona.titleFont : Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: root.spec.tagText
                    }
                    StyledText {
                        visible: (root.notificationGroup?.appName ?? "") !== "" && root.notificationGroup.appName !== root.latest?.summary
                        Layout.maximumWidth: 110
                        elide: Text.ElideRight
                        text: root.notificationGroup?.appName ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.spec.tagText
                        opacity: 0.7
                    }
                }
            }

            StyledText {
                visible: root.hiddenCount > 0 && !root.expanded
                Layout.leftMargin: 10
                text: Translation.tr("+%1 earlier").arg(root.hiddenCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }

            // ---- speech bubbles
            Repeater {
                model: root.shown
                delegate: Item {
                    id: bubbleItem
                    required property var modelData
                    required property int index
                    readonly property string text: NotificationUtils.processNotificationBody(modelData.body || "", modelData.appName || modelData.summary)
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    visible: text.length > 0
                    implicitHeight: bubble.height
                    rotation: bubbleItem.index % 2 === 0 ? -1.2 : 0.8

                    // tail toward the mugshot
                    Canvas {
                        id: tail
                        x: -9; y: 10
                        width: 12; height: 14
                        property color fill: root.spec.bubble
                        onFillChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = tail.fill;
                            ctx.beginPath();
                            ctx.moveTo(width, 0);
                            ctx.lineTo(0, height * 0.55);
                            ctx.lineTo(width, height);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                    Rectangle { // hard shadow
                        x: 4; y: 4
                        width: bubble.width; height: bubble.height
                        radius: bubble.radius
                        color: Persona.shadowColor
                        opacity: 0.85
                    }
                    Rectangle {
                        id: bubble
                        width: Math.min(parent.width, bodyText.implicitWidth + 28)
                        height: bodyText.implicitHeight + 18
                        radius: 16
                        color: root.spec.bubble
                        StyledText {
                            id: bodyText
                            anchors { left: parent.left; top: parent.top; margins: 14; topMargin: 9 }
                            width: Math.min(implicitWidth, bubbleItem.width - 28)
                            text: bubbleItem.text.replace(/\n/g, "<br/>")
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            maximumLineCount: root.expanded ? 1000 : 4
                            elide: Text.ElideRight
                            // Tell the card whether something is cut off.
                            property bool countedTruncated: false
                            function syncTruncated() {
                                const t = truncated && !root.expanded;
                                if (t === countedTruncated) return;
                                countedTruncated = t;
                                root.truncatedBubbles += t ? 1 : -1;
                            }
                            onTruncatedChanged: syncTruncated()
                            Component.onCompleted: syncTruncated()
                            Component.onDestruction: if (countedTruncated) root.truncatedBubbles -= 1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: root.spec.bubbleText
                        }
                    }
                }
            }

            // ---- inline reply: your own bubble, on the right
            Item {
                id: replyBox
                visible: root.replying
                Layout.fillWidth: true
                Layout.leftMargin: 24
                implicitHeight: replyBubble.height + 4
                Rectangle { // hard shadow
                    x: replyBubble.x + 4; y: 4
                    width: replyBubble.width; height: replyBubble.height
                    radius: replyBubble.radius
                    color: Persona.shadowColor
                    opacity: 0.85
                }
                Rectangle {
                    id: replyBubble
                    anchors.right: parent.right
                    width: parent.width
                    height: Math.max(36, replyInput.contentHeight + 18)
                    radius: 16
                    color: root.spec.tag
                    border.width: root.spec.tag === root.spec.frame ? 2 : 0
                    border.color: root.spec.mugBorder
                    StyledTextInput {
                        id: replyInput
                        anchors { left: parent.left; right: sendButton.left; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 6 }
                        wrapMode: TextInput.Wrap
                        color: root.spec.tagText
                        selectByMouse: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        Keys.onReturnPressed: event => {
                            if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return; }
                            root.sendReply();
                        }
                        Keys.onEnterPressed: root.sendReply()
                        Keys.onEscapePressed: root.replying = false
                        StyledText {
                            anchors.fill: parent
                            visible: replyInput.text.length === 0
                            text: root.latest?.inlineReplyPlaceholder || Translation.tr("Reply…")
                            font: replyInput.font
                            color: root.spec.tagText
                            opacity: 0.55
                            elide: Text.ElideRight
                        }
                    }
                    RippleButton {
                        id: sendButton
                        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: 14
                        enabled: replyInput.text.trim().length > 0
                        colBackground: Persona.shadowColor
                        onClicked: root.sendReply()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "send"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.spec.mugBorder
                        }
                    }
                }
            }

            // ---- actions (latest message)
            Flow {
                id: actionsFlow
                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 6
                readonly property var actions: (root.latest?.actions ?? []).filter(a => a.identifier !== "default"
                    && !(root.popup && a.identifier === Notifications.markReadAction(root.latest)?.identifier)
                    && a.identifier !== root.replyMethod?.identifier)
                visible: actions.length > 0
                Repeater {
                    model: actionsFlow.actions.slice(0, 3)
                    delegate: RippleButton {
                        id: actionButton
                        required property var modelData
                        implicitHeight: 28
                        implicitWidth: actionText.implicitWidth + 22
                        buttonRadius: Persona.corner
                        colBackground: root.spec.tag
                        colBackgroundHover: Persona.shadowColor
                        onClicked: {
                            Notifications.attemptInvokeAction(root.latest.notificationId, modelData.identifier);
                            Notifications.timeoutNotification(root.latest.notificationId);
                        }
                        contentItem: StyledText {
                            id: actionText
                            anchors.centerIn: parent
                            text: actionButton.modelData.text.toUpperCase()
                            font.family: Persona.fonts ? Persona.titleFont : Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: root.spec.tagText
                        }
                    }
                }
            }
        }
    }
}
