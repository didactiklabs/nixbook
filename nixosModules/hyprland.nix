{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customNixOSModules;
in {
  imports = [
  ];
  config = lib.mkIf (cfg.hyprland.enable) {
    programs.hyprland.enable = true;
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
