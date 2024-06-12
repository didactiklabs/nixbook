{
  config,
  pkgs,
  username,
  lib,
  ...
}: let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-24.05.tar.gz";
in {
  imports = [
    (import "${home-manager}/nixos")
    ./nixosModules/laptopProfile.nix
    (import ./nixosModules/networkManager.nix {inherit lib config pkgs username;})
  ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "${pkgs.sway}/bin/sway";
        user = "${username}";
      };
      default_session = initial_session;
    };
  };
  ## sway on home-manager
  security.polkit.enable = true;
  programs.sway.enable = true;
  #programs.sway.checkConfig = false;
  programs.zsh.enable = true;
  users.users."${username}".shell = pkgs.zsh;
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    users.${username} = {
      pkgs,
      config,
      ...
    }: {
      config = {
        home = {
          stateVersion = "23.11";
          username = "${username}";
          homeDirectory = "/home/${username}";
          packages = [pkgs.bat pkgs.dconf];
          sessionVariables = {
            NIXPKGS_ALLOW_UNFREE = 1;
          };
        };
        programs.home-manager.enable = true;
      };
      # Let Home Manager install and manage itself.
      imports = [
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
