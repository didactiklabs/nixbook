{
  pkgs,
  lib,
  sources,
  overrides ? { },
}:
let
  # Use runCommand for simple asset copying - faster evaluation than mkDerivation
  defaultImagePath = pkgs.runCommand "default-images" { src = ../assets/images; } ''
    mkdir -p $out
    cp -r $src/* $out
  '';

  defaultSoundPath = pkgs.runCommand "default-sounds" { src = ../assets/sounds; } ''
    mkdir -p $out
    cp -r $src/* $out
  '';

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
    imports = [ ];
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
        geoclue2.enable = true;
      };

      environment = {
        systemPackages = with pkgs; [
          libsForQt5.qt5ct
          kdePackages.qt6ct
          adwaita-qt
          ffmpegthumbnailer
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

      systemd.services.ydotoold.enable = true;

      programs = {
        ydotool.enable = true; # clipboard prerequisite
        zsh.enable = true;
      };

      users.users."${username}" = {
        inherit shell;
        inherit (mergedConfig) extraGroups;
        isNormalUser = true;
        createHome = true;
        description = username;
      };

      security.sudo.extraConfig = ''
        Defaults env_keep += "NIXPKGS_ALLOW_UNFREE"
      '';

      security.sudo.extraRules = [
        {
          users = [ username ];
          commands = [
            {
              command = "${pkgs.colmena}/bin/colmena";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      home-manager = {
        useUserPackages = true;
        useGlobalPkgs = true;
        backupFileExtension = ".backup";
        users.${username} =
          { ... }:
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
                (import "${sources.agenix}/modules/age-home.nix")
                dmsFlake.defaultNix.homeModules.dank-material-shell
                dmsPluginRegistryFlake.defaultNix.modules.default
                zenBrowserFlake.defaultNix.homeModules.twilight
                ../homeManagerModules
              ]
              ++ mergedConfig.imports
              ++ userImports;

            options.profileCustomization = {
              mainWallpaper = lib.mkOption {
                type = lib.types.str;
                default = "${defaultImagePath}/nixos-wallpaper.png";
                description = "Image to set as main wallpaper.";
              };
              lockWallpaper = lib.mkOption {
                type = lib.types.str;
                default = "${defaultImagePath}/nixos-wallpaper.png";
                description = "Image to set as lock wallpaper.";
              };
              startup_audio = lib.mkOption {
                type = lib.types.path;
                default = "${defaultSoundPath}/startup.mp3";
                description = "Path to startup sound that hyprland plays on startup.";
              };
              notification_audio = lib.mkOption {
                type = lib.types.path;
                default = "${defaultSoundPath}/notifications.mp3";
                description = "Path to sound that hyprland plays on notifications.";
              };
            };

            config = {
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

              xdg.userDirs = {
                enable = true;
                createDirectories = true;
                setSessionVariables = false;
              };

              services = {
                udiskie.enable = true;
                gnome-keyring.enable = true;
                kdeconnect.enable = lib.mkDefault false;
              };

              dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Roboto";

              inherit (mergedConfig) customHomeManagerModules;

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
                  wlprop
                  wf-recorder
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
              };
            };
          };
      };
    };
in
{
  inherit mkUser;
}
