import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "github-notifier-custom"

    // Settings
    property string ghBinary: pluginData.ghBinary || "gh"
    property string org: pluginData.org || ""
    property int refreshInterval: pluginData.refreshInterval || 60

    property string faGithubGlyph: "\uf09b" // Font Awesome GitHub (brands)
    property string faFamily: "Font Awesome 6 Brands, Font Awesome 5 Brands, Font Awesome 6 Free, Font Awesome 5 Free"

    property bool showPRs: GitHubNotifierCustomState.asBool(pluginData.showPRs, true)
    property bool showIssues: GitHubNotifierCustomState.asBool(pluginData.showIssues, true)

    readonly property int totalCount: (showPRs ? GitHubNotifierCustomState.prCount : 0) + (showIssues ? GitHubNotifierCustomState.issuesCount : 0)

    Timer {
        interval: root.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: GitHubNotifierCustomState.refresh(root.ghBinary, root.org, root.showPRs, root.showIssues)
    }

    onGhBinaryChanged: GitHubNotifierCustomState.refresh(root.ghBinary, root.org, root.showPRs, root.showIssues)
    onOrgChanged: GitHubNotifierCustomState.refresh(root.ghBinary, root.org, root.showPRs, root.showIssues)
    onShowPRsChanged: GitHubNotifierCustomState.refresh(root.ghBinary, root.org, root.showPRs, root.showIssues)
    onShowIssuesChanged: GitHubNotifierCustomState.refresh(root.ghBinary, root.org, root.showPRs, root.showIssues)

    function openUrl(url) {
        if (!url) return;
        Quickshell.execDetached(["xdg-open", url]);
        root.closePopout();
    }

    function prWebUrl() {
        const o = (root.org || "").trim();
        if (o)
            return "https://github.com/pulls?q=is:pr+is:open+author:@me+org:" + o;
        return "https://github.com/pulls";
    }

    function issuesWebUrl() {
        const o = (root.org || "").trim();
        if (o)
            return "https://github.com/issues?q=is:issue+is:open+assignee:@me+org:" + o;
        return "https://github.com/issues";
    }

    component Badge: StyledRect {
        property int value: 0
        property color badgeColor: Theme.primary

        height: 18
        width: Math.max(22, badgeText.implicitWidth + Theme.spacingS)
        radius: 9
        color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.18)
        border.width: 1
        border.color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.35)

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: value.toString()
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: badgeColor
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            StyledText {
                text: root.faGithubGlyph
                font.family: root.faFamily
                font.pixelSize: Theme.iconSize - 7
                color: GitHubNotifierCustomState.lastError ? Theme.error : (root.totalCount > 0 ? Theme.primary : (Theme.widgetIconColor ? Theme.widgetIconColor : Theme.surfaceText))
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.totalCount.toString()
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: GitHubNotifierCustomState.lastError ? Theme.error : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                visible: root.totalCount > 0
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            StyledText {
                text: root.faGithubGlyph
                font.family: root.faFamily
                font.pixelSize: 20
                color: GitHubNotifierCustomState.lastError ? Theme.error : (root.totalCount > 0 ? Theme.primary : (Theme.widgetIconColor ? Theme.widgetIconColor : Theme.surfaceText))
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.totalCount.toString()
                color: GitHubNotifierCustomState.lastError ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    component StatRow: Row {
        property string title: ""
        property int count: 0
        property string openUrl: ""

        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: title
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            width: 120
        }

        Badge {
            value: count
            badgeColor: count > 0 ? Theme.primary : Theme.surfaceVariantText
        }

        Item { width: Theme.spacingS; height: 1 }

        Rectangle {
            width: 90
            height: 30
            radius: Theme.cornerRadius
            color: openMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            visible: openUrl.length > 0

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon { name: "open_in_new"; size: 18; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: "Open"; color: Theme.primary; font.pixelSize: Theme.fontSizeMedium; anchors.verticalCenter: parent.verticalCenter }
            }

            MouseArea {
                id: openMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(parent.parent.openUrl)
            }
        }
    }

    popoutContent: Component {
        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingXS
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: root.faGithubGlyph
                    font.family: root.faFamily
                    font.pixelSize: 26
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: "GitHub Notifier"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: root.org ? ("Org: " + root.org) : "All repositories"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: GitHubNotifierCustomState.lastError ? 60 : 0
                radius: Theme.cornerRadius
                color: Theme.errorContainer ? Theme.errorContainer : Theme.error
                visible: GitHubNotifierCustomState.lastError.length > 0

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    text: GitHubNotifierCustomState.lastError
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.onErrorContainer ? Theme.onErrorContainer : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            StatRow {
                title: "Pull Requests"
                count: GitHubNotifierCustomState.prCount
                openUrl: root.prWebUrl()
                visible: root.showPRs
            }

            Flickable {
                width: parent.width
                height: Math.min(contentHeight, 200)
                visible: root.showPRs && GitHubNotifierCustomState.prItems.count > 0
                clip: true
                contentHeight: prColumn.height
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height

                Column {
                    id: prColumn
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: GitHubNotifierCustomState.prItems
                        delegate: Rectangle {
                            width: prColumn.width
                            height: prItemRow.height + 6
                            radius: Theme.cornerRadius
                            color: prItemMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Row {
                                id: prItemRow
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                spacing: Theme.spacingXS
                                leftPadding: 8

                                StyledText {
                                    text: itemRepo ? (itemRepo + " #" + itemNumber) : ("#" + itemNumber)
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                }
                                StyledText {
                                    text: itemTitle
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    width: parent.width - parent.leftPadding - (itemRepo ? 140 : 50)
                                }
                            }

                            MouseArea {
                                id: prItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (itemRepo)
                                        root.openUrl("https://github.com/" + itemRepo + "/pull/" + itemNumber);
                                }
                            }
                        }
                    }
                }
            }

            StatRow {
                title: "Issues"
                count: GitHubNotifierCustomState.issuesCount
                openUrl: root.issuesWebUrl()
                visible: root.showIssues
            }

            Flickable {
                width: parent.width
                height: Math.min(contentHeight, 200)
                visible: root.showIssues && GitHubNotifierCustomState.issueItems.count > 0
                clip: true
                contentHeight: issueColumn.height
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height

                Column {
                    id: issueColumn
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: GitHubNotifierCustomState.issueItems
                        delegate: Rectangle {
                            width: issueColumn.width
                            height: issueItemRow.height + 6
                            radius: Theme.cornerRadius
                            color: issueItemMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            Row {
                                id: issueItemRow
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                spacing: Theme.spacingXS
                                leftPadding: 8

                                StyledText {
                                    text: itemRepo ? (itemRepo + " #" + itemNumber) : ("#" + itemNumber)
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                }
                                StyledText {
                                    text: itemTitle
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    width: parent.width - parent.leftPadding - (itemRepo ? 140 : 50)
                                }
                            }

                            MouseArea {
                                id: issueItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (itemRepo)
                                        root.openUrl("https://github.com/" + itemRepo + "/issues/" + itemNumber);
                                }
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.spacingM
            }
        }
    }

    popoutWidth: 320
    popoutHeight: 0
}
