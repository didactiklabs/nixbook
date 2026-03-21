{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  imports = [ ];
  config = lib.mkIf cfg.hyprland.enable {
    programs = {
      hyprland = {
        enable = true;
        portalPackage = pkgs.xdg-desktop-portal-wlr;
      };
    };
    security = {
      pam.services = {
        # yubikey login
        hyprlock.u2fAuth = true;
      };
    };
    nix.settings = {
      substituters = [ "https://hyprland.cachix.org" ];
      trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
    };
  };
  options.customNixOSModules.hyprland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Hyprland dynamic tiling Wayland compositor.

        Hyprland is a highly customisable compositor featuring animations, blur,
        rounded corners, and rich IPC.

        This module:
        - Enables programs.hyprland with wlr XDG desktop portal for screen sharing
        - Adds U2F PAM authentication support for hyprlock (screen locker)
        - Registers the hyprland.cachix.org binary cache for fast builds

        Used on: totoro (fallback), nishinoya (fallback).
        See also: homeManagerModules/hyprland/ for per-user compositor configuration.
      '';
    };
  };
}
