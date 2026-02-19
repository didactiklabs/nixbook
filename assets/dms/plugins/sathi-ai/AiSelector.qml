import QtQuick
import qs.Common 
import QtQuick.Controls

// Display a small combo box at the bottom to change the model dynamically.
ComboBox {
    id: root

    width: parent.width
    textRole: "display_name"
    valueRole: "name"
    flat: true
    height: 40

    background: Rectangle {
        // Controls the background of the button itself.
        // Change color logic here to prevent updates or style it differently.
        color: root.popup.visible ? Theme.surfaceContainerHigh : "transparent"
        radius: Theme.cornerRadius
        // padding
        border.color: root.popup.visible ? Theme.primary : "transparent"
        border.width: 1
    }

    contentItem: Text {
        text: root.displayText
        font: root.font
        color: Theme.backgroundText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        rightPadding: Theme.spacingM // 25
        leftPadding: Theme.spacingM // 25
    }

    delegate: ItemDelegate {
        width: ListView.view.width
        clip: true
        contentItem: Text {
            text: model[root.textRole]
            color: Theme.surfaceText
            font: root.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        highlighted: root.highlightedIndex === index
        
        background: Rectangle {
             color: parent.highlighted ? Theme.surfaceContainerHigh : "transparent"
             radius: Theme.cornerRadius
        }
    }


    property real maxPopupHeight: 300

    popup: Popup {
        y: root.height + Theme.spacingM
        width: root.width 
        height: Math.min(contentItem.implicitHeight, root.maxPopupHeight)
        padding: 4

        contentItem: ListView {
            id: lvItems
            clip: true
            implicitHeight: contentHeight 
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex

            ScrollIndicator.vertical: ScrollIndicator { }

            section.property: "provider"
            section.criteria: ViewSection.FullString
            section.delegate: ItemDelegate {
                width: ListView.view.width
                height: 30
                enabled: false
                background: Rectangle {
                    color: Theme.surfaceContainerHighest
                }
                contentItem: Text {
                    text: section.toUpperCase()
                    font.weight: Font.Bold
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSmall
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.spacingM
                }
            }
        }

        background: Rectangle {
            color: Theme.surfaceContainer
            border.color: Theme.primary
            border.width: 1
            radius: Theme.cornerRadius
        }
    }

    // indicator.color:         // Customize the indicator component
    indicator: Rectangle {
        // Anchor it to the right side of the ComboBox
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 20 // Adjust width as needed
        height: parent.height // Match ComboBox height
        color: "transparent"

        Text {
            text: "▼"
            anchors.centerIn: parent
            color:  Theme.backgroundText
            font.pixelSize: root.font.pixelSize * 0.7
        }
    }


    // Set currentIndex to the value stored in the backend.
    // currentIndex: backend.modifier
    displayText: currentText
    font.pixelSize: Theme.fontSizeSmall
    font.bold: true
    // contentItem.contentItem.font.pixelSize: Theme.fontSizeSmall
    // When an item is selected, update the backend.
    // onActivated: backend.modifier = currentValue

}
