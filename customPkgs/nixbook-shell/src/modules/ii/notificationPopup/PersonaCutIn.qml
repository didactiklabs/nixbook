pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

/**
 * Persona "cut-in" for critical notifications: a full-screen overlay with the
 * sender's picture slashing across the screen in a jagged band, a slanted
 * dialogue box with the message typed out, a skewed name tag with the speech
 * tail, the "next" triangle and the calendar badge. Shown on the focused
 * monitor while the Persona style is on, never while locked or silenced (DND).
 *
 * Click: run the notification's default action and dismiss. Right click /
 * Escape / Enter / Space: dismiss (the notification stays in the centre).
 * Several critical notifications queue up.
 */
Scope {
    id: root

    property var queue: []
    readonly property var current: root.queue.length > 0 ? root.queue[0] : null
    readonly property bool enabled: Persona.enabled && Persona.shapes

    readonly property var rules: Config.options?.notifications?.cutIn ?? ({})
    function isCritical(n) {
        return n && (n.urgency == NotificationUrgency.Critical || n.urgency === "critical");
    }
    // Settings → Notifications → Persona cut-in: critical urgency, chosen
    // apps, or keywords in the title/text (case-insensitive).
    // Everything a keyword can match: app name, title, raw text (Chromium
    // browsers put the origin site on its first line) and string hints.
    function matchText(n) {
        const hints = n?.hints ?? {};
        const hintText = Object.keys(hints).map(k => typeof hints[k] === "string" ? hints[k] : "").join(" ");
        return `${n?.appName ?? ""} ${n?.summary ?? ""} ${n?.body ?? ""} ${hintText}`.toLowerCase();
    }
    // Why `n` gets a cut-in ("" = it doesn't).
    function cutInReason(n) {
        if (!n || !(root.rules.enable ?? true)) return "";
        if ((root.rules.critical ?? true) && root.isCritical(n)) return "critical";
        const app = (n.appName ?? "").toLowerCase();
        if ((root.rules.apps ?? []).some(a => a.toLowerCase() === app)) return `app "${n.appName}"`;
        const text = root.matchText(n);
        const keyword = (root.rules.keywords ?? []).find(k => k.trim().length > 0 && text.includes(k.trim().toLowerCase()));
        return keyword ? `keyword "${keyword}"` : "";
    }
    function wantsCutIn(n) {
        return root.cutInReason(n) !== "";
    }
    property var lastSeen: null
    function show(n) {
        root.queue = root.queue.concat([n]);
    }
    function next() {
        root.queue = root.queue.slice(1);
    }
    function dismiss() {
        cutIn.leave(() => root.next());
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
            root.lastSeen = n;
            if (root.enabled && !Notifications.silent && !GlobalStates.screenLocked && root.wantsCutIn(n))
                root.show(n);
        }
        // Discarded elsewhere (centre, app withdrew it): drop it from the queue.
        function onDiscard(id) {
            if (root.current?.notificationId === id) root.dismiss();
            else root.queue = root.queue.filter(n => n.notificationId !== id);
        }
    }

    Connections {
        target: GlobalStates
        function onPersonaCutInPreviewChanged() {
            root.show({ notificationId: -1, summary: Translation.tr("Preview"), body: Translation.tr("This is how a cut-in notification looks."),
                appName: "nixbook-shell", appIcon: "", image: UserAvatar.source, actions: [], time: Date.now() });
        }
    }

    IpcHandler {
        target: "personaCutIn"
        // Preview: `nixbook-shell ipc call personaCutIn test "Name" "Message"`
        // What the last notification contained and whether it got a cut-in —
        // to write rules: `nixbook-shell ipc call personaCutIn explain`
        function explain(): string {
            const n = root.lastSeen;
            if (!n) return "no notification received since the shell started";
            const hints = n.hints ?? {};
            return JSON.stringify({
                app: n.appName, title: n.summary, text: n.body, urgency: n.urgency,
                hints: Object.fromEntries(Object.keys(hints).filter(k => typeof hints[k] !== "object").map(k => [k, hints[k]])),
                cutIn: root.cutInReason(n) || "no"
            }, null, 2);
        }
        function test(name: string, message: string): void {
            root.show({ notificationId: -1, summary: name, body: message, appName: "nixbook-shell", appIcon: "", image: "", actions: [], time: Date.now() });
        }
    }

    PanelWindow {
        id: cutIn
        visible: root.current !== null
        screen: Quickshell.screens.find(s => s.name === WM.focusedMonitor?.name) ?? null
        WlrLayershell.namespace: "quickshell:personaCutIn"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        readonly property var n: root.current
        readonly property var spec: Persona.spec
        readonly property real w: width
        readonly property real h: height
        readonly property string bodyText: NotificationUtils.processNotificationBody(n?.body ?? "", n?.appName ?? "")
            .replace(/<[^>]*>/g, "").trim() || (n?.summary ?? "")
        readonly property string speaker: (n?.body ? n?.summary : n?.appName) || n?.appName || ""

        // 0 → 1 entrance, reversed on leave.
        property real t: 0
        property var afterLeave: null
        function leave(cb) {
            afterLeave = cb;
            leaveAnim.restart();
        }
        onNChanged: {
            if (!n) return;
            leaveAnim.stop();
            t = 0;
            typed = 0;
            enterAnim.restart();
        }
        NumberAnimation on t {
            id: enterAnim
            running: false
            to: 1
            duration: 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Persona.curves.slam
        }
        SequentialAnimation {
            id: leaveAnim
            NumberAnimation { target: cutIn; property: "t"; to: 0; duration: 200; easing.type: Easing.InCubic }
            ScriptAction { script: { const cb = cutIn.afterLeave; cutIn.afterLeave = null; if (cb) cb(); } }
        }

        // Typewriter reveal of the message.
        property int typed: 0
        Timer {
            running: cutIn.visible && cutIn.t > 0.6 && cutIn.typed < cutIn.bodyText.length
            interval: 16
            repeat: true
            onTriggered: cutIn.typed = Math.min(cutIn.bodyText.length, cutIn.typed + 2)
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if ([Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) {
                    // First press finishes the typing, the next one dismisses.
                    if (cutIn.typed < cutIn.bodyText.length) cutIn.typed = cutIn.bodyText.length;
                    else root.dismiss();
                    event.accepted = true;
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => mouse.button === Qt.RightButton ? root.dismiss() : root.activate()
            }

            // Scrim
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.45 * Math.min(1, cutIn.t * 2)
            }

            // ---- cut-in band with the picture (from the right, slashing down-left)
            Item {
                id: band
                anchors.fill: parent
                opacity: Math.min(1, cutIn.t * 1.5)
                transform: Translate { x: (1 - cutIn.t) * cutIn.w * 0.45; y: (1 - cutIn.t) * -cutIn.h * 0.12 }

                // Band polygon (outer = black outline, mid = light border, inner = picture)
                function poly(inset) {
                    const w = cutIn.w, h = cutIn.h;
                    return [
                        Qt.point(w * 0.40 + inset * 1.6, h * 0.70 - inset),
                        Qt.point(w * 0.93 + inset, h * 0.05 + inset * 0.3),
                        Qt.point(w + 40, h * 0.06 + inset),
                        Qt.point(w + 40, h * 0.62 - inset),
                        Qt.point(w * 0.47 + inset * 0.4, h * 0.86 - inset * 1.2),
                    ];
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: cutIn.spec.frame
                        strokeWidth: 0
                        PathPolyline { path: band.poly(-18) }
                    }
                    ShapePath {
                        fillColor: cutIn.spec.frameBorder
                        strokeWidth: 0
                        PathPolyline { path: band.poly(-7) }
                    }
                }
                // Accent slash behind the band (P5 red, P3R cyan, P4 yellow)
                Shape {
                    anchors.fill: parent
                    z: -1
                    ShapePath {
                        fillColor: Persona.shadowColor
                        strokeWidth: 0
                        PathPolyline {
                            path: [
                                Qt.point(cutIn.w * 0.34, cutIn.h * 0.80), Qt.point(cutIn.w * 0.90, cutIn.h * 0.0),
                                Qt.point(cutIn.w * 0.96, cutIn.h * 0.0), Qt.point(cutIn.w * 0.39, cutIn.h * 0.84)
                            ]
                        }
                    }
                }

                // Picture, masked to the inner polygon
                Item {
                    id: pictureLayer
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: bandMask
                        maskThresholdMin: 0.5
                    }
                    Rectangle { // background for icons
                        anchors.fill: parent
                        color: cutIn.spec.surface3 ?? cutIn.spec.frame
                    }
                    PersonaTexture {
                        anchors.fill: parent
                        opacity: 0.5
                    }
                    Image {
                        id: face
                        readonly property bool ok: (cutIn.n?.image ?? "") !== "" && status !== Image.Error
                        visible: ok
                        x: cutIn.w * 0.42; y: -cutIn.h * 0.05
                        width: cutIn.w * 0.62; height: cutIn.h * 0.95
                        source: cutIn.n?.image ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        rotation: -6
                        scale: 1.0 + (1 - cutIn.t) * 0.15
                    }
                    IconImage {
                        visible: !face.ok
                        x: cutIn.w * 0.60; y: cutIn.h * 0.14
                        implicitSize: Math.min(cutIn.w, cutIn.h) * 0.42
                        rotation: -8
                        source: (cutIn.n?.appIcon ?? "") !== "" ? Quickshell.iconPath(cutIn.n.appIcon, "dialog-warning") : Quickshell.iconPath("dialog-warning")
                    }
                }
                Shape {
                    id: bandMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    ShapePath {
                        fillColor: "white"
                        strokeWidth: 0
                        PathPolyline { path: band.poly(0) }
                    }
                }
            }

            // ---- date badge (top-left)
            Column {
                x: 40 - (1 - cutIn.t) * 120
                y: 30
                opacity: cutIn.t
                rotation: -8
                spacing: -14
                StyledText {
                    text: Qt.formatDate(new Date(), "M/d")
                    font.family: Persona.titleFont
                    font.pixelSize: 84
                    font.weight: Font.Black
                    color: cutIn.spec.ink
                    style: Text.Outline
                    styleColor: cutIn.spec.frame
                }
                StyledText {
                    x: 60
                    text: Qt.formatDate(new Date(), "dddd").toUpperCase()
                    font.family: Persona.titleFont
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    color: cutIn.spec.frame
                    style: Text.Outline
                    styleColor: cutIn.spec.ink
                }
            }

            // ---- dialogue box
            Item {
                id: dialog
                readonly property real bx: cutIn.w * 0.27
                readonly property real by: cutIn.h * 0.76
                readonly property real bw: cutIn.w * 0.46
                readonly property real bh: Math.max(cutIn.h * 0.16, dialogText.implicitHeight + 70)
                anchors.fill: parent
                opacity: Math.min(1, Math.max(0, cutIn.t * 1.6 - 0.3))
                transform: Translate { x: -(1 - cutIn.t) * 160; y: (1 - cutIn.t) * 60 }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath { // light outer border
                        fillColor: cutIn.spec.frameBorder
                        strokeWidth: 0
                        PathPolyline {
                            path: [
                                Qt.point(dialog.bx - 10, dialog.by + 4), Qt.point(dialog.bx + dialog.bw + 14, dialog.by - 22),
                                Qt.point(dialog.bx + dialog.bw + 6, dialog.by + dialog.bh + 8), Qt.point(dialog.bx + 4, dialog.by + dialog.bh + 14)
                            ]
                        }
                    }
                    ShapePath { // body
                        fillColor: cutIn.spec.frame
                        strokeWidth: 0
                        PathPolyline {
                            path: [
                                Qt.point(dialog.bx, dialog.by + 10), Qt.point(dialog.bx + dialog.bw, dialog.by - 12),
                                Qt.point(dialog.bx + dialog.bw - 6, dialog.by + dialog.bh), Qt.point(dialog.bx + 12, dialog.by + dialog.bh + 4)
                            ]
                        }
                    }
                    ShapePath { // "next" triangle
                        fillColor: cutIn.spec.frameBorder
                        strokeWidth: 0
                        PathPolyline {
                            path: [
                                Qt.point(dialog.bx + dialog.bw - 110, dialog.by + dialog.bh - 14), Qt.point(dialog.bx + dialog.bw + 70, dialog.by - 4),
                                Qt.point(dialog.bx + dialog.bw - 60, dialog.by + dialog.bh + 2)
                            ]
                        }
                    }
                }

                StyledText {
                    id: dialogText
                    x: dialog.bx + 48
                    y: dialog.by + 26
                    width: dialog.bw - 190
                    text: cutIn.bodyText.substring(0, cutIn.typed)
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                    font.pixelSize: Math.round(Appearance.font.pixelSize.huge * 1.15)
                    font.weight: Font.DemiBold
                    color: cutIn.spec.ink
                }

                // Name tag (skewed, one inverted letter) with the speech tail
                Item {
                    id: nameTag
                    x: dialog.bx - 40
                    y: dialog.by - 58
                    rotation: -6
                    scale: 0.6 + 0.4 * cutIn.t
                    width: nameText.implicitWidth + 64
                    height: nameText.implicitHeight + 16
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            fillColor: cutIn.spec.bubble
                            strokeColor: cutIn.spec.frame
                            strokeWidth: 3
                            PathPolyline {
                                path: [
                                    Qt.point(0, 10), Qt.point(nameTag.width, 0), Qt.point(nameTag.width - 10, nameTag.height),
                                    Qt.point(nameTag.width * 0.62, nameTag.height), Qt.point(nameTag.width * 0.66, nameTag.height + 26),
                                    Qt.point(nameTag.width * 0.48, nameTag.height), Qt.point(12, nameTag.height - 2), Qt.point(0, 10)
                                ]
                            }
                        }
                    }
                    Text {
                        id: nameText
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 4
                        textFormat: Text.RichText
                        // Invert one letter, like the games' name plates.
                        text: {
                            const name = cutIn.speaker;
                            if (name.length < 3) return name;
                            const i = 1 + (name.length * 7) % (name.length - 1);
                            const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
                            return `${esc(name.slice(0, i))}<span style="background-color:${cutIn.spec.bubbleText};color:${cutIn.spec.bubble};">${esc(name[i])}</span>${esc(name.slice(i + 1))}`;
                        }
                        font.family: Persona.titleFont
                        font.pixelSize: 38
                        font.weight: Font.Bold
                        color: cutIn.spec.bubbleText
                    }
                }

                // App name + time
                StyledText {
                    x: dialog.bx + 48
                    y: dialog.by + dialog.bh - 26
                    text: `${cutIn.n?.appName ?? ""} · ${Qt.formatTime(new Date(cutIn.n?.time ?? Date.now()), "hh:mm")}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: cutIn.spec.ink
                    opacity: 0.6
                }

                // Actions
                Row {
                    x: dialog.bx + 40
                    y: dialog.by + dialog.bh + 26
                    spacing: 10
                    Repeater {
                        model: (cutIn.n?.actions ?? []).filter(a => a.identifier !== "default").slice(0, 3)
                        delegate: RippleButton {
                            id: actionButton
                            required property var modelData
                            implicitHeight: 34
                            implicitWidth: actionLabel.implicitWidth + 30
                            buttonRadius: 0
                            colBackground: cutIn.spec.frame
                            colBackgroundHover: Persona.shadowColor
                            onClicked: {
                                Notifications.attemptInvokeAction(cutIn.n.notificationId, modelData.identifier);
                                root.dismiss();
                            }
                            contentItem: StyledText {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: actionButton.modelData.text.toUpperCase()
                                font.family: Persona.titleFont
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: cutIn.spec.ink
                            }
                        }
                    }
                }
            }
        }
    }
}
