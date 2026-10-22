pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

/**
 * What asked in Claude's bubble is a plain command, done at once in plain
 * code instead of a Claude run (which can think for a while): open an app,
 * the music (play, pause, next, previous), the volume and brightness, dark
 * or light mode, Do Not Disturb, locking the screen, a timer or a
 * pomodoro, a saved window layout, a task added. Strict patterns only:
 * anything else, or anything unsure (an app it can't name for sure), goes
 * to Claude as before. `run(text)` does it and says what it did, else "".
 */
Singleton {
    id: root

    // Lowercase, no politeness around it, no final punctuation.
    function _clean(text) {
        return String(text ?? "").trim().toLowerCase()
            .replace(/^(hey |ok |okay )?(claude[,:]?\s+)?/, "")
            .replace(/^(please |pls |can you |could you |would you |will you )+/, "")
            .replace(/(,?\s*(please|pls|thanks|thank you))+$/, "")
            .replace(/[.!?\s]+$/, "")
            .trim()
    }

    function run(text) {
        const raw = String(text ?? "").trim()
        // Short and on one line: a command, not a question or a story.
        if (raw.length === 0 || raw.length > 80 || raw.includes("\n")) return ""
        const t = root._clean(raw)
        let m
        // The music.
        if (/^(play|resume|unpause)( (the )?(music|song))?$/.test(t)) {
            const p = MprisController.activePlayer
            if (!p) return ""
            if (!p.isPlaying && p.canPlay) p.play()
            return Translation.tr("Playing.")
        }
        if (/^(pause|stop)( (the )?(music|song))?$/.test(t)) {
            if (Mpris.players.values.length === 0) return ""
            for (const player of Mpris.players.values) if (player.canPause) player.pause()
            return Translation.tr("Paused.")
        }
        if (/^(next|skip)( (this )?(song|track))?$/.test(t) || /^(next|skip) (song|track)$/.test(t)) {
            if (!MprisController.canGoNext) return ""
            MprisController.next()
            return Translation.tr("Next track.")
        }
        if (/^(previous|prev)( (song|track))?$/.test(t) || /^(go back|last) (song|track)$/.test(t)) {
            if (!MprisController.canGoPrevious) return ""
            MprisController.previous()
            return Translation.tr("Previous track.")
        }
        // The volume.
        if ((m = /^(?:set |turn )?(?:the )?(?:volume|sound)(?: to| at)? (\d{1,3}) ?%?$/.exec(t))) {
            if (!Audio.sink?.audio) return ""
            const v = Math.min(100, Number(m[1]))
            Audio.sink.audio.muted = false
            Audio.sink.audio.volume = v / 100
            return Translation.tr("Volume %1%.").arg(v)
        }
        if ((m = /^(?:turn )?(?:the )?(?:volume|sound) (up|down)$|^(louder|quieter|softer)$/.exec(t))) {
            if (!Audio.sink?.audio) return ""
            const up = m[1] === "up" || m[2] === "louder"
            Audio.sink.audio.volume = Math.max(0, Math.min(1, Math.round((Audio.value + (up ? 0.1 : -0.1)) * 100) / 100))
            return Translation.tr("Volume %1%.").arg(Math.round(Audio.sink.audio.volume * 100))
        }
        if ((m = /^(mute|unmute)( (the )?(sound|audio|volume))?$/.exec(t))) {
            if (!Audio.sink?.audio) return ""
            Audio.sink.audio.muted = m[1] === "mute"
            return m[1] === "mute" ? Translation.tr("Muted.") : Translation.tr("Sound on.")
        }
        // The brightness.
        if ((m = /^(?:turn )?(?:the )?(?:brightness|screen) (up|down)$|^(brighter|darker|dimmer)$/.exec(t))) {
            if (m[1] === "up" || m[2] === "brighter") Brightness.increaseBrightness()
            else Brightness.decreaseBrightness()
            return m[1] === "up" || m[2] === "brighter" ? Translation.tr("Brighter.") : Translation.tr("Dimmer.")
        }
        // Dark or light.
        if ((m = /^(?:switch to |turn on |use |go |enable )?(dark|light)(?: mode| theme)?(?: on)?$|^(?:turn off|disable) (dark|light)(?: mode| theme)?$/.exec(t))) {
            const mode = m[1] ?? (m[2] === "dark" ? "light" : "dark")
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", mode, "--noswitch"])
            return mode === "dark" ? Translation.tr("Dark mode on.") : Translation.tr("Light mode on.")
        }
        // Do Not Disturb.
        if ((m = /^(?:turn |switch )?(on |off )?(?:do not disturb|dnd)( on| off)?$/.exec(t))) {
            const on = (m[1] ?? m[2] ?? " on").trim() !== "off"
            Notifications.silent = on
            return on ? Translation.tr("Do Not Disturb on.") : Translation.tr("Do Not Disturb off.")
        }
        // Lock.
        if (/^lock( the| my)?( screen| computer| session| pc)?$/.test(t)) {
            Qt.callLater(() => GlobalStates.screenLocked = true)
            return Translation.tr("Locking.")
        }
        // A timer, a pomodoro.
        if ((m = /^(?:set |start )?(?:a )?(?:timer|countdown)(?: for| of)? (\d{1,3}) ?(?:m|min|mins|minutes?)$|^(?:set |start )?(?:a )?(\d{1,3}) ?(?:m|min|mins|minutes?) (?:timer|countdown)$/.exec(t))) {
            const minutes = Number(m[1] ?? m[2])
            if (minutes <= 0) return ""
            TimerService.resetCountdown()
            TimerService.addCountdownMinutes(minutes)
            TimerService.toggleCountdown()
            return Translation.tr("Timer: %1 min.").arg(minutes)
        }
        if (/^(start )?(a )?pomodoro$/.test(t)) {
            if (!TimerService.pomodoroRunning) TimerService.togglePomodoro()
            return Translation.tr("Pomodoro started.")
        }
        // A saved window layout, by its name.
        if ((m = /^(?:restore |load |switch to |open )?(?:the |my )?(.+?) layout$|^layout (.+)$/.exec(t))) {
            const want = (m[1] ?? m[2]).trim()
            const layout = WindowLayouts.layouts.find(l => String(l.name).toLowerCase() === want)
            if (!layout) return ""
            WindowLayouts.restore(layout.name)
            return Translation.tr("Restoring the %1 layout.").arg(layout.name)
        }
        // A task.
        if ((m = /^(?:add )?(?:a )?(?:todo|task)[: ]+(.+)$/.exec(t)) || (m = /^add (.+) to (?:my )?(?:todo|tasks|to-?do list)$/.exec(t))) {
            // In the user's own words, not lowercased.
            const words = raw.replace(/[.!]+$/, "")
            const at = words.toLowerCase().indexOf(m[1])
            const content = (at >= 0 ? words.slice(at, at + m[1].length) : m[1]).trim()
            if (content.length === 0) return ""
            Todo.addTask(content)
            return Translation.tr("Added to your tasks: %1").arg(content)
        }
        // The shell's settings.
        if (/^(open )?(the )?(shell )?settings$/.test(t)) {
            GlobalStates.settingsOpen = true
            return Translation.tr("Opening Settings.")
        }
        // An app, only when its name is certain.
        if ((m = /^(?:open|launch|start|run) (?:the |my )?(.+?)(?: app)?$/.exec(t))) {
            const entry = root._app(m[1])
            if (!entry) return ""
            AppLaunch.launchEntry(entry)
            return Translation.tr("Opening %1.").arg(entry.name)
        }
        return ""
    }

    // The app named exactly (its name, its id, or the start of its name),
    // else none: an app opened by mistake is worse than asking Claude.
    function _app(name) {
        const want = name.trim()
        if (want.length < 2) return null
        for (const entry of AppSearch.fuzzyQuery(want).slice(0, 5)) {
            const n = String(entry.name ?? "").toLowerCase()
            const id = String(entry.id ?? "").toLowerCase().replace(/\.desktop$/, "")
            if (n === want || id === want || id.split(".").pop() === want || (want.length >= 4 && n.startsWith(want + " ")))
                return entry
        }
        return null
    }
}
