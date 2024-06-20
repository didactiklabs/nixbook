{
  config,
  pkgs,
  home-manager,
  lib,
  stylix,
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
      "networkmanager"
      "wheel"
      "ydotool"
      "storage"
      "input"
    ];
    customHomeManagerModules = {
      gitConfig.enable = true;
      sshConfig.enable = true;
      starship.enable = true;
      vim.enable = true;
      fastfetchConfig.enable = true;
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
            ../homeManagerModules/vimConfig.nix
            ../homeManagerModules/bluetoothConfig.nix
            ../homeManagerModules/rofiConfig.nix
            ../homeManagerModules/copyqConfig.nix
            ../homeManagerModules/fastfetchConfig.nix
            ../homeManagerModules/desktopApps.nix
            ../homeManagerModules/thunarConfig.nix
            ../homeManagerModules/makoConfig.nix
            ../homeManagerModules/waybarConfig.nix
            ../homeManagerModules/kubeTools.nix
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
