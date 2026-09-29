pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// NixOS update indicator — left click toggles an action panel (status line,
// Check / Execute / Logs, changelog, live log tail), right click re-checks.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3

    property bool panelOpen: false

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true

    readonly property bool busy: UpdateState.checking || UpdateState.updating
    readonly property bool cursorNear: containsMouse || updatePopup.hovered

    // One shared rotation angle: every icon variant binds `rotation` to it,
    // so stopping the check always snaps them back upright (a per-icon
    // RotationAnimation would freeze at its last angle).
    property real spin: 0
    onBusyChanged: {
        if (!busy) spin = 0
    }

    NumberAnimation on spin {
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
        running: root.busy
    }

    // Leaving closes the panel after a generous grace period, so a cursor
    // overshooting the panel or crossing the bar doesn't lose it.
    // When the panel resizes (a check finished: Execute + changelog appear),
    // the compositor can report a leave without the cursor moving; so after
    // a resize, auto-close waits until the cursor is seen over it again
    // (a click elsewhere still closes it through the focus grab).
    property bool closeArmed: true

    onCursorNearChanged: {
        if (cursorNear) {
            closeArmed = true
            closeTimer.stop()
        } else if (panelOpen && closeArmed) {
            closeTimer.restart()
        }
    }

    onPanelOpenChanged: if (panelOpen) closeArmed = true

    function contentResized() {
        if (!root.panelOpen) return
        root.closeArmed = false
        closeTimer.stop()
        settleTimer.restart()
    }

    // Once the resize has settled, a cursor still over the panel re-arms it.
    Timer {
        id: settleTimer
        interval: 400
        onTriggered: if (root.cursorNear) root.closeArmed = true
    }

    Timer {
        id: closeTimer
        interval: 1200
        onTriggered: {
            if (!root.cursorNear && root.closeArmed) root.panelOpen = false
        }
    }

    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            root.panelOpen = !root.panelOpen
        }
    }

    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            UpdateState.checkUpdate()
            Quickshell.execDetached([
                "notify-send",
                Translation.tr("Updates"),
                Translation.tr("Checking for updates..."),
                "-a", "Shell"
            ])
            mouse.accepted = false
        }
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: 4

            // Default
            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignVCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                rotation: root.spin
            }

            // Material
            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                    rotation: root.spin
                }
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 4

            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignHCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                rotation: root.spin
            }

            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: UpdateState.updateAvailable ? Appearance.m3colors.m3error
                    : Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignHCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                    rotation: root.spin
                }
            }
        }
    }

    // Hover tooltip: a quick status summary, hidden while the panel is open.
    StyledPopup {
        hoverTarget: root
        active: !root.panelOpen && root.containsMouse && Config.options.bar.tooltips.enable

        ColumnLayout {
            spacing: 4

            StyledPopupHeaderRow {
                icon: "deployed_code_update"
                label: Translation.tr("System updates")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: UpdateState.updating || UpdateState.checking ? "sync"
                    : UpdateState.updateAvailable ? "upgrade" : "check_circle"
                label: Translation.tr("Status")
                value: UpdateState.updating ? Translation.tr("Updating...")
                    : UpdateState.checking ? Translation.tr("Checking...")
                    : UpdateState.updateAvailable ? Translation.tr("Update available")
                    : Translation.tr("Up to date")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "commit"
                label: Translation.tr("Deployed")
                value: root.shortRev(UpdateState.localRev)
                    + (UpdateState.localBranch !== "Unknown" ? " (" + UpdateState.localBranch + ")" : "")
                    + (UpdateState.localDirty ? " — " + Translation.tr("dirty") : "")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: UpdateState.updateAvailable
                icon: "cloud_download"
                label: Translation.tr("Latest")
                value: root.shortRev(UpdateState.remoteRev)
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: UpdateState.lastResult !== ""
                icon: UpdateState.lastResult === "failed" ? "error" : "check_circle"
                label: Translation.tr("Last update")
                value: (UpdateState.lastResult === "failed" ? Translation.tr("Failed") : Translation.tr("Succeeded"))
                    + (UpdateState.lastRunTime !== "" ? " — " + UpdateState.lastRunTime : "")
            }

            StyledText {
                text: Translation.tr("Click to manage · right click to check")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledPopup {
        id: updatePopup
        hoverTarget: root
        hoverMargin: 10
        active: root.panelOpen

        ColumnLayout {
            id: panelContent
            spacing: 10

            onImplicitWidthChanged: root.contentResized()
            onImplicitHeightChanged: root.contentResized()

            // Panel width (a ColumnLayout recomputes its own implicitWidth,
            // so a zero-height row sets it): wider while a log is shown.
            Item {
                Layout.minimumWidth: (UpdateState.viewingLogs || failureCard.visible) ? 600 : 420
                implicitHeight: 0
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: UpdateState.updateAvailable && !UpdateState.checking && !UpdateState.updating
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
                text: UpdateState.updating ? Translation.tr("Updating system...")
                    : UpdateState.checking ? Translation.tr("Checking for updates...")
                    : UpdateState.updateAvailable
                        ? Translation.tr("Update available: %1 \u2192 %2").arg(root.shortRev(UpdateState.localRev)).arg(root.shortRev(UpdateState.remoteRev))
                        : Translation.tr("System up to date (%1)").arg(root.shortRev(UpdateState.localRev))
            }

            StyledText {
                Layout.fillWidth: true
                visible: UpdateState.localDirty
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Deployed from a local tree with uncommitted changes.")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "sync"
                    mainText: UpdateState.checking ? Translation.tr("Checking...") : Translation.tr("Check")
                    enabled: !UpdateState.checking && !UpdateState.updating
                    onClicked: UpdateState.checkUpdate()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    visible: UpdateState.updateAvailable || UpdateState.updating
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "deployed_code_update"
                    mainText: UpdateState.updating ? Translation.tr("Updating...") : Translation.tr("Execute")
                    enabled: !UpdateState.updating
                    onClicked: UpdateState.startUpdate()
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "terminal"
                    mainText: UpdateState.viewingLogs ? Translation.tr("Stop Logs") : Translation.tr("Logs")
                    onClicked: {
                        if (UpdateState.viewingLogs) {
                            UpdateState.stopLogs()
                        } else {
                            UpdateState.startLogs()
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: UpdateState.changelogText !== ""
                text: Translation.tr("Changelog")
                color: Appearance.colors.colOnLayer2
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                visible: UpdateState.changelogText !== ""
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                Flickable {
                    id: changelogFlickable
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: changelogLabel.paintedHeight
                    clip: true

                    StyledText {
                        id: changelogLabel
                        width: parent.width
                        text: UpdateState.changelogText
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.Wrap
                    }
                }
            }

            // The last run failed: its log, selectable, with a copy button.
            LogView {
                id: failureCard
                visible: UpdateState.lastResult === "failed" && !UpdateState.updating && !UpdateState.viewingLogs
                title: UpdateState.lastRunTime !== ""
                    ? Translation.tr("Last update failed (%1)").arg(UpdateState.lastRunTime)
                    : Translation.tr("Last update failed")
                titleColor: Appearance.m3colors.m3error
                log: UpdateState.lastRunLog
            }

            LogView {
                visible: UpdateState.viewingLogs
                title: Translation.tr("Live log")
                log: UpdateState.logText
                placeholder: Translation.tr("Waiting for logs...")
            }
        }
    }

    function shortRev(rev) {
        return rev === "Unknown" ? Translation.tr("unknown") : rev.slice(0, 7)
    }

    // Selectable log text (drag to select) + Copy (the selection, else all).
    component LogView: ColumnLayout {
        id: logView
        property string title
        property color titleColor: Appearance.colors.colOnLayer2
        property string log
        property string placeholder: ""
        Layout.fillWidth: true
        spacing: 6

        // Show the end (where the error is), unless text is being selected.
        function toEnd() {
            if (logArea.selectedText !== "") return
            const f = logScroll.contentItem
            f.contentY = Math.max(0, f.contentHeight - f.height)
        }
        onVisibleChanged: if (visible) Qt.callLater(toEnd)

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: logView.title
                color: logView.titleColor
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.normal
                materialIcon: "content_copy"
                mainText: logArea.selectedText !== "" ? Translation.tr("Copy selection") : Translation.tr("Copy log")
                enabled: logView.log !== ""
                onClicked: {
                    Quickshell.clipboardText = logArea.selectedText !== "" ? logArea.selectedText : logView.log
                    Quickshell.execDetached(["notify-send", Translation.tr("Updates"), Translation.tr("Log copied to the clipboard"), "-a", "Shell"])
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 280
            clip: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            ScrollView {
                id: logScroll
                anchors.fill: parent
                anchors.margins: 4
                StyledTextArea {
                    id: logArea
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    background: null
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: logView.log
                    placeholderText: logView.placeholder
                    onImplicitHeightChanged: Qt.callLater(logView.toEnd)
                }
            }
        }
    }
}
