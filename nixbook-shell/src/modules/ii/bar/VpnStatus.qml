pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// VPN status indicator — port of the DMS vpn-dms plugin
// (assets/dms/plugins/vpn-dms) to nixbook-shell. Bar shows a lock icon per backend
// (coloured when connected); left click opens a panel with connect/disconnect
// plus Tailscale account/exit-node and NetBird profile switchers.
//
// This file is view-only: all state, caching and process work lives in the
// VpnState singleton (services/VpnState.qml) so the polling runs once for the
// whole shell instead of once per monitor, and so a finished switch can never
// have its refresh dropped by an in-flight poll.
MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    // Which inline selector is expanded in the panel ("", "tsNet", "tsExit", "nbProfile").
    property string selector: ""

    property bool panelOpen: false
    readonly property bool cursorNear: containsMouse || panelHover.hovered
    readonly property bool locked: VpnState.busy

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0)
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true

    onPanelOpenChanged: {
        if (root.panelOpen) VpnState.panelOpened()
        else VpnState.panelClosed()
    }
    Component.onDestruction: {
        if (root.panelOpen) VpnState.panelClosed()
    }

    Connections {
        target: VpnState
        function onOperationFinished(kind, ok) {
            if (ok && (kind === "tsSwitch" || kind === "tsExit" || kind === "nbSelect"))
                root.selector = ""
        }
    }

    onCursorNearChanged: {
        if (cursorNear) closeTimer.stop()
        else if (panelOpen) closeTimer.start()
    }

    Timer {
        id: closeTimer
        interval: 500
        onTriggered: {
            if (!root.cursorNear) root.panelOpen = false
        }
    }

    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            root.panelOpen = !root.panelOpen
            if (root.panelOpen) {
                VpnState.refreshStatus()
                VpnState.refreshLists(false)
            }
        } else if (mouse.button === Qt.RightButton) {
            VpnState.refresh()
        }
    }

    // ---------------------------------------------------------------- Bar UI

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
                text: "vpn_lock"
                iconSize: Appearance.font.pixelSize.normal
                color: VpnState.tsConnected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "vpn_key"
                iconSize: Appearance.font.pixelSize.normal
                color: VpnState.nbConnected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: 4
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "vpn_lock"
                iconSize: Appearance.font.pixelSize.normal
                color: VpnState.tsConnected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "vpn_key"
                iconSize: Appearance.font.pixelSize.normal
                color: VpnState.nbConnected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }
        }
    }

    // ----------------------------------------------------------------- Panel

    component SelectorRow: Rectangle {
        id: selRow
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        property bool busy: false
        signal activated

        Layout.fillWidth: true
        implicitHeight: 42
        radius: Appearance.rounding.small
        opacity: root.locked && !selRow.busy ? 0.45 : 1
        color: checked ? Appearance.colors.colLayer2 : (rowMa.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)

        Behavior on opacity {
            NumberAnimation { duration: 100 }
        }

        onBusyChanged: {
            if (!busy) rowIcon.rotation = 0
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            MaterialSymbol {
                id: rowIcon
                text: selRow.busy
                    ? "progress_activity"
                    : (selRow.checked ? "radio_button_checked" : "radio_button_unchecked")
                iconSize: Appearance.font.pixelSize.large
                color: (selRow.checked || selRow.busy) ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2

                RotationAnimator on rotation {
                    running: selRow.busy
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: selRow.title
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: selRow.subtitle !== ""
                    text: selRow.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !root.locked
            onClicked: selRow.activated()
        }
    }

    // Hover tooltip: a quick status summary, hidden while the panel is open.
    StyledPopup {
        hoverTarget: root
        active: !root.panelOpen && root.containsMouse && Config.options.bar.tooltips.enable

        ColumnLayout {
            spacing: 4

            StyledPopupHeaderRow {
                icon: "vpn_lock"
                label: Translation.tr("VPN")
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: VpnState.tsConnected ? "check_circle" : "cancel"
                label: "Tailscale"
                value: VpnState.tsConnected
                    ? (VpnState.tsSelectedNetwork || VpnState.tsStatusText) + (VpnState.tsIp ? " — " + VpnState.tsIp : "")
                    : VpnState.tsStatusText
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: VpnState.tsConnected && VpnState.tsExitNode !== ""
                icon: "output"
                label: Translation.tr("Exit node")
                value: VpnState.tsExitNode
            }

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: VpnState.nbConnected ? "check_circle" : "cancel"
                label: "NetBird"
                value: VpnState.nbConnected
                    ? (VpnState.nbSelectedProfile || VpnState.nbStatusText) + (VpnState.nbIp ? " — " + VpnState.nbIp : "")
                    : VpnState.nbStatusText
            }

            StyledText {
                text: Translation.tr("Click to manage · right click to refresh")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledPopup {
        id: vpnPopup
        hoverTarget: root
        active: root.panelOpen

        ColumnLayout {
            id: panelContent
            spacing: 10

            HoverHandler {
                id: panelHover
            }

            // Panel width. A ColumnLayout recomputes its own implicitWidth from
            // its children, so an explicit `implicitWidth` on it was silently
            // overwritten (the panel collapsed to its narrowest row and cut
            // names off); a zero-height spacer with a minimum width sticks.
            Item {
                Layout.minimumWidth: 460
                implicitHeight: 0
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("VPN")
                color: Appearance.colors.colOnLayer1
                font.weight: Font.DemiBold
            }

            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: VpnState.busy
            }

            StyledText {
                Layout.fillWidth: true
                visible: VpnState.opError !== "" && !VpnState.busy
                text: VpnState.opError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }

            // ------------------------------------------------ Tailscale section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selector === ""

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: VpnState.tsConnected ? "check_circle" : "cancel"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: VpnState.tsConnected ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: "Tailscale"
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: VpnState.tsConnected
                                ? (VpnState.tsSelectedNetwork || VpnState.tsStatusText) + (VpnState.tsIp ? " — " + VpnState.tsIp : "")
                                : VpnState.tsStatusText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            visible: VpnState.tsConnected && VpnState.tsExitNode !== ""
                            text: Translation.tr("Exit: %1").arg(VpnState.tsExitNode)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        enabled: !root.locked
                        buttonRadius: Appearance.rounding.normal
                        materialIcon: VpnState.tsConnected ? "link_off" : "link"
                        mainText: VpnState.tsConnected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                        onClicked: VpnState.tsToggle()
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        enabled: !root.locked
                        buttonRadius: Appearance.rounding.normal
                        materialIcon: "switch_account"
                        mainText: Translation.tr("Account")
                        onClicked: {
                            root.selector = "tsNet"
                            VpnState.refreshLists(false)
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    visible: VpnState.tsConnected
                    enabled: !root.locked
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "output"
                    mainText: VpnState.tsExitNode ? Translation.tr("Exit node: %1").arg(VpnState.tsExitNode) : Translation.tr("Select exit node")
                    onClicked: root.selector = "tsExit"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                visible: root.selector === ""
                color: Appearance.colors.colOutlineVariant
            }

            // -------------------------------------------------- NetBird section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selector === ""

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: VpnState.nbConnected ? "check_circle" : "cancel"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: VpnState.nbConnected ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: "NetBird"
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: VpnState.nbConnected
                                ? (VpnState.nbSelectedProfile || VpnState.nbStatusText) + (VpnState.nbIp ? " — " + VpnState.nbIp : "")
                                : VpnState.nbStatusText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        enabled: !root.locked
                        buttonRadius: Appearance.rounding.normal
                        materialIcon: VpnState.nbConnected ? "link_off" : "link"
                        mainText: VpnState.nbConnected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                        onClicked: VpnState.nbToggle()
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        enabled: !root.locked
                        buttonRadius: Appearance.rounding.normal
                        materialIcon: "badge"
                        mainText: Translation.tr("Profile")
                        onClicked: {
                            root.selector = "nbProfile"
                            VpnState.refreshLists(false)
                        }
                    }
                }
            }

            // ------------------------------------------ Tailscale account list
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selector === "tsNet"

                StyledText {
                    text: Translation.tr("Tailscale accounts")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    visible: VpnState.tsNetworks.length === 0
                    text: VpnState.tsNetworksFetchedAt > 0
                        ? Translation.tr("No accounts found")
                        : Translation.tr("Loading…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }

                Repeater {
                    model: VpnState.tsNetworks
                    delegate: SelectorRow {
                        required property var modelData
                        title: modelData.name
                        subtitle: modelData.account
                        checked: modelData.name === VpnState.tsSelectedNetwork
                        busy: VpnState.op === "tsSwitch" && VpnState.opTarget === modelData.name
                        onActivated: VpnState.tsSwitchNetwork(modelData.name)
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: !root.locked
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "arrow_back"
                    mainText: Translation.tr("Back")
                    onClicked: root.selector = ""
                }
            }

            // -------------------------------------------- Tailscale exit nodes
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selector === "tsExit"

                StyledText {
                    text: Translation.tr("Tailscale exit nodes")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                SelectorRow {
                    title: Translation.tr("None (direct)")
                    checked: VpnState.tsExitNode === ""
                    busy: VpnState.op === "tsExit" && VpnState.opTarget === ""
                    enabled: !root.locked
                    onActivated: VpnState.tsClearExitNode()
                }

                Repeater {
                    model: VpnState.tsExitNodes
                    delegate: SelectorRow {
                        required property var modelData
                        title: modelData.hostname
                        subtitle: {
                            const parts = []
                            if (modelData.city) parts.push(modelData.city)
                            if (modelData.country) parts.push(modelData.country)
                            const loc = parts.join(", ")
                            return loc ? loc : (modelData.online ? "Online" : "Offline")
                        }
                        checked: modelData.active || modelData.hostname === VpnState.tsExitNode
                        busy: VpnState.op === "tsExit" && VpnState.opTarget === modelData.hostname
                        onActivated: VpnState.tsSetExitNode(modelData.hostname)
                    }
                }

                StyledText {
                    visible: VpnState.tsExitNodes.length === 0 && VpnState.tsConnected
                    text: Translation.tr("No exit nodes found")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: !root.locked
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "arrow_back"
                    mainText: Translation.tr("Back")
                    onClicked: root.selector = ""
                }
            }

            // --------------------------------------------- NetBird profile list
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selector === "nbProfile"

                StyledText {
                    text: Translation.tr("NetBird profiles")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    visible: VpnState.nbProfiles.length === 0
                    text: VpnState.nbProfilesFetchedAt > 0
                        ? Translation.tr("No profiles found")
                        : Translation.tr("Loading…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }

                Repeater {
                    model: VpnState.nbProfiles
                    delegate: SelectorRow {
                        required property var modelData
                        title: modelData.name
                        checked: modelData.name === VpnState.nbSelectedProfile
                        busy: VpnState.op === "nbSelect" && VpnState.opTarget === modelData.name
                        onActivated: VpnState.nbSelectProfile(modelData.name)
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: !root.locked
                    buttonRadius: Appearance.rounding.normal
                    materialIcon: "arrow_back"
                    mainText: Translation.tr("Back")
                    onClicked: root.selector = ""
                }
            }
        }
    }
}
