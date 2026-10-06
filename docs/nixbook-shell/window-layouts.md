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
- A layout works with any monitors: restored with a monitor unplugged, each of its workspaces goes on a new workspace of the focused monitor, with its columns, widths and floating windows. The layout can't be overwritten until the monitor is back (save under another name).

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
