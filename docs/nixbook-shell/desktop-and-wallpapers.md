# Desktop widgets & wallpapers

## Desktop widgets

Widgets live on the desktop, behind your windows. Toggle and arrange them from the desktop's **right-click menu → Widgets** or **Settings → Desktop**:

| Widget            | What                                                                   |
| ----------------- | ---------------------------------------------------------------------- |
| Clock             | Digital, or the Material "cookie" clock with a second hand             |
| World clock       | Up to four cities                                                      |
| Weather           | Current conditions and forecast                                        |
| Calendar          | Month view with event dots ([Calendar](./calendar))                    |
| Next event        | The next meeting with a _Join_ button                                  |
| To-do             | Your task list                                                         |
| Notes             | Sticky notes                                                           |
| Timers            | Pomodoro, stopwatch, countdown and alarms (once or daily, with snooze) |
| Media             | Now playing                                                            |
| Visualizer        | Audio spectrum ring or bars                                            |
| Music recognition | Identify the song playing                                              |
| Resources         | CPU, memory…                                                           |
| User card         | Your account picture and greeting                                      |
| Custom text       | Any text                                                               |
| Images            | Your pictures, framed and styled                                       |

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
  - **Each screen plays its own copy**, made once in the background at exactly its size (lanczos scaling, cropped to cover it) and at 60 fps, then swapped in at the same position without a restart. With nothing left to scale, mpv draws it the cheapest way: about 13 % of the GPU instead of ~55 % for a 1080p video on a 2880×1800 screen, with no dropped frame.
  - **Slower videos become 60 fps**: under ~47 fps they are motion-interpolated to 60 (at 1080p at most, then scaled to the screen; only while plugged in, and only once the wallpaper has stayed a minute; until then they play at their own rate). Faster ones are brought down to 60.
  - The copies are made at idle priority in a systemd unit of their own (`nixbook-live-wallpaper-copies-*`, 3 GB of memory at most), never in the shell's service, and choosing another wallpaper cancels them.
  - **Paused when it can't be seen**: while windows cover the whole desktop of that screen (they show its blurred still frame, not the video), while locked and with the screens off.
  - Windows blur its still frame, so the GPU doesn't re-blur every frame. Copies live in `~/.cache/nixbook-shell/live-wallpapers` and go after a month unplayed.
- **Overview backdrop**: niri's overview (`Mod+Tab`) shows the wallpaper, blurred, around the workspaces instead of a flat colour; for a video, its still frame. Without nixbook's niri configuration, add a layer rule with `match namespace="^quickshell:wallpaperBackdrop$"` and `place-within-backdrop true`.
- Agents can set the wallpaper (`set_wallpaper`), e.g. from a [folder DAI may write](./ai-assistant#what-dai-can-and-can-t-do) (`ai.writableFolders`).

## Night light

The night-light toggle runs `wlsunset` at the chosen temperature, manually or automatically, without flickering.
