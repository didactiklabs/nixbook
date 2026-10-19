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

    # KDE's application menu layout (Dolphin's "Open With" reads it). Copied at
    # build time: reading it with builtins.readFile was an import-from-
    # derivation, building/substituting plasma-workspace during evaluation.
    # The copy keeps plasma-workspace out of the closure, as before.
    xdg.configFile."menus/applications.menu".source = pkgs.runCommand "plasma-applications.menu" { } ''
      cp ${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu "$out"
    '';
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
