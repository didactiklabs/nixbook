# Window layouts

A **window layout** remembers where every window is — monitor, workspace, column and its width, or floating position and size, and the app that opens it — under a name. Restoring it puts every window back in one go, **starting the apps that are closed**.

## Using layouts

- **Mod+G** opens the launcher as a layout picker (the `#` prefix):
  - pick a layout to restore it;
  - update or delete one with its row's buttons (or Shift+Delete);
  - _Save the windows as a new layout_, or type a new name first (spaces become `-`).
- The desktop's right-click menu has a **Window layouts** submenu.
- **Settings → Window layouts** lists them to restore, update, rename or delete.

## Options

- **Close the other windows when restoring** (`windowLayouts.closeOthers`, off by default) also closes windows the layout doesn't have, as their close button would.
- Apps whose first window is a splash screen (e.g. Vesktop's "Loading") are placed once their real window replaces it.
- A layout works with any monitors: it keeps one arrangement per set of monitors it was saved with (saving off the dock replaces the laptop's and keeps the docked one), and restoring uses the one for the monitors connected. Without one, the largest is restored, each workspace of an unplugged monitor on a new workspace of the focused monitor, with its columns, widths and floating windows.

## From key bindings and scripts

```bash
nixbook-shell ipc call layouts cycle
nixbook-shell ipc call layouts restore work
nixbook-shell ipc call layouts restoreNumber 2
nixbook-shell ipc call layouts save work
nixbook-shell ipc call layouts saveCurrent

nixbook-desktop-mcp layout list|save|restore|delete|rename|cycle [--close-others]
```

Layouts are stored in `~/.local/state/nixbook-shell/layouts/`. AI agents can save and restore them too (`save_layout`, `restore_layout`), but cannot call the `layouts` IPC target, and their restores never close windows.

## Projects

A **project** is a whole context to come back to: its window layout, the Zen tabs of its window, Do Not Disturb on or off while it is open, and a focus timer (a countdown or a pomodoro).

- **Save one** in **Settings → Window layouts → Projects** (a name, **Save**: the desktop as it is now), from the launcher (`#` lists projects first), or ask DAI ("save this as the hackathon project").
- **"Work on the hackathon"** in DAI's bubble (also "travaille sur le hackathon", "arbeite am Hackathon", "làm việc với hackathon"; no model when the name is a saved project) opens it as you left it, in one go: the windows put back where they were (apps not open started), its tabs that aren't open opened in the background (Zen started if needed), then Do Not Disturb and its timer. The windows as they were before are kept as the hidden layout `_before-undo` (`nixbook-desktop-mcp layout restore _before-undo` puts them back).
- **"Pause the hackathon"** ("mets le hackathon en pause", "pausiere den Hackathon", "tạm dừng hackathon") saves it as it is now (its layout and the tabs of its Zen window, not pinned or private ones), then does what its **pause rule** says: leave it all open, or close its tabs. Do Not Disturb and the timer go back to what they were before it opened.
- Each project's options are one click each in Settings: **DND** (on while open, off while open, left alone), **Timer** (none, 25, 50, 90 minutes, a pomodoro), **Pausing** (leaves it all open, or closes its tabs).

AI agents have the `project` tool (`list`, `open`, `save`, `pause`; the windows group). The `projects` IPC target is the user's, like `layouts`.

```bash
nixbook-shell ipc call projects open hackathon
nixbook-shell ipc call projects pause hackathon
nixbook-shell ipc call projects pauseCurrent

nixbook-desktop-mcp project list|show NAME|open NAME|save NAME|pause NAME|delete NAME|rename OLD NEW
nixbook-desktop-mcp project set NAME dnd on|off|none
nixbook-desktop-mcp project set NAME focus 50|pomodoro|0
nixbook-desktop-mcp project set NAME on-pause keep|tabs
```

Projects are stored in `~/.local/state/nixbook-shell/contexts/NAME.json` (private), each with its layout as the hidden layout `_project-NAME` (not listed with yours).
