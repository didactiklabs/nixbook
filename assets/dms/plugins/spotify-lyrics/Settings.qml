import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    spacing: Theme.spacingM
    
    StyledText {
        text: "Spotify Lyrics Settings"
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }
    
    StyledText {
        text: "Configure appearance and behavior here."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
