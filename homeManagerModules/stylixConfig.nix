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
        Whether to enable Stylix declarative theming.

        Stylix generates a consistent base16 colour palette from the wallpaper
        image and applies it automatically to supported applications (terminals,
        editors, bars, GTK, etc.).

        This configuration:
          - polarity: dark — always generates a dark colour scheme
          - image: pulled from profileCustomization.mainWallpaper (set per profile)
          - autoEnable: true — opt-in theming for all supported Stylix targets
          - Disabled targets:
              dank-material-shell — DMS manages its own theming via matugen
              k9s                 — Stylix's k9s target causes schema errors
          - Cursor: phinger-cursors-light, size 24

          Fonts (shared with fontConfig):
            - Monospace: Roboto Mono
            - Sans-serif: Roboto
            - Serif:      Roboto Serif

          DMS override: when dmsConfig is enabled, forces the base16 scheme to
          tomorrow-night.yaml (from base16-schemes) instead of the wallpaper-
          derived palette, keeping DMS colours consistent.

        Enabled by default — disable only if you want fully manual theming.
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
