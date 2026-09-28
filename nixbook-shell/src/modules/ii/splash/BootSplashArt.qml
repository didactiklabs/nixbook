import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * What the loading screen draws: background, Persona art, title, progress
 * bar and stage text. Shared by BootSplash (inside the shell) and
 * earlySplash.qml (its own small Quickshell instance, up before the shell has
 * loaded), so the handover between the two is invisible.
 *
 * progress < 0: indeterminate (a segment sweeping along the bar).
 */
Item {
    id: root

    property real progress: -1
    property string stageText: ""
    // Screen size, for the texture bucket (known before the layout is).
    property real screenWidth: 16
    property real screenHeight: 9

    readonly property bool indeterminate: root.progress < 0
    onIndeterminateChanged: if (!root.indeterminate) fill.x = 0

    Rectangle {
        anchors.fill: parent
        color: Persona.shapes ? Persona.frameColor : Appearance.m3colors.m3background
    }
    // The art *is* the splash: decoded synchronously (a 1200×800
    // PNG, a few ms; the other screens hit the pixmap cache) with
    // the bucket picked from the screen size, so it is there in the
    // very first frame. PersonaTexture waits for its layout size and
    // decodes asynchronously, which showed the bare background and
    // text for a moment at startup.
    Image {
        anchors.fill: parent
        visible: Persona.halftone
        source: visible ? Persona.textureUrl(Persona.textureShapeFor(root.screenWidth, root.screenHeight)) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: true
        smooth: true
        opacity: 0.6
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width * 0.5, 520)
        spacing: 18

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
                border.color: Persona.frameBorderColor
                clip: true
                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, Persona.shapes ? -0.4 : 0, 0, Persona.shapes ? 0.4 * 7 : 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                Rectangle {
                    id: fill
                    anchors { top: parent.top; bottom: parent.bottom }
                    // Indeterminate: a fixed segment swept by the animation below.
                    x: 0
                    width: root.indeterminate ? parent.width * 0.3 : parent.width * Math.max(0.04, root.progress)
                    radius: track.radius
                    color: Persona.shapes ? Persona.stripeColor : Appearance.colors.colPrimary
                    Behavior on width {
                        enabled: !root.indeterminate
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    SequentialAnimation on x {
                        running: root.indeterminate && root.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: -track.width * 0.3
                            to: track.width
                            duration: 1100
                            easing.type: Easing.InOutQuad
                        }
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
