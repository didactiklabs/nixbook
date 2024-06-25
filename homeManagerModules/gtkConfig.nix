{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  options.customHomeManagerModules.gtkConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable gtkConfig globally or not
      '';
    };
  };

  config = lib.mkIf cfg.gtkConfig.enable {
    home.packages = [
      pkgs.numix-gtk-theme
      pkgs.numix-icon-theme-square
      pkgs.numix-cursor-theme
      pkgs.dconf
    ];

    gtk = {
      enable = true;
      iconTheme.package = pkgs.numix-icon-theme-square;
      iconTheme.name = "Numix-Square";
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
      gtk3.extraCss = ''
        .thunar {
          font-family: Hack Nerd Font Bold;
          font-size: 10pt;
          font-weight: 600;
          -gkt-icon-theme: "Numix Square";
        }
      '';
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
