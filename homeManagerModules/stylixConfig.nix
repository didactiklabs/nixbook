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
  options.customHomeManagerModules.stylixConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable stylix theming configuration.
      '';
    };
  };

  config = lib.mkIf cfg.stylixConfig.enable {
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
        k9s.enable = false; # enable this parameter cause this error in k9s: "load failed:Additional property ui is not allowed"
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
      base16Scheme = "${pkgs.base16-schemes}/share/themes/tomorrow-night.yaml";
    };
  };
}
