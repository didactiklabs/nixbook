{
  config,
  lib,
  pkgs,
  ...
}:
let
  # NOTE: Must use direct import here instead of the `sources` module arg,
  # because this is used in `imports` which cannot depend on `config`/_module.args.
  sources = import ../npins;
  niri-flake =
    (import sources.flake-compat {
      src = sources.niri-flake;
    }).defaultNix;
  cfg = config.customNixOSModules;
in
{
  imports = [
    niri-flake.nixosModules.niri
  ];
  config = lib.mkIf cfg.niri.enable {
    programs.niri.enable = true;
    programs.niri.package = pkgs.niri;
    systemd.user.services.niri-flake-polkit = {
      enable = false;
    };
    security.pam.services.sddm.enableGnomeKeyring = true;

    # Add essential tools for niri
    environment.systemPackages = with pkgs; [
      # mako # notification daemon
      fuzzel # application launcher
      grimblast # screenshot tool
      wl-clipboard # clipboard utilities
      wlr-randr # display management
      libnotify # provides notify-send
      xwayland-satellite # X11 support for Wayland
    ];

    # Add niri cachix
    nix.settings = {
      substituters = [
        "https://cache.nixos.org/"
        "https://niri.cachix.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      ];
    };
  };
  options.customNixOSModules.niri = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Niri scrollable-tiling Wayland compositor.

        Niri is a modern Wayland compositor where windows are arranged in an
        infinite horizontal scrollable strip rather than traditional workspaces.

        This module:
        - Imports the niri-flake NixOS module (sourced from npins, not nixpkgs)
        - Enables programs.niri with the nixpkgs niri package
        - Disables the niri-flake bundled polkit agent (the system polkit handles it)
        - Enables GNOME keyring unlock via SDDM PAM integration
        - Installs essential Wayland utilities: fuzzel (launcher), grimblast (screenshots),
          wl-clipboard, wlr-randr (display management), libnotify, xwayland-satellite
          (X11 app compatibility layer)
        - Adds the niri.cachix.org binary cache for fast pre-built niri packages

        Used on: totoro (primary), nishinoya (primary).
        See also: homeManagerModules/niri/ for per-user compositor configuration.
      '';
    };
  };
}
