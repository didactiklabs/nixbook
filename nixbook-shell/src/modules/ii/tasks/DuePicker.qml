pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A month to pick a due date from: picked(date) with the day chosen.
Popup {
    id: root
    property var date: null
    property var month: new Date()
    signal picked(var date)

    padding: 14
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onAboutToShow: {
        const d = root.date ?? new Date()
        root.month = new Date(d.getFullYear(), d.getMonth(), 1)
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer3Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    readonly property var days: {
        const first = new Date(root.month.getFullYear(), root.month.getMonth(), 1)
        // Weeks start on the locale's first day.
        const shift = (first.getDay() - Qt.locale().firstDayOfWeek % 7 + 7) % 7
        const out = []
        for (let i = 0; i < 42; i++)
            out.push(new Date(first.getFullYear(), first.getMonth(), 1 - shift + i))
        return out
    }
    function sameDay(a, b) {
        return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    contentItem: ColumnLayout {
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: Qt.locale().toString(root.month, "MMMM yyyy")
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer3
            }
            Repeater {
                model: [["chevron_left", -1], ["chevron_right", 1]]
                delegate: Rectangle {
                    id: navButton
                    required property var modelData
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 16
                    color: navMouse.containsMouse ? Appearance.colors.colLayer3Hover : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: navButton.modelData[0]
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer3
                    }
                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.month = new Date(root.month.getFullYear(), root.month.getMonth() + navButton.modelData[1], 1)
                    }
                }
            }
        }

        Grid {
            columns: 7
            spacing: 2
            Repeater {
                model: 7
                delegate: StyledText {
                    required property int index
                    width: 34
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((Qt.locale().firstDayOfWeek + index) % 7, Locale.NarrowFormat)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            Repeater {
                model: root.days
                delegate: Rectangle {
                    id: dayCell
                    required property var modelData
                    readonly property bool chosen: root.sameDay(modelData, root.date)
                    readonly property bool today: root.sameDay(modelData, new Date())
                    width: 34
                    height: 34
                    radius: 17
                    color: dayCell.chosen ? Appearance.colors.colPrimary
                        : dayMouse.containsMouse ? Appearance.colors.colLayer3Hover : "transparent"
                    border.width: dayCell.today && !dayCell.chosen ? 1 : 0
                    border.color: Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: dayCell.modelData.getDate()
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: dayCell.chosen ? Appearance.colors.colOnPrimary
                            : dayCell.modelData.getMonth() !== root.month.getMonth() ? Appearance.colors.colSubtext
                            : Appearance.colors.colOnLayer3
                    }
                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.picked(dayCell.modelData)
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
