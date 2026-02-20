{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    stylix = {
      enable = true;
      polarity = "dark";
      image = config.profileCustomization.mainWallpaper;
      cursor = {
        package = pkgs.phinger-cursors;
        name = "phinger-cursors-light";
        size = 24;
      };
      autoEnable = true;
      targets.dank-material-shell.enable = false;
      targets.gtk.extraCss = ''
        .thunar {
          font-family: Quicksand;
          font-size: 10pt;
          font-weight: 600;
          -gtk-icon-theme: "Papirus-Dark";
          -gtk-icon-theme: "Numix Square";
        }
      '';

      fonts = {
        monospace = {
          name = "Quicksand";
          package = pkgs.quicksand;
        };
        sansSerif = {
          name = "Quicksand";
          package = pkgs.quicksand;
        };
        serif = {
          name = "Quicksand";
          package = pkgs.quicksand;
        };
      };
    }
    // lib.optionalAttrs (config.customHomeManagerModules.dmsConfig.enable or false) {
      base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    };
  };
}
