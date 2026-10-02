import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// One result in the launcher's grid (SearchWidget's grid mode): a big icon
// over the name, like DankLauncher's grid. Prefix modes (clipboard, emojis…)
// keep the list rows (SearchItem).
RippleButton {
    id: root
    property LauncherSearchResult entry
    property string itemName: entry?.name ?? ""
    property string itemType: entry?.type ?? Translation.tr("App")
    property var iconType: entry?.iconType
    property string iconName: entry?.iconName ?? ""
    property var itemExecute: entry?.execute
    property bool keyboardDown: false
    readonly property int iconSize: 48
    // The grid's current tile is the one Enter opens (the pointer moves it
    // too: SearchWidget's HoverHandler).
    readonly property bool selected: (root.focus || GridView.isCurrentItem)

    visible: entry?.shown ?? true
    buttonRadius: Appearance.rounding.normal
    readonly property color colSelected: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.7)
    colBackground: (root.down || root.keyboardDown) ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.55) :
        (selected ? root.colSelected :
        ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1))
    colBackgroundHover: root.colSelected
    colRipple: Appearance.colors.colPrimaryContainerActive
    border: root.selected
    borderWidth: 1.5
    colBorder: Appearance.colors.colPrimary
    property color colForeground: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface

    onClicked: {
        GlobalStates.overviewOpen = false
        root.itemExecute()
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = true
            root.clicked()
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false
            event.accepted = true;
        }
    }

    contentItem: ColumnLayout {
        spacing: 6

        Item { Layout.fillHeight: true }

        Loader {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            sourceComponent: switch (root.iconType) {
                case LauncherSearchResult.IconType.Material:
                    return materialSymbolComponent
                case LauncherSearchResult.IconType.Text:
                    return bigTextComponent
                case LauncherSearchResult.IconType.System:
                    return iconImageComponent
                default:
                    return null
            }
        }

        Component {
            id: iconImageComponent
            IconImage {
                source: Quickshell.iconPath(root.iconName, "image-missing")
                implicitSize: root.iconSize
            }
        }
        Component {
            id: materialSymbolComponent
            MaterialSymbol {
                text: root.iconName
                iconSize: 40
                color: root.colForeground
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        Component {
            id: bigTextComponent
            StyledText {
                text: root.iconName
                font.pixelSize: Appearance.font.pixelSize.hugeass
                color: root.colForeground
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        StyledText { // Name
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colForeground
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: typeText.visible ? 1 : 2
            elide: Text.ElideRight
            text: root.itemName
        }
        StyledText { // Kind, for what isn't an app (settings, command, web search…)
            id: typeText
            Layout.fillWidth: true
            visible: root.itemType && root.itemType != Translation.tr("App")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.itemType
        }

        Item { Layout.fillHeight: true }
    }
}
