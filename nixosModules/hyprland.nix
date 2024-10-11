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
    security.pam.services.hyprlock = { };
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
        whether to enable hyprland config globally or not
      '';
    };
  };
}
