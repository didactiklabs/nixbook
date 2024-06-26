{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.desktopApps.enable {
    programs.mpv = {
      enable = true;
      scripts = [
        pkgs.mpvScripts.thumbfast
        pkgs.mpvScripts.modernx
        pkgs.mpvScripts.mpris
      ];
    };
  };
}
