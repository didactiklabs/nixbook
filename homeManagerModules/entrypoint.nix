{
  username ? "khoa",
  profileName ? "totoro",
  shell ? pkgs.zsh,
  pkgs ? import (import ../npins).nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  },
  lib ? pkgs.lib,
  sources ? import ../npins,
  extraHomeManagerModules ? [ ],
}:
{
  imports =
    let
      dmsFlake = import sources.flake-compat {
        src = sources.dms;
      };
      dmsPluginRegistryFlake = import sources.flake-compat {
        src = sources.dms-plugin-registry;
      };
    in
    [
      (import sources.stylix).homeModules.stylix
      (import sources.nixvim).homeModules.nixvim
      (import "${sources.agenix}/modules/age-home.nix").userProfileHomeManagerConfig
      dmsFlake.defaultNix.homeModules.dank-material-shell
      dmsPluginRegistryFlake.defaultNix.modules.default
    ]
    ++ extraHomeManagerModules;

  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      let
        browser = "firefox.desktop";
        images = "imv.desktop";
        video = "mpv.desktop";
        fileManager = "org.kde.dolphin.desktop";
      in
      {
        "application/pdf" = "zathura.desktop";
        "text/html" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "inode/directory" = fileManager;
        "x-scheme-handler/kdeconnect" = fileManager;
      }
      // lib.genAttrs [ "image/png" "image/jpeg" "image/gif" "image/webp" ] (_: images)
      // lib.genAttrs [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "video/x-flv"
        "video/mpeg"
        "video/ogg"
        "video/3gpp"
        "video/3gpp2"
      ] (_: video);
  };

  services = {
    udiskie.enable = true;
    gnome-keyring.enable = true;
    kdeconnect.enable = lib.mkDefault false;
  };

  dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Roboto";

  home = {
    stateVersion = "24.05";
    inherit username;
    homeDirectory = "/home/${username}";
    packages = with pkgs; [
      pavucontrol
      pulseaudio
      numix-cursor-theme
      hicolor-icon-theme
      playerctl
      wev
      jq
      wlprop
      wf-recorder
      sway-contrib.grimshot
    ];
    sessionPath = [
      "$HOME/go/bin"
      "$HOME/.local/go/bin"
    ];
    sessionVariables = {
      YDOTOOL_SOCKET = "/run/ydotoold/socket";
      NIXPKGS_ALLOW_UNFREE = 1;
    };
  };

  programs = {
    go = {
      enable = true;
      env.GOPATH = "/home/${username}/go";
    };
    home-manager.enable = true;
    zsh.enable = true;
  };
}
