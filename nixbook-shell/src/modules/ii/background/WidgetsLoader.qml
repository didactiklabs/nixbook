pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.images
import qs.modules.ii.background.widgets.resources
import qs.modules.ii.background.widgets.visualizer
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.nextevent
import qs.modules.ii.background.widgets.musicrecognition
import qs.modules.ii.background.widgets.worldclock
import qs.modules.ii.background.widgets.usercard
import qs.modules.ii.background.widgets.notes
import qs.modules.ii.background.widgets.todo
import qs.modules.ii.background.widgets.timers
import qs.modules.ii.background.widgets.customtext

Item {
    id: root

    required property var screen
    required property var wallpaperItem
    required property bool wallpaperSafetyTriggered

    readonly property bool onThisScreen: Config.options.background.screenList.length === 0
        || Config.options.background.screenList.includes(root.screen.name)

    // One desktop widget: built once wanted on this monitor, revealed after
    // the loading screen.
    component WidgetSlot: FadeLoader {
        id: loaderDelegate
        // The widget's config key ("customImage:<id>" for an extra image).
        required property string widgetKey
        property bool alwaysOnLock: false
        // Set by the delegates: an inline component can't see `root`.
        required property string screenName
        required property Component widgetComponent

        property bool enableLoading: true

        // Per monitor (DesktopWidgets.enabledOn: this monitor's own choice,
        // else the shared switch on the monitors of background.screenList).
        // The clock set to show on the lock screen shows on every monitor
        // while locked.
        readonly property bool wanted: loaderDelegate.enableLoading
            && ((loaderDelegate.alwaysOnLock && GlobalStates.screenLocked
                    && Config.options.background.widgets[loaderDelegate.widgetKey].enable)
                || DesktopWidgets.enabledOn(loaderDelegate.widgetKey, loaderDelegate.screenName))

        // Widgets appear one after another once the loading screen has
        // lifted (Preloader.queueReveal): each one is built while still
        // transparent, then fades in on the next frames, so no build
        // lands in the middle of a fade.
        property bool built: false
        property bool revealed: false
        function requestReveal() {
            if (!loaderDelegate.wanted || loaderDelegate.built)
                return;
            Preloader.queueReveal(() => {
                loaderDelegate.built = true;
                revealTimer.restart();
            });
        }
        onWantedChanged: requestReveal()
        Component.onCompleted: requestReveal()
        Timer {
            id: revealTimer
            interval: 32
            onTriggered: loaderDelegate.revealed = true
        }
        shown: loaderDelegate.wanted && loaderDelegate.revealed
        active: loaderDelegate.built && loaderDelegate.wanted || opacity > 0

        sourceComponent: loaderDelegate.widgetComponent

        onLoaded: {
            if (loaderDelegate.widgetKey === "media" && loaderDelegate.item && loaderDelegate.item.requestReset) {
                loaderDelegate.item.requestReset.connect(() => {
                    loaderDelegate.enableLoading = false
                    mediaResetTimer.restart()
                })
            }
        }

        Timer {
            id: mediaResetTimer
            interval: 500
            onTriggered: loaderDelegate.enableLoading = true
        }
    }

    function componentFor(key) {
        switch (key) {
        case "visualizer":  return visualizerComp
        case "customImage": return customImageComp
        case "sticker":     return stickerComp
        case "calendar":    return calendarComp
        case "nextEvent":   return nextEventComp
        case "musicRecognition": return musicRecognitionComp
        case "weather":     return weatherComp
        case "clock":       return clockComp
        case "notes":       return notesComp
        case "media":       return mediaComp
        case "images":      return imagesComp
        case "resources":   return resourcesComp
        case "worldClock":  return worldClockComp
        case "userCard":    return userCardComp
        case "todo":        return todoComp
        case "timers":      return timersComp
        case "customText":  return customTextComp
        }
        return null
    }

    Repeater {
        model: [
            { key: "visualizer" },
            { key: "customImage" },
            { key: "sticker" },
            { key: "calendar" },
            { key: "nextEvent" },
            { key: "musicRecognition" },
            { key: "weather" },
            { key: "clock", alwaysOnLock: true },
            { key: "notes" },
            { key: "media" },
            { key: "images" },
            { key: "resources" },
            { key: "worldClock" },
            { key: "userCard" },
            { key: "todo" },
            { key: "timers" },
            { key: "customText" },
        ]

        delegate: WidgetSlot {
            required property var modelData
            widgetKey: modelData.key
            alwaysOnLock: modelData.alwaysOnLock ?? false
            screenName: root.screen?.name ?? ""
            widgetComponent: root.componentFor(modelData.key)
        }
    }

    // Extra custom images (DesktopWidgets.multiInstance). A ListModel kept in
    // step by name: editing one image rewrites the whole instances list, which
    // as a plain model would rebuild every image.
    ListModel {
        id: extraImages
    }
    function syncExtraImages() {
        const names = DesktopWidgets.instanceNames("customImage");
        for (let i = extraImages.count - 1; i >= 0; i--) {
            if (!names.includes(extraImages.get(i).name))
                extraImages.remove(i);
        }
        for (const name of names) {
            let found = false;
            for (let i = 0; i < extraImages.count; i++)
                if (extraImages.get(i).name === name) found = true;
            if (!found)
                extraImages.append({ name: name });
        }
    }
    Connections {
        target: Config.options.background.widgets.customImage
        function onInstancesChanged() { root.syncExtraImages() }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.syncExtraImages() }
    }
    Component.onCompleted: root.syncExtraImages()

    Repeater {
        model: extraImages
        delegate: WidgetSlot {
            id: extraImage
            required property string name
            widgetKey: extraImage.name
            screenName: root.screen?.name ?? ""
            widgetComponent: Component {
                CustomImage {
                    configEntryName: extraImage.name
                    screenName: root.screen?.name ?? ""
                    screenWidth: root.screen.width
                    screenHeight: root.screen.height
                    scaledScreenWidth: root.screen.width
                    scaledScreenHeight: root.screen.height
                    wallpaperScale: 1
                    wallpaperItem: root.wallpaperItem
                }
            }
        }
    }

    Component {
        id: visualizerComp
        VisualizerWidget {
            showSelectionBorder: false
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            pinnedBottom: true
        }
    }
    Component {
        id: customImageComp
        CustomImage {
            configEntryName: "customImage"
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: stickerComp
        StickerWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: calendarComp
        CalendarWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: weatherComp
        WeatherWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: clockComp
        ClockWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperSafetyTriggered: root.wallpaperSafetyTriggered
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: notesComp
        NotesWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: mediaComp
        MediaWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: imagesComp
        ImageConverterWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: resourcesComp
        ResourcesWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: nextEventComp
        NextEventWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: musicRecognitionComp
        MusicRecognitionWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: worldClockComp
        WorldClockWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: userCardComp
        UserCardWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: todoComp
        TodoWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: timersComp
        TimerWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
    Component {
        id: customTextComp
        CustomTextWidget {
            screenName: root.screen?.name ?? ""
            screenWidth: root.screen.width
            screenHeight: root.screen.height
            scaledScreenWidth: root.screen.width
            scaledScreenHeight: root.screen.height
            wallpaperScale: 1
            wallpaperItem: root.wallpaperItem
        }
    }
}