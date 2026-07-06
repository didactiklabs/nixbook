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
      pkgs.kdePackages.kdegraphics-thumbnailers
      pkgs.kdePackages.kio-extras
      pkgs.kdePackages.kimageformats
      pkgs.kdePackages.qtimageformats
      pkgs.kdePackages.kpeople
      pkgs.kdePackages.kservice
      pkgs.ntfs3g
      pkgs.gparted
    ];

    xdg.configFile."menus/applications.menu".text =
      builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";
    # Ensure dolphin plugins and thumbnailers are found
    home.sessionVariables = {
      QT_PLUGIN_PATH = lib.concatMapStringsSep ":" (p: "${p}/${pkgs.qt6.qtbase.qtPluginPrefix}") [
        pkgs.kdePackages.dolphin-plugins
        pkgs.kdePackages.ffmpegthumbs
        pkgs.kdePackages.kdegraphics-thumbnailers
        pkgs.kdePackages.kimageformats
        pkgs.kdePackages.qtimageformats
        pkgs.kdePackages.kio-extras
      ];
    };
  };
}
