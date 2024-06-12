{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.sway.enable {
    home.packages = [
      pkgs.numix-icon-theme-square
    ];

    programs.rofi = {
      enable = true;
      package = pkgs.rofi-wayland;
      font = "Hack Nerd Font Bold 9";
      theme =
        if cfg.pywalConfig.enable
        then lib.mkForce "${config.xdg.cacheHome}/wal/colors-rofi-light.rasi"
        else "purple";

      extraConfig = {
        modi = "drun";
        show-icons = true;
        icon-theme = "Numix-Square";
        combi-modi = "window,drun,ssh";
      };
    };
  };
}
