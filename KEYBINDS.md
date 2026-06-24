# Keybindings Reference

> **Maintenance note for humans & AI agents:** This file is hand-maintained. Whenever
> you add, remove, or change a keybind anywhere in the repo, update the matching
> table here. Sources to check:
>
> - `homeManagerModules/niri/niriConfig.nix` (`programs.niri.settings.binds`)
> - `homeManagerModules/sway/swayConfig.nix` (`wayland.windowManager.sway.config.keybindings` + `modes`)
> - `homeManagerModules/hyprland/hyprlandConfig.nix` (`settings.bind`/`bindle`/`bindl`)
> - `homeManagerModules/kittyConfig.nix` (terminal binds + the `Mod+Return` spawn bind for every compositor)
> - `homeManagerModules/nixvim/default.nix` and `homeManagerModules/nixvim/plugins/*.nix`
> - Per-profile overrides in `profiles/*/*/{niriConfig,swayConfig,hyprlandConfig}.nix`

`Mod` / `$mod` / `Mod4` / `SUPER` all refer to the **Super (Windows) key**.

Many compositor binds are conditional on the `dmsConfig` (DankMaterialShell) module
being enabled. The current profiles all enable DMS, so the DMS variants are the
active ones; the non-DMS fallbacks are listed where they differ.

Keyboards are configured for the **French (AZERTY)** layout. In Sway and Hyprland the
workspace digit keys are therefore bound to their AZERTY symbol names
(`ampersand`=1, `eacute`=2, `quotedbl`=3, `apostrophe`=4, `parenleft`=5, `minus`=6,
`egrave`=7, `underscore`=8, `ccedilla`=9, `agrave`=10).

---

## Niri (scrollable tiling compositor — totoro, tanjiro, nishinoya, hanamichi)

Source: `homeManagerModules/niri/niriConfig.nix`, terminal bind from `kittyConfig.nix`.
Niri is column/scroll based; it has no numbered workspaces (workspaces stack vertically).

### Applications & shell

| Keybind      | Action                                                   |
| ------------ | -------------------------------------------------------- |
| `Mod+Return` | Launch Kitty terminal                                    |
| `Mod+D`      | Spotlight app launcher (DMS)                             |
| `Mod+Q`      | Toggle clipboard manager (DMS)                           |
| `Mod+N`      | Toggle notification center (DMS)                         |
| `Mod+B`      | Toggle top bar (+ dock when `showDock` is enabled) (DMS) |
| `Mod+O`      | Toggle dash overview (DMS)                               |
| `Mod+W`      | Open wallpaper picker / dankdash (DMS)                   |
| `Mod+L`      | Power menu (DMS)                                         |
| `Mod+Space`  | Toggle Sathi AI assistant widget (DMS)                   |
| `Ctrl+Space` | Toggle fcitx5 input method (when `fcitx5Config` enabled) |

> Note: `Mod+I` is overloaded — it maps to **focus workspace up** _and_, when DMS is
> enabled, also to **toggle idle inhibitor** (DMS). The DMS spawn bind is merged in last.

### Window management

| Keybind       | Action                             |
| ------------- | ---------------------------------- |
| `Mod+A`       | Close window                       |
| `Mod+F`       | Fullscreen window                  |
| `Mod+Z`       | Maximize column                    |
| `Mod+C`       | Center column                      |
| `Mod+R`       | Cycle preset column widths         |
| `Mod+E`       | Consume / expel window to the left |
| `Mod+Tab`     | Toggle overview (all windows)      |
| `Mod+Shift+E` | Quit niri (exit session)           |
| `Mod+Shift+P` | Power off monitors                 |

### Focus navigation

| Keybind         | Action                        |
| --------------- | ----------------------------- |
| `Mod+Left`      | Focus column left             |
| `Mod+Right`     | Focus column right            |
| `Mod+Up`        | Focus workspace up            |
| `Mod+Down`      | Focus workspace down          |
| `Mod+U`         | Focus workspace down          |
| `Mod+I`         | Focus workspace up            |
| `Mod+Page_Down` | Focus workspace down          |
| `Mod+Page_Up`   | Focus workspace up            |
| `Mod+Ctrl+Up`   | Focus window up (in column)   |
| `Mod+Ctrl+Down` | Focus window down (in column) |

### Moving windows / columns / workspaces

| Keybind               | Action                        |
| --------------------- | ----------------------------- |
| `Mod+Shift+Left`      | Move column left              |
| `Mod+Shift+Right`     | Move column right             |
| `Mod+Shift+Up`        | Move column to workspace up   |
| `Mod+Shift+Down`      | Move column to workspace down |
| `Mod+Ctrl+Page_Down`  | Move column to workspace down |
| `Mod+Ctrl+Page_Up`    | Move column to workspace up   |
| `Mod+Ctrl+U`          | Move column to workspace down |
| `Mod+Ctrl+I`          | Move column to workspace up   |
| `Mod+Shift+Page_Down` | Move whole workspace down     |
| `Mod+Shift+Page_Up`   | Move whole workspace up       |
| `Mod+Shift+U`         | Move whole workspace down     |
| `Mod+Shift+I`         | Move whole workspace up       |

### Multi-monitor

| Keybind                | Action                       |
| ---------------------- | ---------------------------- |
| `Ctrl+Alt+Left`        | Focus monitor left           |
| `Ctrl+Alt+Right`       | Focus monitor right          |
| `Ctrl+Alt+Up`          | Focus monitor up             |
| `Ctrl+Alt+Down`        | Focus monitor down           |
| `Ctrl+Alt+Shift+Left`  | Move column to monitor left  |
| `Ctrl+Alt+Shift+Right` | Move column to monitor right |
| `Ctrl+Alt+Shift+Up`    | Move column to monitor up    |
| `Ctrl+Alt+Shift+Down`  | Move column to monitor down  |

### Media / brightness / screenshot

| Keybind                 | Action                                                               |
| ----------------------- | -------------------------------------------------------------------- |
| `Print`                 | Screenshot: DMS screenshot tool, or area-to-clipboard via grim+slurp |
| `XF86MonBrightnessUp`   | Brightness +10%                                                      |
| `XF86MonBrightnessDown` | Brightness -10%                                                      |
| `XF86AudioRaiseVolume`  | Volume +3%                                                           |
| `XF86AudioLowerVolume`  | Volume -3%                                                           |
| `XF86AudioMute`         | Toggle mute                                                          |

---

## Sway (SwayFX i3-like compositor — anya)

Source: `homeManagerModules/sway/swayConfig.nix`, terminal bind from `kittyConfig.nix`.
`Mod` = `Mod4` (Super). On **anya** the keybindings are cleared/overridden in
`profiles/anya/khoa/swayConfig.nix` (it is a headless streaming box), so the table
below reflects the shared default module.

### Applications & shell

| Keybind        | Action                                                   |
| -------------- | -------------------------------------------------------- |
| `Mod4+Return`  | Launch Kitty terminal                                    |
| `Mod4+d`       | Spotlight app launcher (DMS)                             |
| `Mod4+q`       | Toggle clipboard manager (DMS)                           |
| `Mod4+n`       | Toggle notification center (DMS)                         |
| `Mod4+b`       | Toggle top bar (+ dock when `showDock`) (DMS)            |
| `Mod4+o`       | Toggle dash overview (DMS)                               |
| `Mod4+w`       | Wallpaper picker / dankdash (DMS)                        |
| `Mod4+i`       | Toggle idle inhibitor (DMS)                              |
| `Mod4+l`       | Power menu (DMS)                                         |
| `Mod4+space`   | Toggle Sathi AI assistant widget (DMS)                   |
| `Ctrl+space`   | Toggle fcitx5 input method (when `fcitx5Config` enabled) |
| `Mod4+Shift+v` | Run `wlprop` (window property inspector)                 |

### Window management

| Keybind            | Action                         |
| ------------------ | ------------------------------ |
| `Mod4+a`           | Kill (close) focused window    |
| `Mod4+c`           | Reload Sway config             |
| `Mod4+Shift+r`     | Restart Sway                   |
| `Mod4+s`           | Stacking layout                |
| `Mod4+e`           | Toggle split layout            |
| `Mod4+z`           | Tabbed layout                  |
| `Mod4+Shift+space` | Toggle floating                |
| `Mod4+Shift+p`     | Move window to scratchpad      |
| `Mod4+x`           | Move workspace to output right |

### Focus & move

| Keybind            | Action            |
| ------------------ | ----------------- |
| `Mod4+Left`        | Focus left        |
| `Mod4+Down`        | Focus down        |
| `Mod4+Up`          | Focus up          |
| `Mod4+Right`       | Focus right       |
| `Mod4+Shift+Left`  | Move window left  |
| `Mod4+Shift+Down`  | Move window down  |
| `Mod4+Shift+Up`    | Move window up    |
| `Mod4+Shift+Right` | Move window right |

### Workspaces (AZERTY digit row)

| Keybind                     | Action                           |
| --------------------------- | -------------------------------- |
| `Mod4+<digit symbol>`       | Switch to workspace 1–10         |
| `Mod4+Shift+<digit symbol>` | Move container to workspace 1–10 |

Digit symbols: `ampersand`(1) `eacute`(2) `quotedbl`(3) `apostrophe`(4)
`parenleft`(5) `minus`(6) `egrave`(7) `underscore`(8) `ccedilla`(9) `agrave`(10).

### Modes

| Keybind        | Action                |
| -------------- | --------------------- |
| `Mod4+r`       | Enter **Resize** mode |
| `Mod4+Shift+t` | Enter **System** mode |

**Resize mode** (`Return`/`Escape`/`Mod4+r` to exit):

| Key           | Action             |
| ------------- | ------------------ |
| `j` / `Left`  | Shrink width 10px  |
| `l` / `Right` | Grow width 10px    |
| `k` / `Down`  | Grow height 10px   |
| `i` / `Up`    | Shrink height 10px |

**System mode** (`Return`/`Escape` to exit):

| Key       | Action                      |
| --------- | --------------------------- |
| `l`       | Lock screen                 |
| `e`       | Logout (exit Sway)          |
| `s`       | Lock + suspend              |
| `h`       | Hibernate                   |
| `r`       | Reboot                      |
| `Shift+s` | Shutdown / power off        |
| `Shift+r` | Reboot into BIOS / firmware |

### Media / brightness / screenshot

| Keybind                        | Action                                                |
| ------------------------------ | ----------------------------------------------------- |
| `Print`                        | Screenshot: DMS tool, or `grimshot` area-to-clipboard |
| `XF86MonBrightnessUp`          | Brightness +10%                                       |
| `XF86MonBrightnessDown`        | Brightness -10%                                       |
| `Mod4+equal` / `XF86AudioNext` | Next track (playerctl, works while locked)            |
| `Mod4+minus` / `XF86AudioPrev` | Previous track (playerctl, works while locked)        |
| `XF86AudioPlay`                | Play/pause (works while locked)                       |
| `XF86AudioRaiseVolume`         | Volume +3% (works while locked)                       |
| `XF86AudioLowerVolume`         | Volume -3% (works while locked)                       |
| `XF86AudioMute`                | Toggle mute (works while locked)                      |

> Note: `Mod4+minus` is bound both to "previous track" and to workspace 6; the later
> workspace binding wins. Use the media keys for track control.

---

## Hyprland (dynamic tiling compositor — available, not a primary WM)

Source: `homeManagerModules/hyprland/hyprlandConfig.nix`, terminal bind from `kittyConfig.nix`.
`$mod` = `SUPER`. Uses the hy3 layout and hyprexpo plugins.

### Applications & shell

| Keybind       | Action                                                   |
| ------------- | -------------------------------------------------------- |
| `$mod+RETURN` | Launch Kitty terminal                                    |
| `$mod+D`      | Spotlight (DMS) / rofi drun (fallback)                   |
| `$mod+N`      | Toggle notifications (DMS / swaync fallback)             |
| `$mod+B`      | Toggle bar (+dock) (DMS) / toggle waybar (fallback)      |
| `$mod+O`      | Dash overview (DMS)                                      |
| `$mod+W`      | Wallpaper picker / dankdash (DMS)                        |
| `$mod+I`      | Toggle idle inhibitor (DMS)                              |
| `$mod+L`      | Power menu (DMS) / rofi lock script (fallback)           |
| `$mod+space`  | Toggle Sathi AI assistant widget (DMS)                   |
| `Ctrl+Space`  | Toggle fcitx5 input method (when `fcitx5Config` enabled) |

### Window / layout (hy3)

| Keybind                         | Action                          |
| ------------------------------- | ------------------------------- |
| `$mod+A`                        | Kill active window              |
| `$mod+TAB`                      | Toggle hyprexpo (expo overview) |
| `$mod+Z`                        | hy3: toggle tab group           |
| `$mod+E`                        | hy3: change group to opposite   |
| `$mod+Left/Right/Up/Down`       | Move focus (hy3)                |
| `$mod+Shift+Left/Right/Up/Down` | Move window (hy3)               |

### Workspaces (AZERTY digit row)

| Keybind                     | Action                        |
| --------------------------- | ----------------------------- |
| `$mod+<digit symbol>`       | Switch to workspace 1–10      |
| `$mod+Shift+<digit symbol>` | Move window to workspace 1–10 |

(Same AZERTY digit symbol mapping as Sway above.)

### Media / brightness / screenshot

| Keybind                 | Action                                                 |
| ----------------------- | ------------------------------------------------------ |
| `Print`                 | Screenshot: DMS tool, or `grimblast` area-to-clipboard |
| `XF86MonBrightnessUp`   | Brightness +10%                                        |
| `XF86MonBrightnessDown` | Brightness -10%                                        |
| `XF86AudioRaiseVolume`  | Volume +3%                                             |
| `XF86AudioLowerVolume`  | Volume -3%                                             |
| `XF86AudioMute`         | Toggle mute                                            |

---

## Kitty terminal

Source: `homeManagerModules/kittyConfig.nix`.

| Keybind            | Action                            |
| ------------------ | --------------------------------- |
| `Ctrl+Shift+S`     | Vertical split (in current dir)   |
| `Ctrl+Shift+Enter` | Horizontal split (in current dir) |
| `Ctrl+Shift+W`     | Close tab                         |
| `Ctrl+Shift+Right` | Next tab                          |
| `Ctrl+Shift+Left`  | Previous tab                      |
| `Alt+Left`         | Focus split to the left           |
| `Alt+Right`        | Focus split to the right          |
| `Alt+Up`           | Focus split above                 |
| `Alt+Down`         | Focus split below                 |
| `Shift+Left`       | Move/reorder split left           |
| `Shift+Right`      | Move/reorder split right          |
| `Shift+Up`         | Move/reorder split up             |
| `Shift+Down`       | Move/reorder split down           |

---

## Neovim (NixVim)

Sources: `homeManagerModules/nixvim/default.nix` and `homeManagerModules/nixvim/plugins/*.nix`.
**Leader** = `Space`.

### Core (default.nix)

| Keybind            | Action                     |
| ------------------ | -------------------------- |
| `<leader>a`        | LSP code action            |
| `Shift+H`          | Previous buffer            |
| `Shift+L`          | Next buffer                |
| `Ctrl+L`           | Clear search highlight     |
| `Ctrl+Shift+Up`    | Resize split +2 (height)   |
| `Ctrl+Shift+Down`  | Resize split -2 (height)   |
| `Ctrl+Shift+Left`  | Vertical resize -2 (width) |
| `Ctrl+Shift+Right` | Vertical resize +2 (width) |

### LSP (plugins/lsp.nix)

| Keybind     | Action                |
| ----------- | --------------------- |
| `gd`        | Go to definition      |
| `gD`        | Go to references      |
| `gt`        | Go to type definition |
| `gi`        | Go to implementation  |
| `K`         | Hover docs            |
| `<F2>`      | Rename symbol         |
| `<leader>k` | Previous diagnostic   |
| `<leader>j` | Next diagnostic       |

### Telescope (plugins/telescope.nix)

| Keybind      | Action       |
| ------------ | ------------ |
| `<leader>ff` | Find files   |
| `<leader>fg` | Live grep    |
| `<leader>b`  | Buffers      |
| `<leader>fh` | Help tags    |
| `<leader>fd` | Diagnostics  |
| `<leader>p`  | Recent files |
| `Ctrl+p`     | Git files    |
| `Ctrl+f`     | Live grep    |

### File tree / diagnostics

| Keybind      | Action                            | Plugin           |
| ------------ | --------------------------------- | ---------------- |
| `<leader>n`  | Focus & reveal in Neo-tree        | neo-tree         |
| `<leader>nt` | Toggle Neo-tree width (20 ↔ 40)   | neo-tree         |
| `<leader>t`  | Toggle Trouble diagnostics        | trouble          |
| `<leader>y`  | Focus Trouble diagnostics         | trouble          |
| `<leader>m`  | Markdown preview (markdown files) | markdown-preview |

### Buffers (barbar)

| Keybind     | Action          |
| ----------- | --------------- |
| `Tab`       | Next buffer     |
| `Shift+Tab` | Previous buffer |
| `Ctrl+W`    | Close buffer    |

### Editing — mini.nvim

| Keybind                   | Action                         |
| ------------------------- | ------------------------------ |
| `gsa`                     | Surround add                   |
| `gsd`                     | Surround delete                |
| `gsf` / `gsF`             | Surround find (right/left)     |
| `gsr`                     | Surround replace               |
| `gsh`                     | Surround highlight             |
| `gsn`                     | Surround update n_lines        |
| `Ctrl+Left/Right/Up/Down` | Move line/selection            |
| `f` / `F`                 | Jump forward / backward        |
| `t` / `T`                 | Jump till forward / backward   |
| `;` / `,`                 | Repeat jump forward / backward |

### OpenCode AI (plugins/opencode.nix)

| Keybind        | Action                           |
| -------------- | -------------------------------- |
| `Ctrl+a`       | Ask OpenCode (normal/visual)     |
| `Ctrl+x`       | Execute OpenCode action          |
| `Ctrl+o`       | Toggle OpenCode (normal/term)    |
| `go`           | Add range to OpenCode (operator) |
| `goo`          | Add line to OpenCode             |
| `Ctrl+Shift+u` | Scroll OpenCode up               |
| `Ctrl+Shift+d` | Scroll OpenCode down             |

### 99 plugin (plugins/99.nix)

| Keybind      | Action                   |
| ------------ | ------------------------ |
| `<leader>9v` | 99: Visual (visual mode) |
| `<leader>9x` | 99: Stop all requests    |
| `<leader>9s` | 99: Search               |
| `<leader>9m` | 99: Select model         |
| `<leader>9p` | 99: Select provider      |
