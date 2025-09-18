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
      cp $src/* $out
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
      cp $src/* $out
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
    ];
    customHomeManagerModules = { };
  };

  mergedConfig = lib.recursiveUpdate defaultConfig overrides;

  mkUser =
    {
      username,
      userImports ? [ ],
    }:
    {
      # Enable automount usb
      services = {
        gvfs.enable = true;
        udisks2.enable = true;
        devmon.enable = true;
      };
      programs.ydotool = {
        enable = true; # clipboard prerequisite
      };
      systemd.services.ydotoold = {
        enable = true;
      };
      programs.zsh.enable = true;
      users.users."${username}" = {
        shell = pkgs.zsh;
        inherit (mergedConfig) extraGroups;
        isNormalUser = true;
        description = "${username}";
      };
      home-manager = {
        useUserPackages = true;
        useGlobalPkgs = true;
        backupFileExtension = "rebuild";
        users.${username} = {
          config = {
            xdg.mimeApps = {
              enable = true;
              defaultApplications = {
                "application/pdf" = "zathura.desktop"; # Set zathura as default for PDF
              };
            };
            services = {
              udiskie.enable = true;
              gnome-keyring.enable = true;
            };
            dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Hack Nerd Font";
            inherit (mergedConfig) customHomeManagerModules;
            ## https://nix-community.github.io/home-manager/options.html#opt-services.gnome-keyring.enable
            systemd.user.services.polkit-gnome = {
              Unit = {
                Description = "PolicyKit Authentication Agent";
                After = [ "graphical-session-pre.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Service = {
                ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
              };
              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };
            home.packages = [
              pkgs.pavucontrol
              pkgs.pulseaudio
              pkgs.numix-cursor-theme
              pkgs.playerctl
              pkgs.wev
              pkgs.jq
              pkgs.wlprop
              pkgs.wf-recorder
              pkgs.sway-contrib.grimshot
            ];
            programs.go = {
              enable = true;
              goPath = "go";
            };
            services.gammastep = {
              enable = true;
              dawnTime = "6:00-7:45";
              duskTime = "18:35-20:45";
              latitude = 48.9;
              longitude = 2.26;
              provider = "manual";
              tray = true;
            };
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
            programs.home-manager.enable = true;
          };
          imports = lib.concatLists [
            mergedConfig.imports
            [
              (import sources.stylix).homeModules.stylix
              ../homeManagerModules/stylixConfig.nix
              (import sources.nixvim).homeManagerModules.nixvim
              ../homeManagerModules/nixvim
              ../homeManagerModules/sway
              ../homeManagerModules/hyprland
              ../homeManagerModules/niri
              ../homeManagerModules/vscode
              ../homeManagerModules/kittyConfig.nix
              # ../homeManagerModules/ghosttyConfig.nix
              ../homeManagerModules/zshConfig.nix
              ../homeManagerModules/fontConfig.nix
              ../homeManagerModules/gitConfig.nix
              ../homeManagerModules/gtkConfig.nix
              ../homeManagerModules/sshConfig.nix
              ../homeManagerModules/starshipConfig.nix
              ../homeManagerModules/bluetoothConfig.nix
              ../homeManagerModules/rofiConfig.nix
              ../homeManagerModules/copyqConfig.nix
              ../homeManagerModules/fastfetchConfig.nix
              ../homeManagerModules/desktopApps.nix
              ../homeManagerModules/thunarConfig.nix
              ../homeManagerModules/waybarConfig.nix
              ../homeManagerModules/kubeTools.nix
              ../homeManagerModules/mpvConfig.nix
              ../homeManagerModules/k9sConfig.nix
              ../homeManagerModules/scripts
              ../homeManagerModules/swayncConfig.nix
              ../homeManagerModules/goji.nix
              ../homeManagerModules/atuinConfig.nix
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
