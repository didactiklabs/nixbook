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
          font-family: Hack Nerd Font Bold;
          font-size: 10pt;
          font-weight: 600;
          -gtk-icon-theme: "Numix Square";
        }
      '';

      fonts = {
        monospace = {
          name = "Hack Nerd Font";
          package = pkgs.nerd-fonts.hack;
        };
        sansSerif = {
          name = "Inter";
          package = pkgs.inter;
        };
        serif = {
          name = "Inter";
          package = pkgs.inter;
        };
      };
    }
    // lib.optionalAttrs (config.customHomeManagerModules.dmsConfig.enable or false) {
      base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    };
  };
}
