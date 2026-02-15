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
      targets.gtk.extraCss = ''
        .thunar {
          font-family: Hack Nerd Font Bold;
          font-size: 10pt;
          font-weight: 600;
          -gkt-icon-theme: "Numix Square";
        }
      '';

      fonts = {
        monospace = {
          name = "Hack Nerd Font";
          package = pkgs.nerd-fonts.fira-code;
        };
      };
    }
    // lib.optionalAttrs (config.customHomeManagerModules.dmsConfig.enable or false) {
      base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    };
  };
}
