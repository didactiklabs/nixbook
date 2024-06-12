{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  options.customHomeManagerModules.pywalConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable gtkConfig globally or not
      '';
    };
  };

  config = lib.mkIf cfg.pywalConfig.enable {
    wayland.windowManager.sway.config.startup = lib.mkIf cfg.sway.enable [
      {
        command = "${pkgs.pywal}/bin/wal -i ${config.profileCustomization.mainWallpaper}";
      }
    ];
    home.packages = [
      pkgs.pywal
      pkgs.pywalfox-native
    ];
    programs.pywal.enable = true;
  };
}
