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
      zenBrowserFlake = import sources.flake-compat {
        src = sources.zen-browser-flake;
      };
    in
    [
      (import sources.stylix).homeModules.stylix
      (import sources.nixvim).homeModules.nixvim
      (import "${sources.agenix}/modules/age-home.nix").userProfileHomeManagerConfig
      dmsFlake.defaultNix.homeModules.dank-material-shell
      dmsPluginRegistryFlake.defaultNix.modules.default
      zenBrowserFlake.defaultNix.homeModules.twilight
    ]
    ++ extraHomeManagerModules;

  # Open plain-text files with VSCode when it is installed, otherwise fall back
  # to nvim launched inside a kitty terminal. The choice is made at runtime so
  # this entry works regardless of whether the vscode module is enabled.
  xdg.desktopEntries.editor-text = {
    name = "Text Editor (VSCode or nvim)";
    genericName = "Text Editor";
    comment = "Edit text files with VSCode if available, else nvim";
    exec = "${pkgs.writeShellScript "open-text-editor" ''
      if command -v code >/dev/null 2>&1; then
        exec code --new-window "$@"
      else
        exec ${pkgs.kitty}/bin/kitty ${pkgs.neovim}/bin/nvim "$@"
      fi
    ''} %F";
    mimeType = [ "text/plain" ];
    categories = [
      "Utility"
      "TextEditor"
    ];
    terminal = false;
  };

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
        "text/plain" = "editor-text.desktop";
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
    gnome-keyring = {
      enable = true;
      # Only PKCS#11 and Secret Service. The ssh component is deliberately
      # excluded: gpg-agent owns SSH_AUTH_SOCK
      # (programs.gnupg.agent.enableSSHSupport in nixosModules/tools.nix).
      components = [
        "pkcs11"
        "secrets"
      ];
    };
    kdeconnect.enable = lib.mkDefault true;
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
