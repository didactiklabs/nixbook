# nixbook-shell

nixbook's Quickshell (QML) desktop shell: bar, dock, sidebars, launcher,
notifications, lock screen, desktop widgets and the optional Persona style.

It is packaged and configured by this repository, not installed by hand:

- package: `customPkgs/nixbook-shell/` (this tree is `src/`)
- Home Manager module: `customHomeManagerModules.nixbookShellConfig`
  (`homeManagerModules/nixbookShellConfig.nix`, shared settings in
  `homeManagerModules/nixbookShellConfig/settings.nix`)
- runs as the `nixbook-shell` user service; `nixbook-shell ipc call <target> <fn>`
  drives it and `nixbook-shell config …` relates the live settings to Nix
- settings live in `~/.config/nixbook-shell/config.json` (keys set in Nix are
  locked in the Settings window, everything else is editable there)

See `AGENTS.md` at the repository root for the full description.

## Credits

nixbook-shell started as a fork of [pctrade/end4-pC](https://github.com/pctrade/end4-pC),
itself a personal fork of end-4's illogical-impulse, and has been maintained
here independently since (last synced from end4-pC revision `0ff392bc`).

- **[@end-4](https://github.com/end-4)** — the original
  [dots-hyprland](https://github.com/end-4/dots-hyprland) / illogical-impulse shell
- **[@pctrade](https://github.com/pctrade)** — the end4-pC fork this grew from
- **[@gh0stzk](https://github.com/gh0stzk)** — the weather API integration
- **[@simeulinuxkaliaiwr](https://github.com/simeulinuxkaliaiwr)** — shader transitions

Licensed under the GPL-3.0, like upstream (see `LICENSE`).
