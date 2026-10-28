pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Shapes

/**
 * The Full AI mode's mascot: a small round robot, the MC of the desktop
 * while the AI has the controls. Pure QML (no image): a soft blob body in
 * the theme's accent, big eyes that look where it goes and blink, cheeks,
 * a mouth that talks, an antenna whose glow says its mood, two little arms.
 *   mood: idle | listening | thinking | acting | speaking | happy | sad | muted
 *   level: the microphone's level (0..1), while listening
 *   talking: its mouth moves (the voice reading an answer)
 *   lookX / lookY: where it looks (-1..1)
 *   stretchX / stretchY: squash & stretch, set by the stage while it moves
 * hop(), celebrate() (a jump, a spin, stars), shake().
 * Nothing animates while it is hidden (`running`).
 */
Item {
    id: root
    implicitWidth: 120
    implicitHeight: 140
    width: implicitWidth
    height: implicitHeight

    property string mood: "idle"
    property real level: 0
    property bool talking: false
    property real lookX: 0
    property real lookY: 0
    property real stretchX: 1
    property real stretchY: 1
    readonly property bool running: root.visible && root.opacity > 0

    // ── Colours: the theme's accent (Chiikawa: its pale body and line) ──
    readonly property bool cute: Chiikawa.enabled
    readonly property color accent: Chiikawa.enabled ? (Chiikawa.spec.accent ?? "#f29bb2")
        : Cyberpunk.enabled ? Cyberpunk.accent
        : Persona.enabled ? Persona.stripeColor
        : Ghibli.enabled ? Ghibli.accent
        : Appearance.colors.colPrimary
    readonly property color bodyTop: root.cute ? (Chiikawa.spec.background ?? "#fff6f8") : Qt.lighter(root.accent, 1.45)
    readonly property color bodyBottom: root.cute ? Qt.lighter(root.accent, 1.35) : root.accent
    readonly property color outline: root.cute ? (Chiikawa.spec.line ?? "#7a5560") : Qt.darker(root.accent, 2.2)
    readonly property color ink: "#2a2230"
    readonly property color tipColor: ({
        idle: Qt.lighter(root.accent, 1.3), listening: "#ff5c7a", thinking: "#ffd25c", acting: "#5cd6ff",
        speaking: "#7cf29a", happy: "#ffd25c", sad: "#8aa0c8", muted: "#9a9a9a"
    })[root.mood] ?? root.accent

    // ── One-shots ──
    function hop() {
        if (!root.running) return;
        hopAnim.restart();
    }
    function celebrate() {
        if (!root.running) return;
        celebrateAnim.restart();
        stars.burst();
    }
    function shake() {
        if (!root.running) return;
        shakeAnim.restart();
    }

    // ── Alive: bob, breath, tilt, blink ──
    property real bob: 0
    property real breath: 1
    property real tilt: 0
    property real jump: 0
    property real spin: 0
    property real shakeX: 0
    property real eyeOpen: 1
    property real mouthOpen: 0

    readonly property real bobSpeed: root.mood === "acting" ? 0.55 : root.mood === "listening" ? 1.6 : 1
    SequentialAnimation on bob {
        running: root.running
        loops: Animation.Infinite
        NumberAnimation { to: -5; duration: 700 * root.bobSpeed; easing.type: Easing.InOutSine }
        NumberAnimation { to: 2; duration: 700 * root.bobSpeed; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on breath {
        running: root.running
        loops: Animation.Infinite
        NumberAnimation { to: 1.035; duration: 1500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.985; duration: 1500; easing.type: Easing.InOutSine }
    }
    // An occasional head tilt (and the listening one, held).
    Timer {
        running: root.running && root.mood !== "listening"
        interval: 3200 + Math.random() * 2500
        repeat: true
        onTriggered: {
            interval = 3200 + Math.random() * 2500;
            tiltAnim.to = (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 5);
            tiltAnim.restart();
        }
    }
    SequentialAnimation {
        id: tiltAnim
        property real to: 6
        NumberAnimation { target: root; property: "tilt"; to: tiltAnim.to; duration: 380; easing.type: Easing.OutBack }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: root; property: "tilt"; to: 0; duration: 420; easing.type: Easing.InOutSine }
    }
    Binding {
        target: root
        property: "tilt"
        value: 7
        when: root.mood === "listening"
        restoreMode: Binding.RestoreBindingOrValue
    }
    // Blink every 2.5–5 s (twice, now and then); half-closed when muted.
    Timer {
        running: root.running && root.mood !== "happy"
        interval: 2500 + Math.random() * 2500
        repeat: true
        onTriggered: {
            interval = 2500 + Math.random() * 2500;
            blinkAnim.loops = Math.random() < 0.2 ? 2 : 1;
            blinkAnim.restart();
        }
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: root; property: "eyeOpen"; to: 0.08; duration: 70 }
        NumberAnimation { target: root; property: "eyeOpen"; to: 1; duration: 110 }
    }
    // Talking: the mouth opens and closes, a little irregular.
    SequentialAnimation on mouthOpen {
        running: root.running && root.talking
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 110 }
        NumberAnimation { to: 0.3; duration: 90 }
        NumberAnimation { to: 0.8; duration: 130 }
        NumberAnimation { to: 0.1; duration: 120 }
    }
    onTalkingChanged: if (!talking) mouthOpen = 0

    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: root; property: "jump"; to: -16; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "jump"; to: 0; duration: 220; easing.type: Easing.OutBounce }
    }
    SequentialAnimation {
        id: celebrateAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "jump"; to: -34; duration: 260; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "spin"; from: 0; to: 360; duration: 520; easing.type: Easing.InOutCubic }
        }
        NumberAnimation { target: root; property: "jump"; to: 0; duration: 320; easing.type: Easing.OutBounce }
        ScriptAction { script: root.spin = 0 }
    }
    SequentialAnimation {
        id: shakeAnim
        loops: 1
        NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 6; duration: 80 }
        NumberAnimation { target: root; property: "shakeX"; to: -4; duration: 80 }
        NumberAnimation { target: root; property: "shakeX"; to: 3; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 60 }
    }
    // Happy: a little hop now and then while the mood lasts.
    Timer {
        running: root.running && root.mood === "happy"
        interval: 1100
        repeat: true
        onTriggered: root.hop()
    }
    // Sad: a slow sigh-shake once in a while.
    Timer {
        running: root.running && root.mood === "sad"
        interval: 2600
        repeat: true
        onTriggered: root.shake()
    }

    // ── Shadow on the ground (shrinks as it rises) ──
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 126
        width: 68 * (1 - Math.min(0.5, (-root.bob - root.jump) / 70))
        height: 10
        radius: 5
        color: Qt.rgba(0, 0, 0, 0.28 * (1 - Math.min(0.6, (-root.bob - root.jump) / 60)))
    }

    // ── The robot ──
    Item {
        id: rig
        width: 120
        height: 124
        y: 0
        transform: [
            Scale {
                origin.x: 60
                origin.y: 122
                xScale: root.stretchX * (2 - root.breath)
                yScale: root.stretchY * root.breath
            },
            Rotation {
                origin.x: 60
                origin.y: 70
                angle: root.tilt + root.spin
            },
            Translate {
                x: root.shakeX
                y: root.bob + root.jump
            }
        ]

        // Antenna: a stalk and a glowing tip.
        Rectangle {
            x: 58.5
            y: 4
            width: 3
            height: 18
            radius: 1.5
            color: root.outline
            rotation: root.mood === "thinking" ? antennaSwing.angle : root.mood === "listening" ? -6 + 12 * root.level : 0
            transformOrigin: Item.Bottom
            QtObject {
                id: antennaSwing
                property real angle: 0
            }
            SequentialAnimation {
                running: root.running && root.mood === "thinking"
                loops: Animation.Infinite
                NumberAnimation { target: antennaSwing; property: "angle"; to: -14; duration: 260; easing.type: Easing.InOutSine }
                NumberAnimation { target: antennaSwing; property: "angle"; to: 14; duration: 260; easing.type: Easing.InOutSine }
            }
            // The glow and the tip, on the stalk's end.
            Rectangle {
                id: glow
                anchors.horizontalCenter: parent.horizontalCenter
                y: -9 - (width - 10) / 2
                readonly property real pulse: root.mood === "listening" ? 0.5 + root.level * 1.4 : 1
                width: 24 * glow.pulse * glowBeat.v
                height: width
                radius: width / 2
                color: Qt.alpha(root.tipColor, 0.32)
                QtObject {
                    id: glowBeat
                    property real v: 1
                }
                SequentialAnimation {
                    running: root.running
                    loops: Animation.Infinite
                    NumberAnimation { target: glowBeat; property: "v"; to: root.mood === "acting" ? 1.25 : 1.12; duration: root.mood === "acting" ? 260 : 700; easing.type: Easing.InOutSine }
                    NumberAnimation { target: glowBeat; property: "v"; to: 0.85; duration: root.mood === "acting" ? 260 : 700; easing.type: Easing.InOutSine }
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: -9
                width: 11
                height: 11
                radius: 5.5
                color: root.tipColor
                border.width: 1.5
                border.color: root.outline
                Rectangle {
                    x: 2.5
                    y: 2
                    width: 3.5
                    height: 3.5
                    radius: 1.75
                    color: "white"
                    opacity: 0.85
                }
            }
        }

        // Arms (behind the body): a little wave or point by mood.
        Rectangle {
            id: leftArm
            x: 2
            y: 64
            width: 18
            height: 34
            radius: 9
            color: root.bodyBottom
            border.width: 2
            border.color: root.outline
            transformOrigin: Item.Top
            rotation: root.mood === "speaking" ? armWave.left : root.mood === "happy" ? 150 : root.mood === "sad" ? 8 : 25
            Behavior on rotation { enabled: root.mood !== "speaking"; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
        }
        Rectangle {
            id: rightArm
            x: 100
            y: 64
            width: 18
            height: 34
            radius: 9
            color: root.bodyBottom
            border.width: 2
            border.color: root.outline
            transformOrigin: Item.Top
            rotation: root.mood === "acting" ? -100 : root.mood === "speaking" ? armWave.right : root.mood === "happy" ? -150
                : root.mood === "sad" ? -8 : root.mood === "listening" ? -35 : -25
            Behavior on rotation { enabled: root.mood !== "speaking"; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
        }
        QtObject {
            id: armWave
            property real left: 30
            property real right: -30
        }
        SequentialAnimation {
            running: root.running && root.mood === "speaking"
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: armWave; property: "left"; to: 70; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { target: armWave; property: "right"; to: -20; duration: 420; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
                NumberAnimation { target: armWave; property: "left"; to: 20; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { target: armWave; property: "right"; to: -75; duration: 420; easing.type: Easing.InOutSine }
            }
        }

        // The body: a soft blob, lit from above.
        Rectangle {
            id: body
            x: 10
            y: 22
            width: 100
            height: 96
            radius: 46
            border.width: 2.5
            border.color: root.outline
            gradient: Gradient {
                GradientStop { position: 0; color: root.bodyTop }
                GradientStop { position: 1; color: root.bodyBottom }
            }
            // A sheen on the top left.
            Rectangle {
                x: 18
                y: 10
                width: 26
                height: 12
                radius: 6
                rotation: -20
                color: "white"
                opacity: 0.45
            }
            // The face plate.
            Rectangle {
                x: 12
                y: 22
                width: 76
                height: 54
                radius: 26
                color: root.cute ? "white" : Qt.alpha("white", 0.9)
                border.width: 1.5
                border.color: Qt.alpha(root.outline, 0.5)

                // Eyes.
                Repeater {
                    model: 2
                    delegate: Item {
                        id: eye
                        required property int index
                        readonly property bool isLeft: index === 0
                        x: isLeft ? 12 : 42
                        y: 8
                        width: 22
                        height: 26

                        // Open eye: white, pupil looking, a highlight.
                        Item {
                            anchors.fill: parent
                            visible: root.mood !== "happy"
                            Rectangle {
                                anchors.centerIn: parent
                                width: 20
                                height: 24 * Math.max(0.08, root.eyeOpen * (root.mood === "muted" ? 0.45 : root.mood === "listening" ? 1.08 : 1))
                                radius: 10
                                color: root.ink
                                clip: true
                                Rectangle {
                                    id: pupilShine
                                    x: 10 + root.lookX * 3 - 3
                                    y: parent.height * 0.18 + root.lookY * 2
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "white"
                                }
                                Rectangle {
                                    x: 4 + root.lookX * 3
                                    y: parent.height * 0.6
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: "white"
                                    opacity: 0.8
                                }
                                transform: Translate {
                                    x: root.lookX * 2.5
                                    y: (root.mood === "thinking" ? -3 : 0) + root.lookY * 2
                                }
                            }
                            // Brows: determined (acting), droopy (sad).
                            Rectangle {
                                visible: root.mood === "acting" || root.mood === "sad"
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: -5
                                width: 16
                                height: 3
                                radius: 1.5
                                color: root.ink
                                rotation: root.mood === "acting" ? (eye.isLeft ? 18 : -18) : (eye.isLeft ? -18 : 18)
                            }
                        }
                        // Happy: ^ ^
                        Shape {
                            anchors.fill: parent
                            visible: root.mood === "happy"
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: root.ink
                                strokeWidth: 3.5
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                startX: 3; startY: 17
                                PathQuad { x: 19; y: 17; controlX: 11; controlY: 3 }
                            }
                        }
                    }
                }

                // Cheeks.
                Rectangle {
                    x: 4; y: 34; width: 14; height: 8; radius: 4
                    color: "#ff8fab"
                    opacity: root.mood === "happy" || root.cute ? 0.8 : 0.55
                }
                Rectangle {
                    x: 58; y: 34; width: 14; height: 8; radius: 4
                    color: "#ff8fab"
                    opacity: root.mood === "happy" || root.cute ? 0.8 : 0.55
                }

                // Mouth: open while talking, a smile, a frown when sad.
                Rectangle {
                    visible: root.talking || root.mood === "listening"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 38
                    width: root.talking ? 12 : 8
                    height: root.talking ? 3 + 9 * root.mouthOpen : 6
                    radius: width / 2
                    color: "#a8324e"
                    border.width: 1.5
                    border.color: root.ink
                }
                Shape {
                    visible: !root.talking && root.mood !== "listening"
                    x: 30
                    y: 36
                    width: 16
                    height: 10
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.ink
                        strokeWidth: 2.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 2; startY: root.mood === "sad" ? 8 : 2
                        PathQuad {
                            x: 14; y: root.mood === "sad" ? 8 : 2
                            controlX: 8; controlY: root.mood === "sad" ? 0 : (root.mood === "happy" ? 14 : 10)
                        }
                    }
                }
            }
        }

        // Thinking: three dots popping above its head.
        Row {
            visible: root.mood === "thinking"
            x: 78
            y: 2
            spacing: 3
            Repeater {
                model: 3
                delegate: Rectangle {
                    id: dot
                    required property int index
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "white"
                    border.width: 1.5
                    border.color: root.outline
                    opacity: 0.3
                    SequentialAnimation on opacity {
                        running: root.running && root.mood === "thinking"
                        loops: Animation.Infinite
                        PauseAnimation { duration: dot.index * 180 }
                        NumberAnimation { to: 1; duration: 240 }
                        NumberAnimation { to: 0.3; duration: 240 }
                        PauseAnimation { duration: (2 - dot.index) * 180 }
                    }
                }
            }
        }

        // Listening: little sound arcs at its "ears", with the level.
        Repeater {
            model: 2
            delegate: Shape {
                id: ear
                required property int index
                visible: root.mood === "listening"
                x: ear.index === 0 ? -6 : 110
                y: 46
                width: 16
                height: 28
                opacity: 0.35 + 0.65 * Math.min(1, root.level * 1.6)
                scale: 0.85 + 0.35 * root.level
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.tipColor
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: ear.index === 0 ? 12 : 4; startY: 2
                    PathQuad {
                        x: ear.index === 0 ? 12 : 4; y: 26
                        controlX: ear.index === 0 ? -4 : 20; controlY: 14
                    }
                }
            }
        }

        // Muted: a small "mic off" badge.
        Rectangle {
            visible: root.mood === "muted"
            x: 84
            y: 92
            width: 24
            height: 24
            radius: 12
            color: "#5a5a66"
            border.width: 2
            border.color: "white"
            MaterialSymbol {
                anchors.centerIn: parent
                text: "mic_off"
                iconSize: 15
                color: "white"
            }
        }
    }

    // Stars for celebrate(): a burst from its head.
    Item {
        id: stars
        anchors.fill: parent
        function burst() {
            for (let i = 0; i < starRepeater.count; i++) starRepeater.itemAt(i).fly();
        }
        Repeater {
            id: starRepeater
            model: 7
            delegate: Text {
                id: star
                required property int index
                readonly property real angle: -Math.PI / 2 + (star.index - 3) * 0.42
                text: "★"
                font.pixelSize: 14 + (star.index % 3) * 4
                color: ["#ffd25c", "#ff8fab", "#7cf29a", "#5cd6ff"][star.index % 4]
                style: Text.Outline
                styleColor: Qt.alpha("black", 0.35)
                x: 60 - width / 2
                y: 30
                opacity: 0
                function fly() { flyAnim.restart(); }
                ParallelAnimation {
                    id: flyAnim
                    NumberAnimation { target: star; property: "x"; from: 60 - star.width / 2; to: 60 - star.width / 2 + Math.cos(star.angle) * 70; duration: 700; easing.type: Easing.OutCubic }
                    NumberAnimation { target: star; property: "y"; from: 30; to: 30 + Math.sin(star.angle) * 60; duration: 700; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        NumberAnimation { target: star; property: "opacity"; to: 1; duration: 90 }
                        PauseAnimation { duration: 380 }
                        NumberAnimation { target: star; property: "opacity"; to: 0; duration: 230 }
                    }
                    NumberAnimation { target: star; property: "rotation"; from: 0; to: 180; duration: 700 }
                }
            }
        }
    }
}
