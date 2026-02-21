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
      targets = {
        dank-material-shell.enable = false;
        gtk.extraCss = "";
      };

      fonts = {
        monospace = {
          name = "Roboto Mono";
          package = pkgs.roboto-mono;
        };
        sansSerif = {
          name = "Roboto";
          package = pkgs.roboto;
        };
        serif = {
          name = "Roboto Serif";
          package = pkgs.roboto-serif;
        };
      };
    }
    // lib.optionalAttrs (config.customHomeManagerModules.dmsConfig.enable or false) {
      base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    };
  };
}
