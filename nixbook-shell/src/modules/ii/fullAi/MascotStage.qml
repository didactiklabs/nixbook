pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The Full AI mode's stage: the mascot as the desktop's MC, on a
 * transparent full-screen surface. It wanders between spots (edges,
 * corners, the top third rather than the middle) in arcs, squashing and
 * stretching, its eyes on where it goes, a bounce when it lands; dash()
 * darts it somewhere else with a sparkle trail (the agent starting a
 * step); listening it stays put, facing the user; speaking it comes down
 * towards the bottom centre. A speech balloon follows it with `line`, and
 * `hint` sits at the bottom of the screen.
 *   mood, line, hint, level, talking, active (false: no wandering), zoom
 *   celebrate(), shake(), dash()
 */
Item {
    id: root
    anchors.fill: parent

    property string mood: "idle"
    property string line: ""
    // "say" (a speech bubble with its tail), "thought" (a dimmer cloud in
    // italics, little circles trailing to the mascot), "heard" (the user's
    // words, in quotes), "status" (how to talk to it).
    property string lineKind: "say"
    // Yes / No under a question (FullAi.yesNo): `chose(yes)` on a click;
    // `choicesArea` is what the overlay lets clicks through to.
    property bool yesNo: false
    signal chose(bool yes)
    readonly property Item choicesArea: choices
    readonly property bool thinking: root.lineKind === "thought" || root.lineKind === "status"
    property string hint: ""
    property real level: 0
    property bool talking: false
    property bool active: true
    // How big the mascot is (1: 120×140 px).
    property real zoom: 1.3

    readonly property real margin: 40
    readonly property real mw: mascot.width * root.zoom
    readonly property real mh: mascot.height * root.zoom

    function celebrate() { mascot.celebrate(); }
    function shake() { mascot.shake(); }
    function dash() {
        if (!root.active) return;
        root.travel(root.pickSpot(false), 380, 0.35, true);
    }

    // ── Where it goes ──
    // Edges and corners, the top third more than the bottom, not the
    // middle of the screen.
    // Never where Claude's speech bubble is (the top-left corner, under the
    // bar): it holds the conversation.
    readonly property rect bubbleZone: Qt.rect(0, 0, 460, 360)
    function pickSpot(small) {
        const p = root.pickSpotAnywhere(small);
        if (p.x < root.bubbleZone.x + root.bubbleZone.width && p.y < root.bubbleZone.y + root.bubbleZone.height)
            return Qt.point(Math.max(p.x, root.bubbleZone.width + root.margin), p.y);
        return p;
    }
    function pickSpotAnywhere(small) {
        const w = Math.max(root.width, 400), h = Math.max(root.height, 300);
        const minX = root.margin, maxX = w - root.mw - root.margin;
        const minY = root.margin + 30, maxY = h - root.mh - root.margin - 40;
        if (small) {
            const nx = Math.max(minX, Math.min(maxX, actor.x + (Math.random() - 0.5) * 220));
            const ny = Math.max(minY, Math.min(maxY, actor.y + (Math.random() - 0.5) * 120));
            return Qt.point(nx, ny);
        }
        for (let i = 0; i < 8; i++) {
            const r = Math.random();
            let x, y;
            if (r < 0.55) { // the top third, anywhere across
                x = minX + Math.random() * (maxX - minX);
                y = minY + Math.random() * Math.max(10, h * 0.33 - minY);
            } else if (r < 0.85) { // a side, any height
                x = Math.random() < 0.5 ? minX + Math.random() * w * 0.15 : maxX - Math.random() * w * 0.15;
                y = minY + Math.random() * (maxY - minY);
            } else { // the bottom band
                x = minX + Math.random() * (maxX - minX);
                y = maxY - Math.random() * h * 0.12;
            }
            const cx = x + root.mw / 2, cy = y + root.mh / 2;
            const central = Math.abs(cx - w / 2) < w * 0.2 && Math.abs(cy - h / 2) < h * 0.2;
            const far = Math.hypot(x - actor.x, y - actor.y) > 160;
            if (!central && far) return Qt.point(x, y);
        }
        return Qt.point(minX + Math.random() * (maxX - minX), minY);
    }

    // ── How it goes: an arc (t 0..1), stretched while flying ──
    property point from: Qt.point(0, 0)
    property point to: Qt.point(0, 0)
    property real arc: 0
    property real t: 1
    property bool trail: false
    function travel(target, duration, arcFactor, sparkle) {
        root.from = Qt.point(actor.x, actor.y);
        root.to = target;
        const d = Math.hypot(target.x - actor.x, target.y - actor.y);
        // Never above the screen's top edge mid-flight.
        root.arc = Math.max(0, Math.min(160, d * arcFactor, Math.min(actor.y, target.y) - 8));
        root.trail = sparkle;
        root.restLook = Math.max(-0.6, Math.min(0.6, (target.x - actor.x) / 400));
        if (sparkle) trailDots.drop();
        flight.duration = duration;
        root.t = 0;
        flight.restart();
    }
    NumberAnimation {
        id: flight
        target: root
        property: "t"
        from: 0
        to: 1
        easing.type: Easing.InOutCubic
        onFinished: landing.restart()
    }
    readonly property bool flying: flight.running
    // Where it rests its eyes after a flight (a little towards where it went).
    property real restLook: 0
    onTChanged: {
        actor.x = root.from.x + (root.to.x - root.from.x) * root.t;
        actor.y = root.from.y + (root.to.y - root.from.y) * root.t - Math.sin(Math.PI * root.t) * root.arc;
    }
    // A squash on landing, then back to round.
    SequentialAnimation {
        id: landing
        ParallelAnimation {
            NumberAnimation { target: mascot; property: "stretchX"; to: 1.16; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: mascot; property: "stretchY"; to: 0.86; duration: 90; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: mascot; property: "stretchX"; to: 1; duration: 260; easing.type: Easing.OutBack }
            NumberAnimation { target: mascot; property: "stretchY"; to: 1; duration: 260; easing.type: Easing.OutBack }
        }
    }

    // Wandering: every 2–6 s (listening: rarely and a little; speaking: to
    // the bottom centre).
    Timer {
        id: wander
        running: root.active && root.visible && !root.flying
        interval: 2500
        repeat: true
        onTriggered: {
            if (root.mood === "listening") {
                interval = 6000 + Math.random() * 4000;
                if (Math.random() < 0.5) root.travel(root.pickSpot(true), 900, 0.15, false);
                return;
            }
            interval = 2000 + Math.random() * 4000;
            if (root.mood === "speaking") return;
            root.travel(root.pickSpot(false), 1100 + Math.random() * 600, 0.3, false);
        }
    }
    onMoodChanged: {
        if (!root.active) return;
        if (root.mood === "speaking") {
            const target = Qt.point(root.width / 2 - root.mw / 2 + (Math.random() - 0.5) * 160, root.height * 0.68);
            root.travel(target, 900, 0.2, false);
        }
    }
    onActiveChanged: if (active && actor.x === 0 && actor.y === 0) root.placeStart()
    Component.onCompleted: root.placeStart()
    onWidthChanged: if (actor.x === 0 && actor.y === 0) root.placeStart()
    function placeStart() {
        if (root.width <= 0) return;
        actor.x = root.width - root.mw - root.margin * 2;
        actor.y = root.margin + 60;
        root.from = Qt.point(actor.x, actor.y);
        root.to = root.from;
    }

    // ── The mascot ──
    Item {
        id: actor
        width: root.mw
        height: root.mh

        Mascot {
            id: mascot
            scale: root.zoom
            transformOrigin: Item.TopLeft
            visible: root.visible
            mood: root.mood
            level: root.level
            talking: root.talking
            // Eyes on where it goes; on the user (straight) when listening.
            lookX: root.flying ? Math.max(-1, Math.min(1, (root.to.x - root.from.x) / 200)) : (root.mood === "listening" ? 0 : root.restLook)
            lookY: root.mood === "thinking" ? -1 : root.flying ? -0.3 : 0.2
            // Stretched along the flight.
            stretchX: root.flying ? 0.92 : 1
            stretchY: root.flying ? 1.08 : 1
            Behavior on stretchX { enabled: !landing.running; NumberAnimation { duration: 140 } }
            Behavior on stretchY { enabled: !landing.running; NumberAnimation { duration: 140 } }
        }
    }

    // A sparkle trail where a dash leaves from.
    Item {
        id: trailDots
        anchors.fill: parent
        function drop() {
            for (let i = 0; i < trailRep.count; i++) trailRep.itemAt(i).go(i);
        }
        Repeater {
            id: trailRep
            model: 6
            delegate: Text {
                id: spark
                required property int index
                text: index % 2 === 0 ? "✦" : "✧"
                font.pixelSize: 12 + (index % 3) * 5
                color: ["#ffd25c", "#5cd6ff", "#ff8fab"][index % 3]
                style: Text.Outline
                styleColor: Qt.alpha("black", 0.3)
                opacity: 0
                function go(i) {
                    // Along the path just flown, as it flies.
                    sparkTimer.interval = 40 + i * 45;
                    sparkTimer.restart();
                }
                Timer {
                    id: sparkTimer
                    onTriggered: {
                        spark.x = actor.x + root.mw / 2 - spark.width / 2 + (Math.random() - 0.5) * 30;
                        spark.y = actor.y + root.mh / 2 + (Math.random() - 0.5) * 30;
                        sparkFade.restart();
                    }
                }
                SequentialAnimation {
                    id: sparkFade
                    NumberAnimation { target: spark; property: "opacity"; to: 1; duration: 60 }
                    ParallelAnimation {
                        NumberAnimation { target: spark; property: "opacity"; to: 0; duration: 520 }
                        NumberAnimation { target: spark; property: "scale"; from: 1.2; to: 0.3; duration: 520 }
                        NumberAnimation { target: spark; property: "y"; to: spark.y + 18; duration: 520 }
                    }
                }
            }
        }
    }

    // ── The balloon: beside it, flipped at the edges, on screen ──
    Rectangle {
        id: balloon
        readonly property bool onLeft: actor.x + root.mw + 16 + width > root.width - 8
        readonly property real maxW: 360
        visible: opacity > 0
        opacity: root.line.length > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        width: Math.min(maxW, Math.max(balloonText.implicitWidth, root.yesNo ? choices.implicitWidth : 0) + 28)
        height: balloonText.implicitHeight + 20 + (root.yesNo ? choices.implicitHeight + 8 : 0)
        radius: root.thinking ? height / 2 : 16
        color: root.lineKind === "heard" ? Qt.alpha(Appearance.m3colors.m3secondaryContainer, 0.95)
            : root.thinking ? Qt.alpha(Appearance.m3colors.m3surfaceContainer, 0.88)
            : Qt.alpha(Appearance.m3colors.m3surfaceContainerHigh, 0.97)
        border.width: root.thinking ? 1 : root.lineKind === "ask" ? 3 : 2
        border.color: root.thinking ? Qt.alpha(mascot.outline, 0.45)
            : root.lineKind === "ask" ? Appearance.colors.colPrimary : mascot.outline
        Behavior on color { ColorAnimation { duration: 160 } }
        x: Math.max(8, Math.min(root.width - width - 8, onLeft ? actor.x - width - 14 : actor.x + root.mw + 14))
        y: Math.max(8, Math.min(root.height - height - 8, actor.y + 10))
        transformOrigin: onLeft ? Item.Right : Item.Left
        // A thought: little circles trailing to the mascot, no tail.
        Repeater {
            model: root.thinking ? 2 : 0
            delegate: Rectangle {
                required property int index
                width: index === 0 ? 10 : 6
                height: width
                radius: width / 2
                color: balloon.color
                border.width: 1
                border.color: balloon.border.color
                y: balloon.height - 6 + index * 8
                x: balloon.onLeft ? balloon.width - 6 + index * 9 : -4 - index * 9 - width / 2
            }
        }
        // The tail, towards the mascot (speech only).
        Rectangle {
            visible: !root.thinking
            width: 14
            height: 14
            rotation: 45
            color: balloon.color
            border.width: 2
            border.color: balloon.border.color
            y: 18
            x: balloon.onLeft ? parent.width - 8 : -6
            z: -1
        }
        StyledText {
            id: balloonText
            x: 14
            y: 10
            width: Math.min(balloon.maxW - 28, implicitWidth)
            text: root.line
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
            font.pixelSize: root.lineKind === "say" ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small
            font.italic: root.lineKind !== "say"
            color: root.lineKind === "heard" ? Appearance.m3colors.m3onSecondaryContainer
                : root.thinking ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.72) : Appearance.m3colors.m3onSurface
            // A pop when a new kind of line appears, not at every sentence
            // revealed as it is said.
            property string lastKind: ""
            onTextChanged: {
                if (balloonText.text.length > 0 && balloonText.lastKind !== root.lineKind) pop.restart();
                balloonText.lastKind = balloonText.text.length > 0 ? root.lineKind : "";
            }
        }
        Row {
            id: choices
            visible: root.yesNo
            spacing: 8
            x: 14
            y: balloonText.y + balloonText.height + 8
            Repeater {
                model: [true, false]
                delegate: Rectangle {
                    id: chip
                    required property bool modelData
                    width: chipText.implicitWidth + 24
                    height: chipText.implicitHeight + 10
                    radius: height / 2
                    color: chipMouse.containsMouse ? Appearance.colors.colPrimaryHover
                        : chip.modelData ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData ? Translation.tr("Yes") : Translation.tr("No")
                        color: chip.modelData ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chose(chip.modelData)
                    }
                }
            }
        }
        SequentialAnimation {
            id: pop
            NumberAnimation { target: balloon; property: "scale"; from: 0.82; to: 1.04; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: balloon; property: "scale"; to: 1; duration: 120; easing.type: Easing.InOutQuad }
        }
    }

    // ── The hint, at the bottom ──
    Rectangle {
        visible: root.hint.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: hintText.implicitWidth + 28
        height: hintText.implicitHeight + 12
        radius: height / 2
        color: Qt.alpha("black", 0.55)
        border.width: 1
        border.color: Qt.alpha(mascot.accent, 0.8)
        StyledText {
            id: hintText
            anchors.centerIn: parent
            text: root.hint
            font.pixelSize: Appearance.font.pixelSize.small
            color: "white"
        }
    }
}
