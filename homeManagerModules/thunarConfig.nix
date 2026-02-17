{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    home.packages = [
      (pkgs.thunar.override {
        thunarPlugins = [
          pkgs.thunar-archive-plugin
          pkgs.thunar-volman
          pkgs.xfconf
          pkgs.tumbler
          pkgs.xfce4-exo
        ];
      })
      pkgs.ntfs3g
      pkgs.gparted
      pkgs.file-roller
    ];
  };
}
