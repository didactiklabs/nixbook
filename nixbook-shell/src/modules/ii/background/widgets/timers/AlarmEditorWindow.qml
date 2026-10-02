pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Floating editor for the alarm (TimerService), opened from the timers
 * desktop widget: a time, a date (or every day), an optional label. Escape or
 * a click outside the card closes without saving; Enter saves.
 */
PanelWindow {
    id: root

    // Emitted once the close animation has run: the loader drops the window.
    signal dismissed()

    property bool closing: false

    // Starts from the alarm set, else the next round hour.
    readonly property date initial: {
        if (TimerService.alarmAt > 0)
            return new Date(TimerService.alarmAt * 1000);
        const d = new Date();
        d.setHours(d.getHours() + 1, 0, 0, 0);
        return d;
    }
    property int hour: root.initial.getHours()
    property int minute: root.initial.getMinutes()
    property date day: new Date(root.initial.getFullYear(), root.initial.getMonth(), root.initial.getDate())
    property bool daily: TimerService.alarmDaily
    // The month the calendar shows
    property date month: new Date(root.day.getFullYear(), root.day.getMonth(), 1)

    readonly property date today: {
        const d = new Date(clock.now);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }
    readonly property int atSeconds: Math.floor(new Date(root.day.getFullYear(), root.day.getMonth(), root.day.getDate(), root.hour, root.minute).getTime() / 1000)
    // When it would ring: a daily alarm's next time, from today.
    readonly property int ringsAt: root.daily
        ? TimerService.nextDaily(Math.floor(new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate(), root.hour, root.minute).getTime() / 1000), Math.floor(clock.now / 1000))
        : root.atSeconds
    readonly property bool valid: root.ringsAt > Math.floor(clock.now / 1000)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:alarmEditor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Keeps "today" and "rings in …" current while open.
    QtObject {
        id: clock
        property real now: Date.now()
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: clock.now = Date.now()
    }

    function save() {
        if (!root.valid) return;
        TimerService.setAlarm(root.daily ? root.ringsAt : root.atSeconds, labelField.text.trim(), root.daily);
        root.close();
    }

    function close() {
        if (root.closing) return;
        root.closing = true;
        closeAnim.start();
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // "in 2 d 3 h", "in 45 min", "in less than a minute"
    function untilText(seconds) {
        const mins = Math.ceil(seconds / 60);
        if (mins < 1) return Translation.tr("in less than a minute");
        const d = Math.floor(mins / 1440), h = Math.floor((mins % 1440) / 60), m = mins % 60;
        const parts = [];
        if (d > 0) parts.push(Translation.tr("%1 d").arg(d));
        if (h > 0) parts.push(Translation.tr("%1 h").arg(h));
        if (m > 0 && d === 0) parts.push(Translation.tr("%1 min").arg(m));
        return Translation.tr("in %1").arg(parts.join(" "));
    }

    // The month's days, Monday first, padded with the neighbouring months'.
    function monthCells(first) {
        const year = first.getFullYear(), month = first.getMonth();
        const offset = (new Date(year, month, 1).getDay() + 6) % 7;
        const cells = [];
        for (let i = 0; i < 42; i++)
            cells.push(new Date(year, month, 1 - offset + i));
        return cells;
    }

    Component.onCompleted: {
        labelField.text = TimerService.alarmLabel;
        hourField.forceActiveFocus();
        openAnim.start();
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        onActivated: root.save()
    }

    // Scrim: a click outside the card closes.
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.close()
        }
    }

    Item {
        id: card
        width: Math.min(420, root.width - 64)
        height: Math.min(content.implicitHeight + 32, root.height - 64)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        scale: 0.9
        opacity: 0

        StyledRectangularShadow {
            target: cardBg
        }

        Rectangle {
            id: cardBg
            anchors.fill: parent
            radius: Appearance.rounding.verylarge
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        // Swallow clicks so they don't reach the scrim.
        MouseArea {
            anchors.fill: parent
        }

        // Scrolls on a screen too short for it
        StyledFlickable {
            anchors {
                fill: parent
                margins: 16
            }
            clip: true
            contentHeight: content.implicitHeight
            interactive: contentHeight > height

        ColumnLayout {
            id: content
            width: parent.width
            spacing: 8

            // Header, also the handle to move the card
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Item {
                    Layout.fillWidth: true
                    implicitHeight: title.implicitHeight

                    StyledText {
                        id: title
                        anchors {
                            left: parent.left
                            leftMargin: 8
                        }
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Alarm")
                    }

                    DragHandler {
                        target: card
                        cursorShape: Qt.ClosedHandCursor
                        xAxis.minimum: 0
                        xAxis.maximum: root.width - card.width
                        yAxis.minimum: 0
                        yAxis.maximum: root.height - card.height
                    }
                }

                EditorButton {
                    visible: TimerService.alarmAt > 0
                    iconText: "delete"
                    tooltip: Translation.tr("Delete alarm")
                    onClicked: {
                        TimerService.clearAlarm();
                        root.close();
                    }
                }
                EditorButton {
                    iconText: "close"
                    tooltip: Translation.tr("Close (Esc)")
                    onClicked: root.close()
                }
            }

            // Time
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                TimeField {
                    id: hourField
                    value: root.hour
                    maximum: 23
                    onEdited: v => root.hour = v
                }
                StyledText {
                    text: ":"
                    font.pixelSize: 40
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                }
                TimeField {
                    value: root.minute
                    maximum: 59
                    onEdited: v => root.minute = v
                }
            }

            // Date
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                opacity: root.daily ? 0.4 : 1
                enabled: !root.daily

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    text: Qt.locale().standaloneMonthName(root.month.getMonth()) + " " + root.month.getFullYear()
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                Chip {
                    label: Translation.tr("Today")
                    toggled: root.sameDay(root.day, root.today)
                    onClicked: root.day = root.today
                }
                Chip {
                    label: Translation.tr("Tomorrow")
                    toggled: root.sameDay(root.day, new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate() + 1))
                    onClicked: root.day = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate() + 1)
                }
                EditorButton {
                    iconText: "chevron_left"
                    tooltip: Translation.tr("Previous month")
                    // Not before this month
                    enabled: root.month > new Date(root.today.getFullYear(), root.today.getMonth(), 1)
                    onClicked: root.month = new Date(root.month.getFullYear(), root.month.getMonth() - 1, 1)
                }
                EditorButton {
                    iconText: "chevron_right"
                    tooltip: Translation.tr("Next month")
                    onClicked: root.month = new Date(root.month.getFullYear(), root.month.getMonth() + 1, 1)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 2
                columnSpacing: 2
                opacity: root.daily ? 0.4 : 1
                enabled: !root.daily

                Repeater {
                    model: 7
                    delegate: StyledText {
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        // Monday first
                        text: Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                Repeater {
                    model: root.monthCells(root.month)
                    delegate: RippleButton {
                        id: dayButton
                        required property var modelData
                        readonly property bool inMonth: modelData.getMonth() === root.month.getMonth()
                        readonly property bool selected: root.sameDay(modelData, root.day)
                        readonly property bool isToday: root.sameDay(modelData, root.today)
                        Layout.fillWidth: true
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        enabled: modelData >= root.today
                        toggled: dayButton.selected
                        colBackground: "transparent"
                        onClicked: {
                            root.day = dayButton.modelData;
                            if (!dayButton.inMonth)
                                root.month = new Date(dayButton.modelData.getFullYear(), dayButton.modelData.getMonth(), 1);
                        }
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: dayButton.modelData.getDate()
                            font.weight: dayButton.isToday ? Font.Bold : Font.Normal
                            color: dayButton.selected ? Appearance.colors.colOnPrimary
                                : dayButton.isToday ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer1
                            opacity: !dayButton.enabled ? 0.3 : dayButton.inMonth ? 1 : 0.5
                        }
                    }
                }
            }

            MaterialTextField {
                id: labelField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Label (optional)")
            }

            ConfigSwitch {
                buttonIcon: "event_repeat"
                text: Translation.tr("Repeat every day")
                checked: root.daily
                onCheckedChanged: root.daily = checked
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    wrapMode: Text.Wrap
                    color: root.valid ? Appearance.colors.colSubtext : Appearance.colors.colError
                    text: !root.valid ? Translation.tr("That time has passed")
                        : (root.daily ? Translation.tr("Every day at %1").arg(Qt.formatTime(new Date(root.ringsAt * 1000), Config.options.time.format))
                            : Qt.formatDateTime(new Date(root.ringsAt * 1000), Config.options.time.dateFormat + " " + Config.options.time.format))
                          + " · " + root.untilText(root.ringsAt - clock.now / 1000)
                }
                DialogButton {
                    buttonText: Translation.tr("Save")
                    enabled: root.valid
                    onClicked: root.save()
                }
            }
        }
        }
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: scrim; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            NumberAnimation { target: scrim; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: card; property: "scale"; to: 0.92; duration: 140; easing.type: Easing.InQuad }
        }
        ScriptAction { script: root.dismissed() }
    }

    // Two digits: type them, scroll, or use the arrows (wrapping around).
    component TimeField: ColumnLayout {
        id: field
        property int value: 0
        property int maximum: 59
        signal edited(int value)
        function step(delta) {
            field.edited((field.value + delta + field.maximum + 1) % (field.maximum + 1));
        }
        function forceActiveFocus() {
            input.forceActiveFocus();
            input.selectAll();
        }
        spacing: 0

        EditorButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 28
            iconText: "keyboard_arrow_up"
            onClicked: field.step(1)
        }
        Rectangle {
            implicitWidth: 84
            implicitHeight: 60
            radius: Appearance.rounding.normal
            color: input.activeFocus ? Appearance.colors.colPrimaryContainer : Appearance.m3colors.m3surfaceContainerHigh

            StyledTextInput {
                id: input
                anchors.centerIn: parent
                text: field.value.toString().padStart(2, "0")
                font.pixelSize: 40
                font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colOnLayer1
                maximumLength: 2
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: field.maximum }
                onTextEdited: {
                    if (acceptableInput)
                        field.edited(parseInt(text));
                }
                // Back to two digits when leaving the field
                onActiveFocusChanged: {
                    if (!activeFocus)
                        text = Qt.binding(() => field.value.toString().padStart(2, "0"));
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => field.step(event.angleDelta.y > 0 ? 1 : -1)
            }
        }
        EditorButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 28
            iconText: "keyboard_arrow_down"
            onClicked: field.step(-1)
        }
    }

    component Chip: RippleButton {
        id: chip
        property string label
        implicitHeight: 30
        implicitWidth: chipText.implicitWidth + 24
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        contentItem: StyledText {
            id: chipText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
    }

    component EditorButton: RippleButton {
        id: btn
        property string iconText
        property string tooltip
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        opacity: enabled ? 1 : 0.4
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: Appearance.font.pixelSize.larger
            text: btn.iconText
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            extraVisibleCondition: btn.tooltip !== ""
            text: btn.tooltip
        }
    }
}
