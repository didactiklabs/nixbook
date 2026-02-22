{
  pkgs,
  lib,
  sources,
  overrides ? { },
}:
let
  defaultImagePath = pkgs.stdenv.mkDerivation {
    name = "defaultImagePath";
    src = ../assets/images;
    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out
    '';
  };
  defaultSoundPath = pkgs.stdenv.mkDerivation {
    name = "defaultSoundPath";
    src = ../assets/sounds;
    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r $src/* $out
    '';
  };
  defaultConfig = {
    extraGroups = [
      "ydotool"
      "storage"
      "input"
      "wheel"
      "scanner"
      "lp"
      "video"
      "audio"
      "gamemode"
      "networkmanager"
    ];
    customHomeManagerModules = { };
  };

  mergedConfig = lib.recursiveUpdate defaultConfig overrides;

  mkUser =
    {
      username,
      userImports ? [ ],
      shell ? pkgs.zsh,
    }:
    {
      # Enable automount usb
      services = {
        gvfs.enable = true;
        udisks2.enable = true;
        devmon.enable = true;
      };
      environment = {
        systemPackages = with pkgs; [
          libsForQt5.qt5ct
          kdePackages.qt6ct
          adwaita-qt
        ];
        sessionVariables = {
          QT_QPA_PLATFORMTHEME = "qt5ct";
        };
        etc = {
          "xdg/qt5ct/qt5ct.conf".text = ''
            [Appearance]
            style=adwaita-dark
          '';
          "xdg/qt6ct/qt6ct.conf".text = ''
            [Appearance]
            style=adwaita-dark
          '';
        };
      };
      systemd.services.ydotoold = {
        enable = true;
      };
      programs = {
        ydotool = {
          enable = true; # clipboard prerequisite
        };
        zsh.enable = true;
      };
      users.users."${username}" = {
        inherit shell;
        inherit (mergedConfig) extraGroups;
        isNormalUser = true;
        description = "${username}";
      };
      home-manager = {
        useUserPackages = true;
        useGlobalPkgs = true;
        backupFileExtension = ".backup";
        users.${username} = {
          config = {
            xdg.mimeApps = {
              enable = true;
              defaultApplications = {
                "application/pdf" = "zathura.desktop"; # Set zathura as default for PDF
                "image/png" = "imv.desktop";
                "image/jpeg" = "imv.desktop";
                "image/gif" = "imv.desktop";
                "image/webp" = "imv.desktop";
                "video/mp4" = "mpv.desktop";
                "video/x-matroska" = "mpv.desktop";
                "video/webm" = "mpv.desktop";
                "video/quicktime" = "mpv.desktop";
                "video/x-msvideo" = "mpv.desktop";
                "video/x-flv" = "mpv.desktop";
                "video/mpeg" = "mpv.desktop";
                "video/ogg" = "mpv.desktop";
                "video/3gpp" = "mpv.desktop";
                "video/3gpp2" = "mpv.desktop";
                "text/html" = "firefox.desktop";
                "x-scheme-handler/http" = "firefox.desktop";
                "x-scheme-handler/https" = "firefox.desktop";
                "inode/directory" = "org.kde.dolphin.desktop";
                "x-scheme-handler/kdeconnect" = "org.kde.dolphin.desktop";
              };
            };
            services = {
              udiskie.enable = true;
              gnome-keyring.enable = true;
              kdeconnect.enable = true;
            };
            dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Roboto";
            inherit (mergedConfig) customHomeManagerModules;
            home.packages = [
              pkgs.pavucontrol
              pkgs.pulseaudio
              pkgs.numix-cursor-theme
              pkgs.hicolor-icon-theme
              pkgs.playerctl
              pkgs.wev
              pkgs.jq
              pkgs.wlprop
              pkgs.wf-recorder
              pkgs.sway-contrib.grimshot
            ];
            home = {
              stateVersion = "24.05";
              username = "${username}";
              homeDirectory = "/home/${username}";
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
            };
          };
          imports = lib.concatLists [
            mergedConfig.imports
            [
              (import sources.stylix).homeModules.stylix
              (import sources.nixvim).homeModules.nixvim
              (import "${sources.agenix}/modules/age-home.nix")
              ../homeManagerModules
            ]
            userImports
          ];
          options.profileCustomization = {
            mainWallpaper = lib.mkOption {
              type = lib.types.str;
              default = "${defaultImagePath}/nixos-wallpaper.png";
              description = ''
                Image to set as main wallpaper.
              '';
            };
            lockWallpaper = lib.mkOption {
              type = lib.types.str;
              default = "${defaultImagePath}/nixos-wallpaper.png";
              description = ''
                Image to set as lock wallpaper.
              '';
            };
            startup_audio = lib.mkOption {
              type = lib.types.path;
              default = "${defaultSoundPath}/startup.mp3";
              description = ''
                path to startup sound that hyprland play on startup
              '';
            };
            notification_audio = lib.mkOption {
              type = lib.types.path;
              default = "${defaultSoundPath}/notifications.mp3";
              description = ''
                path to startup sound that hyprland play on notifications
              '';
            };
          };
        };
      };
    };
in
{
  inherit mkUser;
}
