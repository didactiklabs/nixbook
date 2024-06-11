{
  config,
  pkgs,
  lib,
  username,
  ...
}: let
  cfg = config.customHomeManagerModules.gtkConfig;
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

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.numix-gtk-theme
      pkgs.numix-icon-theme-square
      pkgs.numix-cursor-theme
    ];

    ## regarding cursor
    ## https://nixos.wiki/wiki/Cursor_Themes
    ## also https://gist.github.com/themattchan/55d21a524955111913afd7e1e22ce811
    ## https://github.com/NixOS/nixpkgs/issues/22652
    home.file.".icons/default".source = "${pkgs.numix-cursor-theme}/share/icons/Numix-Cursor";
    #xresources.properties = { "Xcursor.theme" = "Numix-Cursor"; };
    #xsession.pointerCursor = {
    #  package = pkgs.numix-cursor-theme;
    #  name = "Numix-Cursor";
    #  size = 10;
    #};

    gtk = {
      enable = true;
      theme.package = pkgs.numix-gtk-theme;
      theme.name = "Numix";
      iconTheme.package = pkgs.numix-icon-theme-square;
      iconTheme.name = "Numix-Square";
      font.name = "Hack Nerd Font Bold 10";
      font.size = 10;
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
      gtk3.bookmarks = [
        "file:///home/${username}/Documents"
        "file:///home/${username}/Downloads"
        "file:///home/${username}/Music"
        "file:///home/${username}/Pictures"
        "file:///home/${username}/Public"
        "file:///home/${username}/Templates"
        "file:///home/${username}/Videos"
      ];
      gtk2.extraConfig = ''
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
