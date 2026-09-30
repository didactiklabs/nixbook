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
              qt, zen-browser     — with nixbookShellConfig: the shell colours
                                    them like itself (wallpaper or theme palette)
          - Cursor: phinger-cursors-light, size 24

          Fonts (shared with fontConfig):
            - Monospace: Roboto Mono
            - Sans-serif: Roboto
            - Serif:      Roboto Serif

          Desktop-shell override: when a Quickshell shell is in use (dmsConfig
          or nixbookShellConfig), forces the base16 scheme to tomorrow-night.yaml (from
          base16-schemes) instead of the wallpaper-derived palette.

          This is not cosmetic. Stylix's auto-generated scheme is derived from
          `image`, and for many wallpapers it collapses into a near-monochrome
          palette — e.g. background #7e62f0 with color1..color6 all shades of
          the same purple, which makes terminals unreadable. Both shells draw
          their own Material You accent from the wallpaper anyway, so pinning a
          stable, legible base16 here keeps the two layers from compounding.

        Enabled by default — disable only if you want fully manual theming.
      '';
    };
  };

  config = lib.mkIf cfg.stylixConfig.enable {
    home.pointerCursor.enable = true;

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
      # stylix's package overlays (nixos-icons, gtksourceview) are set via the
      # Home Manager `nixpkgs.overlays`, which HM ignores under
      # `home-manager.useGlobalPkgs` (and warns about). Stylix itself disables
      # them the same way in its NixOS->HM integration.
      overlays.enable = false;
      targets = {
        zen-browser.profileNames = [ "default" ];
        # Nothing here enables rofi, and the pinned stylix still sets the
        # renamed `programs.rofi.font` (evaluation warning) whenever the target
        # is on.
        rofi.enable = false;
        dank-material-shell.enable = false;
        k9s.enable = false; # enable this parameter cause this error in k9s: "load failed:Additional property ui is not allowed"
        gtk.extraCss = "";
      }
      # nixbook-shell colours these like itself (wallpaper or theme palette):
      # Settings > Appearance > Color generation > Apps.
      // lib.optionalAttrs (config.customHomeManagerModules.nixbookShellConfig.enable or false) {
        qt.enable = false;
        zen-browser.enable = false;
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
    // lib.optionalAttrs (
      (config.customHomeManagerModules.dmsConfig.enable or false)
      || (config.customHomeManagerModules.nixbookShellConfig.enable or false)
    ) { base16Scheme = "${pkgs.base16-schemes}/share/themes/tomorrow-night.yaml"; };
  };
}
