# Sway Configuration Guide

This document provides a comprehensive overview of the Sway configuration for this NixOS setup, including all keybinds, features, and customizations.

## Overview

Sway is a tiling Wayland compositor and drop-in replacement for the i3 window manager. This configuration uses:

- **Base**: SwayFX (enhanced Sway with effects)
- **Layout**: Default i3-style tiling with tabbed and stacking modes
- **Keyboard Layout**: French (AZERTY)
- **Main Key Modifier**: `Mod4` (SUPER/Windows key)

## Configuration Files

- **Main Config**: `homeManagerModules/sway/swayConfig.nix`
- **Profile Overrides**: 
  - `profiles/anya/khoa/swayConfig.nix` (Headless setup)

## Features

### Visual Effects (SwayFX)
- **Blur**: Enabled for all windows with 5 passes, 6px radius
- **Shadows**: Enabled for all windows
- **Rounded Corners**: 10px radius on all windows
- **Opacity**: 0.8 for most windows, 1.0 for media applications
- **Layer Effects**: Waybar blur enabled

### Layout System
- **Default Layout**: Tiling (i3-style)
- **Available Layouts**: Stacking, Tabbed, Split (horizontal/vertical)
- **Window Gaps**: 5px inner, 5px outer
- **Smart Borders**: Disabled
- **Border Width**: 2px for windows, 2px for floating windows

### Auto-Lock and Power Management
- **Screen Lock**: 60 seconds of inactivity
- **Display Off**: 5 minutes (300 seconds) of inactivity
- **Lock Image**: Uses configured lock wallpaper
- **Integration**: SwayIdle service manages power states

## Keybinds

### Modifier Key
- **Primary Modifier**: `Mod4` (SUPER/Windows key)

### Workspace Navigation (French AZERTY Layout)
| Key Combination | Action | Workspace |
|------------------|--------|-----------|
| `SUPER + &` | Switch to workspace 1 | 1 |
| `SUPER + é` | Switch to workspace 2 | 2 |
| `SUPER + "` | Switch to workspace 3 | 3 |
| `SUPER + '` | Switch to workspace 4 | 4 |
| `SUPER + (` | Switch to workspace 5 | 5 |
| `SUPER + -` | Switch to workspace 6 | 6 |
| `SUPER + è` | Switch to workspace 7 | 7 |
| `SUPER + _` | Switch to workspace 8 | 8 |
| `SUPER + ç` | Switch to workspace 9 | 9 |
| `SUPER + à` | Switch to workspace 10 | 10 |

### Move Windows to Workspaces
| Key Combination | Action | Target Workspace |
|------------------|--------|------------------|
| `SUPER + SHIFT + &` | Move to workspace 1 | 1 |
| `SUPER + SHIFT + é` | Move to workspace 2 | 2 |
| `SUPER + SHIFT + "` | Move to workspace 3 | 3 |
| `SUPER + SHIFT + '` | Move to workspace 4 | 4 |
| `SUPER + SHIFT + (` | Move to workspace 5 | 5 |
| `SUPER + SHIFT + -` | Move to workspace 6 | 6 |
| `SUPER + SHIFT + è` | Move to workspace 7 | 7 |
| `SUPER + SHIFT + _` | Move to workspace 8 | 8 |
| `SUPER + SHIFT + ç` | Move to workspace 9 | 9 |
| `SUPER + SHIFT + à` | Move to workspace 10 | 10 |

### Window Navigation
| Key Combination | Action |
|------------------|--------|
| `SUPER + ←` | Focus window left |
| `SUPER + →` | Focus window right |
| `SUPER + ↑` | Focus window up |
| `SUPER + ↓` | Focus window down |

### Window Movement
| Key Combination | Action |
|------------------|--------|
| `SUPER + SHIFT + ←` | Move window left |
| `SUPER + SHIFT + →` | Move window right |
| `SUPER + SHIFT + ↑` | Move window up |
| `SUPER + SHIFT + ↓` | Move window down |

### Window Management
| Key Combination | Action |
|------------------|--------|
| `SUPER + A` | Kill/close window |
| `SUPER + SHIFT + SPACE` | Toggle floating mode |
| `SUPER + SHIFT + P` | Move to scratchpad |

### Layout Controls
| Key Combination | Action |
|------------------|--------|
| `SUPER + S` | Stacking layout |
| `SUPER + E` | Toggle split layout |
| `SUPER + Z` | Tabbed layout |

### System Controls
| Key Combination | Action |
|------------------|--------|
| `SUPER + C` | Reload configuration |
| `SUPER + SHIFT + R` | Restart Sway |

### Application Shortcuts
| Key Combination | Action |
|------------------|--------|
| `SUPER + D` | Open application launcher (Rofi) |
| `SUPER + L` | Lock screen (Rofi lock script) |
| `SUPER + Q` | Toggle CopyQ clipboard manager* |

*Only available when CopyQ is enabled

### Screenshots
| Key Combination | Action |
|------------------|--------|
| `PRINT` | Take area screenshot and copy to clipboard |

### System Controls
| Key Combination | Action |
|------------------|--------|
| `XF86MonBrightnessDown` | Decrease brightness by 10% |
| `XF86MonBrightnessUp` | Increase brightness by 10% |

### Media Controls (Works even when locked)
| Key Combination | Action |
|------------------|--------|
| `SUPER + =` | Next track |
| `SUPER + -` | Previous track |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86AudioPlay` | Play/pause toggle |

### Multi-Monitor Support
| Key Combination | Action |
|------------------|--------|
| `SUPER + X` | Move workspace to next output/monitor |

### Special Modes

#### Resize Mode (`SUPER + R`)
Enter resize mode to adjust window sizes:

| Key | Action |
|-----|--------|
| `J` or `←` | Shrink width by 10px |
| `K` or `↓` | Grow height by 10px |
| `I` or `↑` | Shrink height by 10px |
| `L` or `→` | Grow width by 10px |
| `ENTER`, `ESC`, or `SUPER + R` | Exit resize mode |

#### System Mode (`SUPER + SHIFT + T`)
System power management mode:

| Key | Action |
|-----|--------|
| `L` | Lock screen |
| `E` | Exit/logout from Sway |
| `S` | Suspend (with lock) |
| `H` | Hibernate |
| `R` | Reboot |
| `SHIFT + S` | Shutdown |
| `SHIFT + R` | Reboot to BIOS/UEFI |
| `ENTER` or `ESC` | Cancel and return to normal mode |

### Utility Shortcuts
| Key Combination | Action |
|------------------|--------|
| `SUPER + SHIFT + V` | Window properties inspector (wlprop) |

## Window Rules and Behavior

### Floating Windows
- **CopyQ**: Automatically floating, sticky, 550×600px, positioned at cursor

### Opacity Rules
- **Default**: 0.8 opacity with blur, shadows, and rounded corners
- **Full Opacity (1.0)**: Moonlight game streaming, Kitty terminal (Anya profile)

### SwayFX Effects
All windows by default receive:
- 0.8 opacity
- Shadow effects
- Blur with 5 passes and 6px radius  
- 10px corner radius

## Color Scheme

### Window Colors
- **Focused**: Light grey background (`#525865`), black border
- **Focused Inactive**: Dark grey background (`#222222`), black border
- **Unfocused**: Dark grey background (`#222222`), black border
- **Urgent**: Red background (`#bb0000`), red border
- **Text**: White (`#f3f4f5`) for all states

### Status Bar (Waybar Integration)
- **Background**: Dark grey (`#222222`)
- **Text**: White (`#f3f4f5`)
- **Active Workspace**: Light grey background (`#525865`)
- **Inactive Workspace**: Dark grey background (`#222222`)
- **Urgent**: Red background (`#bb0000`)

## Input Configuration

### Keyboard
- **Layout**: French (fr)
- **Numlock**: Enabled by default

### Touchpad
- **Tap-to-click**: Enabled
- **Acceleration**: Adaptive profile with 0.3 sensitivity
- **Natural scrolling**: Configurable per setup

## Environment Variables

```bash
CLUTTER_BACKEND=wayland
SDL_VIDEODRIVER=wayland
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
_JAVA_AWT_WM_NONREPARENTING=1
MOZ_ENABLE_WAYLAND=1
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=sway
XDG_CURRENT_DESKTOP=sway
WLR_NO_HARDWARE_CURSORS=1
```

## Output Configuration

### Display Settings
- **Background**: Configurable wallpaper with "fill" mode
- **Subpixel**: RGB rendering
- **Adaptive Sync**: Available but disabled by default

## Font Configuration

- **Primary Font**: Hack Nerd Font
- **Secondary Font**: FontAwesome
- **Style**: Bold
- **Size**: 9.0pt

## Profile-Specific Configurations

### Anya Profile (Headless)
- **SwayIdle**: Disabled for headless operation
- **Keyboard Bindings**: Completely disabled for automation
- **Backend**: Headless with libinput support
- **Virtual Output**: HEADLESS-1 at 2560×1440@60Hz
- **Kitty Opacity**: Reduced to 0.8

## Integration Features

### SwayIdle Integration
- **Lock on Idle**: 60 seconds
- **Display Power**: Off after 5 minutes
- **Manual Lock**: `SUPER + L` or system mode
- **Lock Image**: Uses profile-specific lock wallpaper

### Waybar Integration
- **Auto-start**: Starts with Sway
- **Reload Support**: `SUPER + C` reloads Waybar config
- **Blur Effect**: Waybar has blur effect enabled
- **Position**: Top bar with custom styling

### Rofi Integration
- **Application Launcher**: `SUPER + D`
- **Lock Screen**: Custom Rofi-based lock script
- **Theme**: Landscape style configuration

## Performance Notes

### SwayFX Effects
- **Blur**: 5 passes provide good quality/performance balance
- **Shadows**: Hardware accelerated when available
- **Opacity**: Minimal performance impact
- **Rounded Corners**: GPU accelerated

### Power Management
- **Automatic**: SwayIdle handles screen blanking and locking
- **Manual**: System mode provides immediate power options
- **Efficiency**: Wayland protocol provides better power management than X11

## Tips and Best Practices

1. **Layout Management**: Use `SUPER + S/E/Z` to quickly switch between stacking, split, and tabbed layouts
2. **System Mode**: `SUPER + SHIFT + T` provides quick access to all power management functions
3. **Resize Mode**: `SUPER + R` allows precise window resizing with keyboard
4. **Multi-Monitor**: `SUPER + X` quickly moves workspaces between monitors
5. **Scratchpad**: Use `SUPER + SHIFT + P` to hide windows and recall them later
6. **French Layout**: All bindings optimized for AZERTY keyboard layout

## Troubleshooting

### Common Issues
1. **Screen Tearing**: Enable adaptive sync if supported by your monitor
2. **Touch/Trackpad**: Adjust sensitivity in input configuration
3. **Application Launching**: Ensure Rofi configuration is properly set up
4. **Power Management**: Check SwayIdle service status if auto-lock isn't working

### Debug Information
Check Sway logs:
```bash
journalctl --user -u sway-session.target
```

### Performance Issues
1. **Reduce blur passes** from 5 to 2-3 for older hardware
2. **Disable shadows** if experiencing lag
3. **Adjust opacity** settings for better performance

## Dependencies

- **Required**: SwayFX, SwayIdle, SwayLock
- **Optional**: Waybar, Rofi, CopyQ, Grimshot, PlayerCtl
- **Audio**: PlayerCtl for media controls
- **Display**: Brightnessctl for brightness control
- **System**: SystemD for power management