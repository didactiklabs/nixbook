import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "nixosUpdate"
    popoutWidth: 320
    popoutHeight: UpdateState.changelogText ? 600 : 300

    Component {
        id: statusPillBase
        Item {
            property bool vertical: false
            implicitWidth: content.implicitWidth + Theme.spacingM
            implicitHeight: content.implicitHeight

            readonly property bool isActive: UpdateState.checking || UpdateState.updating || UpdateState.updateAvailable

            QtObject {
                id: d
                readonly property string statusText: {
                    if (UpdateState.updating) return vertical ? "Upd..." : "Updating"
                    if (UpdateState.checking) return vertical ? "Chk..." : "Checking"
                    return vertical ? "Upd" : "Update"
                }
            }

            Loader {
                id: content
                anchors.centerIn: parent
                sourceComponent: vertical ? verticalLayout : horizontalLayout
            }

            Component {
                id: horizontalLayout
                Row {
                    spacing: Theme.spacingS
                    DankIcon {
                        name: "sync"
                        size: Theme.iconSize
                        color: UpdateState.updateAvailable ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 1000
                            loops: Animation.Infinite
                            running: UpdateState.checking || UpdateState.updating
                        }
                    }
                    StyledText {
                        visible: isActive
                        text: d.statusText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Component {
                id: verticalLayout
                Column {
                    spacing: Theme.spacingS
                    DankIcon {
                        name: "sync"
                        size: Theme.iconSize
                        color: UpdateState.updateAvailable ? Theme.primary : Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 1000
                            loops: Animation.Infinite
                            running: UpdateState.checking || UpdateState.updating
                        }
                    }
                    StyledText {
                        visible: isActive
                        text: d.statusText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    horizontalBarPill: Loader {
        sourceComponent: statusPillBase
        onLoaded: item.vertical = false
    }

    verticalBarPill: Loader {
        sourceComponent: statusPillBase
        onLoaded: item.vertical = true
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "NixOS Update"
            detailsText: UpdateState.updating ? "Updating system..." : (UpdateState.checking ? "Checking for updates..." : (UpdateState.updateAvailable ? "New version available" : "System up to date"))
            showCloseButton: true

            component VersionDisplay: ColumnLayout {
                property string label: ""
                property string version: ""
                property bool highlight: false
                Layout.fillWidth: true
                spacing: Theme.spacingS

                StyledText {
                    text: label
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    text: ma.containsMouse ? version : (version !== "Unknown" ? version.substring(0, 7) + "..." : "Unknown")
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: "Fira Code"
                    Layout.fillWidth: true
                    color: highlight ? Theme.primary : Theme.surfaceText
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingM

                VersionDisplay {
                    label: "Current Version"
                    version: UpdateState.localRev
                }

                VersionDisplay {
                    label: "Latest Version"
                    version: UpdateState.remoteRev
                    highlight: UpdateState.updateAvailable
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: UpdateState.changelogText !== ""
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Changelog"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        color: Theme.surfaceVariant
                        radius: Theme.cornerRadius

                        Flickable {
                            id: changelogFlickable
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            contentWidth: width
                            contentHeight: changelogLabel.paintedHeight
                            clip: true
                            ScrollBar.vertical: ScrollBar {}

                            StyledText {
                                id: changelogLabel
                                width: parent.width
                                text: UpdateState.changelogText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                DankButton {
                    width: parent.width
                    text: UpdateState.updating ? "Updating..." : "Execute Update"
                    visible: UpdateState.updateAvailable || UpdateState.updating
                    enabled: !UpdateState.updating
                    onClicked: {
                        UpdateState.updating = true
                        UpdateState.startUpdateProcess.running = true
                    }
                }

                DankButton {
                    width: parent.width
                    text: UpdateState.checking ? "Checking..." : "Check for Updates"
                    enabled: !UpdateState.checking && !UpdateState.updating
                    onClicked: UpdateState.checkUpdate()
                }
            }
        }
    }
}
