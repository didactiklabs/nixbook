{
  config,
  lib,
  pkgs,
  ...
}:
let
  ytui = import ../customPkgs/ytui.nix { inherit pkgs; };
  jtui = import ../customPkgs/jtui.nix { inherit pkgs; };
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
