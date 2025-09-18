# Nixvim Configuration and Keybinds

This document provides a comprehensive overview of the Nixvim/Neovim configuration and all keyboard shortcuts in this NixOS setup.

## Overview

Nixvim is a Neovim configuration system for Nix that provides declarative configuration management. This setup includes a comprehensive plugin ecosystem with LSP support, file management, search capabilities, and development tools.

## Configuration Structure

- **Main Config**: `homeManagerModules/nixvim/default.nix`
- **Options**: `homeManagerModules/nixvim/options.nix` 
- **Auto Commands**: `homeManagerModules/nixvim/autocmd.nix`
- **Plugins Directory**: `homeManagerModules/nixvim/plugins/`

## Leader Key Configuration

- **Leader Key**: `<Space>` (Spacebar)
- **Local Leader Key**: `<Space>` (Spacebar)

All leader-based shortcuts start with the spacebar.

## Global Keybinds

### LSP (Language Server Protocol) Actions
| Key Combination | Action | Mode | Description |
|------------------|--------|------|-------------|
| `<leader>ca` | `:lua vim.lsp.buf.code_action()<CR>` | Normal | Open code actions menu |

## Plugin-Specific Keybinds

### Buffer Management (Barbar)
**File**: `homeManagerModules/nixvim/plugins/barbar.nix`

| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<TAB>` | Next buffer | Switch to next buffer tab |
| `<S-TAB>` | Previous buffer | Switch to previous buffer tab |
| `<C-w>` | Close buffer | Close current buffer tab |

### Comment Plugin
**File**: `homeManagerModules/nixvim/plugins/comment.nix`

| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<C-b>` | Toggle line comment | Comment/uncomment current line |
| `<C-b>` | Operator line comment | Comment/uncomment in operator mode |

### Floating Terminal (Floaterm)
**File**: `homeManagerModules/nixvim/plugins/floaterm.nix`

| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<leader>,` | Toggle floaterm | Open/close floating terminal |

### LSP Navigation and Operations
**File**: `homeManagerModules/nixvim/plugins/lsp.nix`

#### Diagnostic Navigation
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<leader>k` | Go to previous diagnostic | Navigate to previous error/warning |
| `<leader>j` | Go to next diagnostic | Navigate to next error/warning |

#### Code Navigation
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `gd` | Go to definition | Jump to symbol definition |
| `gD` | Go to references | Show all references to symbol |
| `gt` | Go to type definition | Jump to type definition |
| `gi` | Go to implementation | Jump to implementation |
| `K` | Show hover information | Display documentation/info |

#### Code Modification
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<F2>` | Rename symbol | Rename symbol across project |

### Markdown Preview
**File**: `homeManagerModules/nixvim/plugins/markdown-preview.nix`

| Key Combination | Action | Mode | File Type | Description |
|------------------|--------|------|-----------|-------------|
| `<leader>m` | `:MarkdownPreview<cr>` | Normal | Markdown | Open live preview in browser |

### File Explorer (Neo-tree)
**File**: `homeManagerModules/nixvim/plugins/neo-tree.nix`

| Key Combination | Action | Mode | Description |
|------------------|--------|------|-------------|
| `<leader>n` | `:Neotree action=focus reveal<CR>` | Normal | Focus file tree and reveal current file |
| `<leader>c` | `:Neotree toggle<CR>` | Normal | Toggle file tree visibility |

### Fuzzy Finder (Telescope)
**File**: `homeManagerModules/nixvim/plugins/telescope.nix`

#### Leader-based Search
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<leader>ff` | Find files | Search files in project |
| `<leader>fg` | Live grep | Search text in all files |
| `<leader>b` | List buffers | Show open buffers |
| `<leader>fh` | Help tags | Search help documentation |
| `<leader>fd` | Show diagnostics | Display LSP diagnostics |
| `<leader>p` | Old files | Recently opened files |

#### FZF-style Shortcuts
| Key Combination | Action | Description |
|------------------|--------|-------------|
| `<C-p>` | Git files | Find files tracked by git |
| `<C-f>` | Live grep | Search text in all files |

### Diagnostics Panel (Trouble)
**File**: `homeManagerModules/nixvim/plugins/trouble.nix`

| Key Combination | Action | Mode | Description |
|------------------|--------|------|-------------|
| `<leader>t` | `:Trouble diagnostics toggle<CR>` | Normal | Toggle diagnostics panel |
| `<leader>y` | `:Trouble diagnostics focus<CR>` | Normal | Focus diagnostics panel |

## Keybind Summary by Category

### Leader Key Shortcuts (`<leader>` = Space)

#### File Operations
- `<leader>ff` - Find files (Telescope)
- `<leader>fg` - Live grep search (Telescope)
- `<leader>fh` - Search help tags (Telescope)
- `<leader>fd` - Show diagnostics (Telescope)
- `<leader>p` - Recently opened files (Telescope)

#### Buffer Management
- `<leader>b` - List buffers (Telescope)
- `<leader>c` - Toggle file tree (Neo-tree)
- `<leader>n` - Focus and reveal in file tree (Neo-tree)

#### Code Operations
- `<leader>ca` - LSP code actions
- `<leader>j` - Next diagnostic
- `<leader>k` - Previous diagnostic

#### Tools
- `<leader>,` - Toggle floating terminal
- `<leader>m` - Markdown preview (markdown files only)
- `<leader>t` - Toggle diagnostics panel
- `<leader>y` - Focus diagnostics panel

### Control Key Shortcuts
- `<C-b>` - Toggle line comment
- `<C-f>` - Live grep search (Telescope)
- `<C-p>` - Find git files (Telescope)
- `<C-w>` - Close buffer

### Function Keys
- `<F2>` - Rename symbol (LSP)

### Vim Standard Keys (Enhanced with LSP)
- `gd` - Go to definition
- `gD` - Go to references
- `gt` - Go to type definition
- `gi` - Go to implementation
- `K` - Show hover information

### Tab Navigation
- `<TAB>` - Next buffer
- `<S-TAB>` - Previous buffer

## Plugin Features

### Included Plugins

1. **Barbar**: Buffer/tab management with visual tabs
2. **Comment**: Intelligent commenting for all file types
3. **Floaterm**: Floating terminal integration
4. **LSP**: Full Language Server Protocol support
5. **Markdown Preview**: Live preview for markdown files
6. **Neo-tree**: Modern file explorer
7. **Telescope**: Fuzzy finder for everything
8. **Trouble**: Enhanced diagnostics display
9. **CMP**: Auto-completion engine
10. **Treesitter**: Syntax highlighting and parsing
11. **Noice**: Enhanced UI for messages and notifications
12. **Lualine**: Status line
13. **Notify**: Notification system
14. **Neocord**: Discord rich presence
15. **Git Conflict**: Git merge conflict resolution
16. **Startify**: Start screen
17. **Colorizer**: Color preview for color codes
18. **Trim**: Whitespace management
19. **None-ls**: Null-ls replacement for linting/formatting

### Language Support

The LSP configuration provides intelligent support for:
- **Go**: Full LSP with gopls
- **Python**: LSP with pyright/pylsp
- **JavaScript/TypeScript**: LSP with tsserver
- **Rust**: LSP with rust-analyzer
- **Nix**: LSP with nil/nixd
- **HTML/CSS**: LSP support
- **JSON/YAML**: LSP support
- **Markdown**: Preview and LSP support

### Auto-completion Features

- **Snippet Support**: Code snippets with expansion
- **LSP Integration**: Intelligent suggestions based on language servers
- **Buffer Text**: Completion from open buffers
- **Path Completion**: File and directory path completion
- **Command Completion**: Vim command completion

## Global Settings

### Editor Behavior
- **Default Editor**: Nixvim is set as system default editor
- **Vi/Vim Aliases**: `vi` and `vim` commands point to nixvim
- **Completion**: Menu-based completion with preview
- **Lua Loader**: Enabled for faster plugin loading

### Spell Checking
- **French Support**: Full French spell checking with dictionaries
- **Encodings**: UTF-8 and Latin1 support
- **Files**: 
  - `~/.config/nvim/spell/fr.utf-8.spl`
  - `~/.config/nvim/spell/fr.utf-8.sug`
  - `~/.config/nvim/spell/fr.latin1.spl`
  - `~/.config/nvim/spell/fr.latin1.sug`

### Whitespace Management
- **Better Whitespace**: Automatic whitespace handling
- **Strip on Save**: Removes trailing whitespace automatically
- **End of File**: Removes blank lines at file end
- **Tab/Space Mix**: Highlights mixed indentation

### Neovide Integration
GUI-specific settings for Neovide:
- **Window Size**: Not remembered between sessions
- **Scale Factor**: 0.8 for appropriate sizing
- **Fullscreen**: Disabled by default

## Development Workflow

### Typical Workflow
1. **Open Project**: Use `<leader>ff` to find and open files
2. **Navigate Code**: Use LSP keybinds (`gd`, `gt`, `gi`) for code navigation
3. **Search Content**: Use `<leader>fg` for project-wide text search
4. **File Management**: Use `<leader>c` to toggle file tree
5. **Terminal Access**: Use `<leader>,` for integrated terminal
6. **Buffer Management**: Use `<TAB>`/`<S-TAB>` to switch between files
7. **Code Actions**: Use `<leader>ca` for refactoring and fixes
8. **Diagnostics**: Use `<leader>t` to view all issues

### Quick Reference Card

**Essential Shortcuts:**
```
SPACE ff  - Find Files          TAB       - Next Buffer
SPACE fg  - Search Text         SHIFT+TAB - Previous Buffer  
SPACE c   - File Tree           CTRL+w    - Close Buffer
SPACE ,   - Terminal            F2        - Rename
SPACE ca  - Code Actions        gd        - Go to Definition
SPACE t   - Diagnostics         K         - Hover Info
```

## Troubleshooting

### Common Issues
1. **LSP Not Working**: Check if language server is installed
2. **Slow Startup**: Disable unused plugins in configuration
3. **Telescope Errors**: Ensure ripgrep and fd are installed
4. **French Spell Check**: Dictionaries download automatically

### Performance Tips
1. **Lazy Loading**: Most plugins are lazy-loaded for faster startup
2. **Treesitter**: Incremental parsing for better performance
3. **LSP**: Only enabled for supported file types
4. **Caching**: Lua loader provides module caching

### Getting Help
- **Help Tags**: Use `<leader>fh` to search help documentation
- **LSP Info**: `:LspInfo` shows language server status
- **Plugin Status**: `:checkhealth` diagnoses configuration issues

## Recent Updates

### New Plugins Added
- **Smear Cursor**: Animated cursor trail effects with exaggerated movement
- **Neoscroll**: Smooth scrolling animations for all navigation

### Enhanced Features
- **Mouse Support**: Full mouse support with resize functionality for windows/buffers
- **Cursor Styling**: Blinking cursor with smear trail effects

## Dependencies

### Required
- **Neovim**: Version 0.8+ with Lua support
- **Git**: For plugin management and git integration
- **Node.js**: For many language servers

### Optional but Recommended
- **ripgrep**: Fast text searching for Telescope
- **fd**: Fast file finding for Telescope
- **tree-sitter CLI**: Enhanced syntax highlighting
- **Language Servers**: For specific language support
- **Formatters**: prettier, black, rustfmt, etc.
- **Linters**: eslint, flake8, clippy, etc.