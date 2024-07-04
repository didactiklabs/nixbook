{
  pkgs,
  lib,
  stylix,
  nixvim,
  overrides ? {},
}: let
  defaultWallpaper = pkgs.stdenv.mkDerivation {
    name = "defaultWallpaper";
    src = ../assets/images;
    phases = ["unpackPhase" "installPhase"];
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
    ];
    customHomeManagerModules = {
    };
  };

  mergedConfig = lib.recursiveUpdate defaultConfig overrides;

  mkUser = {
    username,
    userImports ? [],
  }: {
    # Enable automount usb
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    services.devmon.enable = true;
    programs.ydotool = {
      enable = true; # clipboard prerequisite
    };
    systemd.services.ydotoold = {
      enable = true;
    };
    programs.zsh.enable = true;
    users.users."${username}" = {
      shell = pkgs.zsh;
      extraGroups = mergedConfig.extraGroups;
      isNormalUser = true;
      description = "${username}";
    };
    home-manager = {
      useUserPackages = true;
      useGlobalPkgs = true;
      backupFileExtension = "rebuild";
      users.${username} = {
        config = {
          services.udiskie.enable = true;
          dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Hack Nerd Font";
          customHomeManagerModules = mergedConfig.customHomeManagerModules;
          ## https://nix-community.github.io/home-manager/options.html#opt-services.gnome-keyring.enable
          services.gnome-keyring.enable = true;
          systemd.user.services.polkit-gnome = {
            Unit = {
              Description = "PolicyKit Authentication Agent";
              After = ["graphical-session-pre.target"];
              PartOf = ["graphical-session.target"];
            };
            Service = {
              ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
            };
            Install = {
              WantedBy = ["graphical-session.target"];
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
            pkgs.copyq
            pkgs.slurp
            pkgs.sway-contrib.grimshot
          ];
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
            (import stylix).homeManagerModules.stylix
            ../homeManagerModules/stylixConfig.nix
            (import nixvim).homeManagerModules.nixvim
            ../homeManagerModules/nixvim
            ../homeManagerModules/sway
            ../homeManagerModules/hyprland
            ../homeManagerModules/vscode
            ../homeManagerModules/alacrittyConfig.nix
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
            #../homeManagerModules/makoConfig.nix
            ../homeManagerModules/waybarConfig.nix
            ../homeManagerModules/kubeTools.nix
            ../homeManagerModules/mpvConfig.nix
            ../homeManagerModules/k9sConfig.nix
            ../homeManagerModules/scripts
            ../homeManagerModules/swayncConfig.nix
          ]
          userImports
        ];
        options.profileCustomization = {
          mainWallpaper = lib.mkOption {
            type = lib.types.str;
            default = "${defaultWallpaper}/nixos-wallpaper.png";
            description = ''
              Image to set as main wallpaper.
            '';
          };
          lockWallpaper = lib.mkOption {
            type = lib.types.str;
            default = "${defaultWallpaper}/nixos-wallpaper.png";
            description = ''
              Image to set as lock wallpaper.
            '';
          };
        };
      };
    };
  };
in {inherit mkUser;}
