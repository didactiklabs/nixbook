{ pkgs, ... }:
let
  sources = import ../../../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
in
{
  imports = [
    ./gitConfig.nix
    ./swayConfig.nix
    ./sunshine.nix
    ./zshConfig.nix
  ];
  profileCustomization = {
    mainWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/5g/wallhaven-5gp535.png";
          sha256 = "sha256-Ip4Kox49zJxYIGxtisI0qcWcc/MSzeeEdsxJIiHUcvg=";
        };
      in
      "${image}";
    lockWallpaper =
      let
        image = pkgs.fetchurl {
          url = "https://w.wallhaven.cc/full/5g/wallhaven-5gp535.png";
          sha256 = "sha256-Ip4Kox49zJxYIGxtisI0qcWcc/MSzeeEdsxJIiHUcvg=";
        };
      in
      "${image}";
  };
  home.packages = [
    pkgs.wineWowPackages.waylandFull
    pkgs.firefox
  ];
  customHomeManagerModules = {
    bluetooth.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = true;
    nixvimConfig.enable = true;
    # https://github.com/adi1090x/rofi
    rofiConfig.enable = true;
    fastfetchConfig.enable = true;
    waybar.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
  };
}
