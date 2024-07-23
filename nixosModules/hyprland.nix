{ config, lib, pkgs, ... }:
let cfg = config.customNixOSModules;
in {
  imports = [ ];
  config = lib.mkIf cfg.hyprland.enable {
    programs = {
      hyprland = {
        enable = true;
        portalPackage = pkgs.xdg-desktop-portal-wlr;
      };
    };
    security.pam.services.hyprlock = { };
  };
  options.customNixOSModules.hyprland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable hyprland config globally or not
      '';
    };
  };
}
