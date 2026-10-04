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

- Separate wallpapers for the **desktop**, **lock screen** and **login screen** (empty falls back to the lock screen's, then the desktop's), and [per theme variant](./themes#wallpapers-per-theme).
- A **centred wallpaper** mode draws the image inside a Material shape (heart, cookie…) over a colour.
- **Live (video) wallpapers**: pick a video and it plays behind the desktop with mpvpaper, paused while not visible (locked, screens off). Windows blur its still frame, so the GPU doesn't re-blur every frame; a video larger than your screens is transcoded once in the background (VA-API when available) to the smallest size that covers them.
- Agents can set the wallpaper from a [shared folder](./agent-desktop#shared-folders).

## Night light

The night-light toggle runs `wlsunset` at the chosen temperature, manually or automatically, without flickering.
