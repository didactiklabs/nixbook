//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Qt Quick keeps one texture atlas per window for its small images (icons),
// sized from the window rounded up to powers of two: 4096x2048, 32 MB, for a
// full-screen surface holding a dozen icons, 16 MB for a sidebar, 8 MB for the
// bar (about 90 MB over the shell's windows, read from the driver's buffer
// list). 1024x512 (2 MB) holds what a window shows at once; what doesn't fit
// (or is 512 px or more) gets a texture of its own, as large pictures do.
//@ pragma Env QSG_ATLAS_WIDTH=1024
//@ pragma Env QSG_ATLAS_HEIGHT=512
// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1
import "modules/common"
import "services"
import "panelFamilies"
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.modules.ii.equalizer

ShellRoot {
    id: root

    ReloadPopup {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        NightLightService.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        UpdateState.load()
        CalendarEvents.load()
        CalendarReminders.load()
        MemoryReminders.load()
        Initiative.load()
        Kiroshi.load()
        RecentContext.load()
        SmartClipboard.load()
        Routines.load()
        SelfImprove.load()
        ThemeWallpapers.load()
        NiriThemeAnimations.load()
        Preloader.load()
        DesktopControl.load()
        WindowLayouts.load()
        // Projects (projects IPC).
        Projects.load()
        AppTheming.load()
        // Their IPC targets (widgets, notes, todo, contacts, timers,
        // equalizer) exist once they are loaded.
        DesktopWidgets.load()
        Notes.load()
        KeepSync.load()
        Mesh.load()
        Todo.load()
        Contacts.load()
        TimerService.load()
        EqualizerAutoService.load()
        // Echo cancellation: on again if it was (its quick toggle may not be
        // built), and resting while nothing records the microphone.
        EchoCancel.load()
        // YouTube links opened by the shell (youtubeMusic openLink): its IPC
        // target exists once the service is.
        YouTubeMusic.load()
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        // Once niri has said what its outputs are (WM.outputsKnown, a few
        // milliseconds): the surfaces built per screen need each one's scale.
        active: Config.ready && WM.outputsKnown && Config.options.panelFamily === identifier
    }
}