# Kitty Terminal Configuration and Keybinds

This document provides a comprehensive overview of the Kitty terminal configuration and all keyboard shortcuts.

## Overview

Kitty is configured with powerline-style tab bars, mouse support, cursor effects, and comprehensive keyboard shortcuts for efficient terminal management.

## Configuration File

**Main Config**: `homeManagerModules/kittyConfig.nix`

## Visual Features

### Tab Bar
- **Style**: Powerline with round edges
- **Position**: Bottom of terminal
- **Visibility**: Always visible (even with single tab)
- **Template**: Shows tab title and window count

### Cursor Effects
- **Blinking**: Animated cursor with 0.5s interval
- **Trail**: Cursor trail effects matching neovide style
- **Mouse Hide**: Cursor hides after 3s of typing

### Mouse Support
- **Copy on Select**: Automatically copy selected text
- **Hide When Typing**: Mouse cursor disappears during keyboard activity
- **Window Resizing**: Drag borders to resize splits

## Keyboard Shortcuts

### Tab Management
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `Ctrl+Shift+T` | New tab | Create new terminal tab |
| `Ctrl+Shift+W` | Close tab | Close current tab |
| `Ctrl+Shift+Right` | Next tab | Switch to next tab |
| `Ctrl+Shift+Left` | Previous tab | Switch to previous tab |
| `Ctrl+Shift+1-9` | Go to tab | Switch to specific tab number |
| `Ctrl+Shift+0` | Go to tab 10 | Switch to tab 10 |

### Window/Split Management
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `Ctrl+Shift+Enter` | New window | Create new split/pane |
| `Alt+Left` | Navigate left | Move to left split |
| `Alt+Right` | Navigate right | Move to right split |
| `Alt+Up` | Navigate up | Move to split above |
| `Alt+Down` | Navigate down | Move to split below |

### Default Kitty Shortcuts
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `Ctrl+Shift+C` | Copy | Copy selected text |
| `Ctrl+Shift+V` | Paste | Paste from clipboard |
| `Ctrl+Shift+F` | Search | Search in terminal history |
| `Ctrl+Shift+H` | Show scrollback | View terminal history |
| `Ctrl+Shift+=` | Increase font size | Make text larger |
| `Ctrl+Shift+-` | Decrease font size | Make text smaller |
| `Ctrl+Shift+0` | Reset font size | Return to default size |
| `Ctrl+Shift+F5` | Reload config | Reload kitty.conf |

### Window Management (Advanced)
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `Ctrl+Shift+]` | Next window | Navigate to next split |
| `Ctrl+Shift+[` | Previous window | Navigate to previous split |
| `Ctrl+Shift+F` | Move window forward | Reorder split forward |
| `Ctrl+Shift+B` | Move window backward | Reorder split backward |
| `Ctrl+Shift+R` | Resize window | Start resize mode |
| `Ctrl+Shift+L` | Next layout | Switch split layout |

## Integration Features

### System Integration
- **Default Terminal**: Set as default terminal for XFCE4
- **VS Code**: Configured as external terminal
- **Window Managers**: Integrated with Hyprland, Sway, and Niri
  - `Super+Return` opens Kitty in all WMs

### SSH Integration
- **Smart SSH**: Enhanced ssh command with kitty kitten
- **Command**: `sshs` with template support
- **Terminal Compatibility**: Automatic TERM variable adjustment

### File Manager Integration
- **Ranger**: Image preview support through kitty
- **Preview Method**: `kitty` for image display
- **File Previews**: Enabled for better file browsing

## Quick Reference

### Essential Shortcuts
```
TERMINAL MANAGEMENT:
Ctrl+Shift+T     - New Tab          Alt+Arrows      - Navigate Splits
Ctrl+Shift+W     - Close Tab        Ctrl+Shift+Enter - New Split
Ctrl+Shift+←/→   - Switch Tabs      

SYSTEM:
Ctrl+Shift+C     - Copy             Ctrl+Shift+F    - Search
Ctrl+Shift+V     - Paste            Ctrl+Shift+H    - History
```

### Workflow Tips
1. **Multi-Tab Setup**: Use `Ctrl+Shift+T` for different projects
2. **Split Terminals**: Use `Ctrl+Shift+Enter` for side-by-side work
3. **Quick Navigation**: Use `Alt+Arrows` to move between splits
4. **Tab Switching**: Use `Ctrl+Shift+Left/Right` for tab navigation

## Font Configuration

- **Font Family**: Hack Nerd Font Bold
- **Font Size**: 10.0 (force override)
- **Features**: Full Nerd Font icon support

## Performance Settings

- **Copy on Select**: Immediate clipboard integration
- **Shell Integration**: Enhanced zsh integration
- **Mouse Hide**: Reduces distraction during typing
- **Cursor Effects**: GPU-accelerated animations

## Troubleshooting

### Common Issues
1. **Split Navigation Not Working**: Ensure Alt key isn't captured by system
2. **Tab Bar Not Visible**: Check `tab_bar_min_tabs = 1` setting
3. **Font Issues**: Verify Hack Nerd Font installation
4. **SSH Terminal Issues**: Use `sshs` command for enhanced compatibility

### Configuration Reload
- **Live Reload**: `Ctrl+Shift+F5` reloads configuration
- **Full Restart**: Close and reopen Kitty for major changes

## Advanced Features

### Powerline Tab Bar
- **Style**: Round powerline with visual separators
- **Information**: Shows active tab and window count
- **Customization**: Template-based title formatting

### Mouse Integration
- **Window Resizing**: Drag split borders to resize
- **Tab Interaction**: Click tabs to switch
- **Text Selection**: Click and drag to select text
- **Right-click Menu**: Context menu support

### Terminal Multiplexing
- **Tabs**: Multiple terminal sessions in one window
- **Splits**: Multiple terminals visible simultaneously  
- **Layouts**: Automatic layout management for splits
- **Persistence**: Tab and window state maintained

This configuration provides a modern, efficient terminal experience with comprehensive keyboard shortcuts and visual enhancements.