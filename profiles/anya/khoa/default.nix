{ pkgs, ... }:
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
    cliTools.enable = true;
    devTools.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    gtkConfig.enable = true;
    securityTools.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    swayConfig.enable = true;
    systemTools.enable = true;
    nixvimConfig.enable = true;
    fastfetchConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    dmsConfig.enable = true;
  };
}
