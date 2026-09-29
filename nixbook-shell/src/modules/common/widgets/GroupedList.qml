import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    default property list<Item> items
    property real bigRadius: Appearance.rounding.normal
    property real smallRadius: Appearance.rounding.unsharpenmore
    property color bgcolor: Appearance.colors.colLayer1
    property real itemVerticalPadding: 24
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight

    // Indices of the rows left visible: an item hidden by its page (`shown`)
    // or by the settings menu's "Editable only" filter collapses its row, and
    // the rounded ends move to the first and last remaining ones.
    readonly property var shownIndices: {
        const out = [];
        for (let i = 0; i < root.items.length; i++) {
            const item = root.items[i];
            if (item.shown !== false && !NixManaged.allFiltered(item)) out.push(i);
        }
        return out;
    }
    // Set `shown` (not `visible`) to hide the list conditionally from a page:
    // an instance's `visible:` would replace the filter binding below.
    property bool shown: true
    visible: root.shown && !(root.items.length > 0 && root.shownIndices.length === 0)

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.items.length
            delegate: Rectangle {
                required property int index
                readonly property bool isFirst: index === root.shownIndices[0]
                readonly property bool isLast: index === root.shownIndices[root.shownIndices.length - 1]
                visible: root.shownIndices.includes(index)
                Layout.fillWidth: true
                implicitHeight: (root.items[index]?.implicitHeight ?? 0) + root.itemVerticalPadding
                color: root.bgcolor
                topLeftRadius:     isFirst ? root.bigRadius : root.smallRadius
                topRightRadius:    isFirst ? root.bigRadius : root.smallRadius
                bottomLeftRadius:  isLast  ? root.bigRadius : root.smallRadius
                bottomRightRadius: isLast  ? root.bigRadius : root.smallRadius

                Component.onCompleted: {
                    const child = root.items[index]
                    if (child) {
                        child.parent = contentArea
                        child.Layout.fillWidth = true
                    }
                }

                ColumnLayout {
                    id: contentArea
                    anchors { fill: parent; margins: 8 }
                    spacing: 0
                }
            }
        }
    }
}