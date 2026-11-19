pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Anthropic (Claude) usage indicator — bar shows the % left in the 5-hour
// window; left click opens a panel with both windows' remaining % and reset
// times, plus any one-model weekly limit (e.g. Fable's). Data comes from the
// `anthropic-usage` script (Claude Code's or OpenCode's OAuth login).
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    property string status: "init"
    property int fiveHourUtil: -1
    property int sevenDayUtil: -1
    property string fiveHourReset: ""
    property string sevenDayReset: ""
    property real updatedAt: 0 // unix seconds of the data shown
    property real retryAt: 0 // unix seconds of the next try after a 429 (0: none)
    // One-model weekly limits: [{name, left, reset}], set once a read ends.
    property var scopedLimits: []
    property var _scoped: []
    readonly property bool refreshing: usageProc.running

    readonly property bool available: status === "ok" || status === "stale"
    readonly property int fiveHourLeft: fiveHourUtil >= 0 ? Math.max(0, 100 - fiveHourUtil) : -1
    readonly property int sevenDayLeft: sevenDayUtil >= 0 ? Math.max(0, 100 - sevenDayUtil) : -1
    readonly property bool low: available && fiveHourLeft >= 0 && fiveHourLeft <= 20

    property bool panelOpen: false
    readonly property bool cursorNear: containsMouse || panelHover.hovered

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true

    // Cached read (hover, timer) or forced fetch (click).
    // A click during a running (e.g. hover) read is queued, not dropped.
    property bool forcePending: false
    function refresh(force = false) {
        if (usageProc.running) {
            if (force) root.forcePending = true
            return
        }
        usageProc.command = force ? ["anthropic-usage", "--force"] : ["anthropic-usage"]
        usageProc.running = true
    }

    function fmtReset(iso: string): string {
        if (!iso) return "\u2014"
        const d = new Date(iso)
        if (isNaN(d.getTime())) return "\u2014"
        return Qt.formatDateTime(d, "HH:mm")
    }

    function fmtResetDay(iso: string): string {
        if (!iso) return "\u2014"
        const d = new Date(iso)
        if (isNaN(d.getTime())) return "\u2014"
        return Qt.formatDateTime(d, "ddd HH:mm")
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 120000
        repeat: true
        // Paused while the screens are off (Idle); refreshed when they're back.
        running: !Idle.screensOff
        onTriggered: root.refresh()
        onRunningChanged: if (running) root.refresh()
    }

    // Hover shows the details (short intent delay so sweeping across the bar
    // doesn't flash the panel); leaving closes it after a grace period.
    onCursorNearChanged: {
        if (cursorNear) {
            closeTimer.stop()
            if (!panelOpen) hoverOpenTimer.restart()
        } else {
            hoverOpenTimer.stop()
            if (panelOpen) closeTimer.start()
        }
    }

    Timer {
        id: hoverOpenTimer
        interval: 120
        onTriggered: {
            if (!root.cursorNear) return
            root.panelOpen = true
            root.refresh()
        }
    }

    Timer {
        id: closeTimer
        interval: 500
        onTriggered: {
            if (!root.cursorNear) root.panelOpen = false
        }
    }

    // Click (either button) fetches fresh numbers, bypassing the 120s cache.
    onClicked: (mouse) => {
        hoverOpenTimer.stop()
        root.panelOpen = true
        root.refresh(true)
    }

    Process {
        id: usageProc
        command: ["anthropic-usage"]
        running: false
        onExited: {
            root.scopedLimits = root._scoped
            if (root.forcePending) {
                root.forcePending = false
                Qt.callLater(() => root.refresh(true))
            }
        }
        stdout: SplitParser {
            onRead: line => {
                const eq = line.indexOf("=")
                if (eq < 0) return
                const key = line.slice(0, eq)
                const value = line.slice(eq + 1)
                if (key === "STATUS") {
                    root.status = value
                    root._scoped = []
                } else if (key === "SCOPED_LIMIT") {
                    const parts = value.split("\t")
                    const used = parseInt(parts[1])
                    if (parts.length >= 2 && !isNaN(used))
                        root._scoped.push({ name: parts[0], left: Math.max(0, 100 - used), reset: parts[2] ?? "" })
                } else if (key === "RETRY_AT") {
                    const n = parseInt(value)
                    root.retryAt = isNaN(n) ? 0 : n
                } else if (key === "FIVE_HOUR_UTIL") {
                    const n = parseInt(value)
                    root.fiveHourUtil = isNaN(n) ? -1 : n
                } else if (key === "SEVEN_DAY_UTIL") {
                    const n = parseInt(value)
                    root.sevenDayUtil = isNaN(n) ? -1 : n
                } else if (key === "FIVE_HOUR_RESET") {
                    root.fiveHourReset = value
                } else if (key === "SEVEN_DAY_RESET") {
                    root.sevenDayReset = value
                } else if (key === "UPDATED_AT") {
                    const n = parseInt(value)
                    root.updatedAt = isNaN(n) ? 0 : n
                }
            }
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

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "data_usage"
                iconSize: Appearance.font.pixelSize.normal
                color: !root.available ? Appearance.colors.colOnLayer2
                    : root.low ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.available && root.fiveHourLeft >= 0 ? root.fiveHourLeft + "%" : "\u2014"
                color: !root.available ? Appearance.colors.colOnLayer2
                    : root.low ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 4

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "data_usage"
                iconSize: Appearance.font.pixelSize.normal
                color: !root.available ? Appearance.colors.colOnLayer2
                    : root.low ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.available && root.fiveHourLeft >= 0 ? root.fiveHourLeft + "%" : "\u2014"
                color: !root.available ? Appearance.colors.colOnLayer2
                    : root.low ? Appearance.m3colors.m3error
                    : Appearance.colors.colOnLayer1
            }
        }
    }

    StyledPopup {
        id: usagePopup
        hoverTarget: root
        active: root.panelOpen

        ColumnLayout {
            id: panelContent
            spacing: 8

            HoverHandler {
                id: panelHover
            }

            // Panel width. A ColumnLayout recomputes its own implicitWidth from
            // its children, so an explicit `implicitWidth` on it was silently
            // overwritten (the panel collapsed to its narrowest row and cut
            // names off); a zero-height spacer with a minimum width sticks.
            Item {
                Layout.minimumWidth: 300
                implicitHeight: 0
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Claude usage")
                color: Appearance.colors.colOnLayer1
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "schedule"
                    iconSize: Appearance.font.pixelSize.small
                    color: root.low ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.available && root.fiveHourLeft >= 0
                        ? Translation.tr("5-hour window: %1% left").arg(root.fiveHourLeft)
                        : Translation.tr("5-hour window: \u2014")
                    color: root.low ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: Translation.tr("resets %1").arg(root.fmtReset(root.fiveHourReset))
                    color: Appearance.colors.colOnLayer2
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "calendar_month"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.available && root.sevenDayLeft >= 0
                        ? Translation.tr("7-day window: %1% left").arg(root.sevenDayLeft)
                        : Translation.tr("7-day window: \u2014")
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: Translation.tr("resets %1").arg(root.fmtResetDay(root.sevenDayReset))
                    color: Appearance.colors.colOnLayer2
                }
            }

            Repeater {
                model: root.available ? root.scopedLimits : []
                delegate: RowLayout {
                    id: scopedRow
                    required property var modelData
                    readonly property bool low: modelData.left <= 20
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: "neurology"
                        iconSize: Appearance.font.pixelSize.small
                        color: scopedRow.low ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Translation.tr("%1 this week: %2% left").arg(scopedRow.modelData.name).arg(scopedRow.modelData.left)
                        color: scopedRow.low ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: Translation.tr("resets %1").arg(root.fmtResetDay(scopedRow.modelData.reset))
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }

            // The numbers above are an older copy: the server refused the
            // last fetch and the script waits before asking again.
            StyledText {
                Layout.fillWidth: true
                visible: root.status === "stale"
                wrapMode: Text.Wrap
                text: root.retryAt > 0
                    ? Translation.tr("Anthropic refused the last update (too many requests). Next try at %1.").arg(Qt.formatDateTime(new Date(root.retryAt * 1000), "HH:mm"))
                    : Translation.tr("Couldn't get fresh numbers; showing the last ones.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.available
                wrapMode: Text.Wrap
                text: root.status === "noauth"
                    ? Translation.tr("Sign in to Claude Code (or Claude in OpenCode) to see usage")
                    : root.status === "ratelimited"
                        ? Translation.tr("Rate limited \u2014 retrying later")
                        : Translation.tr("Usage data unavailable")
                color: Appearance.colors.colOnLayer2
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    id: refreshIcon
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    RotationAnimator on rotation {
                        running: root.refreshing
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) refreshIcon.rotation = 0
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.refreshing ? Translation.tr("Refreshing…")
                        : root.updatedAt > 0 ? Translation.tr("Updated %1 · click to refresh").arg(Qt.formatDateTime(new Date(root.updatedAt * 1000), "HH:mm:ss"))
                        : Translation.tr("Click to refresh")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
