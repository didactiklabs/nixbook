{ config, lib, ... }:
let cfg = config.customHomeManagerModules;
in {
  imports = [ ./hyprlandConfig.nix ./hyprlockConfig.nix ];
  config = lib.mkIf cfg.hyprlandConfig.enable { };
  options.customHomeManagerModules.hyprlandConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable hyprland config globally or not
      '';
    };
  };
}
