# Home Manager on other distributions

Nixbook's Home Manager modules work on any Linux distribution — Ubuntu, Fedora, Arch… — so you can reproduce the shell, editor and tooling without installing NixOS. No flakes are required.

## Prerequisites

1. **Install Nix**:

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **Install Home Manager** (standalone mode):

   ```bash
   nix-shell '<home-manager>' -A install
   ```

## Get the configuration

```bash
git clone https://github.com/didactiklabs/nixbook ~/.config/nixbook
mkdir -p ~/.config/home-manager
```

## Write `home.nix`

On NixOS machines, `lib/userConfig.nix` (`mkUser`) wires the modules up. Standalone, `~/.config/home-manager/home.nix` does the same: it imports the external modules nixbook's modules build on (Stylix, NixVim, agenix, niri, DankMaterialShell, Zen Browser), then every nixbook module — all off until you enable them.

```nix
{ config, pkgs, lib, ... }:

let
  # A literal path: imports cannot depend on `config`.
  nixbookPath = /home/alice/.config/nixbook;
  sources = import "${nixbookPath}/npins";
  flake = src: (import sources.flake-compat { inherit src; }).defaultNix;
in
{
  imports = [
    (import sources.stylix).homeModules.stylix
    (import sources.nixvim).homeModules.nixvim
    (import "${sources.agenix}/modules/age-home.nix")
    (flake sources.niri-flake).homeModules.niri
    (flake sources.dms).homeModules.dank-material-shell
    (flake sources.dms-plugin-registry).homeModules.default
    (flake sources.zen-browser-flake).homeModules.twilight
    "${nixbookPath}/homeManagerModules"
  ];

  # Defined by mkUser on NixOS; Stylix and the shells read them.
  options.profileCustomization = {
    mainWallpaper = lib.mkOption {
      type = lib.types.str;
      default = "${nixbookPath}/assets/images/nixos-wallpaper.png";
    };
    lockWallpaper = lib.mkOption {
      type = lib.types.str;
      default = "${nixbookPath}/assets/images/nixos-wallpaper.png";
    };
  };

  config = {
    home.username = "alice";
    home.homeDirectory = "/home/alice";
    home.stateVersion = "24.05"; # match your Home Manager version

    nixpkgs.config.allowUnfree = true;
    # nixbook's overlays and its own packages (pkgs.customPkgs.*)
    nixpkgs.overlays = [
      (import "${nixbookPath}/lib/overlays.nix" { inherit sources; })
      (import "${nixbookPath}/customPkgs")
    ];
    # niri's Home Manager module would otherwise build niri-flake's own niri
    programs.niri.package = pkgs.niri;

    # Switch on what you want (see the module options reference):
    customHomeManagerModules = {
      zshConfig.enable = true;
      starship.enable = true;
      kittyConfig.enable = true;
      gitConfig.enable = true;
      nixvimConfig.enable = true;
    };
  };
}
```

Pick modules from the [User](/user/shell) section or the [module options reference](/reference/options). Desktop modules (`niriConfig`, `dmsConfig`, `nixbookShellConfig`) also need the compositor installed system-wide by your distribution.

## Activate

```bash
home-manager build    # see what would change
home-manager switch   # apply (add -v for details)
```

On the first activation Home Manager may refuse to overwrite existing dotfiles; move them aside and switch again.

::: tip nixbook-shell on its own
The [nixbook-shell](/nixbook-shell/) desktop shell is self-contained and has its own Home Manager module — see [using it outside nixbook](/nixbook-shell/#using-it-outside-nixbook).
:::
