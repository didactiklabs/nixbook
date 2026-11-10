# Desktop widgets & wallpapers

## Desktop widgets

Widgets live on the desktop, behind your windows. Toggle and arrange them from the desktop's **right-click menu → Widgets** or **Settings → Desktop**:

| Widget      | What                                                                   |
| ----------- | ---------------------------------------------------------------------- |
| Clock       | Digital, or the Material "cookie" clock with a second hand             |
| World clock | Up to four cities                                                      |
| Weather     | Current conditions and forecast                                        |
| Calendar    | Month view with event dots ([Calendar](./calendar))                    |
| Next event  | The next meeting with a _Join_ button                                  |
| To-do       | Your task list                                                         |
| Notes       | Sticky notes                                                           |
| Timers      | Pomodoro, stopwatch, countdown and alarms (once or daily, with snooze) |
| Media       | Now playing                                                            |
| Visualizer  | Audio spectrum ring or bars                                            |
| Resources   | CPU, memory…                                                           |
| User card   | Your account picture and greeting                                      |
| Custom text | Any text                                                               |
| Images      | Your pictures, framed and styled                                       |

- **Drag** to move and resize; widgets can be placed **per monitor** — each monitor has its own position, size and on/off switch (the menu's switches apply to the monitor it was opened on).
- Widgets can follow the wallpaper's **calm areas** so they don't cover the busy parts.
- **Card opacity** (Background → Widgets → Canvas, 0.75 by default) makes cards translucent.
- After login, widgets fade in one at a time once the shell has loaded.
- The visualizer **pauses behind windows** (and cava stops), which matters a lot for GPU load.

AI agents can read and edit notes and tasks, set timers and alarms and arrange widgets through the [`widget` tool](./desktop-agents#what-agents-can-do).

## Wallpapers

**Mod+W** opens the **wallpaper selector**: browse folders with thumbnails (regenerated automatically when missing), or fetch wallpapers from **online providers** — downloads continue in the background and can be applied to the desktop or the lock screen. Picking a wallpaper regenerates the palette (Material theme) with a smooth transition.

In folders, the **back arrow** beside the title (or Alt+Left, or the mouse's back button) returns to the previous folder, Alt+Right goes forward again and Alt+Up opens the parent folder.

- Separate wallpapers for the **desktop**, **lock screen** and **login screen** (empty falls back to the lock screen's, then the desktop's), and [per theme variant](./themes#wallpapers-per-theme).
- A **centred wallpaper** mode draws the image inside a Material shape (heart, cookie…) over a colour.
- **Live (video) wallpapers** are picked like images: the selector lists videos (mp4, webm, mkv, avi, mov) beside the images, with a thumbnail and a **Live** badge, and previews them with their first frame. Applying one transitions to that frame like any wallpaper, then the video starts from it. Settings → Background → Live Wallpaper Folder adds a **Live** button among the selector's folders. The video plays behind the desktop with mpvpaper, at 60 fps and sharp, for little battery:
  - **Prepared ahead of time**: the videos of the wallpaper folders (Pictures/Wallpapers, the Live Wallpaper Folder, the current one's) get their still frame and, only while plugged in, a copy for each screen at exactly its size (lanczos scaling, cropped to cover it) and at 60 fps: under ~47 fps they are motion-interpolated to 60 at the screen's own size (a 4K video keeps its detail; a smaller one is interpolated at its size, then scaled up), faster ones brought down to 60. This runs at idle priority in a systemd unit of its own (`nixbook-live-wallpapers-prepare`; pieces of a video are converted side by side only while enough memory is free — at least 2 GB left for your apps — and one goes back in the queue when they need it), the current wallpaper first, a while after login, when AC power comes back, when screens change and after a video is applied; the first run over a large library takes a while (to interpolate, about 18 s of CPU per second of 1080p video, ~50 s at 2880×1800). A video not prepared yet plays as it is; once its copy is ready, the playing video switches to it on the spot, from the same moment (it just gets sharper). The player draws at the screen's own pixels, also on a fractionally scaled screen (nixbook patches mpvpaper for it: it used to draw at the next whole scale and have the compositor shrink it, which softened the picture). With nothing left to scale, mpv draws the copy the cheapest way: about 13 % of the GPU instead of ~55 % for a 1080p video on a 2880×1800 screen, with no dropped frame.
  - **Instant switching**: going from one live wallpaper to another changes the file inside the running player (no new window, nothing to re-stack); the new video waits on its first frame under the transition, then plays.
  - **Paused when it can't be seen**: while windows cover the whole desktop of that screen (they show its blurred still frame, not the video), while locked and with the screens off — and while saving power: in power-saver mode or on a low battery. Unplugging stops the conversion at once (systemd stops its unit); it resumes once plugged in again, skipping what is done — within a video too: interpolation goes in 4-second pieces, kept until the copy is whole. A charger that can't keep up counts as unplugged: when the battery level falls 3 points while plugged in without rising, or stays under the low-battery threshold for 10 minutes without rising, the shell notifies "Charger not keeping up", stops the conversion and pauses the video until the battery charges again (a low-power USB-C charger once let the conversion empty the battery while it showed as charging).
  - Windows blur its still frame, so the GPU doesn't re-blur every frame. Copies live in `~/.cache/nixbook-shell/live-wallpapers` and go with their video.
- **Overview backdrop**: niri's overview (`Mod+Tab`) shows the wallpaper, blurred, around the workspaces instead of a flat colour; for a video, its still frame. Without nixbook's niri configuration, add a layer rule with `match namespace="^quickshell:wallpaperBackdrop$"` and `place-within-backdrop true`.
- Agents can set the wallpaper (`set_wallpaper`), e.g. from a [folder DAI may write](./ai-assistant#what-dai-can-and-can-t-do) (`ai.writableFolders`).

## Night light

The night-light toggle runs `wlsunset` at the chosen temperature, manually or automatically, without flickering.
