import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * What the loading screen draws: background, Persona art (or the Chiikawa
 * character, the Ghibli spirit), title, progress
 * bar and stage text. Shared by BootSplash (inside the shell) and
 * earlySplash.qml (its own small Quickshell instance, up before the shell has
 * loaded), so the handover between the two is invisible.
 *
 * progress < 0: indeterminate (a segment sweeping along the bar). The sweep
 * follows the wall clock, not an animation started with the window, so the
 * two instances draw the very same bar at the same moment; when progress
 * starts, the segment glides into the fill.
 */
Item {
    id: root

    property real progress: -1
    property string stageText: ""
    // Screen size, for the texture bucket (known before the layout is).
    property real screenWidth: 16
    property real screenHeight: 9

    readonly property bool indeterminate: root.progress < 0

    // Sweep position 0..1 from the wall clock (eased in and out).
    readonly property int sweepMs: 1100
    property real sweep: 0
    function updateSweep() {
        const t = (Date.now() % root.sweepMs) / root.sweepMs;
        root.sweep = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
    }
    FrameAnimation {
        running: root.indeterminate && root.visible
        onTriggered: root.updateSweep()
    }
    Component.onCompleted: root.updateSweep()

    // 0 → 1: from where the sweep stopped to the progress fill.
    property real glide: root.indeterminate ? 0 : 1
    onIndeterminateChanged: if (!root.indeterminate) glideAnim.restart()
    NumberAnimation {
        id: glideAnim
        target: root
        property: "glide"
        from: 0
        to: 1
        duration: 280
        easing.type: Easing.OutCubic
    }

    Rectangle {
        anchors.fill: parent
        color: Persona.shapes ? Persona.frameColor : Appearance.m3colors.m3background
    }
    // The art *is* the splash: decoded synchronously (a 1200×800
    // PNG, a few ms per screen) with the bucket picked from the
    // screen size, so it is there in the very first frame.
    // PersonaTexture waits for its layout size and decodes
    // asynchronously, which showed the bare background and text for
    // a moment at startup. Not from the pixmap cache: Persona's
    // preloader starts async loads of these very urls when the
    // config is read, just before BootSplash is created, and a
    // cached request joins a pending load (QQuickPixmap::load) —
    // asynchronous: false or not.
    Image {
        anchors.fill: parent
        visible: Persona.halftone
        source: visible ? Persona.textureUrl(Persona.textureShapeFor(root.screenWidth, root.screenHeight)) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        smooth: true
        opacity: 0.6
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width * 0.5, 520)
        spacing: 18

        // Chiikawa theme: the three friends, decoded synchronously like the
        // Persona art (there in the first frame).
        ChiikawaMascot {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 400
            Layout.preferredHeight: 400 / Chiikawa.friendsAspect
            friends: true
            asynchronous: false
            hopOnHover: false
        }
        // Ghibli theme: the variant's spirit, swaying.
        GhibliSpirit {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200
            asynchronous: false
            wobbleOnHover: false
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Persona.fonts ? "NOW LOADING" : Translation.tr("Getting things ready")
            font.family: Persona.fonts ? Persona.titleFont : Appearance.font.family.title
            font.pixelSize: Persona.fonts ? 64 : Appearance.font.pixelSize.title
            font.weight: Font.Bold
            font.italic: Persona.shapes
            color: Persona.shapes ? Persona.spec.ink : Appearance.colors.colOnLayer0
            style: Persona.shapes ? Text.Outline : Text.Normal
            styleColor: Persona.shadowColor
        }

        // Progress: a slanted accent bar in the Persona style, a
        // rounded Material one otherwise.
        Item {
            Layout.fillWidth: true
            implicitHeight: 14
            Rectangle {
                visible: Persona.shapes
                x: Persona.shadowOffset
                y: Persona.shadowOffset
                width: parent.width
                height: parent.height
                color: Persona.shadowColor
                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.4, 0, 0.4 * 7, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
            }
            Rectangle {
                id: track
                anchors.fill: parent
                radius: Persona.shapes ? 0 : height / 2
                color: Persona.shapes ? Persona.spec.frame : Appearance.colors.colSecondaryContainer
                border.width: Persona.shapes ? 2 : 0
                border.color: Persona.outlineColor
                clip: true
                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, Persona.shapes ? -0.4 : 0, 0, Persona.shapes ? 0.4 * 7 : 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                Rectangle {
                    id: fill
                    anchors { top: parent.top; bottom: parent.bottom }
                    // Indeterminate: a segment swept across by the clock;
                    // then it glides (root.glide) into the fill, which grows
                    // from the left.
                    readonly property real sweepX: -parent.width * 0.3 + root.sweep * parent.width * 1.3
                    readonly property real sweepWidth: parent.width * 0.3
                    readonly property real fillWidth: parent.width * Math.max(0.04, root.progress)
                    x: fill.sweepX * (1 - root.glide)
                    width: fill.sweepWidth + (fill.fillWidth - fill.sweepWidth) * root.glide
                    radius: track.radius
                    color: Persona.shapes ? Persona.stripeColor : Appearance.colors.colPrimary
                    Behavior on width {
                        enabled: root.glide === 1
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.stageText
            font.family: Persona.fonts ? Persona.titleFont : Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Persona.shapes ? Persona.spec.ink : Appearance.colors.colSubtext
            opacity: 0.8
        }
    }
}
