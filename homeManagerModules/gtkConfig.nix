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
  options.customHomeManagerModules.gtkConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable GTK appearance and theming configuration.

        Configures a consistent dark GTK theme across GTK2, GTK3, and GTK4:
          - Icon theme: Papirus-Dark
          - Cursor theme: Numix-Cursor (size 10)
          - Prefer dark theme flag set for all GTK versions
          - Font rendering: antialias + light hinting, RGB subpixel
          - Toolbar: BOTH_HORIZ style, LARGE_TOOLBAR icon size
          - GTK modules: gail and atk-bridge (accessibility)

        Installed theme packages:
          - numix-gtk-theme          — Numix GTK2/3 theme
          - papirus-icon-theme       — Papirus SVG icon set
          - material-design-icons    — Material Design icon font
          - numix-icon-theme-square  — Square variant of Numix icons
          - numix-cursor-theme       — Numix cursor set
          - dconf                    — GNOME settings daemon CLI

        Note: Stylix (stylixConfig) overrides some GTK colours at the system level;
        this module controls layout/UX preferences that Stylix does not manage.
      '';
    };
  };

  config = lib.mkIf cfg.gtkConfig.enable {
    home.packages = [
      pkgs.numix-gtk-theme
      pkgs.papirus-icon-theme
      pkgs.material-design-icons
      pkgs.numix-icon-theme-square
      pkgs.numix-cursor-theme
      pkgs.dconf
    ];

    gtk = {
      enable = true;
      iconTheme.package = pkgs.papirus-icon-theme;
      iconTheme.name = "Papirus-Dark";
      gtk4.extraConfig = {
        gtk-application-prefer-dark-theme = 1;
      };
      gtk3.extraConfig = {
        gtk-cursor-theme-size = 10;
        gtk-application-prefer-dark-theme = 1;
        gtk-button-images = 1;
        gtk-menu-images = 1;
        gtk-enable-event-sounds = 1;
        gtk-enable-input-feedback-sounds = 1;
        gtk-toolbar-style = "GTK_TOOLBAR_BOTH_HORIZ";
        gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
        gtk-xft-antialias = 1;
        gtk-xft-hinting = 1;
        gtk-xft-hintstyle = "hintslight";
        gtk-xft-rgba = "rgb";
        gtk-cursor-theme-name = "Numix-Cursor";
        gtk-modules = "gail:atk-bridge";
      };
      gtk2.extraConfig = ''
        gtk-application-prefer-dark-theme=1
        gtk-cursor-theme-name="Numix-Cursor"
        gtk-cursor-theme-size=10
        gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
        gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
        gtk-button-images=1
        gtk-menu-images=1
        gtk-enable-event-sounds=1
        gtk-enable-input-feedback-sounds=1
        gtk-xft-antialias=1
        gtk-xft-hinting=1
        gtk-xft-hintstyle="hintslight"
        gtk-xft-rgba="rgb"
        gtk-modules="gail:atk-bridge"
      '';
    };
  };
}
