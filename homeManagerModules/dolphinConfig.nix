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
      pkgs.kdePackages.dolphin
      pkgs.kdePackages.dolphin-plugins
      pkgs.kdePackages.ark
      pkgs.kdePackages.kio-admin
      pkgs.kdePackages.ffmpegthumbs
      pkgs.kdePackages.kpeople
      pkgs.ntfs3g
      pkgs.gparted
    ];

    # Ensure dolphin plugins are found
    home.sessionVariables = {
      QT_PLUGIN_PATH = "${pkgs.kdePackages.dolphin-plugins}/${pkgs.qt6.qtbase.qtPluginPrefix}";
    };
  };
}
