{
  config,
  pkgs,
  username,
  lib,
  stylix,
  home-manager,
  nixOS_version,
  ...
}: let
  defaultWallpaper = pkgs.stdenv.mkDerivation {
    name = "database";
    src = ./assets/images;
    phases = ["unpackPhase" "installPhase"];
    installPhase = ''
      mkdir -p $out
      cp $src/* $out
    '';
  };
in {
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
    extraGroups = ["ydotool"];
  };
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    backupFileExtension = "rebuild";
    users.${username} = {
      pkgs,
      config,
      ...
    }: {
      config = {
        services.udiskie.enable = true;
        dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Hack Nerd Font";
        home = {
          stateVersion = "${nixOS_version}";
          username = "${username}";
          homeDirectory = "/home/${username}";
          sessionVariables = {
            YDOTOOL_SOCKET = "/run/ydotoold/socket";
            NIXPKGS_ALLOW_UNFREE = 1;
          };
        };
        programs.home-manager.enable = true;
      };
      # Let Home Manager install and manage itself.
      imports = [
        (import stylix).homeManagerModules.stylix
        ./homeManagerModules/stylixConfig.nix
        ./homeManagerModules/sway
        ./homeManagerModules/hyprland
        ./homeManagerModules/vscode
        ./homeManagerModules/alacrittyConfig.nix
        ./homeManagerModules/zshConfig.nix
        ./homeManagerModules/fontConfig.nix
        ./homeManagerModules/gitConfig.nix
        (import ./homeManagerModules/gtkConfig.nix {inherit lib config pkgs username;})
        ./homeManagerModules/sshConfig.nix
        ./homeManagerModules/starshipConfig.nix
        ./homeManagerModules/vimConfig.nix
        ./homeManagerModules/bluetoothConfig.nix
        ./homeManagerModules/rofiConfig.nix
        ./homeManagerModules/copyqConfig.nix
        ./homeManagerModules/fastfetchConfig.nix
        ./homeManagerModules/desktopApps.nix
        ./homeManagerModules/thunarConfig.nix
        ./homeManagerModules/makoConfig.nix
        ./homeManagerModules/waybarConfig.nix
        ./homeManagerModules/waybarStyle.nix
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
}
