import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

TextArea {
    id: root

    signal accepted()

    color: Theme.surfaceText
    font.pixelSize: Theme.fontSizeMedium
    selectedTextColor: Theme.onPrimary
    selectionColor: Theme.primary

    wrapMode: TextEdit.Wrap
    
    background: Rectangle {
        implicitHeight: 40
        color: Theme.surfaceContainerHigh
        radius: Theme.cornerRadius
        border.width: 1
        border.color: root.activeFocus ? Theme.primary : "transparent"

        // We implement our own placeholder to control its position
        Text {
            id: placeholderLabel
            text: "Type a message..."
            color: root.activeFocus ? Theme.primary : Theme.surfaceText
            font.pixelSize: (root.activeFocus || root.length > 0) ? Theme.fontSizeSmall : Theme.fontSizeMedium
            
            // Animation for position and font size
            Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
            Behavior on x { NumberAnimation { duration: 150 } }

            // Position logic
            // Start: Centered vertically (or padded)
            // End: Above the box
            x: (root.activeFocus || root.length > 0) ? Theme.spacingM : Theme.spacingM
            y: (root.activeFocus || root.length > 0) ? -height - (Theme.spacingXS / 2) : (parent.height - height) / 2
        }
    }

    padding: Theme.spacingM

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ShiftModifier) {
                // Allow new line implicitly by not accepting the event
                event.accepted = false; 
            } else {
                event.accepted = true;
                root.accepted();
            }
        }
    }
}
