{
  config,
  lib,
  pkgs,
  ...
}:
let
  sources = import ../npins;
  niri-flake-src = sources.niri-flake;
  niri-flake =
    (import sources.flake-compat {
      src = niri-flake-src;
    }).defaultNix;
  cfg = config.customNixOSModules;
in
{
  imports = [
    niri-flake.nixosModules.niri
  ];
  config = lib.mkIf cfg.niri.enable {
    programs.niri.enable = true;
    
    # Add essential tools for niri
    environment.systemPackages = with pkgs; [
      mako # notification daemon
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
        Whether to enable Niri config globally or not.
        Niri is a scrollable-tiling Wayland compositor.
      '';
    };
  };
}
