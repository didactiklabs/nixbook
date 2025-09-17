# Niri Configuration Guide

This document provides a comprehensive overview of the Niri configuration for this NixOS setup, including all keybinds, features, and customizations.

## Overview

Niri is a scrollable-tiling Wayland compositor inspired by PaperWM. It features a unique horizontal scrolling layout where windows are arranged in columns that can be scrolled through infinitely. This configuration uses:

- **Layout**: Scrollable columns with vertical workspaces
- **Keyboard Layout**: French (AZERTY)
- **Main Key Modifier**: `Mod` (SUPER/Windows key)
- **Theme Integration**: Stylix for automatic color theming

## Configuration Files

- **Main Config**: `homeManagerModules/niri/niriConfig.nix`
- **Profile Overrides**: 
  - `profiles/totoro/khoa/niriConfig.nix` (Multi-monitor setup with app assignments)

## Unique Features

### Scrollable Tiling Layout
- **Horizontal Scrolling**: Windows arranged in columns, scroll left/right between columns
- **Vertical Workspaces**: Multiple workspace levels, scroll up/down between workspaces
- **Column-Based**: Each column can contain multiple windows stacked vertically
- **Infinite Scrolling**: No fixed number of columns or workspaces

### Visual Effects
- **Rounded Corners**: 12px radius on all windows
- **Opacity**: 0.85 for most windows, 1.0 for media applications and Firefox
- **Focus Ring**: 2px width with Stylix theme colors
- **Window Borders**: 1px width with Stylix theme colors
- **Animations**: Smooth spring-based animations for all transitions

### Advanced Window Management
- **Column Presets**: Predefined column widths (1/3, 1/2, 2/3, 4/5)
- **Default Width**: 4/5 of screen width
- **Window Grouping**: Consume/expel windows into/from columns
- **Floating Support**: Windows can float when needed

## Keybinds

### Modifier Key
- **Primary Modifier**: `Mod` (SUPER/Windows key)

### Core Navigation

#### Column Navigation (Horizontal Scrolling)
| Key Combination | Action |
|------------------|--------|
| `SUPER + ←` | Focus column to the left |
| `SUPER + →` | Focus column to the right |

#### Workspace Navigation (Vertical Scrolling)
| Key Combination | Action |
|------------------|--------|
| `SUPER + ↑` | Focus workspace above |
| `SUPER + ↓` | Focus workspace below |
| `SUPER + Page_Up` | Focus workspace above (alternative) |
| `SUPER + Page_Down` | Focus workspace below (alternative) |
| `SUPER + I` | Focus workspace above (alternative) |
| `SUPER + U` | Focus workspace below (alternative) |

#### Monitor Navigation (Multi-Monitor)
| Key Combination | Action |
|------------------|--------|
| `CTRL + ALT + ←` | Focus monitor to the left |
| `CTRL + ALT + →` | Focus monitor to the right |
| `CTRL + ALT + ↑` | Focus monitor above |
| `CTRL + ALT + ↓` | Focus monitor below |

### Window Movement

#### Move Columns
| Key Combination | Action |
|------------------|--------|
| `SUPER + SHIFT + ←` | Move column left |
| `SUPER + SHIFT + →` | Move column right |

#### Move to Workspaces
| Key Combination | Action |
|------------------|--------|
| `SUPER + SHIFT + ↑` | Move column to workspace above |
| `SUPER + SHIFT + ↓` | Move column to workspace below |
| `SUPER + CTRL + Page_Up` | Move column to workspace above |
| `SUPER + CTRL + Page_Down` | Move column to workspace below |
| `SUPER + CTRL + I` | Move column to workspace above |
| `SUPER + CTRL + U` | Move column to workspace below |

#### Move to Monitors
| Key Combination | Action |
|------------------|--------|
| `CTRL + ALT + SHIFT + ←` | Move column to monitor left |
| `CTRL + ALT + SHIFT + →` | Move column to monitor right |
| `CTRL + ALT + SHIFT + ↑` | Move column to monitor above |
| `CTRL + ALT + SHIFT + ↓` | Move column to monitor below |

#### Move Workspaces
| Key Combination | Action |
|------------------|--------|
| `SUPER + SHIFT + Page_Up` | Move entire workspace up |
| `SUPER + SHIFT + Page_Down` | Move entire workspace down |
| `SUPER + SHIFT + I` | Move entire workspace up |
| `SUPER + SHIFT + U` | Move entire workspace down |

### Window Management

#### Basic Window Operations
| Key Combination | Action |
|------------------|--------|
| `SUPER + A` | Close window |
| `SUPER + TAB` | Toggle overview (show all windows) |

#### Column Management
| Key Combination | Action |
|------------------|--------|
| `SUPER + ,` | Consume window into column (stack vertically) |
| `SUPER + .` | Expel window from column (unstack) |
| `SUPER + R` | Switch preset column width |
| `SUPER + Z` | Maximize column |
| `SUPER + C` | Center column |

#### Window States
| Key Combination | Action |
|------------------|--------|
| `SUPER + F` | Fullscreen window |

### Application Shortcuts
| Key Combination | Action |
|------------------|--------|
| `SUPER + D` | Open application launcher (Rofi) |
| `SUPER + L` | Lock screen (Rofi lock script) |
| `SUPER + Q` | Toggle CopyQ clipboard manager* |
| `SUPER + N` | Toggle notification center |
| `SUPER + B` | Toggle waybar visibility |

*Only available when CopyQ is enabled

### System Controls
| Key Combination | Action |
|------------------|--------|
| `SUPER + SHIFT + E` | Quit Niri |
| `SUPER + SHIFT + P` | Power off monitors |

### Screenshots
| Key Combination | Action |
|------------------|--------|
| `PRINT` | Take area screenshot with slurp selection |

### Hardware Controls
| Key Combination | Action |
|------------------|--------|
| `XF86MonBrightnessDown` | Decrease brightness by 10% |
| `XF86MonBrightnessUp` | Increase brightness by 10% |
| `XF86AudioRaiseVolume` | Increase volume |
| `XF86AudioLowerVolume` | Decrease volume |
| `XF86AudioMute` | Toggle mute |

## Layout Configuration

### Column Presets
Predefined column widths for quick adjustment:
1. **1/3 Width**: Narrow columns for side panels
2. **1/2 Width**: Half-screen columns
3. **2/3 Width**: Wide columns for main content
4. **4/5 Width**: Near full-screen (default)

### Gaps and Spacing
- **Window Gaps**: 10px between all windows
- **Focus Ring**: 2px width around focused window
- **Window Borders**: 1px width for visual separation

### Centering Behavior
- **Center Focused Column**: Never (allows infinite scrolling)
- **Default Column Width**: 4/5 of available width

## Window Rules

### Default Window Behavior
- **Opacity**: 0.85 (semi-transparent)
- **Corner Radius**: 12px on all corners
- **Column Width**: 4/5 proportion
- **Open Maximized**: Disabled (maintains column layout)
- **Geometry Clipping**: Enabled for clean rounded corners

### Application-Specific Rules

#### CopyQ (Clipboard Manager)
- **Column Width**: 40% of screen
- **Floating**: Enabled
- **Behavior**: Opens as floating overlay

#### Media Applications (Full Opacity)
- **Firefox**: All variants (firefox, org.mozilla.firefox, firefox-esr)
- **MPV**: Video player with screen capture blocking
- **IMV**: Image viewer with screen capture blocking
- **Jellyfin Media Player**: With screen capture blocking
- **Moonlight**: Game streaming with screen capture blocking

#### Terminal Applications
- **Ranger**: File manager with full opacity

#### Web Applications (Full Opacity)
- **Immich**: Photo management
- **YouTube**: Video streaming
- **Jellyfin**: Media streaming
- **Social Media**: Facebook, Instagram
- **Gaming**: Nexus Mods
- **Image Sharing**: Imgur
- **Discord**: Popout windows

### Privacy Features
Screen capture blocking is enabled for:
- Media players (MPV, IMV)
- Streaming applications (Jellyfin, Moonlight)
- Content that should remain private

## Multi-Monitor Configuration

### Totoro Profile Setup
Complex multi-monitor layout with different resolutions and positions:

#### Monitor Configuration
- **eDP-1**: Laptop screen, 1.6x scale, position (0, 755)
- **DP-8**: 1920×1080@60Hz, position (1800, 230)
- **DP-9**: 2560×1440@60Hz, position (3720, 0)
- **DP-10**: 1920×1080@60Hz, position (1800, 0)
- **DP-11**: 1920×1080@60Hz, position (3720, 0)

#### Application Assignments
**eDP-1 (Laptop Screen):**
- Thunderbird (email)
- Vesktop (Discord client)
- Spotify Premium
- Signal (messaging)

**DP-9 (Main Monitor):**
- Moonlight (game streaming)
- MPV (video player)

## Input Configuration

### Keyboard
- **Layout**: French (fr)
- **Options**: Microsoft numpad layout
- **Numlock**: Enabled by default

### Touchpad
- **Tap-to-click**: Enabled
- **Drag-while-tap**: Enabled
- **Natural Scrolling**: Enabled
- **Click Method**: Clickfinger (multi-finger clicking)

### Focus Behavior
- **Focus Follows Mouse**: Enabled
- **Mouse Tracking**: Cursor position affects window focus

## Animations

All animations use spring physics for natural movement:

### Window Animations
- **Open/Close**: Spring with 0.8 damping, 1000 stiffness
- **Movement**: Spring with 1.0 damping, 800 stiffness
- **Resize**: Spring with 1.0 damping, 800 stiffness

### View Animations
- **Horizontal Movement**: Column scrolling with 1.0 damping, 800 stiffness
- **Workspace Switch**: Vertical scrolling with 1.0 damping, 1000 stiffness

### Notification Animations
- **Config Notifications**: Spring with 0.6 damping, 1000 stiffness

### Performance
- **Global Slowdown**: 1.0 (normal speed)
- **Precision**: 0.0001 epsilon for smooth stopping

## Environment Variables

```bash
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=niri
QT_AUTO_SCREEN_SCALE_FACTOR=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_QPA_PLATFORMTHEME=qt6ct
SDL_VIDEODRIVER=wayland
_JAVA_AWT_WM_NONEREPARENTING=1
CLUTTER_BACKEND=wayland
GDK_BACKEND=wayland,x11
NIXOS_OZONE_WL=1
```

## Startup Applications

1. **Audio**: Startup sound using mpg123
2. **Status Bar**: Waybar for system information
3. **Wallpaper**: Background using swaybg with fill mode
4. **Notifications**: SwayNC client with delayed config reload

## Styling Integration

### Stylix Theme Colors
Niri integrates with the Stylix theming system:
- **Focus Ring Active**: `config.lib.stylix.colors.base0D`
- **Focus Ring Inactive**: `config.lib.stylix.colors.base03`
- **Border Active**: `config.lib.stylix.colors.base0D`
- **Border Inactive**: `config.lib.stylix.colors.base03`

### Layer Rules
- **Wallpaper Layer**: Positioned within backdrop for proper layering

## Advanced Features

### Screenshot Integration
- **Path**: `~/Pictures/Screenshots/Screenshot-%Y-%m-%d-%H-%M-%S.png`
- **Area Selection**: Slurp integration for region selection
- **Clipboard**: Automatic copy to clipboard with notification
- **Dependencies**: grim + slurp + wl-copy

### Volume Control
Custom volume script with fallback:
- **Primary**: Uses system `volume` script if available
- **Fallback**: wpctl/pamixer for direct audio control
- **Increment**: 3% volume steps

### Hotkey Overlay
- **Skip at Startup**: Disabled for clean startup experience
- **On-Demand**: Available when needed

## Workflow Tips

### Column-Based Workflow
1. **Horizontal Navigation**: Use `SUPER + ←/→` to scroll between column groups
2. **Vertical Workspaces**: Use `SUPER + ↑/↓` for different workspace levels
3. **Column Grouping**: Use `SUPER + ,/.` to stack/unstack windows in columns
4. **Quick Sizing**: Use `SUPER + R` to cycle through preset column widths

### Multi-Monitor Workflow
1. **Monitor Switching**: Use `CTRL + ALT + arrows` to quickly jump between monitors
2. **Content Movement**: Use `CTRL + ALT + SHIFT + arrows` to move content between monitors
3. **Application Assignment**: Specific apps auto-open on designated monitors

### Power User Features
1. **Overview Mode**: `SUPER + TAB` shows all windows across all workspaces
2. **Center Column**: `SUPER + C` for focusing on single column
3. **Maximize Toggle**: `SUPER + Z` for temporary full-width columns
4. **Workspace Management**: Move entire workspaces with `SUPER + SHIFT + I/U`

## Troubleshooting

### Common Issues
1. **Column Scrolling**: If scrolling feels unnatural, adjust animation parameters
2. **Multi-Monitor**: Ensure monitor positions match physical setup
3. **Application Assignment**: Check app-id matching for auto-assignment rules
4. **Animations**: Reduce stiffness values if animations feel too fast

### Performance Tuning
1. **Animation Speed**: Adjust global slowdown value
2. **Blur Effects**: Managed by compositor, generally efficient
3. **Spring Physics**: Tune damping/stiffness for preferred feel

### Debug Information
Check Niri logs:
```bash
journalctl --user -u niri
```

## Dependencies

- **Required**: Niri compositor from niri-flake
- **Screenshot**: grim, slurp, wl-copy
- **Audio**: wireplumber/pamixer for volume control
- **Notifications**: libnotify for screenshot notifications
- **Wallpaper**: swaybg for background management
- **Status**: Waybar for system information
- **Launcher**: Rofi for application launching
- **Lock**: Custom Rofi-based lock script
- **Clipboard**: CopyQ (optional)
- **Theme**: Stylix for color coordination

## Unique Advantages

### Compared to Traditional Tilers
1. **Infinite Scrolling**: No workspace limits
2. **Column Flexibility**: Dynamic width adjustment
3. **Vertical Workspaces**: True 2D navigation
4. **Spring Animations**: Natural, physics-based movement

### Workflow Benefits
1. **No Window Size Limits**: Columns can be any width
2. **Intuitive Navigation**: Arrow keys match movement direction
3. **Context Preservation**: Easy to return to previous layouts
4. **Multi-Monitor Fluidity**: Seamless cross-monitor workflows