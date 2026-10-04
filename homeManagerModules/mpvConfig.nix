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
        config = {
          # Hardware decoding (VA-API on AMD/Intel, NVDEC on NVIDIA) instead
          # of the CPU: far less power and heat for video. auto-safe only
          # picks decoders known to be correct, and falls back to software.
          hwdec = "auto-safe";
          vo = "gpu-next";
        };
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
