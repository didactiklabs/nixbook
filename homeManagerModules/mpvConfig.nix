{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.customPkgs) ytui jtui;
  cfg = config.customHomeManagerModules;
  mpvScripts = with pkgs.mpvScripts; [
    thumbfast
    mpris
    modernx
  ];
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    programs = {
      mpv = {
        enable = true;
        scripts = mpvScripts;
        config = { };
      };
    };
    home = {
      packages = [
        jtui
        ytui
        pkgs.yt-dlp
      ];
    };
  };
}
