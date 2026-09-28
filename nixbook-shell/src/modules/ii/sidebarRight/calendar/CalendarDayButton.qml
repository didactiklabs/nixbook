import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    // Events on this day (CalendarEvents), shown as up to three dots in
    // their calendar's colour.
    property var events: []

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38;
    implicitHeight: 38;

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small

    contentItem: StyledText {
        anchors.fill: parent
        text: day
        horizontalAlignment: Text.AlignHCenter
        font.weight: bold ? Font.DemiBold : Font.Normal
        color: (isToday == 1) ? Appearance.m3colors.m3onPrimary :
            (isToday == 0) ? Appearance.colors.colOnLayer1 :
            Appearance.colors.colOutlineVariant

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        spacing: 2
        visible: button.events.length > 0
        opacity: button.isToday == -1 ? 0.5 : 1
        Repeater {
            model: button.events.slice(0, 3)
            delegate: Rectangle {
                required property var modelData
                width: 4
                height: 4
                radius: 2
                color: button.isToday == 1 ? Appearance.m3colors.m3onPrimary
                    : (modelData.color || Appearance.colors.colPrimary)
            }
        }
    }
}
