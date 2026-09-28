pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    // Scrolls when taller than the screen allows (DesktopMenu's loader).
    readonly property real maxHeight: parent?.maxItemHeight ?? Number.POSITIVE_INFINITY
    implicitHeight: Math.min(col.implicitHeight + 16, maxHeight)

    readonly property var widgetList: [
        { key: "visualizer",  icon: "graphic_eq",         name: Translation.tr("Visualizer") },
        { key: "customImage", icon: "image",              name: Translation.tr("Custom Image") },
        { key: "weather",     icon: "partly_cloudy_day",  name: Translation.tr("Weather") },
        { key: "clock",       icon: "schedule",           name: Translation.tr("Clock") },
        { key: "media",       icon: "music_note",         name: Translation.tr("Media") },
        { key: "images",      icon: "photo_library",      name: Translation.tr("Image Converter") },
        { key: "resources",   icon: "monitor_heart",      name: Translation.tr("Resources") },
        { key: "calendar",    icon: "calendar_month",     name: Translation.tr("Calendar") },
        { key: "nextEvent",   icon: "event_upcoming",     name: Translation.tr("Next Event") },
        { key: "worldClock",  icon: "public",             name: Translation.tr("World Clock") },
        { key: "userCard",    icon: "person",             name: Translation.tr("User Card") },
        { key: "notes",       icon: "note_stack_add",     name: Translation.tr("Notes") },
        { key: "timers",      icon: "timer",              name: Translation.tr("Timers") },
        { key: "todo",        icon: "add_task",           name: Translation.tr("To-Do") },
        { key: "sticker",     icon: "sticker",            name: Translation.tr("Sticker") },
    ]

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    StyledFlickable {
        id: flick
        anchors { fill: parent; margins: 8 }
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight
        interactive: contentHeight > height

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 2

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "lock"
                text: Translation.tr("Lock widget positions")
                configKey: "background.widgetsLocked"
                checked: Config.options.background.widgetsLocked
                onCheckedChanged: Config.options.background.widgetsLocked = checked
            }
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "shadow"
                text: Translation.tr("Shadow")
                configKey: "background.widgets.shadow"
                checked: Config.options.background.widgets.shadow 
                onCheckedChanged: Config.options.background.widgets.shadow = checked
            }
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "blur_on"
                text: Translation.tr("Blur widgets")
                configKey: "background.widgets.blurWidgets"
                checked: Config.options.background.widgets.blurWidgets 
                onCheckedChanged: Config.options.background.widgets.blurWidgets = checked
            }

            ConfigSlider {
                configKey: "background.widgets.blurRadius"
                Layout.fillWidth: true
                showLabel: false
                visible: Config.options.background.widgets.blurWidgets
                value: Config.options.background.widgets.blurRadius ?? 32
                usePercentTooltip: false
                buttonIcon: "aspect_ratio"
                from: 1
                to: 64
                stopIndicatorValues: [32]
                onValueChanged: Config.options.background.widgets.blurRadius = value
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.4
            }

            Repeater {
                model: root.widgetList
                delegate: ConfigSwitch {
                    required property var modelData
                    Layout.fillWidth: true
                    buttonIcon: modelData.icon
                    text: modelData.name
                    // For the monitor the menu was opened on (DesktopWidgets):
                    // each monitor can show its own set of widgets.
                    readonly property string screenName: GlobalStates.desktopMenuScreen?.name ?? ""
                    checked: DesktopWidgets.enabledOn(modelData.key, screenName)
                    onCheckedChanged: {
                        if (checked !== DesktopWidgets.enabledOn(modelData.key, screenName))
                            DesktopWidgets.setValues(modelData.key, screenName, { enable: checked });
                        // Clicking replaced the binding; the menu outlives one
                        // opening (and one monitor), so bind it again.
                        checked = Qt.binding(() => DesktopWidgets.enabledOn(modelData.key, screenName));
                    }
                }
            }
        }
    }
}
