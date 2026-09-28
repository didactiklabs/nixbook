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

    // Indices of the items the settings menu's "Editable only" filter leaves
    // visible: hidden rows collapse and the rounded ends move to the first
    // and last remaining ones.
    readonly property var shownIndices: {
        const out = [];
        for (let i = 0; i < root.items.length; i++)
            if (!NixManaged.allFiltered(root.items[i])) out.push(i);
        return out;
    }
    Binding on visible {
        when: root.items.length > 0 && root.shownIndices.length === 0
        value: false
    }

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