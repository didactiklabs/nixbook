# Leadr Keybinds

Leadr is activated with `Ctrl+g` in your terminal.

## Git Commands

| Shortcut | Command | Description |
|----------|---------|-------------|
| `ghm` | `gh pr create ; gh pr merge --auto` | Create GitHub PR and auto-merge |
| `ghc` | `gh pr create` | Create GitHub PR |
| `ga` | `git add .` | Git add all files |
| `gs` | `git status` | Show git status |

## Git Commit Commands (with goji)

| Shortcut | Command | Description |
|----------|---------|-------------|
| `gfeat` | `goji -a -m "#CURSOR" -t feat` | Start a feature commit |
| `gfix` | `goji -a -m "#CURSOR" -t feat` | Start a fix commit |
| `gdoc` | `goji -a -m "#CURSOR" -t docs` | Start a documentation commit |
| `grefactor` | `goji -a -m "#CURSOR" -t refactor` | Start a refactor commit |

## Text Manipulation

| Shortcut | Command | Description |
|----------|---------|-------------|
| `id` | `date +%Y%m%d` | Insert current date (YYYYMMDD format) |
| `sq` | `"#COMMAND"` | Surround selection with quotes |
| `ps` | `sudo ` | Prepend sudo to command |

## Configuration

- **Activation Key**: `Ctrl+g`
- **Theme**: catppuccin-mocha
- **Panel Delay**: 500ms
- **Panel Height**: 10 lines
- **Column Width**: 40 characters

The leadr configuration is managed through NixOS home-manager and automatically integrates with both Fish and Zsh shells.