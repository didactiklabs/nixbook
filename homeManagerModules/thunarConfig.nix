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
      (pkgs.xfce.thunar.override {
        thunarPlugins = [
          pkgs.xfce.thunar-archive-plugin
          pkgs.xfce.thunar-volman
          pkgs.xfce.xfconf
          pkgs.xfce.tumbler
          pkgs.xfce.exo
        ];
      })
      pkgs.ntfs3g
      pkgs.gparted
      pkgs.gnome.file-roller
    ];
    home.file = {
      ".config/xfce4/helpers.rc".text = ''
        TerminalEmulator=kitty
      '';
    };
  };
}
