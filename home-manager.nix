{
  config,
  pkgs,
  username,
  lib,
  ...
}: let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-24.05.tar.gz";
  stylix = pkgs.fetchFromGitHub {
    owner = "danth";
    repo = "stylix";
    rev = "release-24.05";
    sha256 = "sha256-A+dBkSwp8ssHKV/WyXb9uqIYrHBqHvtSedU24Lq9lqw=";
  };
in {
  imports = [
    (import "${home-manager}/nixos")
    ./nixosModules/laptopProfile.nix
    (import ./nixosModules/networkManager.nix {inherit lib config pkgs username;})
  ];
  programs.sway = {
    enable = true;
    package = pkgs.swayfx;
  };
  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "${pkgs.swayfx}/bin/sway";
        user = "${username}";
      };
      default_session = initial_session;
    };
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
        dconf.settings."org/gnome/desktop/interface".font-name = lib.mkForce "Hack Nerd Font";
        home = {
          stateVersion = "23.11";
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
        ./homeManagerModules/vscode
        ./homeManagerModules/alacrittyConfig.nix
        ./homeManagerModules/zshConfig.nix
        ./homeManagerModules/fontConfig.nix
        (import ./homeManagerModules/gitConfig.nix {inherit lib config pkgs username;})
        (import ./homeManagerModules/gtkConfig.nix {inherit lib config pkgs username;})
        ./homeManagerModules/sshConfig.nix
        ./homeManagerModules/starshipConfig.nix
        ./homeManagerModules/vimConfig.nix
        ./homeManagerModules/bluetoothConfig.nix
        ./homeManagerModules/pywalConfig.nix
        ./homeManagerModules/rofiConfig.nix
        ./homeManagerModules/copyqConfig.nix
      ];
      options.profileCustomization = {
        mainWallpaper = lib.mkOption {
          type = lib.types.str;
          default = let
            image = pkgs.fetchurl {
              url = "https://unsplash.com/photos/phIFdC6lA4E/download?ixid=M3wxMjA3fDB8MXxzZWFyY2h8M3x8bW91bnRhaW58ZW58MHx8fHwxNzE4MTE3NzQ5fDA&force=true&w=2400";
              sha256 = "sha256-8HfHaa7ZLRP9YAgkgOkTDgf27iq36iY10axnXBZXND0=";
            };
          in "${image}";
          description = ''
            Image to set as main wallpaper.
          '';
        };
        lockWallpaper = lib.mkOption {
          type = lib.types.str;
          default = let
            image = pkgs.fetchurl {
              url = "https://unsplash.com/photos/zAhAUSdRLJ8/download?ixid=M3wxMjA3fDB8MXxzZWFyY2h8MzR8fGxvY2t8ZW58MHx8fHwxNzE4MDY1NjM5fDA&force=true&w=2400";
              sha256 = "sha256-W0ecv2YENdG7mu1ORMnKUnhpvnCWFN0ZJrmcFexb+Qs=";
            };
          in "${image}";
          description = ''
            Image to set as lock wallpaper.
          '';
        };
      };
    };
  };
}
