# Hyprland Configuration Guide

This document provides a comprehensive overview of the Hyprland configuration for this NixOS setup, including all keybinds, features, and customizations.

## Overview

Hyprland is a dynamic tiling Wayland compositor that focuses on aesthetics, performance, and customizability. This configuration uses:

- **Layout**: hy3 (hierarchical tiling layout)
- **Plugins**: hy3, hyprexpo
- **Keyboard Layout**: French (AZERTY)
- **Main Key Modifier**: `SUPER` key

## Configuration Files

- **Main Config**: `homeManagerModules/hyprland/hyprlandConfig.nix`
- **Profile Overrides**: 
  - `profiles/totoro/khoa/hyprlandConfig.nix` (Multi-monitor setup)
  - `profiles/nishinoya/aamoyel/hyprlandConfig.nix` (Custom setup)

## Features

### Visual Effects
- **Blur**: Enabled with 9px radius, 1 pass
- **Rounded Corners**: 10px radius on windows
- **Opacity**: 0.85 for active and inactive windows
- **Animations**: Smooth spring-based animations for windows, workspaces, and borders
- **Shadows**: Available (configuration varies by profile)

### Layout System
- **Default Layout**: hy3 (hierarchical tiling)
- **Window Gaps**: 5px inner, 10px outer
- **Border**: Disabled (0px width)
- **Resize on Border**: Enabled

### Plugins

#### hy3 Plugin
- **Purpose**: Advanced hierarchical tiling layout
- **Tab Styling**: 20px rounding, custom colors based on Stylix theme
- **Features**: Tab groups, window organization

#### hyprexpo Plugin  
- **Purpose**: Workspace overview/exposé functionality
- **Layout**: 4 columns
- **Gap**: 5px between workspaces
- **Gesture Support**: 3-finger touchpad gestures (300px distance)

## Keybinds

### Modifier Key
- **Primary Modifier**: `SUPER` (Windows key)

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

### Window Navigation (hy3 Layout)
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
| `SUPER + A` | Kill active window |
| `SUPER + Z` | Toggle tab group |
| `SUPER + E` | Switch to opposite pane in group |

### Special Features
| Key Combination | Action |
|------------------|--------|
| `SUPER + TAB` | Toggle hyprexpo (workspace overview) |
| `SUPER + D` | Open application launcher (Rofi) |
| `SUPER + L` | Lock screen (Rofi lock script) |
| `SUPER + N` | Toggle notification center |
| `SUPER + B` | Toggle waybar visibility |
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

## Window Rules

### Floating Windows
- **CopyQ**: Floating, centered, 40% width × 60% height

### Opaque Windows (No transparency)
- Media players: `mpv`, `imv`, Jellyfin Media Player, Moonlight
- Terminal applications: `ranger`
- Specific Firefox tabs: Immich, YouTube, Jellyfin, Facebook, Instagram, Nexus Mods, Imgur
- Discord popouts

## Environment Variables

```bash
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=Hyprland
QT_AUTO_SCREEN_SCALE_FACTOR=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_QPA_PLATFORMTHEME=qt6ct
SDL_VIDEODRIVER=wayland
_JAVA_AWT_WM_NONEREPARENTING=1
CLUTTER_BACKEND=wayland
GDK_BACKEND=wayland,x11
```

## Startup Applications

1. **Audio**: Plays startup sound using mpg123
2. **Waybar**: Status bar (if not already running)
3. **Wallpaper**: Sets background using swaybg
4. **Notifications**: Reloads SwayNC configuration

## Multi-Monitor Setup

The configuration supports complex multi-monitor setups with different scaling factors and positions. Monitor configurations are profile-specific:

### Totoro Profile
- **eDP-1**: 1.6x scale, position 0x755
- **DP-8**: 1920x1080 at 1800x230
- **DP-9**: 2560x1440 at 3720x0  
- **DP-10**: 1920x1080 at 1800x0
- **DP-11**: 1920x1080 at 3720x0

### Nishinoya Profile
- **eDP-1**: 1.666667x scale, position 3000x0
- **DP-9**: 1920x1080 at 0x0, rotated 90°
- **DP-10**: 1920x1080 at 1080x0

## Application Assignments

### Workspace Auto-Assignment
- **Workspace 1**: Communication apps (Thunderbird, Vesktop, Spotify, Signal)
- **Workspace 3**: Media applications (Moonlight, MPV)

## Styling Integration

This configuration integrates with **Stylix** for automatic theming:
- Window border colors
- Tab colors for hy3 plugin
- Focus ring colors
- All colors automatically adapt to your system theme

## Performance Optimizations

- **VFR (Variable Frame Rate)**: Enabled for better performance
- **New Blur Optimizations**: Enabled
- **Blur Ignore Opacity**: Enabled for better visual quality
- **Hardware Cursor**: Uses system default
- **Log Reduction**: Hyprland logo disabled, minimal logging

## Tips and Best Practices

1. **hy3 Layout**: Use `SUPER + Z` to create tab groups, `SUPER + E` to navigate between panes
2. **Workspace Overview**: `SUPER + TAB` provides a macOS-like exposé view of all workspaces
3. **French Layout**: All workspace bindings are optimized for AZERTY keyboards
4. **Screenshots**: The print key provides area selection with automatic clipboard copy
5. **Multi-Monitor**: Applications automatically restore to their assigned monitors on startup

## Troubleshooting

### Common Issues
1. **Blur Performance**: If experiencing lag, reduce blur passes in decoration settings
2. **Touch Gestures**: Ensure touchpad drivers are properly configured for 3-finger gestures
3. **Multi-Monitor**: Monitor positions may need adjustment based on physical setup
4. **Application Launching**: Ensure Rofi configuration is properly set up for `SUPER + D`

### Debug Mode
Debug logging is enabled by default. Check Hyprland logs with:
```bash
journalctl --user -u hyprland
```

## Dependencies

- **Required**: Hyprland, hy3 plugin, hyprexpo plugin
- **Optional**: Waybar, Rofi, CopyQ, SwayNC, Grimblast
- **Styling**: Stylix theme system
- **Audio**: mpg123 for startup sounds