{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  nixoscfg = config.customNixOSModules;
in {
  imports = [
  ];
  config =
    lib.mkIf (nixoscfg.hyprland.enable && !nixoscfg.sway.enable) {
    };
  options.customNixOSModules.hyprland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable sway config globally or not
      '';
    };
  };
}
